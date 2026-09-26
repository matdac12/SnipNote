//
//  OpenAIError.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

enum OpenAIError: Error {
    case notAuthenticated
    case transcriptionFailed
    case summarizationFailed
    case audioProcessingFailed(String)
    case insufficientDiskSpace(required: UInt64, available: UInt64)
    case apiError(String)
}