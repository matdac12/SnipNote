//
//  LocalizationManager.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 24/10/25.
//

import Foundation

private enum AppLocalization {
    static let storageKey = "appLanguage"

    static func currentLanguageCode() -> String {
        let stored = UserDefaults.standard.string(forKey: storageKey) ?? defaultLanguageCode()
        return normalizedCode(from: stored)
    }

    static func localizedString(_ key: String) -> String {
        let bundle = bundle(for: currentLanguageCode())
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func localizedString(_ key: String, arguments: [CVarArg]) -> String {
        let format = localizedString(key)
        let locale = Locale(identifier: currentLanguageCode())
        return String(format: format, locale: locale, arguments: arguments)
    }

    static func defaultLanguageCode() -> String {
        guard let preferred = Locale.preferredLanguages.first else { return "en" }
        return normalizedCode(from: preferred)
    }

    static func normalizedCode(from string: String) -> String {
        let lower = string.lowercased()
        if lower.hasPrefix("it") { return "it" }
        return "en"
    }

    static func bundle(for code: String) -> Bundle {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    static let supportedLanguageCodes: [String] = ["en", "it"]

    @Published private(set) var languageCode: String
    @Published private(set) var locale: Locale

    private init() {
        let normalized = AppLocalization.currentLanguageCode()
        languageCode = normalized
        locale = Locale(identifier: normalized)
        UserDefaults.standard.set(normalized, forKey: AppLocalization.storageKey)
    }

    func setLanguage(code: String) {
        let normalized = AppLocalization.normalizedCode(from: code)
        guard normalized != languageCode else { return }
        languageCode = normalized
        locale = Locale(identifier: normalized)
        UserDefaults.standard.set(normalized, forKey: AppLocalization.storageKey)
    }

    func localizedString(_ key: String) -> String {
        Self.localizedAppString(key)
    }

    nonisolated static func localizedAppString(_ key: String) -> String {
        AppLocalization.localizedString(key)
    }

    nonisolated static func localizedAppString(_ key: String, _ arguments: CVarArg...) -> String {
        localizedAppString(key, arguments: arguments)
    }

    nonisolated static func localizedAppString(_ key: String, arguments: [CVarArg]) -> String {
        AppLocalization.localizedString(key, arguments: arguments)
    }

    nonisolated static func currentLanguageCode() -> String {
        AppLocalization.currentLanguageCode()
    }
}
