//
//  Meeting.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import SwiftData

enum TranscriptionBackend: String, Codable, CaseIterable {
    case cloud
    case local
}

enum MeetingProcessingPhase: String, Codable, CaseIterable {
    case idle
    case queued
    case preparing
    case transcribing
    case generatingOverview = "generating_overview"
    case generatingSummary = "generating_summary"
    case extractingActions = "extracting_actions"
    case paused
    case failed
    case completed

    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .queued:
            return "Queued"
        case .preparing:
            return "Preparing"
        case .transcribing:
            return "Transcribing"
        case .generatingOverview:
            return "Generating Overview"
        case .generatingSummary:
            return "Generating Summary"
        case .extractingActions:
            return "Extracting Actions"
        case .paused:
            return "Paused"
        case .failed:
            return "Failed"
        case .completed:
            return "Completed"
        }
    }
}

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
    var transcriptionJobId: String? // Async transcription job ID for server-side processing
    var transcriptionBackendRaw: String?
    var localTranscriptionModelRaw: String?
    var transcriptionLanguage: String?
    var processingPhaseRaw: String = MeetingProcessingPhase.idle.rawValue
    var progressPercent: Double = 0
    var currentStageDescription: String?
    var pausedAt: Date?
    var pauseReason: String?
    var resumePhaseRaw: String?
    var sourceAudioDurationSeconds: Double = 0
    var didDebitTranscriptionMinutes: Bool = false
    var hasPendingMinutesDebit: Bool = false
    var pendingMinutesDebitError: String?
    var localSpeechPlanJSON: String?
    var localSpeechPlanFingerprint: String?

    // Computed property for processing state
    var processingState: ProcessingState {
        get {
            return ProcessingState(rawValue: processingStateRaw) ?? .pending
        }
        set {
            processingStateRaw = newValue.rawValue
        }
    }

    var transcriptionBackend: TranscriptionBackend? {
        get {
            transcriptionBackendRaw.flatMap(TranscriptionBackend.init(rawValue:))
        }
        set {
            transcriptionBackendRaw = newValue?.rawValue
        }
    }

    var localTranscriptionModel: LocalTranscriptionModel? {
        get {
            localTranscriptionModelRaw.flatMap(LocalTranscriptionModel.init(rawValue:))
        }
        set {
            localTranscriptionModelRaw = newValue?.rawValue
        }
    }

    var processingPhase: MeetingProcessingPhase {
        get {
            MeetingProcessingPhase(rawValue: processingPhaseRaw) ?? .idle
        }
        set {
            processingPhaseRaw = newValue.rawValue
        }
    }

    var resumePhase: MeetingProcessingPhase {
        get {
            resumePhaseRaw.flatMap(MeetingProcessingPhase.init(rawValue:)) ?? .transcribing
        }
        set {
            resumePhaseRaw = newValue.rawValue
        }
    }

    // Computed property - true when actively processing
    var isProcessing: Bool {
        processingState == .transcribing || processingState == .generatingSummary
    }

    var isLocalJob: Bool {
        transcriptionBackend == .local
    }

    var isPausedLocalJob: Bool {
        isLocalJob && processingPhase == .paused
    }

    var canResumeLocalJob: Bool {
        isPausedLocalJob && localAudioPath != nil
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
    
    init(name: String = "", location: String = "", meetingNotes: String = "", audioTranscript: String = "", shortSummary: String = "", aiSummary: String = "", hasRecording: Bool = false) {
        self.id = UUID()
        self.name = name
        self.location = location
        self.meetingNotes = meetingNotes
        self.audioTranscript = audioTranscript
        self.shortSummary = shortSummary
        self.aiSummary = aiSummary
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
        self.transcriptionJobId = nil
        self.transcriptionBackendRaw = nil
        self.localTranscriptionModelRaw = nil
        self.transcriptionLanguage = nil
        self.processingPhaseRaw = MeetingProcessingPhase.idle.rawValue
        self.progressPercent = 0
        self.currentStageDescription = nil
        self.pausedAt = nil
        self.pauseReason = nil
        self.resumePhaseRaw = nil
        self.sourceAudioDurationSeconds = 0
        self.didDebitTranscriptionMinutes = false
        self.hasPendingMinutesDebit = false
        self.pendingMinutesDebitError = nil
        self.localSpeechPlanJSON = nil
        self.localSpeechPlanFingerprint = nil
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
    }

    func setProcessingError(_ error: String) {
        processingError = error
        processingState = .failed
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
        processingError = nil
        dateModified = Date()
    }

    func markMinutesDebitPending(message: String? = nil) {
        didDebitTranscriptionMinutes = false
        hasPendingMinutesDebit = true
        pendingMinutesDebitError = message
        dateModified = Date()
    }

    func markMinutesDebitSettled() {
        didDebitTranscriptionMinutes = true
        hasPendingMinutesDebit = false
        pendingMinutesDebitError = nil
        dateModified = Date()
    }

    func configureTranscriptionJob(
        backend: TranscriptionBackend,
        model: LocalTranscriptionModel? = nil,
        language: String?,
        sourceAudioDuration: TimeInterval
    ) {
        transcriptionBackend = backend
        localTranscriptionModel = model
        transcriptionLanguage = language
        sourceAudioDurationSeconds = sourceAudioDuration
        didDebitTranscriptionMinutes = false
        hasPendingMinutesDebit = false
        pendingMinutesDebitError = nil
        localSpeechPlanJSON = nil
        localSpeechPlanFingerprint = nil
        pausedAt = nil
        pauseReason = nil
        resumePhaseRaw = nil
        dateModified = Date()
    }

    func updateProcessingPhase(
        _ phase: MeetingProcessingPhase,
        stage: String? = nil,
        progressPercent: Double? = nil
    ) {
        processingPhase = phase
        currentStageDescription = stage
        if let progressPercent {
            self.progressPercent = progressPercent
        }
        if phase != .paused {
            pausedAt = nil
            pauseReason = nil
            resumePhaseRaw = nil
        }
        dateModified = Date()
    }

    func updateDetailedProgress(
        completed: Int,
        total: Int,
        percent: Double,
        stage: String?
    ) {
        lastProcessedChunk = completed
        totalChunks = total
        progressPercent = percent
        currentStageDescription = stage
        processingPhase = .transcribing
        processingState = .transcribing
        pausedAt = nil
        pauseReason = nil
        resumePhaseRaw = nil
        dateModified = Date()
    }

    func markLocalJobPaused(reason: String, stage: String? = nil) {
        processingError = reason
        processingState = .failed
        resumePhase = processingPhase
        processingPhase = .paused
        currentStageDescription = stage ?? reason
        pauseReason = reason
        pausedAt = Date()
        dateModified = Date()
    }

    func markLocalJobFailed(_ error: String, stage: String? = nil) {
        processingError = error
        processingState = .failed
        processingPhase = .failed
        currentStageDescription = stage ?? error
        pausedAt = nil
        pauseReason = nil
        resumePhaseRaw = nil
        dateModified = Date()
    }

    func markLocalJobCompleted(stage: String = "Completed") {
        processingPhase = .completed
        currentStageDescription = stage
        progressPercent = 100
        pausedAt = nil
        pauseReason = nil
        resumePhaseRaw = nil
        markCompleted()
    }

    var progressPercentage: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(lastProcessedChunk) / Double(totalChunks) * 100.0
    }

    var displayedProgressPercent: Double {
        progressPercent > 0 ? progressPercent : progressPercentage
    }

    var billingDuration: TimeInterval {
        sourceAudioDurationSeconds > 0 ? sourceAudioDurationSeconds : duration
    }

    var effectiveStageDescription: String {
        if let currentStageDescription, !currentStageDescription.isEmpty {
            return currentStageDescription
        }

        if isPausedLocalJob, let pauseReason, !pauseReason.isEmpty {
            return pauseReason
        }

        return processingPhase.displayName
    }

    var hasTranscriptContent: Bool {
        let trimmed = audioTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let placeholders = [
            "Transcribing meeting audio...",
            "Transcription failed"
        ]

        return !placeholders.contains(trimmed)
    }

    var canRetryAnalysis: Bool {
        let overviewPending = shortSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || shortSummary == "Generating overview..."
            || shortSummary == "AI overview unavailable"
        let summaryPending = aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || aiSummary == "Generating meeting summary..."
        return processingState == .failed
            && hasTranscriptContent
            && localAudioPath != nil
            && (overviewPending || summaryPending)
    }

    var canRetry: Bool {
        return (processingState == .failed || isPausedLocalJob) && localAudioPath != nil
    }
}
