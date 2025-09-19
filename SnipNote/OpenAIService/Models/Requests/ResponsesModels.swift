//
//  ResponsesModels.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

struct ResponsesRequest: Codable {
    let model: String
    let prompt: ResponsesPrompt
    var input: [ResponseInputItem]
    let conversation: String
    let text: ResponseTextConfig
    let reasoning: ResponseReasoningConfig
    var tools: [ResponseTool]?
}

struct ResponsesPrompt: Codable {
    let id: String
    let variables: ResponsesPromptVariables
}

struct ResponsesPromptVariables: Codable {
    let meetingOverview: String
    let meetingSummary: String

    enum CodingKeys: String, CodingKey {
        case meetingOverview = "meeting_overview"
        case meetingSummary = "meeting_summary"
    }
}

struct ResponseInputItem: Codable {
    let role: String
    let content: [ResponseInputContent]
}

struct ResponseInputContent: Codable {
    let type: String
    let text: String?

    init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}

struct ResponseTool: Codable {
    let type: String
    let vectorStoreIds: [String]
    let maxNumResults: Int

    enum CodingKeys: String, CodingKey {
        case type
        case vectorStoreIds = "vector_store_ids"
        case maxNumResults = "max_num_results"
    }
}

struct ResponseTextConfig: Codable {
    let format: ResponseTextFormat
    let verbosity: String
}

struct ResponseTextFormat: Codable {
    let type: String
}

struct ResponseReasoningConfig: Codable {
    let effort: String
}