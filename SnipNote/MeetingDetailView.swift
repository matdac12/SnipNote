//
//  MeetingDetailView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct MeetingDetailView: View {
    @StateObject private var analysisUploads: AnalysisUploadObservation
    private var backgroundUploads: BackgroundUploadCoordinator { .shared }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var meeting: Meeting
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject private var localization: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var lastAnalysisPresentation: AnalysisPresentation?
    @State private var showedAcceptedServer = false

    @State private var isEditingName = false
    @State private var tempName = ""
    @State private var showingNotes = true
    @State private var showingOverview = true
    @State private var showingTranscript = false
    @State private var showingSummary = true
    @State private var showingFullScreenSummary = false
    @State private var showingFullScreenTranscript = false

    // Retry functionality
    @State private var isRetrying = false
    @StateObject private var minutesManager = MinutesManager.shared

    // Force refresh for processing updates
    @State private var refreshTrigger = false

    // PDF / Word export
    @State private var isExporting = false
    @State private var exportErrorMessage: String?

    // Async job tracking
    @State private var jobId: String?
    @State private var jobStatus: JobStatus?
    @State private var jobErrorMessage: String?
    @State private var jobProgress: Int = 0
    @State private var jobStage: String = ""
    @State private var jobPollingTask: Task<Void, Never>?
    @StateObject private var transcriptionService = RenderTranscriptionService()

#if DEBUG
    private var analysisPreview: AnalysisPresentationInput? = nil
    init(meeting: Meeting, analysisPreview: AnalysisPresentationInput) {
        self.meeting = meeting
        self.analysisPreview = analysisPreview
        _analysisUploads = StateObject(wrappedValue: AnalysisUploadObservation(coordinator: nil))
    }
#endif

    init(meeting: Meeting) {
        self.meeting = meeting
        _analysisUploads = StateObject(wrappedValue: AnalysisUploadObservation(coordinator: .shared))
    }

    private var isAnalysisPreview: Bool {
#if DEBUG
        return analysisPreview != nil
#else
        return false
#endif
    }

#if DEBUG
  @Environment(\.analysisPreviewReduceMotion) private var previewReduceMotion
#endif
  private var reduceMotion: Bool {
#if DEBUG
    return previewReduceMotion ?? systemReduceMotion
#else
    return systemReduceMotion
#endif
  }

    private var theme: AppTheme {
        themeManager.currentTheme
    }
    
    var body: some View {
        VStack(spacing: 0) {
            meetingHeaderView

            ScrollView {
                if meeting.isProcessing || isRetrying || meeting.isPausedLocalJob || (usesQuietAnalysis && meeting.processingState == .failed) {
                    processingStatusSection
                        .padding(usesQuietAnalysis ? 0 : 16)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        if !meeting.meetingNotes.isEmpty {
                            meetingNotesSection
                        }

                        if meeting.hasPendingMinutesDebit {
                            minutesSyncNoticeCard
                        }

                        overviewSection
                        summarySection
                        transcriptSection
                    }
                    .padding()
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: meeting.processingState == .completed)
            .refreshable {
                await refreshJobStatus()
            }
        }
        .background(theme.backgroundColor)
        .foregroundColor(themeManager.currentTheme.accentColor)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            toolbarContent
        }
        .alert(
            LocalizedStringKey("export.error.title"),
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .onChange(of: analysisPresentation) { _, value in
            if value.canLeave { showedAcceptedServer = true }
            if value.phase == .foreground { showedAcceptedServer = false }
            lastAnalysisPresentation = value
        }
        .onAppear {
            lastAnalysisPresentation = analysisPresentation
            showedAcceptedServer = analysisPresentation.canLeave
            tempName = meeting.name
        }
        .task {
            guard !isAnalysisPreview else { return }
            // Continuously refresh meeting data - start immediately to catch stale data
            let meetingId = meeting.id

            // Always fetch fresh data first, even if meeting.isProcessing is false
            await MainActor.run {
                let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate<Meeting> { $0.id == meetingId })
                if let fetchedMeeting = try? modelContext.fetch(descriptor).first {
                    let hasChanged =
                        meeting.lastProcessedChunk != fetchedMeeting.lastProcessedChunk ||
                        meeting.totalChunks != fetchedMeeting.totalChunks ||
                        meeting.processingStateRaw != fetchedMeeting.processingStateRaw ||
                        meeting.processingPhaseRaw != fetchedMeeting.processingPhaseRaw ||
                        meeting.progressPercent != fetchedMeeting.progressPercent ||
                        meeting.currentStageDescription != fetchedMeeting.currentStageDescription ||
                        meeting.processingError != fetchedMeeting.processingError ||
                        meeting.hasPendingMinutesDebit != fetchedMeeting.hasPendingMinutesDebit ||
                        meeting.pendingMinutesDebitError != fetchedMeeting.pendingMinutesDebitError ||
                        meeting.pauseReason != fetchedMeeting.pauseReason ||
                        meeting.pausedAt != fetchedMeeting.pausedAt ||
                        meeting.audioTranscript != fetchedMeeting.audioTranscript ||
                        meeting.shortSummary != fetchedMeeting.shortSummary ||
                        meeting.aiSummary != fetchedMeeting.aiSummary

                    guard hasChanged else { return }

                    meeting.lastProcessedChunk = fetchedMeeting.lastProcessedChunk
                    meeting.totalChunks = fetchedMeeting.totalChunks
                    meeting.processingStateRaw = fetchedMeeting.processingStateRaw
                    meeting.processingPhaseRaw = fetchedMeeting.processingPhaseRaw
                    meeting.progressPercent = fetchedMeeting.progressPercent
                    meeting.currentStageDescription = fetchedMeeting.currentStageDescription
                    meeting.processingError = fetchedMeeting.processingError
                    meeting.hasPendingMinutesDebit = fetchedMeeting.hasPendingMinutesDebit
                    meeting.pendingMinutesDebitError = fetchedMeeting.pendingMinutesDebitError
                    meeting.pauseReason = fetchedMeeting.pauseReason
                    meeting.pausedAt = fetchedMeeting.pausedAt
                    meeting.resumePhaseRaw = fetchedMeeting.resumePhaseRaw
                    meeting.audioTranscript = fetchedMeeting.audioTranscript
                    meeting.shortSummary = fetchedMeeting.shortSummary
                    meeting.aiSummary = fetchedMeeting.aiSummary
                    refreshTrigger.toggle()

#if DEBUG
                    print("🔄 [MeetingDetail] Initial sync - chunks: \(fetchedMeeting.lastProcessedChunk)/\(fetchedMeeting.totalChunks), \(fetchedMeeting.progressPercentage)%")
#endif
                }
            }

            // Now continue polling if processing
            while meeting.isProcessing {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                await MainActor.run {
                    let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate<Meeting> { $0.id == meetingId })
                    if let fetchedMeeting = try? modelContext.fetch(descriptor).first {
                        let hasChanged =
                            meeting.lastProcessedChunk != fetchedMeeting.lastProcessedChunk ||
                            meeting.totalChunks != fetchedMeeting.totalChunks ||
                            meeting.processingStateRaw != fetchedMeeting.processingStateRaw ||
                            meeting.processingPhaseRaw != fetchedMeeting.processingPhaseRaw ||
                            meeting.progressPercent != fetchedMeeting.progressPercent ||
                            meeting.currentStageDescription != fetchedMeeting.currentStageDescription ||
                            meeting.processingError != fetchedMeeting.processingError ||
                            meeting.hasPendingMinutesDebit != fetchedMeeting.hasPendingMinutesDebit ||
                            meeting.pendingMinutesDebitError != fetchedMeeting.pendingMinutesDebitError ||
                            meeting.pauseReason != fetchedMeeting.pauseReason ||
                            meeting.pausedAt != fetchedMeeting.pausedAt ||
                            meeting.audioTranscript != fetchedMeeting.audioTranscript ||
                            meeting.shortSummary != fetchedMeeting.shortSummary ||
                            meeting.aiSummary != fetchedMeeting.aiSummary

                        guard hasChanged else { return }

                        meeting.lastProcessedChunk = fetchedMeeting.lastProcessedChunk
                        meeting.totalChunks = fetchedMeeting.totalChunks
                        meeting.processingStateRaw = fetchedMeeting.processingStateRaw
                        meeting.processingPhaseRaw = fetchedMeeting.processingPhaseRaw
                        meeting.progressPercent = fetchedMeeting.progressPercent
                        meeting.currentStageDescription = fetchedMeeting.currentStageDescription
                        meeting.processingError = fetchedMeeting.processingError
                        meeting.hasPendingMinutesDebit = fetchedMeeting.hasPendingMinutesDebit
                        meeting.pendingMinutesDebitError = fetchedMeeting.pendingMinutesDebitError
                        meeting.pauseReason = fetchedMeeting.pauseReason
                        meeting.pausedAt = fetchedMeeting.pausedAt
                        meeting.resumePhaseRaw = fetchedMeeting.resumePhaseRaw
                        meeting.audioTranscript = fetchedMeeting.audioTranscript
                        meeting.shortSummary = fetchedMeeting.shortSummary
                        meeting.aiSummary = fetchedMeeting.aiSummary
                        refreshTrigger.toggle()

#if DEBUG
                        print("🔄 [MeetingDetail] Poll - chunks: \(fetchedMeeting.lastProcessedChunk)/\(fetchedMeeting.totalChunks), \(fetchedMeeting.progressPercentage)%")
#endif
                    }
                }
            }

