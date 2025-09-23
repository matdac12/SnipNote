//
//  MinutesManager.swift
//  SnipNote
//
//  Created for minutes-based pricing system.
//

import Foundation
import Supabase
import StoreKit

@MainActor
class MinutesManager: ObservableObject {
    // MARK: - Published Properties
    @Published var currentBalance: Int = 0
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    // MARK: - Singleton
    static let shared = MinutesManager()

    private init() {}

    // MARK: - Balance Management

    /// Refresh the current balance from Supabase
    func refreshBalance() async {
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
            } else {
                print("❌ [MinutesManager] Failed to decode balance response")
                lastError = "Failed to decode balance"
            }
        } catch {
            print("❌ [MinutesManager] Failed to refresh balance: \(error)")
            lastError = error.localizedDescription
        }
    }

    /// Grant free tier minutes (30 minutes, one-time per user)
    func grantFreeTierMinutes() async -> Bool {
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
            print("❌ [MinutesManager] Failed to credit minutes: \(error)")
            lastError = error.localizedDescription
            return false
        }
    }

    /// Debit minutes for usage
    func debitMinutes(seconds: Int, meetingID: String? = nil) async -> Bool {
        // User-friendly rounding: 119 seconds = 1 minute, 120 seconds = 2 minutes
        let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))

        guard minutes > 0 else {
            print("❌ [MinutesManager] Invalid debit amount: \(minutes)")
            return false
        }

        do {
            let params = DebitMinutesParams(
                p_amount: minutes,
                p_meeting_id: meetingID
            )

            let response = try await SupabaseManager.shared.client
                .rpc("debit_minutes", params: params)
                .execute()

            let data = response.data
            if let newBalance = try? JSONDecoder().decode(Int.self, from: data) {
                currentBalance = newBalance // Allow negative balance temporarily
                print("✅ [MinutesManager] Debited \(minutes) minutes (\(seconds)s). New balance: \(currentBalance)")
                return true
            } else {
                print("❌ [MinutesManager] Failed to decode debit response")
                return false
            }
        } catch {
            print("❌ [MinutesManager] Failed to debit minutes: \(error)")
            lastError = error.localizedDescription
            return false
        }
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
        await refreshBalance()
        if currentBalance == 0 {
            _ = await grantFreeTierMinutes()
        }
    }
}