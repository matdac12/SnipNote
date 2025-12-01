//
//  MeetingSyncService.swift
//  SnipNote
//
//  Created by Claude on 24/11/25.
//

import Foundation
import SwiftData

/// Service responsible for syncing meetings between local SwiftData and Supabase
/// Uses server-as-truth strategy: Supabase data overwrites local data
@MainActor
class MeetingSyncService: ObservableObject {
    static let shared = MeetingSyncService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var lastSyncError: String?

    private init() {}

    /// Sync meetings from Supabase to local SwiftData
    /// - Server wins on conflicts (overwrites local data)
    /// - Meetings not on server are deleted locally (delete sync)
    /// - Meetings being processed locally are not overwritten
    func syncFromServer(modelContext: ModelContext) async throws {
        guard !isSyncing else {
            print("⚠️ [Sync] Already syncing, skipping...")
            return
        }

        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        print("🔄 [Sync] Starting sync from Supabase...")

        // 1. Fetch all meetings with content from Supabase
        let remoteMeetings = try await SupabaseManager.shared.getAllMeetingsWithContent()

        // 2. Process each remote meeting
        var syncedCount = 0
        var createdCount = 0
        var skippedCount = 0

        for remoteData in remoteMeetings {
            let result = try mergeRemoteMeeting(remoteData, into: modelContext)
            switch result {
            case .updated:
                syncedCount += 1
            case .created:
                createdCount += 1
            case .skipped:
                skippedCount += 1
            }
        }

        // 3. Delete local meetings not on server (delete sync)
        let deletedCount = try deleteOrphanedLocalMeetings(
            remoteMeetingIds: Set(remoteMeetings.map { $0.meeting.id }),
            modelContext: modelContext
        )

        // 4. Save all changes
        try modelContext.save()

        lastSyncDate = Date()
        print("✅ [Sync] Complete: \(syncedCount) updated, \(createdCount) created, \(skippedCount) skipped, \(deletedCount) deleted")
    }

    // MARK: - Private Helpers

    private enum MergeResult {
        case updated
        case created
        case skipped
    }

    private func mergeRemoteMeeting(_ remoteData: MeetingWithContent, into context: ModelContext) throws -> MergeResult {
        let record = remoteData.meeting
        let meetingId = record.id

        // Fetch existing meeting by ID
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.id == meetingId }
        )

        if let existingMeeting = try context.fetch(descriptor).first {
            // Skip if meeting is actively processing locally
            if existingMeeting.isProcessing {
                print("⏭️ [Sync] Skipping '\(existingMeeting.name)' - currently processing")
                return .skipped
            }

            // Server wins: overwrite local data
            updateMeeting(existingMeeting, from: remoteData)
            print("📝 [Sync] Updated '\(existingMeeting.name)'")
            return .updated
        } else {
            // Create new local meeting from server data
            let newMeeting = createMeeting(from: remoteData)
            context.insert(newMeeting)
            print("➕ [Sync] Created '\(newMeeting.name)'")
            return .created
        }
    }

    private func updateMeeting(_ meeting: Meeting, from remoteData: MeetingWithContent) {
        let record = remoteData.meeting

        // Update metadata
        meeting.name = record.name
        meeting.location = record.location ?? ""
        meeting.meetingNotes = record.meetingNotes ?? ""
        meeting.startTime = record.startTime
        meeting.endTime = record.endTime
        meeting.dateCreated = record.dateCreated
        meeting.dateModified = record.dateModified
        meeting.hasRecording = record.hasRecording
        meeting.processingStateRaw = record.processingState
        meeting.processingError = record.processingError
        meeting.lastProcessedChunk = record.lastProcessedChunk
        meeting.totalChunks = record.totalChunks
        meeting.transcriptionJobId = record.transcriptionJobId?.uuidString

        // Update content (from transcription_jobs table)
        if let transcript = remoteData.transcript {
            meeting.audioTranscript = transcript
        }
        if let shortSummary = remoteData.shortSummary {
            meeting.shortSummary = shortSummary
        }
        if let aiSummary = remoteData.aiSummary {
            meeting.aiSummary = aiSummary
        }
    }

    private func createMeeting(from remoteData: MeetingWithContent) -> Meeting {
        let record = remoteData.meeting

        let meeting = Meeting(
            name: record.name,
            location: record.location ?? "",
            meetingNotes: record.meetingNotes ?? "",
            audioTranscript: remoteData.transcript ?? "",
            shortSummary: remoteData.shortSummary ?? "",
            aiSummary: remoteData.aiSummary ?? "",
            hasRecording: record.hasRecording
        )

        // Set the ID to match the server
        meeting.id = record.id

        // Set additional properties
        meeting.startTime = record.startTime
        meeting.endTime = record.endTime
        meeting.dateCreated = record.dateCreated
        meeting.dateModified = record.dateModified
        meeting.processingStateRaw = record.processingState
        meeting.processingError = record.processingError
        meeting.lastProcessedChunk = record.lastProcessedChunk
        meeting.totalChunks = record.totalChunks
        meeting.transcriptionJobId = record.transcriptionJobId?.uuidString

        return meeting
    }

    private func deleteOrphanedLocalMeetings(remoteMeetingIds: Set<UUID>, modelContext: ModelContext) throws -> Int {
        // Fetch all local meetings
        let allLocalMeetings = try modelContext.fetch(FetchDescriptor<Meeting>())

        var deletedCount = 0

        for localMeeting in allLocalMeetings {
            if !remoteMeetingIds.contains(localMeeting.id) {
                // Skip if meeting is actively processing (don't delete work in progress)
                if localMeeting.isProcessing {
                    print("⏭️ [Sync] Not deleting '\(localMeeting.name)' - currently processing")
                    continue
                }

                print("🗑️ [Sync] Removing local meeting not found on server: '\(localMeeting.name)'")
                modelContext.delete(localMeeting)
                deletedCount += 1
            }
        }

        return deletedCount
    }
}
