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
    
    @Query private var allActions: [Action]
    
    @State private var isEditingName = false
    @State private var isEditingSummary = false
    @State private var tempName = ""
    @State private var tempSummary = ""
    @State private var showingTranscript = false
    
    private var relatedActions: [Action] {
        allActions.filter { $0.sourceNoteId == meeting.id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Meeting Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if isEditingName {
                        TextField("Meeting Name", text: $tempName)
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .textFieldStyle(PlainTextFieldStyle())
                            .onSubmit {
                                saveName()
                            }
                    } else {
                        Text("[ \(meeting.name.isEmpty ? "UNTITLED MEETING" : meeting.name.uppercased()) ]")
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .lineLimit(1)
                            .onTapGesture {
                                startEditingName()
                            }
                    }
                    
                    HStack {
                        if !meeting.location.isEmpty {
                            Text("📍 \(meeting.location)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        if meeting.duration > 0 {
                            Text("⏱️ \(meeting.durationFormatted)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Text(meeting.dateCreated, style: .date)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Pre-meeting Notes (if any)
                    if !meeting.meetingNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MEETING NOTES:")
                                .font(.system(.headline, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            Text(meeting.meetingNotes)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                    }
                    
                    // Short Overview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OVERVIEW:")
                            .font(.system(.headline, design: .monospaced, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(meeting.shortSummary)
                                .font(.system(.body, design: .monospaced))
                                .opacity(meeting.isProcessing ? 0.6 : 1.0)
                            
                            if meeting.isProcessing {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                    
                    // Meeting Summary
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("MEETING SUMMARY:")
                                .font(.system(.headline, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if !meeting.isProcessing {
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
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                                .frame(minHeight: 300)
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
                                Text(meeting.aiSummary)
                                    .font(.system(.body, design: .monospaced))
                                    .opacity(meeting.isProcessing ? 0.6 : 1.0)
                                
                                if meeting.isProcessing {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Transcript Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("FULL TRANSCRIPT:")
                                .font(.system(.headline, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(showingTranscript ? "HIDE" : "SHOW") {
                                withAnimation {
                                    showingTranscript.toggle()
                                }
                            }
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundColor(.blue)
                        }
                        
                        if showingTranscript {
                            ScrollView {
                                Text(meeting.audioTranscript)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                            }
                            .frame(maxHeight: 300)
                        }
                    }
                    
                    // Related Actions
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("MEETING ACTIONS:")
                                .font(.system(.headline, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if meeting.isProcessing {
                                Text("EXTRACTING...")
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        if meeting.isProcessing {
                            HStack {
                                Text("Extracting action items from meeting...")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .opacity(0.6)
                                
                                Spacer()
                                
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            .padding()
                            .background(.ultraThinMaterial)
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
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding()
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                            }
                        } else {
                            Text("No action items found in this meeting")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding()
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
        }
        .background(.black)
        .foregroundColor(.green)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            if meeting.isProcessing {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("GO TO MEETINGS") {
                        // Navigation will happen automatically via back button
                    }
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            tempName = meeting.name
            tempSummary = meeting.aiSummary
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
            print("Error saving meeting name: \(error)")
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
            print("Error saving meeting summary: \(error)")
        }
    }
}