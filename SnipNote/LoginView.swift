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
    @State private var showingForgotPassword = false
    @State private var forgotPasswordEmail = ""
    @State private var resetEmailSent = false
    @FocusState private var focusedField: Field?

    @ObservedObject var authManager: AuthenticationManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var localizationManager: LocalizationManager

    enum Field {
        case email
        case password
    }
    
    var body: some View {
        ZStack {
            themeManager.currentTheme.gradient
                .ignoresSafeArea()
            VStack(spacing: 30) {
            VStack(spacing: 10) {
                LoginLogoView(color: themeManager.currentTheme.accentColor)
                
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
                    Text("Email")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                    
                    TextField("", text: $email)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .padding()
                        .background(themeManager.currentTheme.secondaryBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                                .stroke(focusedField == .email ? themeManager.currentTheme.accentColor.opacity(0.6) : themeManager.currentTheme.secondaryTextColor.opacity(0.3), lineWidth: focusedField == .email ? 2 : 1)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)

                    SecureField("", text: $password)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .padding()
                        .background(themeManager.currentTheme.secondaryBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                                .stroke(focusedField == .password ? themeManager.currentTheme.accentColor.opacity(0.6) : themeManager.currentTheme.secondaryTextColor.opacity(0.3), lineWidth: focusedField == .password ? 2 : 1)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .focused($focusedField, equals: .password)
                }

                // Forgot password link (only show on sign in, not sign up)
                if !isSignUp {
                    HStack {
                        Spacer()
                        Button(action: {
                            forgotPasswordEmail = email  // Pre-fill with current email
                            showingForgotPassword = true
                        }) {
                            Text(localizationManager.localizedString("auth.forgotPassword"))
                                .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                                .foregroundColor(themeManager.currentTheme.accentColor)
                        }
                    }
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
            
            VStack(spacing: 18) {
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
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.currentTheme.accentColor)
                    .foregroundColor(themeManager.currentTheme.backgroundColor)
                    .cornerRadius(themeManager.currentTheme.cornerRadius)
                    .shadow(color: themeManager.currentTheme.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                
                VStack(spacing: 6) {
                    let ctaColor = Color.blue
                    Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                        .font(.system(.callout, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                        .transition(.opacity)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isSignUp.toggle()
                            errorMessage = ""
                        }
                    }) {
                        Text(isSignUp ? "Sign in" : "Sign up")
                            .font(.system(.headline, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                            .foregroundColor(ctaColor)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(ctaColor.opacity(themeManager.currentTheme.colorScheme == .dark ? 0.28 : 0.16))
                            )
                            .shadow(color: ctaColor.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(localizationManager.localizedString("auth.resetPassword.title"), isPresented: $showingForgotPassword) {
            TextField(localizationManager.localizedString("auth.resetPassword.emailPlaceholder"), text: $forgotPasswordEmail)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
            Button(localizationManager.localizedString("auth.resetPassword.cancel"), role: .cancel) { }
            Button(localizationManager.localizedString("auth.resetPassword.send")) {
                Task {
                    do {
                        try await authManager.resetPassword(email: forgotPasswordEmail)
                        resetEmailSent = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(localizationManager.localizedString("auth.resetPassword.description"))
        }
        .alert(localizationManager.localizedString("auth.resetPassword.emailSentTitle"), isPresented: $resetEmailSent) {
            Button(localizationManager.localizedString("auth.resetPassword.ok")) { }
        } message: {
            Text(localizationManager.localizedString("auth.resetPassword.emailSent"))
        }
    }

    // MARK: - Animated Logo
    private struct LoginLogoView: View {
        let color: Color
        @State private var isAnimating = false
        
        var body: some View {
            ZStack {
                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: 120, height: 120)
                    .blur(radius: 5)
                    .offset(y: 8)
                    .opacity(0.8)
                
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .scaleEffect(isAnimating ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: isAnimating)
                
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: isAnimating)
                
                Circle()
                    .strokeBorder(AngularGradient(gradient: Gradient(colors: [color.opacity(0.1), color.opacity(0.45), color.opacity(0.1)]), center: .center), lineWidth: 3)
                    .frame(width: 105, height: 105)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: isAnimating)
                
                Image(systemName: "note.text")
                    .font(.system(size: 58, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                    .shadow(color: color.opacity(0.4), radius: 10, x: 0, y: 6)
            }
            .frame(height: 150)
            .onAppear {
                guard !isAnimating else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
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
