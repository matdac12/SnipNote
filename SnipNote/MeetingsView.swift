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
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var showingCreateMeeting = false
    @State private var selectedMeeting: Meeting?
    @State private var navigateToCreate = false
    @State private var createdMeeting: Meeting?
    @State private var navigateToCreatedMeeting = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                
                HStack {
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "[ MEETINGS ]" : "Meetings")
                        .themedTitle()
                    Spacer()
                    Text("\(meetings.count) \(themeManager.currentTheme.headerStyle == .brackets ? "MEETINGS" : "meetings")")
                        .themedCaption()
                }
                .padding()
                .background(themeManager.currentTheme.materialStyle)
                
                if meetings.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Text(themeManager.currentTheme.headerStyle == .brackets ? "NO MEETINGS FOUND" : "No meetings yet")
                            .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        Text(themeManager.currentTheme.headerStyle == .brackets ? "TAP + TO CREATE YOUR FIRST MEETING" : "Tap + to create your first meeting")
                            .themedCaption()
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(meetings) { meeting in
                            NavigationLink(value: meeting) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(meeting.name.isEmpty ? (themeManager.currentTheme.headerStyle == .brackets ? "UNTITLED MEETING" : "Untitled Meeting") : (themeManager.currentTheme.headerStyle == .brackets ? meeting.name.uppercased() : meeting.name))
                                            .themedBody()
                                            .fontWeight(.bold)
                                            .lineLimit(1)
                                        
                                        if meeting.isProcessing {
                                            Text(themeManager.currentTheme.headerStyle == .brackets ? "PROCESSING..." : "Processing...")
                                                .themedCaption()
                                                .fontWeight(.bold)
                                                .foregroundColor(themeManager.currentTheme.warningColor)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(themeManager.currentTheme.warningColor.opacity(0.2))
                                                .cornerRadius(3)
                                        }
                                        
                                        Spacer()
                                        Text(meeting.dateCreated, style: .date)
                                            .themedCaption()
                                    }
                                    
                                    HStack {
                                        if !meeting.location.isEmpty {
                                            Text("📍 \(meeting.location)")
                                                .themedCaption()
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        if meeting.duration > 0 {
                                            Text("⏱️ \(meeting.durationFormatted)")
                                                .themedCaption()
                                        }
                                    }
                                    
                                    // Show overview/summary preview
                                    if !meeting.shortSummary.isEmpty {
                                        Text(meeting.shortSummary)
                                            .themedCaption()
                                            .lineLimit(2)
                                    } else if !meeting.meetingNotes.isEmpty {
                                        // Fallback to meeting notes if no summary yet
                                        Text(meeting.meetingNotes.prefix(80) + (meeting.meetingNotes.count > 80 ? "..." : ""))
                                            .themedCaption()
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 4)
                                .opacity(meeting.isProcessing ? 0.6 : 1.0)
                                .overlay(
                                    meeting.isProcessing ? 
                                    RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                                        .stroke(themeManager.currentTheme.warningColor.opacity(0.5), lineWidth: 1)
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
            .themedBackground()
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(meeting: meeting)
            }
            .navigationDestination(isPresented: $navigateToCreate) {
                CreateMeetingView(
                    onMeetingCreated: { meeting in
                        createdMeeting = meeting
                        navigateToCreate = false
                        navigateToCreatedMeeting = true
                        // Clear deep link after meeting is created
                        deepLinkAudioURL = nil
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
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                }
                
                if !meetings.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                }
            }
        } detail: {
            VStack {
                Spacer()
                Text(themeManager.currentTheme.headerStyle == .brackets ? "SELECT A MEETING" : "Select a meeting")
                    .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                Spacer()
            }
            .themedBackground()
        }
        .onAppear {
            // Handle deep link when view appears
            if deepLinkAudioURL != nil {
                print("🎵 MeetingsView appeared with audio URL: \(deepLinkAudioURL!)")
                // Use a small delay to ensure view is fully loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    navigateToCreate = true
                }
            }
        }
        .task {
            // Also handle deep link in task (runs after view is fully loaded)
            if deepLinkAudioURL != nil && !navigateToCreate {
                print("🎵 MeetingsView task with audio URL: \(deepLinkAudioURL!)")
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await MainActor.run {
                    navigateToCreate = true
                }
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