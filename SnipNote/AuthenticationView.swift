//
//  AuthenticationView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import SwiftUI
import StoreKit

struct AuthenticationView: View {
    @StateObject private var authManager = AuthenticationManager()
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var deepLinkAudioURL: URL?
    @Binding var shouldNavigateToActions: Bool
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                ContentView(deepLinkAudioURL: $deepLinkAudioURL, shouldNavigateToActions: $shouldNavigateToActions)
                    .environmentObject(authManager)
                    .environmentObject(themeManager)
                    .task {
                        // Ensure products and subscription status are ready for the paywall
                        await StoreManager.shared.loadProducts()
                        await StoreManager.shared.updateSubscriptionStatus()
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
        .animation(.easeInOut, value: authManager.isAuthenticated)
    }
}

