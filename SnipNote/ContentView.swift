//
//  ContentView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var actions: [Action]
    
    private var pendingActionsCount: Int {
        actions.filter { !$0.isCompleted }.count
    }

    var body: some View {
        TabView {
            NotesView()
                .tabItem {
                    Image(systemName: "note.text")
                    Text("NOTES")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                }
            
            ActionsView()
                .tabItem {
                    Image(systemName: "checklist")
                    Text("ACTIONS")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                }
                .badge(pendingActionsCount)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("SETTINGS")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                }
        }
        .accentColor(.green)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Note.self, inMemory: true)
}
