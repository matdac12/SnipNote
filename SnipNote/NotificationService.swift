//
//  NotificationService.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import UserNotifications
import SwiftData

@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    @Published var isNotificationEnabled = UserDefaults.standard.bool(forKey: "notificationEnabled")
    @Published var notificationTime = UserDefaults.standard.object(forKey: "notificationTime") as? Date ?? {
        var components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationIdentifier = "daily-high-priority-actions"
    private let processingNotificationIdentifierPrefix = "meeting-processing-"
    
    private init() {}
    
    // MARK: - Permission Management
    
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Error requesting notification permission: \(error)")
            return false
        }
    }
    
    func checkNotificationPermission() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Notification Scheduling
    
    func scheduleNotification(with actions: [Action]) {
        guard isNotificationEnabled else { return }
        
        // Cancel existing notification
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        
        let highPriorityActions = actions.filter { $0.priority == .high && !$0.isCompleted }
        
        guard !highPriorityActions.isEmpty else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "High Priority Actions"
        content.body = createNotificationBody(for: highPriorityActions)
        content.sound = .default
        content.badge = NSNumber(value: highPriorityActions.count)
        content.categoryIdentifier = "ACTIONS_NOTIFICATION"
        content.userInfo = ["navigateTo": "actions"]
        
        // Create trigger for daily notification
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: notificationTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    private func createNotificationBody(for actions: [Action]) -> String {
        let count = actions.count

        if count == 1 {
            return "You have 1 high priority action: \(actions.first?.title ?? "Untitled")"
        } else if count <= 3 {
            let titles = actions.prefix(2).map { $0.title }.joined(separator: ", ")
            return count == 2 ? "You have 2 high priority actions: \(titles)" : "You have \(count) high priority actions: \(titles) and \(count - 2) more"
        } else {
            let titles = actions.prefix(2).map { $0.title }.joined(separator: ", ")
            return "You have \(count) high priority actions: \(titles) and \(count - 2) more"
        }
    }
    
    // MARK: - Settings Management
    
    func updateNotificationSettings(enabled: Bool, time: Date) {
        isNotificationEnabled = enabled
        notificationTime = time
        
        UserDefaults.standard.set(enabled, forKey: "notificationEnabled")
        UserDefaults.standard.set(time, forKey: "notificationTime")
        
        if !enabled {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        }
    }
    
    func cancelAllNotifications() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }
    
    func updateBadgeCount(with actions: [Action], actionsEnabled: Bool) async {
        let highPriorityCount = actionsEnabled ? actions.filter { $0.priority == .high && !$0.isCompleted }.count : 0
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(highPriorityCount)
        } catch {
            print("Error updating badge count: \(error)")
        }
    }

    // MARK: - Processing Notifications

    /// Schedule a notification for when a meeting starts processing
    func scheduleProcessingNotification(for meetingId: UUID, meetingName: String) async {
        // Only schedule if we have permission
        Task {
            let status = await checkNotificationPermission()
            guard status == .authorized else { return }

            let identifier = "\(processingNotificationIdentifierPrefix)\(meetingId.uuidString)"

            let content = UNMutableNotificationContent()
            content.title = "Recording Started"
            content.body = "Processing '\(meetingName.isEmpty ? "Untitled Meeting" : meetingName)'..."
            content.sound = .default
            content.categoryIdentifier = "PROCESSING_NOTIFICATION"

            // Schedule a very short delay to show the notification (1 second)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
            } catch {
                print("Error scheduling processing notification: \(error)")
            }
        }
    }

    /// Send notification when processing is complete
    func sendProcessingCompleteNotification(for meetingId: UUID, meetingName: String) async {
        // Only send if we have permission
        Task {
            let status = await checkNotificationPermission()
            guard status == .authorized else { return }

            // Cancel the original processing notification
            let processingIdentifier = "\(processingNotificationIdentifierPrefix)\(meetingId.uuidString)"
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [processingIdentifier])

            let identifier = "meeting-complete-\(meetingId.uuidString)"

            let content = UNMutableNotificationContent()
            content.title = "Meeting Ready!"
            content.body = "'\(meetingName.isEmpty ? "Untitled Meeting" : meetingName)' is ready with AI summary and actions"
            content.sound = .default
            content.categoryIdentifier = "MEETING_COMPLETE_NOTIFICATION"
            content.userInfo = ["meetingId": meetingId.uuidString, "navigateTo": "meeting"]

            // Send immediately
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
                print("✅ Processing complete notification sent for meeting: \(meetingName)")
            } catch {
                print("Error sending processing complete notification: \(error)")
            }
        }
    }

    /// Send notification when processing fails
    func sendProcessingFailedNotification(for meetingId: UUID, meetingName: String, errorMessage: String) async {
        // Only send if we have permission
        Task {
            let status = await checkNotificationPermission()
            guard status == .authorized else { return }

            // Cancel the original processing notification
            let processingIdentifier = "\(processingNotificationIdentifierPrefix)\(meetingId.uuidString)"
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [processingIdentifier])

            let identifier = "meeting-failed-\(meetingId.uuidString)"

            let content = UNMutableNotificationContent()
            content.title = "Transcription Failed"
            content.body = "'\(meetingName.isEmpty ? "Untitled Meeting" : meetingName)' failed to process: \(errorMessage)"
            content.sound = .default
            content.categoryIdentifier = "MEETING_FAILED_NOTIFICATION"
            content.userInfo = ["meetingId": meetingId.uuidString, "navigateTo": "meeting"]

            // Send immediately
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
                print("✅ Processing failed notification sent for meeting: \(meetingName)")
            } catch {
                print("Error sending processing failed notification: \(error)")
            }
        }
    }

    /// Send notification when transcription is paused due to background task expiration
    func sendTranscriptionPausedNotification(for meetingId: UUID, meetingName: String) async {
        // Only send if we have permission
        Task {
            let status = await checkNotificationPermission()
            guard status == .authorized else {
                print("⚠️ [NotificationService] No permission to send pause notification")
                return
            }

            let identifier = "meeting-paused-\(meetingId.uuidString)"

            let content = UNMutableNotificationContent()
            content.title = "Transcription Paused"
            content.body = "Open SnipNote to continue transcribing '\(meetingName.isEmpty ? "Untitled Meeting" : meetingName)'"
            content.sound = .default
            content.categoryIdentifier = "TRANSCRIPTION_PAUSED_NOTIFICATION"
            content.userInfo = [
                "meetingId": meetingId.uuidString,
                "navigateTo": "meeting",
                "action": "resume"
            ]

            // Send immediately
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
                print("✅ [NotificationService] Pause notification sent for meeting: \(meetingName)")
            } catch {
                print("❌ [NotificationService] Error sending pause notification: \(error)")
            }
        }
    }

    /// Send progress notification during transcription
    func sendProgressNotification(meetingId: UUID, meetingName: String, progress: Int) async {
        // Only send if we have permission
        Task {
            let status = await checkNotificationPermission()
            guard status == .authorized else { return }

            let identifier = "meeting-progress-\(meetingId.uuidString)-\(progress)"

            let content = UNMutableNotificationContent()
            content.title = "Processing Update"
            content.body = "'\(meetingName.isEmpty ? "Untitled Meeting" : meetingName)' is \(progress)% complete"
            content.sound = .default
            content.categoryIdentifier = "PROGRESS_NOTIFICATION"

            // Send immediately
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
                print("📊 Progress notification sent: \(progress)% for meeting: \(meetingName)")
            } catch {
                print("Error sending progress notification: \(error)")
            }
        }
    }

    /// Cancel processing notification for a specific meeting
    func cancelProcessingNotification(for meetingId: UUID) {
        let identifier = "\(processingNotificationIdentifierPrefix)\(meetingId.uuidString)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Schedule a notification for estimated completion time based on audio duration
    /// Formula: 2 min (worker startup) + audioDuration (minutes) × 0.08 × 1.5 (safety buffer)
    /// Example: 2hr audio (120 min) → 2 min + (10 min base × 1.5) = 17 min notification
    /// Example: 5min audio → 2 min + (0.4 min × 1.5) = 2.6 min notification
    func scheduleEstimatedCompletionNotification(for meetingId: UUID, meetingName: String, audioDuration: TimeInterval) async {
        // Only schedule if we have permission
        Task {
            let status = await checkNotificationPermission()
            guard status == .authorized else { return }

            // Calculate estimated processing time
            let audioDurationMinutes = audioDuration / 60.0
            let baseProcessingMinutes = audioDurationMinutes * 0.08  // Processing takes ~8% of audio duration
            let safetyBuffer = 1.5  // Add 50% buffer for safety
            let workerStartupMinutes = 2.0  // Python worker may take ~1 min to start, add buffer
            let estimatedMinutes = workerStartupMinutes + (baseProcessingMinutes * safetyBuffer)

            // Convert to seconds for notification trigger
            let notificationDelay = estimatedMinutes * 60.0

            print("⏱️ Scheduling estimated completion notification:")
            print("   Audio duration: \(Int(audioDurationMinutes)) min")
            print("   Base processing: \(Int(baseProcessingMinutes)) min")
            print("   Worker startup: \(Int(workerStartupMinutes)) min")
            print("   Total estimated: \(Int(estimatedMinutes)) min")
            print("   Notification in: \(Int(notificationDelay)) seconds")

            let identifier = "meeting-estimated-\(meetingId.uuidString)"

            let content = UNMutableNotificationContent()
            content.title = "Processing Update"
            content.body = "Your transcript for '\(meetingName.isEmpty ? "Untitled Meeting" : meetingName)' should be ready! Check back to see your results."
            content.sound = .default
            content.categoryIdentifier = "ESTIMATED_COMPLETE_NOTIFICATION"
            content.userInfo = ["meetingId": meetingId.uuidString, "navigateTo": "meeting"]

            // Schedule for estimated completion time
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: notificationDelay, repeats: false)

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
                print("✅ Estimated completion notification scheduled for \(Int(estimatedMinutes)) minutes")
            } catch {
                print("❌ Error scheduling estimated completion notification: \(error)")
            }
        }
    }

    /// Cancel estimated completion notification for a specific meeting
    func cancelEstimatedCompletionNotification(for meetingId: UUID) {
        let identifier = "meeting-estimated-\(meetingId.uuidString)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        print("🗑️ Cancelled estimated completion notification for meeting")
    }
}