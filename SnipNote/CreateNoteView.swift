//
//  CreateNoteView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct CreateNoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var onNoteCreated: ((Note) -> Void)?
    
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var openAIService = OpenAIService.shared
    
    @State private var isProcessing = false
    @State private var currentRecordingURL: URL?
    @State private var transcript = ""
    @State private var summary = ""
    @State private var showingAPIKeyAlert = false
    @State private var apiKeyInput = ""
    @State private var createdNote: Note?
    @State private var createdNoteId: UUID?
    @State private var navigateToNote = false
    @State private var hasFinishedRecording = false
    
    var body: some View {
        VStack(spacing: 0) {
                
                HStack {
                    Text("[ NEW NOTE ]")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                
                Spacer()
                
                VStack(spacing: 30) {
                    
                    if audioRecorder.isRecording {
                        VStack(spacing: 20) {
                            Text("RECORDING...")
                                .font(.system(.title, design: .monospaced, weight: .bold))
                                .foregroundColor(.red)
                            
                            Rectangle()
                                .fill(.red)
                                .frame(width: CGFloat(audioRecorder.recordingLevel * 200), height: 4)
                                .animation(.easeInOut(duration: 0.1), value: audioRecorder.recordingLevel)
                            
                            Button("STOP RECORDING") {
                                toggleRecording()
                            }
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .foregroundColor(.white)
                            .padding()
                            .background(.red)
                            .cornerRadius(8)
                        }
                    } else if hasFinishedRecording {
                        VStack(spacing: 20) {
                            Text("CREATING NOTE...")
                                .font(.system(.title, design: .monospaced, weight: .bold))
                                .foregroundColor(.orange)
                            
                            ProgressView()
                                .scaleEffect(1.5)
                        }
                    } else {
                        VStack(spacing: 20) {
                            Text("TAP TO RECORD")
                                .font(.system(.title, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            Image(systemName: "mic.circle")
                                .font(.system(size: 80))
                                .foregroundColor(.blue)
                        }
                        .onTapGesture {
                            toggleRecording()
                        }
                    }
                }
                
                Spacer()
                
                HStack {
                    Button("CANCEL") {
                        if let url = currentRecordingURL {
                            audioRecorder.deleteRecording(at: url)
                        }
                        dismiss()
                    }
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .foregroundColor(.red)
                    .padding()
                    .overlay(
                        Rectangle()
                            .stroke(.red, lineWidth: 1)
                    )
                    
                    Spacer()
                }
                .padding()
        }
        .background(.black)
        .foregroundColor(.green)
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
    }
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            stopRecordingAndProcess()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard openAIService.apiKey != nil else {
            showingAPIKeyAlert = true
            return
        }
        
        currentRecordingURL = audioRecorder.startRecording()
    }
    
    private func stopRecordingAndProcess() {
        guard let recordingURL = audioRecorder.stopRecording() else { return }
        
        // Set state to show "CREATING NOTE..." instead of "TAP TO RECORD"
        hasFinishedRecording = true
        
        // Create note immediately with processing placeholder
        createProcessingNote()
        
        // Notify parent to handle navigation
        if let note = createdNote {
            onNoteCreated?(note)
        }
        
        Task {
            do {
                let audioData = try Data(contentsOf: recordingURL)
                
                // Get transcript first
                let transcript = try await openAIService.transcribeAudio(audioData: audioData)
                
                await MainActor.run {
                    updateNoteWithTranscript(transcript: transcript)
                    audioRecorder.deleteRecording(at: recordingURL)
                }
                
                // Process AI in background after navigation
                let title = try await openAIService.generateTitle(transcript)
                let summary = try await openAIService.summarizeText(transcript)
                let actionItems = try await openAIService.extractActions(transcript)
                
                await MainActor.run {
                    updateNoteWithAI(title: title, summary: summary, actionItems: actionItems)
                }
                
            } catch {
                await MainActor.run {
                    print("Error processing audio: \(error)")
                }
            }
        }
    }
    
    private func createProcessingNote() {
        let note = Note(
            title: "Generating Title...",
            originalTranscript: "Transcribing audio...",
            aiSummary: "Generating AI summary...",
            isProcessing: true
        )
        
        modelContext.insert(note)
        createdNote = note
        createdNoteId = note.id
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving note: \(error)")
        }
    }
    
    private func updateNoteWithTranscript(transcript: String) {
        guard let noteId = createdNoteId else { return }
        
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteId })
        
        do {
            let notes = try modelContext.fetch(descriptor)
            guard let note = notes.first else { return }
            
            note.title = "Generating Title..."
            note.originalTranscript = transcript
            note.dateModified = Date()
            
            try modelContext.save()
        } catch {
            print("Error updating note with transcript: \(error)")
        }
    }
    
    private func updateNoteWithAI(title: String, summary: String, actionItems: [ActionItem]) {
        guard let noteId = createdNoteId else { return }
        
        // Find the note in the model context using the ID
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteId })
        
        do {
            let notes = try modelContext.fetch(descriptor)
            guard let note = notes.first else { return }
            
            note.title = title
            note.aiSummary = summary
            note.isProcessing = false
            note.dateModified = Date()
            
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
                    sourceNoteId: note.id
                )
                
                modelContext.insert(action)
            }
            
            try modelContext.save()
            
            // Update notifications after creating new actions
            Task { @MainActor in
                // Fetch all actions to update notifications
                let descriptor = FetchDescriptor<Action>()
                if let allActions = try? modelContext.fetch(descriptor) {
                    NotificationService.shared.scheduleNotification(with: allActions)
                }
            }
        } catch {
            print("Error updating note with AI: \(error)")
        }
    }
}