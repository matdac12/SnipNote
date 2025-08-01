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
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Image(systemName: "note.text")
                    .font(.system(size: 60))
                    .foregroundColor(themeManager.currentTheme.accentColor)
                
                Text("SNIPNOTE")
                    .font(.system(.largeTitle, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.textColor)
                
                Text(isSignUp ? "Create Account" : "Sign In")
                    .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
            }
            .padding(.top, 60)
            
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "EMAIL" : "Email")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                    
                    TextField("", text: $email)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .padding()
                        .background(themeManager.currentTheme.secondaryBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                                .stroke(themeManager.currentTheme.secondaryTextColor.opacity(0.3), lineWidth: 1)
                        )
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "PASSWORD" : "Password")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                    
                    SecureField("", text: $password)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .padding()
                        .background(themeManager.currentTheme.secondaryBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                                .stroke(themeManager.currentTheme.secondaryTextColor.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 30)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .themedCaption()
                    .foregroundColor(themeManager.currentTheme.destructiveColor)
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
                                .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.backgroundColor))
                                .scaleEffect(0.8)
                        } else {
                            Text(isSignUp ? (themeManager.currentTheme.headerStyle == .brackets ? "CREATE ACCOUNT" : "Create Account") : (themeManager.currentTheme.headerStyle == .brackets ? "SIGN IN" : "Sign In"))
                                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.currentTheme.accentColor)
                    .foregroundColor(themeManager.currentTheme.backgroundColor)
                    .cornerRadius(themeManager.currentTheme.cornerRadius)
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
                        .themedCaption()
                        .foregroundColor(themeManager.currentTheme.accentColor)
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
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