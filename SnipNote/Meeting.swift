//
//  Meeting.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import SwiftData

enum ProcessingState: String, Codable, CaseIterable {
    case pending = "pending"
    case transcribing = "transcribing"
    case generatingSummary = "generating_summary"
    case failed = "failed"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .transcribing:
            return "Transcribing"
        case .generatingSummary:
            return "Generating Summary"
        case .failed:
            return "Failed"
        case .completed:
            return "Completed"
        }
    }
}

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

    // Error tracking and processing state
    var processingError: String?
    var processingStateRaw: String = ProcessingState.pending.rawValue
    var lastProcessedChunk: Int = 0
    var totalChunks: Int = 0
    var localAudioPath: String? // Path to local audio file for retry

    // Computed property for processing state
    var processingState: ProcessingState {
        get {
            return ProcessingState(rawValue: processingStateRaw) ?? .pending
        }
        set {
            processingStateRaw = newValue.rawValue
        }
    }
    
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

        // Initialize new fields
        self.processingError = nil
        self.processingStateRaw = ProcessingState.pending.rawValue
        self.lastProcessedChunk = 0
        self.totalChunks = 0
        self.localAudioPath = nil
    }
    
    func startRecording() {
        startTime = Date()
    }
    
    func stopRecording() {
        endTime = Date()
    }

    // MARK: - Processing State Management

    func updateProcessingState(_ state: ProcessingState) {
        processingState = state
        dateModified = Date()

        // Auto-update isProcessing based on state
        isProcessing = state == .transcribing || state == .generatingSummary
    }

    func setProcessingError(_ error: String) {
        processingError = error
        processingState = .failed
        isProcessing = false
        dateModified = Date()
    }

    func clearProcessingError() {
        processingError = nil
        dateModified = Date()
    }

    func updateChunkProgress(completed: Int, total: Int) {
        lastProcessedChunk = completed
        totalChunks = total
        dateModified = Date()
    }

    func markCompleted() {
        processingState = .completed
        isProcessing = false
        processingError = nil
        dateModified = Date()
    }

    var progressPercentage: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(lastProcessedChunk) / Double(totalChunks) * 100.0
    }

    var canRetry: Bool {
        return processingState == .failed && localAudioPath != nil
    }
}