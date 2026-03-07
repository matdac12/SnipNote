//
//  LocalAudioPreprocessor.swift
//  SnipNote
//
//  Created by Codex on 06/03/26.
//

import Foundation
import CryptoKit

#if canImport(WhisperKit)
import WhisperKit
#endif

struct LocalSpeechChunk: Codable, Sendable, Equatable {
    let startSample: Int
    let endSample: Int

    var sampleCount: Int {
        max(0, endSample - startSample)
    }
}

struct LocalSpeechChunkPlan: Codable, Sendable, Equatable {
    let sourceAudioPath: String
    let fingerprint: String
    let sampleRate: Int
    let chunks: [LocalSpeechChunk]

    var totalChunks: Int {
        chunks.count
    }
}

struct PreparedLocalAudio: Sendable {
    let audioSamples: [Float]
    let plan: LocalSpeechChunkPlan
    let diagnostics: LocalSpeechChunkDiagnostics
}

struct LocalSpeechChunkDiagnostics: Sendable {
    let totalDurationSeconds: Double
    let detectedSpeechSpanCount: Int
    let mergedSpeechSpanCount: Int
    let finalChunkCount: Int
    let speechDurationSeconds: Double

    var speechCoverage: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return speechDurationSeconds / totalDurationSeconds
    }
}

