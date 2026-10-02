//
//  LocalTranscriptionService.swift
//  SnipNote
//
//  Created by Codex on 06/03/26.
//

import Foundation
import SwiftData
import FluidAudio

enum LocalTranscriptionError: LocalizedError {
    case modelNotInstalled(LocalTranscriptionModel)
    case failedToLoadModel
    case downloadIncomplete
    case emptyTranscript
    case modelBusy
    case unsupportedParakeetLanguage(String)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let model):
            return LocalizationManager.localizedAppString(
                "transcription.local.error.modelNotInstalled",
                model.displayName
            )
        case .failedToLoadModel:
            return LocalizationManager.localizedAppString("transcription.local.error.failedToLoadModel")
        case .downloadIncomplete:
            return LocalizationManager.localizedAppString("transcription.local.error.downloadIncomplete")
        case .modelBusy:
            return LocalizationManager.localizedAppString("transcription.local.error.modelBusy")
        case .unsupportedParakeetLanguage(let language):
            return LocalizationManager.localizedAppString("transcription.local.error.unsupportedParakeetLanguage", language)
        case .emptyTranscript:
            return LocalizationManager.localizedAppString("transcription.local.error.emptyTranscript")
        }
    }
}

actor LocalTranscriptionService {
    static let shared = LocalTranscriptionService()

    func removeRetiredWhisperModels() throws {
        try Self.removeRetiredWhisperModels(
            modelRoot: URL.applicationSupportDirectory.appendingPathComponent("SnipNote/LocalModels"),
            documentsDirectory: URL.documentsDirectory
        )
    }

    /// Remove only known model folders owned by the retired local download flow.
    nonisolated static func removeRetiredWhisperModels(modelRoot: URL, documentsDirectory: URL) throws {
        for variant in ["base", "small"] {
            let folder = "openai_whisper-\(variant)"
            let repoPath = "huggingface/models/argmaxinc/whisperkit-coreml/\(folder)"
            let directories = [
                modelRoot.appendingPathComponent("Installed/\(folder)"),
                modelRoot.appendingPathComponent("Staging/\(repoPath)"),
                documentsDirectory.appendingPathComponent(repoPath)
            ]
            for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    func status(for model: LocalTranscriptionModel) async -> LocalModelStatus {
        await ParakeetTranscriptionService.service(for: model).status()
    }

    func downloadModel(
        _ model: LocalTranscriptionModel,
        statusHandler: @escaping @Sendable (LocalModelStatus) -> Void
    ) async throws {
        try await ParakeetTranscriptionService.service(for: model).downloadModel(statusHandler: statusHandler)
    }

    func deleteModel(_ model: LocalTranscriptionModel) async throws {
        try await ParakeetTranscriptionService.service(for: model).deleteModel()
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
        _ = try ParakeetTranscriptionService.languageHint(for: language)
        progressCallback(AudioChunkerProgress(
            currentChunk: 0, totalChunks: 0,
            currentStage: LocalizationManager.localizedAppString("transcription.local.progress.loadingModel", model.displayName),
            percentComplete: 1, partialTranscript: nil
        ))
        let service = ParakeetTranscriptionService.service(for: model)
        let session = try await service.makeSession()
        do {
            let transcript = try await transcribePreparedAudio(
                from: audioURL, model: model, language: language, meetingId: meetingId,
                resumeFromCompletedChunks: resumeFromCompletedChunks, existingTranscript: existingTranscript,
                parakeetSession: session, progressCallback: progressCallback
            )
            await service.finishSession(session)
            return transcript
        } catch {
            await service.finishSession(session)
            throw error
        }
    }

    private func transcribePreparedAudio(
        from audioURL: URL,
        model: LocalTranscriptionModel,
        language: String?,
        meetingId: UUID?,
        resumeFromCompletedChunks: Int,
        existingTranscript: String?,
        parakeetSession: AsrManager,
        progressCallback: @escaping @Sendable (AudioChunkerProgress) -> Void
    ) async throws -> String {
        let transcriptionStart = Date()
        // Resumable one-minute units; FluidAudio handles overlapping 15-second
        // windows and word reconciliation inside each call.
        let maxChunkLength = 960_000
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
            preferSilenceBoundaries: true,
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
            var decoderState = try TdtDecoderState()
            let result = try await parakeetSession.transcribe(
                ParakeetTranscriptionService.prepareChunkSamples(samples), decoderState: &decoderState,
                language: ParakeetTranscriptionService.languageHint(for: language)
            )
            let text = result.text
            try Task.checkCancellation()
            let transcript = Self.sanitizeTranscript(text)

            if transcript.isEmpty {
                progressCallback(AudioChunkerProgress(
                    currentChunk: chunkNumber,
                    totalChunks: totalChunks,
                    currentStage: LocalizationManager.localizedAppString(
                        "transcription.local.progress.chunkSkipped",
                        Int64(chunkNumber)
                    ),
                    percentComplete: 10.0 + (Double(chunkNumber) / Double(totalChunks)) * 90.0,
                    partialTranscript: nil,
                    completedChunks: chunkNumber,
                    cumulativeTranscript: Self.sanitizeTranscript(Self.mergeChunkTranscripts(transcripts))
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
                partialTranscript: transcript,
                completedChunks: chunkNumber,
                cumulativeTranscript: Self.sanitizeTranscript(Self.mergeChunkTranscripts(transcripts))
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

    private func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            Meeting.self,
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

}
