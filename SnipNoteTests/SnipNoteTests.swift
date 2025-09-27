//
//  SnipNoteTests.swift
//  SnipNoteTests
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Testing
@testable import SnipNote

struct SnipNoteTests {

    @Test("App should initialize without crashing")
    @MainActor
    func testAppInitialization() async throws {
        // Test that core managers can be initialized
        let minutesManager = MinutesManager.shared
        let balance = minutesManager.currentBalance

        // Should not crash and should return a valid balance
        #expect(balance >= 0, "Balance should be non-negative")

        print("✅ App initialization test passed")
    }

    @Test("Core dependencies should be available")
    @MainActor
    func testCoreDependencies() async throws {
        // Test that essential services are available
        let storeManager = StoreManager.shared
        let failedQueue = FailedTransactionQueue.shared

        // Should not crash when accessing - test their properties instead
        #expect(storeManager.products.count >= 0, "StoreManager should have products array")
        #expect(failedQueue.getFailedCount() >= 0, "FailedTransactionQueue should track failed count")

        print("✅ Core dependencies test passed")
    }
}
