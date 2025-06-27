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
    
    @Query private var allActions: [Action]
    
    @State private var isEditingTitle = false
    @State private var isEditingSummary = false
    @State private var tempTitle = ""
    @State private var tempSummary = ""
    
    private var relatedActions: [Action] {
        allActions.filter { $0.sourceNoteId == note.id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                if isEditingTitle {
                    TextField("Title", text: $tempTitle)
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .textFieldStyle(PlainTextFieldStyle())
                        .onSubmit {
                            saveTitle()
                        }
                } else {
                    Text("[ \(note.title.isEmpty ? "UNTITLED" : note.title.uppercased()) ]")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .lineLimit(1)
                        .onTapGesture {
                            startEditingTitle()
                        }
                }
                
                Spacer()
                
                Text(note.dateCreated, style: .date)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRANSCRIPT:")
                            .font(.system(.headline, design: .monospaced, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Text(note.originalTranscript)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(.ultraThinMaterial)
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
                                .background(.ultraThinMaterial)
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
                            .background(.ultraThinMaterial)
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
                            Text("No actionable items found in this note")
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
            if note.isProcessing {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("GO TO NOTES") {
                        // Navigation will happen automatically via back button
                    }
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            tempTitle = note.title
            tempSummary = note.aiSummary
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
}