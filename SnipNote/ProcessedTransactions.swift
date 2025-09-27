//
//  ProcessedTransactions.swift
//  SnipNote
//
//  Created for duplicate transaction prevention.
//

import Foundation

@MainActor
class ProcessedTransactions: ObservableObject {
    static let shared = ProcessedTransactions()

    private let storageKey = "processedTransactionIDs"
    private let timestampKey = "processedTransactionTimestamps"
    private let maxAge: TimeInterval = 90 * 24 * 60 * 60 // 90 days

    @Published private(set) var processedIDs: Set<String> = []
    private var transactionTimestamps: [String: Date] = [:]

    // CRITICAL: Track transactions currently being processed to prevent race conditions
    private var inFlightTransactions: Set<String> = []

    private init() {
        loadProcessedData()
        cleanupOldTransactions()
    }

    /// Check if a transaction ID has already been processed
    func isProcessed(_ transactionID: String) -> Bool {
        let result = processedIDs.contains(transactionID)
        if result {
            print("🔒 [ProcessedTransactions] Duplicate detected: \(transactionID)")
        }
        return result
    }

    /// Check if transaction is already processed OR currently being processed (prevents race conditions)
    func isProcessedOrInFlight(_ transactionID: String) -> Bool {
        if processedIDs.contains(transactionID) {
            print("🔒 [ProcessedTransactions] Already processed: \(transactionID)")
            return true
        }
        if inFlightTransactions.contains(transactionID) {
            print("⏳ [ProcessedTransactions] Currently in-flight: \(transactionID)")
            return true
        }
        return false
    }

    /// Check if transaction is currently being processed
    func isInFlight(_ transactionID: String) -> Bool {
        if inFlightTransactions.contains(transactionID) {
            print("⏳ [ProcessedTransactions] Currently in-flight: \(transactionID)")
            return true
        }
        return false
    }

    /// Mark a transaction as in-flight (being processed) - MUST call before async work
    func markAsInFlight(_ transactionID: String) {
        inFlightTransactions.insert(transactionID)
        print("🚁 [ProcessedTransactions] Marked as in-flight: \(transactionID) (In-flight: \(inFlightTransactions.count))")
    }

    /// Complete transaction processing - call this after async work finishes
    func completeProcessing(_ transactionID: String, success: Bool) {
        inFlightTransactions.remove(transactionID)

        if success {
            processedIDs.insert(transactionID)
            transactionTimestamps[transactionID] = Date()
            saveProcessedData()
            print("✅ [ProcessedTransactions] Completed processing: \(transactionID) (Success, Total: \(processedIDs.count))")
        } else {
            print("❌ [ProcessedTransactions] Failed processing: \(transactionID) (Will retry)")
        }
    }

    /// Mark a transaction as successfully processed (legacy method - use completeProcessing instead)
    @available(*, deprecated, message: "Use completeProcessing instead")
    func markAsProcessed(_ transactionID: String) {
        processedIDs.insert(transactionID)
        transactionTimestamps[transactionID] = Date()
        saveProcessedData()
        print("✅ [ProcessedTransactions] Marked as processed: \(transactionID) (Total: \(processedIDs.count))")
    }

    /// Get count of processed transactions for debugging
    func getProcessedCount() -> Int {
        return processedIDs.count
    }

    /// Get all processed transaction IDs for debugging
    func getAllProcessedIDs() -> [String] {
        return Array(processedIDs).sorted()
    }

    // MARK: - Private Methods

    private func loadProcessedData() {
        // Load processed IDs
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            processedIDs = ids
            print("📋 [ProcessedTransactions] Loaded \(processedIDs.count) processed transaction IDs")
        }

        // Load timestamps
        if let data = UserDefaults.standard.data(forKey: timestampKey),
           let timestamps = try? JSONDecoder().decode([String: Date].self, from: data) {
            transactionTimestamps = timestamps
        }
    }

    private func saveProcessedData() {
        // Save processed IDs
        if let data = try? JSONEncoder().encode(processedIDs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }

        // Save timestamps
        if let data = try? JSONEncoder().encode(transactionTimestamps) {
            UserDefaults.standard.set(data, forKey: timestampKey)
        }
    }

    /// Clean up old transactions to prevent UserDefaults from growing indefinitely
    private func cleanupOldTransactions() {
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        let oldTransactions = transactionTimestamps.compactMap { (id, timestamp) -> String? in
            return timestamp < cutoffDate ? id : nil
        }

        if !oldTransactions.isEmpty {
            for transactionID in oldTransactions {
                processedIDs.remove(transactionID)
                transactionTimestamps.removeValue(forKey: transactionID)
            }
            saveProcessedData()
            print("🧹 [ProcessedTransactions] Cleaned up \(oldTransactions.count) old transactions")
        }
    }

    /// Force cleanup - useful for testing or maintenance
    func performCleanup() {
        cleanupOldTransactions()
    }

    /// Clear all processed transactions - USE WITH EXTREME CAUTION
    /// This should only be used for testing or if you want to reset the system
    func clearAll() {
        processedIDs.removeAll()
        transactionTimestamps.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
        print("🗑️ [ProcessedTransactions] CLEARED ALL processed transactions")
    }
}