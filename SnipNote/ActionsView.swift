//
//  ActionsView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData
import UserNotifications

struct ActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allActions: [Action]
    @Query private var allMeetings: [Meeting]
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var filter: ActionFilter = .toDo
    @State private var expandedSections: Set<String> = []
    @State private var allExpanded: Bool = false
    @State private var showingReport = false
    @State private var reportContent = ""
    @State private var isGeneratingReport = false
    
    enum ActionFilter: String, CaseIterable {
        case toDo = "TO DO"
        case completed = "COMPLETED"
    }
    
    private var filteredActions: [Action] {
        switch filter {
        case .toDo:
            return allActions.filter { !$0.isCompleted }
        case .completed:
            return allActions.filter { $0.isCompleted }
        }
    }
    
    private var groupedActions: [String: [Action]] {
        var grouped: [String: [Action]] = [:]

        for action in filteredActions {
            guard let sourceId = action.sourceNoteId else { continue }

            var groupTitle = "Unknown Source"

            if let meeting = allMeetings.first(where: { $0.id == sourceId }) {
                let meetingName = meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
                groupTitle = "M • \(meetingName)"
            } else {
                // Handle orphaned note actions gracefully
                groupTitle = "Legacy Notes"
            }

            if grouped[groupTitle] == nil {
                grouped[groupTitle] = []
            }
            grouped[groupTitle]?.append(action)
        }

        return grouped
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text(themeManager.currentTheme.headerStyle == .brackets ? "[ ACTIONS ]" : "Actions")
                    .themedTitle()
                
                Spacer()
                
                Button(action: {
                    generateReport()
                }) {
                    HStack(spacing: 6) {
                        if isGeneratingReport {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                        } else {
                            Image(systemName: "doc.text")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(themeManager.currentTheme.headerStyle == .brackets ? "REPORT" : "Report")
                            .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    }
                }
                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(isGeneratingReport ? themeManager.currentTheme.secondaryTextColor : themeManager.currentTheme.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isGeneratingReport ? themeManager.currentTheme.secondaryTextColor.opacity(0.2) : themeManager.currentTheme.accentColor.opacity(0.15))

                .clipShape(Capsule())
                .shadow(color: isGeneratingReport ? Color.clear : themeManager.currentTheme.accentColor.opacity(0.2), radius: 3, x: 0, y: 2)
                .buttonStyle(PlainButtonStyle())
                .disabled(isGeneratingReport || allActions.isEmpty)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [
                        themeManager.currentTheme.secondaryBackgroundColor.opacity(0.9),
                        themeManager.currentTheme.backgroundColor
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // Divider line
            Rectangle()
                .fill(themeManager.currentTheme.secondaryTextColor.opacity(0.1))
                .frame(height: 1)
            
            VStack(spacing: 8) {
                // Filter buttons
                HStack(spacing: 12) {
                    ForEach(ActionFilter.allCases, id: \.self) { filterOption in
                        Button(action: {
                            filter = filterOption
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: filterOption == .toDo ? "list.bullet" : "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(filterOption.rawValue)
                                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                            }
                            .foregroundColor(filter == filterOption ? themeManager.currentTheme.backgroundColor : themeManager.currentTheme.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(filter == filterOption ? themeManager.currentTheme.accentColor : themeManager.currentTheme.secondaryBackgroundColor.opacity(0.5))
                            .clipShape(Capsule())
                            .shadow(color: filter == filterOption ? themeManager.currentTheme.accentColor.opacity(0.3) : Color.clear, radius: 3, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                }
                
                // Expand All button
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            allExpanded.toggle()
                            if allExpanded {
                                // Expand all sections
                                expandedSections = Set(groupedActions.keys)
                            } else {
                                // Collapse all sections
                                expandedSections.removeAll()
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: allExpanded ? "chevron.up.chevron.down" : "chevron.right.chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text(themeManager.currentTheme.headerStyle == .brackets ? (allExpanded ? "COLLAPSE ALL" : "EXPAND ALL") : (allExpanded ? "Collapse All" : "Expand All"))
                                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                        }
                        .foregroundColor(themeManager.currentTheme.warningColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(themeManager.currentTheme.warningColor.opacity(0.15))
                        .clipShape(Capsule())
                        .shadow(color: themeManager.currentTheme.warningColor.opacity(0.2), radius: 3, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()
                }
            }
            .padding()
            
            if filteredActions.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "NO ACTIONS FOUND" : "No actions found")
                        .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "NO \(filter.rawValue) ACTIONS" : "No \(filter.rawValue.lowercased()) actions")
                        .themedCaption()
                    Spacer()
                }
            } else {
                List {
                    ForEach(groupedActions.keys.sorted(), id: \.self) { groupTitle in
                        // Group header (always visible as separate row)
                        ExpandableGroupHeaderView(
                            title: groupTitle,
                            actionCount: groupedActions[groupTitle]?.count ?? 0,
                            isExpanded: expandedSections.contains(groupTitle),
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedSections.contains(groupTitle) {
                                        expandedSections.remove(groupTitle)
                                    } else {
                                        expandedSections.insert(groupTitle)
                                    }
                                    // Update allExpanded state based on current sections
                                    allExpanded = expandedSections.count == groupedActions.count
                                }
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        
                        // Expandable actions (only show if expanded, each as separate row)
                        if expandedSections.contains(groupTitle) {
                            ForEach(groupedActions[groupTitle]?.sorted(by: { 
                                if $0.isCompleted != $1.isCompleted {
                                    return !$0.isCompleted && $1.isCompleted
                                }
                                return $0.dateCreated > $1.dateCreated
                            }) ?? []) { action in
                                ActionRowView(action: action)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 2, leading: 32, bottom: 2, trailing: 16))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button {
                                            completeAction(action)
                                        } label: {
                                            Image(systemName: action.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                        }
                                        .tint(themeManager.currentTheme.accentColor)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            deleteAction(action)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .tint(themeManager.currentTheme.destructiveColor)
                                    }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
            }
        }
        .themedBackground()
        .sheet(isPresented: $showingReport) {
            ActionsReportView(reportContent: reportContent)
        }
    }
    
    private func completeAction(_ action: Action) {
        withAnimation {
            let wasCompleted = action.isCompleted
            
            if action.isCompleted {
                action.uncomplete()
            } else {
                action.complete()
            }
            
            do {
                try modelContext.save()
                
                // Track action completion status change
                Task {
                    if !wasCompleted && action.isCompleted {
                        // Action was just completed
                        await UsageTracker.shared.trackActionsCompleted(count: 1)
                    } else if wasCompleted && !action.isCompleted {
                        // Action was uncompleted (subtract from completed count)
                        await UsageTracker.shared.trackActionsCompleted(count: -1)
                    }
                }
                
                // Update notifications after action completion changes
                Task { @MainActor in
                    NotificationService.shared.scheduleNotification(with: allActions)
                    // Also update badge immediately
                    await NotificationService.shared.updateBadgeCount(with: allActions)
                }
            } catch {
                print("Error updating action: \(error)")
            }
        }
    }
    
    private func deleteAction(_ action: Action) {
        withAnimation {
            modelContext.delete(action)
            
            do {
                try modelContext.save()
                // Update notifications after action deletion
                Task { @MainActor in
                    // Need to fetch remaining actions after deletion
                    let remainingActions = allActions.filter { $0.id != action.id }
                    NotificationService.shared.scheduleNotification(with: remainingActions)
                    // Update badge immediately based on remaining actions
                    await NotificationService.shared.updateBadgeCount(with: remainingActions)
                }
            } catch {
                print("Error deleting action: \(error)")
            }
        }
    }
    
    private func generateReport() {
        isGeneratingReport = true
        
        Task {
            do {
                // Prepare data for report generation
                var actionsData: [String: [(action: String, priority: String, isCompleted: Bool)]] = [:]
                
                for (groupTitle, actions) in groupedActions {
                    actionsData[groupTitle] = actions.map { action in
                        (action: action.title, 
                         priority: action.priority.rawValue,
                         isCompleted: action.isCompleted)
                    }
                }
                
                // Also include completed actions for a comprehensive report
                let allGroupedActions = Dictionary(grouping: allActions) { action -> String in
                    guard let sourceId = action.sourceNoteId else { return "Unknown Source" }
                    
                    if let meeting = allMeetings.first(where: { $0.id == sourceId }) {
                        let meetingName = meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
                        return "M • \(meetingName)"
                    }
                    return "Unknown Source"
                }
                
                var allActionsData: [String: [(action: String, priority: String, isCompleted: Bool)]] = [:]
                for (groupTitle, actions) in allGroupedActions {
                    allActionsData[groupTitle] = actions.map { action in
                        (action: action.title, 
                         priority: action.priority.rawValue,
                         isCompleted: action.isCompleted)
                    }
                }
                
                reportContent = try await OpenAIService.shared.generateActionsReport(groupedActions: allActionsData)
                showingReport = true
            } catch {
                print("Error generating report: \(error)")
                reportContent = "Failed to generate report. Please try again."
                showingReport = true
            }
            
            isGeneratingReport = false
        }
    }
    
}

struct ExpandableGroupHeaderView: View {
    let title: String
    let actionCount: Int
    let isExpanded: Bool
    let onTap: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(themeManager.currentTheme.headerStyle == .brackets ? title.uppercased() : title)

                        .foregroundColor(themeManager.currentTheme.accentColor)
                        .lineLimit(1)
                    
                    Text("\(actionCount) \(themeManager.currentTheme.headerStyle == .brackets ? "ACTION\(actionCount == 1 ? "" : "S")" : "action\(actionCount == 1 ? "" : "s")" )")
                        .themedCaption()
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.accentColor)
                    .rotationEffect(.degrees(isExpanded ? 0 : 0))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(themeManager.currentTheme.materialStyle)
            .cornerRadius(themeManager.currentTheme.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActionRowView: View {
    let action: Action
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(displayTitle)
                            .themedBody()
                            .foregroundColor(titleColor)
                            .strikethrough(action.isCompleted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)

                        Spacer(minLength: 8)

                        if action.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(themeManager.currentTheme.accentColor)
                        }
                    }

                    HStack(spacing: 8) {
                        priorityBadge

                        Text(dateLabel)
                            .themedCaption()
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(16)
        .background(themeManager.currentTheme.materialStyle)
        .cornerRadius(themeManager.currentTheme.cornerRadius)
        .shadow(
            color: Color.black.opacity(shadowOpacity),
            radius: 4,
            x: 0,
            y: 2
        )
        .padding(.vertical, 4)
    }

    private var shadowOpacity: Double {
        themeManager.currentTheme.colorScheme == .dark ? 0.45 : 0.18
    }

    private var displayTitle: String {
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return themeManager.currentTheme.headerStyle == .brackets ? "UNTITLED ACTION" : "Untitled Action"
        }
        return title
    }

    private var titleColor: Color {
        action.isCompleted ? themeManager.currentTheme.secondaryTextColor : themeManager.currentTheme.accentColor
    }

    @ViewBuilder
    private var priorityBadge: some View {
        Text(priorityLabel)
            .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
            .foregroundColor(priorityColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priorityColor.opacity(0.18))
            .cornerRadius(6)
    }

    private var priorityLabel: String {
        switch themeManager.currentTheme.headerStyle {
        case .brackets:
            return action.priority.rawValue
        case .plain:
            switch action.priority {
            case .high: return "High Priority"
            case .medium: return "Medium Priority"
            case .low: return "Low Priority"
            }
        }
    }

    private var dateLabel: String {
        let formatter = Date.FormatStyle(date: .abbreviated, time: .omitted)
        let base: String
        let date: Date

        if action.isCompleted, let completed = action.dateCompleted {
            base = themeManager.currentTheme.headerStyle == .brackets ? "COMPLETED" : "Completed"
            date = completed
        } else {
            base = themeManager.currentTheme.headerStyle == .brackets ? "CREATED" : "Created"
            date = action.dateCreated
        }

        let formatted = date.formatted(formatter)
        return themeManager.currentTheme.headerStyle == .brackets ? "\(base) \(formatted.uppercased())" : "\(base) \(formatted)"
    }

    private var priorityColor: Color {
        switch action.priority {
        case .high:
            return themeManager.currentTheme.destructiveColor
        case .medium:
            return themeManager.currentTheme.warningColor
        case .low:
            return themeManager.currentTheme.accentColor
        }
    }
}

#Preview {
    ActionsView()
        .modelContainer(for: Action.self, inMemory: true)
}
