//
//  BackgroundTaskManager.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/09/25.
//

import Foundation
import UIKit
import BackgroundTasks
import SwiftUI

final class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()

    private let transcriptionTaskIdentifier = "com.mattia.snipnote.transcription"
    private var trackedMeetings: [UUID: String] = [:]
    private var activeBackgroundTasks: [UUID: UIBackgroundTaskIdentifier] = [:]

    private init() {}

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: transcriptionTaskIdentifier, using: nil) { task in
            task.setTaskCompleted(success: false)
        }
    }

    private func beginBackgroundTask(for meetingId: UUID, meetingName: String = "") {
        trackedMeetings[meetingId] = meetingName.isEmpty ? trackedMeetings[meetingId] ?? "" : meetingName

        guard UIApplication.shared.applicationState == .background else {
            return
        }

        finishSystemBackgroundTask(for: meetingId, removeTracking: false)

        let taskId = UIApplication.shared.beginBackgroundTask(withName: "Transcription-\(meetingId)") {
            print("⏰ [BackgroundTask] Expiring task for meeting \(meetingId)")
            self.finishSystemBackgroundTask(for: meetingId, removeTracking: false)

            Task.detached {
                await LocalTranscriptionJobManager.shared.handleBackgroundExpiration(for: meetingId)
            }
        }

        guard taskId != .invalid else { return }
        activeBackgroundTasks[meetingId] = taskId
        print("🔄 Started background task \(taskId) for meeting \(meetingId) \(trackedMeetings[meetingId] ?? meetingName)")
    }

    @discardableResult
    func startBackgroundTask(
        for meetingId: UUID,
        meetingName: String = "",
        currentChunk: Int = 0,
        totalChunks: Int = 0
    ) -> UIBackgroundTaskIdentifier {
        beginBackgroundTask(for: meetingId, meetingName: meetingName)
        return activeBackgroundTasks[meetingId] ?? .invalid
    }

    func endBackgroundTask(for meetingId: UUID) {
        finishSystemBackgroundTask(for: meetingId, removeTracking: true)
    }

    func endBackgroundTask(_ taskId: UIBackgroundTaskIdentifier) {
        guard taskId != .invalid,
              let match = activeBackgroundTasks.first(where: { $0.value == taskId }) else {
            return
        }

        endBackgroundTask(for: match.key)
    }

    func getRemainingBackgroundTime() -> TimeInterval {
        UIApplication.shared.backgroundTimeRemaining
    }

    func isBackgroundTaskActive(for meetingId: UUID) -> Bool {
        activeBackgroundTasks[meetingId] != nil
    }

    func handleScenePhaseChange(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            deactivateAllBackgroundTasksKeepingTracking()
        case .background:
            activateTrackedBackgroundTasks()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func activateTrackedBackgroundTasks() {
        for (meetingId, meetingName) in trackedMeetings {
            beginBackgroundTask(for: meetingId, meetingName: meetingName)
        }
    }

    private func deactivateAllBackgroundTasksKeepingTracking() {
        for meetingId in activeBackgroundTasks.keys {
            finishSystemBackgroundTask(for: meetingId, removeTracking: false)
        }
    }

    private func finishSystemBackgroundTask(for meetingId: UUID, removeTracking: Bool) {
        if removeTracking {
            trackedMeetings.removeValue(forKey: meetingId)
        }

        guard let taskId = activeBackgroundTasks.removeValue(forKey: meetingId),
              taskId != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(taskId)
        print("🔄 Ended background task \(taskId) for meeting \(meetingId)")
    }
}
