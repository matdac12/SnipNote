//
//  FileUploadModels.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

struct OpenAIFileUploadResponse: Decodable {
    let id: String
    let expiresAt: Int?
}