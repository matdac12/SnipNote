//
//  SubscriptionModels.swift
//  SnipNote
//
//  Created by Claude on 27/08/25.
//

import Foundation

// MARK: - Subscription Status Model
struct SubscriptionStatus: Codable {
    let isSubscribed: Bool
    let entitlement: String?
    let productIdentifier: String?
    let expiresAt: Date?
    
    static let empty = SubscriptionStatus(
        isSubscribed: false,
        entitlement: nil,
        productIdentifier: nil,
        expiresAt: nil,
    )
}


// MARK: - Supabase Models
struct UserSubscription: Codable {
    let id: UUID?
    let userId: UUID
    let revenuecatCustomerId: String?
    let entitlementIdentifier: String?
    let productIdentifier: String?
    let isActive: Bool
    let expiresAt: Date?
    let purchaseDate: Date?
    let originalPurchaseDate: Date?
    let store: String?
    let isSandbox: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case revenuecatCustomerId = "revenuecat_customer_id"
        case entitlementIdentifier = "entitlement_identifier"
        case productIdentifier = "product_identifier"
        case isActive = "is_active"
        case expiresAt = "expires_at"
        case purchaseDate = "purchase_date"
        case originalPurchaseDate = "original_purchase_date"
        case store
        case isSandbox = "is_sandbox"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Subscription Tier
enum SubscriptionTier: String, CaseIterable {
    case weekly = "snipnote_pro_weekly03"
    case monthly = "snipnote_pro_monthly03"
    case annual = "snipnote_pro_annual03"
    
    var displayName: String {
        switch self {
        case .weekly:
            return "SnipNote Pro Weekly"
        case .monthly:
            return "SnipNote Pro Monthly"
        case .annual:
            return "SnipNote Pro Annual"
        }
    }
    
    // Prices are dynamically loaded from App Store via package.localizedPriceString
    // No hardcoded prices needed
    
    var savingsText: String? {
        switch self {
        case .weekly:
            return nil
        case .monthly:
            return "Most Popular"
        case .annual:
            return "Save 33%"
        }
    }
    
    var isBestValue: Bool {
        return self == .annual
    }
}

// MARK: - Free Tier Limits
struct FreeTierLimits {
    static let maxItemsTotal = 2 // Lifetime limit for meetings on free tier
    static let maxTranscriptionSecondsPerRecording = 60
    static let aiFeatures = false // No AI for free users

    static func allows(duration: TimeInterval, subscribed: Bool) -> Bool {
        guard subscribed else {
            return duration <= TimeInterval(maxTranscriptionSecondsPerRecording)
        }
        return true
    }

    static var durationDescription: String {
        "\(maxTranscriptionSecondsPerRecording) seconds"
    }
}
