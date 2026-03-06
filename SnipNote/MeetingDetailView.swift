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

    @State private var isEditingName = false
    @State private var tempName = ""
    @State private var showingNotes = true
    @State private var showingOverview = true
    @State private var showingTranscript = false
    @State private var showingSummary = true
    @State private var showingActions = true
    @State private var showingFullScreenSummary = false
    @State private var showingFullScreenTranscript = false

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

    private var relatedActions: [Action] {
        allActions.filter { $0.sourceNoteId == meeting.id }
    }

    private var theme: AppTheme {
        themeManager.currentTheme
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
                        meeting.processingStateRaw != fetchedMeeting.processingStateRaw ||
                        meeting.audioTranscript != fetchedMeeting.audioTranscript ||
                        meeting.shortSummary != fetchedMeeting.shortSummary ||
                        meeting.aiSummary != fetchedMeeting.aiSummary

                    guard hasChanged else { return }

                    meeting.lastProcessedChunk = fetchedMeeting.lastProcessedChunk
                    meeting.totalChunks = fetchedMeeting.totalChunks
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
                            meeting.processingStateRaw != fetchedMeeting.processingStateRaw ||
                            meeting.audioTranscript != fetchedMeeting.audioTranscript ||
                            meeting.shortSummary != fetchedMeeting.shortSummary ||
                            meeting.aiSummary != fetchedMeeting.aiSummary

                        guard hasChanged else { return }

                        meeting.lastProcessedChunk = fetchedMeeting.lastProcessedChunk
                        meeting.totalChunks = fetchedMeeting.totalChunks
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
            // Show async job status if available (server-side processing)
            if let _ = meeting.transcriptionJobId, let status = jobStatus {
                if status.isInProgress {
                    let isUploading = status == .pending
                    // Server-side: use minimalist processing view
                    MinimalistProcessingView(
                        phase: jobProgress == 0 && status == .pending ? .uploading : .transcribing,
                        progress: Double(jobProgress),
                        stageDescription: jobStage.isEmpty ? (status == .pending ? "Preparing transcription..." : "Processing on server...") : jobStage,
                        showPercentage: !isUploading,
                        infoMessage: isUploading ? "Keep SnipNote open while uploading." : "Upload complete. You can close the app.",
                        estimatedTimeRemaining: jobProgress >= 25 ? serverEstimatedTimeRemaining() : nil,
                        currentChunk: nil,
                        totalChunks: nil,
                        partialTranscript: nil  // Server-side has no partial transcript
                    )
                } else if status == .failed {
                    // Show error state
                    serverErrorCard()
                }
                // If completed, processingStatusSection won't be shown (meeting.isProcessing = false)
            } else if meeting.transcriptionJobId != nil || meeting.isProcessing {
                // Job ID exists but status not loaded yet, or in upload phase
                MinimalistProcessingView(
                    phase: .uploading,
                    progress: 0,
                    stageDescription: "Uploading to server...",
                    showPercentage: false,
                    infoMessage: "Keep SnipNote open while uploading.",
                    estimatedTimeRemaining: nil,
                    currentChunk: nil,
                    totalChunks: nil,
                    partialTranscript: nil
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
        editorialSection(title: "Meeting Notes", isExpanded: $showingNotes) {
            Text(meeting.meetingNotes)
                .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(theme.textColor)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
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

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(theme.warningColor)
                    .font(.title3)

                Text("Something went wrong")
                    .font(.system(.headline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.textColor)
            }

            Text("We couldn't process this meeting. Please try again.")
                .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(theme.secondaryTextColor)

            if meeting.canRetry {
                Button {
                    retryTranscription()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Processing")
                    }
                    .font(.system(.subheadline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.backgroundColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(theme.accentColor)
                    .cornerRadius(theme.cornerRadius)
                }
                .disabled(isRetrying)
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
    
    private var actionsSection: some View {
        editorialSection(title: "Actions", isExpanded: $showingActions) {
            if !relatedActions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(relatedActions.sorted(by: { !$0.isCompleted && $1.isCompleted })) { action in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(priorityColor(for: action))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            Text(action.title)
                                .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                                .foregroundColor(action.isCompleted ? theme.secondaryTextColor : theme.textColor)
                                .strikethrough(action.isCompleted)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if action.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(theme.accentColor)
                            }
                        }
                    }
                }
            } else {
                Text("No action items found in this meeting")
                    .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(theme.secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                    // Eve Chat Button - navigates to Eve with this meeting pre-selected
                    NavigationLink(destination: EveView(preSelectedMeetingId: meeting.id)) {
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

    @ViewBuilder
    private func markdownSummaryText(_ text: String) -> some View {
        let blocks = summaryBlocks(from: text)

        if blocks.isEmpty {
            Text(text)
                .themedBody()
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
        return meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
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

            let shouldUploadAudio = await MainActor.run {
                !LocalTranscriptionManager.shared.isLocalModeEnabled
            }
            var uploadedAudioPath: String?

            if shouldUploadAudio, let latestLocalPath = meeting.localAudioPath {
                let latestURL = URL(fileURLWithPath: latestLocalPath)
                do {
                    uploadedAudioPath = try await SupabaseManager.shared.uploadAudioRecording(
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
            HapticService.shared.success()

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

            let shouldDeleteLocalAudio = meeting.hasRecording || !shouldUploadAudio

            if shouldDeleteLocalAudio,
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

                        if let uploadedAudioPath {
                            try await SupabaseManager.shared.saveCompletedTranscriptionJob(
                                meetingId: meeting.id,
                                audioStoragePath: uploadedAudioPath,
                                duration: meeting.duration,
                                transcript: meeting.audioTranscript,
                                overview: overview,
                                summary: summary,
                                actions: actionItems
                            )
                        }
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
