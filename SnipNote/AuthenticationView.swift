//
//  AuthenticationView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import SwiftUI
import SwiftData
import StoreKit

struct AuthenticationView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authManager = AuthenticationManager()
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var sharedAudioImportRequest: SharedAudioImportRequest?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

    var body: some View {
        Group {
            if authManager.isAuthenticated {
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
            } else {
                LoginView(authManager: authManager)
            }
        }
        .task(id: authManager.currentUser?.id) {
            if let user = authManager.currentUser?.id {
                await BackgroundUploadReconciler.shared.activate(context: modelContext, userID: user)
            } else {
                BackgroundUploadReconciler.shared.stop()
                await BackgroundUploadCoordinator.shared.signOut()
            }
        }
        .animation(.easeInOut, value: authManager.isAuthenticated)
    }
}
