//
//  AudioChunker.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 28/06/25.
//

import Foundation
import AVFoundation
import CoreMedia

struct AudioChunk {
    let data: Data
    let startTime: TimeInterval
    let duration: TimeInterval
    let chunkIndex: Int
    let totalChunks: Int
}

struct AudioChunkerProgress {
    let currentChunk: Int
    let totalChunks: Int
    let currentStage: String
    let percentComplete: Double
    let partialTranscript: String? // Optional field for completed chunk transcripts
}

class AudioChunker {
    static let maxChunkSizeBytes = Int(1.5 * 1024 * 1024) // 1.5MB for more frequent progress updates
    static let overlapSeconds: TimeInterval = 2.0 // 2 seconds overlap between chunks
    
    enum ChunkerError: Error {
        case fileNotFound
        case invalidAudioFile
        case audioFormatNotSupported
        case chunkingFailed
        case fileTooLarge
        
        var localizedDescription: String {
            switch self {
            case .fileNotFound:
                return "Audio file not found"
            case .invalidAudioFile:
                return "Invalid audio file format"
            case .audioFormatNotSupported:
                return "Audio format not supported"
            case .chunkingFailed:
                return "Failed to split audio file"
            case .fileTooLarge:
                return "File is too large (maximum 25MB)"
            }
        }
    }
    
    static func getFileSize(url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? UInt64 ?? 0
    }
    
    static func needsChunking(url: URL) throws -> Bool {
        let fileSize = try getFileSize(url: url)
        return fileSize > maxChunkSizeBytes
    }
    
    static func estimateChunkCount(url: URL) throws -> Int {
        let fileSize = try getFileSize(url: url)
        if fileSize <= maxChunkSizeBytes {
            return 1
        }
        
        // Rough estimation based on file size
        let estimatedChunks = Int(ceil(Double(fileSize) / Double(maxChunkSizeBytes)))
        return max(1, estimatedChunks)
    }
    
    static func validateAudioFile(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ChunkerError.fileNotFound
        }

        // Remove the 25MB limit check - we'll handle large files with chunking
        // Individual chunks will be validated to stay under 25MB

