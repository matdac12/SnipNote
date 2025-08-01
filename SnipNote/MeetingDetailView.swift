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
    @State private var isEditingSummary = false
    @State private var tempName = ""
    @State private var tempSummary = ""
    @State private var showingTranscript = false
    @State private var showingExportMenu = false
    
    private var relatedActions: [Action] {
        allActions.filter { $0.sourceNoteId == meeting.id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            meetingHeaderView
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
        .sheet(isPresented: $showingExportMenu) {
            exportMenuSheet
        }
    }
    
    // MARK: - Header View
    
    private var meetingHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
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
                        .lineLimit(1)
                        .onTapGesture {
                            startEditingName()
                        }
                }
                
                HStack {
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
        }
        .padding()
        .background(themeManager.currentTheme.materialStyle)
    }
    
    // MARK: - Content Sections
    
    private var meetingNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "MEETING NOTES:", alternateTitle: "Meeting Notes:")
            
            Text(meeting.meetingNotes)
                .themedBody()
                .padding()
                .background(themeManager.currentTheme.materialStyle)
                .cornerRadius(themeManager.currentTheme.cornerRadius)
        }
    }
    
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "OVERVIEW:", alternateTitle: "Overview:")
            
            HStack {
                Text(meeting.shortSummary)
                    .themedBody()
                    .opacity(meeting.isProcessing ? 0.6 : 1.0)
                
                if meeting.isProcessing {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()
            .background(themeManager.currentTheme.materialStyle)
            .cornerRadius(themeManager.currentTheme.cornerRadius)
        }
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader(title: "MEETING SUMMARY:", alternateTitle: "Meeting Summary:")
                
                Spacer()
                
                if !meeting.isProcessing {
                    editButton
                } else {
                    processingLabel
                }
            }
            
            if isEditingSummary {
                summaryEditor
            } else {
                summaryDisplay
            }
        }
    }
    
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader(title: "FULL TRANSCRIPT:", alternateTitle: "Full Transcript:")
                
                Spacer()
                
                Button(showingTranscript ? "HIDE" : "SHOW") {
                    withAnimation {
                        showingTranscript.toggle()
                    }
                }
                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(themeManager.currentTheme.accentColor)
            }
            
            if showingTranscript {
                ScrollView {
                    Text(meeting.audioTranscript)
                        .themedBody()
                        .padding()
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                }
                .frame(maxHeight: 300)
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                processingActionsView
            } else if !relatedActions.isEmpty {
                ForEach(relatedActions.sorted(by: { !$0.isCompleted && $1.isCompleted })) { action in
                    actionRow(for: action)
                }
            } else {
                noActionsView
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
        Button(themeManager.currentTheme.headerStyle == .brackets ? "EDIT" : "Edit") {
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
    
    private var summaryDisplay: some View {
        HStack {
            Text(meeting.aiSummary)
                .themedBody()
                .opacity(meeting.isProcessing ? 0.6 : 1.0)
            
            if meeting.isProcessing {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
        .background(themeManager.currentTheme.materialStyle)
        .cornerRadius(themeManager.currentTheme.cornerRadius)
    }
    
    private var processingActionsView: some View {
        HStack {
            Text("Extracting action items from meeting...")
                .themedBody()
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                .opacity(0.6)
            
            Spacer()
            
            ProgressView()
                .scaleEffect(0.8)
        }
        .padding()
        .background(themeManager.currentTheme.materialStyle)
        .cornerRadius(themeManager.currentTheme.cornerRadius)
    }
    
    private func actionRow(for action: Action) -> some View {
        HStack {
            Text(themeManager.currentTheme.headerStyle == .brackets ? "[\(action.priority.rawValue)]" : action.priority.rawValue)
                .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(priorityColor(for: action))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(priorityColor(for: action).opacity(0.2))
                .cornerRadius(3)
            
            Text(action.title)
                .themedBody()
                .foregroundColor(action.isCompleted ? themeManager.currentTheme.secondaryTextColor : themeManager.currentTheme.accentColor)
                .strikethrough(action.isCompleted)
                .lineLimit(2)
            
            Spacer()
            
            if action.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(themeManager.currentTheme.accentColor)
            }
        }
        .padding()
        .background(themeManager.currentTheme.materialStyle)
        .cornerRadius(themeManager.currentTheme.cornerRadius)
    }
    
    private var noActionsView: some View {
        Text("No action items found in this meeting")
            .themedBody()
            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
            .padding()
            .background(themeManager.currentTheme.materialStyle)
            .cornerRadius(themeManager.currentTheme.cornerRadius)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if meeting.isProcessing {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(themeManager.currentTheme.headerStyle == .brackets ? "GO TO MEETINGS" : "Go to Meetings") {
                    // Navigation will happen automatically via back button
                }
                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(themeManager.currentTheme.accentColor)
            }
        } else if !meeting.audioTranscript.isEmpty {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingExportMenu = true
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(.body))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                }
            }
        }
    }
    
    private var exportMenuSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Export Meeting")
                    .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                
                Button(action: {
                    sharePlainText()
                    showingExportMenu = false
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Export as Plain Text")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.currentTheme.materialStyle)
                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                }
                
                Spacer()
            }
            .padding()
            .themedBackground()
            .navigationBarTitle("Export Options", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingExportMenu = false
                    }
                    .foregroundColor(themeManager.currentTheme.accentColor)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
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
    
    private func sharePlainText() {
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
}