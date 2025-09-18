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

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    private var authStateChangeListener: Task<Void, Never>?
    
    init() {
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
            self.isAuthenticated = false
            self.currentUser = nil
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
        } catch {
            print("Sign out error: \(error)")
            throw error
        }
    }
}
