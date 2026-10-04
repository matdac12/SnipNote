//
//  PlanSettingsView.swift
//  SnipNote
//
//  Subscription page opened from the pass: current plan, App Store management,
//  minute packs, restore and status refresh.
//

import SwiftUI

struct PlanSettingsView: View {
    let isPro: Bool
    let plan: ProPlan?
    let balance: Int
    let onManageSubscription: () -> Void
    let onShowPlans: () -> Void
    let onShowMinutePacks: () -> Void
    let onRestore: () async -> Void
    let onRefresh: () async -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var isRestoring = false
    @State private var isRefreshing = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(planTitle)
                            .font(.headline)
                        Spacer()
                        if isPro {
                            Text(localized("settings.plan.active").uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(themeManager.currentTheme.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(themeManager.currentTheme.accentColor.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(planDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(localized("settings.pass.minutesLeft")): \(max(balance, 0)) min")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(balance <= 0 ? themeManager.currentTheme.warningColor : themeManager.currentTheme.textColor)
                }
                .padding(.vertical, 4)
            }

            Section {
                if isPro {
                    Button(action: onManageSubscription) {
                        LabeledContent {
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } label: {
                            SettingsIconLabel(title: localized("settings.account.manageSubscription"), systemImage: "creditcard.fill", tint: themeManager.currentTheme.accentColor)
                        }
                    }
                } else {
                    Button(action: onShowPlans) {
                        SettingsIconLabel(title: localized("settings.plan.seePlans"), systemImage: "crown.fill", tint: themeManager.currentTheme.accentColor)
                    }
                }
                Button(action: onShowMinutePacks) {
                    SettingsIconLabel(title: localized(isPro ? "settings.plan.buyExtra" : "settings.plan.minutePacks"), systemImage: "clock.fill", tint: .orange)
                }
            } footer: {
                Text(localized(isPro ? "settings.plan.footer.pro" : "settings.plan.footer.free"))
            }

            Section {
                Button {
                    Task {
                        isRestoring = true
                        await onRestore()
                        isRestoring = false
                    }
                } label: {
                    LabeledContent {
                        if isRestoring { ProgressView() }
                    } label: {
                        SettingsIconLabel(title: localized("settings.account.restorePurchases"), systemImage: "arrow.clockwise", tint: .green)
                    }
                }
                .disabled(isRestoring)

                Button {
                    Task {
                        isRefreshing = true
                        await onRefresh()
                        isRefreshing = false
                    }
                } label: {
                    LabeledContent {
                        if isRefreshing { ProgressView() }
                    } label: {
                        SettingsIconLabel(title: localized("settings.plan.refreshStatus"), systemImage: "arrow.triangle.2.circlepath", tint: .gray)
                    }
                }
                .disabled(isRefreshing)
            } header: {
                Text(localized("settings.plan.section.purchases"))
            } footer: {
                Text(localized("settings.plan.footer.restore"))
            }
        }
        .listStyle(.insetGrouped)
        .tint(themeManager.currentTheme.textColor)
        .navigationTitle(localized(isPro ? "settings.plan.title" : "settings.plan.subscription"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var planTitle: String {
        if isPro {
            return plan.map { localized($0.nameKey) } ?? localized("settings.subscription.plan.pro")
        }
        return localized("settings.subscription.plan.free")
    }

    private var planDescription: String {
        if isPro {
            let allowance = plan.map { localized($0.allowanceKey) + ". " } ?? ""
            return allowance + localized("settings.plan.pro.description")
        }
        return localized("settings.plan.free.description")
    }

    private func localized(_ key: String) -> String {
        localizationManager.localizedString(key)
    }
}

/// Settings row label with a rounded, colored icon square, like the iOS Settings app.
struct SettingsIconLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(Color.primary)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}
