//
//  PaywallView.swift
//  SnipNote
//
//  Created by Claude on 27/08/25.
//

import SwiftUI
import StoreKit
import UIKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var store = StoreManager.shared
    
    @State private var selectedProduct: Product?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isPurchasing = false
    @State private var debugInfo: String = ""
    @State private var isShowingDebug = false
    
    var dismissible: Bool = true
    var onPurchaseComplete: (() -> Void)?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    headerSection
                    
                    // Features
                    featuresSection
                    
                    // Subscription Tiers
                    subscriptionTiers
                    
                    // Purchase Button
                    purchaseButton
                    
                    // Restore and Terms
                    footerSection
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(themeManager.currentTheme.backgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if dismissible {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                }
            }
            .alert("Purchase Error", isPresented: $showingError) {
                Button("OK") { }
                if errorMessage.contains("offerings") || errorMessage.contains("subscription") || errorMessage.contains("products") {
                    Button("Retry Loading") {
                        Task { await store.loadProducts() }
                    }
                }
            } message: {
                Text(errorMessage)
            }
            .overlay {
                if isPurchasing {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        }
                }
            }
            .onAppear {
                print("🧪 [PaywallView] onAppear - isLoading=\(store.isLoadingProducts), products=\(store.products.count), hasSub=\(store.hasActiveSubscription)")
                Task { await store.loadProducts() }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 45))
                .foregroundColor(themeManager.currentTheme.accentColor)
            
            Text("Unlock SnipNote Pro")
                .font(.system(.title, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(themeManager.currentTheme.textColor)
            
            Text("Get unlimited access to all premium features")
                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10)
    }
    
    // MARK: - Features Section
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Premium Features")
                .font(.system(.subheadline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(themeManager.currentTheme.textColor)
            
            FeatureRow(icon: "infinity", title: "Unlimited Meetings & Notes", description: "No monthly limits")
            FeatureRow(icon: "sparkles", title: "AI Features", description: "Eve chat, smart summaries & action extraction")
            FeatureRow(icon: "icloud.fill", title: "Cloud Sync", description: "Access your data across all devices")
        }
        .padding(12)
        .background(themeManager.currentTheme.materialStyle)
        .cornerRadius(themeManager.currentTheme.cornerRadius)
    }
    
    // MARK: - Subscription Tiers
    private var subscriptionTiers: some View {
        VStack(spacing: 10) {
            if store.isLoadingProducts {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Loading subscription options...")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(themeManager.currentTheme.materialStyle)
                .cornerRadius(themeManager.currentTheme.cornerRadius)
            } else if store.products.isEmpty {
                // Show loading or error state
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(themeManager.currentTheme.warningColor)
                    
                    Text("Unable to load subscription options")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                    
                    if let error = store.loadingError {
                        Text(error)
                            .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Button("Retry") { Task { await store.loadProducts() } }
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.accentColor)

                    Button(isShowingDebug ? "Hide Debug Info" : "Show Debug Info") {
                        isShowingDebug.toggle()
                        if isShowingDebug && debugInfo.isEmpty {
                            Task { debugInfo = await store.collectDiagnostics() }
                        }
                    }
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.accentColor)

                    if isShowingDebug {
                        ScrollView {
                            Text(debugInfo.isEmpty ? "Collecting diagnostics…" : debugInfo)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 160)
                        .padding(6)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(6)

                        Button("Copy Debug Info") {
                            UIPasteboard.general.string = debugInfo
                        }
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(themeManager.currentTheme.materialStyle)
                .cornerRadius(themeManager.currentTheme.cornerRadius)
            } else {
                ForEach(store.products, id: \.id) { product in
                    SubscriptionTierCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id,
                        onTap: { withAnimation(.spring()) { selectedProduct = product } }
                    )
                }
            }
        }
    }
    
    // MARK: - Purchase Button
    private var purchaseButton: some View {
        VStack(spacing: 8) {
            // Subscription terms text
            if selectedProduct != nil {
                Text("Payment will be charged to your iTunes account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. Manage or cancel your subscription in Account Settings.")
                    .font(.system(size: 9))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Button(action: purchaseSelected) {
                HStack {
                    Text(isPurchasing ? "Processing..." : "Subscribe Now")
                        .font(.system(.subheadline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    
                    if !isPurchasing {
                        Image(systemName: "arrow.right")
                            .font(.caption)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal)
                .background(
                    selectedProduct != nil ? themeManager.currentTheme.accentColor : Color.gray
                )
                .cornerRadius(themeManager.currentTheme.cornerRadius)
            }
            .disabled(selectedProduct == nil || isPurchasing)
        }
    }
    
    // MARK: - Footer Section
    private var footerSection: some View {
        VStack(spacing: 10) {
            Button(action: restorePurchases) {
                Text("Restore Purchases")
                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(themeManager.currentTheme.accentColor)
            }
            
            // Terms and Privacy links placeholder - update these when you have the URLs
            HStack(spacing: 12) {
                Button(action: {
                    // Link to Apple's Standard EULA
                    if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                         UIApplication.shared.open(url)
                     }
                }) {
                    Text("Terms of Use (EULA)")
                        .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                }
                
                Text("•")
                    .font(.system(.caption2))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                
                Button(action: {
                    // TODO: Add Privacy URL when ready
                    if let url = URL(string: "https://www.mattianalytics.com/privacy") {
                        UIApplication.shared.open(url)
                        }
                }) {
                    Text("Privacy Policy")
                        .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                }
            }
            
            Text("Cancel anytime from Settings")
                .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Actions
    private func purchaseSelected() {
        guard let product = selectedProduct else { return }
        
        Task {
            isPurchasing = true
            defer { isPurchasing = false }
            do {
                try await store.purchase(product)
                onPurchaseComplete?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func restorePurchases() {
        Task {
            do {
                try await store.restorePurchases()
                onPurchaseComplete?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(themeManager.currentTheme.accentColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.textColor)
                
                Text(description)
                    .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
            }
            
            Spacer()
        }
    }
}

// MARK: - Subscription Tier Card
struct SubscriptionTierCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let product: Product
    let isSelected: Bool
    let onTap: () -> Void
    
    private func getPeriodTitle(for product: Product) -> String {
        // Use displayName from App Store Connect; fallback based on ID
        let storeTitle = product.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !storeTitle.isEmpty { return storeTitle }
        switch product.id {
        case SubscriptionTier.weekly.rawValue: return "SnipNote Pro Weekly"
        case SubscriptionTier.monthly.rawValue: return "SnipNote Pro Monthly"
        case SubscriptionTier.annual.rawValue: return "SnipNote Pro Annual"
        default: return "SnipNote Pro"
        }
    }
    
    private func getSubscriptionDescription(for product: Product) -> String {
        let storeDescription = product.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if storeDescription.isEmpty {
            if let period = product.subscription?.subscriptionPeriod {
                return "Billed \(getPeriodText(for: period).lowercased()), cancel anytime"
            }
            return "Unlimited access to all premium features"
        }
        if let period = product.subscription?.subscriptionPeriod,
           !storeDescription.lowercased().contains("billed") {
            return "\(storeDescription). Billed \(getPeriodText(for: period).lowercased())."
        }
        return storeDescription
    }
    
    private func getPeriodText(for period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:
            return period.value == 1 ? "Daily" : "Every \(period.value) days"
        case .week:
            return period.value == 1 ? "Weekly" : "Every \(period.value) weeks"
        case .month:
            return period.value == 1 ? "Monthly" : "Every \(period.value) months"
        case .year:
            return period.value == 1 ? "Annually" : "Every \(period.value) years"
        @unknown default:
            return "Subscription"
        }
    }
    
    private var tier: SubscriptionTier? {
        SubscriptionTier.allCases.first { $0.rawValue == product.id }
    }
    
    private var savingsText: String? {
        guard let tier = tier else { return nil }
        return tier.savingsText
    }
    
    private var isBestValue: Bool {
        return tier?.isBestValue ?? false
    }
    
    private func calculateMonthlyEquivalent(for product: Product) -> String {
        // Get the price without currency symbol for calculation
        let price = product.price
        let monthlyPrice = price / 12 // Annual divided by 12 months
        
        // Extract currency symbol from the localized price string
        let fullPriceString = product.displayPrice
        
        // Create a formatter to match the store's formatting
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        
        // Try to detect the currency symbol and format from the full price string
        if fullPriceString.contains("$") {
            formatter.currencySymbol = "$"
            formatter.locale = Locale(identifier: "en_US")
        } else if fullPriceString.contains("€") {
            formatter.currencySymbol = "€"
            formatter.locale = Locale(identifier: "it_IT")
        } else if fullPriceString.contains("£") {
            formatter.currencySymbol = "£"
            formatter.locale = Locale(identifier: "en_GB")
        } else {
            // Use current locale as fallback
            formatter.locale = Locale.current
        }
        
        if let formattedPrice = formatter.string(from: monthlyPrice as NSNumber) {
            return formattedPrice
        }
        
        // Fallback - convert Decimal to Double for string formatting
        let monthlyPriceDouble = NSDecimalNumber(decimal: monthlyPrice).doubleValue
        return String(format: "%.2f", monthlyPriceDouble)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        // Show full product title prominently
                        Text(getPeriodTitle(for: product))
                            .font(.system(.subheadline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.textColor)
                        
                        if isBestValue {
                            Text("BEST VALUE")
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        } else if let savings = savingsText {
                            Text(savings)
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(themeManager.currentTheme.accentColor)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(getSubscriptionDescription(for: product))
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 1) {
                    // Use App Store localized pricing
                    Text(product.displayPrice)
                        .font(.system(.callout, design: .monospaced, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.textColor)
                    
                    // Show period and monthly equivalent for annual
                    if let period = product.subscription?.subscriptionPeriod {
                        if period.unit == .year && period.value == 1 {
                            // For annual, show monthly equivalent
                            let monthlyEquivalent = calculateMonthlyEquivalent(for: product)
                            Text("≈ \(monthlyEquivalent)/mo")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        } else {
                            // For other periods, just show the period
                            Text(getPeriodText(for: period))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        }
                    }
                }
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? themeManager.currentTheme.accentColor : themeManager.currentTheme.secondaryTextColor)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                    .fill(themeManager.currentTheme.materialStyle)
                    .overlay(
                        RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                            .stroke(isSelected ? themeManager.currentTheme.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
