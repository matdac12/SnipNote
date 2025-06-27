//
//  MeetingsView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct MeetingsView: View {
    @Binding var deepLinkAudioURL: URL?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.dateCreated, order: .reverse) private var meetings: [Meeting]
    
    @State private var showingCreateMeeting = false
    @State private var selectedMeeting: Meeting?
    @State private var navigateToCreate = false
    @State private var createdMeeting: Meeting?
    @State private var navigateToCreatedMeeting = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                
                HStack {
                    Text("[ MEETINGS ]")
                        .font(.system(.title, design: .monospaced, weight: .bold))
                        .foregroundColor(.green)
                    Spacer()
                    Text("\(meetings.count) MEETINGS")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                if meetings.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Text("NO MEETINGS FOUND")
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("TAP + TO CREATE YOUR FIRST MEETING")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(meetings) { meeting in
                            NavigationLink(value: meeting) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(meeting.name.isEmpty ? "UNTITLED MEETING" : meeting.name.uppercased())
                                            .font(.system(.body, design: .monospaced, weight: .bold))
                                            .lineLimit(1)
                                        
                                        if meeting.isProcessing {
                                            Text("PROCESSING...")
                                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                                .foregroundColor(.orange)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(.orange.opacity(0.2))
                                                .cornerRadius(3)
                                        }
                                        
                                        Spacer()
                                        Text(meeting.dateCreated, style: .date)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack {
                                        if !meeting.location.isEmpty {
                                            Text("📍 \(meeting.location)")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        if meeting.duration > 0 {
                                            Text("⏱️ \(meeting.durationFormatted)")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if !meeting.meetingNotes.isEmpty {
                                        Text(meeting.meetingNotes.prefix(80) + (meeting.meetingNotes.count > 80 ? "..." : ""))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 4)
                                .opacity(meeting.isProcessing ? 0.6 : 1.0)
                                .overlay(
                                    meeting.isProcessing ? 
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.orange.opacity(0.5), lineWidth: 1)
                                    : nil
                                )
                            }
                        }
                        .onDelete(perform: deleteMeetings)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                }
            }
            .background(.black)
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(meeting: meeting)
            }
            .navigationDestination(isPresented: $navigateToCreate) {
                CreateMeetingView(
                    onMeetingCreated: { meeting in
                        createdMeeting = meeting
                        navigateToCreate = false
                        navigateToCreatedMeeting = true
                    },
                    importedAudioURL: deepLinkAudioURL
                )
            }
            .navigationDestination(isPresented: $navigateToCreatedMeeting) {
                if let meeting = createdMeeting {
                    MeetingDetailView(meeting: meeting)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { navigateToCreate = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.green)
                    }
                }
                
                if !meetings.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                            .foregroundColor(.green)
                    }
                }
            }
        } detail: {
            VStack {
                Spacer()
                Text("SELECT A MEETING")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .background(.black)
        }
        .onAppear {
            // Handle deep link when view appears
            if deepLinkAudioURL != nil {
                print("🎵 MeetingsView appeared with audio URL: \(deepLinkAudioURL!)")
                navigateToCreate = true
            }
        }
        .onChange(of: deepLinkAudioURL) { _, newValue in
            // Handle deep link changes
            if let audioURL = newValue {
                print("🎵 Audio URL changed in MeetingsView: \(audioURL)")
                navigateToCreate = true
            }
        }
        .onChange(of: navigateToCreate) { _, isNavigating in
            print("🎵 navigateToCreate changed: \(isNavigating), audioURL: \(deepLinkAudioURL?.absoluteString ?? "nil")")
            // Don't clear the deep link immediately - let CreateMeetingView handle it
        }
    }

    private func deleteMeetings(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(meetings[index])
            }
        }
    }
}