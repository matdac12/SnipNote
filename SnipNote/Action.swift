//
//  Action.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import SwiftData

enum ActionPriority: String, CaseIterable, Codable {
    case high = "HIGH"
    case medium = "MED"
    case low = "LOW"
    
    var color: String {
        switch self {
        case .high: return "red"
        case .medium: return "orange"
        case .low: return "green"
        }
    }
}

@Model
final class Action {
    var id: UUID
    var title: String
    var priority: ActionPriority
    var isCompleted: Bool
    var sourceNoteId: UUID?
    var dateCreated: Date
    var dateCompleted: Date?
    
    init(title: String, priority: ActionPriority = .medium, sourceNoteId: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.priority = priority
        self.isCompleted = false
        self.sourceNoteId = sourceNoteId
        self.dateCreated = Date()
        self.dateCompleted = nil
    }
    
    func complete() {
        isCompleted = true
        dateCompleted = Date()
    }
    
    func uncomplete() {
        isCompleted = false
        dateCompleted = nil
    }
}