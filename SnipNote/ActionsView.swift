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
    @Query private var allNotes: [Note]
    @Query private var allMeetings: [Meeting]
    
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
            
            if let note = allNotes.first(where: { $0.id == sourceId }) {
                let noteTitle = note.title.isEmpty ? "Untitled Note" : note.title
                groupTitle = "N • \(noteTitle)"
            } else if let meeting = allMeetings.first(where: { $0.id == sourceId }) {
                let meetingName = meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
                groupTitle = "M • \(meetingName)"
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
                Text("[ ACTIONS ]")
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .foregroundColor(.green)
                
                Spacer()
                
                Button(action: {
                    generateReport()
                }) {
                    HStack(spacing: 6) {
                        if isGeneratingReport {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                        }
                        Text("REPORT")
                    }
                }
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundColor(isGeneratingReport ? .gray : .green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isGeneratingReport ? .gray.opacity(0.2) : .green.opacity(0.2))
                .overlay(
                    Rectangle()
                        .stroke(isGeneratingReport ? .gray : .green, lineWidth: 1)
                )
                .cornerRadius(4)
                .disabled(isGeneratingReport || allActions.isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            VStack(spacing: 8) {
                // Filter buttons
                HStack(spacing: 16) {
                    ForEach(ActionFilter.allCases, id: \.self) { filterOption in
                        Button(filterOption.rawValue) {
                            filter = filterOption
                        }
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundColor(filter == filterOption ? .black : .green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(filter == filterOption ? .green : .clear)
                        .overlay(
                            Rectangle()
                                .stroke(.green, lineWidth: 1)
                        )
                    }
                    Spacer()
                }
                
                // Expand All button
                HStack {
                    Button(allExpanded ? "COLLAPSE ALL" : "EXPAND ALL") {
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
                    }
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.1))
                    .overlay(
                        Rectangle()
                            .stroke(.orange, lineWidth: 1)
                    )
                    .cornerRadius(4)
                    
                    Spacer()
                }
            }
            .padding()
            
            if filteredActions.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Text("NO ACTIONS FOUND")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("NO \(filter.rawValue) ACTIONS")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
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
                                        .tint(.green)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            deleteAction(action)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .tint(.red)
                                    }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .scrollContentBackground(.hidden)
            }
        }
        .background(.black)
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
                    
                    if let note = allNotes.first(where: { $0.id == sourceId }) {
                        let noteTitle = note.title.isEmpty ? "Untitled Note" : note.title
                        return "N • \(noteTitle)"
                    } else if let meeting = allMeetings.first(where: { $0.id == sourceId }) {
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
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundColor(.green)
                        .lineLimit(1)
                    
                    Text("\(actionCount) ACTION\(actionCount == 1 ? "" : "S")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(.green)
                    .rotationEffect(.degrees(isExpanded ? 0 : 0))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActionRowView: View {
    let action: Action
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                
                Text("[\(action.priority.rawValue)]")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundColor(priorityColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor.opacity(0.2))
                    .cornerRadius(3)
                
                Spacer()
                
                if action.isCompleted {
                    Text("✓ COMPLETED")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Text(action.dateCreated, style: .date)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Text(action.title)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(action.isCompleted ? .secondary : .green)
                .strikethrough(action.isCompleted)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            if action.isCompleted, let completedDate = action.dateCompleted {
                Text("Completed \(completedDate, style: .date)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var priorityColor: Color {
        switch action.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}

#Preview {
    ActionsView()
        .modelContainer(for: Action.self, inMemory: true)
}