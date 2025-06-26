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
    var dateCreated: Date
    var dateModified: Date
    
    init(title: String = "", originalTranscript: String = "", aiSummary: String = "") {
        self.id = UUID()
        self.title = title
        self.originalTranscript = originalTranscript
        self.aiSummary = aiSummary
        self.dateCreated = Date()
        self.dateModified = Date()
    }
}
