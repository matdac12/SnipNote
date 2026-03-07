//
//  FailedMinutesDebitQueue.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation
import Combine

@MainActor
final class FailedMinutesDebitQueue: ObservableObject {
    static let shared = FailedMinutesDebitQueue()

    private let storageKey = "failedMinutesDebits"
    private let maxRetryCount = 8
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60

    @Published private(set) var pendingDebits: [FailedMinutesDebitData] = []

    private init() {
        load()
        cleanupOldDebits()
    }

    func addDebit(meetingID: String, seconds: Int, errorMessage: String?) {
        if let index = pendingDebits.firstIndex(where: { $0.meetingID == meetingID }) {
            pendingDebits[index].seconds = seconds
            pendingDebits[index].lastError = errorMessage
            pendingDebits[index].updatedAt = Date()
        } else {
            pendingDebits.append(
                FailedMinutesDebitData(
                    meetingID: meetingID,
                    seconds: seconds,
                    retryCount: 0,
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastError: errorMessage
                )
            )
        }

        save()
        print("📝 [MinutesDebitQueue] Queued debit retry for meeting \(meetingID)")
    }

    func markRetryFailure(meetingID: String, errorMessage: String?) {
        guard let index = pendingDebits.firstIndex(where: { $0.meetingID == meetingID }) else {
            return
        }

        pendingDebits[index].retryCount += 1
        pendingDebits[index].updatedAt = Date()
        pendingDebits[index].lastError = errorMessage

        if pendingDebits[index].retryCount >= maxRetryCount {
            print("🗑️ [MinutesDebitQueue] Removing meeting \(meetingID) after \(maxRetryCount) failed debit retries")
            pendingDebits.remove(at: index)
        }

        save()
    }

    func removeDebit(meetingID: String) {
        guard let index = pendingDebits.firstIndex(where: { $0.meetingID == meetingID }) else {
            return
        }

        pendingDebits.remove(at: index)
        save()
        print("✅ [MinutesDebitQueue] Cleared pending debit for meeting \(meetingID)")
    }

    func getPendingDebits() -> [FailedMinutesDebitData] {
        pendingDebits
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FailedMinutesDebitData].self, from: data) else {
            return
        }

        pendingDebits = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pendingDebits) else {
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func cleanupOldDebits() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let originalCount = pendingDebits.count
        pendingDebits.removeAll { $0.updatedAt < cutoff }

        if pendingDebits.count != originalCount {
            save()
            print("🧹 [MinutesDebitQueue] Removed \(originalCount - pendingDebits.count) expired pending debit entries")
        }
    }
}

struct FailedMinutesDebitData: Codable {
    let meetingID: String
    var seconds: Int
    var retryCount: Int
    let createdAt: Date
    var updatedAt: Date
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case seconds
        case retryCount = "retry_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastError = "last_error"
    }
}
