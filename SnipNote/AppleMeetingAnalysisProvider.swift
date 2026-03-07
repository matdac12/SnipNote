//
//  AppleMeetingAnalysisProvider.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppleMeetingAnalysisProvider: MeetingAnalysisProvider {
    func generateOverview(transcript: String, languageContext: AnalysisLanguageContext) async throws -> String {
        try await respond(
            prompt: MeetingAnalysisPrompts.overviewPrompt(transcript: transcript, languageContext: languageContext),
            instructions: MeetingAnalysisPrompts.overviewInstructions,
            languageContext: languageContext
        )
    }

    func generateSummary(transcript: String, languageContext: AnalysisLanguageContext) async throws -> String {
        try await respond(
            prompt: MeetingAnalysisPrompts.summaryPrompt(transcript: transcript, languageContext: languageContext),
            instructions: MeetingAnalysisPrompts.summaryInstructions,
            languageContext: languageContext
        )
    }

    private func respond(
        prompt: String,
        instructions: String,
        languageContext: AnalysisLanguageContext
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default

            if let languageCode = languageContext.languageCode {
                let locale = Locale(identifier: AnalysisLanguageResolver.localeIdentifier(for: languageCode))
                if !model.supportsLocale(locale) {
                    let languageName = languageContext.languageDisplayName ?? languageCode.uppercased()
                    throw MeetingAnalysisError.appleIntelligenceUnavailable("Apple Intelligence does not support \(languageName) for this analysis.")
                }
            } else if !model.supportsLocale() {
                throw MeetingAnalysisError.unsupportedLanguage
            }

            switch model.availability {
            case .available:
                break
            case .unavailable(.deviceNotEligible):
                throw MeetingAnalysisError.appleIntelligenceUnavailable("This device does not support Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                throw MeetingAnalysisError.appleIntelligenceUnavailable("Apple Intelligence is turned off in Settings.")
            case .unavailable(.modelNotReady):
                throw MeetingAnalysisError.appleIntelligenceUnavailable("Apple Intelligence is not ready yet. Try again in a moment.")
            case .unavailable(let reason):
                throw MeetingAnalysisError.appleIntelligenceUnavailable("Apple Intelligence is unavailable: \(String(describing: reason)).")
            }

            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: prompt)
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !content.isEmpty else {
                throw MeetingAnalysisError.emptyResponse
            }

            return content
        }
        throw MeetingAnalysisError.appleIntelligenceUnsupportedInThisBuild
        #else
        throw MeetingAnalysisError.appleIntelligenceUnsupportedInThisBuild
        #endif
    }
}
