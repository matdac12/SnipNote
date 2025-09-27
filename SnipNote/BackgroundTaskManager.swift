//
//  BackgroundTaskManager.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/09/25.
//

import Foundation
import UIKit
import BackgroundTasks
import SwiftData
import AVFoundation

class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()

    private let transcriptionTaskIdentifier = "com.mattia.snipnote.transcription"
    private var currentBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var processingTask: BGProcessingTask?

    private init() {}

    func registerBackgroundTasks() {
        // Register the background processing task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: transcriptionTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                print("❌ [BackgroundTask] Expected BGProcessingTask but got \(type(of: task))")
                task.setTaskCompleted(success: false)
                return
            }
            self.handleTranscriptionBackgroundTask(task: processingTask)
        }
    }

    func startBackgroundTask(for meetingId: UUID) -> UIBackgroundTaskIdentifier {
        let taskId = UIApplication.shared.beginBackgroundTask(withName: "Transcription-\(meetingId)") {
            // Task expiration handler
            print("🔄 Background task expired for meeting \(meetingId)")
            self.handleTaskExpiration(meetingId: meetingId)
        }

        if taskId != .invalid {
            currentBackgroundTask = taskId
            print("🔄 Started background task \(taskId) for meeting \(meetingId)")
        }

        return taskId
    }

    func endBackgroundTask(_ taskId: UIBackgroundTaskIdentifier) {
        guard taskId != .invalid else { return }

        print("🔄 Ending background task \(taskId)")
        UIApplication.shared.endBackgroundTask(taskId)

        if currentBackgroundTask == taskId {
            currentBackgroundTask = .invalid
        }
    }

    func scheduleBackgroundProcessing(for meetingId: UUID) {
        let request = BGProcessingTaskRequest(identifier: transcriptionTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("🔄 Scheduled background processing for meeting \(meetingId)")
        } catch {
            print("🔄 Failed to schedule background processing: \(error)")
        }
    }

    private func handleTranscriptionBackgroundTask(task: BGProcessingTask) {
        processingTask = task

        // Set up task expiration handler
        task.expirationHandler = {
            print("🔄 Background processing task expired")
            self.saveTranscriptionProgress()
            task.setTaskCompleted(success: false)
            self.processingTask = nil
        }

        // Resume any pending transcriptions
        Task {
            await resumePendingTranscriptions()
            task.setTaskCompleted(success: true)
            self.processingTask = nil
        }
    }

    private func handleTaskExpiration(meetingId: UUID) {
        // Save current progress to persist across app termination
        saveTranscriptionProgress()

        // Schedule a new background task to continue processing
        scheduleBackgroundProcessing(for: meetingId)

        // End the current task
        endBackgroundTask(currentBackgroundTask)
    }

    private func saveTranscriptionProgress() {
        // This will be called when background task is about to expire
        // We'll implement this to save progress to UserDefaults or Core Data
        print("🔄 Saving transcription progress before task expiration")

        // Store current processing state in UserDefaults for recovery
        let now = Date()
        UserDefaults.standard.set(now, forKey: "lastTranscriptionSaveTime")
    }

        private func resumePendingTranscriptions() async {
        guard let sharedModelContainer = try? makeModelContainer() else {
            print("🔄 Failed to access model container in background")
            return
        }

        let context = ModelContext(sharedModelContainer)
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.isProcessing == true }
        )

        do {
            let processingMeetings = try context.fetch(descriptor)
            let meetingIds = processingMeetings.map { $0.id }
            print("🔄 Found \(meetingIds.count) meetings to resume processing")

            for meetingId in meetingIds {
                await resumeTranscriptionForMeeting(meetingId: meetingId)
            }
        } catch {
            print("🔄 Error fetching processing meetings: \(error)")
        }
    }

    private func resumeTranscriptionForMeeting(meetingId: UUID) async {
        guard let sharedModelContainer = try? makeModelContainer() else {
            print("🔄 Failed to recreate model container for meeting resume")
            return
        }

        let context = ModelContext(sharedModelContainer)
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })

        guard let meeting = try? context.fetch(descriptor).first else {
            print("🔄 Could not locate meeting to resume: \(meetingId)")
            return
        }

        guard let localPath = meeting.localAudioPath else {
            print("🔄 Meeting missing local audio path: \(meetingId)")
            meeting.setProcessingError("Original audio file unavailable for retry.")
            do {
                try context.save()
            } catch {
                print("❌ [BackgroundTask] Failed to save meeting error state: \(error)")
            }
            return
        }

        let audioURL = URL(fileURLWithPath: localPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("🔄 Local audio file missing at path: \(audioURL.path)")
            meeting.localAudioPath = nil
            meeting.setProcessingError("Original audio file unavailable for retry.")
            do {
                try context.save()
            } catch {
                print("❌ [BackgroundTask] Failed to save missing file error: \(error)")
            }
            return
        }

        let meetingName = meeting.name
        meeting.clearProcessingError()
        meeting.updateProcessingState(.transcribing)
        do {
            try context.save()
        } catch {
            print("❌ [BackgroundTask] Failed to save transcribing state: \(error)")
        }

        _ = await MinutesManager.shared.refreshBalance()

        var durationSeconds = 0
        var debitSucceeded = true
        if let audioFile = try? AVAudioFile(forReading: audioURL) {
            durationSeconds = Int(Double(audioFile.length) / audioFile.fileFormat.sampleRate)
        }

        do {
            let transcript = try await OpenAIService.shared.transcribeAudioFromURL(
                audioURL: audioURL,
                progressCallback: { progress in
                    Task { @MainActor in
                        do {
                            let container = try self.makeModelContainer()
                            let progressContext = ModelContext(container)
                            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
                            if let meetingToUpdate = try progressContext.fetch(descriptor).first {
                                meetingToUpdate.updateChunkProgress(
                                    completed: progress.currentChunk,
                                    total: progress.totalChunks
                                )
                                try progressContext.save()
                            }
                        } catch {
                            print("❌ [BackgroundTask] Failed to update chunk progress: \(error)")
                        }
                    }
                },
                meetingName: meetingName,
                meetingId: meetingId
            )

            do {
                if let meetingToUpdate = try context.fetch(descriptor).first {
                    meetingToUpdate.audioTranscript = transcript
                    meetingToUpdate.updateProcessingState(.generatingSummary)
                    try context.save()
                }
            } catch {
                print("❌ [BackgroundTask] Failed to save transcript: \(error)")
            }

            if durationSeconds > 0 {
                let debitSuccess = await MinutesManager.shared.debitMinutes(seconds: durationSeconds, meetingID: meetingId.uuidString)
                debitSucceeded = debitSuccess
                if !debitSuccess {
                    print("⚠️ Minutes debit failed during background resume for meeting \(meetingId)")
                }
                await UsageTracker.shared.trackMeetingCreated(transcribed: true, meetingSeconds: durationSeconds)
            }

            do {
                _ = try await SupabaseManager.shared.uploadAudioRecording(
                    audioURL: audioURL,
                    meetingId: meetingId,
                    duration: Double(durationSeconds)
                )
                if let meetingToUpdate = try? context.fetch(descriptor).first {
                    meetingToUpdate.hasRecording = true
                    try? context.save()
                }
            } catch {
                print("🔄 Error uploading audio during resume: \(error)")
            }

            let overview = try await OpenAIService.shared.generateMeetingOverview(transcript)
            let summary = try await OpenAIService.shared.summarizeMeeting(transcript)
            let actionItems = try await OpenAIService.shared.extractActions(transcript)

            if let meetingToFinalize = try? context.fetch(descriptor).first {
                meetingToFinalize.shortSummary = overview
                meetingToFinalize.aiSummary = summary
                meetingToFinalize.markCompleted()

                if durationSeconds > 0 && !debitSucceeded {
                    meetingToFinalize.setProcessingError("Minutes debit failed for this transcription. Please refresh your balance.")
                }

                for actionItem in actionItems {
                    let priority: ActionPriority
                    switch actionItem.priority.uppercased() {
                    case "HIGH":
                        priority = .high
                    case "MED", "MEDIUM":
                        priority = .medium
                    case "LOW":
                        priority = .low
                    default:
                        priority = .medium
                    }

                    let action = Action(
                        title: actionItem.action,
                        priority: priority,
                        sourceNoteId: meetingId
                    )
                    context.insert(action)
                }

                if meetingToFinalize.hasRecording,
                   debitSucceeded,
                   FileManager.default.fileExists(atPath: audioURL.path) {
                    try? FileManager.default.removeItem(at: audioURL)
                    meetingToFinalize.localAudioPath = nil
                }

                try? context.save()

                Task {
                    await NotificationService.shared.sendProcessingCompleteNotification(
                        for: meetingId,
                        meetingName: meetingToFinalize.name
                    )
                }

                Task { @MainActor in
                    if let container = try? self.makeModelContainer() {
                        let notificationContext = ModelContext(container)
                        let descriptor = FetchDescriptor<Action>()
                        if let allActions = try? notificationContext.fetch(descriptor) {
                            NotificationService.shared.scheduleNotification(with: allActions)
                            await NotificationService.shared.updateBadgeCount(with: allActions)
                        }
                    }
                }

                Task { @MainActor in
                    await UsageTracker.shared.trackAIUsage(
                        summaries: 1,
                        actionsExtracted: actionItems.count
                    )
                }
            }
        } catch {
            print("🔄 Error resuming transcription for meeting \(meetingId): \(error)")
            if let meetingWithError = try? context.fetch(descriptor).first {
                meetingWithError.setProcessingError("Transcription failed during background processing.")
                try? context.save()
            }
        }
    }

    private func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            Meeting.self,
            Action.self,
            EveMessage.self,
            ChatConversation.self,
            UserAIContext.self,
            MeetingFileState.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }


    func getRemainingBackgroundTime() -> TimeInterval {
        return UIApplication.shared.backgroundTimeRemaining
    }

    func isBackgroundTaskActive() -> Bool {
        return currentBackgroundTask != .invalid
    }
}