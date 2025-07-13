//
//  LoginView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var isSignUp = false
    
    @ObservedObject var authManager: AuthenticationManager
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Image(systemName: "note.text")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("SNIPNOTE")
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .foregroundColor(.white)
                
                Text(isSignUp ? "Create Account" : "Sign In")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding(.top, 60)
            
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("EMAIL")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundColor(.gray)
                    
                    TextField("", text: $email)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("PASSWORD")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundColor(.gray)
                    
                    SecureField("", text: $password)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 30)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)
                    .padding(.horizontal, 30)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 15) {
                Button(action: {
                    Task {
                        await handleAuth()
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        } else {
                            Text(isSignUp ? "CREATE ACCOUNT" : "SIGN IN")
                                .font(.system(.body, design: .monospaced, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                
                Button(action: {
                    withAnimation {
                        isSignUp.toggle()
                        errorMessage = ""
                    }
                }) {
                    Text(isSignUp ? "Already have an account? Sign in" : "Don't have an account? Sign up")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .preferredColorScheme(.dark)
    }
    
    @MainActor
    private func handleAuth() async {
        isLoading = true
        errorMessage = ""
        
        do {
            if isSignUp {
                try await authManager.signUp(email: email, password: password)
            } else {
                try await authManager.signIn(email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}