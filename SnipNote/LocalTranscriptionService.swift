//
//  LocalTranscriptionService.swift
//  SnipNote
//
//  Created by Codex on 06/03/26.
//

import Foundation
import SwiftData

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
        meetingId: UUID? = nil,
        resumeFromCompletedChunks: Int = 0,
        existingTranscript: String? = nil,
        progressCallback: @escaping @Sendable (AudioChunkerProgress) -> Void
    ) async throws -> String {
        #if canImport(WhisperKit)
        let transcriptionStart = Date()
        let whisperKit = try await ensureLoadedModel(model)
        let decodeOptions = Self.makeLocalDecodeOptions(model: model, language: language)
        let maxChunkLength = whisperKit.featureExtractor.windowSamples ?? 480_000
        let cachedPlanJSON: String? = if let meetingId {
            await readStoredSpeechPlan(for: meetingId)
        } else {
            nil
        }

        progressCallback(AudioChunkerProgress(
            currentChunk: 0,
            totalChunks: 0,
            currentStage: LocalizationManager.localizedAppString("transcription.local.progress.loadingAudio"),
            percentComplete: 5.0,
            partialTranscript: nil
        ))

        let preparedAudio = try await LocalAudioPreprocessor.shared.prepareAudio(
            from: audioURL,
            maxChunkLength: maxChunkLength,
            cachedPlanJSON: cachedPlanJSON,
            progressHandler: { stage in
                let percent: Double
                switch stage {
                case LocalizationManager.localizedAppString("transcription.local.progress.loadingAudio"):
                    percent = 5.0
                case LocalizationManager.localizedAppString("transcription.local.progress.detectingSpeech"):
                    percent = 7.0
                default:
                    percent = 9.0
                }

                progressCallback(AudioChunkerProgress(
                    currentChunk: 0,
                    totalChunks: 0,
                    currentStage: stage,
                    percentComplete: percent,
                    partialTranscript: nil
                ))
            }
        )

        if let meetingId {
            await persistSpeechPlan(preparedAudio.plan, for: meetingId)
        }

        Self.logPreprocessingDiagnostics(preparedAudio.diagnostics, model: model, audioURL: audioURL)
        Self.logDecodeDiagnostics(decodeOptions, model: model)

        let totalChunks = preparedAudio.plan.totalChunks
        let safeCompletedChunks = min(max(0, resumeFromCompletedChunks), totalChunks)
        var chunkNumber = safeCompletedChunks
        var transcripts: [String] = []
        var completedTranscriptChunks = 0
        var skippedEmptyChunks = 0

        if let existingTranscript {
            let sanitizedExisting = Self.sanitizeTranscript(existingTranscript)
            if !sanitizedExisting.isEmpty {
                transcripts.append(sanitizedExisting)
            }
        }

        if safeCompletedChunks > 0, safeCompletedChunks < totalChunks, totalChunks > 0 {
            try Task.checkCancellation()
            progressCallback(AudioChunkerProgress(
                currentChunk: safeCompletedChunks + 1,
                totalChunks: totalChunks,
                currentStage: "Resuming from chunk \(safeCompletedChunks + 1) of \(totalChunks)",
                percentComplete: 10.0 + (Double(safeCompletedChunks) / Double(totalChunks)) * 90.0,
                partialTranscript: nil
            ))
        }

        for index in safeCompletedChunks..<totalChunks {
            try Task.checkCancellation()
            let chunk = preparedAudio.plan.chunks[index]
            chunkNumber = index + 1

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

            let samples = Array(preparedAudio.audioSamples[chunk.startSample..<chunk.endSample])
            let result = try await whisperKit.transcribe(audioArray: samples, decodeOptions: decodeOptions)
            let transcript = Self.sanitizeTranscript(
                result
                    .flatMap { $0.segments }
                    .map { $0.text }
                    .joined(separator: " ")
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            )

            if transcript.isEmpty {
                progressCallback(AudioChunkerProgress(
                    currentChunk: chunkNumber,
                    totalChunks: totalChunks,
                    currentStage: LocalizationManager.localizedAppString(
                        "transcription.local.progress.chunkSkipped",
                        Int64(chunkNumber)
                    ),
                    percentComplete: 10.0 + (Double(chunkNumber) / Double(totalChunks)) * 90.0,
                    partialTranscript: nil
                ))
                skippedEmptyChunks += 1
                continue
            }

            transcripts.append(transcript)
            completedTranscriptChunks += 1

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

        guard completedTranscriptChunks > 0 || !transcripts.isEmpty else {
            throw LocalTranscriptionError.emptyTranscript
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

        Self.logCompletionDiagnostics(
            model: model,
            totalChunks: totalChunks,
            transcribedChunks: completedTranscriptChunks,
            skippedEmptyChunks: skippedEmptyChunks,
            transcriptCharacterCount: mergedTranscript.count,
            elapsedSeconds: Date().timeIntervalSince(transcriptionStart)
        )

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

    private func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            Meeting.self,
            Action.self,
            EveMessage.self,
            ChatConversation.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func readStoredSpeechPlan(for meetingId: UUID) async -> String? {
        do {
            let container = try makeModelContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
            return try context.fetch(descriptor).first?.localSpeechPlanJSON
        } catch {
            print("⚠️ [LocalTranscriptionService] Failed to read speech plan for meeting \(meetingId): \(error)")
            return nil
        }
    }

    private func persistSpeechPlan(_ plan: LocalSpeechChunkPlan, for meetingId: UUID) async {
        guard let encodedPlan = LocalAudioPreprocessor.encodePlan(plan) else { return }

        do {
            let container = try makeModelContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
            guard let meeting = try context.fetch(descriptor).first else { return }

            if meeting.localSpeechPlanFingerprint == plan.fingerprint,
               meeting.localSpeechPlanJSON == encodedPlan {
                return
            }

            meeting.localSpeechPlanJSON = encodedPlan
            meeting.localSpeechPlanFingerprint = plan.fingerprint
            try context.save()
        } catch {
            print("⚠️ [LocalTranscriptionService] Failed to persist speech plan for meeting \(meetingId): \(error)")
        }
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

    private static func logPreprocessingDiagnostics(
        _ diagnostics: LocalSpeechChunkDiagnostics,
        model: LocalTranscriptionModel,
        audioURL: URL
    ) {
        let coveragePercent = Int((diagnostics.speechCoverage * 100).rounded())
        print(
            "🧠 [LocalTranscription] Prepared '\(audioURL.lastPathComponent)' with \(model.rawValue) model " +
            "(duration: \(formatSeconds(diagnostics.totalDurationSeconds)), " +
            "speech spans: \(diagnostics.detectedSpeechSpanCount), merged spans: \(diagnostics.mergedSpeechSpanCount), " +
            "chunks: \(diagnostics.finalChunkCount), speech coverage: \(coveragePercent)%)"
        )
    }

    private static func logCompletionDiagnostics(
        model: LocalTranscriptionModel,
        totalChunks: Int,
        transcribedChunks: Int,
        skippedEmptyChunks: Int,
        transcriptCharacterCount: Int,
        elapsedSeconds: TimeInterval
    ) {
        print(
            "✅ [LocalTranscription] Finished with \(model.rawValue) model " +
            "(chunks: \(transcribedChunks)/\(totalChunks), skipped empty: \(skippedEmptyChunks), " +
            "chars: \(transcriptCharacterCount), elapsed: \(formatSeconds(elapsedSeconds)))"
        )
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }

    private static func makeLocalDecodeOptions(
        model: LocalTranscriptionModel,
        language: String?
    ) -> DecodingOptions {
        let thresholds = decodeThresholds(for: model)

        return DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: thresholds.temperatureFallbackCount,
            topK: 5,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            suppressBlank: true,
            compressionRatioThreshold: thresholds.compressionRatioThreshold,
            logProbThreshold: thresholds.logProbThreshold,
            firstTokenLogProbThreshold: thresholds.firstTokenLogProbThreshold,
            noSpeechThreshold: thresholds.noSpeechThreshold,
            chunkingStrategy: ChunkingStrategy.none
        )
    }

    private static func decodeThresholds(for model: LocalTranscriptionModel) -> (
        temperatureFallbackCount: Int,
        compressionRatioThreshold: Float,
        logProbThreshold: Float,
        firstTokenLogProbThreshold: Float,
        noSpeechThreshold: Float
    ) {
        switch model {
        case .base:
            return (
                temperatureFallbackCount: 1,
                compressionRatioThreshold: 2.2,
                logProbThreshold: -0.9,
                firstTokenLogProbThreshold: -1.1,
                noSpeechThreshold: 0.5
            )
        case .small:
            return (
                temperatureFallbackCount: 1,
                compressionRatioThreshold: 2.1,
                logProbThreshold: -0.85,
                firstTokenLogProbThreshold: -1.05,
                noSpeechThreshold: 0.45
            )
        }
    }

    private static func logDecodeDiagnostics(
        _ options: DecodingOptions,
        model: LocalTranscriptionModel
    ) {
        print(
            "🎛️ [LocalTranscription] Decode options for \(model.rawValue) " +
            "(temp: \(options.temperature), fallbacks: \(options.temperatureFallbackCount), " +
            "compression: \(options.compressionRatioThreshold ?? -1), " +
            "logprob: \(options.logProbThreshold ?? -1), " +
            "first-token: \(options.firstTokenLogProbThreshold ?? -1), " +
            "no-speech: \(options.noSpeechThreshold ?? -1), suppressBlank: \(options.suppressBlank))"
        )
    }
}
