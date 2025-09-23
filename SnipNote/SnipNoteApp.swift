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
    @State private var shouldNavigateToActions = false
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
            UserAIContext.self,
            MeetingFileState.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AuthenticationView(deepLinkAudioURL: $deepLinkAudioURL, shouldNavigateToActions: $shouldNavigateToActions)
                .environmentObject(themeManager)
                .environmentObject(localizationManager)
                .themed()
                .environment(\.locale, localizationManager.locale)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    Task {
                        await refreshNotificationsAndBadge()
                        // Initialize minutes manager - grant free tier if needed and refresh balance
                        await MinutesManager.shared.handleAppLaunch()
                    }
                    // Set up the navigation handler in app delegate
                    appDelegate.onNavigateToActions = {
                        shouldNavigateToActions = true
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
    
    @MainActor
    private func refreshNotificationsAndBadge() async {
        // Clear all pending notifications first
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Fetch all actions from the model container
        let descriptor = FetchDescriptor<Action>()
        do {
            let context = sharedModelContainer.mainContext
            let allActions = try context.fetch(descriptor)
            
            // Reschedule notifications based on current actions
            NotificationService.shared.scheduleNotification(with: allActions)
            // Update badge immediately based on current actions
            await NotificationService.shared.updateBadgeCount(with: allActions)
        } catch {
            print("Error refreshing notifications: \(error)")
            // If there's an error, clear the badge to be safe
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
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
    var onNavigateToActions: (() -> Void)?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        // No third-party purchase SDK initialization needed for StoreKit 2
        
        return true
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let navigateTo = userInfo["navigateTo"] as? String, navigateTo == "actions" {
            onNavigateToActions?()
        }
        
        completionHandler()
    }
}
