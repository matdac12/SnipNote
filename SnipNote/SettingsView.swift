//
//  SettingsView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData
import UserNotifications
import StoreKit
import Supabase
import Functions

enum DeleteAccountError: LocalizedError {
    case notAuthenticated
    case deletionFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to delete your account."
        case .deletionFailed:
            return "Failed to delete your account. Please try again or contact support."
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var minutesManager = MinutesManager.shared
    @Query private var meetings: [Meeting]
    @State private var showingLogoutConfirmation = false
    @State private var userUsage: UserUsage?
    @State private var isLoadingStats = false
    @State private var showingPaywall = false
    @State private var showingMinutesPaywall = false
    @State private var showingDeleteAccountAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showingRestoreAlert = false
    @State private var restoredSuccessfully = false
    @State private var showingAboutSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
             HStack(spacing: 12) {
                 let title = localized("settings.title")
                 Text(title)
                     .themedTitle()

                 Spacer()

                 Picker("", selection: languageSelection) {
                     Text(localized("language.option.short.english")).tag("en")
                     Text(localized("language.option.short.italian")).tag("it")
                 }
                 .pickerStyle(.segmented)
                 .frame(width: 140)
                 .labelsHidden()
             }
             .padding()
             .background(themeManager.currentTheme.materialStyle)
             .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            
             ScrollView {
                 VStack(alignment: .leading, spacing: 20) {
                     Spacer().frame(height: 8) // Add some top spacing
                    
                     // SUBSCRIPTION STATUS SECTION
                     VStack(alignment: .leading, spacing: 16) {
                         HStack {
                             Text(localized("settings.section.subscription.title").uppercased())
                                 .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                 .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                             Spacer()

                             // Refresh button
                             Button(action: {
                                 Task {
                                     await storeManager.loadProducts()
                                     await storeManager.updateSubscriptionStatus()
                                 }
                             }) {
                                 Image(systemName: "arrow.clockwise")
                                     .font(.caption)
                                     .foregroundColor(themeManager.currentTheme.accentColor)
                             }
                         }

                         VStack(spacing: 12) {
                             HStack {
                                 VStack(alignment: .leading, spacing: 4) {
                                     HStack(spacing: 8) {
                                         Text(storeManager.hasActiveSubscription ? localized("settings.subscription.plan.pro") : localized("settings.subscription.plan.free"))
                                             .themedBody()
                                             .fontWeight(.bold)

                                         if storeManager.hasActiveSubscription {
                                             ProBadge()
                                         }
                                     }

                                     if storeManager.hasActiveSubscription {
                                         Text(localized("settings.subscription.plan.unlimited"))
                                             .themedCaption()
                                     } else {
                                          Text("Free Tier - Minutes-based usage")
                                             .themedCaption()
                                     }

                                     // Minutes balance display
                                     HStack(spacing: 4) {
                                         Image(systemName: "clock.fill")
                                             .font(.caption)
                                             .foregroundColor(minutesManager.currentBalance > 0 ? themeManager.currentTheme.accentColor : themeManager.currentTheme.warningColor)

                                         Text(minutesManager.formattedBalance)
                                             .themedCaption()
                                             .foregroundColor(minutesManager.currentBalance > 0 ? themeManager.currentTheme.textColor : themeManager.currentTheme.warningColor)
                                     }
                                 }

                                 Spacer()

                                 if !storeManager.hasActiveSubscription {
                                     Button(localized("settings.subscription.upgrade")) {
                                         showingPaywall = true
                                     }
                                     .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                     .foregroundColor(.white)
                                     .padding(.horizontal, 16)
                                     .padding(.vertical, 8)
                                     .background(themeManager.currentTheme.accentColor)
                                     .cornerRadius(themeManager.currentTheme.cornerRadius)
                                 }
                             }
                         }
                         .padding()
                         .background(themeManager.currentTheme.materialStyle)
                         .cornerRadius(themeManager.currentTheme.cornerRadius)
                         .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                     }
                     .padding(.horizontal, 10)
                     .padding(.vertical, 12)
                     .background(
                         RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius + 6)
                             .fill(themeManager.currentTheme.secondaryBackgroundColor.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.45 : 0.18))
                     )
                     .shadow(color: Color.black.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.4 : 0.12), radius: 8, x: 0, y: 4)

                     // MINUTES PACKS SECTION
                     // Always show - allow users to buy extra minutes even with subscriptions
                         VStack(alignment: .leading, spacing: 16) {
                             Text(storeManager.hasActiveSubscription ? "EXTRA MINUTES" : "NEED MORE MINUTES?")
                                 .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                 .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                             VStack(spacing: 12) {
                                 HStack {
                                     VStack(alignment: .leading, spacing: 4) {
                                         Text(storeManager.hasActiveSubscription ? "Buy Extra Minutes" : "Buy Minutes Packs")
                                             .themedBody()
                                             .fontWeight(.bold)

                                         Text("Get instant minutes that never expire")
                                             .themedCaption()
                                     }

                                     Spacer()

                                     Button("Buy Packs") {
                                         showingMinutesPaywall = true
                                     }
                                     .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                     .foregroundColor(.white)
                                     .padding(.horizontal, 16)
                                     .padding(.vertical, 8)
                                     .background(minutesManager.currentBalance <= 0 ? themeManager.currentTheme.warningColor : themeManager.currentTheme.accentColor)
                                     .cornerRadius(themeManager.currentTheme.cornerRadius)
                                 }
                             }
                             .padding()
                             .background(themeManager.currentTheme.materialStyle)
                             .cornerRadius(themeManager.currentTheme.cornerRadius)
                             .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                         }
                         .padding(.horizontal, 10)
                         .padding(.vertical, 12)
                         .background(
                             RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius + 6)
                                 .fill(themeManager.currentTheme.secondaryBackgroundColor.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.45 : 0.18))
                         )
                         .shadow(color: Color.black.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.4 : 0.12), radius: 8, x: 0, y: 4)

                     // APPEARANCE SECTION
                     VStack(alignment: .leading, spacing: 16) {
                         Text(localized("settings.section.appearance.title").uppercased())
                             .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                             .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                         VStack(spacing: 12) {
                             HStack {
                                 Text(localized("settings.appearance.theme"))
                                     .themedBody()
                                     .fontWeight(.bold)

                                 Spacer()

                                 Picker(localized("settings.appearance.theme"), selection: $themeManager.themeType) {
                                     ForEach(ThemeType.allCases, id: \.self) { theme in
                                         Text(theme.rawValue)
                                             .tag(theme)
                                     }
                                 }
                                 .pickerStyle(SegmentedPickerStyle())
                                 .frame(width: 150)
                             }

                             Text(themeManager.themeType == .light ? localized("settings.appearance.lightDescription") : localized("settings.appearance.darkDescription"))
                                 .themedCaption()
                                 .frame(maxWidth: .infinity, alignment: .leading)
                         }
                         .padding()
                         .background(themeManager.currentTheme.materialStyle)
                         .cornerRadius(themeManager.currentTheme.cornerRadius)
                         .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                     }
                     .padding(.horizontal, 10)
                     .padding(.vertical, 12)
                     .background(
                         RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius + 6)
                             .fill(themeManager.currentTheme.secondaryBackgroundColor.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.45 : 0.18))
                     )
                     .shadow(color: Color.black.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.4 : 0.12), radius: 8, x: 0, y: 4)

                     VStack(alignment: .leading, spacing: 16) {
                         HStack {
                             Text(localized("settings.section.usage.title").uppercased())
                                 .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                                 .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                             Spacer()

                             if isLoadingStats {
                                 ProgressView()
                                     .scaleEffect(0.7)
                             }
                         }

                         VStack(spacing: 12) {
                             if let usage = userUsage {
                                 StatRow(label: localized("settings.usage.meetingsCreated"), value: "\(usage.totalMeetings)")
                                 StatRow(label: localized("settings.usage.meetingsTranscribed"), value: "\(usage.totalMeetingsTranscribed)")
                                 StatRow(label: localized("settings.usage.totalRecordingTime"), value: usage.formattedMeetingTime)
                                 StatRow(label: localized("settings.usage.aiSummaries"), value: "\(usage.totalAiSummaries)")
                             } else {
                                 HStack {
                                     Spacer()
                                     Text(localized("settings.usage.loading"))
                                         .themedBody()
                                         .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                     Spacer()
                                 }
                             }
                         }
                         .padding()
                         .background(themeManager.currentTheme.materialStyle)
                         .cornerRadius(themeManager.currentTheme.cornerRadius)
                         .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                     }
                     .padding(.horizontal, 10)
                     .padding(.vertical, 12)
                     .background(
                         RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius + 6)
                             .fill(themeManager.currentTheme.secondaryBackgroundColor.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.45 : 0.18))
                     )
                     .shadow(color: Color.black.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.4 : 0.12), radius: 8, x: 0, y: 4)
                    
                     VStack(alignment: .leading, spacing: 16) {
                         Text(localized("settings.section.account.title").uppercased())
                             .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                             .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                         VStack(spacing: 12) {
                             if let email = authManager.currentUser?.email {
                                 HStack {
                                     Text(localized("settings.account.email"))
                                         .themedBody()

                                     Spacer()

                                     Text(email)
                                         .themedBody()
                                         .fontWeight(.bold)
                                         .foregroundColor(themeManager.currentTheme.accentColor)
                                 }
                             }

                             // Manage Subscription button (for pro users)
                             if storeManager.hasActiveSubscription {
                                 Button(action: manageSubscription) {
                                     HStack {
                                         Image(systemName: "creditcard")
                                         Text(localized("settings.account.manageSubscription"))
                                             .themedBody()
                                             .fontWeight(.bold)
                                     }
                                     .frame(maxWidth: .infinity)
                                     .padding()
                                     .background(themeManager.currentTheme.accentColor.opacity(0.2))
                                     .foregroundColor(themeManager.currentTheme.accentColor)
                                     .cornerRadius(themeManager.currentTheme.cornerRadius)
                                 }
                             }

                             Button(action: { showingLogoutConfirmation = true }) {
                                 HStack {
                                     Image(systemName: "rectangle.portrait.and.arrow.right")
                                     Text(localized("settings.account.logoutButton").uppercased())
                                         .themedBody()
                                         .fontWeight(.bold)
                                 }
                                 .frame(maxWidth: .infinity)
                                 .padding()
                                 .background(themeManager.currentTheme.destructiveColor.opacity(0.2))
                                 .foregroundColor(themeManager.currentTheme.destructiveColor)
                                 .cornerRadius(themeManager.currentTheme.cornerRadius)
                             }

                             // Delete Account button
                             Button(action: { showingDeleteAccountAlert = true }) {
                                 HStack {
                                     Image(systemName: "trash")
                                     Text(localized("settings.account.deleteAccount"))
                                         .themedBody()
                                         .fontWeight(.bold)
                                 }
                                 .frame(maxWidth: .infinity)
                                 .padding()
                                 .background(Color.red.opacity(0.15))
                                 .foregroundColor(.red)
                                 .cornerRadius(themeManager.currentTheme.cornerRadius)
                             }
                         }
                         .padding()
                         .background(themeManager.currentTheme.materialStyle)
                         .cornerRadius(themeManager.currentTheme.cornerRadius)
                         .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                     }
                     .padding(.horizontal, 10)
                     .padding(.vertical, 12)
                     .background(
                         RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius + 6)
                             .fill(themeManager.currentTheme.secondaryBackgroundColor.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.45 : 0.18))
                     )
                     .shadow(color: Color.black.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.4 : 0.12), radius: 8, x: 0, y: 4)
                    
                     VStack(alignment: .leading, spacing: 16) {
                         Text("ABOUT")
                             .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                             .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                         Button(action: { showingAboutSheet = true }) {
                             VStack(alignment: .leading, spacing: 8) {
                                 Text(localized("settings.about.version"))
                                     .themedBody()
                                     .fontWeight(.bold)
                                 Text(localized("settings.about.tagline"))
                                     .themedCaption()
                                     .lineLimit(2)
                             }
                             .padding()
                             .background(themeManager.currentTheme.materialStyle)
                             .cornerRadius(themeManager.currentTheme.cornerRadius)
                             .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                         }
                         .buttonStyle(.plain)
                     }
                     .padding(.horizontal, 10)
                     .padding(.vertical, 12)
                     .background(
                         RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius + 6)
                             .fill(themeManager.currentTheme.secondaryBackgroundColor.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.45 : 0.18))
                     )
                     .shadow(color: Color.black.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.4 : 0.12), radius: 8, x: 0, y: 4)
                }
                 .padding()
             }
             .background(
                 LinearGradient(
                     colors: [
                         themeManager.currentTheme.secondaryBackgroundColor.opacity(0.15),
                         themeManager.currentTheme.backgroundColor
                     ],
                     startPoint: .top,
                     endPoint: .bottom
                 )
             )
        }
        .themedBackground()
        .alert(localized("settings.notifications.logout.title"), isPresented: $showingLogoutConfirmation) {
            Button(localized("settings.notifications.logout.confirm"), role: .destructive) {
                Task {
                    await cleanupUserAIContext()
                    try? await authManager.signOut()
                }
            }
            Button(localized("settings.notifications.logout.cancel"), role: .cancel) {}
        } message: {
            Text(localized("settings.notifications.logout.message"))
        }
        .alert(localized("settings.account.deleteAccount"), isPresented: $showingDeleteAccountAlert) {
            Button(localized("settings.account.deleteAccount"), role: .destructive) {
                showingDeleteConfirmation = true
            }
            Button(localized("settings.account.deleteAccount.cancel"), role: .cancel) {}
        } message: {
            Text(localized("settings.account.deleteAccount.description"))
        }
        .alert(localized("settings.account.deleteAccount.confirmTitle"), isPresented: $showingDeleteConfirmation) {
            TextField(localized("settings.account.deleteAccount.confirmPlaceholder"), text: $deleteConfirmationText)
            Button(localized("settings.account.deleteAccount.confirmButton"), role: .destructive) {
                if deleteConfirmationText == "DELETE" {
                    Task {
                        await deleteAccount()
                    }
                }
            }
            .disabled(deleteConfirmationText != "DELETE")
            Button(localized("settings.account.deleteAccount.cancel"), role: .cancel) {
                deleteConfirmationText = ""
            }
        } message: {
            Text(localized("settings.account.deleteAccount.confirmMessage"))
        }
        .alert(localized("settings.account.deleteAccount.errorTitle"), isPresented: $showingDeleteError) {
            Button(localized("settings.account.deleteAccount.errorDismiss")) { }
        } message: {
            Text(deleteErrorMessage)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingMinutesPaywall) {
            MinutesPackPaywallView(onPurchaseComplete: {
                Task { await minutesManager.refreshBalance() }
            })
        }
        .sheet(isPresented: $showingAboutSheet) {
            AboutSheetView()
        }
        .onAppear {
            fetchUsageStats()
            Task { await minutesManager.refreshBalance() }
        }
    }

    private var languageSelection: Binding<String> {
        Binding(
            get: { localizationManager.languageCode },
            set: { localizationManager.setLanguage(code: $0) }
        )
    }

    private func localized(_ key: String) -> String {
        localizationManager.localizedString(key)
    }

    @MainActor
    private func cleanupUserAIContext() async {
        guard let userId = authManager.currentUser?.id else { return }

        do {
            let descriptor = FetchDescriptor<UserAIContext>(predicate: #Predicate { $0.userId == userId })
            guard let context = try modelContext.fetch(descriptor).first else { return }

            let states = Array(context.meetingFiles)

            if let storeId = context.vectorStoreId {
                for state in states where state.isAttached {
                    do {
                        try await OpenAIService.shared.detachFileFromVectorStore(fileId: state.fileId, vectorStoreId: storeId)
                    } catch {
                        print("Error detaching file during sign out: \(error)")
                    }
                }
            }

            for state in states {
                modelContext.delete(state)
            }
            modelContext.delete(context)
            try modelContext.save()
        } catch {
            print("Error cleaning AI context on sign out: \(error)")
        }
    }

    private func fetchUsageStats() {
        isLoadingStats = true
        Task {
            do {
                let usage = try await SupabaseManager.shared.getUserUsage()
                await MainActor.run {
                    self.userUsage = usage
                    self.isLoadingStats = false
                }
            } catch {
                print("Failed to fetch usage data: \(error)")
                await MainActor.run {
                    self.isLoadingStats = false
                }
            }
        }
    }
    
    private func restorePurchases() async {
        do {
            try await storeManager.restorePurchases()
            await MainActor.run {
                restoredSuccessfully = true
                showingRestoreAlert = true
            }
        } catch {
            await MainActor.run {
                restoredSuccessfully = false
                showingRestoreAlert = true
            }
        }
    }
    
    private func deleteAccount() async {
        isDeletingAccount = true
        deleteConfirmationText = ""
        
        do {
            guard let userId = authManager.currentUser?.id else {
                throw DeleteAccountError.notAuthenticated
            }
            
            // Call Supabase Edge Function to delete account
            struct DeleteRequest: Encodable {
                let user_id: String
            }
            
            let deleteRequest = DeleteRequest(user_id: userId.uuidString)
            
            let response: Data = try await SupabaseManager.shared.client.functions
                .invoke(
                    "delete-account",
                    options: FunctionInvokeOptions(
                        body: deleteRequest
                    )
                )
            
            // Check if deletion was successful
            if let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
               let success = json["success"] as? Bool,
               success {
                // Sign out locally after successful deletion
                await cleanupUserAIContext()
                try await authManager.signOut()
            } else {
                throw DeleteAccountError.deletionFailed
            }
            
            await MainActor.run {
                isDeletingAccount = false
            }
        } catch {
            await MainActor.run {
                isDeletingAccount = false
                showingDeleteConfirmation = false
                
                if let deleteError = error as? DeleteAccountError {
                    deleteErrorMessage = deleteError.localizedDescription
                } else {
                    deleteErrorMessage = "Failed to delete account: \(error.localizedDescription)"
                }
                showingDeleteError = true
            }
        }
    }
    
    private func manageSubscription() {
        Task {
            #if os(iOS)
            do {
                // Try to show native subscription management (requires a UIWindowScene)
                let scene = await MainActor.run { UIApplication.shared.connectedScenes.first as? UIWindowScene }
                if let scene {
                    try await AppStore.showManageSubscriptions(in: scene)
                } else {
                    // Fallback to App Store subscriptions page if no scene found
                    await MainActor.run {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } catch {
                // Fall back to opening App Store subscriptions page
                await MainActor.run {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            #endif
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack {
            Text(label)
                .themedBody()
            
            Spacer()
            
            Text(value)
                .themedBody()
                .fontWeight(.bold)
                .foregroundColor(themeManager.currentTheme.accentColor)
        }
    }
}

struct AboutSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About SnipNote")
                            .font(.system(.title, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.textColor)

                        Text(localized("settings.about.subtitle"))
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                    }

                    // Developer Info
                    VStack(alignment: .leading, spacing: 16) {
                        Text("DEVELOPER")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(themeManager.currentTheme.accentColor)
                                    .font(.system(size: 24))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mattia Da Campo")
                                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                                        .foregroundColor(themeManager.currentTheme.textColor)
                                    Text(localized("settings.about.developer.role"))
                                        .font(.system(.subheadline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                                }
                            }

                            Text(localized("settings.about.developer.description"))
                                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                                .foregroundColor(themeManager.currentTheme.textColor)
                                .lineSpacing(4)
                        }
                        .padding()
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                    }

                    // Contact Information
                    VStack(alignment: .leading, spacing: 16) {
                        Text("CONTACT")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                        VStack(spacing: 12) {
                            ContactRow(
                                icon: "envelope.fill",
                                title: "Email",
                                value: "mattianalytics6@gmail.com",
                                action: { openEmail() }
                            )

                            ContactRow(
                                icon: "globe",
                                title: "Website",
                                value: "www.mattianalytics.com",
                                action: { openWebsite() }
                            )

                            ContactRow(
                                icon: "star.fill",
                                title: "Rate on App Store",
                                value: "Leave a review",
                                action: { openAppStore() }
                            )
                        }
                    }

                    // Support Guidelines
                    VStack(alignment: .leading, spacing: 16) {
                        Text("NEED HELP?")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("If you're experiencing issues or have questions:")
                                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                                .foregroundColor(themeManager.currentTheme.textColor)

                            VStack(alignment: .leading, spacing: 8) {
                                
                                SupportGuideline(
                                    icon: "1.circle.fill",
                                    text: "Restart the app and try again"
                                )

                                SupportGuideline(
                                    icon: "2.circle.fill",
                                    text: "Contact support via email with details about your issue"
                                )

                                SupportGuideline(
                                    icon: "3.circle.fill",
                                    text: "Include your device type, iOS version, and steps to reproduce"
                                )
                            }
                        }
                        .padding()
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                    }

                    // Version Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VERSION")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                        Text("SnipNote v1.4.6")
                            .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(themeManager.currentTheme.textColor)
                    }
                }
                .padding()
            }
            .background(themeManager.currentTheme.backgroundColor.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.currentTheme.accentColor)
                }
            }
        }
        .themed()
    }

    private func localized(_ key: String) -> String {
        localizationManager.localizedString(key)
    }

    private func openEmail() {
        let subject = "SnipNote Support Request"
        let body = "Please describe your issue or question here.\n\nDevice: \(UIDevice.current.model)\nOS: \(UIDevice.current.systemVersion)\nApp Version: 1.0.0"
        let email = "support@snipnote.app"

        if let url = URL(string: "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url)
        }
    }

    private func openWebsite() {
        if let url = URL(string: "http://mattianalytics.com") {
            UIApplication.shared.open(url)
        }
    }

    private func openAppStore() {
        if let url = URL(string: "https://apps.apple.com/app/snipnote/id1234567890") { // Replace with actual App Store URL
            UIApplication.shared.open(url)
        }
    }
}

struct ContactRow: View {
    let icon: String
    let title: String
    let value: String
    let action: () -> Void

    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(themeManager.currentTheme.accentColor)
                    .font(.system(size: 20))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.textColor)

                    Text(value)
                        .font(.system(.subheadline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding()
            .background(themeManager.currentTheme.materialStyle)
            .cornerRadius(themeManager.currentTheme.cornerRadius)
        }
        .buttonStyle(.plain)
    }
}

struct SupportGuideline: View {
    let icon: String
    let text: String

    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(themeManager.currentTheme.accentColor)
                .font(.system(size: 16))
                .frame(width: 20)

            Text(text)
                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                .foregroundColor(themeManager.currentTheme.textColor)
                .lineSpacing(4)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Action.self], inMemory: true)
        .environmentObject(ThemeManager.shared)
        .environmentObject(AuthenticationManager())
        .environmentObject(LocalizationManager.shared)
}
