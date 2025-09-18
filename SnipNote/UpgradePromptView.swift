//
//  UpgradePromptView.swift
//  SnipNote
//
//  Created by Claude on 27/08/25.
//

import SwiftUI
import StoreKit
import SwiftData

struct UpgradePromptView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingPaywall = false
    
    let title: String
    let message: String
    let icon: String
    
    init(
        title: String = "Upgrade to Pro",
        message: String = "This feature requires a Pro subscription",
        icon: String = "crown.fill"
    ) {
        self.title = title
        self.message = message
        self.icon = icon
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(themeManager.currentTheme.accentColor)
            
            Text(title)
                .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(themeManager.currentTheme.textColor)
            
            Text(message)
                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                .multilineTextAlignment(.center)
            
            Button(action: { showingPaywall = true }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Upgrade Now")
                }
                .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(themeManager.currentTheme.accentColor)
                .cornerRadius(themeManager.currentTheme.cornerRadius)
            }
        }
        .padding()
        .background(themeManager.currentTheme.materialStyle)
        .cornerRadius(themeManager.currentTheme.cornerRadius)
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
}

// MARK: - Inline Upgrade Badge
struct UpgradeBadge: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingPaywall = false
    
    var body: some View {
        Button(action: { showingPaywall = true }) {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.caption)
                Text("PRO")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
            }
            .foregroundColor(themeManager.currentTheme.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                themeManager.currentTheme.accentColor.opacity(0.1)
            )
            .cornerRadius(4)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
}

// MARK: - Usage Counter View
struct UsageCounterView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var store = StoreManager.shared
    @Query private var meetings: [Meeting]

    let type: String // "meetings"

    private var usageText: String {
        if store.hasActiveSubscription {
            return "Unlimited"
        }
        let total = meetings.count
        return "\(total)/\(FreeTierLimits.maxItemsTotal)"
    }

    private var color: Color {
        if store.hasActiveSubscription {
            return .green
        }
        let total = meetings.count
        if total >= FreeTierLimits.maxItemsTotal {
            return .red
        } else if total >= (FreeTierLimits.maxItemsTotal - 1) {
            return .orange
        }
        
        return themeManager.currentTheme.secondaryTextColor
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type == "meetings" ? "person.3.fill" : "note.text")
                .font(.caption)
            Text(usageText)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(4)
        .onAppear { Task { await store.updateSubscriptionStatus() } }
    }
}

// MARK: - Pro Badge
struct ProBadge: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.caption)
            Text("PRO")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.purple, Color.blue]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(4)
    }
}
