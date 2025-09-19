//
//  ConversationModels.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

struct ConversationCreateRequest: Codable {
    let metadata: [String: String]?
}