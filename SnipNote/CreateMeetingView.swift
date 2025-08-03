//
//  CreateMeetingView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData
import AVFoundation

struct CreateMeetingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    
    var onMeetingCreated: ((Meeting) -> Void)?
    var importedAudioURL: URL? // For shared audio files
    
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var openAIService = OpenAIService.shared
    
    @State private var meetingName = ""
    @State private var meetingLocation = ""
    @State private var meetingNotes = ""
    @State private var isRecording = false
    @State private var currentRecordingURL: URL?
    @State private var createdMeeting: Meeting?
    @State private var createdMeetingId: UUID?
    @State private var showingAPIKeyAlert = false
    @State private var apiKeyInput = ""
    @State private var recordingStartTime: Date?
    @State private var hasFinishedRecording = false
    
    // Timer for recording duration display
    @State private var recordingTimer: Timer?
    @State private var recordingDuration: TimeInterval = 0
    
    // Processing state
    @State private var isProcessingAudio = false
    
    // Focus state for notes field
    @FocusState private var isNotesFieldFocused: Bool
    
    // Computed properties for imported audio mode
    private var hasImportedAudio: Bool {
        let hasAudio = importedAudioURL != nil
        print("🎵 hasImportedAudio: \(hasAudio), URL: \(importedAudioURL?.absoluteString ?? "nil")")
        return hasAudio
    }
    
    private var importedAudioDuration: TimeInterval {
        guard let url = importedAudioURL else { 
            print("❌ No imported audio URL")
            return 0 
        }
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            print("🎵 Audio duration calculated: \(duration) seconds")
            return duration
        } catch {
            print("❌ Failed to read audio file: \(error)")
            return 0
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text(themeManager.currentTheme.headerStyle == .brackets ? "[ NEW MEETING ]" : "New Meeting")
                    .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.textColor)
                Spacer()
            }
            .padding()
            .background(themeManager.currentTheme.materialStyle)
            
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Meeting Details Form
                    VStack(alignment: .leading, spacing: 16) {
                        Text(themeManager.currentTheme.headerStyle == .brackets ? "MEETING DETAILS" : "Meeting Details")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Meeting Name")
                                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                TextField("Enter meeting name", text: $meetingName)
                                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                                    .padding()
                                    .background(themeManager.currentTheme.materialStyle)
                                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Location")
                                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                TextField("Enter meeting location", text: $meetingLocation)
                                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                                    .padding()
                                    .background(themeManager.currentTheme.materialStyle)
                                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Notes")
                                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                    
                                    Spacer()
                                    
                                    if isNotesFieldFocused {
                                        Button(action: {
                                            // Dismiss keyboard
                                            isNotesFieldFocused = false
                                        }) {
                                            Image(systemName: "keyboard.chevron.compact.down")
                                                .font(.system(.caption))
                                                .foregroundColor(themeManager.currentTheme.accentColor)
                                        }
                                        .transition(.opacity)
                                    }
                                }
                                .animation(.easeInOut(duration: 0.2), value: isNotesFieldFocused)
                                
                                TextEditor(text: $meetingNotes)
                                    .focused($isNotesFieldFocused)
                                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                                    .padding()
                                    .background(themeManager.currentTheme.materialStyle)
                                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                                    .frame(minHeight: 100)
                            }
                        }
                    }
                    
                    // Recording Section
                    VStack(spacing: 20) {
                        
                        if hasImportedAudio {
                            VStack(spacing: 20) {
                                Text(themeManager.currentTheme.headerStyle == .brackets ? "IMPORTED AUDIO READY" : "Imported Audio Ready")
                                    .font(.system(.title, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(themeManager.currentTheme.accentColor)
                                
                                Text("Duration: \(formatDuration(importedAudioDuration))")
                                    .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(themeManager.currentTheme.accentColor)
                                
                                Rectangle()
                                    .fill(themeManager.currentTheme.accentColor)
                                    .frame(width: 200, height: 4)
                                    .opacity(0.7)
                                
                                if hasFinishedRecording || isProcessingAudio {
                                    VStack(spacing: 20) {
                                        Text(themeManager.currentTheme.headerStyle == .brackets ? "PROCESSING MEETING..." : "Processing meeting...")
                                            .font(.system(.title, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                            .foregroundColor(themeManager.currentTheme.warningColor)
                                        
                                        ProgressView()
                                            .scaleEffect(1.5)
                                    }
                                } else {
                                    Button(themeManager.currentTheme.headerStyle == .brackets ? "ANALYZE MEETING" : "Analyze Meeting") {
                                        analyzeImportedAudio()
                                    }
                                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(themeManager.currentTheme.backgroundColor)
                                    .padding()
                                    .background(themeManager.currentTheme.accentColor)
                                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                                    .disabled(meetingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        } else if audioRecorder.isRecording {
                            VStack(spacing: 20) {
                                Text(themeManager.currentTheme.headerStyle == .brackets ? (audioRecorder.isPaused ? "MEETING PAUSED" : "RECORDING MEETING...") : (audioRecorder.isPaused ? "Meeting Paused" : "Recording Meeting..."))
                                    .font(.system(.title, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(audioRecorder.isPaused ? themeManager.currentTheme.warningColor : themeManager.currentTheme.destructiveColor)
                                
                                Text(formatDuration(recordingDuration))
                                    .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(audioRecorder.isPaused ? themeManager.currentTheme.warningColor : themeManager.currentTheme.destructiveColor)
                                
                                if !audioRecorder.isPaused {
                                    Rectangle()
                                        .fill(themeManager.currentTheme.destructiveColor)
                                        .frame(width: CGFloat(audioRecorder.recordingLevel * 200), height: 4)
                                        .animation(.easeInOut(duration: 0.1), value: audioRecorder.recordingLevel)
                                } else {
                                    Rectangle()
                                        .fill(themeManager.currentTheme.warningColor)
                                        .frame(width: 200, height: 4)
                                        .opacity(0.5)
                                }
                                
                                HStack(spacing: 16) {
                                    if audioRecorder.isPaused {
                                        Button(themeManager.currentTheme.headerStyle == .brackets ? "RESUME" : "Resume") {
                                            resumeMeetingRecording()
                                        }
                                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                        .foregroundColor(themeManager.currentTheme.backgroundColor)
                                        .padding()
                                        .background(themeManager.currentTheme.accentColor)
                                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                                    } else {
                                        Button(themeManager.currentTheme.headerStyle == .brackets ? "PAUSE" : "Pause") {
                                            pauseMeetingRecording()
                                        }
                                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                        .foregroundColor(themeManager.currentTheme.backgroundColor)
                                        .padding()
                                        .background(themeManager.currentTheme.warningColor)
                                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                                    }
                                    
                                    Button(themeManager.currentTheme.headerStyle == .brackets ? "STOP MEETING" : "Stop Meeting") {
                                        stopMeetingRecording()
                                    }
                                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(themeManager.currentTheme.backgroundColor)
                                    .padding()
                                    .background(themeManager.currentTheme.destructiveColor)
                                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                                    
                                    Button(themeManager.currentTheme.headerStyle == .brackets ? "CANCEL" : "Cancel") {
                                        cancelMeetingRecording()
                                    }
                                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(themeManager.currentTheme.backgroundColor)
                                    .padding()
                                    .background(themeManager.currentTheme.secondaryTextColor)
                                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                                }
                            }
                        } else if hasFinishedRecording {
                            VStack(spacing: 20) {
                                Text(themeManager.currentTheme.headerStyle == .brackets ? "PROCESSING MEETING..." : "Processing meeting...")
                                    .font(.system(.title, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(themeManager.currentTheme.warningColor)
                                
                                ProgressView()
                                    .scaleEffect(1.5)
                            }
                        } else {
                            VStack(spacing: 20) {
                                Text(themeManager.currentTheme.headerStyle == .brackets ? "START MEETING RECORDING" : "Start Meeting Recording")
                                    .font(.system(.title, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                
                                Button(themeManager.currentTheme.headerStyle == .brackets ? "START MEETING RECORDING" : "Start Meeting Recording") {
                                    startMeetingRecording()
                                }
                                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                .foregroundColor(themeManager.currentTheme.backgroundColor)
                                .padding()
                                .background(themeManager.currentTheme.accentColor)
                                .cornerRadius(themeManager.currentTheme.cornerRadius)
                                .disabled(meetingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                .padding()
            }
            
            Spacer()
            
            // Bottom Cancel Button
            if !audioRecorder.isRecording && !hasFinishedRecording && !hasImportedAudio {
                HStack {
                    Button(themeManager.currentTheme.headerStyle == .brackets ? "CANCEL" : "Cancel") {
                        dismiss()
                    }
                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.destructiveColor)
                    .padding()
                    .overlay(
                        Rectangle()
                            .stroke(themeManager.currentTheme.destructiveColor, lineWidth: 1)
                    )
                    
                    Spacer()
                }
                .padding()
            }
        }
        .themedBackground()
        .foregroundColor(themeManager.currentTheme.accentColor)
        .navigationBarBackButtonHidden(false)
        .alert("API Key Required", isPresented: $showingAPIKeyAlert) {
            TextField("OpenAI API Key", text: $apiKeyInput)
            Button("Save") {
                openAIService.apiKey = apiKeyInput
                apiKeyInput = ""
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Enter your OpenAI API key to enable transcription and summarization.")
        }
        .onAppear {
            print("🎵 CreateMeetingView appeared with importedAudioURL: \(importedAudioURL?.absoluteString ?? "nil")")
            if let url = importedAudioURL {
                print("🎵 File exists: \(FileManager.default.fileExists(atPath: url.path))")
                
                // Use filename as default meeting name if it's empty
                if meetingName.isEmpty {
                    let fileName = url.lastPathComponent
                    // Remove file extension and clean up the name
                    let nameWithoutExtension = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
                    meetingName = nameWithoutExtension
                    print("🎵 Set default meeting name: \(meetingName)")
                }
            }
        }
    }
    
    private func startMeetingRecording() {
        guard openAIService.apiKey != nil else {
            showingAPIKeyAlert = true
            return
        }
        
        guard !meetingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        recordingStartTime = Date()
        recordingDuration = 0
        currentRecordingURL = audioRecorder.startRecording()
        
        // Start timer for duration display
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let startTime = recordingStartTime {
                recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func pauseMeetingRecording() {
        audioRecorder.pauseRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    private func resumeMeetingRecording() {
        audioRecorder.resumeRecording()
        
        // Restart timer for duration display
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let startTime = recordingStartTime {
                recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func cancelMeetingRecording() {
        audioRecorder.cancelRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Reset state and dismiss
        recordingStartTime = nil
        recordingDuration = 0
        hasFinishedRecording = false
        
        dismiss()
    }
    
    private func analyzeImportedAudio() {
        guard let audioURL = importedAudioURL else { 
            print("❌ No audio URL to analyze")
            return 
        }
        
        print("🎵 Starting analysis of imported audio: \(audioURL)")
        isProcessingAudio = true
        
        // Create meeting immediately with form data
        createProcessingMeeting()
        
        // Track meeting creation (without transcription yet)
        Task {
            let duration = Int(importedAudioDuration)
            await UsageTracker.shared.trackMeetingCreated(transcribed: false, meetingSeconds: duration)
        }
        
        // Notify parent to handle navigation
        if let meeting = createdMeeting {
            onMeetingCreated?(meeting)
        }
        
        Task {
            do {
                // Use the chunked transcription method
                let transcript = try await openAIService.transcribeAudioFromURL(
                    audioURL: audioURL,
                    progressCallback: { _ in }
                )
                
                // Track successful transcription
                let duration = Int(importedAudioDuration)
                await UsageTracker.shared.trackMeetingCreated(transcribed: true, meetingSeconds: duration)
                
                await MainActor.run {
                    updateMeetingWithTranscript(transcript: transcript)
                }
                
                // Upload imported audio to Supabase
                if let meeting = createdMeeting {
                    do {
                        _ = try await SupabaseManager.shared.uploadAudioRecording(
                            audioURL: audioURL,
                            meetingId: meeting.id,
                            duration: importedAudioDuration
                        )
                        
                        // Update meeting to indicate it has a recording
                        await MainActor.run {
                            meeting.hasRecording = true
                        }
                    } catch {
                        print("Error uploading imported audio to Supabase: \(error)")
                    }
                }
                
                // Process AI analysis
                let overview = try await openAIService.generateMeetingOverview(transcript)
                let summary = try await openAIService.summarizeMeeting(transcript)
                let actionItems = try await openAIService.extractActions(transcript)
                
                // Track AI usage
                await UsageTracker.shared.trackAIUsage(
                    summaries: 1,
                    actionsExtracted: actionItems.count
                )
                
                await MainActor.run {
                    updateMeetingWithAI(overview: overview, summary: summary, actionItems: actionItems)
                    isProcessingAudio = false
                }
                
            } catch {
                await MainActor.run {
                    print("Error processing imported audio: \(error)")
                    isProcessingAudio = false
                }
            }
        }
    }
    
    private func stopMeetingRecording() {
        guard let recordingURL = audioRecorder.stopRecording() else { return }
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        hasFinishedRecording = true
        
        // Create meeting immediately with form data
        createProcessingMeeting()
        
        // Track meeting creation (without transcription yet)
        Task {
            let duration = Int(recordingDuration)
            await UsageTracker.shared.trackMeetingCreated(transcribed: false, meetingSeconds: duration)
        }
        
        // Notify parent to handle navigation
        if let meeting = createdMeeting {
            onMeetingCreated?(meeting)
        }
        
        Task {
            do {
                let audioData = try Data(contentsOf: recordingURL)
                
                // Get transcript first
                let transcript = try await openAIService.transcribeAudio(audioData: audioData)
                
                // Track successful transcription
                let duration = Int(recordingDuration)
                await UsageTracker.shared.trackMeetingCreated(transcribed: true, meetingSeconds: duration)
                
                await MainActor.run {
                    updateMeetingWithTranscript(transcript: transcript)
                }
                
                // Upload audio to Supabase before deleting local file
                if let meeting = createdMeeting {
                    do {
                        _ = try await SupabaseManager.shared.uploadAudioRecording(
                            audioURL: recordingURL,
                            meetingId: meeting.id,
                            duration: recordingDuration
                        )
                        
                        // Update meeting to indicate it has a recording
                        await MainActor.run {
                            meeting.hasRecording = true
                        }
                    } catch {
                        print("Error uploading audio to Supabase: \(error)")
                    }
                }
                
                // Delete local recording after successful upload
                audioRecorder.deleteRecording(at: recordingURL)
                
                // Process AI in background after navigation
                let overview = try await openAIService.generateMeetingOverview(transcript)
                let summary = try await openAIService.summarizeMeeting(transcript)
                let actionItems = try await openAIService.extractActions(transcript)
                
                // Track AI usage
                await UsageTracker.shared.trackAIUsage(
                    summaries: 1,
                    actionsExtracted: actionItems.count
                )
                
                await MainActor.run {
                    updateMeetingWithAI(overview: overview, summary: summary, actionItems: actionItems)
                }
                
            } catch {
                await MainActor.run {
                    print("Error processing meeting audio: \(error)")
                }
            }
        }
    }
    
    private func createProcessingMeeting() {
        let meeting = Meeting(
            name: meetingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Meeting" : meetingName,
            location: meetingLocation,
            meetingNotes: meetingNotes,
            audioTranscript: "Transcribing meeting audio...",
            shortSummary: "Generating overview...",
            aiSummary: "Generating meeting summary...",
            isProcessing: true
        )
        
        if let startTime = recordingStartTime {
            meeting.startTime = startTime
            meeting.stopRecording() // Sets end time
        }
        
        modelContext.insert(meeting)
        createdMeeting = meeting
        createdMeetingId = meeting.id
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving meeting: \(error)")
        }
    }
    
    private func updateMeetingWithTranscript(transcript: String) {
        guard let meetingId = createdMeetingId else { return }
        
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
        
        do {
            let meetings = try modelContext.fetch(descriptor)
            guard let meeting = meetings.first else { return }
            
            meeting.audioTranscript = transcript
            meeting.dateModified = Date()
            
            try modelContext.save()
        } catch {
            print("Error updating meeting with transcript: \(error)")
        }
    }
    
    private func updateMeetingWithAI(overview: String, summary: String, actionItems: [ActionItem]) {
        guard let meetingId = createdMeetingId else { return }
        
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
        
        do {
            let meetings = try modelContext.fetch(descriptor)
            guard let meeting = meetings.first else { return }
            
            meeting.shortSummary = overview
            meeting.aiSummary = summary
            meeting.isProcessing = false
            meeting.dateModified = Date()
            
            // Create Action entities from extracted action items
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
                    sourceNoteId: meeting.id // Reusing the same field for meetings
                )
                
                modelContext.insert(action)
            }
            
            try modelContext.save()
            
            // Track action creation
            if !actionItems.isEmpty {
                Task {
                    await UsageTracker.shared.trackActionsCreated(count: actionItems.count)
                }
            }
            
            // Update notifications after creating new actions
            Task { @MainActor in
                // Fetch all actions to update notifications
                let descriptor = FetchDescriptor<Action>()
                if let allActions = try? modelContext.fetch(descriptor) {
                    NotificationService.shared.scheduleNotification(with: allActions)
                    // Also update badge immediately
                    await NotificationService.shared.updateBadgeCount(with: allActions)
                }
            }
        } catch {
            print("Error updating meeting with AI: \(error)")
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}