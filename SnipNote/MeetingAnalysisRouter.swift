//
//  MeetingAnalysisRouter.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation

final class MeetingAnalysisRouter {
    static let shared = MeetingAnalysisRouter()

    private let openAIProvider = OpenAIMeetingAnalysisProvider()
    private let appleProvider = AppleMeetingAnalysisProvider()

    private init() {}

    func generateOverview(transcript: String, explicitLanguageCode: String?) async throws -> String {
        let providerType = await selectedProviderType()
        let languageContext = AnalysisLanguageResolver.resolve(
            explicitLanguageCode: explicitLanguageCode,
            transcript: transcript
        )
        logLanguageContext(languageContext)
        print("🧠 [AnalysisRouter] Generating overview with \(providerType.displayName)")
        return try await provider(for: providerType).generateOverview(
            transcript: transcript,
            languageContext: languageContext
        )
    }

    func generateSummary(transcript: String, explicitLanguageCode: String?) async throws -> String {
        let providerType = await selectedProviderType()
        let languageContext = AnalysisLanguageResolver.resolve(
            explicitLanguageCode: explicitLanguageCode,
            transcript: transcript
        )
        logLanguageContext(languageContext)
        print("🧠 [AnalysisRouter] Generating summary with \(providerType.displayName)")
        return try await provider(for: providerType).generateSummary(
            transcript: transcript,
            languageContext: languageContext
        )
    }

    func extractActionsIfEnabled(_ transcript: String) async throws -> [ActionItem]? {
        let providerType = await selectedProviderType()
        guard providerType == .openAI else {
            print("🧠 [AnalysisRouter] Skipping action extraction for \(providerType.displayName)")
            return nil
        }

        print("🧠 [AnalysisRouter] Extracting actions with OpenAI")
        return try await OpenAIService.shared.extractActions(transcript)
    }

    func actionsEnabled() async -> Bool {
        (await selectedProviderType()) == .openAI
    }

    func selectedProviderType() async -> MeetingAnalysisProviderType {
        await MainActor.run { MeetingAnalysisManager.shared.selectedProvider }
    }

    func failureDescription(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty || description == "The operation couldn’t be completed." {
            return "AI analysis failed."
        }

        return description
    }

    private func provider(for type: MeetingAnalysisProviderType) -> any MeetingAnalysisProvider {
        switch type {
        case .openAI:
            return openAIProvider
        case .appleIntelligence:
            return appleProvider
        }
    }

    private func logLanguageContext(_ context: AnalysisLanguageContext) {
        let code = context.languageCode ?? "auto"
        let source: String

        switch context.source {
        case .explicitPicker:
            source = "explicit-picker"
        case .transcriptDetection:
            source = "transcript-detection"
        case .none:
            source = "none"
        }

        print("🧠 [AnalysisRouter] Language context code=\(code) source=\(source)")
    }
}
