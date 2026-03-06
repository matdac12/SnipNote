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
    case downloadIncomplete
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .whisperKitUnavailable:
            return LocalizationManager.localizedAppString("transcription.local.error.unavailable")
        case .modelNotInstalled(let model):
            return LocalizationManager.localizedAppString(
                "transcription.local.error.modelNotInstalled",
                model.displayName
            )
        case .failedToLoadModel:
            return LocalizationManager.localizedAppString("transcription.local.error.failedToLoadModel")
        case .downloadIncomplete:
            return LocalizationManager.localizedAppString("transcription.local.error.downloadIncomplete")
        case .emptyTranscript:
            return LocalizationManager.localizedAppString("transcription.local.error.emptyTranscript")
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
        let status: LocalModelStatus = resolvedModelDirectory(for: model) != nil ? .installed : .notInstalled
        if case .notInstalled = status {
            defaults.removeObject(forKey: storageKey(for: model))
        }
        return status
        #else
        return .failed(LocalTranscriptionError.whisperKitUnavailable.localizedDescription)
        #endif
    }

    func downloadModel(
        _ model: LocalTranscriptionModel,
        statusHandler: @escaping @Sendable (LocalModelStatus) -> Void
    ) async throws {
        #if canImport(WhisperKit)
        do {
            try ensureModelDirectories()
            try cleanupLegacyModelDirectory(for: model)
            try cleanupStagingDirectory(for: model)

            let whisperKit = try await WhisperKit(
                verbose: true,
                logLevel: .error,
                prewarm: false,
                load: false,
                download: false
            )

            statusHandler(.downloading(0))

            let downloadedModelFolder = try await WhisperKit.download(
                variant: model.whisperVariant,
                downloadBase: stagingDownloadBaseDirectory(),
                from: repoName
            ) { progress in
                statusHandler(.downloading(progress.fractionCompleted))
            }

            statusHandler(.verifying)

            let installedModelFolder = installedModelDirectory(for: model)

            do {
                try excludeFromBackup(localModelRootDirectory())
                try excludeFromBackup(stagingRootDirectory())
                try validateDownloadedModel(at: downloadedModelFolder)

                if fileManager.fileExists(atPath: installedModelFolder.path) {
                    try fileManager.removeItem(at: installedModelFolder)
                }

                try fileManager.moveItem(at: downloadedModelFolder, to: installedModelFolder)
                try excludeFromBackup(installedModelFolder)
                try writeInstalledMarker(for: model, in: installedModelFolder)

                defaults.set(installedModelFolder.path, forKey: storageKey(for: model))
                whisperKit.modelFolder = installedModelFolder
            } catch {
                try? cleanupInstalledArtifacts(for: model)
                throw error is LocalTranscriptionError ? error : LocalTranscriptionError.downloadIncomplete
            }
        } catch {
            try? cleanupStagingDirectory(for: model)
            throw error
        }
        #else
        throw LocalTranscriptionError.whisperKitUnavailable
        #endif
    }

    func deleteModel(_ model: LocalTranscriptionModel) throws {
        #if canImport(WhisperKit)
        loadedModels[model] = nil
        try cleanupInstalledArtifacts(for: model)
        try cleanupLegacyModelDirectory(for: model)
        defaults.removeObject(forKey: storageKey(for: model))
        #else
        throw LocalTranscriptionError.whisperKitUnavailable
        #endif
    }

    func transcribeAudio(
        from audioURL: URL,
        model: LocalTranscriptionModel,
        language: String?,
        resumeFromCompletedChunks: Int = 0,
        existingTranscript: String? = nil,
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
                currentStage: LocalizationManager.localizedAppString("transcription.local.progress.running"),
                percentComplete: 20.0,
                partialTranscript: nil
            ))

            let result = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: decodeOptions)
            let transcript = Self.sanitizeTranscript(result
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines))

            guard !transcript.isEmpty else {
                throw LocalTranscriptionError.emptyTranscript
            }

            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: LocalizationManager.localizedAppString("transcription.local.progress.complete"),
                percentComplete: 100.0,
                partialTranscript: transcript
            ))

            return transcript
        }

        let safeCompletedChunks = max(0, resumeFromCompletedChunks)
        var chunkNumber = safeCompletedChunks
        var totalChunks = 1
        var transcripts: [String] = []

        if let existingTranscript {
            let sanitizedExisting = Self.sanitizeTranscript(existingTranscript)
            if !sanitizedExisting.isEmpty {
                transcripts.append(sanitizedExisting)
            }
        }

        for try await chunk in AudioChunker.streamChunks(
            from: audioURL,
            startAtChunkIndex: safeCompletedChunks,
            progressCallback: { progress in
                let stageDescription: String
                if safeCompletedChunks > 0,
                   progress.currentStage.hasPrefix("Creating audio chunk") {
                    stageDescription = "Resuming from chunk \(progress.currentChunk) of \(progress.totalChunks)"
                } else {
                    stageDescription = progress.currentStage
                }

                progressCallback(AudioChunkerProgress(
                    currentChunk: progress.currentChunk,
                    totalChunks: progress.totalChunks,
                    currentStage: stageDescription,
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
                currentStage: LocalizationManager.localizedAppString(
                    "transcription.local.progress.chunkRunning",
                    Int64(chunkNumber),
                    Int64(totalChunks)
                ),
                percentComplete: 10.0 + (Double(chunkNumber - 1) / Double(totalChunks)) * 90.0,
                partialTranscript: nil
            ))

            let chunkURL = try writeTemporaryChunk(chunk)
            defer { try? fileManager.removeItem(at: chunkURL) }

            let result = try await whisperKit.transcribe(audioPath: chunkURL.path, decodeOptions: decodeOptions)
            let transcript = Self.sanitizeTranscript(result
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
                currentStage: LocalizationManager.localizedAppString(
                    "transcription.local.progress.chunkComplete",
                    Int64(chunkNumber)
                ),
                percentComplete: 10.0 + (Double(chunkNumber) / Double(totalChunks)) * 90.0,
                partialTranscript: transcript
            ))
        }

        let mergedTranscript = Self.sanitizeTranscript(Self.mergeChunkTranscripts(transcripts))
        guard !mergedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalTranscriptionError.emptyTranscript
        }

        progressCallback(AudioChunkerProgress(
            currentChunk: totalChunks,
            totalChunks: totalChunks,
            currentStage: LocalizationManager.localizedAppString("transcription.local.progress.combining"),
            percentComplete: 100.0,
            partialTranscript: nil
        ))

        return mergedTranscript
        #else
        throw LocalTranscriptionError.whisperKitUnavailable
        #endif
    }

    nonisolated static func mergePartialTranscript(_ existing: String, with next: String) -> String {
        let sanitizedExisting = sanitizeTranscript(existing)
        let sanitizedNext = sanitizeTranscript(next)

        guard !sanitizedExisting.isEmpty else { return sanitizedNext }
        guard !sanitizedNext.isEmpty else { return sanitizedExisting }

        let deduplicated = trimOverlapBetween(sanitizedExisting, next: sanitizedNext)
        guard !deduplicated.isEmpty else { return sanitizedExisting }

        let separator = sanitizedExisting.last?.isWhitespace == true ? "" : " "
        return sanitizeTranscript(sanitizedExisting + separator + deduplicated)
    }

    #if canImport(WhisperKit)
    private func ensureLoadedModel(_ model: LocalTranscriptionModel) async throws -> WhisperKit {
        if let loaded = loadedModels[model] {
            return loaded
        }

        guard let modelDirectory = resolvedModelDirectory(for: model) else {
            throw LocalTranscriptionError.modelNotInstalled(model)
        }

        guard fileManager.fileExists(atPath: modelDirectory.path),
              hasInstalledMarker(for: model, in: modelDirectory) else {
            defaults.removeObject(forKey: storageKey(for: model))
            throw LocalTranscriptionError.modelNotInstalled(model)
        }

        do {
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
        } catch {
            throw LocalTranscriptionError.failedToLoadModel
        }
    }

    private func ensureModelDirectories() throws {
        for directory in [localModelRootDirectory(), installedRootDirectory(), stagingRootDirectory()] {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }
            try excludeFromBackup(directory)
        }
    }

    private func localModelRootDirectory() -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("SnipNote", isDirectory: true)
            .appendingPathComponent("LocalModels", isDirectory: true)
    }

    private func installedRootDirectory() -> URL {
        localModelRootDirectory().appendingPathComponent("Installed", isDirectory: true)
    }

    private func stagingRootDirectory() -> URL {
        localModelRootDirectory().appendingPathComponent("Staging", isDirectory: true)
    }

    private func stagingDownloadBaseDirectory() -> URL {
        stagingRootDirectory()
    }

    private func installedModelDirectory(for model: LocalTranscriptionModel) -> URL {
        installedRootDirectory()
            .appendingPathComponent("openai_whisper-\(model.whisperVariant)", isDirectory: true)
    }

    private func legacyModelDirectory(for model: LocalTranscriptionModel) -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return legacyModelDirectory(forVariant: model.whisperVariant, documentsDirectory: documentsDirectory)
    }

    private func resolvedModelDirectory(for model: LocalTranscriptionModel) -> URL? {
        if let storedPath = defaults.string(forKey: storageKey(for: model)),
           fileManager.fileExists(atPath: storedPath) {
            let storedURL = URL(fileURLWithPath: storedPath, isDirectory: true)
            if hasInstalledMarker(for: model, in: storedURL) {
                return storedURL
            }
        }

        let installedDirectory = installedModelDirectory(for: model)
        if fileManager.fileExists(atPath: installedDirectory.path),
           hasInstalledMarker(for: model, in: installedDirectory) {
            return installedDirectory
        }

        return nil
    }

    private func storageKey(for model: LocalTranscriptionModel) -> String {
        "localTranscription.modelPath.\(model.rawValue)"
    }

    private func installedMarkerURL(for model: LocalTranscriptionModel, in directory: URL) -> URL {
        directory.appendingPathComponent(".snipnote-\(model.rawValue)-installed")
    }

    private func hasInstalledMarker(for model: LocalTranscriptionModel, in directory: URL) -> Bool {
        fileManager.fileExists(atPath: installedMarkerURL(for: model, in: directory).path)
    }

    private func writeInstalledMarker(for model: LocalTranscriptionModel, in directory: URL) throws {
        let markerURL = installedMarkerURL(for: model, in: directory)
        try Data("ok".utf8).write(to: markerURL, options: .atomic)
        try excludeFromBackup(directory)
    }

    private func cleanupInstalledArtifacts(for model: LocalTranscriptionModel) throws {
        let installedDirectory = installedModelDirectory(for: model)
        if fileManager.fileExists(atPath: installedDirectory.path) {
            try fileManager.removeItem(at: installedDirectory)
        }

        let stagingDirectory = stagingModelDirectory(for: model)
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
    }

    private func cleanupLegacyModelDirectory(for model: LocalTranscriptionModel) throws {
        let legacyDirectory = legacyModelDirectory(for: model)
        if fileManager.fileExists(atPath: legacyDirectory.path) {
            try fileManager.removeItem(at: legacyDirectory)
        }
    }

    private func cleanupStagingDirectory(for model: LocalTranscriptionModel) throws {
        let stagingDirectory = stagingModelDirectory(for: model)
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
    }

    private func stagingModelDirectory(for model: LocalTranscriptionModel) -> URL {
        let variantPath = "huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(model.whisperVariant)"
        return stagingRootDirectory().appendingPathComponent(variantPath, isDirectory: true)
    }

    private func legacyModelDirectory(forVariant variant: String, documentsDirectory: URL) -> URL {
        documentsDirectory
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func validateDownloadedModel(at directory: URL) throws {
        let requiredNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

        for name in requiredNames {
            let modelBundle = directory.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            guard fileManager.fileExists(atPath: modelBundle.path) else {
                throw LocalTranscriptionError.downloadIncomplete
            }

            let modelMIL = modelBundle.appendingPathComponent("model.mil")
            guard fileManager.fileExists(atPath: modelMIL.path) else {
                throw LocalTranscriptionError.downloadIncomplete
            }
        }

        let encoderWeights = directory
            .appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true)
            .appendingPathComponent("weights", isDirectory: true)
            .appendingPathComponent("weight.bin")

        guard fileManager.fileExists(atPath: encoderWeights.path) else {
            throw LocalTranscriptionError.downloadIncomplete
        }
    }

    private func writeTemporaryChunk(_ chunk: AudioChunk) throws -> URL {
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("local_chunk_\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try chunk.data.write(to: tempURL)
        return tempURL
    }
    #endif

    private static func mergeChunkTranscripts(_ transcripts: [String]) -> String {
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

    private static func sanitizeTranscript(_ transcript: String) -> String {
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

    private static func trimOverlapBetween(_ previous: String, next: String) -> String {
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
