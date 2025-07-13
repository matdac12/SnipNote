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

@main
struct SnipNoteApp: App {
    @State private var deepLinkAudioURL: URL?
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Note.self,
            Action.self,
            Meeting.self,
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
            ContentView(deepLinkAudioURL: $deepLinkAudioURL)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    Task {
                        await refreshNotificationsAndBadge()
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
