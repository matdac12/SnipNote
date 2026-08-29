//
//  ContentView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Binding var sharedAudioImportRequest: SharedAudioImportRequest?
    @State private var selectedTab: Tab = .home
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var localizationManager: LocalizationManager

    enum Tab: Hashable {
        case home
        case meetings
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text(tabTitle(for: "tab.home"))
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                }
                .tag(Tab.home)

            MeetingsView(sharedAudioImportRequest: $sharedAudioImportRequest)
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
        .onAppear {
            // Cold launch from the share extension: the request is already set
            // before this view mounts, so onChange never fires. MeetingsView owns
            // the import handling and is lazily built by TabView, so select its
            // tab up front or the pending import is dropped.
            if sharedAudioImportRequest != nil {
                selectedTab = .meetings
            }
        }
        .onChange(of: sharedAudioImportRequest?.id) { _, newValue in
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
    ContentView(sharedAudioImportRequest: .constant(nil))
        .modelContainer(for: [Action.self, Meeting.self, EveMessage.self, ChatConversation.self], inMemory: true)
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationManager.shared)
}
