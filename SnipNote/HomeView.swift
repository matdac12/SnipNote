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

    private var transcribedCount: Int {
        meetings.filter { $0.processingState == .completed }.count
    }

    /// The meeting currently being processed (or paused mid-processing), if any.
    private var activeMeeting: Meeting? {
        meetings.first { $0.isProcessing || $0.isPausedLocalJob }
    }

    /// The most recent finished meeting that has a one-line overview.
    private var latestOutcomeMeeting: Meeting? {
        meetings.first {
            $0.processingState == .completed
                && !$0.shortSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var activity: HomeActivity {
        HomeActivity(meetings: meetings)
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
                VStack(alignment: .leading, spacing: 14) {
                    let activity = self.activity

                    // MARK: - Greeting Header
                    greetingHeader
                        .padding(.bottom, 6)

                    // MARK: - Record + Streak
                    RecordStreakWidget(
                        activity: activity,
                        theme: theme,
                        localizationManager: localizationManager,
                        onRecord: startRecording,
                        onImport: { showingFileImporter = true }
                    )

                    // MARK: - Balance + Library
                    HStack(spacing: 14) {
                        Button {
                            showingPaywall = true
                        } label: {
                            BalanceWidget(
                                balance: minutesManager.currentBalance,
                                isPro: storeManager.hasActiveSubscription,
                                minutesLast30Days: activity.minutesLast30Days,
                                theme: theme,
                                localizationManager: localizationManager
                            )
                        }
                        .buttonStyle(.plain)

                        LibraryWidget(
                            meetingCount: meetings.count,
                            transcribedCount: transcribedCount,
                            meetingTime: usageStats?.formattedMeetingTime,
                            theme: theme,
                            localizationManager: localizationManager
                        )
                    }

                    // MARK: - In Progress
                    if let activeMeeting {
                        NavigationLink(value: activeMeeting) {
                            InProgressWidget(
                                meeting: activeMeeting,
                                theme: theme,
                                localizationManager: localizationManager
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: - Latest Outcome
                    if let latestOutcomeMeeting {
                        NavigationLink(value: latestOutcomeMeeting) {
                            LatestOutcomeWidget(
                                meeting: latestOutcomeMeeting,
                                theme: theme,
                                localizationManager: localizationManager
                            )
                        }
                        .buttonStyle(.plain)
                    } else if meetings.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
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
    }

    // MARK: - Empty State

    private var emptyState: some View {
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
        .homeWidgetBackground(theme)
    }

    // MARK: - Actions

    private func startRecording() {
        createdMeeting = nil
        createMeetingActivityState = .idle
        createRoute = .blankDraft()
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

// MARK: - Activity Data

/// Recording activity for the home widgets: a Monday-aligned 4-week grid of
/// minutes per day, the current recording streak, and recent usage.
struct HomeActivity {
    static let weekCount = 4

    struct Day: Identifiable {
        let date: Date
        let minutes: Double
        let hasMeeting: Bool
        let isToday: Bool
        let isFuture: Bool

        var id: Date { date }

        /// 0 = nothing recorded, 1...4 = increasing recorded minutes.
        var level: Int {
            guard hasMeeting else { return 0 }
            switch minutes {
            case ..<15: return 1
            case ..<45: return 2
            case ..<90: return 3
            default: return 4
            }
        }
    }

    /// Oldest first, `weekCount * 7` days, each row starting on Monday.
    let days: [Day]
    let streak: Int
    let recordedToday: Bool
    let minutesLast30Days: Double

    var weeks: [[Day]] {
        stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    init(meetings: [Meeting], now: Date = Date(), calendar: Calendar = .current) {
        var calendar = calendar
        calendar.firstWeekday = 2 // Monday

        let today = calendar.startOfDay(for: now)

        var minutesByDay: [Date: Double] = [:]
        for meeting in meetings {
            let day = calendar.startOfDay(for: meeting.dateCreated)
            minutesByDay[day, default: 0] += meeting.recordedSeconds / 60
        }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let gridStart = calendar.date(byAdding: .day, value: -7 * (Self.weekCount - 1), to: weekStart) ?? weekStart

        days = (0..<(Self.weekCount * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return Day(
                date: date,
                minutes: minutesByDay[date] ?? 0,
                hasMeeting: minutesByDay[date] != nil,
                isToday: date == today,
                isFuture: date > today
            )
        }

        recordedToday = minutesByDay[today] != nil

        // Count consecutive recording days ending today, or yesterday if
        // nothing has been recorded yet today (the streak is still alive).
        var streakCount = 0
        var cursor = recordedToday ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while minutesByDay[cursor] != nil {
            streakCount += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        streak = streakCount

        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        minutesLast30Days = meetings
            .filter { $0.dateCreated >= thirtyDaysAgo }
            .reduce(0) { $0 + $1.recordedSeconds / 60 }
    }
}

private extension Meeting {
    /// Recording length, falling back to the source audio length for imports.
    var recordedSeconds: Double {
        max(duration, sourceAudioDurationSeconds)
    }
}

// MARK: - Widget Chrome

private extension View {
    func homeWidgetBackground(_ theme: AppTheme) -> some View {
        self
            .background(theme.secondaryBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

private struct WidgetLabel: View {
    let text: String
    let color: Color
    let theme: AppTheme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: theme.useMonospacedFont ? .monospaced : .default))
            .tracking(0.5)
            .foregroundColor(color)
            .lineLimit(1)
    }
}

// MARK: - Record + Streak Widget

private struct RecordStreakWidget: View {
    let activity: HomeActivity
    let theme: AppTheme
    let localizationManager: LocalizationManager
    let onRecord: () -> Void
    let onImport: () -> Void

    private var design: Font.Design { theme.useMonospacedFont ? .monospaced : .default }

    private var streakText: String {
        if activity.streak == 0 {
            return localizationManager.localizedString("home.widget.streak.start")
        }
        if activity.recordedToday {
            return String(format: localizationManager.localizedString("home.widget.streak.active"), activity.streak)
        }
        return String(
            format: localizationManager.localizedString("home.widget.streak.keep"),
            activity.streak,
            activity.streak + 1
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Record (primary) and Import (secondary)
            VStack(alignment: .leading, spacing: 10) {
                Button(action: onRecord) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.22))
                            .clipShape(Circle())

                        Spacer(minLength: 0)

                        Text(localizationManager.localizedString("home.action.record"))
                            .font(.system(.subheadline, design: design, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onImport) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text(localizationManager.localizedString("home.action.import"))
                            .font(.system(.caption, design: design, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(.white)
            .padding(14)
            .frame(width: 136)
            .frame(maxHeight: .infinity)
            .background(theme.accentColor)

            // Right: last 4 weeks + streak
            VStack(alignment: .leading, spacing: 8) {
                WidgetLabel(
                    text: localizationManager.localizedString("home.widget.last_4_weeks"),
                    color: theme.secondaryTextColor,
                    theme: theme
                )

                ActivityGrid(activity: activity, theme: theme)

                Spacer(minLength: 0)

                Text(streakText)
                    .font(.system(.caption, design: design, weight: activity.streak > 0 ? .semibold : .regular))
                    .foregroundColor(activity.streak > 0 ? theme.accentColor : theme.secondaryTextColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 160)
        .homeWidgetBackground(theme)
    }
}

private struct ActivityGrid: View {
    let activity: HomeActivity
    let theme: AppTheme

    private func color(for day: HomeActivity.Day) -> Color {
        if day.isFuture { return theme.secondaryTextColor.opacity(0.06) }
        switch day.level {
        case 0: return theme.secondaryTextColor.opacity(0.15)
        case 1: return theme.accentColor.opacity(0.3)
        case 2: return theme.accentColor.opacity(0.55)
        case 3: return theme.accentColor.opacity(0.8)
        default: return theme.accentColor
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(activity.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(week) { day in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: day))
                            .frame(height: 14)
                            .overlay {
                                if day.isToday {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(theme.textColor, lineWidth: 1.5)
                                }
                            }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activity.days.filter(\.hasMeeting).count) recording days in the last 4 weeks")
    }
}

// MARK: - Balance Widget

private struct BalanceWidget: View {
    let balance: Int
    let isPro: Bool
    let minutesLast30Days: Double
    let theme: AppTheme
    let localizationManager: LocalizationManager

    private var design: Font.Design { theme.useMonospacedFont ? .monospaced : .default }

    /// How many weeks the balance lasts at the last 30 days' pace, if there is any usage.
    private var weeksLeft: Double? {
        let minutesPerWeek = minutesLast30Days / 30 * 7
        guard minutesPerWeek > 0 else { return nil }
        return Double(balance) / minutesPerWeek
    }

    /// The gauge is full when the balance covers four or more weeks.
    private var fill: Double {
        guard let weeksLeft else { return balance > 0 ? 1 : 0 }
        return min(1, max(0, weeksLeft / 4))
    }

    private var forecastText: String {
        guard let weeksLeft else {
            return localizationManager.localizedString("home.widget.balance.minutes")
        }
        let weeks = Int(weeksLeft.rounded())
        if weeksLeft < 1 {
            return localizationManager.localizedString("home.widget.balance.lasts_less")
        } else if weeks <= 1 {
            return localizationManager.localizedString("home.widget.balance.lasts_one")
        }
        return String(format: localizationManager.localizedString("home.widget.balance.lasts"), weeks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WidgetLabel(
                    text: localizationManager.localizedString("home.widget.balance"),
                    color: theme.secondaryTextColor,
                    theme: theme
                )
                Spacer(minLength: 4)
                WidgetLabel(
                    text: localizationManager.localizedString(isPro ? "home.kpi.pro" : "home.kpi.free"),
                    color: isPro ? theme.accentColor : theme.secondaryTextColor,
                    theme: theme
                )
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(theme.secondaryTextColor.opacity(0.15), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                Circle()
                    .trim(from: 0, to: 0.5 * fill)
                    .stroke(theme.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            }
            .rotationEffect(.degrees(180))
            .frame(width: 104, height: 104)
            .frame(height: 58, alignment: .top)
            .overlay(alignment: .bottom) {
                Text("\(balance)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(theme.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            Text(forecastText)
                .font(.system(.caption2, design: design))
                .foregroundColor(theme.secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .homeWidgetBackground(theme)
    }
}

// MARK: - Library Widget

private struct LibraryWidget: View {
    let meetingCount: Int
    let transcribedCount: Int
    let meetingTime: String?
    let theme: AppTheme
    let localizationManager: LocalizationManager

    private var design: Font.Design { theme.useMonospacedFont ? .monospaced : .default }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetLabel(
                text: localizationManager.localizedString("home.widget.library"),
                color: theme.secondaryTextColor,
                theme: theme
            )

            Spacer(minLength: 0)

            Text("\(meetingCount)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(theme.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("\(transcribedCount) \(localizationManager.localizedString("home.kpi.transcribed"))")
                .font(.system(.caption, design: design))
                .foregroundColor(theme.secondaryTextColor)
                .lineLimit(1)

            if let meetingTime {
                Text(meetingTime)
                    .font(.system(.caption, design: design))
                    .foregroundColor(theme.secondaryTextColor)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .homeWidgetBackground(theme)
    }
}

// MARK: - In Progress Widget

private struct InProgressWidget: View {
    let meeting: Meeting
    let theme: AppTheme
    let localizationManager: LocalizationManager

    private var design: Font.Design { theme.useMonospacedFont ? .monospaced : .default }

    private static let stepKeys = [
        "home.widget.step.prepare",
        "home.widget.step.transcribe",
        "home.widget.step.overview",
        "home.widget.step.summary"
    ]

    /// Index into `stepKeys` for the meeting's current (or resumable) phase.
    private var currentStep: Int {
        let phase = (meeting.processingPhase == .paused || meeting.processingPhase == .failed)
            ? meeting.resumePhase
            : meeting.processingPhase
        switch phase {
        case .queued, .preparing: return 0
        case .transcribing: return 1
        case .generatingOverview: return 2
        case .generatingSummary: return 3
        case .completed: return 4
        default:
            // Server jobs report progress through processingState only.
            switch meeting.processingState {
            case .transcribing: return 1
            case .generatingSummary: return 3
            default: return 0
            }
        }
    }

    private var statusColor: Color {
        meeting.isPausedLocalJob ? theme.secondaryTextColor : theme.warningColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WidgetLabel(
                    text: localizationManager.localizedString(
                        meeting.isPausedLocalJob ? "home.widget.paused" : "home.widget.in_progress"
                    ),
                    color: theme.secondaryTextColor,
                    theme: theme
                )
                Spacer(minLength: 4)
                if meeting.displayedProgressPercent > 0 {
                    Text("\(Int(meeting.displayedProgressPercent))%")
                        .font(.system(.caption2, design: design, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Text(meeting.name.isEmpty ? "Untitled Transcription" : meeting.name)
                .font(.system(.subheadline, design: design, weight: .semibold))
                .foregroundColor(theme.textColor)
                .lineLimit(1)
                .padding(.top, 2)

            HStack(spacing: 4) {
                ForEach(Self.stepKeys.indices, id: \.self) { index in
                    Capsule()
                        .fill(index < currentStep
                              ? theme.accentColor
                              : index == currentStep ? theme.accentColor.opacity(0.4) : theme.secondaryTextColor.opacity(0.15))
                        .frame(height: 4)
                }
            }
            .padding(.top, 6)

            HStack(spacing: 4) {
                ForEach(Self.stepKeys.indices, id: \.self) { index in
                    Text(localizationManager.localizedString(Self.stepKeys[index]))
                        .font(.system(size: 10, weight: index == currentStep ? .semibold : .regular, design: design))
                        .foregroundColor(index == currentStep ? theme.textColor : theme.secondaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeWidgetBackground(theme)
    }
}

// MARK: - Latest Outcome Widget

private struct LatestOutcomeWidget: View {
    let meeting: Meeting
    let theme: AppTheme
    let localizationManager: LocalizationManager

    private var design: Font.Design { theme.useMonospacedFont ? .monospaced : .default }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetLabel(
                    text: localizationManager.localizedString("home.widget.latest_outcome"),
                    color: theme.secondaryTextColor,
                    theme: theme
                )
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.secondaryTextColor.opacity(0.5))
            }

            Text(meeting.shortSummary.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(.subheadline, design: design, weight: .medium))
                .foregroundColor(theme.textColor)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(meeting.name.isEmpty ? "Untitled Transcription" : meeting.name) · \(meeting.dateCreated.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(.caption, design: design))
                .foregroundColor(theme.secondaryTextColor)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeWidgetBackground(theme)
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(for: [Meeting.self], inMemory: true)
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationManager.shared)
}
