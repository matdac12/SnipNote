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
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var localizationManager = LocalizationManager.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Action.self,
            Meeting.self,
            EveMessage.self,
            ChatConversation.self,
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
                Task {
                    // Initialize minutes manager - grant free tier if needed and refresh balance
                    await MinutesManager.shared.handleAppLaunch()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                BackgroundTaskManager.shared.handleScenePhaseChange(newPhase)
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
