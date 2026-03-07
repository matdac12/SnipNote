//
//  OpenAIMeetingAnalysisProvider.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation

final class OpenAIMeetingAnalysisProvider: MeetingAnalysisProvider {
    private let openAIService = OpenAIService.shared

    func generateOverview(transcript: String, languageContext: AnalysisLanguageContext) async throws -> String {
        try await openAIService.generateMeetingOverview(transcript, languageContext: languageContext)
    }

    func generateSummary(transcript: String, languageContext: AnalysisLanguageContext) async throws -> String {
        try await openAIService.summarizeMeeting(transcript, languageContext: languageContext)
    }
}
