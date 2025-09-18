//
//  EveMessage.swift
//  SnipNote
//
//  Created by Eve AI Assistant on 03/08/25.
//

import Foundation
import SwiftData

enum EveMessageRole: String, Codable {
    case user
    case assistant
}

@Model
final class EveMessage {
    var id: UUID
    var content: String
    var roleRawValue: String
    var timestamp: Date
    var conversationId: UUID
    
    var role: EveMessageRole {
        get { EveMessageRole(rawValue: roleRawValue) ?? .user }
        set { roleRawValue = newValue.rawValue }
    }
    
    init(content: String, role: EveMessageRole, conversationId: UUID) {
        self.id = UUID()
        self.content = content
        self.roleRawValue = role.rawValue
        self.timestamp = Date()
        self.conversationId = conversationId
    }
}