//
//  MinutesManager.swift
//  SnipNote
//
//  Created for minutes-based pricing system.
//

import Foundation
import Supabase
import StoreKit
import SwiftData

@MainActor
class MinutesManager: ObservableObject {
    enum DebitMinutesResult: Equatable {
        case debited
        case queuedForRetry(message: String)
        case failed(message: String)

        var didDebitImmediately: Bool {
            if case .debited = self {
                return true
            }
            return false
        }

        var userMessage: String? {
            switch self {
            case .debited:
                return nil
            case .queuedForRetry(let message), .failed(let message):
                return message
            }
        }
    }

    // MARK: - Published Properties
    @Published var currentBalance: Int = 0
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    // MARK: - Singleton
    static let shared = MinutesManager()

    private var scheduledDebitRetryTask: Task<Void, Never>?

    private init() {}

    // MARK: - Balance Management

    /// Refresh the current balance from Supabase
    @discardableResult
    func refreshBalance() async -> Bool {
        guard SupabaseManager.shared.client.auth.currentUser != nil else {
            print("ℹ️ [MinutesManager] Skipping balance refresh - no authenticated session")
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await SupabaseManager.shared.client
                .rpc("get_user_minutes_balance")
                .execute()

            let data = response.data
            if let balanceValue = try? JSONDecoder().decode(Int.self, from: data) {
                currentBalance = max(0, balanceValue)
                lastError = nil
                return true
            } else {
                print("❌ [MinutesManager] Failed to decode balance response")
                lastError = "Failed to decode balance"
                return false
            }
        } catch {
            print("❌ [MinutesManager] Failed to refresh balance: \(error)")
            lastError = error.localizedDescription
            return false
        }
    }

    /// Grant free tier minutes (30 minutes, one-time per user)
    func grantFreeTierMinutes() async -> Bool {
        guard SupabaseManager.shared.client.auth.currentUser != nil else {
            print("ℹ️ [MinutesManager] Skipping free tier grant - no authenticated session")
            return false
        }

        do {
            let response = try await SupabaseManager.shared.client
                .rpc("grant_free_tier_minutes")
                .execute()

            let data = response.data
            if let newBalance = try? JSONDecoder().decode(Int.self, from: data) {
                currentBalance = max(0, newBalance)
                print("✅ [MinutesManager] Granted free tier minutes. New balance: \(currentBalance)")
                return true
            } else {
                print("❌ [MinutesManager] Failed to decode free tier response")
                return false
            }
        } catch {
            print("❌ [MinutesManager] Failed to grant free tier minutes: \(error)")
            lastError = error.localizedDescription
            return false
        }
    }

    /// Credit minutes from purchases or subscriptions
    func creditMinutes(
        amount: Int,
        reason: String,
        appleTransactionID: String? = nil,
        metadata: [String: Any]? = nil
    ) async -> Bool {
        guard amount > 0 else {
            print("❌ [MinutesManager] Invalid credit amount: \(amount)")
            return false
        }

        // CRITICAL: Check local duplicate - treat as benign success (prevents user lock-out)
        if let transactionID = appleTransactionID,
           ProcessedTransactions.shared.isProcessed(transactionID) {
            print("✅ [MinutesManager] Transaction already processed locally - treating as success: \(transactionID)")
            await refreshBalance()  // Get latest balance from server
            return true  // Benign duplicate - prevents user lock-out after app reinstall
        }

        do {
            let params = CreditMinutesParams(
                p_amount: amount,
                p_reason: reason,
                p_apple_transaction_id: appleTransactionID,
                p_metadata: metadata
            )

            let response = try await SupabaseManager.shared.client
                .rpc("credit_minutes", params: params)
                .execute()

            let data = response.data
            if let newBalance = try? JSONDecoder().decode(Int.self, from: data) {
                currentBalance = max(0, newBalance)
                print("✅ [MinutesManager] Credited \(amount) minutes. Reason: \(reason). New balance: \(currentBalance)")
                return true
            } else {
                print("❌ [MinutesManager] Failed to decode credit response")
                return false
            }
        } catch {
            // CRITICAL: Handle duplicate errors as success to prevent user lock-out
            let errorString = String(describing: error).lowercased()

            if let transactionID = appleTransactionID {
                // Check for duplicate-related error messages from Supabase
                if errorString.contains("duplicate") ||
                   errorString.contains("already") ||
                   errorString.contains("conflict") ||
                   errorString.contains("unique") ||
                   errorString.contains("23505") ||  // PostgreSQL unique violation code
                   errorString.contains("constraint") {

                    print("✅ [MinutesManager] Supabase duplicate detected - treating as success: \(transactionID)")
                    print("🔍 [MinutesManager] Duplicate error details: \(error)")

                    // Refresh balance to ensure we have correct state from server
                    await refreshBalance()

                    return true  // Transaction was already processed on server - this is fine
                }
            }

            print("❌ [MinutesManager] Failed to credit minutes: \(error)")
            lastError = error.localizedDescription
            return false
        }
    }

