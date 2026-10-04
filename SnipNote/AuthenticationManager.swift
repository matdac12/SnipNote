//
//  AuthenticationManager.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import Foundation
import SwiftUI
import Supabase
import Combine
import StoreKit

enum AuthenticationError: LocalizedError {
    case emailConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .emailConfirmationRequired:
            return LocalizationManager.localizedAppString("account.error.confirmEmail")
        }
    }
}

@MainActor
class AuthenticationManager: ObservableObject {
    /// Shared so Cloud entry points anywhere in the app can check for an Account without plumbing.
    static let shared = AuthenticationManager()

    /// A Guest has no Account and no session. Local mode never needs one.
    @Published var isAuthenticated = false
    @Published var currentUser: User?

    private var authStateChangeListener: Task<Void, Never>?

    init() {
        // The SDK restores a stored session synchronously, so a returning Account holder is never
        // shown as a Guest while the async session check below runs.
        let storedUser = SupabaseManager.shared.client.auth.currentUser
        isAuthenticated = storedUser != nil
        currentUser = storedUser
        setupAuthListener()
        Task {
            await checkCurrentSession()
        }
    }
    
    deinit {
        authStateChangeListener?.cancel()
    }
    
    private func setupAuthListener() {
        authStateChangeListener = Task {
            for await state in SupabaseManager.shared.client.auth.authStateChanges {
                switch state.event {
                case .signedIn:
                    self.isAuthenticated = true
                    self.currentUser = state.session?.user
                case .signedOut:
                    self.isAuthenticated = false
                    self.currentUser = nil
                    self.resetToGuest()
                case .userUpdated:
                    self.currentUser = state.session?.user
                default:
                    break
                }
            }
        }
    }
    
    func checkCurrentSession() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            self.isAuthenticated = true
            self.currentUser = session.user
        } catch {
            // A failed refresh (for example offline) must not turn an Account holder into a Guest
            guard SupabaseManager.shared.client.auth.currentUser == nil else { return }
            self.isAuthenticated = false
            self.currentUser = nil
            // No stored session: Cloud mode left over from before Guests existed is unusable
            resetToGuest()
        }
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let response = try await SupabaseManager.shared.client.auth.signIn(
                email: email,
                password: password
            )
            self.isAuthenticated = true
            self.currentUser = response.user
        } catch {
            print("Sign in error: \(error)")
            throw error
        }
    }
    
    func signUp(email: String, password: String) async throws {
        do {
            let response = try await SupabaseManager.shared.client.auth.signUp(
                email: email,
                password: password
            )

            // With email confirmation turned on there is no session yet. Treating that user as signed in
            // would leave the UI and the data layer disagreeing, so ask them to confirm and sign in.
            guard response.session != nil else {
                throw AuthenticationError.emailConfirmationRequired
            }

            self.isAuthenticated = true
            self.currentUser = response.user
        } catch {
            print("Sign up error: \(error)")
            throw error
        }
    }
    
    func signOut() async throws {
        do {
            // Sign out of Supabase
            try await SupabaseManager.shared.client.auth.signOut()
            self.isAuthenticated = false
            self.currentUser = nil
            resetToGuest()
        } catch {
            print("Sign out error: \(error)")
            throw error
        }
    }

    /// Cloud mode needs an Account, so a device with no session goes back to free Local mode and
    /// forgets the previous account's balance. Runs for every way a session can end.
    private func resetToGuest() {
        LocalTranscriptionManager.shared.setTranscriptionMode(.local)
        MinutesManager.shared.resetForSignOut()
        AccountSetup.shared.reset()
    }

    func resetPassword(email: String) async throws {
        do {
            try await SupabaseManager.shared.client.auth.resetPasswordForEmail(email)
        } catch {
            print("Reset password error: \(error)")
            throw error
        }
    }
}
