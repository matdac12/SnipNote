//
//  MeetingSyncService.swift
//  SnipNote
//
//  Created by Claude on 24/11/25.
//

import Foundation
import SwiftData

/// Service responsible for syncing meetings between local SwiftData and Supabase
/// Server wins on conflicts for meetings that exist on both sides, but a local meeting is
/// never deleted just because the server lacks it: local-only meetings are pushed instead,
/// and only an explicit server tombstone (`meeting_deletions`) removes one locally.
@MainActor
class MeetingSyncService: ObservableObject {
    static let shared = MeetingSyncService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var lastSyncError: String?

    private init() {}

    /// Sync meetings between local SwiftData and Supabase
    /// - Meetings tombstoned on the server are removed locally (delete sync)
    /// - Local meetings missing from the server are pushed before anything is pulled, so a
    ///   Guest who creates an Account keeps every recording
    /// - Server wins on conflicts for meetings present on both sides
    /// - Meetings being processed locally are neither overwritten, pushed nor deleted
    /// Returns false when another sync was already running and this call did nothing, so callers
    /// that need the push to have happened (account setup) can retry instead of assuming it ran.
    @discardableResult
    func syncFromServer(modelContext: ModelContext) async throws -> Bool {
        guard !isSyncing else {
            print("⚠️ [Sync] Already syncing, skipping...")
            return false
        }

        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        print("🔄 [Sync] Starting sync from Supabase...")

        // 1. Fetch all meetings with content from Supabase
        let remoteMeetings = try await SupabaseManager.shared.getAllMeetingsWithContent()
        let remoteMeetingIds = Set(remoteMeetings.map { $0.meeting.id })

        // Without the tombstone list we cannot tell "never synced" from "deleted elsewhere", so a
        // failed fetch skips the delete and push steps but still lets the pull go ahead.
        var deletedMeetingIds: Set<UUID> = []
        var deletedCount = 0
        var pushedCount = 0

        do {
            deletedMeetingIds = try await SupabaseManager.shared.getMeetingDeletions()

            // 2. Remove local meetings the server explicitly says were deleted
            deletedCount = try deleteTombstonedLocalMeetings(
                deletedMeetingIds: deletedMeetingIds,
                modelContext: modelContext
            )

            // 3. Push local meetings the server has never seen (before the first pull merges)
            if claimLocalMeetingsForCurrentUser() {
                pushedCount = try await pushLocalOnlyMeetings(
                    remoteMeetingIds: remoteMeetingIds,
                    deletedMeetingIds: deletedMeetingIds,
                    modelContext: modelContext
                )
            }
        } catch {
            print("⚠️ [Sync] Skipping delete and push steps: \(error)")
        }

        // 4. Process each remote meeting
        var syncedCount = 0
        var createdCount = 0
        var skippedCount = 0

        for remoteData in remoteMeetings where !deletedMeetingIds.contains(remoteData.meeting.id) {
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

        if let user = SupabaseManager.shared.client.auth.currentUser?.id {
            await BackgroundUploadReconciler.shared.reconcile(context: modelContext, userID: user)
        }

        // 5. Save all changes
        try modelContext.save()

        lastSyncDate = Date()
        print("✅ [Sync] Complete: \(syncedCount) updated, \(createdCount) created, \(skippedCount) skipped, \(pushedCount) pushed, \(deletedCount) deleted")
        return true
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
            if existingMeeting.isProcessing || existingMeeting.isPausedLocalJob {
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

        // A summary written on another device replaces the local transcript-only notice.
        if !meeting.aiSummary.isEmpty {
            meeting.analysisUnavailableReason = nil
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

    private func deleteTombstonedLocalMeetings(deletedMeetingIds: Set<UUID>, modelContext: ModelContext) throws -> Int {
        guard !deletedMeetingIds.isEmpty else { return 0 }

        let allLocalMeetings = try modelContext.fetch(FetchDescriptor<Meeting>())

        var deletedCount = 0

        for localMeeting in allLocalMeetings where deletedMeetingIds.contains(localMeeting.id) {
            // Skip if meeting is actively processing (don't delete work in progress)
            if localMeeting.isProcessing || localMeeting.isPausedLocalJob {
                print("⏭️ [Sync] Not deleting '\(localMeeting.name)' - currently processing")
                continue
            }

            print("🗑️ [Sync] Removing local meeting deleted elsewhere: '\(localMeeting.name)'")
            modelContext.delete(localMeeting)
            deletedCount += 1
        }

        return deletedCount
    }

    /// Local meetings belong to whoever syncs them first: Guest meetings go to the first Account
    /// created on the device. Signing out keeps them on disk, so a different account signing in
    /// later must not receive another account's meetings.
    private func claimLocalMeetingsForCurrentUser() -> Bool {
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id.uuidString else {
            return false
        }

        let key = "sync.localMeetingsOwnerId"
        guard let owner = UserDefaults.standard.string(forKey: key) else {
            UserDefaults.standard.set(userId, forKey: key)
            return true
        }

        if owner != userId {
            print("⏭️ [Sync] Local meetings belong to another account, not pushing")
        }
        return owner == userId
    }

    /// Uploads local meetings that exist neither on the server nor as a tombstone.
    /// A failed upload is logged and retried on the next sync; nothing is deleted either way.
    private func pushLocalOnlyMeetings(
        remoteMeetingIds: Set<UUID>,
        deletedMeetingIds: Set<UUID>,
        modelContext: ModelContext
    ) async throws -> Int {
        let allLocalMeetings = try modelContext.fetch(FetchDescriptor<Meeting>())

        var pushedCount = 0

        for localMeeting in allLocalMeetings {
            guard !remoteMeetingIds.contains(localMeeting.id),
                  !deletedMeetingIds.contains(localMeeting.id) else { continue }

            if localMeeting.isProcessing || localMeeting.isPausedLocalJob {
                print("⏭️ [Sync] Not pushing '\(localMeeting.name)' - currently processing")
                continue
            }

            do {
                try await SupabaseManager.shared.saveMeeting(localMeeting)
                if localMeeting.hasTranscriptContent {
                    let duration = localMeeting.sourceAudioDurationSeconds > 0
                        ? localMeeting.sourceAudioDurationSeconds
                        : localMeeting.duration
                    try await SupabaseManager.shared.saveCompletedTranscriptionJob(
                        meetingId: localMeeting.id,
                        audioStoragePath: nil,
                        duration: duration,
                        transcript: localMeeting.audioTranscript,
                        overview: localMeeting.shortSummary,
                        summary: localMeeting.aiSummary
                    )
                }
                print("⬆️ [Sync] Pushed local meeting '\(localMeeting.name)'")
                pushedCount += 1
            } catch {
                print("⚠️ [Sync] Failed to push '\(localMeeting.name)', will retry next sync: \(error)")
            }
        }

        return pushedCount
    }
}
