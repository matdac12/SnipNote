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
            let availability = model.availability

            // Availability comes before the language check: while Apple Intelligence is off or still
            // preparing, `supportsLocale` can report false, which would hide the retry for a fixable state.
            switch availability {
            case .available:
                break
            case .unavailable(.deviceNotEligible):
                throw MeetingAnalysisError.analysisUnavailable(.deviceNotEligible)
            case .unavailable(.appleIntelligenceNotEnabled):
                throw MeetingAnalysisError.analysisUnavailable(.appleIntelligenceNotEnabled)
            case .unavailable(.modelNotReady):
                throw MeetingAnalysisError.analysisUnavailable(.modelNotReady)
            case .unavailable:
                throw MeetingAnalysisError.analysisUnavailable(.unknown)
            }

            if let languageCode = languageContext.languageCode {
                let locale = Locale(identifier: AnalysisLanguageResolver.localeIdentifier(for: languageCode))
                if !model.supportsLocale(locale) {
                    throw MeetingAnalysisError.analysisUnavailable(.unsupportedLanguage)
                }
            } else if !model.supportsLocale() {
                throw MeetingAnalysisError.analysisUnavailable(.unsupportedLanguage)
            }

            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: prompt)
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !content.isEmpty else {
                throw MeetingAnalysisError.emptyResponse
            }

            return content
        }
        throw MeetingAnalysisError.analysisUnavailable(.osUpdateRequired)
        #else
        throw MeetingAnalysisError.analysisUnavailable(.unknown)
        #endif
    }
}
