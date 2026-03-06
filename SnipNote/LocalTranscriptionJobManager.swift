//
//  LocalTranscriptionJobManager.swift
//  SnipNote
//
//  Created by Codex on 06/03/26.
//

import Foundation
import SwiftData

actor LocalTranscriptionJobManager {
    static let shared = LocalTranscriptionJobManager()

    private struct JobContext: Sendable {
        let meetingId: UUID
        let meetingName: String
        let audioURL: URL
        let language: String?
        let model: LocalTranscriptionModel
        let sourceAudioDuration: TimeInterval
        let resumePhase: MeetingProcessingPhase
        let completedChunks: Int
        let existingTranscript: String?
    }

    private let openAIService = OpenAIService.shared
    private var activeJobs: [UUID: Task<Void, Never>] = [:]
    private var pauseRequestedMeetingIDs = Set<UUID>()
    private var cancelRequestedMeetingIDs = Set<UUID>()

    private init() {}

    func startJob(
        meetingId: UUID,
        audioURL: URL,
        language: String?,
        sourceAudioDuration: TimeInterval
    ) async {
        guard activeJobs[meetingId] == nil else { return }

        let model = await MainActor.run { LocalTranscriptionManager.shared.selectedModel }

        guard let context = await prepareFreshJob(
            meetingId: meetingId,
            audioURL: audioURL,
            language: language,
            sourceAudioDuration: sourceAudioDuration,
            model: model
        ) else {
            return
        }

        await beginBackgroundTask(for: context.meetingId, meetingName: context.meetingName)
        await scheduleProcessingNotification(for: context)
        launchJob(with: context)
    }

    func resumeJob(meetingId: UUID) async {
        guard activeJobs[meetingId] == nil else { return }

        guard let context = await preparePausedJob(meetingId: meetingId) else {
            return
        }

        await beginBackgroundTask(for: context.meetingId, meetingName: context.meetingName)
        await scheduleProcessingNotification(for: context)
        launchJob(with: context)
    }

    func cancelJob(meetingId: UUID, deleteMeeting: Bool = false) async {
        cancelRequestedMeetingIDs.insert(meetingId)
        let hadActiveTask: Bool

        if let task = activeJobs.removeValue(forKey: meetingId) {
            task.cancel()
            hadActiveTask = true
        } else {
            hadActiveTask = false
        }

        await endBackgroundTask(for: meetingId)
        await cancelProcessingNotification(for: meetingId)

        do {
            let container = try makeModelContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })

            guard let meeting = try context.fetch(descriptor).first else {
                if !hadActiveTask {
                    cancelRequestedMeetingIDs.remove(meetingId)
                }
                return
            }

            if deleteMeeting {
                let actionDescriptor = FetchDescriptor<Action>(predicate: #Predicate { $0.sourceNoteId == meetingId })
                let actions = try context.fetch(actionDescriptor)
                for action in actions {
                    context.delete(action)
                }
                context.delete(meeting)
            } else {
                meeting.markLocalJobFailed("Transcription cancelled.")
            }

            try context.save()
        } catch {
            print("❌ [LocalJobManager] Failed to cancel local job for meeting \(meetingId): \(error)")
        }

        if !hadActiveTask {
            cancelRequestedMeetingIDs.remove(meetingId)
        }
    }

    func handleBackgroundExpiration(for meetingId: UUID) async {
        guard activeJobs[meetingId] != nil else { return }

        let pauseMessage = "Transcription paused. Open SnipNote to continue."
        pauseRequestedMeetingIDs.insert(meetingId)

        if let task = activeJobs.removeValue(forKey: meetingId) {
            task.cancel()
        }

        do {
            let container = try makeModelContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })

            if let meeting = try context.fetch(descriptor).first {
                meeting.markLocalJobPaused(reason: pauseMessage)
                try context.save()

                await sendPausedNotification(for: meetingId, meetingName: meeting.name)
            }
        } catch {
            print("❌ [LocalJobManager] Failed to pause local job \(meetingId): \(error)")
        }
    }

    func pauseAllActiveJobsForBackgroundExpiration() async {
        let meetingIDs = Array(activeJobs.keys)
        for meetingId in meetingIDs {
            await handleBackgroundExpiration(for: meetingId)
        }
    }

    func isJobActive(for meetingId: UUID) -> Bool {
        activeJobs[meetingId] != nil
    }

    private func launchJob(with context: JobContext) {
        let task = Task.detached(priority: .userInitiated) { [context] in
            await self.runJob(with: context)
        }

        activeJobs[context.meetingId] = task
    }

    private func runJob(with context: JobContext) async {
        defer {
            Task {
                await self.cleanupRun(for: context.meetingId)
            }
        }

        do {
            let (transcript, debitSucceeded) = try await ensureTranscript(for: context)
            try Task.checkCancellation()

            let overview = try await ensureOverview(for: context, transcript: transcript)
            try Task.checkCancellation()

            let summary = try await ensureSummary(for: context, transcript: transcript)
            try Task.checkCancellation()

            let actionItems = try await ensureActions(for: context, transcript: transcript)
            try Task.checkCancellation()

            await UsageTracker.shared.trackAIUsage(
                summaries: 1,
                actionsExtracted: actionItems.count
            )

            try await finalizeSuccess(
                for: context,
                transcript: transcript,
                debitSucceeded: debitSucceeded,
                overview: overview,
                summary: summary,
                actionItems: actionItems
            )
        } catch is CancellationError {
            if pauseRequestedMeetingIDs.contains(context.meetingId) || cancelRequestedMeetingIDs.contains(context.meetingId) {
                return
            }

            await failJob(
                meetingId: context.meetingId,
                message: "Transcription cancelled.",
                notifyUser: false
            )
        } catch {
            let message = await failureMessage(for: context.meetingId)
            await failJob(meetingId: context.meetingId, message: message, notifyUser: true)
            print("❌ [LocalJobManager] Local job failed for meeting \(context.meetingId): \(error)")
        }
    }

    private func prepareFreshJob(
        meetingId: UUID,
        audioURL: URL,
        language: String?,
        sourceAudioDuration: TimeInterval,
        model: LocalTranscriptionModel
    ) async -> JobContext? {
        do {
            let container = try makeModelContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })

            guard let meeting = try context.fetch(descriptor).first else {
                return nil
            }

            meeting.configureTranscriptionJob(
                backend: .local,
                model: model,
                language: language,
                sourceAudioDuration: sourceAudioDuration
            )
            meeting.localAudioPath = audioURL.path
            meeting.audioTranscript = Self.transcriptPlaceholder
            meeting.shortSummary = Self.overviewPlaceholder
            meeting.aiSummary = Self.summaryPlaceholder
            meeting.updateProcessingState(.transcribing)
            meeting.updateProcessingPhase(.queued, stage: "Starting transcription...", progressPercent: 0)
            meeting.processingError = nil
            meeting.lastProcessedChunk = 0
            meeting.totalChunks = 0
            try context.save()

            return JobContext(
                meetingId: meeting.id,
                meetingName: meeting.name,
                audioURL: audioURL,
                language: language,
                model: model,
                sourceAudioDuration: sourceAudioDuration,
                resumePhase: .transcribing,
                completedChunks: 0,
                existingTranscript: nil
            )
        } catch {
            print("❌ [LocalJobManager] Failed to prepare local job \(meetingId): \(error)")
            return nil
        }
    }

    private func preparePausedJob(meetingId: UUID) async -> JobContext? {
        do {
            let container = try makeModelContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })

            guard let meeting = try context.fetch(descriptor).first,
                  let localPath = meeting.localAudioPath else {
                return nil
            }

            let audioURL = URL(fileURLWithPath: localPath)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                meeting.localAudioPath = nil
                meeting.markLocalJobFailed("Original audio file unavailable for retry.")
                try context.save()
                return nil
            }

            let model: LocalTranscriptionModel
            if let storedModel = meeting.localTranscriptionModel {
                model = storedModel
            } else {
                model = await MainActor.run {
                    LocalTranscriptionManager.shared.selectedModel
                }
            }

            let resumePhase = meeting.resumePhase
            let transcript = meeting.hasTranscriptContent ? meeting.audioTranscript : nil
            let resumeStage: String?
            if resumePhase == .transcribing,
               meeting.lastProcessedChunk > 0,
               meeting.totalChunks > 0 {
                resumeStage = "Resuming from chunk \(meeting.lastProcessedChunk + 1) of \(meeting.totalChunks)"
            } else {
                resumeStage = meeting.effectiveStageDescription
            }
            meeting.clearProcessingError()
            meeting.updateProcessingState(resumePhase == .transcribing ? .transcribing : .generatingSummary)
            meeting.updateProcessingPhase(
                resumePhase,
                stage: resumeStage,
                progressPercent: meeting.displayedProgressPercent
            )
            try context.save()

            return JobContext(
                meetingId: meeting.id,
                meetingName: meeting.name,
                audioURL: audioURL,
                language: meeting.transcriptionLanguage,
                model: model,
                sourceAudioDuration: meeting.billingDuration,
                resumePhase: resumePhase,
                completedChunks: resumePhase == .transcribing ? meeting.lastProcessedChunk : 0,
                existingTranscript: transcript
            )
        } catch {
            print("❌ [LocalJobManager] Failed to prepare paused job \(meetingId): \(error)")
            return nil
        }
    }

    private func ensureTranscript(for context: JobContext) async throws -> (String, Bool) {
        if context.resumePhase != .transcribing, let existingTranscript = context.existingTranscript {
            return (existingTranscript, await didDebitMinutesAlready(for: context.meetingId))
        }

        try await updateMeeting(context.meetingId) { meeting, _ in
            meeting.updateProcessingState(.transcribing)
            let stage: String
            if context.completedChunks > 0, meeting.totalChunks > 0 {
                stage = "Resuming from chunk \(context.completedChunks + 1) of \(meeting.totalChunks)"
            } else {
                stage = "Preparing transcription..."
            }
            meeting.updateProcessingPhase(.preparing, stage: stage, progressPercent: max(meeting.displayedProgressPercent, 0))
        }

        let transcript = try await TranscriptionRouter.shared.transcribeAudioFromURL(
            audioURL: context.audioURL,
            progressCallback: { progress in
                Task {
                    await self.handleTranscriptionProgress(for: context.meetingId, progress: progress)
                }
            },
            meetingName: context.meetingName,
            meetingId: context.meetingId,
            language: context.language,
            localModel: context.model,
            localResumeCompletedChunks: context.completedChunks,
            localExistingTranscript: context.completedChunks > 0 ? context.existingTranscript : nil
        )

        try Task.checkCancellation()
        let debitSucceeded = try await persistTranscript(
            transcript,
            for: context.meetingId,
            duration: context.sourceAudioDuration
        )
        return (transcript, debitSucceeded)
    }

    private func ensureOverview(for context: JobContext, transcript: String) async throws -> String {
        if context.resumePhase == .generatingSummary || context.resumePhase == .extractingActions || context.resumePhase == .completed {
            if let overview = await readMeetingValue(context.meetingId, value: { $0.shortSummary }),
               !overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               overview != Self.overviewPlaceholder {
                return overview
            }
        }

        try await updateMeeting(context.meetingId) { meeting, _ in
            meeting.updateProcessingState(.generatingSummary)
            meeting.updateProcessingPhase(.generatingOverview, stage: "Generating overview...", progressPercent: max(meeting.displayedProgressPercent, 92))
        }

        let overview = try await openAIService.generateMeetingOverview(transcript)
        try Task.checkCancellation()

        try await updateMeeting(context.meetingId) { meeting, _ in
            meeting.shortSummary = overview
            meeting.updateProcessingState(.generatingSummary)
            meeting.updateProcessingPhase(.generatingSummary, stage: "Generating summary...", progressPercent: max(meeting.displayedProgressPercent, 95))
        }

        return overview
    }

    private func ensureSummary(for context: JobContext, transcript: String) async throws -> String {
        if context.resumePhase == .extractingActions || context.resumePhase == .completed {
            if let summary = await readMeetingValue(context.meetingId, value: { $0.aiSummary }),
               !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               summary != Self.summaryPlaceholder {
                return summary
            }
        }

        if context.resumePhase == .generatingSummary {
            try await updateMeeting(context.meetingId) { meeting, _ in
                meeting.updateProcessingState(.generatingSummary)
                meeting.updateProcessingPhase(.generatingSummary, stage: "Generating summary...", progressPercent: max(meeting.displayedProgressPercent, 95))
            }
        }

        let summary = try await openAIService.summarizeMeeting(transcript)
        try Task.checkCancellation()

        try await updateMeeting(context.meetingId) { meeting, _ in
            meeting.aiSummary = summary
            meeting.updateProcessingState(.generatingSummary)
            meeting.updateProcessingPhase(.extractingActions, stage: "Extracting action items...", progressPercent: max(meeting.displayedProgressPercent, 98))
        }

        return summary
    }

    private func ensureActions(for context: JobContext, transcript: String) async throws -> [ActionItem] {
        if context.resumePhase == .extractingActions {
            try await updateMeeting(context.meetingId) { meeting, _ in
                meeting.updateProcessingState(.generatingSummary)
                meeting.updateProcessingPhase(.extractingActions, stage: "Extracting action items...", progressPercent: max(meeting.displayedProgressPercent, 98))
            }
        }

        return try await openAIService.extractActions(transcript)
    }

    private func persistTranscript(
        _ transcript: String,
        for meetingId: UUID,
        duration: TimeInterval
    ) async throws -> Bool {
        try await updateMeeting(meetingId) { meeting, _ in
            meeting.audioTranscript = transcript
            meeting.updateProcessingState(.generatingSummary)
            meeting.updateProcessingPhase(.generatingOverview, stage: "Generating overview...", progressPercent: max(meeting.displayedProgressPercent, 90))
        }

        var debitSucceeded = true
        if duration > 0 {
            let durationSeconds = Int(duration)
            let meetingID = meetingId.uuidString
            let alreadyDebited = await didDebitMinutesAlready(for: meetingId)
            if alreadyDebited {
                debitSucceeded = true
            } else {
                debitSucceeded = await MinutesManager.shared.debitMinutes(seconds: durationSeconds, meetingID: meetingID)
            }

            if !debitSucceeded {
                print("⚠️ [LocalJobManager] Minutes debit failed for meeting \(meetingId)")
            }

            try await updateMeeting(meetingId) { meeting, _ in
                if debitSucceeded {
                    meeting.didDebitTranscriptionMinutes = true
                }
            }

            if debitSucceeded && !alreadyDebited {
                await UsageTracker.shared.trackMeetingCreated(
                    transcribed: true,
                    meetingSeconds: durationSeconds
                )
            }
        }

        return debitSucceeded
    }

    private func finalizeSuccess(
        for context: JobContext,
        transcript: String,
        debitSucceeded: Bool,
        overview: String,
        summary: String,
        actionItems: [ActionItem]
    ) async throws {
        let meetingID = context.meetingId
        let billingFailureMessage = "Minutes debit failed for this transcription. Please refresh your balance."

        try await updateMeeting(meetingID) { meeting, modelContext in
            meeting.shortSummary = overview
            meeting.aiSummary = summary
            if debitSucceeded {
                meeting.markLocalJobCompleted()
            } else {
                meeting.markLocalJobFailed(billingFailureMessage)
            }

            let actionDescriptor = FetchDescriptor<Action>(predicate: #Predicate { $0.sourceNoteId == meetingID })
            let existingActions = try modelContext.fetch(actionDescriptor)
            for action in existingActions {
                modelContext.delete(action)
            }

            for actionItem in actionItems {
                let priority: ActionPriority
                switch actionItem.priority.uppercased() {
                case "HIGH":
                    priority = .high
                case "LOW":
                    priority = .low
                case "MED", "MEDIUM":
                    priority = .medium
                default:
                    priority = .medium
                }

                modelContext.insert(
                    Action(
                        title: actionItem.action,
                        priority: priority,
                        sourceNoteId: meetingID
                    )
                )
            }

            if debitSucceeded,
               let localPath = meeting.localAudioPath,
               FileManager.default.fileExists(atPath: localPath) {
                try? FileManager.default.removeItem(atPath: localPath)
                meeting.localAudioPath = nil
            }
        }

        try await syncSuccessfulMeeting(
            meetingId: context.meetingId,
            transcript: transcript,
            overview: overview,
            summary: summary,
            actions: actionItems,
            duration: context.sourceAudioDuration
        )

        if debitSucceeded {
            await sendCompletionNotification(for: context.meetingId, meetingName: context.meetingName)
        } else {
            await sendFailureNotification(
                for: context.meetingId,
                meetingName: context.meetingName,
                message: billingFailureMessage
            )
        }
    }

    private func failJob(meetingId: UUID, message: String, notifyUser: Bool) async {
        do {
            let meetingName = try await updateMeeting(meetingId) { meeting, _ in
                meeting.markLocalJobFailed(message)
            }

            if notifyUser {
                await sendFailureNotification(for: meetingId, meetingName: meetingName, message: message)
            }
        } catch {
            print("❌ [LocalJobManager] Failed to persist failure for meeting \(meetingId): \(error)")
        }
    }

    private func handleTranscriptionProgress(for meetingId: UUID, progress: AudioChunkerProgress) async {
        do {
            _ = try await updateMeeting(meetingId) { meeting, _ in
                let currentPercent = meeting.displayedProgressPercent
                let nextPercent = max(currentPercent, progress.percentComplete)
                if let partialTranscript = progress.partialTranscript,
                   !partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let existingTranscript = meeting.hasTranscriptContent ? meeting.audioTranscript : ""
                    meeting.audioTranscript = LocalTranscriptionService.mergePartialTranscript(
                        existingTranscript,
                        with: partialTranscript
                    )
                }

                meeting.updateDetailedProgress(
                    completed: progress.currentChunk,
                    total: progress.totalChunks,
                    percent: nextPercent,
                    stage: progress.currentStage
                )
            }
        } catch {
            print("❌ [LocalJobManager] Failed to save transcription progress for meeting \(meetingId): \(error)")
        }
    }

    private func syncSuccessfulMeeting(
        meetingId: UUID,
        transcript: String,
        overview: String,
        summary: String,
        actions: [ActionItem],
        duration: TimeInterval
    ) async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })

        guard let meeting = try context.fetch(descriptor).first else {
            return
        }

        do {
            try await SupabaseManager.shared.saveMeeting(meeting)
            try await SupabaseManager.shared.saveCompletedTranscriptionJob(
                meetingId: meetingId,
                audioStoragePath: nil,
                duration: duration,
                transcript: transcript,
                overview: overview,
                summary: summary,
                actions: actions
            )
        } catch {
            print("⚠️ [LocalJobManager] Failed to sync meeting \(meetingId): \(error)")
        }
    }

    private func failureMessage(for meetingId: UUID) async -> String {
        let hasTranscript = (await readMeetingValue(meetingId, value: { $0.hasTranscriptContent })) ?? false
        if hasTranscript {
            return "Transcript saved, but AI analysis failed. Check your connection and retry."
        }
        return "Transcription failed. Please try again."
    }

    private func didDebitMinutesAlready(for meetingId: UUID) async -> Bool {
        await readMeetingValue(meetingId, value: { $0.didDebitTranscriptionMinutes }) ?? false
    }

    private func readMeetingValue<T>( _ meetingId: UUID, value: @escaping (Meeting) -> T) async -> T? {
        do {
            let container = try makeModelContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
            return try context.fetch(descriptor).first.map(value)
        } catch {
            print("❌ [LocalJobManager] Failed to read meeting \(meetingId): \(error)")
            return nil
        }
    }

    @discardableResult
    private func updateMeeting(
        _ meetingId: UUID,
        updates: (Meeting, ModelContext) throws -> Void
    ) async throws -> String {
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })

        guard let meeting = try context.fetch(descriptor).first else {
            throw NSError(domain: "LocalTranscriptionJobManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Meeting not found"])
        }

        try updates(meeting, context)
        try context.save()
        return meeting.name
    }

    private func cleanupRun(for meetingId: UUID) async {
        activeJobs[meetingId] = nil
        pauseRequestedMeetingIDs.remove(meetingId)
        cancelRequestedMeetingIDs.remove(meetingId)
        await endBackgroundTask(for: meetingId)
    }

    private func beginBackgroundTask(for meetingId: UUID, meetingName: String) async {
        _ = await MainActor.run {
            BackgroundTaskManager.shared.startBackgroundTask(for: meetingId, meetingName: meetingName)
        }
    }

    private func endBackgroundTask(for meetingId: UUID) async {
        _ = await MainActor.run {
            BackgroundTaskManager.shared.endBackgroundTask(for: meetingId)
        }
    }

    private func scheduleProcessingNotification(for context: JobContext) async {
        _ = await MainActor.run {
            Task {
                await NotificationService.shared.scheduleProcessingNotification(
                    for: context.meetingId,
                    meetingName: context.meetingName
                )
            }
        }
    }

    private func sendCompletionNotification(for meetingId: UUID, meetingName: String) async {
        _ = await MainActor.run {
            NotificationService.shared.cancelEstimatedCompletionNotification(for: meetingId)
            Task {
                await NotificationService.shared.sendProcessingCompleteNotification(
                    for: meetingId,
                    meetingName: meetingName
                )
            }
        }
    }

    private func sendFailureNotification(for meetingId: UUID, meetingName: String, message: String) async {
        _ = await MainActor.run {
            NotificationService.shared.cancelEstimatedCompletionNotification(for: meetingId)
            Task {
                await NotificationService.shared.sendProcessingFailedNotification(
                    for: meetingId,
                    meetingName: meetingName,
                    errorMessage: message
                )
            }
        }
    }

    private func sendPausedNotification(for meetingId: UUID, meetingName: String) async {
        _ = await MainActor.run {
            Task {
                await NotificationService.shared.sendTranscriptionPausedNotification(
                    for: meetingId,
                    meetingName: meetingName
                )
            }
        }
    }

    private func cancelProcessingNotification(for meetingId: UUID) async {
        _ = await MainActor.run {
            NotificationService.shared.cancelProcessingNotification(for: meetingId)
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

    private static let transcriptPlaceholder = "Transcribing meeting audio..."
    private static let overviewPlaceholder = "Generating overview..."
    private static let summaryPlaceholder = "Generating meeting summary..."
}