        // Test if file can be read as audio
        do {
            _ = try AVAudioFile(forReading: url)
        } catch {
            throw ChunkerError.invalidAudioFile
        }
    }

    /// Checks if sufficient disk space is available for audio chunking
    /// - Parameter required: Required disk space in bytes
    /// - Throws: ChunkerError if not enough space available
    private static func checkDiskSpace(required: UInt64) throws {
        do {
            let fileManager = FileManager.default
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())

            guard let availableSpace = systemAttributes[.systemFreeSize] as? UInt64 else {
                print("⚠️ [AudioChunker] Could not determine available disk space")
                // Proceed optimistically if we can't determine space
                return
            }

            // Add 100MB safety buffer
            let safetyBuffer: UInt64 = 100 * 1024 * 1024  // 100MB
            let totalRequired = required + safetyBuffer

            if availableSpace < totalRequired {
                let requiredMB = Double(totalRequired) / (1024 * 1024)
                let availableMB = Double(availableSpace) / (1024 * 1024)

                print("❌ [AudioChunker] Insufficient disk space: need \(String(format: "%.1f", requiredMB))MB, have \(String(format: "%.1f", availableMB))MB")
                throw ChunkerError.chunkingFailed  // Use existing error type
            }

            let availableMB = Double(availableSpace) / (1024 * 1024)
            print("✅ [AudioChunker] Disk space check passed: \(String(format: "%.1f", availableMB))MB available")
        } catch let error as ChunkerError {
            // Re-throw ChunkerError
            throw error
        } catch {
            // For other errors (e.g., FileManager errors), log and proceed optimistically
            print("⚠️ [AudioChunker] Disk space check failed: \(error.localizedDescription)")
        }
    }
    
    static func createChunks(
        from audioURL: URL,
        progressCallback: @escaping (AudioChunkerProgress) -> Void
    ) async throws -> [AudioChunk] {

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ChunkerError.fileNotFound
        }

        let fileSize = try getFileSize(url: audioURL)

        // Check disk space before starting chunking
        // Required space: (original file × 2) + (estimated chunks × 2MB per chunk)
        let estimatedChunks = try estimateChunkCount(url: audioURL)
        let requiredSpace = (fileSize * 2) + (UInt64(estimatedChunks) * 2 * 1024 * 1024)
        try checkDiskSpace(required: requiredSpace)
        
        // If file is small enough, return single chunk
        if fileSize <= maxChunkSizeBytes {
            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: "Processing audio file",
                percentComplete: 50.0,
                partialTranscript: nil
            ))
            
            // Use streaming for small files too to maintain consistency
            let audioFile = try AVAudioFile(forReading: audioURL)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate

            // Read file in chunks even for small files to prevent memory spikes
            let audioData = try readFileInChunks(audioURL: audioURL)

            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: "Audio ready for processing",
                percentComplete: 100.0,
                partialTranscript: nil
            ))

            return [AudioChunk(
                data: audioData,
                startTime: 0,
                duration: duration,
                chunkIndex: 0,
                totalChunks: 1
            )]
        }
        
        // For large files, split into chunks
        return try await createAudioChunks(
            from: audioURL,
            fileSize: fileSize,
            progressCallback: progressCallback
        )
    }
    
    private static func createAudioChunks(
        from audioURL: URL,
        fileSize: UInt64,
        progressCallback: @escaping (AudioChunkerProgress) -> Void
    ) async throws -> [AudioChunk] {
        
        // Get total duration using AVURLAsset (iOS 18+ compatible)
        let asset = AVURLAsset(url: audioURL)
        let totalDuration = try await asset.load(.duration).seconds
        
        // Calculate chunk duration based on target size
        let avgBytesPerSecond = Double(fileSize) / totalDuration
        let targetChunkDuration = Double(maxChunkSizeBytes) / avgBytesPerSecond
        
        // Ensure minimum chunk duration to avoid too many small chunks
        let chunkDuration = max(targetChunkDuration, 60.0) // At least 60 seconds per chunk
        
        var chunks: [AudioChunk] = []
        var currentTime: TimeInterval = 0
        var chunkIndex = 0
        
        // Estimate total chunks for progress tracking
        let estimatedChunks = Int(ceil(totalDuration / chunkDuration))
        
        while currentTime < totalDuration {
            // Check for cancellation before creating each chunk
            try Task.checkCancellation()

            let endTime = min(currentTime + chunkDuration, totalDuration)
            let actualChunkDuration = endTime - currentTime

            progressCallback(AudioChunkerProgress(
                currentChunk: chunkIndex + 1,
                totalChunks: estimatedChunks,
                currentStage: "Creating audio chunk \(chunkIndex + 1)",
                percentComplete: (Double(chunkIndex) / Double(estimatedChunks)) * 100.0,
                partialTranscript: nil
            ))
            
            // Create chunk with overlap (except for the last chunk)
            let chunkStartTime = currentTime
            let chunkEndTime = endTime
            let chunkWithOverlap = min(chunkEndTime + overlapSeconds, totalDuration)
            
            let chunkData = try await extractAudioSegment(
                from: audioURL,
                startTime: chunkStartTime,
                endTime: chunkWithOverlap
            )
            
            // Log chunk creation
            let chunkSizeMB = Double(chunkData.count) / (1024 * 1024)
            print("🎵 Chunk \(chunkIndex + 1) created: \(String(format: "%.1f", chunkSizeMB)) MB")
            
            let chunk = AudioChunk(
                data: chunkData,
                startTime: chunkStartTime,
                duration: actualChunkDuration,
                chunkIndex: chunkIndex,
                totalChunks: estimatedChunks
            )
            
            chunks.append(chunk)
            
            // Move to next chunk (without overlap to avoid duplication)
            currentTime = endTime
            chunkIndex += 1
        }
        
        // Update total chunks count in all chunks (in case estimation was off)
        let finalChunks = chunks.enumerated().map { index, chunk in
            AudioChunk(
                data: chunk.data,
                startTime: chunk.startTime,
                duration: chunk.duration,
                chunkIndex: chunk.chunkIndex,
                totalChunks: chunks.count
            )
        }
        
        progressCallback(AudioChunkerProgress(
            currentChunk: chunks.count,
            totalChunks: chunks.count,
            currentStage: "Audio chunks ready",
            percentComplete: 100.0,
            partialTranscript: nil
        ))
        
        return finalChunks
    }
    
    
    private static func extractAudioSegment(
        from sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> Data {
        
        // Create temporary file for the segment
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Use AVAssetExportSession for better format handling
        let asset = AVURLAsset(url: sourceURL)
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        
        guard let exportSession = exportSession else {
            throw ChunkerError.chunkingFailed
        }
        
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 1000),
            duration: CMTime(seconds: endTime - startTime, preferredTimescale: 1000)
        )
        
        // Export the segment (iOS 18+ compatible)
        do {
            try await exportSession.export(to: tempURL, as: .m4a)
        } catch {
            throw ChunkerError.chunkingFailed
        }
        
        // Read the exported file
        let audioData = try Data(contentsOf: tempURL)
        return audioData
    }

    /// Read file in chunks to prevent memory spikes
    private static func readFileInChunks(audioURL: URL) throws -> Data {
        let chunkSize = 1024 * 1024 // 1MB chunks for reading
        let fileHandle = try FileHandle(forReadingFrom: audioURL)
        defer { fileHandle.closeFile() }

        var result = Data()
        while true {
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            result.append(chunk)
        }
        return result
    }
}