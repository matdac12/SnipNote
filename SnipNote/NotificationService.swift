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
            return "You have 1 high priority action: \(actions.first!.title)"
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
    
    func updateBadgeCount(with actions: [Action]) async {
        let highPriorityCount = actions.filter { $0.priority == .high && !$0.isCompleted }.count
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(highPriorityCount)
        } catch {
            print("Error updating badge count: \(error)")
        }
    }
}