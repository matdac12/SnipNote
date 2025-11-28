//
//  MeetingsView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData
import StoreKit

struct MeetingsView: View {
    @Binding var deepLinkAudioURL: URL?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.dateCreated, order: .reverse) private var meetings: [Meeting]
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var syncService = MeetingSyncService.shared

    @State private var showingCreateMeeting = false
    @State private var hasSyncedOnLaunch = false
    @State private var selectedMeeting: Meeting?
    @State private var navigateToCreate = false
    @State private var createdMeeting: Meeting?
    @State private var navigateToCreatedMeeting = false
    @State private var showingPaywall = false
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var isBouncingEmpty = false

    private var filteredMeetings: [Meeting] {
        if searchText.isEmpty {
            return meetings
        } else {
            return meetings.filter { meeting in
                // Search in meeting name
                meeting.name.localizedCaseInsensitiveContains(searchText) ||
                // Search in location
                meeting.location.localizedCaseInsensitiveContains(searchText) ||
                // Search in meeting notes
                meeting.meetingNotes.localizedCaseInsensitiveContains(searchText) ||
                // Search in transcript
                meeting.audioTranscript.localizedCaseInsensitiveContains(searchText) ||
                // Search in AI summary
                meeting.aiSummary.localizedCaseInsensitiveContains(searchText) ||
                // Search in short summary
                meeting.shortSummary.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                
                 HStack(alignment: .center, spacing: 12) {
                     Text("Meetings")
                         .themedTitle()

                     Spacer()

                     HStack(spacing: 12) {
                         Text("\(searchText.isEmpty ? meetings.count : filteredMeetings.count) meetings\(searchText.isEmpty ? "" : " found")")
                             .themedCaption()

                         Button(action: checkLimitAndCreate) {
                             Image(systemName: "plus")
                                 .font(.system(size: 16, weight: .semibold))
                         }
                         .buttonStyle(.plain)
                         .foregroundColor(themeManager.currentTheme.accentColor)
                         .padding(8)
                         .background(themeManager.currentTheme.accentColor.opacity(0.12))
                         .clipShape(Circle())

                         if !meetings.isEmpty {
                             EditButton()
                                 .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                 .foregroundColor(themeManager.currentTheme.accentColor)
                                 .buttonStyle(.plain)
                         }
                     }
                 }
                 .padding(.horizontal)
                 .padding(.vertical, 12)
                 .background(themeManager.currentTheme.materialStyle)
                 .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)

                // Search Bar (only show if there are meetings)
                if !meetings.isEmpty {
                     HStack {
                         Image(systemName: "magnifyingglass")
                             .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                             .font(.system(size: 16))

                         TextField("Search meetings, transcripts...", text: $searchText)
                             .textFieldStyle(PlainTextFieldStyle())
                             .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                             .foregroundColor(themeManager.currentTheme.textColor)
                             .onTapGesture {
                                 isSearching = true
                             }

                         if !searchText.isEmpty {
                             Button(action: {
                                 searchText = ""
                                 isSearching = false
                             }) {
                                 Image(systemName: "xmark.circle.fill")
                                     .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                     .font(.system(size: 16))
                             }
                         }
                     }
                     .padding(.horizontal, 16)
                     .padding(.vertical, 10)
                     .background(themeManager.currentTheme.secondaryBackgroundColor)
                     .cornerRadius(themeManager.currentTheme.cornerRadius)
                     .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                     .padding(.horizontal)
                     .padding(.top, 16)
                     .padding(.bottom, 8)
                }

                if meetings.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()

                        // Animated empty state icon
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor.opacity(0.6))
                            .offset(y: isBouncingEmpty ? -10 : 0)
                            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isBouncingEmpty)
                            .onAppear {
                                isBouncingEmpty = true
                            }

                        Text("No meetings yet")
                            .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        Text("Tap + to create your first meeting")
                            .themedCaption()
                        Spacer()
                    }
                } else if filteredMeetings.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        Text("No results found")
                            .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        Text("Try a different search term")
                            .themedCaption()
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredMeetings) { meeting in
                             Button {
                                 selectedMeeting = meeting
                             } label: {
                                 VStack(alignment: .leading, spacing: 6) {
                                     HStack {
                                         Text(meeting.name.isEmpty ? "Untitled Meeting" : meeting.name)
                                             .themedBody()
                                             .fontWeight(.bold)
                                             .lineLimit(1)

                                         if meeting.isProcessing {
                                             Text("Processing...")
                                                 .themedCaption()
                                                 .fontWeight(.bold)
                                                 .foregroundColor(themeManager.currentTheme.warningColor)
                                                 .padding(.horizontal, 4)
                                                 .padding(.vertical, 2)
                                                 .background(themeManager.currentTheme.warningColor.opacity(0.2))
                                                 .cornerRadius(3)
                                         }
                                     }

                                     Text(meeting.dateCreated, style: .date)
                                         .themedCaption()

                                     if !meeting.location.isEmpty {
                                         Text("📍 \(meeting.location)")
                                             .themedCaption()
                                             .lineLimit(1)
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
                                 .frame(maxWidth: .infinity, alignment: .leading)
                                 .padding(.vertical, 8)
                                 .padding(.horizontal, 12)
                                 .background(themeManager.currentTheme.secondaryBackgroundColor.opacity(0.5))
                                 .cornerRadius(themeManager.currentTheme.cornerRadius)
                                 .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                 .opacity(meeting.isProcessing ? 0.6 : 1.0)
                                 .overlay(
                                     meeting.isProcessing ?
                                     RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                                         .stroke(themeManager.currentTheme.warningColor.opacity(0.5), lineWidth: 1)
                                     : nil
                                 )
                             }
                             .buttonStyle(PlainButtonStyle())
                        }
                        .onDelete(perform: deleteMeetings)
                        .listRowBackground(Color.clear)
                    }
                    .navigationDestination(item: $selectedMeeting) { meeting in
                        MeetingDetailView(meeting: meeting)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await performSync()
                    }
                }
            }
            .themedBackground()
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
        } detail: {
            VStack {
                Spacer()
                Text("Select a meeting")
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
            // Auto-sync from Supabase on app launch (only once per session)
            if !hasSyncedOnLaunch && authManager.isAuthenticated {
                hasSyncedOnLaunch = true
                await performSync()
            }

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
            // Clear deep link when navigating away from CreateMeetingView (back button or cancel)
            if !isNavigating && deepLinkAudioURL != nil {
                print("🎵 Clearing deep link audio URL on navigation away")
                deepLinkAudioURL = nil
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
    
    private func checkLimitAndCreate() {
        // With minutes-based system, CreateMeetingView will handle minutes validation
        // No need to check meeting count limits anymore
        navigateToCreate = true
    }

    private func deleteMeetings(offsets: IndexSet) {
        let meetingsToDelete = offsets.map { meetings[$0] }

        Task { @MainActor in
            for meeting in meetingsToDelete {
                // Delete Supabase audio first, then SwiftData
                if meeting.hasRecording {
                    do {
                        try await SupabaseManager.shared.deleteAudioRecording(meetingId: meeting.id)
                    } catch {
                        print("⚠️ Failed to delete Supabase recording for meeting \(meeting.id): \(error)")
                        // Continue with deletion anyway - user intent is to delete
                    }
                }

                // Delete from Supabase meetings table
                do {
                    try await SupabaseManager.shared.deleteMeeting(id: meeting.id)
                } catch {
                    print("⚠️ Failed to delete meeting from Supabase: \(error)")
                    // Continue with deletion anyway - user intent is to delete
                }

                withAnimation {
                    modelContext.delete(meeting)
                }
            }

            do {
                try modelContext.save()
            } catch {
                print("Error deleting meetings: \(error)")
            }
        }
    }

    // MARK: - Sync

    /// Sync meetings from Supabase (called on launch and pull-to-refresh)
    private func performSync() async {
        guard authManager.isAuthenticated else {
            print("⚠️ [Sync] User not authenticated, skipping sync")
            return
        }

        do {
            try await syncService.syncFromServer(modelContext: modelContext)
        } catch {
            print("⚠️ [Sync] Failed: \(error.localizedDescription)")
            // Don't show error to user - sync failures should be silent
            // Local data is still available
        }
    }
}
