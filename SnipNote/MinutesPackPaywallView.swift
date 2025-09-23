//
//  MinutesPackPaywallView.swift
//  SnipNote
//
//  Created for minutes-based pricing system.
//

import SwiftUI
import StoreKit

struct MinutesPackPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var store = StoreManager.shared

    @State private var selectedProduct: Product?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isPurchasing = false
    @StateObject private var minutesManager = MinutesManager.shared

    let minutesPacks = [
        MinutesPack(id: "com.snipnote.packs.minutes100", minutes: 100, price: "€1.49", bestFor: "Quick top-ups"),
        MinutesPack(id: "com.snipnote.packs.minutes500", minutes: 500, price: "€4.99", bestFor: "Regular users"),
        MinutesPack(id: "com.snipnote.packs.minutes1000", minutes: 1000, price: "€9.99", bestFor: "Power users")
    ]

    var dismissible: Bool = true
    var onPurchaseComplete: (() -> Void)?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Current Balance
                    balanceSection

                    // Minutes Packs
                    packsSection

                    // Purchase Button
                    purchaseButton

                    // Footer
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
                Task {
                    await store.loadProducts()
                    await minutesManager.refreshBalance()
                }
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.plus.fill")
                .font(.system(size: 45))
                .foregroundColor(themeManager.currentTheme.accentColor)

            Text("Need More Minutes?")
                .font(.system(.title, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(themeManager.currentTheme.textColor)

            Text("Top up your transcription minutes instantly")
                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10)
    }

    // MARK: - Balance Section
    private var balanceSection: some View {
        VStack(spacing: 8) {
            Text("Current Balance")
                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)

            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundColor(minutesManager.currentBalance > 0 ? themeManager.currentTheme.accentColor : themeManager.currentTheme.warningColor)

                Text("\(minutesManager.currentBalance)")
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.textColor)

                Text("minutes")
                    .font(.system(.title3, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
            }
        }
        .padding(16)
        .background(themeManager.currentTheme.materialStyle)
        .cornerRadius(themeManager.currentTheme.cornerRadius)
    }

    // MARK: - Packs Section
    private var packsSection: some View {
        VStack(spacing: 12) {
            Text("Choose Your Pack")
                .font(.system(.subheadline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(themeManager.currentTheme.textColor)

            if store.isLoadingProducts {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
            } else {
                ForEach(minutesPacks, id: \.id) { pack in
                    MinutesPackCard(
                        pack: pack,
                        product: store.products.first { $0.id == pack.id },
                        isSelected: selectedProduct?.id == pack.id,
                        onTap: { selectPack(pack) }
                    )
                }
            }
        }
    }

    // MARK: - Purchase Button
    private var purchaseButton: some View {
        Button(action: purchaseSelected) {
            HStack {
                Text(isPurchasing ? "Processing..." : "Purchase Pack")
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

    // MARK: - Footer Section
    private var footerSection: some View {
        VStack(spacing: 10) {
            Text("• Minutes are added instantly to your account")
                .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)

            Text("• Purchase multiple packs anytime")
                .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)

            Text("• Minutes never expire")
                .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions
    private func selectPack(_ pack: MinutesPack) {
        if let product = store.products.first(where: { $0.id == pack.id }) {
            withAnimation(.spring()) {
                selectedProduct = product
            }
        }
    }

    private func purchaseSelected() {
        guard let product = selectedProduct else { return }

        Task {
            isPurchasing = true
            defer { isPurchasing = false }
            do {
                try await store.purchase(product)
                await minutesManager.refreshBalance() // Refresh balance
                onPurchaseComplete?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

}

// MARK: - Minutes Pack Model
struct MinutesPack {
    let id: String
    let minutes: Int
    let price: String
    let bestFor: String
}

// MARK: - Minutes Pack Card
struct MinutesPackCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let pack: MinutesPack
    let product: Product?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(pack.minutes) Minutes")
                            .font(.system(.subheadline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.textColor)

                        if pack.minutes == 1000 {
                            Text("BEST VALUE")
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }

                    Text("Perfect for \(pack.bestFor.lowercased())")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product?.displayPrice ?? pack.price)
                        .font(.system(.callout, design: .monospaced, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.textColor)

                    Text("≈ \(String(format: "%.3f", Double(pack.price.dropFirst().replacingOccurrences(of: ",", with: ".")) ?? 0.0 / Double(pack.minutes)))€/min")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
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