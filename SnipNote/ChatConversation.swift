//
//  ChatConversation.swift
//  SnipNote
//
//  Created by Eve AI Assistant on 03/08/25.
//

import Foundation
import SwiftData

@Model
final class ChatConversation {
    var id: UUID
    var title: String
    @Relationship(deleteRule: .cascade) var messages: [EveMessage]
    var selectedMeetingIds: [UUID]
    var selectedNoteIds: [UUID]
    var isSelectingAllContent: Bool
    var dateCreated: Date
    var dateModified: Date
    var openAIConversationId: String?
    
    init(title: String = "New Conversation") {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.selectedMeetingIds = []
        self.selectedNoteIds = []
        self.isSelectingAllContent = true
        self.dateCreated = Date()
        self.dateModified = Date()
        self.openAIConversationId = nil
    }
    
    func addMessage(_ message: EveMessage) {
        messages.append(message)
        dateModified = Date()
    }
}