    /// Debit minutes for usage
    func debitMinutes(seconds: Int, meetingID: String? = nil) async -> DebitMinutesResult {
        // User-friendly rounding: 119 seconds = 1 minute, 120 seconds = 2 minutes
        let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))

        guard minutes > 0 else {
            print("❌ [MinutesManager] Invalid debit amount: \(minutes)")
            return .failed(message: "Unable to calculate minutes for this meeting.")
        }

        let immediateRetryCount = 3
        var lastDebitError: Error?

        for attempt in 1...immediateRetryCount {
            do {
                try await performDebitRequest(minutes: minutes, seconds: seconds, meetingID: meetingID)
                if let meetingID {
                    await updateMeetingDebitState(meetingID: meetingID, pending: false, message: nil)
                }
                return .debited
            } catch {
                lastDebitError = error

                if isDuplicateDebitError(error) {
                    print("✅ [MinutesManager] Debit already recorded for meeting \(meetingID ?? "n/a") - treating as success")
                    await refreshBalance()
                    if let meetingID {
                        await updateMeetingDebitState(meetingID: meetingID, pending: false, message: nil)
                    }
                    return .debited
                }

                let isRetryable = shouldRetryDebit(error)
                print("❌ [MinutesManager] Failed to debit minutes (attempt \(attempt)/\(immediateRetryCount)): \(error)")

                if isRetryable && attempt < immediateRetryCount {
                    let delay = retryDelay(for: attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                break
            }
        }

        let errorMessage = userFriendlyDebitFailureMessage(for: lastDebitError)
        lastError = errorMessage

        if let meetingID {
            FailedMinutesDebitQueue.shared.addDebit(
                meetingID: meetingID,
                seconds: seconds,
                errorMessage: errorMessage
            )
            await updateMeetingDebitState(meetingID: meetingID, pending: true, message: errorMessage)
            schedulePendingDebitRetry()
            return .queuedForRetry(message: errorMessage)
        }

        return .failed(message: errorMessage)
    }

    // MARK: - Subscription Helpers

    /// Credit minutes based on subscription product
    func creditForSubscription(_ product: Product, transactionID: String) async -> Bool {
        let (amount, reason) = getMinutesForProduct(product.id)
        guard amount > 0 else {
            print("❌ [MinutesManager] Unknown product: \(product.id)")
            return false
        }

        let metadata = [
            "product_id": product.id,
            "product_name": product.displayName,
            "price": product.displayPrice
        ]

        return await creditMinutes(
            amount: amount,
            reason: reason,
            appleTransactionID: transactionID,
            metadata: metadata
        )
    }

    /// Credit minutes based on consumable pack product
    func creditForPack(_ product: Product, transactionID: String) async -> Bool {
        let (amount, reason) = getMinutesForProduct(product.id)
        guard amount > 0 else {
            print("❌ [MinutesManager] Unknown pack: \(product.id)")
            return false
        }

        let metadata = [
            "product_id": product.id,
            "product_name": product.displayName,
            "price": product.displayPrice,
            "type": "consumable_pack"
        ]

        return await creditMinutes(
            amount: amount,
            reason: reason,
            appleTransactionID: transactionID,
            metadata: metadata
        )
    }

    // MARK: - Validation Helpers

    /// Check if user has sufficient minutes for a recording
    func hasMinutesFor(seconds: Int) -> Bool {
        let requiredMinutes = max(1, Int(ceil(Double(seconds) / 60.0)))
        return currentBalance >= requiredMinutes
    }

    /// Get formatted time remaining
    var formattedBalance: String {
        if currentBalance <= 0 {
            return "0 minutes"
        } else if currentBalance == 1 {
            return "1 minute"
        } else {
            return "\(currentBalance) minutes"
        }
    }

    /// Check if user is in free tier (has 30 or fewer minutes and no subscription)
    func isFreeTierUser() async -> Bool {
        // This could be enhanced to check subscription status
        return currentBalance <= 30
    }

    // MARK: - Private Helpers

    private func getMinutesForProduct(_ productID: String) -> (amount: Int, reason: String) {
        switch productID {
        case "snipnote_pro_weekly03":
            return (200, "weekly_allowance")
        case "snipnote_pro_monthly03":
            return (800, "monthly_allowance")
        case "snipnote_pro_annual03":
            return (9600, "annual_allowance")
        case "com.snipnote.packs.minutes100":
            return (100, "pack_100")
        case "com.snipnote.packs.minutes500":
            return (500, "pack_500")
        case "com.snipnote.packs.minutes1000":
            return (1000, "pack_1000")
        default:
            return (0, "unknown")
        }
    }
}

