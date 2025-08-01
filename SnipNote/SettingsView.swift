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
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var showingPermissionAlert = false
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingTimeSheet = false
    @State private var showingLogoutConfirmation = false
    @State private var usageStats: UsageStats?
    @State private var isLoadingStats = false
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text(themeManager.currentTheme.headerStyle == .brackets ? "[ SETTINGS ]" : "Settings")
                    .themedTitle()
                Spacer()
            }
            .padding()
            .background(themeManager.currentTheme.materialStyle)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // APPEARANCE SECTION
                    VStack(alignment: .leading, spacing: 16) {
                        Text("APPEARANCE")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Theme")
                                    .themedBody()
                                    .fontWeight(.bold)
                                
                                Spacer()
                                
                                Picker("Theme", selection: $themeManager.themeType) {
                                    ForEach(ThemeType.allCases, id: \.self) { theme in
                                        Text(theme.rawValue)
                                            .tag(theme)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(width: 150)
                            }
                            
                            Text(themeManager.themeType == .light ? "Clean and modern interface for everyday use" : "Terminal-style interface for power users")
                                .themedCaption()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("NOTIFICATIONS")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Daily Reminders")
                                        .themedBody()
                                        .fontWeight(.bold)
                                    Text("Get notified about high priority actions")
                                        .themedCaption()
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $notificationService.isNotificationEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: themeManager.currentTheme.accentColor))
                                    .onChange(of: notificationService.isNotificationEnabled) { _, newValue in
                                        handleNotificationToggle(newValue)
                                    }
                            }
                            
                            if notificationService.isNotificationEnabled {
                                HStack {
                                    Text("Notification Time")
                                        .themedBody()
                                        .fontWeight(.bold)
                                    
                                    Spacer()
                                    
                                    Button(action: { showingTimeSheet = true }) {
                                        Text(DateFormatter.timeFormatter.string(from: notificationService.notificationTime))
                                            .themedBody()
                                            .foregroundColor(themeManager.currentTheme.accentColor)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .overlay(
                                                Rectangle()
                                                    .stroke(themeManager.currentTheme.accentColor, lineWidth: 1)
                                            )
                                    }
                                }
                                
                                HStack {
                                    Text("Permission Status")
                                        .themedBody()
                                        .fontWeight(.bold)
                                    
                                    Spacer()
                                    
                                    Text(permissionStatusText)
                                        .themedCaption()
                                        .fontWeight(.bold)
                                        .foregroundColor(permissionStatusColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(permissionStatusColor.opacity(0.2))
                                        .cornerRadius(3)
                                }
                            }
                        }
                        .padding()
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("STATISTICS")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        
                        VStack(spacing: 12) {
                            StatRow(label: "Total Actions", value: "\(actions.count)")
                            StatRow(label: "Pending", value: "\(actions.filter { !$0.isCompleted }.count)")
                            StatRow(label: "Completed", value: "\(actions.filter { $0.isCompleted }.count)")
                            StatRow(label: "High Priority", value: "\(actions.filter { $0.priority == .high && !$0.isCompleted }.count)")
                        }
                        .padding()
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("USAGE")
                                .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                            
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
                                        .themedBody()
                                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ACCOUNT")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        
                        VStack(spacing: 12) {
                            if let email = authManager.currentUser?.email {
                                HStack {
                                    Text("Email")
                                        .themedBody()
                                    
                                    Spacer()
                                    
                                    Text(email)
                                        .themedBody()
                                        .fontWeight(.bold)
                                        .foregroundColor(themeManager.currentTheme.accentColor)
                                }
                            }
                            
                            Button(action: { showingLogoutConfirmation = true }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("LOG OUT")
                                        .themedBody()
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(themeManager.currentTheme.destructiveColor.opacity(0.2))
                                .foregroundColor(themeManager.currentTheme.destructiveColor)
                                .cornerRadius(themeManager.currentTheme.cornerRadius)
                            }
                        }
                        .padding()
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ABOUT")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SnipNote v1.0")
                                .themedBody()
                                .fontWeight(.bold)
                            Text("AI-powered voice note taking with smart action extraction")
                                .themedCaption()
                                .lineLimit(2)
                        }
                        .padding()
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                    }
                }
                .padding()
            }
        }
        .themedBackground()
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
        case .authorized: return themeManager.currentTheme.accentColor
        case .denied: return themeManager.currentTheme.destructiveColor
        case .provisional: return themeManager.currentTheme.warningColor
        case .ephemeral: return themeManager.currentTheme.warningColor
        case .notDetermined: return themeManager.currentTheme.secondaryTextColor
        @unknown default: return themeManager.currentTheme.secondaryTextColor
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
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack {
            Text(label)
                .themedBody()
            
            Spacer()
            
            Text(value)
                .themedBody()
                .fontWeight(.bold)
                .foregroundColor(themeManager.currentTheme.accentColor)
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
            .themedBackground()
            .navigationTitle("Notification Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(ThemeManager.shared.currentTheme.destructiveColor)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onTimeSelected(selectedTime)
                        dismiss()
                    }
                    .foregroundColor(ThemeManager.shared.currentTheme.accentColor)
                }
            }
        }
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