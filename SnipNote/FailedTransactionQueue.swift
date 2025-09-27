//
//  FailedTransactionQueue.swift
//  SnipNote
//
//  Created for tracking failed Supabase transaction validations.
//

import Foundation
import StoreKit

@MainActor
class FailedTransactionQueue: ObservableObject {
    static let shared = FailedTransactionQueue()

    private let storageKey = "failedSupabaseTransactions"
    private let maxRetryCount = 3
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    @Published private(set) var failedTransactions: [FailedTransactionData] = []

    private init() {
        loadFailedTransactions()
        cleanupOldTransactions()
    }

    /// Add a failed transaction to the retry queue
    func addTransaction(_ transaction: Transaction) {
        let transactionData = FailedTransactionData(
            transactionID: String(transaction.id),
            originalTransactionID: String(transaction.originalID),
            productID: transaction.productID,
            environment: transaction.environment.rawValue,
            failedAt: Date(),
            retryCount: 0
        )

        // Check if already exists
        if let index = failedTransactions.firstIndex(where: { $0.transactionID == transactionData.transactionID }) {
            // Update existing entry
            failedTransactions[index].retryCount += 1
            failedTransactions[index].failedAt = Date()

            // Remove if exceeded max retries
            if failedTransactions[index].retryCount >= maxRetryCount {
                print("🗑️ [FailedTransactionQueue] Removing transaction after \(maxRetryCount) failures: \(transactionData.transactionID)")
                failedTransactions.remove(at: index)
            }
        } else {
            // Add new entry
            failedTransactions.append(transactionData)
            print("📝 [FailedTransactionQueue] Added failed transaction: \(transactionData.transactionID)")
        }

        saveFailedTransactions()
    }

    /// Remove a transaction from the queue (after successful retry)
    func removeTransaction(_ transactionID: String) {
        if let index = failedTransactions.firstIndex(where: { $0.transactionID == transactionID }) {
            failedTransactions.remove(at: index)
            saveFailedTransactions()
            print("✅ [FailedTransactionQueue] Removed successful transaction: \(transactionID)")
        }
    }

    /// Get all failed transactions for retry
    func getFailedTransactions() -> [FailedTransactionData] {
        return failedTransactions.filter { $0.retryCount < maxRetryCount }
    }

    /// Get count of failed transactions
    func getFailedCount() -> Int {
        return failedTransactions.count
    }

    /// Clear all failed transactions (for testing/debugging)
    func clearAll() {
        failedTransactions.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("🗑️ [FailedTransactionQueue] Cleared all failed transactions")
    }

    // MARK: - Private Methods

    private func loadFailedTransactions() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let transactions = try? JSONDecoder().decode([FailedTransactionData].self, from: data) {
            failedTransactions = transactions
            print("📋 [FailedTransactionQueue] Loaded \(failedTransactions.count) failed transactions")
        }
    }

    private func saveFailedTransactions() {
        if let data = try? JSONEncoder().encode(failedTransactions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Clean up old failed transactions to prevent storage bloat
    private func cleanupOldTransactions() {
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        let oldTransactions = failedTransactions.filter { $0.failedAt < cutoffDate }

        if !oldTransactions.isEmpty {
            failedTransactions.removeAll { $0.failedAt < cutoffDate }
            saveFailedTransactions()
            print("🧹 [FailedTransactionQueue] Cleaned up \(oldTransactions.count) old failed transactions")
        }
    }

    /// Perform cleanup manually
    func performCleanup() {
        cleanupOldTransactions()
    }
}

// MARK: - Supporting Types

struct FailedTransactionData: Codable {
    let transactionID: String
    let originalTransactionID: String
    let productID: String
    let environment: String
    var failedAt: Date
    var retryCount: Int

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case originalTransactionID = "original_transaction_id"
        case productID = "product_id"
        case environment
        case failedAt = "failed_at"
        case retryCount = "retry_count"
    }
}