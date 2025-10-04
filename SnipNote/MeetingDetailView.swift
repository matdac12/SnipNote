//
//  MeetingDetailView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct MeetingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var meeting: Meeting
    @EnvironmentObject var themeManager: ThemeManager

    @Query private var allActions: [Action]
    @AppStorage("showActionsTab") private var showActionsTab = false

    @Environment(\.navigateToEve) private var navigateToEve

    @State private var isEditingName = false
    @State private var isEditingSummary = false
    @State private var tempName = ""
    @State private var tempSummary = ""
    @State private var showingTranscript = false
    @State private var showingSummary = true
    @State private var showingFullScreenSummary = false
    @State private var showingFullScreenTranscript = false
    @State private var isDownloadingAudio = false
    @State private var downloadProgress: Double = 0
    @State private var showDownloadAlert = false
    @StateObject private var audioPlayer = AudioPlayerManager()

    // Retry functionality
    @State private var isRetrying = false
    @StateObject private var openAIService = OpenAIService.shared
    @StateObject private var backgroundTaskManager = BackgroundTaskManager.shared
    @StateObject private var minutesManager = MinutesManager.shared

    // Force refresh for processing updates
    @State private var refreshTrigger = false

    // Async job tracking
    @State private var jobId: String?
    @State private var jobStatus: JobStatus?
    @State private var jobErrorMessage: String?
    @State private var jobProgress: Int = 0
    @State private var jobStage: String = ""
    @StateObject private var transcriptionService = RenderTranscriptionService()

    private var relatedActions: [Action] {
        allActions.filter { $0.sourceNoteId == meeting.id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            meetingHeaderView

            ScrollView {
                if meeting.isProcessing || isRetrying {
                    processingStatusSection
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        if !meeting.meetingNotes.isEmpty {
                            meetingNotesSection
                        }

                        overviewSection
                        summarySection
                        transcriptSection

                        if showActionsTab {
                            actionsSection
                        }
                    }
                    .padding()
                }
            }
            .id(refreshTrigger)  // Force view rebuild when job completes
            .refreshable {
                await refreshJobStatus()
            }
        }
        .themedBackground()
        .foregroundColor(themeManager.currentTheme.accentColor)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            toolbarContent
        }
        .onAppear {
            tempName = meeting.name
            tempSummary = meeting.aiSummary
        }
        .task {
            // Continuously refresh meeting data - start immediately to catch stale data
            let meetingId = meeting.id

            // Always fetch fresh data first, even if meeting.isProcessing is false
            await MainActor.run {
                let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate<Meeting> { $0.id == meetingId })
                if let fetchedMeeting = try? modelContext.fetch(descriptor).first {
                    let hasChanged =
                        meeting.lastProcessedChunk != fetchedMeeting.lastProcessedChunk ||
                        meeting.totalChunks != fetchedMeeting.totalChunks ||
                        meeting.isProcessing != fetchedMeeting.isProcessing ||
                        meeting.processingStateRaw != fetchedMeeting.processingStateRaw ||
                        meeting.audioTranscript != fetchedMeeting.audioTranscript ||
                        meeting.shortSummary != fetchedMeeting.shortSummary ||
                        meeting.aiSummary != fetchedMeeting.aiSummary

                    guard hasChanged else { return }

                    meeting.lastProcessedChunk = fetchedMeeting.lastProcessedChunk
                    meeting.totalChunks = fetchedMeeting.totalChunks
                    meeting.isProcessing = fetchedMeeting.isProcessing
                    meeting.processingStateRaw = fetchedMeeting.processingStateRaw
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
                            meeting.isProcessing != fetchedMeeting.isProcessing ||
                            meeting.processingStateRaw != fetchedMeeting.processingStateRaw ||
                            meeting.audioTranscript != fetchedMeeting.audioTranscript ||
                            meeting.shortSummary != fetchedMeeting.shortSummary ||
                            meeting.aiSummary != fetchedMeeting.aiSummary

                        guard hasChanged else { return }

                        meeting.lastProcessedChunk = fetchedMeeting.lastProcessedChunk
                        meeting.totalChunks = fetchedMeeting.totalChunks
                        meeting.isProcessing = fetchedMeeting.isProcessing
                        meeting.processingStateRaw = fetchedMeeting.processingStateRaw
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
            // Poll async transcription job status if available
            guard let jobId = meeting.transcriptionJobId else { return }

            self.jobId = jobId
            print("🔄 [MeetingDetail] Starting async job polling for: \(jobId)")

            pollingLoop: while true {
                do {
                    let status = try await transcriptionService.getJobStatus(jobId: jobId)

                    jobStatus = status.status
                    jobProgress = status.progressPercentage ?? 0
                    jobStage = status.currentStage ?? "Processing..."

                    // Update UI based on status
                    if status.status == .completed, let transcript = status.transcript {
                        // Update meeting with all AI-generated content
                        meeting.audioTranscript = transcript

                        if let overview = status.overview {
                            meeting.shortSummary = overview
                            print("✅ [MeetingDetail] Overview: \(overview.prefix(80))...")
                        }

                        if let summary = status.summary {
                            meeting.aiSummary = summary
                            print("✅ [MeetingDetail] Summary: \(summary.count) chars")
                        }

                        // Convert backend action items to iOS Action objects
                        if let backendActions = status.actions, !backendActions.isEmpty {
                            for backendAction in backendActions {
                                let priority = ActionPriority(rawValue: backendAction.priority) ?? .medium
                                let action = Action(
                                    title: backendAction.action,
                                    priority: priority,
                                    sourceNoteId: meeting.id
                                )
                                modelContext.insert(action)
                            }
                            print("✅ [MeetingDetail] Created \(backendActions.count) action items")
                        }

                        meeting.isProcessing = false
                        meeting.markCompleted()
                        meeting.transcriptionJobId = nil // Clear job ID

                        if let duration = status.duration {
                            print("✅ [MeetingDetail] Job completed - duration: \(duration)s")
                        }

                        // Force SwiftUI to detect changes and save
                        meeting.objectWillChange.send()

                        do {
                            try modelContext.save()
                            print("💾 [MeetingDetail] Successfully saved completed job to database")
                        } catch {
                            print("❌ [MeetingDetail] Failed to save: \(error)")
                        }

                        refreshTrigger.toggle()
                        print("✅ [MeetingDetail] Async job completed with full AI processing, stopping polling")
                        break pollingLoop
                    } else if status.status == .failed {
                        // Handle failure
                        jobErrorMessage = status.errorMessage ?? "Transcription failed"
                        meeting.setProcessingError(jobErrorMessage ?? "Server transcription failed")
                        meeting.isProcessing = false
                        meeting.transcriptionJobId = nil // Clear job ID

                        // Force SwiftUI to detect changes
                        meeting.objectWillChange.send()
                        try? modelContext.save()

                        refreshTrigger.toggle()
                        print("❌ [MeetingDetail] Async job failed: \(jobErrorMessage ?? "unknown")")
                        break pollingLoop
                    }

                    // Poll every 5 seconds for responsive updates
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    print("⚠️ [MeetingDetail] Error polling job status: \(error)")
                    // Continue polling on error - could be temporary network issue
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
        .sheet(isPresented: $showingFullScreenSummary) {
            fullScreenSummaryView
        }
        .sheet(isPresented: $showingFullScreenTranscript) {
            fullScreenTranscriptView
        }
        .overlay {
            if isDownloadingAudio && showDownloadAlert {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(themeManager.currentTheme.accentColor)

                        Text("Downloading Audio...")
                            .font(.headline)

                        Text("Please wait while the audio file is being downloaded")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(30)
                    .background(themeManager.currentTheme.materialStyle)
                    .cornerRadius(20)
                }
            }
        }
    }
    
    // MARK: - Header View
    
    private var meetingHeaderView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if isEditingName {
                        TextField("Meeting Name", text: $tempName)
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
                                .themedCaption()
                        }

                        if meeting.duration > 0 {
                            Text("⏱️ \(meeting.durationFormatted)")
                                .themedCaption()
                        }

                        if meeting.hasRecording {
                            MiniAudioPlayer(audioPlayer: audioPlayer, item: meeting) { meeting in
                                await audioPlayer.loadAndPlayAudio(for: meeting)
                            }
                            .allowsHitTesting(true)
                        }
                    }
                }

                Spacer()

                Text(meeting.dateCreated, style: .date)
                    .themedCaption()
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
            // Show async job status if available
            if let jobId = meeting.transcriptionJobId, let status = jobStatus {
                asyncJobStatusCard(jobId: jobId, status: status)
            } else {
                MeetingProcessingStatusView(
                    theme: themeManager.currentTheme,
                    isRetrying: isRetrying,
                    processingState: meeting.processingState,
                    progress: meeting.progressPercentage,
                    chunkIndex: meeting.lastProcessedChunk,
                    totalChunks: meeting.totalChunks
                )
            }
        }
    }

    @ViewBuilder
    private func asyncJobStatusCard(jobId: String, status: JobStatus) -> some View {
        let theme = themeManager.currentTheme

        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: status.isInProgress ? "cloud.fill" : (status == .failed ? "xmark.circle.fill" : "checkmark.circle.fill"))
                    .font(.title2)
                    .foregroundColor(status.isInProgress ? theme.accentColor : (status == .failed ? theme.destructiveColor : .green))

                Text(theme.headerStyle == .brackets ? "SERVER TRANSCRIPTION" : "Server Transcription")
                    .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(theme.textColor)
            }

            // Status indicator
            HStack(spacing: 12) {
                if status.isInProgress {
                    ProgressView()
                        .scaleEffect(1.2)
                }

                Text(status.displayText)
                    .font(.system(.title3, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(status.isInProgress ? theme.warningColor : (status == .failed ? theme.destructiveColor : .green))
            }

            if status.isInProgress {
                // Progress information
                VStack(alignment: .leading, spacing: 12) {
                    // Stage description
                    Text(jobStage)
                        .font(.system(.callout, design: theme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(theme.secondaryTextColor)

                    // Progress bar
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: Double(jobProgress), total: 100)
                            .progressViewStyle(.linear)
                            .tint(theme.accentColor)

                        Text("\(jobProgress)%")
                            .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                            .foregroundColor(theme.secondaryTextColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Your meeting is being transcribed on the server. This may take a few minutes.")
                    .font(.system(.callout, design: theme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }

            // Job ID for reference
            VStack(spacing: 4) {
                Text(theme.headerStyle == .brackets ? "JOB ID:" : "Job ID:")
                    .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(theme.secondaryTextColor)

                Text(jobId)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(theme.secondaryTextColor.opacity(0.7))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius + 6)
                .fill(theme.secondaryBackgroundColor.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius + 6)
                .stroke(theme.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var meetingNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "MEETING NOTES:", alternateTitle: "Meeting Notes:")

            MeetingDetailCard {
                Text(meeting.meetingNotes)
                    .themedBody()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "OVERVIEW:", alternateTitle: "Overview:")

            MeetingDetailCard {
                if meeting.isProcessing || isRetrying {
                    // Show detailed chunk progress when processing
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(meeting.processingState == .transcribing ? "Processing meeting..." : meeting.shortSummary)
                                .themedBody()
                                .opacity(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ProgressView()
                                .scaleEffect(0.8)
                        }

                        // Show chunk progress if available
                        if meeting.totalChunks > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(Int(meeting.progressPercentage))% Complete")
                                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                                    .foregroundColor(themeManager.currentTheme.accentColor)

                                ProgressView(value: meeting.progressPercentage, total: 100)
                                    .progressViewStyle(LinearProgressViewStyle(tint: themeManager.currentTheme.accentColor))
                                    .frame(height: 4)

                                HStack(spacing: 4) {
                                    Image(systemName: "waveform")
                                        .font(.caption2)
                                        .foregroundColor(themeManager.currentTheme.accentColor)
                                    Text("Chunk \(meeting.lastProcessedChunk) of \(meeting.totalChunks)")
                                        .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                }
                            }
                        }
                    }
                } else {
                    HStack {
                        Text(meeting.processingState == .failed ? (meeting.processingError ?? "Processing failed") : meeting.shortSummary)
                            .themedBody()
                            .foregroundColor(meeting.processingState == .failed ? themeManager.currentTheme.destructiveColor : themeManager.currentTheme.textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if meeting.processingState == .failed && meeting.canRetry {
                            Button("Retry") {
                                retryTranscription()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(themeManager.currentTheme.accentColor)
                            .disabled(isRetrying)
                        }
                    }
                }
            }
        }
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "MEETING SUMMARY:", alternateTitle: "Meeting Summary:")

                Spacer()

                HStack(spacing: 12) {
                    Button(showingSummary ? "Hide" : "Show") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingSummary.toggle()
                        }
                    }
                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.accentColor)

                    if !meeting.isProcessing && showingSummary {
                        editButton
                    }
                }
            }

            if showingSummary {
                if isEditingSummary {
                    summaryEditor
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    MeetingDetailCard(action: meeting.isProcessing || isRetrying ? nil : {
                        showingFullScreenSummary = true
                    }) {
                        if meeting.isProcessing || isRetrying {
                            // Show detailed chunk progress when processing
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(meeting.processingState == .transcribing ? "Generating meeting summary..." : formatMarkdownText(meeting.aiSummary))
                                        .themedBody()
                                        .opacity(0.6)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    ProgressView()
                                        .scaleEffect(0.8)
                                }

                                // Show chunk progress if available
                                if meeting.totalChunks > 0 {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(Int(meeting.progressPercentage))% Complete")
                                            .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                                            .foregroundColor(themeManager.currentTheme.accentColor)

                                        ProgressView(value: meeting.progressPercentage, total: 100)
                                            .progressViewStyle(LinearProgressViewStyle(tint: themeManager.currentTheme.accentColor))
                                            .frame(height: 4)

                                        HStack(spacing: 4) {
                                            Image(systemName: "waveform")
                                                .font(.caption2)
                                                .foregroundColor(themeManager.currentTheme.accentColor)
                                            Text("Chunk \(meeting.lastProcessedChunk) of \(meeting.totalChunks)")
                                                .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                                                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                        }
                                    }
                                }
                            }
                        } else {
                            HStack {
                                Text(meeting.processingState == .failed ? (meeting.processingError ?? "Processing failed") : formatMarkdownText(meeting.aiSummary))
                                    .themedBody()
                                    .foregroundColor(meeting.processingState == .failed ? themeManager.currentTheme.destructiveColor : themeManager.currentTheme.textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if meeting.processingState == .failed && meeting.canRetry {
                                    Button("Retry") {
                                        retryTranscription()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(themeManager.currentTheme.accentColor)
                                    .disabled(isRetrying)
                                }
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else if meeting.isProcessing || isRetrying || meeting.processingState == .failed {
                // Show processing or error state even when collapsed
                MeetingDetailCard {
                    if meeting.isProcessing || isRetrying {
                        // Show detailed chunk progress when processing
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(meeting.processingState == .transcribing ? "Processing meeting summary..." : "Processing meeting summary...")
                                    .themedBody()
                                    .opacity(0.6)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                ProgressView()
                                    .scaleEffect(0.8)
                            }

                            // Show chunk progress if available
                            if meeting.totalChunks > 0 {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(Int(meeting.progressPercentage))% Complete")
                                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                                        .foregroundColor(themeManager.currentTheme.accentColor)

                                    ProgressView(value: meeting.progressPercentage, total: 100)
                                        .progressViewStyle(LinearProgressViewStyle(tint: themeManager.currentTheme.accentColor))
                                        .frame(height: 4)

                                    HStack(spacing: 4) {
                                        Image(systemName: "waveform")
                                            .font(.caption2)
                                            .foregroundColor(themeManager.currentTheme.accentColor)
                                        Text("Chunk \(meeting.lastProcessedChunk) of \(meeting.totalChunks)")
                                            .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                    }
                                }
                            }
                        }
                    } else {
                        HStack {
                            Text(meeting.processingState == .failed ? (meeting.processingError ?? "Processing failed") : "Processing meeting summary...")
                                .themedBody()
                                .foregroundColor(meeting.processingState == .failed ? themeManager.currentTheme.destructiveColor : themeManager.currentTheme.textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if meeting.processingState == .failed && meeting.canRetry {
                                Button("Retry") {
                                    retryTranscription()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(themeManager.currentTheme.accentColor)
                                .disabled(isRetrying)
                            }
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "FULL TRANSCRIPT:", alternateTitle: "Full Transcript:")

                Spacer()

                Button(showingTranscript ? "Hide" : "Show") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingTranscript.toggle()
                    }
                }
                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(themeManager.currentTheme.accentColor)
            }

            if showingTranscript {
                MeetingDetailCard(action: {
                    showingFullScreenTranscript = true
                }) {
                    ScrollView {
                        Text(meeting.audioTranscript)
                            .themedBody()
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "MEETING ACTIONS:", alternateTitle: "Meeting Actions:")

                Spacer()

                if meeting.isProcessing {
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "EXTRACTING..." : "Extracting...")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.warningColor)
                }
            }

            if meeting.isProcessing {
                MeetingDetailCard {
                    HStack {
                        Text("Extracting action items from meeting...")
                            .themedBody()
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                            .opacity(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            } else if !relatedActions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(relatedActions.sorted(by: { !$0.isCompleted && $1.isCompleted })) { action in
                        MeetingDetailCard {
                            HStack(spacing: 12) {
                                // Colored priority badge
                                Circle()
                                    .fill(priorityColor(for: action))
                                    .frame(width: 8, height: 8)

                                Text(action.title)
                                    .themedBody()
                                    .foregroundColor(action.isCompleted ? themeManager.currentTheme.secondaryTextColor : themeManager.currentTheme.accentColor)
                                    .strikethrough(action.isCompleted)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if action.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(themeManager.currentTheme.accentColor)
                                }
                            }
                        }
                    }
                }
            } else {
                MeetingDetailCard {
                    Text("No action items found in this meeting")
                        .themedBody()
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(title: String, alternateTitle: String) -> some View {
        Text(themeManager.currentTheme.headerStyle == .brackets ? title : alternateTitle)
            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
    }
    
    private var editButton: some View {
        Button("Edit") {
            startEditingSummary()
        }
        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
        .foregroundColor(themeManager.currentTheme.accentColor)
    }
    
    private var processingLabel: some View {
        Text(themeManager.currentTheme.headerStyle == .brackets ? "PROCESSING..." : "Processing...")
            .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
            .foregroundColor(themeManager.currentTheme.warningColor)
    }
    
    private var summaryEditor: some View {
        TextEditor(text: $tempSummary)
            .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
            .padding()
            .background(themeManager.currentTheme.materialStyle)
            .cornerRadius(themeManager.currentTheme.cornerRadius)
            .frame(minHeight: 300)
            .overlay(
                VStack {
                    HStack {
                        Spacer()
                        Button(themeManager.currentTheme.headerStyle == .brackets ? "SAVE" : "Save") {
                            saveSummary()
                        }
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                    }
                    Spacer()
                }
            )
    }
    
    
    private var fullScreenSummaryView: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(formatMarkdownText(meeting.aiSummary))
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .themedBackground()
            .navigationTitle("Meeting Summary")
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
            .themedBackground()
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
                    // Eve Chat Button
                    Button(action: {
                        navigateToEve(meeting.id)
                    }) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(.body))
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                    .help("Chat with Eve about this meeting")

                    // Share Menu
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

                        if meeting.hasRecording {
                            Divider()

                            Button(action: shareAudio) {
                                if isDownloadingAudio {
                                    Label("Downloading...", systemImage: "arrow.down.circle")
                                } else {
                                    Label("Audio", systemImage: "waveform")
                                }
                            }
                            .disabled(isDownloadingAudio)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(.body))
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                }
            }
        }
    }
    
    
    // MARK: - Helper Methods

    private func formatMarkdownText(_ text: String) -> String {
        // Replace bullet points (asterisks at start of line) with proper bullets
        var processedText = text.replacingOccurrences(of: #"^\* "#, with: "• ", options: .regularExpression)

        // Remove bold markdown for now (simple replacement)
        processedText = processedText.replacingOccurrences(of: "**", with: "")

        return processedText
    }

    private func getMeetingTitle() -> String {
        let meetingTitle = meeting.name.isEmpty ? "UNTITLED MEETING" : meeting.name.uppercased()
        if themeManager.currentTheme.headerStyle == .brackets {
            return "[ \(meetingTitle) ]"
        } else {
            return meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
        }
    }
    
    private func priorityColor(for action: Action) -> Color {
        switch action.priority {
        case .high: return themeManager.currentTheme.destructiveColor
        case .medium: return themeManager.currentTheme.warningColor
        case .low: return themeManager.currentTheme.accentColor
        }
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
        } catch {
            print("Error saving name: \(error)")
        }
    }
    
    private func startEditingSummary() {
        tempSummary = meeting.aiSummary
        isEditingSummary = true
    }
    
    private func saveSummary() {
        meeting.aiSummary = tempSummary
        meeting.dateModified = Date()
        isEditingSummary = false
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving summary: \(error)")
        }
    }
    
    private func shareEverything() {
        let content = """
        Meeting: \(meeting.name.isEmpty ? "Untitled Meeting" : meeting.name)
        Date: \(meeting.dateCreated.formatted())
        Location: \(meeting.location.isEmpty ? "N/A" : meeting.location)
        Duration: \(meeting.durationFormatted)
        
        Notes:
        \(meeting.meetingNotes.isEmpty ? "N/A" : meeting.meetingNotes)
        
        Summary:
        \(meeting.aiSummary.isEmpty ? "N/A" : meeting.aiSummary)
        
        Transcript:
        \(meeting.audioTranscript.isEmpty ? "N/A" : meeting.audioTranscript)
        
        Actions:
        \(relatedActions.isEmpty ? "No actions" : relatedActions.map { action in "- [\(action.priority.rawValue)] \(action.title)" }.joined(separator: "\n"))
        """
        
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-\(meeting.name.isEmpty ? "untitled" : meeting.name).txt")
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
        Meeting: \(meeting.name.isEmpty ? "Untitled Meeting" : meeting.name)
        Date: \(meeting.dateCreated.formatted())
        Location: \(meeting.location.isEmpty ? "N/A" : meeting.location)
        Duration: \(meeting.durationFormatted)
        
        Summary:
        \(meeting.aiSummary.isEmpty ? "No summary available" : meeting.aiSummary)
        """
        
        do {
            let filename = "\(meeting.name.isEmpty ? "Meeting" : meeting.name.replacingOccurrences(of: " ", with: "_"))_Summary_\(dateString).txt"
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
        Meeting: \(meeting.name.isEmpty ? "Untitled Meeting" : meeting.name)
        Date: \(meeting.dateCreated.formatted())
        
        Transcript:
        \(meeting.audioTranscript.isEmpty ? "No transcript available" : meeting.audioTranscript)
        """
        
        do {
            let filename = "\(meeting.name.isEmpty ? "Meeting" : meeting.name.replacingOccurrences(of: " ", with: "_"))_Transcript_\(dateString).txt"
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
    
    private func shareAudio() {
        isDownloadingAudio = true
        downloadProgress = 0

        // Show alert for downloads that might take time
        if meeting.duration > 60 { // Show alert for recordings longer than 1 minute
            showDownloadAlert = true
        }
        
        print("🎵 Starting audio download - Duration: \(meeting.duration)s")
        
        Task {
            do {
                // Get audio URL from Supabase
                guard let audioURL = try await SupabaseManager.shared.getAudioURL(for: meeting.id) else {
                    await MainActor.run {
                        isDownloadingAudio = false
                        showDownloadAlert = false
                        print("❌ No audio URL found")
                    }
                    return
                }
                
                print("🎵 Got audio URL: \(audioURL)")
                
                // Download audio using URLSession
                let session = URLSession(configuration: .default)
                let (tempLocalURL, _) = try await session.download(from: audioURL)
                
                print("🎵 Download completed to: \(tempLocalURL)")
                
                // Create proper filename
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let dateString = dateFormatter.string(from: meeting.dateCreated)
                let filename = "\(meeting.name.isEmpty ? "Meeting" : meeting.name.replacingOccurrences(of: " ", with: "_"))_\(dateString).m4a"
                let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                
                // Move file to proper location with correct name
                try? FileManager.default.removeItem(at: destinationURL) // Remove if exists
                try FileManager.default.moveItem(at: tempLocalURL, to: destinationURL)
                
                await MainActor.run {
                    isDownloadingAudio = false
                    showDownloadAlert = false
                    
                    print("🎵 Presenting share sheet for: \(destinationURL)")
                    
                    // Present share sheet
                    let activityVC = UIActivityViewController(activityItems: [destinationURL], applicationActivities: nil)
                    
                    // Clean up temp file after sharing
                    activityVC.completionWithItemsHandler = { _, _, _, _ in
                        print("🎵 Cleaning up temporary file")
                        try? FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        activityVC.popoverPresentationController?.sourceView = rootVC.view
                        activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                        rootVC.present(activityVC, animated: true)
                        print("🎵 Share sheet presented")
                    } else {
                        print("❌ Could not present share sheet - no root view controller")
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloadingAudio = false
                    showDownloadAlert = false
                    print("❌ Error sharing audio: \(error)")
                    print("❌ Error details: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Refresh Functionality

    @MainActor
    private func refreshJobStatus() async {
        guard let jobId = meeting.transcriptionJobId else {
            print("ℹ️ [MeetingDetail] No job ID to refresh")
            return
        }

        print("🔄 [MeetingDetail] Manual refresh for job: \(jobId)")

        do {
            let status = try await transcriptionService.getJobStatus(jobId: jobId)

            jobStatus = status.status
            jobProgress = status.progressPercentage ?? 0
            jobStage = status.currentStage ?? "Processing..."

            // Update meeting based on status
            if status.status == .completed, let transcript = status.transcript {
                meeting.audioTranscript = transcript

                if let overview = status.overview {
                    meeting.shortSummary = overview
                }

                if let summary = status.summary {
                    meeting.aiSummary = summary
                }

                // Convert backend action items to iOS Action objects
                if let backendActions = status.actions, !backendActions.isEmpty {
                    for backendAction in backendActions {
                        let priority = ActionPriority(rawValue: backendAction.priority) ?? .medium
                        let action = Action(
                            title: backendAction.action,
                            priority: priority,
                            sourceNoteId: meeting.id
                        )
                        modelContext.insert(action)
                    }
                    print("✅ [MeetingDetail] Manual refresh - Created \(backendActions.count) action items")
                }

                meeting.isProcessing = false
                meeting.markCompleted()
                meeting.transcriptionJobId = nil

                if let duration = status.duration {
                    print("✅ [MeetingDetail] Manual refresh - job completed, duration: \(duration)s")
                }

                try? modelContext.save()
            } else if status.status == .failed {
                jobErrorMessage = status.errorMessage ?? "Transcription failed"
                meeting.setProcessingError(jobErrorMessage ?? "Server transcription failed")
                meeting.isProcessing = false
                meeting.transcriptionJobId = nil

                try? modelContext.save()
                print("❌ [MeetingDetail] Manual refresh - job failed: \(jobErrorMessage ?? "unknown")")
            } else {
                print("📊 [MeetingDetail] Manual refresh - job status: \(status.status.displayText)")
            }

            refreshTrigger.toggle()
        } catch {
            print("⚠️ [MeetingDetail] Error refreshing job status: \(error)")
        }
    }

    // MARK: - Retry Functionality

    private func retryTranscription() {
        Task {
            await performRetryTranscription()
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

        let requiredMinutes = max(1, Int(ceil(meeting.duration / 60.0)))
        if minutesManager.currentBalance < requiredMinutes {
            print("⚠️ Cannot retry: insufficient minutes. Required: \(requiredMinutes), Available: \(minutesManager.currentBalance)")
            meeting.setProcessingError("Insufficient minutes for retry. Required: \(requiredMinutes) minutes.")
            return
        }

        isRetrying = true
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

        let backgroundTaskId = backgroundTaskManager.startBackgroundTask(for: meeting.id)
        defer {
            backgroundTaskManager.endBackgroundTask(backgroundTaskId)
            isRetrying = false
        }

        do {
            let transcript = try await openAIService.transcribeAudioFromURL(
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
                meetingId: meeting.id
            )

            meeting.audioTranscript = transcript
            meeting.updateProcessingState(.generatingSummary)
            try? modelContext.save()

            let durationSeconds = Int(meeting.duration)
            var debitSucceeded = true
            if durationSeconds > 0 {
                let debitSuccess = await minutesManager.debitMinutes(
                    seconds: durationSeconds,
                    meetingID: meeting.id.uuidString
                )
                debitSucceeded = debitSuccess
                if !debitSuccess {
                    print("⚠️ Minutes debit failed during retry for meeting \(meeting.id)")
                }
                await UsageTracker.shared.trackMeetingCreated(
                    transcribed: true,
                    meetingSeconds: durationSeconds
                )
            }

            if let latestLocalPath = meeting.localAudioPath {
                let latestURL = URL(fileURLWithPath: latestLocalPath)
                do {
                    _ = try await SupabaseManager.shared.uploadAudioRecording(
                        audioURL: latestURL,
                        meetingId: meeting.id,
                        duration: meeting.duration
                    )
                    meeting.hasRecording = true
                } catch {
                    print("Error uploading audio during retry: \(error)")
                }
            }

            let overview = try await openAIService.generateMeetingOverview(transcript)
            let summary = try await openAIService.summarizeMeeting(transcript)
            let actionItems = try await openAIService.extractActions(transcript)

            meeting.shortSummary = overview
            meeting.aiSummary = summary
            meeting.markCompleted()

            for actionItem in actionItems {
                let priority: ActionPriority
                switch actionItem.priority.uppercased() {
                case "HIGH":
                    priority = .high
                case "MED", "MEDIUM":
                    priority = .medium
                case "LOW":
                    priority = .low
                default:
                    priority = .medium
                }

                let action = Action(
                    title: actionItem.action,
                    priority: priority,
                    sourceNoteId: meeting.id
                )
                modelContext.insert(action)
            }

            if meeting.hasRecording,
               debitSucceeded,
               let latestLocalPath = meeting.localAudioPath,
               FileManager.default.fileExists(atPath: latestLocalPath) {
                try? FileManager.default.removeItem(atPath: latestLocalPath)
                meeting.localAudioPath = nil
            }

            if durationSeconds > 0 && !debitSucceeded {
                meeting.setProcessingError("Minutes debit failed for this transcription. Please refresh your balance.")
            }

            do {
                try modelContext.save()
            } catch {
                print("Error saving retry results: \(error)")
            }

            await NotificationService.shared.sendProcessingCompleteNotification(
                for: meeting.id,
                meetingName: meeting.name
            )

        } catch {
            print("Error during retry: \(error)")
            meeting.setProcessingError("Transcription failed again. Please try later.")
        }
    }
}

private struct MeetingProcessingStatusView: View {
    let theme: AppTheme
    let isRetrying: Bool
    let processingState: ProcessingState
    let progress: Double
    let chunkIndex: Int
    let totalChunks: Int

    private var normalizedProgress: Double {
        min(max(progress, 0), 100)
    }

    private var percentageText: String {
        "\(Int(normalizedProgress))% Complete"
    }

    private var titleText: String {
        let base: String
        switch processingState {
        case .transcribing:
            base = isRetrying ? "Retrying transcription..." : "Processing meeting..."
        case .generatingSummary:
            base = "Generating meeting insights..."
        default:
            base = "Processing..."
        }

        return theme.headerStyle == .brackets ? base.uppercased() : base
    }

    private var stageDescription: String {
        switch processingState {
        case .transcribing:
            return isRetrying ? "Retrying transcription..." : "Transcribing meeting audio..."
        case .generatingSummary:
            return "Creating meeting summary and action items..."
        default:
            return ""
        }
    }

    private var shouldShowChunkInfo: Bool {
        processingState == .transcribing && totalChunks > 1
    }

    private var shouldShowSpinner: Bool {
        totalChunks == 0 && normalizedProgress == 0
    }

    var body: some View {
        MeetingDetailCard {
            VStack(spacing: 20) {
                Text(titleText)
                    .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(theme.warningColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 10) {
                    Text(percentageText)
                        .font(.system(.title3, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                        .foregroundColor(theme.accentColor)

                    ProgressView(value: normalizedProgress, total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: theme.accentColor))
                        .frame(height: 8)
                        .scaleEffect(x: 1, y: 1.4, anchor: .center)

                    if !stageDescription.isEmpty {
                        Text(stageDescription)
                            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                            .foregroundColor(theme.secondaryTextColor)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }

                    if shouldShowChunkInfo {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.caption2)
                                .foregroundColor(theme.accentColor)
                            Text("Chunk \(max(chunkIndex, 1)) of \(totalChunks)")
                                .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                                .foregroundColor(theme.secondaryTextColor)
                        }
                        .padding(.top, 4)
                    }
                }

                if shouldShowSpinner {
                    ProgressView()
                        .scaleEffect(1.4)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 16)
        }
    }
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
