//
//  NoteDetailView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct NoteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note
    @EnvironmentObject var themeManager: ThemeManager
    
    @Query private var allActions: [Action]
    
    @State private var isEditingTitle = false
    @State private var isEditingSummary = false
    @State private var tempTitle = ""
    @State private var tempSummary = ""
    @State private var isDownloadingAudio = false
    @State private var downloadProgress: Double = 0
    @State private var showDownloadAlert = false
    @StateObject private var audioPlayer = AudioPlayerManager()
    
    private var relatedActions: [Action] {
        allActions.filter { $0.sourceNoteId == note.id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if isEditingTitle {
                        TextField("Title", text: $tempTitle)
                            .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .textFieldStyle(PlainTextFieldStyle())
                            .onSubmit {
                                saveTitle()
                            }
                    } else {
                        Text(themeManager.currentTheme.headerStyle == .brackets ? "[ \(note.title.isEmpty ? "UNTITLED" : note.title.uppercased()) ]" : (note.title.isEmpty ? "Untitled" : note.title))
                            .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .lineLimit(1)
                            .onTapGesture {
                                startEditingTitle()
                            }
                    }
                    
                    HStack {
                        if note.duration > 0 {
                            HStack(spacing: 8) {
                                Text("⏱️ \(note.durationFormatted)")
                                    .themedCaption()
                                
                                if note.hasRecording {
                                    MiniAudioPlayer(audioPlayer: audioPlayer, item: note) { note in
                                        await audioPlayer.loadAndPlayAudio(for: note)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                Text(note.dateCreated, style: .date)
                    .themedCaption()
            }
            .padding()
            .background(themeManager.currentTheme.materialStyle)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRANSCRIPT:")
                            .font(.system(.headline, design: .monospaced, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Text(note.originalTranscript)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(themeManager.currentTheme.materialStyle)
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("AI SUMMARY:")
                                .font(.system(.headline, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if !note.isProcessing {
                                Button("EDIT") {
                                    startEditingSummary()
                                }
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundColor(.blue)
                            } else {
                                Text("PROCESSING...")
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        if isEditingSummary {
                            TextEditor(text: $tempSummary)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .background(themeManager.currentTheme.materialStyle)
                                .cornerRadius(8)
                                .frame(minHeight: 200)
                                .overlay(
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Button("SAVE") {
                                                saveSummary()
                                            }
                                            .font(.system(.caption, design: .monospaced, weight: .bold))
                                            .foregroundColor(.green)
                                            .padding(.top, 8)
                                            .padding(.trailing, 8)
                                        }
                                        Spacer()
                                    }
                                )
                        } else {
                            HStack {
                                Text(note.aiSummary)
                                    .font(.system(.body, design: .monospaced))
                                    .opacity(note.isProcessing ? 0.6 : 1.0)
                                
                                if note.isProcessing {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding()
                            .background(themeManager.currentTheme.materialStyle)
                            .cornerRadius(8)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("RELATED ACTIONS:")
                                .font(.system(.headline, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if note.isProcessing {
                                Text("EXTRACTING...")
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        if note.isProcessing {
                            HStack {
                                Text("Extracting actionable items from your note...")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .opacity(0.6)
                                
                                Spacer()
                                
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            .padding()
                            .background(themeManager.currentTheme.materialStyle)
                            .cornerRadius(8)
                        } else if !relatedActions.isEmpty {
                            ForEach(relatedActions.sorted(by: { !$0.isCompleted && $1.isCompleted })) { action in
                                HStack {
                                    Text("[\(action.priority.rawValue)]")
                                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                                        .foregroundColor(action.priority == .high ? .red : action.priority == .medium ? .orange : .green)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background((action.priority == .high ? Color.red : action.priority == .medium ? Color.orange : Color.green).opacity(0.2))
                                        .cornerRadius(3)
                                    
                                    Text(action.title)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(action.isCompleted ? .secondary : .green)
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
                                .cornerRadius(8)
                            }
                        } else {
                            Text("No actionable items found in this note")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding()
                                .background(themeManager.currentTheme.materialStyle)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
        }
        .themedBackground()
        .foregroundColor(themeManager.currentTheme.accentColor)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            if note.isProcessing {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(themeManager.currentTheme.headerStyle == .brackets ? "GO TO NOTES" : "Go to Notes") {
                        // Navigation will happen automatically via back button
                    }
                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.accentColor)
                }
            } else if !note.originalTranscript.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
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
                        
                        if note.hasRecording {
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
        .onAppear {
            tempTitle = note.title
            tempSummary = note.aiSummary
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
    
    private func startEditingTitle() {
        tempTitle = note.title
        isEditingTitle = true
    }
    
    private func saveTitle() {
        note.title = tempTitle
        note.dateModified = Date()
        isEditingTitle = false
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving title: \(error)")
        }
    }
    
    private func startEditingSummary() {
        tempSummary = note.aiSummary
        isEditingSummary = true
    }
    
    private func saveSummary() {
        note.aiSummary = tempSummary
        note.dateModified = Date()
        isEditingSummary = false
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving summary: \(error)")
        }
    }
    
    // MARK: - Share Functions
    
    private func shareEverything() {
        let content = """
        Note: \(note.title.isEmpty ? "Untitled Note" : note.title)
        Date: \(note.dateCreated.formatted())
        Duration: \(note.durationFormatted)
        
        Summary:
        \(note.aiSummary.isEmpty ? "N/A" : note.aiSummary)
        
        Transcript:
        \(note.originalTranscript.isEmpty ? "N/A" : note.originalTranscript)
        
        Actions:
        \(relatedActions.isEmpty ? "No actions" : relatedActions.map { action in "- [\(action.priority.rawValue)] \(action.title)" }.joined(separator: "\n"))
        """
        
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("note-\(note.title.isEmpty ? "untitled" : note.title).txt")
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
        let dateString = dateFormatter.string(from: note.dateCreated)
        
        let content = """
        Note: \(note.title.isEmpty ? "Untitled Note" : note.title)
        Date: \(note.dateCreated.formatted())
        Duration: \(note.durationFormatted)
        
        Summary:
        \(note.aiSummary.isEmpty ? "No summary available" : note.aiSummary)
        """
        
        do {
            let filename = "\(note.title.isEmpty ? "Note" : note.title.replacingOccurrences(of: " ", with: "_"))_Summary_\(dateString).txt"
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
        let dateString = dateFormatter.string(from: note.dateCreated)
        
        let content = """
        Note: \(note.title.isEmpty ? "Untitled Note" : note.title)
        Date: \(note.dateCreated.formatted())
        
        Transcript:
        \(note.originalTranscript.isEmpty ? "No transcript available" : note.originalTranscript)
        """
        
        do {
            let filename = "\(note.title.isEmpty ? "Note" : note.title.replacingOccurrences(of: " ", with: "_"))_Transcript_\(dateString).txt"
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
        if note.duration > 60 { // Show alert for recordings longer than 1 minute
            showDownloadAlert = true
        }
        
        print("🎵 Starting audio download - Duration: \(note.duration)s")
        
        Task {
            do {
                // Get audio URL from Supabase
                guard let audioURL = try await SupabaseManager.shared.getNoteAudioURL(for: note.id) else {
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
                let dateString = dateFormatter.string(from: note.dateCreated)
                let filename = "\(note.title.isEmpty ? "Note" : note.title.replacingOccurrences(of: " ", with: "_"))_\(dateString).m4a"
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