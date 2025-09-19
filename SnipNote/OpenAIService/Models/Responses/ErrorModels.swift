//
//  ErrorModels.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

struct OpenAIAPIErrorResponse: Codable {
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let message: String
        let type: String?
        let code: String?
    }
}