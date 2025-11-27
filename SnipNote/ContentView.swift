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
    @State private var selectedTab: Tab = .meetings
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @State private var selectedMeetingForEve: UUID?

    private enum Tab: Hashable {
        case meetings
        case eve
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MeetingsView(deepLinkAudioURL: $deepLinkAudioURL)
                .tabItem {
                    Image(systemName: "person.3")
                    Text(tabTitle(for: "tab.meetings"))
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                }
                .tag(Tab.meetings)

            EveView(selectedMeetingForEve: $selectedMeetingForEve)
                .tabItem {
                    Image(systemName: "wand.and.stars.inverse")
                    Text(tabTitle(for: "tab.eve"))
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                }
                .tag(Tab.eve)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text(tabTitle(for: "tab.settings"))
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                }
                .tag(Tab.settings)
        }
        .onChange(of: deepLinkAudioURL) { _, newValue in
            if newValue != nil {
                // Switch to Meetings tab when audio is shared
                selectedTab = .meetings
            }
        }
        .onChange(of: selectedMeetingForEve) { _, newMeetingId in
            if newMeetingId != nil {
                selectedTab = .eve
            }
        }
        .environment(\.navigateToEve, navigateToEveWith)
    }

    private func tabTitle(for key: String) -> String {
        return localizationManager.localizedString(key)
    }

    func navigateToEveWith(meetingId: UUID) {
        selectedMeetingForEve = meetingId
    }
}

#Preview {
    ContentView(deepLinkAudioURL: .constant(nil))
        .modelContainer(for: [Action.self, Meeting.self, EveMessage.self, ChatConversation.self, UserAIContext.self, MeetingFileState.self], inMemory: true)
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationManager.shared)
}
