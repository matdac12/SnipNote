//
//  AnalysisLanguageResolver.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation
import NaturalLanguage

enum AnalysisLanguageResolver {
    static func resolve(
        explicitLanguageCode: String?,
        transcript: String
    ) -> AnalysisLanguageContext {
        if let explicitLanguageCode,
           let normalizedCode = normalizedLanguageCode(from: explicitLanguageCode) {
            return AnalysisLanguageContext(
                languageCode: normalizedCode,
                languageDisplayName: displayName(for: normalizedCode),
                source: .explicitPicker
            )
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(transcript)

        if let dominantLanguage = recognizer.dominantLanguage,
           let normalizedCode = normalizedLanguageCode(from: dominantLanguage.rawValue) {
            return AnalysisLanguageContext(
                languageCode: normalizedCode,
                languageDisplayName: displayName(for: normalizedCode),
                source: .transcriptDetection
            )
        }

        return .none
    }

    static func displayName(for languageCode: String) -> String {
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: languageCode)?
            .capitalized(with: locale)
            ?? languageCode.uppercased()
    }

    static func localeIdentifier(for languageCode: String) -> String {
        switch languageCode.lowercased() {
        case "it":
            return "it_IT"
        case "en":
            return "en_US"
        default:
            return languageCode
        }
    }

    static func normalizedLanguageCode(from rawValue: String) -> String? {
        let normalized = rawValue.lowercased()

        if normalized.hasPrefix("it") {
            return "it"
        }

        if normalized.hasPrefix("en") {
            return "en"
        }

        guard let languageCode = Locale(identifier: rawValue).language.languageCode?.identifier
            ?? Locale.Language(identifier: rawValue).languageCode?.identifier else {
            return nil
        }

        return languageCode.lowercased()
    }
}
