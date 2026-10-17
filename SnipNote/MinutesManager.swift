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
    /// The launch refresh and Trial grant currently running, so concurrent callers share one run.
    private var launchTask: Task<Bool, Never>?

    private init() {}

    // MARK: - Balance Management

    /// Forget the previous account's balance so a Guest, or the next account, never sees it.
    func resetForSignOut() {
        scheduledDebitRetryTask?.cancel()
        scheduledDebitRetryTask = nil
        launchTask = nil
        currentBalance = 0
#if DEBUG
        if ScreenshotSeed.isActive { currentBalance = ScreenshotSeed.balanceMinutes }
#endif
        lastError = nil
        UserDefaults.standard.removeObject(forKey: "lastBalanceRefreshTime")
    }

    /// Refresh the current balance from Supabase
    @discardableResult
    func refreshBalance() async -> Bool {
#if DEBUG
        if ScreenshotSeed.isActive {
            currentBalance = ScreenshotSeed.balanceMinutes
            return true
        }
#endif
        guard let userID = SupabaseManager.shared.client.auth.currentUser?.id else {
            print("ℹ️ [MinutesManager] Skipping balance refresh - no authenticated session")
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await SupabaseManager.shared.client
                .rpc("get_user_minutes_balance")
                .execute()

            // The user may have signed out while the request was in flight
            guard SupabaseManager.shared.client.auth.currentUser?.id == userID else { return false }

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
        guard let userID = SupabaseManager.shared.client.auth.currentUser?.id else {
            print("ℹ️ [MinutesManager] Skipping free tier grant - no authenticated session")
            return false
        }

        do {
            let response = try await SupabaseManager.shared.client
                .rpc("grant_free_tier_minutes")
                .execute()

            // The grant itself is recorded on the server; only skip showing it if the user changed
            guard SupabaseManager.shared.client.auth.currentUser?.id == userID else { return true }

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

    /// Credit minutes for a StoreKit purchase. The server verifies Apple's signature on the signed
    /// transaction and decides the amount from the product; the client never sends an amount.
    func creditPurchase(signedTransaction: String, transactionID: String) async -> Bool {
        // CRITICAL: Check local duplicate - treat as benign success (prevents user lock-out)
        if ProcessedTransactions.shared.isProcessed(transactionID) {
            print("✅ [MinutesManager] Transaction already processed locally - treating as success: \(transactionID)")
            await refreshBalance()  // Get latest balance from server
            return true  // Benign duplicate - prevents user lock-out after app reinstall
        }

        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let response: CreditPurchaseResponse = try await SupabaseManager.shared.client.functions.invoke(
                "credit-storekit-transaction",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: CreditPurchaseRequest(signedTransaction: signedTransaction)
                )
            )
            // A transaction the server already credited to this Account answers 200 with the balance
            currentBalance = max(0, response.balance)
            print("✅ [MinutesManager] Credited \(response.credited) minutes for \(transactionID). New balance: \(currentBalance)")
            return true
        } catch {
            print("❌ [MinutesManager] Failed to credit purchase \(transactionID): \(error)")
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
            return .failed(message: "Unable to calculate minutes for this transcription.")
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
                errorMessage: errorMessage,
                userID: SupabaseManager.shared.client.auth.currentUser?.id.uuidString
            )
            await updateMeetingDebitState(meetingID: meetingID, pending: true, message: errorMessage)
            schedulePendingDebitRetry()
            return .queuedForRetry(message: errorMessage)
        }

        return .failed(message: errorMessage)
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
}

// MARK: - Edge Function Payloads

struct CreditPurchaseRequest: Encodable {
    let signedTransaction: String
}

struct CreditPurchaseResponse: Decodable {
    let balance: Int
    let credited: Int
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
    /// Returns false when the balance refresh or the Trial grant failed, so callers can retry.
    /// Several launch paths call this at once, so concurrent callers share one run.
    @discardableResult
    func handleAppLaunch() async -> Bool {
        if let launchTask {
            return await launchTask.value
        }

        let task = Task { @MainActor in await self.performAppLaunch() }
        launchTask = task
        let result = await task.value
        launchTask = nil
        return result
    }

