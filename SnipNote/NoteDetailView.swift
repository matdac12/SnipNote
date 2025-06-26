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
    
    @State private var isEditingTitle = false
    @State private var isEditingSummary = false
    @State private var tempTitle = ""
    @State private var tempSummary = ""
    
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
                            
                            Button("EDIT") {
                                startEditingSummary()
                            }
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundColor(.blue)
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
                            Text(note.aiSummary)
                                .font(.system(.body, design: .monospaced))
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