//
//  OnboardingView.swift
//  SnipNote
//
//  Created by Claude on 17/09/25.
//

import SwiftUI
import AVFoundation
import AVFAudio
import UserNotifications

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @State private var currentPage = 0
    @State private var microphonePermissionGranted = false
    @State private var notificationPermissionGranted = false

    let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            // Page Indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index <= currentPage ? themeManager.currentTheme.accentColor : themeManager.currentTheme.secondaryTextColor.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                }
            }
            .padding(.top, 20)

            // Content
            TabView(selection: $currentPage) {
                WelcomeScreen()
                    .tag(0)

                RecordingTutorialScreen()
                    .tag(1)

                AIFeaturesScreen()
                    .tag(2)

                PermissionsScreen(
                    microphoneGranted: $microphonePermissionGranted,
                    notificationGranted: $notificationPermissionGranted
                )
                .tag(3)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.5), value: currentPage)

            // Navigation Buttons
            HStack {
                Button("Skip") {
                    completeOnboarding()
                }
                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                .opacity(currentPage < totalPages - 1 ? 1 : 0)

                Spacer()

                if currentPage < totalPages - 1 {
                    Button("Next") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage += 1
                        }
                    }
                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(themeManager.currentTheme.accentColor)
                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(themeManager.currentTheme.accentColor)
                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .themedBackground()
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismiss()
    }
}

struct WelcomeScreen: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App Icon or Illustration
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 80))
                .foregroundColor(themeManager.currentTheme.accentColor)
                .padding(.bottom, 20)

            VStack(spacing: 16) {
                Text("Welcome to SnipNote")
                    .themedTitle()
                    .multilineTextAlignment(.center)

                Text("AI-powered voice note taking with smart action extraction. Turn your meetings into actionable insights.")
                    .themedBody()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

struct RecordingTutorialScreen: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Animated Recording Visualization
            ZStack {
                Circle()
                    .stroke(themeManager.currentTheme.accentColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(themeManager.currentTheme.accentColor)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.8 : 1.0)

                Image(systemName: "mic.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }

            VStack(spacing: 16) {
                Text("Record Your Meetings")
                    .themedTitle()
                    .multilineTextAlignment(.center)

                Text("Tap the record button to capture audio from meetings, calls, or voice notes. SnipNote will automatically transcribe and analyze your content.")
                    .themedBody()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

struct AIFeaturesScreen: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // AI Icon
            Image(systemName: "wand.and.stars")
                .font(.system(size: 80))
                .foregroundColor(themeManager.currentTheme.accentColor)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)

            VStack(spacing: 16) {
                Text("AI-Powered Insights")
                    .themedTitle()
                    .multilineTextAlignment(.center)

                Text("Get automatic summaries, action item extraction, and smart organization. Focus on the conversation while SnipNote handles the notes.")
                    .themedBody()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Feature List
            VStack(alignment: .leading, spacing: 12) {
                OnboardingFeatureRow(icon: "doc.text", title: "Auto Transcription", description: "Accurate speech-to-text")
                OnboardingFeatureRow(icon: "sparkles", title: "AI Summaries", description: "Key points extracted")
                OnboardingFeatureRow(icon: "checklist", title: "Action Items", description: "Tasks identified automatically")
                OnboardingFeatureRow(icon: "magnifyingglass", title: "Smart Search", description: "Find content instantly")
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(themeManager.currentTheme.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .themedBody()
                    .fontWeight(.semibold)

                Text(description)
                    .themedCaption()
            }

            Spacer()
        }
    }
}

struct PermissionsScreen: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var microphoneGranted: Bool
    @Binding var notificationGranted: Bool

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 80))
                .foregroundColor(themeManager.currentTheme.accentColor)

            VStack(spacing: 16) {
                Text("Permissions Needed")
                    .themedTitle()
                    .multilineTextAlignment(.center)

                Text("To provide the best experience, SnipNote needs access to your microphone and permission to send notifications.")
                    .themedBody()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            VStack(spacing: 16) {
                PermissionCard(
                    icon: "mic.fill",
                    title: "Microphone Access",
                    description: "Required for recording meetings and voice notes",
                    isGranted: microphoneGranted,
                    action: requestMicrophonePermission
                )

                PermissionCard(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Get notified when processing is complete",
                    isGranted: notificationGranted,
                    action: requestNotificationPermission
                )
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                microphoneGranted = granted
            }
        }
    }

    private func requestNotificationPermission() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await MainActor.run {
                    notificationGranted = granted
                }
            } catch {
                print("Error requesting notification permission: \(error)")
                await MainActor.run {
                    notificationGranted = false
                }
            }
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isGranted ? .green : themeManager.currentTheme.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .themedBody()
                    .fontWeight(.semibold)

                Text(description)
                    .themedCaption()
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
            } else {
                Button("Continue") {
                    action()
                }
                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(themeManager.currentTheme.accentColor)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(themeManager.currentTheme.materialStyle)
        .cornerRadius(themeManager.currentTheme.cornerRadius)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(ThemeManager.shared)
}