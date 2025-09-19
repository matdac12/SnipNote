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
    @State private var selectedTab: Tab = .meetings
    @Binding var shouldNavigateToActions: Bool
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @AppStorage("showActionsTab") private var showActionsTab = false
    @State private var selectedMeetingForEve: UUID?
    
    private var pendingActionsCount: Int {
        return actions.filter { !$0.isCompleted }.count
    }

    private enum Tab: Hashable {
        case meetings
        case actions
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

            if showActionsTab {
                ActionsView()
                    .tabItem {
                        Image(systemName: "checklist")
                        Text(tabTitle(for: "tab.actions"))
                            .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    }
                    .badge(pendingActionsCount)
                    .tag(Tab.actions)
            }

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
        .onChange(of: shouldNavigateToActions) { _, newValue in
            if newValue {
                // Navigate to Actions tab when notification is tapped
                if showActionsTab {
                    selectedTab = .actions
                } else {
                    selectedTab = .meetings
                }
                shouldNavigateToActions = false
            }
        }
        .onChange(of: showActionsTab) { _, isEnabled in
            if !isEnabled && selectedTab == .actions {
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
        let base = localizationManager.localizedString(key)
        if themeManager.currentTheme.headerStyle == .brackets {
            return base.uppercased()
        }
        return base
    }

    func navigateToEveWith(meetingId: UUID) {
        selectedMeetingForEve = meetingId
    }
}

#Preview {
    ContentView(deepLinkAudioURL: .constant(nil), shouldNavigateToActions: .constant(false))
        .modelContainer(for: [Action.self, Meeting.self, EveMessage.self, ChatConversation.self, UserAIContext.self, MeetingFileState.self], inMemory: true)
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationManager.shared)
}