// MARK: - RPC Parameter Structs

struct CreditMinutesParams: Encodable {
    let p_amount: Int
    let p_reason: String
    let p_apple_transaction_id: String?
    let p_metadata: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case p_amount
        case p_reason
        case p_apple_transaction_id
        case p_metadata
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_amount, forKey: .p_amount)
        try container.encode(p_reason, forKey: .p_reason)
        try container.encodeIfPresent(p_apple_transaction_id, forKey: .p_apple_transaction_id)

        if let metadata = p_metadata {
            let jsonData = try JSONSerialization.data(withJSONObject: metadata)
            let jsonString = String(data: jsonData, encoding: .utf8)
            try container.encodeIfPresent(jsonString, forKey: .p_metadata)
        }
    }
}

struct DebitMinutesParams: Encodable {
    let p_amount: Int
    let p_meeting_id: String?
}

// MARK: - Extensions

extension MinutesManager {
    /// Initialize user's free tier minutes on first app launch
    func initializeUserIfNeeded() async {
        if currentBalance == 0 {
            _ = await grantFreeTierMinutes()
        }
    }

    /// Handle app launch - refresh balance and grant free tier if needed
    func handleAppLaunch() async {
        guard SupabaseManager.shared.client.auth.currentUser != nil else {
            print("ℹ️ [MinutesManager] Skipping launch balance refresh - user not authenticated")
            return
        }

        // Add cooldown to prevent rapid refreshes on multiple view appears
        let lastRefreshKey = "lastBalanceRefreshTime"
        let cooldownSeconds: TimeInterval = 300 // 5 minutes

        if let lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date,
           Date().timeIntervalSince(lastRefresh) < cooldownSeconds {
            let elapsed = Date().timeIntervalSince(lastRefresh)
            print("⏱️ [MinutesManager] Skipping refresh, last refresh was \(Int(elapsed))s ago (cooldown: \(Int(cooldownSeconds))s)")
            return
        }

        print("🔄 [MinutesManager] Refreshing balance on app launch")
        let refreshSucceeded = await refreshBalance()
        if refreshSucceeded {
            UserDefaults.standard.set(Date(), forKey: lastRefreshKey)
        }

        // Only grant free tier if never granted before (don't rely on balance == 0)
        let freeGrantedKey = "freeTierGranted"
        if refreshSucceeded,
           currentBalance == 0,
           !UserDefaults.standard.bool(forKey: freeGrantedKey) {
            print("🎁 [MinutesManager] Attempting to grant free tier minutes")
            let granted = await grantFreeTierMinutes()
            if granted {
                UserDefaults.standard.set(true, forKey: freeGrantedKey)
                print("✅ [MinutesManager] Free tier granted and marked as complete")
            } else {
                print("⚠️ [MinutesManager] Free tier grant failed (may already be granted)")
            }
        } else if UserDefaults.standard.bool(forKey: freeGrantedKey) {
            print("✅ [MinutesManager] Free tier already granted for this user")
        }

        await retryPendingDebits()
    }
}

// MARK: - Debit Retry Helpers

