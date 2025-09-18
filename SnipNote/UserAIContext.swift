//
//  UserAIContext.swift
//  SnipNote
//
//  Created by Eve AI Assistant on 08/03/25.
//

import Foundation
import SwiftData

@Model
final class UserAIContext {
    @Attribute(.unique) var userId: UUID
    var vectorStoreId: String?
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MeetingFileState.context) var meetingFiles: [MeetingFileState]

    init(userId: UUID, vectorStoreId: String? = nil, meetingFiles: [MeetingFileState] = []) {
        self.userId = userId
        self.vectorStoreId = vectorStoreId
        self.meetingFiles = meetingFiles
        self.updatedAt = Date()
    }

    func upsertMeetingFile(_ state: MeetingFileState) {
        if let index = meetingFiles.firstIndex(where: { $0.meetingId == state.meetingId }) {
            meetingFiles[index].fileId = state.fileId
            meetingFiles[index].expiresAt = state.expiresAt
            meetingFiles[index].isAttached = state.isAttached
            meetingFiles[index].updatedAt = Date()
        } else {
            state.context = self
            meetingFiles.append(state)
        }
        updatedAt = Date()
    }

    func meetingFile(for meetingId: UUID) -> MeetingFileState? {
        meetingFiles.first(where: { $0.meetingId == meetingId })
    }

    func markDetached(meetingId: UUID) {
        if let index = meetingFiles.firstIndex(where: { $0.meetingId == meetingId }) {
            meetingFiles[index].isAttached = false
            meetingFiles[index].updatedAt = Date()
            updatedAt = Date()
        }
    }

    func removeMeetingFile(meetingId: UUID) {
        meetingFiles.removeAll { $0.meetingId == meetingId }
        updatedAt = Date()
    }
}

@Model
final class MeetingFileState {
    var meetingId: UUID
    var fileId: String
    var expiresAt: Date?
    var isAttached: Bool
    var updatedAt: Date
    @Relationship var context: UserAIContext?

    init(meetingId: UUID, fileId: String, expiresAt: Date?, isAttached: Bool, context: UserAIContext? = nil) {
        self.meetingId = meetingId
        self.fileId = fileId
        self.expiresAt = expiresAt
        self.isAttached = isAttached
        self.context = context
        self.updatedAt = Date()
    }
}
