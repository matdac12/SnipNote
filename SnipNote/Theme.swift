//
//  Theme.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 01/08/25.
//

import SwiftUI

protocol AppTheme {
    var name: String { get }
    var colorScheme: ColorScheme { get }

    // Colors
    var backgroundColor: Color { get }
    var secondaryBackgroundColor: Color { get }
    var tertiaryBackgroundColor: Color { get }
    var accentColor: Color { get }
    var textColor: Color { get }
    var secondaryTextColor: Color { get }
    var destructiveColor: Color { get }
    var warningColor: Color { get }

    // Typography
    var useMonospacedFont: Bool { get }

    // UI Elements
    var materialStyle: Material { get }
    var cornerRadius: CGFloat { get }
    var gradient: LinearGradient { get }
}

struct LightTheme: AppTheme {
    let name = "Light"
    let colorScheme: ColorScheme = .light

    // Colors
    let backgroundColor = Color(UIColor.systemBackground)
    let secondaryBackgroundColor = Color(UIColor.secondarySystemBackground)
    let tertiaryBackgroundColor = Color(UIColor.tertiarySystemBackground)
    let accentColor = Color(red: 1.0, green: 0.42, blue: 0.21) // #FF6B35 - Nice orange
    let textColor = Color(UIColor.label)
    let secondaryTextColor = Color(UIColor.secondaryLabel)
    let destructiveColor = Color.red
    let warningColor = Color.orange

    // Typography
    let useMonospacedFont = false

    // UI Elements
    let materialStyle: Material = .regular
    let cornerRadius: CGFloat = 12
    let gradient: LinearGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.42, blue: 0.21).opacity(0.1), Color(red: 1.0, green: 0.42, blue: 0.21).opacity(0.05)],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct DarkTheme: AppTheme {
    let name = "Dark"
    let colorScheme: ColorScheme = .dark

    // Colors - Uses system colors that automatically adapt to dark mode
    let backgroundColor = Color(UIColor.systemBackground)
    let secondaryBackgroundColor = Color(UIColor.secondarySystemBackground)
    let tertiaryBackgroundColor = Color(UIColor.tertiarySystemBackground)
    let accentColor = Color(red: 1.0, green: 0.42, blue: 0.21) // #FF6B35 - Same orange as Light
    let textColor = Color(UIColor.label)
    let secondaryTextColor = Color(UIColor.secondaryLabel)
    let destructiveColor = Color.red
    let warningColor = Color.orange

    // Typography - Same as Light theme
    let useMonospacedFont = false

    // UI Elements - Same as Light theme
    let materialStyle: Material = .regular
    let cornerRadius: CGFloat = 12
    let gradient: LinearGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.42, blue: 0.21).opacity(0.1), Color(red: 1.0, green: 0.42, blue: 0.21).opacity(0.05)],
        startPoint: .top,
        endPoint: .bottom
    )
}

enum ThemeType: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"

    var theme: AppTheme {
        switch self {
        case .light:
            return LightTheme()
        case .dark:
            return DarkTheme()
        }
    }
}

// Theme Manager
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @AppStorage("selectedTheme") private var selectedThemeRaw: String = ThemeType.light.rawValue
    
    @Published var currentTheme: AppTheme
    
    var themeType: ThemeType {
        get {
            ThemeType(rawValue: selectedThemeRaw) ?? .light
        }
        set {
            selectedThemeRaw = newValue.rawValue
            currentTheme = newValue.theme
        }
    }
    
    private init() {
        // Initialize currentTheme with default value first
        self.currentTheme = LightTheme()
        
        // Then update it based on stored preference
        if let storedType = ThemeType(rawValue: selectedThemeRaw) {
            self.currentTheme = storedType.theme
        }
    }
}

// View Extensions for Theme
extension View {
    func themed() -> some View {
        self.modifier(ThemedViewModifier())
    }
    
    func themedBackground() -> some View {
        self.background(ThemeManager.shared.currentTheme.backgroundColor)
    }
}

struct ThemedViewModifier: ViewModifier {
    @ObservedObject var themeManager = ThemeManager.shared
    
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .accentColor(themeManager.currentTheme.accentColor)
    }
}

// Helper extensions for themed text
extension Text {
    func themedTitle() -> some View {
        self.modifier(ThemedTitleModifier())
    }
    
    func themedBody() -> some View {
        self.modifier(ThemedBodyModifier())
    }
    
    func themedCaption() -> some View {
        self.modifier(ThemedCaptionModifier())
    }
}

struct ThemedTitleModifier: ViewModifier {
    @ObservedObject var themeManager = ThemeManager.shared
    
    func body(content: Content) -> some View {
        if themeManager.currentTheme.useMonospacedFont {
            content
                .font(.system(.title, design: .monospaced, weight: .bold))
                .foregroundColor(themeManager.currentTheme.accentColor)
        } else {
            content
                .font(.system(.title, design: .default, weight: .bold))
                .foregroundColor(themeManager.currentTheme.textColor)
        }
    }
}

struct ThemedBodyModifier: ViewModifier {
    @ObservedObject var themeManager = ThemeManager.shared
    
    func body(content: Content) -> some View {
        if themeManager.currentTheme.useMonospacedFont {
            content
                .font(.system(.body, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.textColor)
        } else {
            content
                .font(.system(.body, design: .default))
                .foregroundColor(themeManager.currentTheme.textColor)
        }
    }
}

struct ThemedCaptionModifier: ViewModifier {
    @ObservedObject var themeManager = ThemeManager.shared
    
    func body(content: Content) -> some View {
        if themeManager.currentTheme.useMonospacedFont {
            content
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
        } else {
            content
                .font(.system(.caption, design: .default))
                .foregroundColor(themeManager.currentTheme.secondaryTextColor)
        }
    }
}