//
//  AuthenticationView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import SwiftUI
import SwiftData
import StoreKit

/// App root. There is no login wall: a Guest uses Local mode straight away and an Account is
/// created the first time they enter Cloud mode (see `AccountGate.swift`).
struct AuthenticationView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var authManager = AuthenticationManager.shared
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var sharedAudioImportRequest: SharedAudioImportRequest?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ContentView(sharedAudioImportRequest: $sharedAudioImportRequest)
            .environmentObject(authManager)
            .environmentObject(themeManager)
            .task {
                // Ensure products and subscription status are ready for the paywall
                await StoreManager.shared.loadProducts()
                await StoreManager.shared.updateSubscriptionStatus()
                await MinutesManager.shared.handleAppLaunch()
            }
            .onAppear {
                // Show onboarding if user hasn't completed it yet
                if !hasCompletedOnboarding {
                    showingOnboarding = true
                }
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView()
                    .environmentObject(themeManager)
            }
            .task(id: authManager.currentUser?.id) {
                if let user = authManager.currentUser?.id {
                    await BackgroundUploadReconciler.shared.activate(context: modelContext, userID: user)
                    await AccountSetup.shared.run(userID: user, modelContext: modelContext)
                } else {
                    BackgroundUploadReconciler.shared.stop()
                    await BackgroundUploadCoordinator.shared.signOut()
                    AccountSetup.shared.reset()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // A setup that failed (for example offline at sign-up) retries when the app returns;
                // one that already succeeded for this user returns immediately.
                guard phase == .active, let user = authManager.currentUser?.id else { return }
                Task { await AccountSetup.shared.run(userID: user, modelContext: modelContext) }
            }
    }
}