#if DEBUG
            print("✅ [MeetingDetail] Processing complete, stopped polling")
#endif
        }
        .task {
            guard !isAnalysisPreview else { return }
            await updatePollingTask(for: meeting.transcriptionJobId)
        }
        .onChange(of: meeting.transcriptionJobId) { _, newValue in
            Task {
                await updatePollingTask(for: newValue)
            }
        }
        .onDisappear {
            jobPollingTask?.cancel()
            jobPollingTask = nil
        }
        .sheet(isPresented: $showingFullScreenSummary) {
            fullScreenSummaryView
        }
        .sheet(isPresented: $showingFullScreenTranscript) {
            fullScreenTranscriptView
        }
    }

    // MARK: - Header View
    
    private var meetingHeaderView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if isEditingName {
                        TextField("Transcription Name", text: $tempName)
                            .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .textFieldStyle(PlainTextFieldStyle())
                            .onSubmit {
                                saveName()
                            }
                    } else {
                        Text(getMeetingTitle())
                            .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .lineLimit(2)
                            .onTapGesture {
                                startEditingName()
                            }
                    }

                    HStack(spacing: 16) {
                        if !meeting.location.isEmpty {
                            Text("📍 \(meeting.location)")
                                .font(.caption).foregroundStyle(theme.secondaryTextColor)
                        }

                        if meeting.duration > 0 {
                            Text("⏱️ \(meeting.durationFormatted)")
                                .font(.caption).foregroundStyle(theme.secondaryTextColor)
                        }
                    }
                }

                Spacer()

                Text(meeting.dateCreated, style: .date)
                    .font(.caption).foregroundStyle(theme.secondaryTextColor)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, 13)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Divider line like CreateMeetingView
            Rectangle()
                .fill(themeManager.currentTheme.secondaryTextColor.opacity(0.1))
                .frame(height: 1)
        }
        .background(
            LinearGradient(
                colors: [
                    themeManager.currentTheme.secondaryBackgroundColor.opacity(0.9),
                    themeManager.currentTheme.backgroundColor
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    // MARK: - Content Sections
    
    private var processingStatusSection: some View {
        VStack(spacing: 24) {
            if usesQuietAnalysis {
                AnalysisStatusView(presentation: analysisPresentation, retryUpload: retryBackgroundUpload)
                if analysisPresentation.phase == .failed {
                    processingErrorCard.padding(.horizontal, 24)
                }
            } else if meeting.isLocalJob {
                MinimalistProcessingView(
                    phase: localMinimalistPhase,
                    progress: meeting.displayedProgressPercent,
                    stageDescription: meeting.effectiveStageDescription,
                    showPercentage: true,
                    infoMessage: meeting.isPausedLocalJob ? "Resume from this transcription when you're ready." : "Local processing continues while SnipNote stays open.",
                    estimatedTimeRemaining: meeting.displayedProgressPercent >= 25 && !meeting.isPausedLocalJob ? localEstimatedTimeRemaining() : nil,
                    currentChunk: meeting.totalChunks > 1 ? meeting.lastProcessedChunk : nil,
                    totalChunks: meeting.totalChunks > 1 ? meeting.totalChunks : nil,
                    partialTranscript: nil
                )

                localProcessingActions
            } else if meeting.transcriptionJobId != nil || meeting.isProcessing {
                MinimalistProcessingView(
                    phase: meeting.processingState == .generatingSummary ? .analyzing : .transcribing,
                    progress: 0,
                    stageDescription: localization.localizedString(meeting.processingState == .generatingSummary ? "analysis.title.analyzing" : "analysis.title.transcribing"),
                    showPercentage: false,
                    infoMessage: LocalizedStringKey(localization.localizedString("analysis.guidance.keep_open.title")),
                    estimatedTimeRemaining: nil, currentChunk: nil, totalChunks: nil, partialTranscript: nil
                )
            } else {
                // Fallback for on-device transcription (rarely used in MeetingDetailView)
                MinimalistProcessingView(
                    phase: meeting.processingState == .transcribing ? .transcribing : .analyzing,
                    progress: meeting.progressPercentage,
                    stageDescription: stageDescriptionForProcessingState(),
                    showPercentage: true,
                    infoMessage: nil,
                    estimatedTimeRemaining: nil,
                    currentChunk: meeting.totalChunks > 1 ? meeting.lastProcessedChunk : nil,
                    totalChunks: meeting.totalChunks > 1 ? meeting.totalChunks : nil,
                    partialTranscript: nil
                )
            }
        }
    }

    private var usesQuietAnalysis: Bool {
#if DEBUG
        if let analysisPreview {
            return analysisPreview.backend != .local && (analysisPreview.upload != nil
                || analysisPreview.jobID != nil || analysisPreview.processingPhase == .preparing)
        }
#endif
        guard !meeting.isLocalJob else { return false }
        return analysisUploads.snapshots[meeting.id] != nil || meeting.transcriptionJobId != nil
            || meeting.processingPhase == .preparing
            || (meeting.processingState == .failed && showedAcceptedServer)
    }

    private var analysisPresentation: AnalysisPresentation {
#if DEBUG
        if let analysisPreview { return AnalysisPresentationResolver.resolve(analysisPreview, previous: lastAnalysisPresentation) }
#endif
        return         AnalysisPresentationResolver.resolve(
            .init(meeting: meeting, upload: analysisUploads.snapshots[meeting.id],
                  serverStatus: jobId == meeting.transcriptionJobId ? jobStatus : nil,
                  serverStage: jobId == meeting.transcriptionJobId ? jobStage : nil),
            previous: lastAnalysisPresentation)
    }

    private func retryBackgroundUpload() {
        guard !isAnalysisPreview else { return }
        guard let upload = backgroundUploads.snapshots[meeting.id] else { return }
        Task { await backgroundUploads.recover(userID: upload.userID) }
    }

    private var localMinimalistPhase: MinimalistPhase {
        switch meeting.processingPhase {
        case .generatingOverview, .generatingSummary:
            return .analyzing
        default:
            return .transcribing
        }
    }

    // Helper for on-device processing state description
    private func stageDescriptionForProcessingState() -> String {
        switch meeting.processingState {
        case .transcribing:
            return isRetrying ? "Retrying transcription..." : "Transcribing audio..."
        case .generatingSummary:
            return "Generating insights..."
        default:
            return "Processing..."
        }
    }

    private func localEstimatedTimeRemaining() -> String {
        let progress = meeting.displayedProgressPercent
        if progress < 30 {
            return "Several minutes remaining"
        } else if progress < 70 {
            return "Making progress"
        } else {
            return "Almost done"
        }
    }

    // Server-side estimated time remaining
    private func serverEstimatedTimeRemaining() -> String {
        if jobProgress < 30 {
            return "A few minutes remaining"
        } else if jobProgress < 70 {
            return "Almost there"
        } else {
            return "Nearly complete"
        }
    }

    // Error card for failed server transcription
    @ViewBuilder
    private func serverErrorCard() -> some View {
        let theme = themeManager.currentTheme

        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(theme.destructiveColor)

            Text("Transcription Failed")
                .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(theme.destructiveColor)

            if let error = jobErrorMessage {
                Text(error)
                    .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private var meetingNotesSection: some View {
        editorialSection(title: "Notes", isExpanded: $showingNotes) {
            Text(meeting.meetingNotes)
                .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(theme.textColor)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var minutesSyncNoticeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundColor(theme.accentColor)
                    .font(.title3)

                Text("Minutes Sync In Progress")
                    .font(.system(.headline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.textColor)
            }

            Text(meeting.pendingMinutesDebitError ?? "This transcription finished successfully. We’re updating your minutes balance in the background.")
                .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(theme.secondaryTextColor)
        }
        .padding(16)
        .background(theme.materialStyle)
        .cornerRadius(theme.cornerRadius)
        .shadow(color: Color.black.opacity(theme.colorScheme == .dark ? 0.5 : 0.18), radius: 4, x: 0, y: 2)
    }
    
    private var overviewSection: some View {
        editorialSection(
            title: "Overview",
            isExpanded: $showingOverview,
            transition: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        ) {
            if meeting.processingState == .failed {
                processingErrorCard
            } else {
                Text(meeting.shortSummary)
                    .font(.system(.title3, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                    .foregroundColor(theme.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var processingErrorCard: some View {
        let theme = themeManager.currentTheme
        let showsAnalysisRetry = meeting.canRetryAnalysis
        let primaryRetryTitle = showsAnalysisRetry
            ? "Retry AI Analysis"
            : (meeting.canResumeLocalJob ? "Resume Processing" : "Retry Processing")
        let subtitle = meeting.processingError ?? "We couldn't process this transcription. Please try again."

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(theme.warningColor)
                    .font(.title3)

                Text(showsAnalysisRetry ? "AI analysis failed" : "Something went wrong")
                    .font(.system(.headline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.textColor)
            }

            Text(subtitle)
                .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(theme.secondaryTextColor)

            if meeting.canRetryAnalysis || meeting.canRetry {
                Button {
                    if showsAnalysisRetry {
                        retryAIAnalysis()
                    } else if meeting.canResumeLocalJob {
                        resumeLocalJob()
                    } else {
                        retryTranscription()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: meeting.canResumeLocalJob ? "play.fill" : "arrow.clockwise")
                        Text(primaryRetryTitle)
                    }
                    .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.backgroundColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(theme.accentColor)
                    .cornerRadius(theme.cornerRadius)
                }
                .disabled(isRetrying || isAnalysisPreview)
                .padding(.top, 4)
            } else {
                Text("The original audio file is no longer available.")
                    .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(theme.secondaryTextColor.opacity(0.7))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var localProcessingActions: some View {
        if meeting.isPausedLocalJob || meeting.isProcessing {
            HStack(spacing: 12) {
                if meeting.canResumeLocalJob {
                    Button("Resume") {
                        resumeLocalJob()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentColor)
                    .foregroundStyle(theme.backgroundColor)
                }

                Button(meeting.isPausedLocalJob ? "Cancel Job" : "Stop Job", role: .destructive) {
                    cancelLocalJob()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var summarySection: some View {
        editorialSection(
            title: "Summary",
            isExpanded: $showingSummary,
            transition: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        ) {
            if meeting.processingState == .failed {
                processingErrorCard
            } else {
                Button {
                    showingFullScreenSummary = true
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        markdownSummaryText(meeting.aiSummary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !meeting.aiSummary.isEmpty {
                            HStack(spacing: 6) {
                                Text("Open full summary")
                                    .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                                    .foregroundColor(theme.accentColor)

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(theme.accentColor)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var transcriptSection: some View {
        editorialSection(title: "Transcript", isExpanded: $showingTranscript) {
            Button {
                showingFullScreenTranscript = true
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(transcriptPreviewText)
                        .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(theme.textColor)
                        .lineSpacing(4)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        Text("Open full transcript")
                            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                            .foregroundColor(theme.accentColor)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.accentColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Helper Views
    
    private func editorialSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        transition: AnyTransition = .move(edge: .top).combined(with: .opacity),
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            editorialSectionHeader(title: title, isExpanded: isExpanded)

            if isExpanded.wrappedValue {
                content()
                    .transition(transition)
            }
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.secondaryBackgroundColor)
                .frame(height: 1)
        }
    }

    private func editorialSectionHeader<Trailing: View>(title: String, isExpanded: Binding<Bool>, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(.title3, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                        .foregroundColor(theme.textColor)

                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.secondaryTextColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            trailing()
        }
    }

    private func editorialSectionHeader(title: String, isExpanded: Binding<Bool>) -> some View {
        editorialSectionHeader(title: title, isExpanded: isExpanded) {
            EmptyView()
        }
    }
    
    private var processingLabel: some View {
        Text("Processing...")
            .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
            .foregroundColor(themeManager.currentTheme.warningColor)
    }
    
    
    private var fullScreenSummaryView: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    markdownSummaryText(meeting.aiSummary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle("Transcription Summary")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingFullScreenSummary = false
                    }
                    .foregroundColor(themeManager.currentTheme.accentColor)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var fullScreenTranscriptView: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(meeting.audioTranscript)
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle("Full Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingFullScreenTranscript = false
                    }
                    .foregroundColor(themeManager.currentTheme.accentColor)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !meeting.isProcessing && !meeting.audioTranscript.isEmpty {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Export menu: Text, PDF, Word
                    Menu {
                        Menu {
                            Button(action: shareSummary) {
                                Label("Summary", systemImage: "doc.richtext")
                            }

                            Button(action: shareTranscript) {
                                Label("Transcript", systemImage: "text.quote")
                            }

                            Button(action: shareEverything) {
                                Label("Everything", systemImage: "doc.text")
                            }
                        } label: {
                            Label(LocalizedStringKey("export.format.text"), systemImage: "doc.plaintext")
                        }

                        Menu {
                            exportContentButtons(format: .pdf)
                        } label: {
                            Label(LocalizedStringKey("export.format.pdf"), systemImage: "doc.richtext")
                        }

                        Menu {
                            exportContentButtons(format: .word)
                        } label: {
                            Label(LocalizedStringKey("export.format.word"), systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(.body))
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                    .disabled(isExporting)
                }
            }
        }
    }
    
    
    // MARK: - Helper Methods

    @ViewBuilder
    private func markdownSummaryText(_ text: String) -> some View {
        let blocks = summaryBlocks(from: text)

        if blocks.isEmpty {
            Text(text)
                .font(.body).foregroundStyle(theme.textColor)
                .lineSpacing(4)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let content, let level):
                        markdownInlineText(content)
                            .font(headingFont(for: level))
                            .foregroundColor(themeManager.currentTheme.textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)

                    case .bullet(let content):
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                .foregroundColor(themeManager.currentTheme.accentColor)

                            markdownInlineText(content)
                                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                                .foregroundColor(themeManager.currentTheme.textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                    case .paragraph(let content):
                        markdownInlineText(content)
                            .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(themeManager.currentTheme.textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .lineSpacing(4)
        }
    }

    private func markdownInlineText(_ text: String) -> Text {
        if let markdown = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return Text(markdown)
        }

        return Text(text)
    }

    private func headingFont(for level: Int) -> Font {
        let design: Font.Design = themeManager.currentTheme.useMonospacedFont ? .monospaced : .default

        switch level {
        case 1:
            return .system(.title3, design: design, weight: .bold)
        case 2:
            return .system(.headline, design: design, weight: .bold)
        default:
            return .system(.subheadline, design: design, weight: .semibold)
        }
    }

    private func summaryBlocks(from text: String) -> [SummaryBlock] {
        var blocks: [SummaryBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !paragraph.isEmpty else {
                paragraphLines.removeAll()
                return
            }

            blocks.append(.paragraph(paragraph))
            paragraphLines.removeAll()
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(from: line) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let bullet = parseBullet(from: line) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        return blocks
    }

    private func parseHeading(from line: String) -> SummaryBlock? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count

        guard (1...6).contains(level) else { return nil }

        let content = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }

        return .heading(content, level: level)
    }

    private func parseBullet(from line: String) -> String? {
        let prefixes = ["- ", "* ", "• "]

        for prefix in prefixes where line.hasPrefix(prefix) {
            let content = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !content.isEmpty {
                return content
            }
        }

        return nil
    }

    private func getMeetingTitle() -> String {
        return meeting.name.isEmpty ? "Untitled Transcription" : meeting.name
    }

    private var transcriptPreviewText: String {
        let trimmed = meeting.audioTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return "No transcript available"
        }

        if trimmed.count <= 700 {
            return trimmed
        }

        return String(trimmed.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
    
    private func startEditingName() {
        tempName = meeting.name
        isEditingName = true
    }
    
    private func saveName() {
        meeting.name = tempName
        meeting.dateModified = Date()
        isEditingName = false

        do {
            try modelContext.save()

            // Sync to Supabase
            Task {
                do {
                    try await SupabaseManager.shared.saveMeeting(meeting)
                } catch {
                    print("⚠️ Failed to sync meeting name to Supabase: \(error)")
                }
            }
        } catch {
            print("Error saving name: \(error)")
        }
    }
    
    private func shareEverything() {
        let content = """
        Transcription: \(meeting.name.isEmpty ? "Untitled Transcription" : meeting.name)
        Date: \(meeting.dateCreated.formatted())
        Location: \(meeting.location.isEmpty ? "N/A" : meeting.location)
        Duration: \(meeting.durationFormatted)
        
        Notes:
        \(meeting.meetingNotes.isEmpty ? "N/A" : meeting.meetingNotes)
        
        Summary:
        \(meeting.aiSummary.isEmpty ? "N/A" : meeting.aiSummary)
        
        Transcript:
        \(meeting.audioTranscript.isEmpty ? "N/A" : meeting.audioTranscript)
        """
        
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("transcription-\(meeting.name.isEmpty ? "untitled" : meeting.name).txt")
            try content.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                activityVC.popoverPresentationController?.sourceView = rootVC.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Error sharing content: \(error)")
        }
    }
    
    private func shareSummary() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: meeting.dateCreated)
        
        let content = """
        Transcription: \(meeting.name.isEmpty ? "Untitled Transcription" : meeting.name)
        Date: \(meeting.dateCreated.formatted())
        Location: \(meeting.location.isEmpty ? "N/A" : meeting.location)
        Duration: \(meeting.durationFormatted)
        
        Summary:
        \(meeting.aiSummary.isEmpty ? "No summary available" : meeting.aiSummary)
        """
        
        do {
            let filename = "\(meeting.name.isEmpty ? "Transcription" : meeting.name.replacingOccurrences(of: " ", with: "_"))_Summary_\(dateString).txt"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try content.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                activityVC.popoverPresentationController?.sourceView = rootVC.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Error sharing summary: \(error)")
        }
    }
    
    private func shareTranscript() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: meeting.dateCreated)
        
        let content = """
        Transcription: \(meeting.name.isEmpty ? "Untitled Transcription" : meeting.name)
        Date: \(meeting.dateCreated.formatted())
        
        Transcript:
        \(meeting.audioTranscript.isEmpty ? "No transcript available" : meeting.audioTranscript)
        """
        
        do {
            let filename = "\(meeting.name.isEmpty ? "Transcription" : meeting.name.replacingOccurrences(of: " ", with: "_"))_Transcript_\(dateString).txt"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try content.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                activityVC.popoverPresentationController?.sourceView = rootVC.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Error sharing transcript: \(error)")
        }
    }

    // MARK: - PDF / Word export

    @ViewBuilder
    private func exportContentButtons(format: ExportFormat) -> some View {
        let hasSummary = !meeting.aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTranscript = meeting.hasTranscriptContent

        if hasSummary {
            Button {
                exportMeeting(content: .summary, format: format)
            } label: {
                Label(LocalizedStringKey("export.content.summary"), systemImage: "doc.richtext")
            }
        }

        if hasTranscript {
            Button {
                exportMeeting(content: .transcript, format: format)
            } label: {
                Label(LocalizedStringKey("export.content.transcript"), systemImage: "text.quote")
            }
        }

        if hasSummary && hasTranscript {
            Button {
                exportMeeting(content: .everything, format: format)
            } label: {
                Label(LocalizedStringKey("export.content.everything"), systemImage: "doc.text")
            }
        }
    }

    private func exportMeeting(content: ExportContent, format: ExportFormat) {
        guard !isExporting else { return }
        isExporting = true
        let snapshot = ExportService.snapshot(of: meeting, content: content)

        Task {
            do {
                let url = try await ExportService.exportFile(snapshot, as: format)
                isExporting = false
                ExportSharePresenter.present(url)
            } catch {
                isExporting = false
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Refresh Functionality

    private func updatePollingTask(for jobId: String?) async {
        guard !isAnalysisPreview else { return }
        await MainActor.run {
            jobPollingTask?.cancel()
            jobPollingTask = nil
        }

        guard let jobId else {
            await MainActor.run {
                self.jobId = nil
                self.jobStatus = nil
                self.jobStage = ""
                self.jobProgress = 0
            }
            return
        }

        await MainActor.run {
            if self.jobId != jobId {
                self.jobStatus = nil
                self.jobStage = ""
                self.jobProgress = 0
                self.lastAnalysisPresentation = nil
            }
            self.jobId = jobId
            print("🔄 [MeetingDetail] Starting async job polling for: \(jobId)")
        }

        let task = Task { await pollJobStatus(jobId: jobId) }

        await MainActor.run {
            jobPollingTask = task
        }
    }

    private func pollJobStatus(jobId: String) async {
        pollingLoop: while !Task.isCancelled {
            do {
                let status = try await transcriptionService.getJobStatus(jobId: jobId)

                let isFinal = await MainActor.run {
                    guard meeting.transcriptionJobId == jobId, self.jobId == jobId, meeting.isProcessing else { return true }
                    if backgroundUploads.snapshots[meeting.id] != nil {
                        jobStatus = status.status
                        jobProgress = status.progressPercentage ?? 0
                        jobStage = status.currentStage ?? ""
                        return status.status == .completed || status.status == .failed
                    }
                    return applyJobStatusUpdate(status: status)
                }

                if isFinal {
                    break pollingLoop
                }

                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                if Task.isCancelled { break }

                // Network/polling exhaustion preserves the remote job identity.
                print("⚠️ [MeetingDetail] Error polling job status: \(error)")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    @MainActor
    private func applyJobStatusUpdate(status: JobStatusResponse) -> Bool {
        jobStatus = status.status
        jobProgress = status.progressPercentage ?? 0
        jobStage = status.currentStage ?? "Processing..."

        switch status.status {
        case .completed:
            jobErrorMessage = nil

            if let transcript = status.transcript {
                meeting.audioTranscript = transcript
            }

            if let overview = status.overview {
                meeting.shortSummary = overview
                print("✅ [MeetingDetail] Overview: \(overview.prefix(80))...")
            }

            if let summary = status.summary {
                meeting.aiSummary = summary
                print("✅ [MeetingDetail] Summary: \(summary.count) chars")
            }

            meeting.markCompleted()
            meeting.transcriptionJobId = nil
            jobId = nil
            HapticService.shared.success()

            if let duration = status.duration {
                print("✅ [MeetingDetail] Job completed - duration: \(duration)s")
            }

            do {
                try modelContext.save()
                print("💾 [MeetingDetail] Successfully saved completed job to database")

                // Sync updated meeting to Supabase
                Task {
                    do {
                        try await SupabaseManager.shared.saveMeeting(meeting)
                    } catch {
                        print("⚠️ Failed to sync completed meeting to Supabase: \(error)")
                    }
                }
            } catch {
                print("❌ [MeetingDetail] Failed to save: \(error)")
            }

            refreshTrigger.toggle()
            print("✅ [MeetingDetail] Async job completed with full AI processing")

            // Send completion notification and cancel estimated notification
            Task {
                // Cancel the estimated completion notification (actual completion happened)
                NotificationService.shared.cancelEstimatedCompletionNotification(for: meeting.id)

                await NotificationService.shared.sendProcessingCompleteNotification(
                    for: meeting.id,
                    meetingName: meeting.name
                )
            }

            // Clean up local audio file after successful server processing
            if meeting.hasRecording,
               let localPath = meeting.localAudioPath,
               FileManager.default.fileExists(atPath: localPath) {
                do {
                    try FileManager.default.removeItem(atPath: localPath)
                    meeting.localAudioPath = nil
                    try? modelContext.save()
                    print("🗑️ Deleted local audio file after successful server processing")
                } catch {
                    print("⚠️ Failed to delete local audio file: \(error.localizedDescription)")
                }
            }

            return true
        case .failed:
            jobErrorMessage = status.errorMessage ?? "Transcription failed"
            meeting.setProcessingError(jobErrorMessage ?? "Server transcription failed")
            meeting.transcriptionJobId = nil
            jobId = nil

            try? modelContext.save()
            refreshTrigger.toggle()

            print("❌ [MeetingDetail] Async job failed: \(jobErrorMessage ?? "unknown")")

            // Send failure notification with error message and cancel estimated notification
            Task {
                // Cancel the estimated completion notification (job failed)
                NotificationService.shared.cancelEstimatedCompletionNotification(for: meeting.id)

                await NotificationService.shared.sendProcessingFailedNotification(
                    for: meeting.id,
                    meetingName: meeting.name,
                    errorMessage: jobErrorMessage ?? "Unknown error"
                )
            }

            return true
        default:
            jobErrorMessage = nil
            if let id = UUID(uuidString: status.id), let user = UUID(uuidString: status.userId) {
                _ = BackgroundUploadReconciler.applyResult(status, to: meeting, userID: user, jobID: id)
                try? modelContext.save()
            }
            return false
        }
    }

    private func refreshJobStatus() async {
        guard !isAnalysisPreview else { return }
        guard let jobId = meeting.transcriptionJobId else {
            print("ℹ️ [MeetingDetail] No job ID to refresh")
            return
        }

        print("🔄 [MeetingDetail] Manual refresh for job: \(jobId)")

        do {
            let status = try await transcriptionService.getJobStatus(jobId: jobId)

            if let upload = backgroundUploads.snapshots[meeting.id] {
                await BackgroundUploadReconciler.shared.reconcile(context: modelContext, userID: upload.userID)
                return
            }
            let isFinal = await MainActor.run { applyJobStatusUpdate(status: status) }

            if !isFinal {
                print("📊 [MeetingDetail] Manual refresh - job status: \(status.status.displayText)")
            }
        } catch {
            print("⚠️ [MeetingDetail] Error refreshing job status: \(error)")
        }
    }

    // MARK: - Retry Functionality

    private func retryTranscription() {
        guard !isAnalysisPreview else { return }
        Task {
            await performRetryTranscription()
        }
    }

    private func retryAIAnalysis() {
        guard !isAnalysisPreview else { return }
        Task {
            await performRetryAIAnalysis()
        }
    }

    private func resumeLocalJob() {
        guard !isAnalysisPreview else { return }
        Task {
            isRetrying = true
            meeting.clearProcessingError()
            meeting.updateProcessingState(meeting.resumePhase == .transcribing ? .transcribing : .generatingSummary)
            meeting.updateProcessingPhase(
                meeting.resumePhase,
                stage: meeting.effectiveStageDescription,
                progressPercent: meeting.displayedProgressPercent
            )
            try? modelContext.save()
            await LocalTranscriptionJobManager.shared.resumeJob(meetingId: meeting.id)
            isRetrying = false
        }
    }

    private func cancelLocalJob() {
        guard !isAnalysisPreview else { return }
        Task {
            isRetrying = true
            let meetingID = meeting.id
            await MainActor.run {
                dismiss()
            }
            await LocalTranscriptionJobManager.shared.cancelJob(
                meetingId: meetingID,
                deleteMeeting: true
            )
            isRetrying = false
        }
    }

    @MainActor
    private func performRetryTranscription() async {
        await minutesManager.refreshBalance()

        guard meeting.canRetry, let localPath = meeting.localAudioPath else {
            print("⚠️ Cannot retry: meeting cannot retry or no local audio path")
            return
        }

        let audioURL = URL(fileURLWithPath: localPath)
        guard FileManager.default.fileExists(atPath: localPath) else {
            print("⚠️ Cannot retry: audio file no longer exists at \(localPath)")
            meeting.localAudioPath = nil
            try? modelContext.save()
            return
        }

        let shouldUsePersistentLocalRetry: Bool
        if let backend = meeting.transcriptionBackend {
            shouldUsePersistentLocalRetry = backend == .local
        } else {
            shouldUsePersistentLocalRetry = LocalTranscriptionManager.shared.isLocalModeEnabled
        }

        // Local transcription is free; only cloud retries need a minutes balance
        let requiredMinutes = max(1, Int(ceil(meeting.billingDuration / 60.0)))
        if !shouldUsePersistentLocalRetry && minutesManager.currentBalance < requiredMinutes {
            print("⚠️ Cannot retry: insufficient minutes. Required: \(requiredMinutes), Available: \(minutesManager.currentBalance)")
            meeting.setProcessingError("Insufficient minutes for retry. Required: \(requiredMinutes) minutes.")
            return
        }

        isRetrying = true
        defer {
            isRetrying = false
        }

        if shouldUsePersistentLocalRetry {
            meeting.clearProcessingError()
            meeting.audioTranscript = "Transcribing meeting audio..."
            meeting.shortSummary = "Generating overview..."
            meeting.aiSummary = "Generating meeting summary..."
            meeting.updateProcessingState(.transcribing)
            meeting.updateProcessingPhase(.queued, stage: "Starting transcription...", progressPercent: 0)
            meeting.didDebitTranscriptionMinutes = false
            try? modelContext.save()

            await LocalTranscriptionJobManager.shared.startJob(
                meetingId: meeting.id,
                audioURL: audioURL,
                language: meeting.transcriptionLanguage,
                sourceAudioDuration: meeting.billingDuration
            )
            return
        }

        meeting.clearProcessingError()
        meeting.updateProcessingState(.transcribing)
        meeting.audioTranscript = "Transcribing meeting audio..."
        meeting.shortSummary = "Generating overview..."
        meeting.aiSummary = "Generating meeting summary..."

        do {
            try modelContext.save()
        } catch {
            print("Error saving retry preparation state: \(error)")
        }

        let backgroundTaskId = BackgroundTaskManager.shared.startBackgroundTask(for: meeting.id)
        defer {
            BackgroundTaskManager.shared.endBackgroundTask(backgroundTaskId)
        }

        do {
            let transcript = try await TranscriptionRouter.shared.transcribeAudioFromURL(
                audioURL: audioURL,
                progressCallback: { progress in
                    Task { @MainActor in
                        meeting.updateChunkProgress(
                            completed: progress.currentChunk,
                            total: progress.totalChunks
                        )
                    }
                },
                meetingName: meeting.name,
                meetingId: meeting.id,
                language: meeting.transcriptionLanguage
            )

            meeting.audioTranscript = transcript
            meeting.updateProcessingState(.generatingSummary)
            try? modelContext.save()

            let durationSeconds = Int(meeting.billingDuration)
            var debitSucceeded = true
            if durationSeconds > 0 {
                let debitResult = await minutesManager.debitMinutes(
                    seconds: durationSeconds,
                    meetingID: meeting.id.uuidString
                )
                debitSucceeded = debitResult.didDebitImmediately
                if !debitResult.didDebitImmediately {
                    print("⚠️ Minutes debit delayed during retry for meeting \(meeting.id): \(debitResult.userMessage ?? "unknown")")
                }
                await UsageTracker.shared.trackMeetingCreated(
                    transcribed: true,
                    meetingSeconds: durationSeconds
                )
            }

            let shouldUploadAudio = !LocalTranscriptionManager.shared.isLocalModeEnabled
            var uploadedAudioPath: String?

            if shouldUploadAudio, let latestLocalPath = meeting.localAudioPath {
                let latestURL = URL(fileURLWithPath: latestLocalPath)
                do {
                    uploadedAudioPath = try await SupabaseManager.shared.uploadAudioRecording(
                        audioURL: latestURL,
                        meetingId: meeting.id,
                        duration: meeting.billingDuration
                    )
                    meeting.hasRecording = true
                } catch {
                    print("Error uploading audio during retry: \(error)")
                }
            }

            let overview = try await MeetingAnalysisRouter.shared.generateOverview(
                transcript: transcript,
                explicitLanguageCode: meeting.transcriptionLanguage
            )
            let summary = try await MeetingAnalysisRouter.shared.generateSummary(
                transcript: transcript,
                explicitLanguageCode: meeting.transcriptionLanguage
            )

            meeting.shortSummary = overview
            meeting.aiSummary = summary
            meeting.markCompleted()
            if debitSucceeded {
                meeting.markMinutesDebitSettled()
            } else {
                meeting.markMinutesDebitPending(
                    message: "Transcription completed. We’re retrying the minutes sync in the background."
                )
            }
            HapticService.shared.success()

            let shouldDeleteLocalAudio = meeting.hasRecording || !shouldUploadAudio

            if shouldDeleteLocalAudio,
               debitSucceeded,
               let latestLocalPath = meeting.localAudioPath,
               FileManager.default.fileExists(atPath: latestLocalPath) {
                try? FileManager.default.removeItem(atPath: latestLocalPath)
                meeting.localAudioPath = nil
            }

            do {
                try modelContext.save()

                Task {
                    do {
                        try await SupabaseManager.shared.saveMeeting(meeting)

                        try await SupabaseManager.shared.saveCompletedTranscriptionJob(
                            meetingId: meeting.id,
                            audioStoragePath: uploadedAudioPath,
                            duration: meeting.billingDuration,
                            transcript: meeting.audioTranscript,
                            overview: overview,
                            summary: summary
                        )
                    } catch {
                        print("⚠️ Failed to sync retry results to Supabase: \(error)")
                    }
                }
            } catch {
                print("Error saving retry results: \(error)")
            }

            NotificationService.shared.cancelEstimatedCompletionNotification(for: meeting.id)

            await NotificationService.shared.sendProcessingCompleteNotification(
                for: meeting.id,
                meetingName: meeting.name
            )

        } catch {
            print("Error during retry: \(error)")
            if meeting.hasTranscriptContent {
                let analysisError = MeetingAnalysisRouter.shared.failureDescription(for: error)
                meeting.setProcessingError("Transcript saved, but AI analysis failed again. \(analysisError)")
            } else {
                meeting.setProcessingError("Transcription failed again. Please try later.")
            }
            try? modelContext.save()
        }
    }

    @MainActor
    private func performRetryAIAnalysis() async {
        guard meeting.canRetryAnalysis else {
            print("⚠️ Cannot retry AI analysis: transcript is unavailable")
            return
        }

        isRetrying = true
        meeting.clearProcessingError()
        meeting.updateProcessingState(.generatingSummary)
        meeting.shortSummary = "Generating overview..."
        meeting.aiSummary = "Generating meeting summary..."

        do {
            try modelContext.save()
        } catch {
            print("Error saving AI retry preparation state: \(error)")
        }

        defer {
            isRetrying = false
        }

        let transcript = meeting.audioTranscript

        do {
            print("🧠 [MeetingDetail][AI Retry] Starting overview generation (transcript chars: \(transcript.count))")
            let overview = try await MeetingAnalysisRouter.shared.generateOverview(
                transcript: transcript,
                explicitLanguageCode: meeting.transcriptionLanguage
            )
            print("✅ [MeetingDetail][AI Retry] Overview generated (chars: \(overview.count))")
            print("🧠 [MeetingDetail][AI Retry] Starting summary generation")
            let summary = try await MeetingAnalysisRouter.shared.generateSummary(
                transcript: transcript,
                explicitLanguageCode: meeting.transcriptionLanguage
            )
            print("✅ [MeetingDetail][AI Retry] Summary generated (chars: \(summary.count))")

            meeting.shortSummary = overview
            meeting.aiSummary = summary
            meeting.markCompleted()

            do {
                try modelContext.save()

                Task {
                    do {
                        try await SupabaseManager.shared.saveMeeting(meeting)
                        try await SupabaseManager.shared.saveCompletedTranscriptionJob(
                            meetingId: meeting.id,
                            audioStoragePath: nil,
                            duration: meeting.billingDuration,
                            transcript: meeting.audioTranscript,
                            overview: overview,
                            summary: summary
                        )
                    } catch {
                        print("⚠️ Failed to sync AI retry results to Supabase: \(error)")
                    }
                }
            } catch {
                print("Error saving AI retry results: \(error)")
            }
        } catch {
            print("Error during AI retry: \(error)")
            let analysisError = MeetingAnalysisRouter.shared.failureDescription(for: error)
            meeting.setProcessingError("Transcript saved, but AI analysis failed again. \(analysisError)")
            try? modelContext.save()
        }
    }

    // MARK: - Fallback Logic

    @MainActor
    private func attemptOnDeviceFallback() async {
        print("🔄 [MeetingDetail] Attempting on-device fallback after server failure")

        // Check if local audio file exists
        guard let localPath = meeting.localAudioPath else {
            print("❌ [MeetingDetail] No local audio path - cannot fallback to on-device")
            meeting.setProcessingError("Server processing failed and no local audio available for retry")
            meeting.transcriptionJobId = nil
            jobId = nil
            try? modelContext.save()
            return
        }

        guard FileManager.default.fileExists(atPath: localPath) else {
            print("❌ [MeetingDetail] Local audio file no longer exists - cannot fallback")
            meeting.setProcessingError("Server processing failed and local audio file was deleted")
            meeting.localAudioPath = nil
            meeting.transcriptionJobId = nil
            jobId = nil
            try? modelContext.save()
            return
        }

        // Check if user has sufficient minutes
        await minutesManager.refreshBalance()
        let requiredMinutes = max(1, Int(ceil(meeting.billingDuration / 60.0)))

        if minutesManager.currentBalance < requiredMinutes {
            print("❌ [MeetingDetail] Insufficient minutes for on-device fallback. Required: \(requiredMinutes), Available: \(minutesManager.currentBalance)")
            meeting.setProcessingError("Server processing failed. Retry requires \(requiredMinutes) minutes but only \(minutesManager.currentBalance) available.")
            meeting.transcriptionJobId = nil
            jobId = nil
            try? modelContext.save()
            return
        }

        print("✅ [MeetingDetail] Fallback conditions met - starting on-device processing")

        // Clear server job ID since we're falling back
        meeting.transcriptionJobId = nil
        jobId = nil
        meeting.clearProcessingError()
        meeting.updateProcessingState(.transcribing)

        // Reuse existing retry logic which handles on-device processing
        await performRetryTranscription()
    }

}

private enum SummaryBlock {
    case heading(String, level: Int)
    case bullet(String)
    case paragraph(String)
}

// MARK: - Reusable Card Component
private struct MeetingDetailCard<Content: View>: View {
    @EnvironmentObject private var themeManager: ThemeManager

    let content: Content
    let action: (() -> Void)?

    init(action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    private var shadowOpacity: Double {
        themeManager.currentTheme.colorScheme == .dark ? 0.5 : 0.18
    }

    var body: some View {
        if let action = action {
            Button(action: action) {
                cardContent
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        content
            .padding(16)
            .background(themeManager.currentTheme.materialStyle)
            .cornerRadius(themeManager.currentTheme.cornerRadius)
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: 4,
                x: 0,
                y: 2
            )
    }
}
