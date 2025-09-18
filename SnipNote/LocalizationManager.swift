//
//  LocalizationManager.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 24/10/25.
//

import Foundation

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    static let supportedLanguageCodes: [String] = ["en", "it"]

    @Published private(set) var languageCode: String
    @Published private(set) var locale: Locale

    private let storageKey = "appLanguage"

    private init() {
        let stored = UserDefaults.standard.string(forKey: storageKey) ?? Self.defaultLanguageCode()
        let normalized = Self.normalizedCode(from: stored)
        languageCode = normalized
        locale = Locale(identifier: normalized)
        UserDefaults.standard.set(normalized, forKey: storageKey)
    }

    func setLanguage(code: String) {
        let normalized = Self.normalizedCode(from: code)
        guard normalized != languageCode else { return }
        languageCode = normalized
        locale = Locale(identifier: normalized)
        UserDefaults.standard.set(normalized, forKey: storageKey)
    }

    func localizedString(_ key: String) -> String {
        let bundle = Self.bundle(for: languageCode)
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func defaultLanguageCode() -> String {
        guard let preferred = Locale.preferredLanguages.first else { return "en" }
        return normalizedCode(from: preferred)
    }

    private static func normalizedCode(from string: String) -> String {
        let lower = string.lowercased()
        if lower.hasPrefix("it") { return "it" }
        return "en"
    }

    private static func bundle(for code: String) -> Bundle {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}
