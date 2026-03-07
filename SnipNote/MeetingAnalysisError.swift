//
//  MeetingAnalysisError.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation

enum MeetingAnalysisError: LocalizedError {
    case appleIntelligenceUnavailable(String)
    case appleIntelligenceUnsupportedInThisBuild
    case unsupportedLanguage
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .appleIntelligenceUnavailable(let reason):
            return reason
        case .appleIntelligenceUnsupportedInThisBuild:
            return "Apple Intelligence is unavailable in this build."
        case .unsupportedLanguage:
            return "Apple Intelligence does not support the current app language."
        case .emptyResponse:
            return "The analysis model returned an empty response."
        }
    }
}
