//
//  LocalTranscriptionService.swift
//  SnipNote
//
//  Created by Codex on 06/03/26.
//

import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

enum LocalTranscriptionError: LocalizedError {
    case whisperKitUnavailable
    case modelNotInstalled(LocalTranscriptionModel)
    case failedToLoadModel
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .whisperKitUnavailable:
            return "Local transcription is unavailable in this build."
        case .modelNotInstalled(let model):
            return "\(model.displayName) is not downloaded. Install it in Settings > Local Transcription."
        case .failedToLoadModel:
            return "The local model could not be loaded."
        case .emptyTranscript:
            return "The local transcription returned no text."
        }
    }
}

actor LocalTranscriptionService {
    static let shared = LocalTranscriptionService()

    #if canImport(WhisperKit)
    private var loadedModels: [LocalTranscriptionModel: WhisperKit] = [:]
    #endif

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let repoName = "argmaxinc/whisperkit-coreml"

    func status(for model: LocalTranscriptionModel) -> LocalModelStatus {
        #if canImport(WhisperKit)
        return resolvedModelDirectory(for: model) != nil ? .installed : .notInstalled
        #else
        return .failed(LocalTranscriptionError.whisperKitUnavailable.localizedDescription)
        #endif
    }

    func downloadModel(
        _ model: LocalTranscriptionModel,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        #if canImport(WhisperKit)
        try ensureModelRootDirectory()

        let whisperKit = try await WhisperKit(
            verbose: true,
            logLevel: .error,
            prewarm: false,
            load: false,
            download: false
        )

        let modelFolder = try await WhisperKit.download(
            variant: model.whisperVariant,
            from: repoName
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }

        defaults.set(modelFolder.path, forKey: storageKey(for: model))
        whisperKit.modelFolder = modelFolder
        try await whisperKit.prewarmModels()
        try await whisperKit.loadModels()
        loadedModels[model] = whisperKit
        progressHandler(1.0)
        #else
        throw LocalTranscriptionError.whisperKitUnavailable
        #endif
    }

    func deleteModel(_ model: LocalTranscriptionModel) throws {
        #if canImport(WhisperKit)
        loadedModels[model] = nil
        let modelDirectory = resolvedModelDirectory(for: model) ?? expectedModelDirectory(for: model)
        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.removeItem(at: modelDirectory)
        }
        defaults.removeObject(forKey: storageKey(for: model))
        #else
        throw LocalTranscriptionError.whisperKitUnavailable
        #endif
    }

    func transcribeAudio(
        from audioURL: URL,
        model: LocalTranscriptionModel,
        language: String?,
        progressCallback: @escaping @Sendable (AudioChunkerProgress) -> Void
    ) async throws -> String {
        #if canImport(WhisperKit)
        let whisperKit = try await ensureLoadedModel(model)
        let needsChunking = try AudioChunker.needsChunking(url: audioURL)
        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: language,
            temperatureFallbackCount: 0,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true
        )

        if !needsChunking {
            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: "Running local transcription",
                percentComplete: 20.0,
                partialTranscript: nil
            ))

            let result = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: decodeOptions)
            let transcript = sanitizeTranscript(result
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines))

            guard !transcript.isEmpty else {
                throw LocalTranscriptionError.emptyTranscript
            }

            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: "Local transcription complete",
                percentComplete: 100.0,
                partialTranscript: transcript
            ))

            return transcript
        }

        var chunkNumber = 0
        var totalChunks = 1
        var transcripts: [String] = []

        for try await chunk in AudioChunker.streamChunks(
            from: audioURL,
            progressCallback: { progress in
                progressCallback(AudioChunkerProgress(
                    currentChunk: progress.currentChunk,
                    totalChunks: progress.totalChunks,
                    currentStage: progress.currentStage,
                    percentComplete: progress.percentComplete * 0.1,
                    partialTranscript: progress.partialTranscript
                ))
            }
        ) {
            try Task.checkCancellation()

            chunkNumber = chunk.chunkIndex + 1
            totalChunks = chunk.totalChunks

            progressCallback(AudioChunkerProgress(
                currentChunk: chunkNumber,
                totalChunks: totalChunks,
                currentStage: "Transcribing locally: chunk \(chunkNumber) of \(totalChunks)",
                percentComplete: 10.0 + (Double(chunkNumber - 1) / Double(totalChunks)) * 90.0,
                partialTranscript: nil
            ))

            let chunkURL = try writeTemporaryChunk(chunk)
            defer { try? fileManager.removeItem(at: chunkURL) }

            let result = try await whisperKit.transcribe(audioPath: chunkURL.path, decodeOptions: decodeOptions)
            let transcript = sanitizeTranscript(result
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines))

            guard !transcript.isEmpty else {
                throw LocalTranscriptionError.emptyTranscript
            }
            transcripts.append(transcript)

            progressCallback(AudioChunkerProgress(
                currentChunk: chunkNumber,
                totalChunks: totalChunks,
                currentStage: "Chunk \(chunkNumber) completed",
                percentComplete: 10.0 + (Double(chunkNumber) / Double(totalChunks)) * 90.0,
                partialTranscript: transcript
            ))
        }

        let mergedTranscript = sanitizeTranscript(mergeChunkTranscripts(transcripts))
        guard !mergedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalTranscriptionError.emptyTranscript
        }

        progressCallback(AudioChunkerProgress(
            currentChunk: totalChunks,
            totalChunks: totalChunks,
            currentStage: "Combining transcripts",
            percentComplete: 100.0,
            partialTranscript: nil
        ))

        return mergedTranscript
        #else
        throw LocalTranscriptionError.whisperKitUnavailable
        #endif
    }

    #if canImport(WhisperKit)
    private func ensureLoadedModel(_ model: LocalTranscriptionModel) async throws -> WhisperKit {
        if let loaded = loadedModels[model] {
            return loaded
        }

        guard let modelDirectory = resolvedModelDirectory(for: model) else {
            throw LocalTranscriptionError.modelNotInstalled(model)
        }
        guard fileManager.fileExists(atPath: modelDirectory.path) else {
            throw LocalTranscriptionError.modelNotInstalled(model)
        }

        let whisperKit = try await WhisperKit(
            verbose: true,
            logLevel: .error,
            prewarm: false,
            load: false,
            download: false
        )
        whisperKit.modelFolder = modelDirectory
        try await whisperKit.prewarmModels()
        try await whisperKit.loadModels()
        loadedModels[model] = whisperKit
        return whisperKit
    }

    private func ensureModelRootDirectory() throws {
        let modelRoot = expectedModelRootDirectory()
        if !fileManager.fileExists(atPath: modelRoot.path) {
            try fileManager.createDirectory(at: modelRoot, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func expectedModelRootDirectory() -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return documentsDirectory
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
    }

    private func expectedModelDirectory(for model: LocalTranscriptionModel) -> URL {
        expectedModelRootDirectory()
            .appendingPathComponent("openai_whisper-\(model.whisperVariant)", isDirectory: true)
    }

    private func resolvedModelDirectory(for model: LocalTranscriptionModel) -> URL? {
        if let storedPath = defaults.string(forKey: storageKey(for: model)),
           fileManager.fileExists(atPath: storedPath) {
            return URL(fileURLWithPath: storedPath, isDirectory: true)
        }

        let expectedDirectory = expectedModelDirectory(for: model)
        if fileManager.fileExists(atPath: expectedDirectory.path) {
            return expectedDirectory
        }

        return nil
    }

    private func storageKey(for model: LocalTranscriptionModel) -> String {
        "localTranscription.modelPath.\(model.rawValue)"
    }

    private func writeTemporaryChunk(_ chunk: AudioChunk) throws -> URL {
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("local_chunk_\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try chunk.data.write(to: tempURL)
        return tempURL
    }
    #endif

    private func mergeChunkTranscripts(_ transcripts: [String]) -> String {
        guard let firstNonEmptyIndex = transcripts.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return ""
        }

        var merged = transcripts[firstNonEmptyIndex].trimmingCharacters(in: .whitespacesAndNewlines)

        for transcript in transcripts.dropFirst(firstNonEmptyIndex + 1) {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let deduplicated = trimOverlapBetween(merged, next: trimmed)
            guard !deduplicated.isEmpty else { continue }

            merged += merged.last?.isWhitespace == true ? deduplicated : " \(deduplicated)"
        }

        return merged
    }

    private func sanitizeTranscript(_ transcript: String) -> String {
        let artifactPatterns = [
            "\\[BLANK_AUDIO\\]",
            "\\[MUSIC\\]",
            "\\[NOISE\\]",
            "<\\|startoftranscript\\|>",
            "<\\|endoftext\\|>"
        ]

        var cleaned = transcript
        for pattern in artifactPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimOverlapBetween(_ previous: String, next: String) -> String {
        let maxOverlapCharacters = 200
        let minOverlapCharacters = 20
        let sanitizedPrevious = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedNext = next.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedPrevious.isEmpty {
            return sanitizedNext
        }

        let previousSuffix = String(sanitizedPrevious.suffix(maxOverlapCharacters)).lowercased()
        let nextLower = sanitizedNext.lowercased()
        let maxCheck = min(previousSuffix.count, nextLower.count)
        var overlapLength = 0

        if maxCheck >= minOverlapCharacters {
            for length in stride(from: maxCheck, through: minOverlapCharacters, by: -1) {
                if nextLower.hasPrefix(previousSuffix.suffix(length)) {
                    overlapLength = length
                    break
                }
            }
        }

        guard overlapLength > 0 else {
            return sanitizedNext
        }

        let index = sanitizedNext.index(sanitizedNext.startIndex, offsetBy: overlapLength)
        return sanitizedNext[index...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
