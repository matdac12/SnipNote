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
    var startTime: Date?
    var endTime: Date?
    var dateCreated: Date
    var dateModified: Date
    var hasRecording: Bool = false // Indicates if audio is stored in Supabase
    
    // Computed property for duration
    var duration: TimeInterval {
        guard let start = startTime, let end = endTime else { return 0 }
        return end.timeIntervalSince(start)
    }
    
    var durationFormatted: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
    
    init(title: String = "", originalTranscript: String = "", aiSummary: String = "", isProcessing: Bool = false, hasRecording: Bool = false) {
        self.id = UUID()
        self.title = title
        self.originalTranscript = originalTranscript
        self.aiSummary = aiSummary
        self.isProcessing = isProcessing
        self.dateCreated = Date()
        self.dateModified = Date()
        self.hasRecording = hasRecording
    }
}
