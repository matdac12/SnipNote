//
//  HomeView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 27/03/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @Binding var selectedTab: ContentView.Tab
    @Query(sort: \Meeting.dateCreated, order: .reverse) private var meetings: [Meeting]
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @StateObject private var minutesManager = MinutesManager.shared
    @StateObject private var storeManager = StoreManager.shared

    @State private var usageStats: UsageStats?
    @State private var showingPaywall = false
    @State private var createRoute: CreateMeetingRoute?
    @State private var showingFileImporter = false
    @State private var createdMeeting: Meeting?
    @State private var navigateToCreatedMeeting = false
    @State private var createMeetingActivityState: CreateMeetingActivityState = .idle

    private var theme: AppTheme { themeManager.currentTheme }

    private var recentMeetings: [Meeting] {
        Array(meetings.prefix(5))
    }

    private var transcribedCount: Int {
        meetings.filter { $0.processingState == .completed }.count
    }

    private var greetingKey: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "home.greeting.morning"
        case 12..<17: return "home.greeting.afternoon"
        default: return "home.greeting.evening"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // MARK: - Greeting Header
                    greetingHeader

                    // MARK: - KPI Cards
                    kpiCardsSection

                    // MARK: - Quick Actions
                    quickActionsSection

                    // MARK: - Recent Meetings
                    recentMeetingsSection
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .themedBackground()
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(meeting: meeting)
            }
            .navigationDestination(item: $createRoute) { route in
                CreateMeetingView(
                    onMeetingCreated: { meeting in
                        createdMeeting = meeting
                        navigateToCreatedMeeting = true
                        createRoute = nil
                        createMeetingActivityState = .idle
                    },
                    importedAudioRequest: route.importRequest,
                    onActivityStateChanged: { activityState in
                        createMeetingActivityState = activityState
                    }
                )
                .id(route.id)
            }
            .navigationDestination(isPresented: $navigateToCreatedMeeting) {
                if let meeting = createdMeeting {
                    MeetingDetailView(meeting: meeting)
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [UTType.audio],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
        .task {
            await minutesManager.refreshBalance()
        }
        .onAppear {
            Task {
                usageStats = await UsageTracker.shared.getMyUsageStats()
            }
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizationManager.localizedString(greetingKey))
                .font(.system(.largeTitle, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(theme.textColor)

            Text(Date().formatted(date: .complete, time: .omitted))
                .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - KPI Cards

    private var kpiCardsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                // Minutes Balance Card
                KPICard(
                    icon: "clock.fill",
                    title: localizationManager.localizedString("home.kpi.minutes_balance"),
                    value: minutesManager.formattedBalance,
                    badge: storeManager.hasActiveSubscription
                        ? localizationManager.localizedString("home.kpi.pro")
                        : localizationManager.localizedString("home.kpi.free"),
                    badgeColor: storeManager.hasActiveSubscription ? theme.accentColor : theme.secondaryTextColor,
                    isBadgeAccent: storeManager.hasActiveSubscription,
                    theme: theme
                )
                .onTapGesture {
                    showingPaywall = true
                }

                // Total Meetings Card
                KPICard(
                    icon: "doc.text.fill",
                    title: localizationManager.localizedString("home.kpi.total_meetings"),
                    value: "\(meetings.count)",
                    badge: "\(transcribedCount) \(localizationManager.localizedString("home.kpi.transcribed"))",
                    badgeColor: theme.secondaryTextColor,
                    isBadgeAccent: false,
                    theme: theme
                )

                // Meeting Time Card
                KPICard(
                    icon: "timer",
                    title: localizationManager.localizedString("home.kpi.meeting_time"),
                    value: usageStats?.formattedMeetingTime ?? "--",
                    badge: nil,
                    badgeColor: theme.secondaryTextColor,
                    isBadgeAccent: false,
                    theme: theme
                )
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        HStack(spacing: 14) {
            // Record — primary action, filled accent
            Button {
                createdMeeting = nil
                createMeetingActivityState = .idle
                createRoute = .blankDraft()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(localizationManager.localizedString("home.action.record"))
                        .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(theme.accentColor)
                .cornerRadius(theme.cornerRadius)
                .shadow(color: theme.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)

            // Import — secondary action, tinted background
            Button {
                showingFileImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                    Text(localizationManager.localizedString("home.action.import"))
                        .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                }
                .foregroundColor(theme.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(theme.accentColor.opacity(0.12))
                .cornerRadius(theme.cornerRadius)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Recent Meetings

    private var recentMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(localizationManager.localizedString("home.recent.title"))
                    .font(.system(.headline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.textColor)

                Spacer()

                if !meetings.isEmpty {
                    Button {
                        selectedTab = .meetings
                    } label: {
                        HStack(spacing: 4) {
                            Text(localizationManager.localizedString("home.recent.see_all"))
                                .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(theme.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            if recentMeetings.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundColor(theme.secondaryTextColor.opacity(0.4))

                    Text(localizationManager.localizedString("home.recent.empty"))
                        .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(theme.secondaryTextColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(theme.secondaryBackgroundColor)
                .cornerRadius(theme.cornerRadius)
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentMeetings.enumerated()), id: \.element.id) { index, meeting in
                        NavigationLink(value: meeting) {
                            HomeMeetingRow(
                                meeting: meeting,
                                theme: theme,
                                isLast: index == recentMeetings.count - 1
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(theme.secondaryBackgroundColor)
                .cornerRadius(theme.cornerRadius)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - File Import Handler

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Note: security-scoped access is managed by CreateMeetingView
            // which copies the file before releasing access
            let request = SharedAudioImportRequest(url: url, source: .fileShare)
            createdMeeting = nil
            createMeetingActivityState = .idle
            createRoute = .imported(request)

        case .failure(let error):
            print("❌ [Home] File import failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - KPI Card

private struct KPICard: View {
    let icon: String
    let title: String
    let value: String
    let badge: String?
    let badgeColor: Color
    let isBadgeAccent: Bool
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon with tinted pill background
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.accentColor)
                .padding(8)
                .background(theme.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer(minLength: 0)

            // Value — large and prominent
            Text(value)
                .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(theme.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Title label
            Text(title)
                .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(theme.secondaryTextColor)
                .lineLimit(1)

            // Badge pill
            if let badge = badge {
                Text(badge)
                    .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(isBadgeAccent ? .white : badgeColor)
                    .padding(.horizontal, isBadgeAccent ? 8 : 0)
                    .padding(.vertical, isBadgeAccent ? 3 : 0)
                    .background(isBadgeAccent ? theme.accentColor : Color.clear)
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
        }
        .frame(width: 140, alignment: .leading)
        .frame(minHeight: 136)
        .padding(16)
        .background(theme.secondaryBackgroundColor)
        .cornerRadius(theme.cornerRadius)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Home Meeting Row

private struct HomeMeetingRow: View {
    let meeting: Meeting
    let theme: AppTheme
    var isLast: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(meeting.name.isEmpty ? "Untitled Transcription" : meeting.name)
                    .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.textColor)
                    .lineLimit(1)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if meeting.isPausedLocalJob {
                        Text("Paused")
                            .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                            .foregroundColor(theme.warningColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.warningColor.opacity(0.12))
                            .clipShape(Capsule())
                    } else if meeting.isProcessing {
                        Text(meeting.isLocalJob ? "\(Int(meeting.displayedProgressPercent))%" : "Processing")
                            .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                            .foregroundColor(theme.warningColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.warningColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.secondaryTextColor.opacity(0.5))
                }
            }

            HStack(spacing: 0) {
                Text(meeting.dateCreated.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(theme.secondaryTextColor)

                if let preview = meeting.summaryPreview(maxLength: 80) {
                    Text(" \u{2022} ")
                        .font(.system(.caption))
                        .foregroundColor(theme.secondaryTextColor.opacity(0.5))

                    Text(preview)
                        .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(theme.secondaryTextColor)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(theme.backgroundColor.opacity(0.6))
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(for: [Action.self, Meeting.self, EveMessage.self, ChatConversation.self], inMemory: true)
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationManager.shared)
}