actor LocalAudioPreprocessor {
    static let shared = LocalAudioPreprocessor()

    #if canImport(WhisperKit)
    private let sampleRate = WhisperKit.sampleRate
    private let frameLengthSeconds: Float = 0.1
    private let frameOverlapSeconds: Float = 0.03
    private let energyThreshold: Float = 0.008
    private let mergeGapSeconds: Double = 0.8
    private let leadingPaddingSeconds: Double = 0.2
    private let trailingPaddingSeconds: Double = 0.35
    private let minimumChunkDurationSeconds: Double = 0.35

    func prepareAudio(
        from audioURL: URL,
        maxChunkLength: Int,
        cachedPlanJSON: String? = nil,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> PreparedLocalAudio {
        progressHandler?(LocalizationManager.localizedAppString("transcription.local.progress.loadingAudio"))
        let audioSamples = try await Task.detached(priority: .userInitiated) {
            try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path, channelMode: .sumChannels(nil))
        }.value
        let totalDurationSeconds = Double(audioSamples.count) / Double(sampleRate)

        let fingerprint = try Self.makeFingerprint(
            for: audioURL,
            sampleRate: sampleRate,
            energyThreshold: energyThreshold,
            mergeGapSeconds: mergeGapSeconds,
            leadingPaddingSeconds: leadingPaddingSeconds,
            trailingPaddingSeconds: trailingPaddingSeconds,
            minimumChunkDurationSeconds: minimumChunkDurationSeconds
        )

        if let cachedPlanJSON,
           let cachedPlan = Self.decodePlan(from: cachedPlanJSON),
           cachedPlan.sourceAudioPath == audioURL.path,
           cachedPlan.fingerprint == fingerprint,
           !cachedPlan.chunks.isEmpty,
           cachedPlan.sampleRate == sampleRate {
            let speechDurationSeconds = Double(cachedPlan.chunks.reduce(0) { $0 + $1.sampleCount }) / Double(sampleRate)
            let diagnostics = LocalSpeechChunkDiagnostics(
                totalDurationSeconds: totalDurationSeconds,
                detectedSpeechSpanCount: cachedPlan.chunks.count,
                mergedSpeechSpanCount: cachedPlan.chunks.count,
                finalChunkCount: cachedPlan.chunks.count,
                speechDurationSeconds: speechDurationSeconds
            )
            return PreparedLocalAudio(audioSamples: audioSamples, plan: cachedPlan, diagnostics: diagnostics)
        }

        progressHandler?(LocalizationManager.localizedAppString("transcription.local.progress.detectingSpeech"))
        let detector = EnergyVAD(
            sampleRate: sampleRate,
            frameLength: frameLengthSeconds,
            frameOverlap: frameOverlapSeconds,
            energyThreshold: energyThreshold
        )

        let activeRanges = detector.calculateActiveChunks(in: audioSamples)
        let mergedRanges = Self.mergeActiveRanges(
            activeRanges,
            totalSampleCount: audioSamples.count,
            sampleRate: sampleRate,
            mergeGapSeconds: mergeGapSeconds,
            leadingPaddingSeconds: leadingPaddingSeconds,
            trailingPaddingSeconds: trailingPaddingSeconds,
            minimumChunkDurationSeconds: minimumChunkDurationSeconds
        )

        guard !mergedRanges.isEmpty else {
            throw LocalTranscriptionError.emptyTranscript
        }

        progressHandler?(LocalizationManager.localizedAppString("transcription.local.progress.preparingChunks"))
        let chunks = Self.splitMergedRanges(
            mergedRanges,
            maxChunkLength: maxChunkLength
        )
        .filter { $0.sampleCount > 0 }

        guard !chunks.isEmpty else {
            throw LocalTranscriptionError.emptyTranscript
        }

        let plan = LocalSpeechChunkPlan(
            sourceAudioPath: audioURL.path,
            fingerprint: fingerprint,
            sampleRate: sampleRate,
            chunks: chunks
        )

        let speechDurationSeconds = Double(mergedRanges.reduce(0) { $0 + $1.sampleCount }) / Double(sampleRate)
        let diagnostics = LocalSpeechChunkDiagnostics(
            totalDurationSeconds: totalDurationSeconds,
            detectedSpeechSpanCount: activeRanges.count,
            mergedSpeechSpanCount: mergedRanges.count,
            finalChunkCount: chunks.count,
            speechDurationSeconds: speechDurationSeconds
        )

        return PreparedLocalAudio(audioSamples: audioSamples, plan: plan, diagnostics: diagnostics)
    }
    #endif

    nonisolated static func encodePlan(_ plan: LocalSpeechChunkPlan) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(plan) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func decodePlan(from json: String) -> LocalSpeechChunkPlan? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LocalSpeechChunkPlan.self, from: data)
    }

    nonisolated static func mergeActiveRanges(
        _ ranges: [(startIndex: Int, endIndex: Int)],
        totalSampleCount: Int,
        sampleRate: Int,
        mergeGapSeconds: Double,
        leadingPaddingSeconds: Double,
        trailingPaddingSeconds: Double,
        minimumChunkDurationSeconds: Double
    ) -> [LocalSpeechChunk] {
        guard !ranges.isEmpty, totalSampleCount > 0, sampleRate > 0 else { return [] }

        let mergeGapSamples = max(0, Int((mergeGapSeconds * Double(sampleRate)).rounded()))
        let leadingPaddingSamples = max(0, Int((leadingPaddingSeconds * Double(sampleRate)).rounded()))
        let trailingPaddingSamples = max(0, Int((trailingPaddingSeconds * Double(sampleRate)).rounded()))
        let minimumChunkSamples = max(1, Int((minimumChunkDurationSeconds * Double(sampleRate)).rounded()))

        var merged: [LocalSpeechChunk] = []

        for range in ranges {
            let startSample = max(0, range.startIndex - leadingPaddingSamples)
            let endSample = min(totalSampleCount, range.endIndex + trailingPaddingSamples)
            guard endSample > startSample else { continue }

            let nextChunk = LocalSpeechChunk(startSample: startSample, endSample: endSample)

            if let previous = merged.last,
               nextChunk.startSample - previous.endSample <= mergeGapSamples {
                merged[merged.count - 1] = LocalSpeechChunk(
                    startSample: previous.startSample,
                    endSample: max(previous.endSample, nextChunk.endSample)
                )
            } else {
                merged.append(nextChunk)
            }
        }

        return merged.filter { $0.sampleCount >= minimumChunkSamples }
    }

    nonisolated static func splitMergedRanges(
        _ ranges: [LocalSpeechChunk],
        maxChunkLength: Int
    ) -> [LocalSpeechChunk] {
        guard maxChunkLength > 0 else { return ranges }

        var chunks: [LocalSpeechChunk] = []

        for range in ranges {
            var startSample = range.startSample
            while startSample < range.endSample {
                let endSample = min(startSample + maxChunkLength, range.endSample)
                guard endSample > startSample else { break }
                chunks.append(LocalSpeechChunk(startSample: startSample, endSample: endSample))
                startSample = endSample
            }
        }

        return chunks
    }

    #if canImport(WhisperKit)
    private nonisolated static func makeFingerprint(
        for audioURL: URL,
        sampleRate: Int,
        energyThreshold: Float,
        mergeGapSeconds: Double,
        leadingPaddingSeconds: Double,
        trailingPaddingSeconds: Double,
        minimumChunkDurationSeconds: Double
    ) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = attributes[.size] as? NSNumber
        let modifiedAt = attributes[.modificationDate] as? Date
        let source = [
            audioURL.path,
            String(fileSize?.int64Value ?? 0),
            String(modifiedAt?.timeIntervalSince1970 ?? 0),
            String(sampleRate),
            String(energyThreshold),
            String(mergeGapSeconds),
            String(leadingPaddingSeconds),
            String(trailingPaddingSeconds),
            String(minimumChunkDurationSeconds)
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    #endif
}
