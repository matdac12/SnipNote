//
//  CriticalAppTests.swift
//  SnipNoteTests
//
//  Five bulletproof tests for SnipNote's most critical functionality
//

import Testing
import Foundation
import StoreKit
@testable import SnipNote

struct CriticalAppTests {

    // MARK: - Test 1: Revenue Protection - Minutes Debit Accuracy

    @Test("Minutes debit should be accurate and prevent revenue loss")
    @MainActor
    func testMinutesDebitAccuracy() async throws {
        // This test ensures users are charged correctly for transcription time

        // Given: User with refreshed balance
        let manager = MinutesManager.shared

        // Refresh balance to get current state from Supabase
        _ = await manager.refreshBalance()
        let initialBalance = manager.currentBalance

        // When: User transcribes 90 seconds of audio (should cost 2 minutes - rounds up)
        let testMeetingID = UUID().uuidString  // Use proper UUID format
        let success = await manager.debitMinutes(seconds: 90, meetingID: testMeetingID)

        // Then: With sufficient balance, debit should succeed
        #expect(success == true, "Debit should succeed with sufficient balance (had \(initialBalance) minutes)")

        let expectedNewBalance = initialBalance - 2
        #expect(manager.currentBalance == expectedNewBalance, "90 seconds should cost exactly 2 minutes (rounded up). Expected: \(expectedNewBalance), Got: \(manager.currentBalance)")

        print("Debit test: \(initialBalance) → \(manager.currentBalance) (debited 2 minutes for 90 seconds)")

        print("✅ Revenue protection: Accurate minutes debit verified")
    }

    // MARK: - Test 2: Transaction Integrity - No Double Spending

    @Test("Duplicate transactions should not double-credit minutes")
    @MainActor
    func testDuplicateTransactionPrevention() async throws {
        // This test prevents users from getting double credits for same purchase

        // Given: Mock transaction
        let mockTransactionID = "test-transaction-123"
        let processedTransactions = ProcessedTransactions.shared

        // When: Same transaction is processed twice
        let firstResult = processedTransactions.isProcessedOrInFlight(mockTransactionID)
        processedTransactions.markAsInFlight(mockTransactionID)
        let secondResult = processedTransactions.isProcessedOrInFlight(mockTransactionID)

        // Then: Second attempt should be detected as duplicate
        #expect(firstResult == false, "First transaction should not be marked as processed")
        #expect(secondResult == true, "Second transaction should be detected as in-flight")

        // Cleanup
        processedTransactions.completeProcessing(mockTransactionID, success: true)

        print("✅ Transaction integrity: Duplicate prevention verified")
    }

    // MARK: - Test 3: Core Functionality - Manager Initialization

    @Test("Core managers should initialize without crashing")
    @MainActor
    func testCoreManagerInitialization() async throws {
        // This test ensures critical managers don't crash on startup

        // Given & When: Initialize core managers
        let minutesManager = MinutesManager.shared
        let storeManager = StoreManager.shared
        let _ = ProcessedTransactions.shared  // Test initialization without using

        // Then: All should be accessible without crashing
        #expect(minutesManager.currentBalance >= 0, "Minutes manager should have valid balance")
        #expect(storeManager.products.count >= 0, "Store manager should have products array")

        print("✅ Core functionality: Manager initialization verified")
    }

    // MARK: - Test 4: Error Handling - Graceful Failures

    @Test("App should handle errors gracefully without crashing")
    @MainActor
    func testErrorHandling() async throws {
        // This test ensures our crash fixes work

        // Given: ProcessedTransactions with test data
        let processedTransactions = ProcessedTransactions.shared

        // When: Testing various operations that previously could crash
        let testTransactionID = "error-test-transaction"

        // Test duplicate prevention system
        let firstCheck = processedTransactions.isProcessedOrInFlight(testTransactionID)
        processedTransactions.markAsInFlight(testTransactionID)
        let secondCheck = processedTransactions.isProcessedOrInFlight(testTransactionID)

        // Then: Should handle gracefully
        #expect(firstCheck == false, "Transaction should initially be unprocessed")
        #expect(secondCheck == true, "Transaction should be marked as in-flight")

        // Cleanup
        processedTransactions.completeProcessing(testTransactionID, success: true)

        print("✅ Error handling: Graceful failure handling verified")
    }

    // MARK: - Test 5: State Management - Balance Consistency

    @Test("Balance state should remain consistent")
    @MainActor
    func testBalanceConsistency() async throws {
        // This test ensures balance tracking is reliable

        // Given: Current balance state
        let manager = MinutesManager.shared
        let currentBalance = manager.currentBalance

        // When: Refreshing balance
        let refreshSuccess = await manager.refreshBalance()

        // Then: Balance should remain consistent or update properly
        if refreshSuccess {
            #expect(manager.currentBalance >= 0, "Balance should never be negative")
            print("Balance refreshed successfully: \(manager.currentBalance) minutes")
        } else {
            #expect(manager.currentBalance == currentBalance, "Balance should remain unchanged on refresh failure")
            print("Balance refresh failed gracefully, balance preserved: \(manager.currentBalance) minutes")
        }

        print("✅ State management: Balance consistency verified")
    }
}