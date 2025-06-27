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
    @State private var selectedTab = 0
    
    private var pendingActionsCount: Int {
        actions.filter { !$0.isCompleted }.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NotesView()
                .tabItem {
                    Image(systemName: "note.text")
                    Text("NOTES")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                }
                .tag(0)
            
            ActionsView()
                .tabItem {
                    Image(systemName: "checklist")
                    Text("ACTIONS")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                }
                .badge(pendingActionsCount)
                .tag(1)
            
            MeetingsView(deepLinkAudioURL: $deepLinkAudioURL)
                .tabItem {
                    Image(systemName: "person.3")
                    Text("MEETINGS")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("SETTINGS")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                }
                .tag(3)
        }
        .accentColor(.green)
        .preferredColorScheme(.dark)
        .onChange(of: deepLinkAudioURL) { _, newValue in
            if newValue != nil {
                // Switch to Meetings tab when audio is shared
                selectedTab = 2
            }
        }
    }
}

#Preview {
    ContentView(deepLinkAudioURL: .constant(nil))
        .modelContainer(for: [Note.self, Action.self, Meeting.self], inMemory: true)
}
