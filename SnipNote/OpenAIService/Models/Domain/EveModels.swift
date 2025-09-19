//
//  EveModels.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

struct ChatWithEveResult {
    let responseText: String
    let conversationId: String
}

struct EvePromptVariables {
    let meetingOverview: String
    let meetingSummary: String

    func sanitized() -> EvePromptVariables {
        EvePromptVariables(
            meetingOverview: meetingOverview.isEmpty ? "No overview provided." : meetingOverview,
            meetingSummary: meetingSummary.isEmpty ? "No summary available." : meetingSummary
        )
    }
}