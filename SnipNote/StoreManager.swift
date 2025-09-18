//
//  StoreManager.swift
//  SnipNote
//
//  Native StoreKit 2 implementation to replace RevenueCat for
//  product loading, purchasing, and subscription status.
//

import Foundation
import StoreKit
#if os(iOS)
import UIKit
#endif
import os

@MainActor
class StoreManager: ObservableObject {
    // MARK: - Published
    @Published var products: [Product] = []
    @Published var isLoadingProducts = false
    @Published var loadingError: String?
    @Published var hasActiveSubscription = false
    @Published var purchasedSubscriptions: Set<String> = []
    @Published var lastProductsFetchAt: Date?
    @Published var diagnosticsText: String = ""

    // MARK: - Properties
    static let shared = StoreManager()

    private let productIds: [String] = [
        "snipnote_pro_weekly03",
        "snipnote_pro_monthly03",
        "snipnote_pro_annual03"
    ]

    private var updatesTask: Task<Void, Never>?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SnipNote", category: "StoreKit")

    private init() {
        // Listen for transaction updates
        updatesTask = listenForTransactions()
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Loading
    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        loadingError = nil

        do {
            print("🛒 [StoreKit] Loading products… IDs=\(productIds)")
            log.debug("Loading products… ids=\(self.productIds, privacy: .public)")

            // Sanity: confirm we are NOT using a bundled StoreKit config
            let hasBundledStoreKit = Bundle.main.url(forResource: "Products", withExtension: "storekit") != nil
            print("🛒 [StoreKit] Bundled .storekit file present in app bundle: \(hasBundledStoreKit)")
            log.debug("Bundled .storekit present: \(hasBundledStoreKit, privacy: .public)")
            #if os(iOS)
            if let sf = await Storefront.current {
                print("🛒 [StoreKit] Storefront: id=\(sf.id), country=\(sf.countryCode)")
                log.debug("Storefront id=\(sf.id, privacy: .public) country=\(sf.countryCode, privacy: .public)")
            } else {
                print("🛒 [StoreKit] Storefront: unavailable")
                log.debug("Storefront unavailable")
            }
            print("🛒 [StoreKit] canMakePayments=\(AppStore.canMakePayments)")
            log.debug("canMakePayments=\(AppStore.canMakePayments, privacy: .public)")
            #endif
            print("🛒 [StoreKit] Locale=\(Locale.current.identifier), currency=\(Locale.current.currency?.identifier ?? "n/a")")
            print("🛒 [StoreKit] BundleID=\(Bundle.main.bundleIdentifier ?? "nil") Version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
            let result = try await AppTransaction.shared
            switch result {
            case .verified(let tx):
                print("🛒 [StoreKit] AppTransaction: verified, purchaseDate=\(tx.originalPurchaseDate as Date? ?? Date.distantPast), environment=\(tx.environment.rawValue)")
                log.debug("AppTransaction verified env=\(tx.environment.rawValue, privacy: .public)")
            case .unverified(_, let error):
                print("🛒 [StoreKit] AppTransaction: unverified error=\(String(describing: error))")
                log.error("AppTransaction unverified error=\(String(describing: error), privacy: .public)")
            }

            let loaded = try await Product.products(for: productIds)
            // Keep only auto-renewable subscriptions we expect
            products = loaded.filter { $0.type == .autoRenewable }
            // Stable sort: weekly < monthly < annual by price or by known IDs
            products.sort { lhs, rhs in
                // Prefer known order by id; fallback to price
                let order: [String: Int] = [
                    "snipnote_pro_weekly03": 0,
                    "snipnote_pro_monthly03": 1,
                    "snipnote_pro_annual03": 2
                ]
                let l = order[lhs.id] ?? 99
                let r = order[rhs.id] ?? 99
                if l != r { return l < r }
                return lhs.price < rhs.price
            }

            if !products.isEmpty {
                print("🛒 [StoreKit] Loaded products (\(products.count)):")
                for p in products {
                    let period: String
                    if let sp = p.subscription?.subscriptionPeriod {
                        switch sp.unit {
                        case .day: period = "P\(sp.value)D"
                        case .week: period = "P\(sp.value)W"
                        case .month: period = "P\(sp.value)M"
                        case .year: period = "P\(sp.value)Y"
                        @unknown default: period = "P?"
                        }
                    } else { period = "n/a" }
                    print("   - id=\(p.id), name=\(p.displayName), price=\(p.displayPrice), period=\(period)")
                }
            }

            if products.isEmpty {
                print("⚠️ [StoreKit] 0 products returned from App Store. Attempting receipt sync and retry…")
                log.warning("0 products returned; attempting AppStore.sync + retry")
                do {
                    try await AppStore.sync()
                    let retry = try await Product.products(for: productIds)
                    products = retry.filter { $0.type == .autoRenewable }
                    print("🛒 [StoreKit] Retry loaded \(products.count) products")
                    log.debug("Retry loaded products=\(self.products.count, privacy: .public)")
                } catch {
                    print("❌ [StoreKit] AppStore.sync or retry failed: \(error)")
                    log.error("sync/retry failed: \(String(describing: error), privacy: .public)")
                }
                if products.isEmpty {
                    loadingError = "No products available. Ensure IAPs are attached to the build and available in your storefront."
                    print("⚠️ [StoreKit] Still 0 products after retry. Common causes: not attached to build, not cleared for sale in storefront, Agreements/Tax/Banking inactive, or propagation delay.")
                    log.fault("Still 0 products after retry. Check ASC attachment, storefront availability, ATB, propagation")
                }
            }
        } catch {
            let ns = error as NSError
            let codeDescription = describeStoreKitError(error)
            print("❌ [StoreKit] products(for:) failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo) desc=\(codeDescription)")
            log.error("products(for:) failed code=\(ns.code, privacy: .public) desc=\(codeDescription, privacy: .public)")
            loadingError = "Unable to load subscription options. \(codeDescription)"
        }

        isLoadingProducts = false
        lastProductsFetchAt = Date()
        await updateSubscriptionStatus()
    }

    // MARK: - Purchase
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updateSubscriptionStatus()
            // Sync transaction to Supabase
            await syncTransactionToSupabase(transaction)
        case .userCancelled:
            throw StorePurchaseError.cancelled
        case .pending:
            throw StorePurchaseError.pending
        @unknown default:
            throw StorePurchaseError.unknown
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updateSubscriptionStatus()
        // Sync all current entitlements to Supabase
        await syncAllTransactionsToSupabase()
        if !hasActiveSubscription {
            throw StorePurchaseError.noPurchasesToRestore
        }
    }

