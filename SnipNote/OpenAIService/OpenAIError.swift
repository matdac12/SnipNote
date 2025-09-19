//
//  OpenAIError.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

enum OpenAIError: Error {
    case noAPIKey
    case transcriptionFailed
    case summarizationFailed
    case apiError(String)
    case vectorStoreUnavailable(String)
}