extension MinutesManager {
    func retryPendingDebits() async {
        guard SupabaseManager.shared.client.auth.currentUser != nil else { return }

        let pendingDebits = FailedMinutesDebitQueue.shared.getPendingDebits()
        guard !pendingDebits.isEmpty else { return }

        print("🔄 [MinutesManager] Retrying \(pendingDebits.count) pending minute debit(s)")

        for pendingDebit in pendingDebits {
            let minutes = max(1, Int(ceil(Double(pendingDebit.seconds) / 60.0)))

            do {
                try await performDebitRequest(
                    minutes: minutes,
                    seconds: pendingDebit.seconds,
                    meetingID: pendingDebit.meetingID
                )

                FailedMinutesDebitQueue.shared.removeDebit(meetingID: pendingDebit.meetingID)
                await updateMeetingDebitState(meetingID: pendingDebit.meetingID, pending: false, message: nil)
            } catch {
                if isDuplicateDebitError(error) {
                    await refreshBalance()
                    FailedMinutesDebitQueue.shared.removeDebit(meetingID: pendingDebit.meetingID)
                    await updateMeetingDebitState(meetingID: pendingDebit.meetingID, pending: false, message: nil)
                    continue
                }

                let errorMessage = userFriendlyDebitFailureMessage(for: error)
                lastError = errorMessage
                FailedMinutesDebitQueue.shared.markRetryFailure(
                    meetingID: pendingDebit.meetingID,
                    errorMessage: errorMessage
                )
                await updateMeetingDebitState(meetingID: pendingDebit.meetingID, pending: true, message: errorMessage)
                print("⚠️ [MinutesManager] Pending debit retry failed for meeting \(pendingDebit.meetingID): \(error)")
            }
        }

        if !FailedMinutesDebitQueue.shared.getPendingDebits().isEmpty {
            schedulePendingDebitRetry()
        }
    }

    private func schedulePendingDebitRetry() {
        guard scheduledDebitRetryTask == nil else { return }

        scheduledDebitRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self else { return }
            self.scheduledDebitRetryTask = nil
            await self.retryPendingDebits()
        }
    }

    private func performDebitRequest(minutes: Int, seconds: Int, meetingID: String?) async throws {
        let params = DebitMinutesParams(
            p_amount: minutes,
            p_meeting_id: meetingID
        )

        let response = try await SupabaseManager.shared.client
            .rpc("debit_minutes", params: params)
            .execute()

        let data = response.data
        guard let newBalance = try? JSONDecoder().decode(Int.self, from: data) else {
            throw NSError(
                domain: "MinutesManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode debit response"]
            )
        }

        currentBalance = newBalance
        lastError = nil
        print("✅ [MinutesManager] Debited \(minutes) minutes (\(seconds)s). New balance: \(currentBalance)")
    }

    private func shouldRetryDebit(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost,
                 .notConnectedToInternet,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        let description = error.localizedDescription.lowercased()
        return description.contains("network")
            || description.contains("timeout")
            || description.contains("connection")
            || description.contains("unreachable")
    }

    private func retryDelay(for attempt: Int) -> Double {
        min(pow(2.0, Double(attempt - 1)), 8.0)
    }

    private func isDuplicateDebitError(_ error: Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("duplicate")
            || description.contains("already")
            || description.contains("conflict")
            || description.contains("23505")
            || description.contains("constraint")
    }

    private func userFriendlyDebitFailureMessage(for error: Error?) -> String {
        guard let error else {
            return "Meeting completed. We’re retrying the minutes sync in the background."
        }

        if shouldRetryDebit(error) {
            return "Meeting completed. We’re retrying the minutes sync in the background."
        }

        return "Meeting completed, but your minutes balance could not be updated yet."
    }

    private func updateMeetingDebitState(meetingID: String, pending: Bool, message: String?) async {
        guard let meetingUUID = UUID(uuidString: meetingID) else { return }

        do {
            let schema = Schema([
                Meeting.self,
                Action.self,
                EveMessage.self,
                ChatConversation.self,
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingUUID })

            guard let meeting = try context.fetch(descriptor).first else { return }

            if pending {
                meeting.markMinutesDebitPending(message: message)
            } else {
                meeting.markMinutesDebitSettled()
            }

            try context.save()
        } catch {
            print("⚠️ [MinutesManager] Failed to update debit state for meeting \(meetingID): \(error)")
        }
    }
}
