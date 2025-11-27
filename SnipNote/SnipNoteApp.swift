//
//  SnipNoteApp.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import UserNotifications
import StoreKit

@main
struct SnipNoteApp: App {
    @State private var deepLinkAudioURL: URL?
    @State private var showResumeAlert = false
    @State private var pausedMeetingInfo: [String: Any]?
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var localizationManager = LocalizationManager.shared
    @StateObject private var backgroundTaskManager = BackgroundTaskManager.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Action.self,
            Meeting.self,
            EveMessage.self,
            ChatConversation.self,
            UserAIContext.self,
            MeetingFileState.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            // Create fallback in-memory container to prevent app crash
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                print("❌ Critical: Even fallback ModelContainer failed: \(error)")
                // Last resort: minimal in-memory schema
                let minimalSchema = Schema([Meeting.self])
                do {
                    return try ModelContainer(for: minimalSchema, configurations: [ModelConfiguration(schema: minimalSchema, isStoredInMemoryOnly: true)])
                } catch {
                    fatalError("Failed to create in-memory ModelContainer as last resort: \(error). This should never happen. Please reinstall the app.")
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            AuthenticationView(deepLinkAudioURL: $deepLinkAudioURL)
                .environmentObject(themeManager)
                .environmentObject(localizationManager)
                .themed()
                .environment(\.locale, localizationManager.locale)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    Task {
                        // Initialize minutes manager - grant free tier if needed and refresh balance
                        await MinutesManager.shared.handleAppLaunch()
                    }
                }
                .alert("Continue Transcription?", isPresented: $showResumeAlert) {
                    Button("Yes") {
                        handleResumeTranscription(resume: true)
                    }
                    Button("No", role: .cancel) {
                        handleResumeTranscription(resume: false)
                    }
                } message: {
                    if let info = pausedMeetingInfo,
                       let meetingName = info["meetingName"] as? String {
                        Text("Continue transcribing '\(meetingName)'?")
                    } else {
                        Text("Continue your paused transcription?")
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        checkForPausedTranscriptions()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleDeepLink(_ url: URL) {
        print("📱 Deep link received: \(url)")
        
        if url.scheme == "snipnote" {
            if url.host == "import-audio" {
                if let audioURLString = url.queryParameters["audioURL"],
                   let audioURL = URL(string: audioURLString) {
                    print("🎵 Audio URL extracted: \(audioURL)")
                    // Store the audio URL for the ContentView to handle
                    deepLinkAudioURL = audioURL
                } else {
                    print("❌ Failed to extract audio URL from: \(url)")
                }
            }
        } else if url.isFileURL {
            // Handle direct file sharing (iOS share sheet)
            print("📁 Direct file URL: \(url)")
            deepLinkAudioURL = url
        }
    }
    
    private func checkForPausedTranscriptions() {
        if let pauseInfo = backgroundTaskManager.checkForPausedTranscription() {
            pausedMeetingInfo = pauseInfo
            showResumeAlert = true
        }
    }

    private func handleResumeTranscription(resume: Bool) {
        guard let info = pausedMeetingInfo,
              let meetingIdString = info["meetingId"] as? String,
              let meetingId = UUID(uuidString: meetingIdString) else {
            print("⚠️ [App] Invalid paused meeting info")
            return
        }

        if resume {
            print("▶️ [App] User chose to resume transcription for meeting \(meetingId)")
            // Clear pause state - CreateMeetingView will handle the resume
            _ = backgroundTaskManager.resumePausedTranscription(meetingId: meetingId)

            // Note: The actual resume logic will need to be handled in CreateMeetingView
            // when it detects the meeting is in a paused state
        } else {
            print("🚫 [App] User chose to cancel paused transcription")
            backgroundTaskManager.cancelPausedTranscription(meetingId: meetingId)
        }

        pausedMeetingInfo = nil
    }
}

extension URL {
    var queryParameters: [String: String] {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }
        
        var parameters: [String: String] = [:]
        for item in queryItems {
            parameters[item.name] = item.value
        }
        return parameters
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Register background tasks for transcription
        BackgroundTaskManager.shared.registerBackgroundTasks()

        // No third-party purchase SDK initialization needed for StoreKit 2

        return true
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
