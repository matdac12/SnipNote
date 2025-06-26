//
//  ContentView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.dateCreated, order: .reverse) private var notes: [Note]
    
    @State private var showingCreateNote = false
    @State private var selectedNote: Note?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                
                HStack {
                    Text("[ SNIP NOTES ]")
                        .font(.system(.title, design: .monospaced, weight: .bold))
                        .foregroundColor(.green)
                    Spacer()
                    Text("\(notes.count) NOTES")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                if notes.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Text("NO NOTES FOUND")
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("TAP + TO CREATE YOUR FIRST NOTE")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(notes) { note in
                            NavigationLink(value: note) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(note.title.isEmpty ? "UNTITLED" : note.title.uppercased())
                                            .font(.system(.body, design: .monospaced, weight: .bold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(note.dateCreated, style: .date)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(note.originalTranscript.prefix(100) + (note.originalTranscript.count > 100 ? "..." : ""))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: deleteNotes)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                }
            }
            .background(.black)
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(note: note)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCreateNote = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.green)
                    }
                }
                
                if !notes.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                            .foregroundColor(.green)
                    }
                }
            }
        } detail: {
            VStack {
                Spacer()
                Text("SELECT A NOTE")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .background(.black)
        }
        .sheet(isPresented: $showingCreateNote) {
            CreateNoteView()
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

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
