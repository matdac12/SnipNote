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
    
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var openAIService = OpenAIService.shared
    
    @State private var isProcessing = false
    @State private var currentRecordingURL: URL?
    @State private var transcript = ""
    @State private var summary = ""
    @State private var showingAPIKeyAlert = false
    @State private var apiKeyInput = ""
    
    var body: some View {
        NavigationView {
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
                        }
                    } else if isProcessing {
                        VStack(spacing: 20) {
                            Text("PROCESSING...")
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
                    }
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    
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
                    
                    Button(action: toggleRecording) {
                        Text(audioRecorder.isRecording ? "STOP" : "RECORD")
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .foregroundColor(.white)
                            .padding()
                            .background(audioRecorder.isRecording ? .red : .blue)
                    }
                    .disabled(isProcessing)
                }
                .padding()
            }
            .background(.black)
            .foregroundColor(.green)
        }
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
        
        isProcessing = true
        
        Task {
            do {
                let audioData = try Data(contentsOf: recordingURL)
                
                let transcript = try await openAIService.transcribeAudio(audioData: audioData)
                let summary = try await openAIService.summarizeText(transcript)
                let actionItems = try await openAIService.extractActions(transcript)
                
                await MainActor.run {
                    createNote(transcript: transcript, summary: summary, actionItems: actionItems)
                    audioRecorder.deleteRecording(at: recordingURL)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    print("Error processing audio: \(error)")
                }
            }
        }
    }
    
    private func createNote(transcript: String, summary: String, actionItems: [ActionItem]) {
        let note = Note(
            title: String(transcript.prefix(50)),
            originalTranscript: transcript,
            aiSummary: summary
        )
        
        modelContext.insert(note)
        
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
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving note and actions: \(error)")
        }
    }
}