//
//  MeetingAnalysisProvider.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation

protocol MeetingAnalysisProvider {
    func generateOverview(transcript: String, languageContext: AnalysisLanguageContext) async throws -> String
    func generateSummary(transcript: String, languageContext: AnalysisLanguageContext) async throws -> String
}
