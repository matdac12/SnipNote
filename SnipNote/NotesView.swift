//
//  NotesView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.dateCreated, order: .reverse) private var notes: [Note]
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var showingCreateNote = false
    @State private var selectedNote: Note?
    @State private var navigateToCreate = false
    @State private var createdNote: Note?
    @State private var navigateToCreatedNote = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                
                HStack {
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "[ NOTES ]" : "Notes")
                        .themedTitle()
                    Spacer()
                    Text("\(notes.count) \(themeManager.currentTheme.headerStyle == .brackets ? "NOTES" : "notes")")
                        .themedCaption()
                }
                .padding()
                .background(themeManager.currentTheme.materialStyle)
                
                if notes.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Text(themeManager.currentTheme.headerStyle == .brackets ? "NO NOTES FOUND" : "No notes found")
                            .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        Text(themeManager.currentTheme.headerStyle == .brackets ? "TAP + TO CREATE YOUR FIRST NOTE" : "Tap + to create your first note")
                            .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(notes) { note in
                            NavigationLink(value: note) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(note.title.isEmpty ? (themeManager.currentTheme.headerStyle == .brackets ? "UNTITLED" : "Untitled") : (themeManager.currentTheme.headerStyle == .brackets ? note.title.uppercased() : note.title))
                                            .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                            .foregroundColor(themeManager.currentTheme.textColor)
                                            .lineLimit(1)
                                        
                                        if note.isProcessing {
                                            Text(themeManager.currentTheme.headerStyle == .brackets ? "PROCESSING..." : "Processing...")
                                                .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                                .foregroundColor(themeManager.currentTheme.warningColor)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(themeManager.currentTheme.warningColor.opacity(0.2))
                                                .cornerRadius(3)
                                        }
                                        
                                        Spacer()
                                        Text(note.dateCreated, style: .date)
                                            .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                    }
                                    
                                    Text(note.originalTranscript.prefix(100) + (note.originalTranscript.count > 100 ? "..." : ""))
                                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 4)
                                .opacity(note.isProcessing ? 0.6 : 1.0)
                                .overlay(
                                    note.isProcessing ? 
                                    RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                                        .stroke(themeManager.currentTheme.warningColor.opacity(0.5), lineWidth: 1)
                                    : nil
                                )
                            }
                        }
                        .onDelete(perform: deleteNotes)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                }
            }
            .themedBackground()
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(note: note)
            }
            .navigationDestination(isPresented: $navigateToCreate) {
                CreateNoteView { note in
                    createdNote = note
                    navigateToCreate = false
                    navigateToCreatedNote = true
                }
            }
            .navigationDestination(isPresented: $navigateToCreatedNote) {
                if let note = createdNote {
                    NoteDetailView(note: note)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { navigateToCreate = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                }
                
                if !notes.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                }
            }
        } detail: {
            VStack {
                Spacer()
                Text(themeManager.currentTheme.headerStyle == .brackets ? "SELECT A NOTE" : "Select a note")
                    .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                Spacer()
            }
            .themedBackground()
        }
    }

    private func deleteNotes(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(notes[index])
            }
        }
    }
}