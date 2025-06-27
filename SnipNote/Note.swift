//
//  Note.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var title: String
    var originalTranscript: String
    var aiSummary: String
    var isProcessing: Bool
    var dateCreated: Date
    var dateModified: Date
    
    init(title: String = "", originalTranscript: String = "", aiSummary: String = "", isProcessing: Bool = false) {
        self.id = UUID()
        self.title = title
        self.originalTranscript = originalTranscript
        self.aiSummary = aiSummary
        self.isProcessing = isProcessing
        self.dateCreated = Date()
        self.dateModified = Date()
    }
}
