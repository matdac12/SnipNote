//
//  ActionsView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData

struct ActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allActions: [Action]
    
    @State private var filter: ActionFilter = .all
    
    enum ActionFilter: String, CaseIterable {
        case all = "ALL"
        case pending = "PENDING"
        case completed = "COMPLETED"
    }
    
    private var filteredActions: [Action] {
        switch filter {
        case .all:
            return allActions
        case .pending:
            return allActions.filter { !$0.isCompleted }
        case .completed:
            return allActions.filter { $0.isCompleted }
        }
    }
    
    private var pendingCount: Int {
        allActions.filter { !$0.isCompleted }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text("[ ACTIONS ]")
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .foregroundColor(.green)
                
                Spacer()
                
                if pendingCount > 0 {
                    Text("\(pendingCount) PENDING")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
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
            .padding()
            
            if filteredActions.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Text("NO ACTIONS FOUND")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(filter == .all ? "CREATE NOTES TO GENERATE ACTIONS" : "NO \(filter.rawValue) ACTIONS")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredActions.sorted(by: { 
                        if $0.isCompleted != $1.isCompleted {
                            return !$0.isCompleted && $1.isCompleted
                        }
                        return $0.dateCreated > $1.dateCreated
                    })) { action in
                        ActionRowView(action: action)
                            .listRowBackground(Color.clear)
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
                .listStyle(PlainListStyle())
                .scrollContentBackground(.hidden)
            }
        }
        .background(.black)
    }
    
    private func completeAction(_ action: Action) {
        withAnimation {
            if action.isCompleted {
                action.uncomplete()
            } else {
                action.complete()
            }
            
            do {
                try modelContext.save()
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
            } catch {
                print("Error deleting action: \(error)")
            }
        }
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