//
//  ChatModels.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

struct ChatRequest: Codable {
    let model: String
    let input: [ChatMessage]
    let maxTokens: Int?
    let reasoning: ReasoningConfig?
    let text: TextConfig?

    enum CodingKeys: String, CodingKey {
        case model, input
        case maxTokens = "max_output_tokens"
        case reasoning
        case text
    }
}

struct TextConfig: Codable {
    let verbosity: String
}

struct ReasoningConfig: Codable {
    let effort: String
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}