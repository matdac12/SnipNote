//
//  ResponsesResponseModels.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

struct OpenAIResponsesResponse: Decodable {
    let output: [ResponseOutputItem]

    var combinedOutputText: String? {
        let chunks = output.flatMap { $0.messageContent.compactMap { $0.text } }
        guard !chunks.isEmpty else { return nil }
        return chunks.joined()
    }
}

enum ResponseOutputItem: Decodable {
    case message(ResponseMessageOutput)
    case toolCall(ResponseToolCallOutput)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "message":
            let message = try ResponseMessageOutput(from: decoder)
            self = .message(message)
        case "tool_call":
            let toolCall = try ResponseToolCallOutput(from: decoder)
            self = .toolCall(toolCall)
        default:
            self = .other
        }
    }

    var messageContent: [ResponseOutputContent] {
        switch self {
        case .message(let message):
            return message.content
        default:
            return []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}

struct ResponseMessageOutput: Decodable {
    let type: String
    let id: String
    let status: String
    let role: String?
    let content: [ResponseOutputContent]
}

struct ResponseToolCallOutput: Decodable {
    let type: String
}

struct ResponseOutputContent: Decodable {
    let type: String
    let text: String?
    let annotations: [ResponseAnnotation]?
}

struct ResponseAnnotation: Decodable {}