//
//  AccountGate.swift
//  SnipNote
//
//  Local mode works as a Guest with no Account. An Account is created with an email the first
//  time the user enters Cloud mode; these helpers are the single place that asks for it.
//

import SwiftUI
import SwiftData

/// Cloud entry points call this reason when asking a Guest to create an Account.
enum AccountReason {
    static var cloud: String { LocalizationManager.localizedAppString("account.reason.cloud") }
    static var signIn: String { LocalizationManager.localizedAppString("account.reason.signIn") }
}

/// Work to run once per signed-in user: the Trial grant first, then pushing the Guest's local
/// meetings before the first pull. `syncFromServer` already pushes before it pulls.
@MainActor
final class AccountSetup {
    static let shared = AccountSetup()

    private var current: (userID: UUID, task: Task<Void, Never>)?

    private init() {}

    /// Runs the setup for `userID`, or waits for the run already in progress. Safe to call from
    /// several places: each user is set up once until `reset()`.
    func run(userID: UUID, modelContext: ModelContext) async {
        if let current, current.userID == userID {
            await current.task.value
            return
        }

        let task = Task { @MainActor in
            var succeeded = await MinutesManager.shared.handleAppLaunch()

            // A purchase or renewal that arrived while this device had no Account is credited now
            await StoreManager.shared.reprocessUnfinishedTransactions()

            do {
                // A sync that was skipped because another one was running did not push anything
                if try await MeetingSyncService.shared.syncFromServer(modelContext: modelContext) == false {
                    succeeded = false
                }
            } catch {
                // Sync failures stay silent; local data is still there
                print("⚠️ [AccountSetup] Sync failed: \(error.localizedDescription)")
                succeeded = false
            }
            // Forget a failed run (for example offline at sign-up) so the next call retries it
            if !succeeded, self.current?.userID == userID { self.current = nil }
        }
        current = (userID, task)
        await task.value
    }

    /// Call on sign-out so the next account on this device is set up from scratch.
    func reset() {
        current = nil
    }
}

/// Shows sign-up (or sign-in) in a sheet and, once the user has an Account and its setup has
/// finished, runs the action they started.
private struct AccountSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let startInSignUp: Bool
    let reason: String
    let onSignedIn: () -> Void

    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            LoginView(
                authManager: .shared,
                startInSignUp: startInSignUp,
                reason: reason,
                onAuthenticated: { _ in
                    isPresented = false
                    Task {
                        if let userID = AuthenticationManager.shared.currentUser?.id {
                            await AccountSetup.shared.run(userID: userID, modelContext: modelContext)
                        }
                        onSignedIn()
                    }
                },
                onClose: { isPresented = false }
            )
            .onAppear {
                // The sign-in entry in Settings is not a Cloud trial prompt
                if startInSignUp { AnalyticsService.track(.cloudTrialPromptShown) }
            }
        }
    }
}

extension View {
    /// Presents the Account sheet when `isPresented` is true. `onSignedIn` runs after the Trial
    /// grant and the local meeting push, so a Cloud action can continue with a funded balance.
    func accountSheet(
        isPresented: Binding<Bool>,
        startInSignUp: Bool = true,
        reason: String = AccountReason.cloud,
        onSignedIn: @escaping () -> Void = {}
    ) -> some View {
        modifier(AccountSheetModifier(
            isPresented: isPresented,
            startInSignUp: startInSignUp,
            reason: reason,
            onSignedIn: onSignedIn
        ))
    }
}

/// Shows `content` to Account holders and the sign-up screen to Guests. Used inside sheets that are
/// Cloud-only, such as the paywalls, so the sheet turns into the content once the Account exists.
struct AccountRequired<Content: View>: View {
    @ObservedObject private var authManager = AuthenticationManager.shared
    @Environment(\.dismiss) private var dismiss

    var dismissible: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        if authManager.isAuthenticated {
            content()
        } else {
            LoginView(
                authManager: authManager,
                startInSignUp: true,
                reason: AccountReason.cloud,
                onClose: dismissible ? { dismiss() } : nil
            )
            .onAppear { AnalyticsService.track(.cloudTrialPromptShown) }
        }
    }
}
