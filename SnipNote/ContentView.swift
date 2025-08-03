//
//  ContentView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Binding var deepLinkAudioURL: URL?
    @Query private var actions: [Action]
    @Query private var notes: [Note]
    @State private var selectedTab = 0
    @Binding var shouldNavigateToActions: Bool
    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("showNotesTab") private var showNotesTab = false
    
    private var pendingActionsCount: Int {
        if showNotesTab {
            return actions.filter { !$0.isCompleted }.count
        } else {
            // Filter out actions from notes when Notes tab is hidden
            let noteIds = Set(notes.map { $0.id })
            return actions.filter { action in
                !action.isCompleted && !(action.sourceNoteId != nil && noteIds.contains(action.sourceNoteId!))
            }.count
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            if showNotesTab {
                NotesView()
                    .tabItem {
                        Image(systemName: "note.text")
                        Text(themeManager.currentTheme.headerStyle == .brackets ? "NOTES" : "Notes")
                            .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    }
                    .tag(0)
            }
            
            MeetingsView(deepLinkAudioURL: $deepLinkAudioURL)
                .tabItem {
                    Image(systemName: "person.3")
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "MEETINGS" : "Meetings")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                }
                .tag(showNotesTab ? 1 : 0)
            
            ActionsView()
                .tabItem {
                    Image(systemName: "checklist")
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "ACTIONS" : "Actions")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                }
                .badge(pendingActionsCount)
                .tag(showNotesTab ? 2 : 1)
            
            EveView()
                .tabItem {
                    Image(systemName: "wand.and.stars.inverse")
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "EVE" : "Eve")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                }
                .tag(showNotesTab ? 3 : 2)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "SETTINGS" : "Settings")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                }
                .tag(showNotesTab ? 4 : 3)
        }
        .onChange(of: deepLinkAudioURL) { _, newValue in
            if newValue != nil {
                // Switch to Meetings tab when audio is shared
                selectedTab = showNotesTab ? 1 : 0
            }
        }
        .onChange(of: shouldNavigateToActions) { _, newValue in
            if newValue {
                // Navigate to Actions tab when notification is tapped
                selectedTab = showNotesTab ? 2 : 1
                shouldNavigateToActions = false
            }
        }
    }
}

#Preview {
    ContentView(deepLinkAudioURL: .constant(nil), shouldNavigateToActions: .constant(false))
        .modelContainer(for: [Note.self, Action.self, Meeting.self, EveMessage.self, ChatConversation.self], inMemory: true)
}