    // MARK: - Status
    func updateSubscriptionStatus() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productType == .autoRenewable {
                active.insert(transaction.productID)
            }
        }
        purchasedSubscriptions = active
        hasActiveSubscription = !active.isEmpty
        print("🛒 [StoreKit] Active subscriptions=\(Array(active))")
    }

    // MARK: - Helpers
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await self.updateSubscriptionStatus()
                    await transaction.finish()
                    // Sync updated transaction to Supabase
                    await self.syncTransactionToSupabase(transaction)
                    print("🛒 [StoreKit] Transaction update finished id=\(transaction.id) product=\(transaction.productID)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StorePurchaseError.verificationFailed
        }
    }

    // MARK: - Diagnostics
    func collectDiagnostics() async -> String {
        var lines: [String] = []
        func add(_ key: String, _ value: String) { lines.append("\(key): \(value)") }

        add("Timestamp", ISO8601DateFormatter().string(from: Date()))
        add("BundleID", Bundle.main.bundleIdentifier ?? "nil")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        add("Version", "\(version) (\(build))")
#if os(iOS)
        add("Device", UIDevice.current.model)
        add("System", "iOS \(UIDevice.current.systemVersion)")
        if let sf = await Storefront.current { add("Storefront", "\(sf.id) \(sf.countryCode)") } else { add("Storefront", "unavailable") }
        add("canMakePayments", String(AppStore.canMakePayments))
#endif
        add("Locale", Locale.current.identifier)
        add("Currency", Locale.current.currency?.identifier ?? "n/a")
        add("ProductIDs", productIds.joined(separator: ", "))
        add("ProductsLoaded", String(products.count))
        add("HasActiveSub", String(hasActiveSubscription))
        add("ActiveProductIDs", Array(purchasedSubscriptions).joined(separator: ", "))
        add("LastFetchAt", lastProductsFetchAt?.description ?? "never")
        add("LoadingError", loadingError ?? "none")
        var env = "unknown"
        do {
            let result = try await AppTransaction.shared
            switch result {
            case .verified(let tx):
                env = tx.environment.rawValue
                add("Receipt", "AppTransaction verified, env=\(tx.environment.rawValue), originalDate=\(tx.originalPurchaseDate as Date? ?? Date.distantPast)")
            case .unverified(_, let error):
                env = "unverified"
                add("Receipt", "AppTransaction unverified: \(String(describing: error))")
            }
        } catch {
            env = "error"
            add("Receipt", "AppTransaction error: \(error.localizedDescription)")
        }
        add("Environment", env)
        let usingLocalTestingHint = (env == "xcode") ? "YES (disable Developer > StoreKit Testing)" : "NO (ASC/Sandbox)"
        add("UsingLocalStoreKitTesting", usingLocalTestingHint)

        let diag = lines.joined(separator: "\n")
        diagnosticsText = diag
        print("\n============= StoreKit Diagnostics =============\n" + diag + "\n===============================================\n")
        return diag
    }

    // MARK: - Supabase Sync

    private func syncTransactionToSupabase(_ transaction: Transaction) async {
        do {
            try await SupabaseManager.shared.validateTransaction(transaction)
        } catch {
            print("❌ [StoreKit] Failed to sync transaction to Supabase: \(error)")
            log.error("Failed to sync transaction to Supabase: \(String(describing: error), privacy: .public)")
        }
    }

    private func syncAllTransactionsToSupabase() async {
        print("🔄 [StoreKit] Syncing all transactions to Supabase")
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productType == .autoRenewable {
                await syncTransactionToSupabase(transaction)
            }
        }
    }

    // MARK: - Error explanation
    private func describeStoreKitError(_ error: Error) -> String {
        if let sk = error as? StoreKitError {
            switch sk {
            case .unknown: return "StoreKitError.unknown"
            case .userCancelled: return "User cancelled"
            case .networkError: return "Network error contacting App Store"
            case .systemError: return "System error"
            case .notAvailableInStorefront: return "Not available in current storefront"
            case .notEntitled: return "Not entitled"
            case .unsupported:
                return "Unsupported"
            @unknown default:
                return "StoreKitError.\(String(describing: sk))"
            }
        }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }
}

enum StorePurchaseError: LocalizedError {
    case cancelled
    case pending
    case verificationFailed
    case noPurchasesToRestore
    case unknown

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Purchase was cancelled"
        case .pending: return "Purchase pending approval"
        case .verificationFailed: return "Purchase verification failed"
        case .noPurchasesToRestore: return "No purchases to restore"
        case .unknown: return "An unknown error occurred"
        }
    }
}
