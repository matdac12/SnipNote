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
    
    private var relatedActions: [Action] {
        allActions.filter { $0.sourceNoteId == meeting.id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            meetingHeaderView
            
            ScrollView {
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
                HStack {
                    Text(meeting.shortSummary)
                        .themedBody()
                        .opacity(meeting.isProcessing ? 0.6 : 1.0)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if meeting.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
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
                    MeetingDetailCard(action: {
                        showingFullScreenSummary = true
                    }) {
                        HStack {
                            Text(formatMarkdownText(meeting.aiSummary))
                                .themedBody()
                                .opacity(meeting.isProcessing ? 0.6 : 1.0)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if meeting.isProcessing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else if meeting.isProcessing {
                // Show processing state even when collapsed
                MeetingDetailCard {
                    HStack {
                        Text("Processing meeting summary...")
                            .themedBody()
                            .opacity(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ProgressView()
                            .scaleEffect(0.8)
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