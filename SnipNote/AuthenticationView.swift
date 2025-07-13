//
//  AuthenticationView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import SwiftUI

struct AuthenticationView: View {
    @StateObject private var authManager = AuthenticationManager()
    @Binding var deepLinkAudioURL: URL?
    @Binding var shouldNavigateToActions: Bool
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                ContentView(deepLinkAudioURL: $deepLinkAudioURL, shouldNavigateToActions: $shouldNavigateToActions)
                    .environmentObject(authManager)
            } else {
                LoginView(authManager: authManager)
            }
        }
        .animation(.easeInOut, value: authManager.isAuthenticated)
    }
}