//
//  ChatResponseModels.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

struct ChatResponse: Codable {
    let output: [ResponseOutput]
}

struct ResponseOutput: Codable {
    let type: String
    let content: [ResponseContent]?  // Optional because reasoning type doesn't have content
}

struct ResponseContent: Codable {
    let type: String
    let text: String
}

// Helper to extract text from nested structure
extension ChatResponse {
    var outputText: String {
        // Find the first output item with type "message" that has content
        guard let messageOutput = output.first(where: { $0.type == "message" }),
              let content = messageOutput.content?.first else {
            return ""
        }
        return content.text
    }
}