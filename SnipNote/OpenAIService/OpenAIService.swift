//
//  OpenAIService.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import Supabase
import AVFoundation
import Security

class OpenAIService: ObservableObject {
    static let shared = OpenAIService()

    /// All OpenAI calls go through the `openai-proxy` Supabase Edge Function, which
    /// verifies the signed-in user and attaches the OpenAI key server-side.
    private let baseURL = SupabaseManager.supabaseURL
        .appendingPathComponent("functions/v1/openai-proxy")
        .absoluteString
    private let urlSession: URLSession
    private let accessTokenProvider: @Sendable () async throws -> String

    private init() {
        // Remove the credential persisted by older app versions. Never read it.
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mattia.snipnote.apikey",
            kSecAttrAccount as String: "openai_api_key"
        ] as CFDictionary)
        // Configure URLSession with custom timeout values
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120  // 2 minutes per request
        configuration.timeoutIntervalForResource = 600 // 10 minutes total
        // Supabase API gateway expects the public anon key on every request
        configuration.httpAdditionalHeaders = ["apikey": SupabaseManager.supabaseAnonKey]
        self.urlSession = URLSession(configuration: configuration)
        self.accessTokenProvider = {
            try await SupabaseManager.shared.client.auth.session.accessToken
        }
    }

    init(urlSession: URLSession, accessTokenProvider: @escaping @Sendable () async throws -> String) {
        self.urlSession = urlSession
        self.accessTokenProvider = accessTokenProvider
    }

    /// Builds an authenticated POST to the proxy. The user's Supabase access token
    /// (refreshed automatically by the SDK) authenticates the call; `task` tells the
    /// proxy which `ai_model_config` row to apply.
    private func proxyRequest(
        _ path: String,
        task: AITask?,
        contentType: String = "application/json"
    ) async throws -> URLRequest {
        let accessToken: String
        do {
            accessToken = try await accessTokenProvider()
        } catch is AuthError {
            throw OpenAIError.notAuthenticated
        }
        // Other errors (e.g. URLError while refreshing an expired token) propagate
        // unchanged so shouldRetry(error:) can retry them.

        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let task {
            request.setValue(task.rawValue, forHTTPHeaderField: "X-SnipNote-Task")
        }
        return request
    }

    /// Identifies the call to the proxy, which looks up model / reasoning effort /
    /// verbosity for it in the Supabase `ai_model_config` table (the source of truth).
    /// The defaults below are only used when that table has no row or can't be read.
    private enum AITask: String {
        case overview, summary, title, transcription
        case textSummary = "text_summary"
    }

    private static let defaultModel = "gpt-6-luna"
    private static let defaultReasoningEffort = "low"

    // MARK: - Audio Processing

    /// Extract sample rate from audio file
    private func getSampleRate(from url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw OpenAIError.apiError("No audio track found")
        }

        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            throw OpenAIError.apiError("No format description found")
        }

        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        let sampleRate = audioStreamBasicDescription?.pointee.mSampleRate ?? 0

        return sampleRate
    }

    /// Simple speed-up without re-compression (for already-optimized audio)
    private func simpleSpeedUp(audioData: Data, inputURL: URL, outputURL: URL) async throws -> Data {
        let asset = AVURLAsset(url: inputURL)
        let originalDuration = try await asset.load(.duration)
        let newDuration = CMTimeMultiplyByFloat64(originalDuration, multiplier: 1.0 / 1.5)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw OpenAIError.apiError("No audio track found")
        }

        // Create time mapping for 1.5x speed
        let timeMapping = AVMutableComposition()
        let audioCompositionTrack = timeMapping.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        try audioCompositionTrack?.insertTimeRange(
            CMTimeRange(start: .zero, duration: originalDuration),
            of: audioTrack,
            at: .zero
        )

        // Scale time to 1.5x speed
        audioCompositionTrack?.scaleTimeRange(
            CMTimeRange(start: .zero, duration: originalDuration),
            toDuration: newDuration
        )

        // Export with preset (no re-compression)
        guard let exportSession = AVAssetExportSession(asset: timeMapping, presetName: AVAssetExportPresetAppleM4A) else {
            throw OpenAIError.apiError("Failed to create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.audioTimePitchAlgorithm = .spectral

        try await exportSession.export(to: outputURL, as: .m4a)

        let resultData = try Data(contentsOf: outputURL)
        print("🚀 [OpenAI] Audio sped up 1.5x (no re-compression) - fast path for in-app recordings")
        return resultData
    }

    /// Speed-up without re-encoding (for already-compressed Voice Memos)
    /// Applies 1.5x speed with minimal quality settings to avoid file bloat
    private func speedUpAndCompress(audioData: Data, inputURL: URL, outputURL: URL) async throws -> Data {
        let asset = AVURLAsset(url: inputURL)
        let originalDuration = try await asset.load(.duration)
        let newDuration = CMTimeMultiplyByFloat64(originalDuration, multiplier: 1.0 / 1.5)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw OpenAIError.apiError("No audio track found")
        }

        // Create time mapping for 1.5x speed
        let timeMapping = AVMutableComposition()
        let audioCompositionTrack = timeMapping.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        try audioCompositionTrack?.insertTimeRange(
            CMTimeRange(start: .zero, duration: originalDuration),
            of: audioTrack,
            at: .zero
        )

        // Scale time to 1.5x speed
        audioCompositionTrack?.scaleTimeRange(
            CMTimeRange(start: .zero, duration: originalDuration),
            toDuration: newDuration
        )

        // Use Passthrough preset - keeps original codec, just applies 1.5x speed
        // No re-encoding = no file bloat, no crashes
        guard let exportSession = AVAssetExportSession(asset: timeMapping, presetName: AVAssetExportPresetPassthrough) else {
            throw OpenAIError.apiError("Failed to create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.audioTimePitchAlgorithm = .spectral

        try await exportSession.export(to: outputURL, as: .m4a)

        let resultData = try Data(contentsOf: outputURL)
        print("🚀 [OpenAI] Audio sped up 1.5x (\(resultData.count / 1024)KB) - no re-compression")
        return resultData
    }

    /// Speed up audio to 1.5x to reduce transcription costs by 33%
    /// Uses smart detection to avoid unnecessary re-compression
    public func speedUpAudio(audioData: Data) async throws -> Data {
        // Check for cancellation before processing
        try Task.checkCancellation()

        // Create temporary input file
        let tempInputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("input_\(UUID().uuidString).m4a")
        let tempOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("output_\(UUID().uuidString).m4a")

        defer {
            // Clean up temp files
            try? FileManager.default.removeItem(at: tempInputURL)
            try? FileManager.default.removeItem(at: tempOutputURL)
        }

        // Write audio data to temp file
        try audioData.write(to: tempInputURL)

        do {
            // Detect audio sample rate
            let sampleRate = try await getSampleRate(from: tempInputURL)
            print("🎵 [OpenAI] Detected audio sample rate: \(Int(sampleRate)) Hz")

            // Choose processing path based on sample rate
            if sampleRate <= 16000 {
                // Low sample rate audio - skip processing
                print("📱 [OpenAI] Low sample rate audio (\(Int(sampleRate))Hz) - using original audio")
                return audioData
            } else {
                // High quality audio - apply speed-up only (using AppleM4A preset)
                return try await simpleSpeedUp(audioData: audioData, inputURL: tempInputURL, outputURL: tempOutputURL)
            }
        } catch {
            // Fallback to original audio if speed-up fails
            print("⚠️ [OpenAI] Audio speed-up failed, using original: \(error.localizedDescription)")
            return audioData
        }
    }

    /// Optimize audio file for server upload by applying 1.5x speed-up and compression
    /// Returns a URL to the optimized audio file in the temp directory
    /// The caller is responsible for cleaning up the returned temp file after upload
    public func optimizeAudioForUpload(audioURL: URL) async throws -> URL {
        print("⚡ Optimizing audio for server upload (1.5x speed-up + compression)...")

        // Read the audio file
        let audioData = try Data(contentsOf: audioURL)
        let originalSize = audioData.count

        // Apply speed-up and compression
        let optimizedData = try await speedUpAudio(audioData: audioData)
        let optimizedSize = optimizedData.count

        // Create optimized file in temp directory
        let tempDirectory = FileManager.default.temporaryDirectory
        let optimizedFileName = "optimized_\(UUID().uuidString).m4a"
        let optimizedURL = tempDirectory.appendingPathComponent(optimizedFileName)

        // Write optimized audio to temp file
        try optimizedData.write(to: optimizedURL)

        let sizeSavings = ((1.0 - Double(optimizedSize) / Double(originalSize)) * 100)
        print("✅ Audio optimized: \(originalSize / 1024)KB → \(optimizedSize / 1024)KB (\(Int(sizeSavings))% smaller)")
        print("📁 Optimized file: \(optimizedURL.lastPathComponent)")

        return optimizedURL
    }

    func transcribeAudio(audioData: Data, language: String? = nil, provider: CloudTranscriptionProvider = .openai) async throws -> String {
        // Speed up audio by 1.5x to reduce costs by 33%
        let processedAudioData = try await speedUpAudio(audioData: audioData)

        let boundary = UUID().uuidString
        let baseRequest = try await proxyRequest(
            "/audio/transcriptions",
            task: .transcription
        )
        let request = CloudTranscriptionRequest.make(
            baseRequest: baseRequest,
            audioData: processedAudioData,
            language: language,
            provider: provider,
            boundary: boundary
        )

        let (data, urlResponse) = try await urlSession.data(for: request)

        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            if let apiError = try? JSONDecoder().decode(OpenAIAPIErrorResponse.self, from: data) {
                // Keep the status code: shouldRetry(error:) decides on it
                throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(apiError.error.message)")
            }
            let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(rawBody)")
        }

        do {
            let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return response.text
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("Unexpected transcription response: \(rawBody)")
        }
    }

    func transcribeAudioFromURL(
        audioURL: URL,
        progressCallback: @escaping (AudioChunkerProgress) -> Void,
        meetingName: String = "",
        meetingId: UUID? = nil,
        language: String? = nil,
        provider: CloudTranscriptionProvider = .openai
    ) async throws -> String {
        // Validate audio file first
        try AudioChunker.validateAudioFile(url: audioURL)

        // Get file size for disk space calculation
        let fileSize = try AudioChunker.getFileSize(url: audioURL)

        // Check disk space before starting transcription
        // Required space: (original file × 2) + (estimated chunks × 2MB per chunk)
        let estimatedChunks = try AudioChunker.estimateChunkCount(url: audioURL)
        let requiredSpace = (fileSize * 2) + (UInt64(estimatedChunks) * 2 * 1024 * 1024)
        try checkDiskSpace(required: requiredSpace)

        // Check if file needs chunking
        let needsChunking = try AudioChunker.needsChunking(url: audioURL)

        if !needsChunking {
            // For small files, use direct processing
            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: "Processing audio file",
                percentComplete: 50.0,
                partialTranscript: nil
            ))

            let audioFile = try AVAudioFile(forReading: audioURL)
            let durationSeconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            let audioData = try Data(contentsOf: audioURL)
            let transcript = try await transcribeAudioWithRetry(audioData: audioData, duration: durationSeconds, language: language, provider: provider)

            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: "Transcription complete",
                percentComplete: 100.0,
                partialTranscript: transcript
            ))

            return transcript
        } else {
            // For large files, use chunked processing
            return try await transcribeAudioInChunks(
                audioURL: audioURL,
                progressCallback: progressCallback,
                meetingName: meetingName,
                meetingId: meetingId,
                language: language,
                provider: provider
            )
        }
    }

    private func transcribeAudioInChunks(
        audioURL: URL,
        progressCallback: @escaping (AudioChunkerProgress) -> Void,
        meetingName: String = "",
        meetingId: UUID? = nil,
        language: String? = nil,
        provider: CloudTranscriptionProvider = .openai
    ) async throws -> String {

        // Check for cancellation before starting
        try Task.checkCancellation()

        // Stream chunks one at a time for memory efficiency
        var transcripts: [String] = []
        var chunkNumber = 0
        var totalChunks = 1 // Will be updated as we receive chunks
        var halfwayNotificationSent = false

        for try await chunk in AudioChunker.streamChunks(
            from: audioURL,
            progressCallback: { chunkProgress in
                // Update progress for chunking phase (0-10%)
                let adjustedProgress = AudioChunkerProgress(
                    currentChunk: chunkProgress.currentChunk,
                    totalChunks: chunkProgress.totalChunks,
                    currentStage: chunkProgress.currentStage,
                    percentComplete: chunkProgress.percentComplete * 0.1,
                    partialTranscript: chunkProgress.partialTranscript
                )
                progressCallback(adjustedProgress)
            }
        ) {
            // Check for cancellation before processing each chunk
            try Task.checkCancellation()

            chunkNumber = chunk.chunkIndex + 1
            totalChunks = chunk.totalChunks

            progressCallback(AudioChunkerProgress(
                currentChunk: chunkNumber,
                totalChunks: totalChunks,
                currentStage: "Transcribing chunk \(chunkNumber) of \(totalChunks)",
                percentComplete: 10.0 + (Double(chunkNumber - 1) / Double(totalChunks)) * 90.0,
                partialTranscript: nil
            ))

            print("🎵 Transcribing chunk \(chunkNumber)/\(totalChunks)")

            do {
                // Use new retry logic with exponential backoff
                let chunkTranscript = try await transcribeChunkWithRetry(chunk: chunk, language: language, provider: provider)
                transcripts.append(chunkTranscript)

                // Calculate progress percentage
                let progressPercent = 10.0 + (Double(chunkNumber) / Double(totalChunks)) * 90.0

                // Send 50% progress notification
                if progressPercent >= 50.0 && !halfwayNotificationSent && !meetingName.isEmpty, let meetingId = meetingId {
                    halfwayNotificationSent = true
                    await NotificationService.shared.sendProgressNotification(
                        meetingId: meetingId,
                        meetingName: meetingName,
                        progress: 50
                    )
                }

                // Report progress with the completed chunk transcript
                progressCallback(AudioChunkerProgress(
                    currentChunk: chunkNumber,
                    totalChunks: totalChunks,
                    currentStage: "Chunk \(chunkNumber) completed",
                    percentComplete: progressPercent,
                    partialTranscript: chunkTranscript
                ))

            } catch {
                // FIXED: Don't continue with partial transcripts - fail completely if any chunk fails
                print("🎵 Chunk \(chunkNumber) failed after all retries: \(error)")
                throw OpenAIError.transcriptionFailed
            }
        }

        progressCallback(AudioChunkerProgress(
            currentChunk: totalChunks,
            totalChunks: totalChunks,
            currentStage: "Combining transcripts",
            percentComplete: 100.0,
            partialTranscript: nil
        ))

        // Send 100% completion notification for transcription phase
        if !meetingName.isEmpty, let meetingId = meetingId {
            await NotificationService.shared.sendProgressNotification(
                meetingId: meetingId,
                meetingName: meetingName,
                progress: 100
            )
        }

        // Combine all transcripts (all chunks succeeded if we reach here)
        let fullTranscript = mergeChunkTranscripts(transcripts)

        // Validate that we got a meaningful transcript
        let trimmedTranscript = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTranscript.isEmpty {
            throw OpenAIError.transcriptionFailed
        }

        return fullTranscript
    }

    func summarizeText(_ text: String) async throws -> String {
        var request = try await proxyRequest("/responses", task: .textSummary)

        let prompt = """
        Please analyze the following transcript and provide:
        1. Key points and insights
        2. Actionable items or tasks mentioned
        3. Important decisions or conclusions

        Keep the summary concise but comprehensive. Format as bullet points.

        Transcript: \(text)
        """

        let requestBody = ChatRequest(
            model: Self.defaultModel,
            input: [
                ChatMessage(role: "system", content: "You are a helpful assistant that summarizes spoken notes into actionable insights."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: nil,
            reasoning: ReasoningConfig(effort: Self.defaultReasoningEffort),
            text: nil
        )

        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData

        let (data, urlResponse) = try await urlSession.data(for: request)

        // Check HTTP status code
        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Debug: Print the response to see what we're getting
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 OpenAI Response: \(responseString)")
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)

        return response.outputText
    }

    func generateTitle(_ text: String) async throws -> String {
        var request = try await proxyRequest("/responses", task: .title)

        let prompt = """
        Identify the language spoken and always respond in the same language as the input transcript.
        Generate an appropriate title for this note transcript in exactly 3-4 words. The title should be concise, descriptive, and capture the main topic or purpose.

        Examples:
        - "Meeting Notes Summary"
        - "Weekly Project Update"
        - "Shopping List Items"
        - "Travel Planning Ideas"

        Transcript: \(text)
        """

        let requestBody = ChatRequest(
            model: Self.defaultModel,
            input: [
                ChatMessage(role: "system", content: "You generate concise, descriptive titles for notes. Always respond with exactly 2-3 words, properly capitalized, in the same language as the input transcript."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: nil,
            reasoning: ReasoningConfig(effort: Self.defaultReasoningEffort),
            text: nil
        )

        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData

        let (data, urlResponse) = try await urlSession.data(for: request)

        // Check HTTP status code
        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Debug: Print the response to see what we're getting
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 OpenAI Response: \(responseString)")
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)

        return response.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateMeetingOverview(_ text: String, languageContext: AnalysisLanguageContext) async throws -> String {
        var request = try await proxyRequest("/responses", task: .overview)

        let prompt = MeetingAnalysisPrompts.overviewPrompt(transcript: text, languageContext: languageContext)

        let requestBody = ChatRequest(
            model: Self.defaultModel,
            input: [
                ChatMessage(role: "system", content: MeetingAnalysisPrompts.overviewInstructions),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: nil,
            reasoning: ReasoningConfig(effort: Self.defaultReasoningEffort),
            text: TextConfig(verbosity: "low")
        )

        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData

        let (data, urlResponse) = try await urlSession.data(for: request)

        // Check HTTP status code
        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Debug: Print the response to see what we're getting
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 OpenAI Response: \(responseString)")
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)

        return response.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func summarizeMeeting(_ text: String, languageContext: AnalysisLanguageContext) async throws -> String {
        var request = try await proxyRequest("/responses", task: .summary)

        let prompt = MeetingAnalysisPrompts.summaryPrompt(transcript: text, languageContext: languageContext)

        let requestBody = ChatRequest(
            model: Self.defaultModel,
            input: [
                ChatMessage(role: "system", content: MeetingAnalysisPrompts.summaryInstructions),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: nil,
            reasoning: ReasoningConfig(effort: Self.defaultReasoningEffort),
            text: TextConfig(verbosity: "low")
        )

        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData

        let (data, urlResponse) = try await urlSession.data(for: request)

        // Check HTTP status code
        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Debug: Print the response to see what we're getting
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 OpenAI Response: \(responseString)")
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)

        return response.outputText
    }

    // MARK: - Retry Helpers

    private func shouldRetry(error: Error) -> Bool {
        // NEVER retry on cancellation
        if error is CancellationError {
            return false
        }

        // Check for specific NSURLError cases that should retry
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost,      // -1005
                 .notConnectedToInternet,     // -1009
                 .timedOut,                   // -1001
                 .cannotConnectToHost:        // -1004
                return true
            default:
                return false
            }
        }

        // Check for HTTP status codes in API errors
        if case OpenAIError.apiError(let message) = error {
            // Retry on temporary server errors
            if message.contains("408") ||  // Request Timeout
               message.contains("429") ||  // Too Many Requests
               message.contains("500") ||  // Internal Server Error
               message.contains("502") ||  // Bad Gateway
               message.contains("503") ||  // Service Unavailable
               message.contains("504") {   // Gateway Timeout
                return true
            }

            // Do NOT retry on client errors (fail fast)
            if message.contains("400") ||  // Bad Request
               message.contains("401") ||  // Unauthorized
               message.contains("403") ||  // Forbidden
               message.contains("413") {   // Payload Too Large
                return false
            }
        }

        // Do NOT retry on audio processing failures (fail fast)
        if case OpenAIError.audioProcessingFailed = error {
            return false
        }

        return false
    }

    // MARK: - Disk Space Management

    /// Checks if sufficient disk space is available for audio processing
    /// - Parameter required: Required disk space in bytes
    /// - Throws: OpenAIError.insufficientDiskSpace if not enough space available
    private func checkDiskSpace(required: UInt64) throws {
        do {
            let fileManager = FileManager.default
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())

            guard let availableSpace = systemAttributes[.systemFreeSize] as? UInt64 else {
                print("⚠️ [OpenAI] Could not determine available disk space")
                // Proceed optimistically if we can't determine space
                return
            }

            // Add 100MB safety buffer
            let safetyBuffer: UInt64 = 100 * 1024 * 1024  // 100MB
            let totalRequired = required + safetyBuffer

            if availableSpace < totalRequired {
                let requiredMB = Double(totalRequired) / (1024 * 1024)
                let availableMB = Double(availableSpace) / (1024 * 1024)

                print("❌ [OpenAI] Insufficient disk space: need \(String(format: "%.1f", requiredMB))MB, have \(String(format: "%.1f", availableMB))MB")
                throw OpenAIError.insufficientDiskSpace(required: totalRequired, available: availableSpace)
            }

            let availableMB = Double(availableSpace) / (1024 * 1024)
            print("✅ [OpenAI] Disk space check passed: \(String(format: "%.1f", availableMB))MB available")
        } catch let error as OpenAIError {
            // Re-throw OpenAIError (including insufficientDiskSpace)
            throw error
        } catch {
            // For other errors (e.g., FileManager errors), log and proceed optimistically
            print("⚠️ [OpenAI] Disk space check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Timeout Protection

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw OpenAIError.apiError("Operation timed out after \(seconds) seconds")
            }

            guard let result = try await group.next() else {
                throw OpenAIError.apiError("Task group completed without result")
            }

            group.cancelAll()
            return result
        }
    }

    private func timeoutForAudio(duration: TimeInterval?, minimum: TimeInterval = 120, maximum: TimeInterval = 360) -> TimeInterval {
        guard let duration, duration > 0 else { return minimum }
        let scaled = duration * 2.5
        return min(maximum, max(minimum, scaled))
    }

    // MARK: - Enhanced Retry Logic for Transcription

    func transcribeAudioWithRetry(audioData: Data, duration: TimeInterval? = nil, language: String? = nil, maxRetries: Int = 3, provider: CloudTranscriptionProvider = .openai) async throws -> String {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                print("🎵 Transcribing audio data (attempt \(attempt + 1))" + (language != nil ? " [language: \(language!)]" : ""))

                // Add timeout protection to each transcription attempt (duration-aware)
                let timeout = timeoutForAudio(duration: duration)
                let transcript = try await withTimeout(seconds: timeout) {
                    try await self.transcribeAudio(audioData: audioData, language: language, provider: provider)
                }

                print("🎵 Audio transcribed successfully (timeout window: \(Int(timeout))s)")
                return transcript

            } catch {
                lastError = error
                print("🎵 Audio transcription failed on attempt \(attempt + 1): \(error)")

                // Don't retry if it's not a retryable error
                if !shouldRetry(error: error) {
                    throw error
                }

                // Don't delay after the last attempt
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s exponential backoff
                    print("🎵 Retrying audio transcription in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // If we get here, all retries failed
        throw lastError ?? OpenAIError.transcriptionFailed
    }

    private func transcribeChunkWithRetry(chunk: AudioChunk, language: String? = nil, maxRetries: Int = 3, provider: CloudTranscriptionProvider = .openai) async throws -> String {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                print("🎵 Transcribing chunk \(chunk.chunkIndex + 1) (attempt \(attempt + 1))" + (language != nil ? " [language: \(language!)]" : ""))

                // Add timeout protection to each chunk based on duration
                let timeout = timeoutForAudio(duration: chunk.duration)
                let transcript = try await withTimeout(seconds: timeout) {
                    try await self.transcribeAudio(audioData: chunk.data, language: language, provider: provider)
                }

                print("🎵 Chunk \(chunk.chunkIndex + 1) transcribed successfully (timeout window: \(Int(timeout))s)")
                return transcript

            } catch {
                lastError = error
                print("🎵 Chunk \(chunk.chunkIndex + 1) failed on attempt \(attempt + 1): \(error)")

                // Don't retry if it's not a retryable error
                if !shouldRetry(error: error) {
                    throw error
                }

                // Don't delay after the last attempt
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s exponential backoff
                    print("🎵 Retrying chunk \(chunk.chunkIndex + 1) in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // If we get here, all retries failed
        throw lastError ?? OpenAIError.transcriptionFailed
    }
}

// MARK: - Transcript Overlap Helpers

extension OpenAIService {
    private func mergeChunkTranscripts(_ transcripts: [String]) -> String {
        // Find first non-empty chunk to start with
        guard let firstNonEmptyIndex = transcripts.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return ""
        }

        var merged = transcripts[firstNonEmptyIndex].trimmingCharacters(in: .whitespacesAndNewlines)

        // Log if we skipped any empty chunks
        if firstNonEmptyIndex > 0 {
            for i in 0..<firstNonEmptyIndex {
                print("⚠️ Chunk \(i + 1) returned empty transcript, skipping")
            }
        }

        // Process all remaining chunks (including those before firstNonEmptyIndex if any were skipped)
        for (index, transcript) in transcripts.enumerated() where index > firstNonEmptyIndex {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                print("⚠️ Chunk \(index + 1) returned empty transcript, skipping")
                continue
            }

            let trimmedNext = trimOverlapBetween(merged, next: transcript)
            guard !trimmedNext.isEmpty else { continue }

            if merged.last?.isWhitespace ?? false {
                merged += trimmedNext
            } else {
                merged += " " + trimmedNext
            }
        }

        return merged
    }

    // MARK: - Test Helper
    #if DEBUG
    internal func testMergeChunkTranscripts(_ transcripts: [String]) -> String {
        return mergeChunkTranscripts(transcripts)
    }
    #endif

    private func trimOverlapBetween(_ previous: String, next: String) -> String {
        let maxOverlapCharacters = 200
        let minOverlapCharacters = 20

        let sanitizedPrevious = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedNext = next.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedPrevious.isEmpty { return sanitizedNext }

        let previousSuffix = String(sanitizedPrevious.suffix(maxOverlapCharacters)).lowercased()
        let nextLower = sanitizedNext.lowercased()

        let maxCheck = min(previousSuffix.count, nextLower.count)
        var overlapLength = 0

        if maxCheck >= minOverlapCharacters {
            for length in stride(from: maxCheck, through: minOverlapCharacters, by: -1) {
                let candidate = previousSuffix.suffix(length)
                if nextLower.hasPrefix(candidate) {
                    overlapLength = length
                    break
                }
            }
        }

        if overlapLength > 0 {
            let index = sanitizedNext.index(sanitizedNext.startIndex, offsetBy: overlapLength)
            let remainder = sanitizedNext[index...]
            return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sanitizedNext
    }
}
