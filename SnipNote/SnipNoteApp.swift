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

/// Observer that updates ThemeManager when system color scheme changes
struct SystemColorSchemeObserver<Content: View>: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject var themeManager: ThemeManager
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .onChange(of: systemColorScheme) { _, newScheme in
                themeManager.handleSystemColorSchemeChange(newScheme)
            }
            .onAppear {
                // Initialize with current system color scheme
                themeManager.handleSystemColorSchemeChange(systemColorScheme)
            }
    }
}

@main
struct SnipNoteApp: App {
    @State private var sharedAudioImportRequest: SharedAudioImportRequest?
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var themeManager: ThemeManager
    @StateObject private var localizationManager: LocalizationManager

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--analysis-preview") {
            let environment = ProcessInfo.processInfo.environment
            _themeManager = StateObject(wrappedValue: ThemeManager(previewTheme: environment["SNIPNOTE_ANALYSIS_APPEARANCE"] == "dark" ? DarkTheme() : LightTheme()))
            _localizationManager = StateObject(wrappedValue: LocalizationManager(previewLanguageCode: environment["SNIPNOTE_ANALYSIS_LANGUAGE"] ?? "en"))
            return
        }
#endif
        _themeManager = StateObject(wrappedValue: ThemeManager.shared)
        _localizationManager = StateObject(wrappedValue: LocalizationManager.shared)
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Meeting.self,
        ])
#if DEBUG
        let preview = ProcessInfo.processInfo.arguments.contains("--analysis-preview")
#else
        let preview = false
#endif
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: preview)

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
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--analysis-preview") {
                let environment = ProcessInfo.processInfo.environment
                AnalysisPreviewHostView(stage: environment["SNIPNOTE_ANALYSIS_STAGE"] ?? "preparing",
                    language: environment["SNIPNOTE_ANALYSIS_LANGUAGE"] ?? "en",
                    dark: environment["SNIPNOTE_ANALYSIS_APPEARANCE"] == "dark",
                    largeText: environment["SNIPNOTE_ANALYSIS_LARGE_TEXT"] == "1",
                    reduceMotion: environment["SNIPNOTE_ANALYSIS_REDUCE_MOTION"] == "1")
            } else {
                productionRoot
            }
#else
            productionRoot
#endif
        }
        .modelContainer(sharedModelContainer)
    }

    private var productionRoot: some View {
            SystemColorSchemeObserver {
                AuthenticationView(sharedAudioImportRequest: $sharedAudioImportRequest)
            }
            .environmentObject(themeManager)
            .environmentObject(localizationManager)
            .themed()
            .environment(\.locale, localizationManager.locale)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onAppear {
                _ = StoreManager.shared
                Task {
                    // Initialize minutes manager - grant free tier if needed and refresh balance
                    await MinutesManager.shared.handleAppLaunch()
                }
                checkForSharedAudio()
            }
            .onChange(of: scenePhase) { _, newPhase in
                BackgroundTaskManager.shared.handleScenePhaseChange(newPhase)
                if newPhase == .active {
                    checkForSharedAudio()
                    if let user = SupabaseManager.shared.client.auth.currentUser?.id {
                        Task { await BackgroundUploadReconciler.shared.activate(context: sharedModelContainer.mainContext, userID: user) }
                    }
                } else {
                    BackgroundUploadReconciler.shared.stop()
                }
            }
    }
    
    private static let appGroupID = "group.com.mattianalytics.snipnote"

    private func handleDeepLink(_ url: URL) {
        print("📱 Deep link received: \(url)")

        if url.scheme == "snipnote" {
            if url.host == "import-shared-audio" {
                // Triggered by Share Extension — read from shared container
                print("🎵 Share Extension triggered, checking shared container...")
                checkForSharedAudio()
            } else if url.host == "import-audio" {
                if let audioURLString = url.queryParameters["audioURL"],
                   let audioURL = URL(string: audioURLString) {
                    print("🎵 Audio URL extracted: \(audioURL)")
                    sharedAudioImportRequest = SharedAudioImportRequest(
                        url: audioURL,
                        source: .deepLink
                    )
                } else {
                    print("❌ Failed to extract audio URL from: \(url)")
                }
            }
        } else if url.isFileURL {
            // Handle direct file sharing (iOS share sheet)
            print("📁 Direct file URL: \(url)")
            sharedAudioImportRequest = SharedAudioImportRequest(
                url: url,
                source: .fileShare
            )
        }
    }

    private func checkForSharedAudio() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else { return }

        let flagFile = containerURL.appendingPathComponent("pending_audio.txt")

        guard let filename = try? String(contentsOf: flagFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !filename.isEmpty else {
            return
        }

        let audioURL = containerURL.appendingPathComponent("SharedAudio").appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("⚠️ Pending audio file not found: \(filename)")
            try? FileManager.default.removeItem(at: flagFile)
            return
        }

        // Remove the flag so we don't re-import
        try? FileManager.default.removeItem(at: flagFile)

        print("📂 ✅ Found shared audio: \(filename)")
        sharedAudioImportRequest = SharedAudioImportRequest(
            url: audioURL,
            source: .fileShare
        )
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
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--analysis-preview") { return true }
#endif
        UNUserNotificationCenter.current().delegate = self

        // Register background tasks for transcription
        BackgroundTaskManager.shared.registerBackgroundTasks()

        // No third-party purchase SDK initialization needed for StoreKit 2

        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        BackgroundUploadCoordinator.shared.handleBackgroundEvents(identifier: identifier, completion: completionHandler)
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
