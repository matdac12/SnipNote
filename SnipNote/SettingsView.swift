//
//  SettingsView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationService = NotificationService.shared
    @Query private var actions: [Action]
    @EnvironmentObject var authManager: AuthenticationManager
    
    @State private var showingPermissionAlert = false
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingTimeSheet = false
    @State private var showingLogoutConfirmation = false
    @State private var usageStats: UsageStats?
    @State private var isLoadingStats = false
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text("[ SETTINGS ]")
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .foregroundColor(.green)
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("NOTIFICATIONS")
                            .font(.system(.headline, design: .monospaced, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Daily Reminders")
                                        .font(.system(.body, design: .monospaced, weight: .bold))
                                    Text("Get notified about high priority actions")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $notificationService.isNotificationEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: .green))
                                    .onChange(of: notificationService.isNotificationEnabled) { _, newValue in
                                        handleNotificationToggle(newValue)
                                    }
                            }
                            
                            if notificationService.isNotificationEnabled {
                                HStack {
                                    Text("Notification Time")
                                        .font(.system(.body, design: .monospaced, weight: .bold))
                                    
                                    Spacer()
                                    
                                    Button(action: { showingTimeSheet = true }) {
                                        Text(DateFormatter.timeFormatter.string(from: notificationService.notificationTime))
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .overlay(
                                                Rectangle()
                                                    .stroke(.blue, lineWidth: 1)
                                            )
                                    }
                                }
                                
                                HStack {
                                    Text("Permission Status")
                                        .font(.system(.body, design: .monospaced, weight: .bold))
                                    
                                    Spacer()
                                    
                                    Text(permissionStatusText)
                                        .font(.system(.caption, design: .monospaced, weight: .bold))
                                        .foregroundColor(permissionStatusColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(permissionStatusColor.opacity(0.2))
                                        .cornerRadius(3)
                                }
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("STATISTICS")
                            .font(.system(.headline, design: .monospaced, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            StatRow(label: "Total Actions", value: "\(actions.count)")
                            StatRow(label: "Pending", value: "\(actions.filter { !$0.isCompleted }.count)")
                            StatRow(label: "Completed", value: "\(actions.filter { $0.isCompleted }.count)")
                            StatRow(label: "High Priority", value: "\(actions.filter { $0.priority == .high && !$0.isCompleted }.count)")
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("USAGE")
                                .font(.system(.headline, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if isLoadingStats {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                        
                        VStack(spacing: 12) {
                            if let stats = usageStats {
                                StatRow(label: "Notes Created", value: "\(stats.totalNotes)")
                                StatRow(label: "Notes Transcribed", value: "\(stats.totalNotesTranscribed)")
                                StatRow(label: "Meetings Created", value: "\(stats.totalMeetings)")
                                StatRow(label: "Meetings Transcribed", value: "\(stats.totalMeetingsTranscribed)")
                                StatRow(label: "Total Recording Time", value: "\(stats.formattedTranscriptionTime)")
                                StatRow(label: "AI Summaries", value: "\(stats.totalAiSummaries)")
                                StatRow(label: "Actions Extracted", value: "\(stats.totalAiActionsExtracted)")
                            } else {
                                HStack {
                                    Spacer()
                                    Text("Loading usage data...")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ACCOUNT")
                            .font(.system(.headline, design: .monospaced, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            if let email = authManager.currentUser?.email {
                                HStack {
                                    Text("Email")
                                        .font(.system(.body, design: .monospaced))
                                    
                                    Spacer()
                                    
                                    Text(email)
                                        .font(.system(.body, design: .monospaced, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            }
                            
                            Button(action: { showingLogoutConfirmation = true }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("LOG OUT")
                                        .font(.system(.body, design: .monospaced, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ABOUT")
                            .font(.system(.headline, design: .monospaced, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SnipNote v1.0")
                                .font(.system(.body, design: .monospaced, weight: .bold))
                            Text("AI-powered voice note taking with smart action extraction")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .background(.black)
        .sheet(isPresented: $showingTimeSheet) {
            TimePickerSheet(selectedTime: $notificationService.notificationTime) { time in
                notificationService.updateNotificationSettings(
                    enabled: notificationService.isNotificationEnabled,
                    time: time
                )
                updateNotifications()
            }
        }
        .alert("Notification Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) {
                notificationService.isNotificationEnabled = false
                notificationService.updateNotificationSettings(enabled: false, time: notificationService.notificationTime)
            }
        } message: {
            Text("Please enable notifications in Settings to receive daily reminders about your high priority actions.")
        }
        .alert("Log Out", isPresented: $showingLogoutConfirmation) {
            Button("Log Out", role: .destructive) {
                Task {
                    try? await authManager.signOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to log out? You'll need to sign in again to use the app.")
        }
        .onAppear {
            checkPermissionStatus()
            updateNotifications()
            fetchUsageStats()
        }
    }
    
    private var permissionStatusText: String {
        switch permissionStatus {
        case .authorized: return "ENABLED"
        case .denied: return "DENIED"
        case .provisional: return "PROVISIONAL"
        case .ephemeral: return "EPHEMERAL"
        case .notDetermined: return "NOT SET"
        @unknown default: return "UNKNOWN"
        }
    }
    
    private var permissionStatusColor: Color {
        switch permissionStatus {
        case .authorized: return .green
        case .denied: return .red
        case .provisional: return .orange
        case .ephemeral: return .orange
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }
    
    private func handleNotificationToggle(_ enabled: Bool) {
        if enabled {
            Task {
                let permission = await notificationService.requestNotificationPermission()
                await MainActor.run {
                    if permission {
                        notificationService.updateNotificationSettings(enabled: true, time: notificationService.notificationTime)
                        updateNotifications()
                    } else {
                        showingPermissionAlert = true
                    }
                    checkPermissionStatus()
                }
            }
        } else {
            notificationService.updateNotificationSettings(enabled: false, time: notificationService.notificationTime)
            notificationService.cancelAllNotifications()
        }
    }
    
    private func checkPermissionStatus() {
        Task {
            let status = await notificationService.checkNotificationPermission()
            await MainActor.run {
                permissionStatus = status
            }
        }
    }
    
    private func updateNotifications() {
        guard notificationService.isNotificationEnabled else { return }
        notificationService.scheduleNotification(with: actions)
    }
    
    private func fetchUsageStats() {
        isLoadingStats = true
        Task {
            let stats = await UsageTracker.shared.getMyUsageStats()
            await MainActor.run {
                self.usageStats = stats
                self.isLoadingStats = false
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .monospaced))
            
            Spacer()
            
            Text(value)
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundColor(.green)
        }
    }
}

struct TimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTime: Date
    let onTimeSelected: (Date) -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Notification Time",
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                
                Spacer()
            }
            .padding()
            .background(.black)
            .navigationTitle("Notification Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onTimeSelected(selectedTime)
                        dismiss()
                    }
                    .foregroundColor(.green)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    SettingsView()
        .modelContainer(for: [Note.self, Action.self], inMemory: true)
}