//
//  Meeting.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import SwiftData

@Model
final class Meeting {
    var id: UUID
    var name: String
    var location: String
    var meetingNotes: String // Pre-meeting notes
    var audioTranscript: String
    var shortSummary: String // One-sentence overview
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
    
    init(name: String = "", location: String = "", meetingNotes: String = "", audioTranscript: String = "", shortSummary: String = "", aiSummary: String = "", isProcessing: Bool = false, hasRecording: Bool = false) {
        self.id = UUID()
        self.name = name
        self.location = location
        self.meetingNotes = meetingNotes
        self.audioTranscript = audioTranscript
        self.shortSummary = shortSummary
        self.aiSummary = aiSummary
        self.isProcessing = isProcessing
        self.hasRecording = hasRecording
        self.startTime = nil
        self.endTime = nil
        self.dateCreated = Date()
        self.dateModified = Date()
    }
    
    func startRecording() {
        startTime = Date()
    }
    
    func stopRecording() {
        endTime = Date()
    }
}