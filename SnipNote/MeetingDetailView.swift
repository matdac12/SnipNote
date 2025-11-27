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
    @State private var jobPollingTask: Task<Void, Never>?
    @StateObject private var transcriptionService = RenderTranscriptionService()

    // Animation state for server processing
    @State private var pulseAnimation = false
    @State private var shimmerAnimation = false
    @State private var rotationAnimation = false

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
                        actionsSection
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
            } else if meeting.transcriptionJobId != nil {
                // Job ID exists but status not loaded yet - show upload state
                uploadingCard()
            } else if meeting.isProcessing {
                // No job ID yet - we're in the upload phase
                uploadingCard()
            } else {
                // Fallback to old processing view (for on-device transcription)
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
    private func uploadingCard() -> some View {
        let theme = themeManager.currentTheme

        VStack(spacing: 24) {
            // Animated header with rotating cloud icon
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                    .font(.title2)
                    .foregroundColor(theme.accentColor)
                    .rotationEffect(.degrees(rotationAnimation ? 360 : 0))
                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: rotationAnimation)
                    .onAppear { rotationAnimation = true }

                Text("Uploading to server...")
                    .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(theme.textColor)
            }

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Preparing your meeting for transcription...")
                        .font(.system(.callout, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                        .foregroundColor(theme.accentColor.opacity(0.8))
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 1.5)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            theme.backgroundColor,
                            theme.accentColor.opacity(0.05)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 1.5)
                .stroke(theme.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func asyncJobStatusCard(jobId: String, status: JobStatus) -> some View {
        let theme = themeManager.currentTheme

        VStack(spacing: 24) {
            // Animated header with rotating cloud icon
            HStack(spacing: 12) {
                Image(systemName: status.isInProgress ? "cloud.fill" : (status == .failed ? "xmark.circle.fill" : "checkmark.circle.fill"))
                    .font(.title2)
                    .foregroundColor(status.isInProgress ? theme.accentColor : (status == .failed ? theme.destructiveColor : .green))
                    .rotationEffect(.degrees(status.isInProgress && rotationAnimation ? 360 : 0))
                    .animation(status.isInProgress ? .linear(duration: 3).repeatForever(autoreverses: false) : .default, value: rotationAnimation)
                    .onAppear {
                        if status.isInProgress {
                            rotationAnimation = true
                        }
                    }

                Text("Server Transcription")
                    .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(theme.textColor)
            }

            if status.isInProgress {
                // Progress percentage with pulsing animation
                VStack(spacing: 16) {
                    // Show different message for initial upload vs processing
                    if jobProgress == 0 && status == .pending {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Uploading to server...")
                                .font(.system(.title3, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                                .foregroundColor(theme.accentColor)
                        }
                    } else {
                        Text("\(jobProgress)% Complete")
                            .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                            .foregroundColor(theme.accentColor)
                            .scaleEffect(pulseAnimation ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulseAnimation)
                            .onAppear { pulseAnimation = true }
                    }

                    // Encouraging message based on progress
                    if jobProgress > 0 {
                        Text(serverEncouragingMessage(progress: jobProgress))
                            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                            .foregroundColor(theme.accentColor.opacity(0.8))
                            .transition(.opacity)
                            .animation(.easeInOut, value: jobProgress)
                    } else if status == .pending {
                        Text("Preparing your meeting for transcription...")
                            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                            .foregroundColor(theme.accentColor.opacity(0.8))
                    }

                    // Enhanced progress bar with shimmer (only show when progress > 0)
                    if jobProgress > 0 {
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.secondaryTextColor.opacity(0.2))
                                .frame(height: 12)

                            // Progress fill with gradient
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            theme.accentColor,
                                            theme.accentColor.opacity(0.7),
                                            theme.accentColor
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: CGFloat(jobProgress) / 100 * (UIScreen.main.bounds.width - 80), height: 12)
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: jobProgress)

                            // Shimmer overlay
                            if jobProgress > 0 && jobProgress < 100 {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0),
                                                Color.white.opacity(0.5),
                                                Color.white.opacity(0)
                                            ]),
                                            startPoint: shimmerAnimation ? .leading : .trailing,
                                            endPoint: shimmerAnimation ? .trailing : .leading
                                        )
                                    )
                                    .frame(width: CGFloat(jobProgress) / 100 * (UIScreen.main.bounds.width - 80), height: 12)
                                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: shimmerAnimation)
                                    .onAppear { shimmerAnimation = true }
                            }
                        }
                        .frame(height: 12)
                    }

                    // Stage description with fade animation (only show when progress > 0)
                    if jobProgress > 0 && !jobStage.isEmpty {
                        Text(jobStage)
                            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                            .foregroundColor(theme.secondaryTextColor)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                            .animation(.easeInOut, value: jobStage)
                    }

                    // Estimated time with clock icon (only show when processing)
                    if jobProgress > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.caption2)
                                .foregroundColor(theme.accentColor.opacity(0.7))
                            Text(serverEstimatedMessage())
                                .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                                .foregroundColor(theme.secondaryTextColor.opacity(0.8))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(theme.accentColor.opacity(0.1))
                        )
                    }
                }
            } else {
                // Status indicator for completed/failed
                HStack(spacing: 12) {
                    Text(status.displayText)
                        .font(.system(.title3, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                        .foregroundColor(status == .failed ? theme.destructiveColor : .green)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 1.5)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            theme.backgroundColor,
                            theme.accentColor.opacity(0.05)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius * 1.5)
                .stroke(theme.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    // Server-specific encouraging messages
    private func serverEncouragingMessage(progress: Int) -> String {
        if progress < 25 {
            return "Processing on our servers..."
        } else if progress < 50 {
            return "Making great progress!"
        } else if progress < 75 {
            return "More than halfway there!"
        } else if progress < 95 {
            return "Almost finished!"
        } else {
            return "Final touches..."
        }
    }

    // Server-specific estimated completion message
    private func serverEstimatedMessage() -> String {
        // Based on server processing: ~8% of audio duration with 1.5x buffer
        // This gets set by the notification system already
        if jobProgress < 30 {
            return "Should be ready soon - check back in a few minutes"
        } else if jobProgress < 70 {
            return "Progressing smoothly - almost there!"
        } else {
            return "Nearly complete - hang tight!"
        }
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
                    Text("Extracting...")
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
        Text(alternateTitle)
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
        Text("Processing...")
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
                        Button("Save") {
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
        return meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
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

            // Sync to Supabase
            Task {
                do {
                    try await SupabaseManager.shared.saveMeeting(meeting)
                } catch {
                    print("⚠️ Failed to sync meeting summary to Supabase: \(error)")
                }
            }
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

    private func updatePollingTask(for jobId: String?) async {
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
            self.jobId = jobId
            // Set initial pending status immediately to show new UI without lag
            self.jobStatus = .pending
            self.jobStage = "Uploading to server..."
            self.jobProgress = 0
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

                let isFinal = await MainActor.run { applyJobStatusUpdate(status: status) }

                if isFinal {
                    break pollingLoop
                }

                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                if Task.isCancelled { break }

                // Check if max retries exceeded - trigger fallback
                if let transcriptionError = error as? TranscriptionError,
                   case .maxRetriesExceeded = transcriptionError {
                    print("❌ [MeetingDetail] Max retries exceeded - attempting on-device fallback")
                    await attemptOnDeviceFallback()
                    break pollingLoop
                }

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

            meeting.markCompleted()
            meeting.transcriptionJobId = nil
            jobId = nil

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
            return false
        }
    }

    private func refreshJobStatus() async {
        guard let jobId = meeting.transcriptionJobId else {
            print("ℹ️ [MeetingDetail] No job ID to refresh")
            return
        }

        print("🔄 [MeetingDetail] Manual refresh for job: \(jobId)")

        do {
            let status = try await transcriptionService.getJobStatus(jobId: jobId)

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

                // Sync updated meeting to Supabase
                Task {
                    do {
                        try await SupabaseManager.shared.saveMeeting(meeting)
                    } catch {
                        print("⚠️ Failed to sync retry results to Supabase: \(error)")
                    }
                }
            } catch {
                print("Error saving retry results: \(error)")
            }

            // Cancel estimated notification before sending completion (retry succeeded)
            NotificationService.shared.cancelEstimatedCompletionNotification(for: meeting.id)

            await NotificationService.shared.sendProcessingCompleteNotification(
                for: meeting.id,
                meetingName: meeting.name
            )

        } catch {
            print("Error during retry: \(error)")
            meeting.setProcessingError("Transcription failed again. Please try later.")
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
        let requiredMinutes = max(1, Int(ceil(meeting.duration / 60.0)))

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

        return base
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