    private func performAppLaunch() async -> Bool {
        var succeeded = true
        guard let userID = SupabaseManager.shared.client.auth.currentUser?.id else {
            print("ℹ️ [MinutesManager] Skipping launch balance refresh - user not authenticated")
            return true
        }

        // Add cooldown to prevent rapid refreshes on multiple view appears
        let lastRefreshKey = "lastBalanceRefreshTime"
        let cooldownSeconds: TimeInterval = 300 // 5 minutes

        if let lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date,
           Date().timeIntervalSince(lastRefresh) < cooldownSeconds {
            let elapsed = Date().timeIntervalSince(lastRefresh)
            print("⏱️ [MinutesManager] Skipping refresh, last refresh was \(Int(elapsed))s ago (cooldown: \(Int(cooldownSeconds))s)")
            return true
        }

        print("🔄 [MinutesManager] Refreshing balance on app launch")
        let refreshSucceeded = await refreshBalance()
        if refreshSucceeded {
            UserDefaults.standard.set(Date(), forKey: lastRefreshKey)
        } else {
            succeeded = false
        }

        // Only grant the Trial grant if this account never got it. The flag is per user because the
        // server grants once per account, and a new account on a shared device must not be blocked
        // by the previous one. The legacy global key is still written for install detection.
        let freeGrantedKey = "freeTierGranted.\(userID.uuidString)"

        // Carry the old device-wide flag over to the account that was signed in when this version
        // first ran, once, so an existing user who spent their Trial grant is not granted again.
        let legacyMigratedKey = "freeTierGranted.legacyMigrated"
        if !UserDefaults.standard.bool(forKey: legacyMigratedKey) {
            if UserDefaults.standard.bool(forKey: "freeTierGranted") {
                UserDefaults.standard.set(true, forKey: freeGrantedKey)
            }
            UserDefaults.standard.set(true, forKey: legacyMigratedKey)
        }

        if refreshSucceeded,
           currentBalance == 0,
           !UserDefaults.standard.bool(forKey: freeGrantedKey) {
            print("🎁 [MinutesManager] Attempting to grant free tier minutes")
            let granted = await grantFreeTierMinutes()
            if granted {
                UserDefaults.standard.set(true, forKey: freeGrantedKey)
                UserDefaults.standard.set(true, forKey: "freeTierGranted")
                AnalyticsService.track(.cloudTrialClaimed)
                print("✅ [MinutesManager] Free tier granted and marked as complete")
            } else {
                print("⚠️ [MinutesManager] Free tier grant failed (may already be granted)")
                succeeded = false
            }
        } else if UserDefaults.standard.bool(forKey: freeGrantedKey) {
            print("✅ [MinutesManager] Free tier already granted for this user")
        }

        await retryPendingDebits()
        return succeeded
    }
}

// MARK: - Debit Retry Helpers

extension MinutesManager {
    func retryPendingDebits() async {
        guard let currentUserID = SupabaseManager.shared.client.auth.currentUser?.id.uuidString else { return }

        // Never charge one account for another account's meeting
        let pendingDebits = FailedMinutesDebitQueue.shared.getPendingDebits().filter {
            $0.userID == nil || $0.userID == currentUserID
        }
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

        let stillPending = FailedMinutesDebitQueue.shared.getPendingDebits().contains {
            $0.userID == nil || $0.userID == currentUserID
        }
        if stillPending {
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
            return "Transcription completed. We’re retrying the minutes sync in the background."
        }

        if shouldRetryDebit(error) {
            return "Transcription completed. We’re retrying the minutes sync in the background."
        }

        return "Transcription completed, but your minutes balance could not be updated yet."
    }

    private func updateMeetingDebitState(meetingID: String, pending: Bool, message: String?) async {
        guard let meetingUUID = UUID(uuidString: meetingID) else { return }

        do {
            let schema = Schema([
                Meeting.self,
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
