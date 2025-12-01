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

    private enum Tab: Hashable {
        case meetings
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MeetingsView(deepLinkAudioURL: $deepLinkAudioURL)
                .tabItem {
                    Image(systemName: "waveform")
                    Text(tabTitle(for: "tab.meetings"))
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                }
                .tag(Tab.meetings)

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
    }

    private func tabTitle(for key: String) -> String {
        return localizationManager.localizedString(key)
    }
}

#Preview {
    ContentView(deepLinkAudioURL: .constant(nil))
        .modelContainer(for: [Action.self, Meeting.self, EveMessage.self, ChatConversation.self], inMemory: true)
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationManager.shared)
}
