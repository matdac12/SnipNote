//
//  MeetingAnalysisError.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation

/// Why Local mode analysis (Apple Intelligence) cannot run. This is not a failure: the free
/// promise on these devices is a transcript only, so the meeting still completes with its
/// transcript and the UI explains what is missing. Raw values are persisted on `Meeting`.
enum AnalysisUnavailableReason: String, Codable, CaseIterable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case unsupportedLanguage
    case modelNotReady
    case osUpdateRequired
    case unknown

    var title: String {
        switch self {
        case .modelNotReady:
            return "Apple Intelligence is getting ready"
        case .deviceNotEligible, .appleIntelligenceNotEnabled, .unsupportedLanguage, .osUpdateRequired, .unknown:
            return "Summaries need Apple Intelligence"
        }
    }

    var message: String {
        switch self {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence, so SnipNote can't write a summary here. Your transcript is saved and free."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off. Turn it on in Settings > Apple Intelligence & Siri to get summaries. Your transcript is saved."
        case .unsupportedLanguage:
            return "Apple Intelligence doesn't support this meeting's language yet, so SnipNote can't write a summary. Your transcript is saved."
        case .modelNotReady:
            return "Apple Intelligence is still getting ready on this device and may be downloading. Your transcript is saved. Try again in a little while."
        case .osUpdateRequired:
            return "Apple Intelligence requires iOS 26 or later. Update iOS to get summaries. Your transcript is saved."
        case .unknown:
            return "Summaries aren't available on this device right now. Your transcript is saved."
        }
    }

    /// Short line for the meetings list.
    var listLabel: String { "Transcript only" }

    /// True when the user can change something so that a retry may succeed.
    var canRetry: Bool {
        switch self {
        case .appleIntelligenceNotEnabled, .modelNotReady, .osUpdateRequired, .unknown:
            return true
        case .deviceNotEligible, .unsupportedLanguage:
            return false
        }
    }
}

enum MeetingAnalysisError: LocalizedError {
    case analysisUnavailable(AnalysisUnavailableReason)
    case emptyResponse

    /// Non-nil when the error means "no Apple Intelligence here" rather than a real failure.
    var unavailableReason: AnalysisUnavailableReason? {
        switch self {
        case .analysisUnavailable(let reason):
            return reason
        case .emptyResponse:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .analysisUnavailable(let reason):
            return reason.message
        case .emptyResponse:
            return "The analysis model returned an empty response."
        }
    }
}
