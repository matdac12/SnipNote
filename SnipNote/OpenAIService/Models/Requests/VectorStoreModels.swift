//
//  VectorStoreModels.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation

struct CreateVectorStoreRequest: Codable {
    let name: String
    let expiresAfter: VectorStoreExpiresAfter

    enum CodingKeys: String, CodingKey {
        case name
        case expiresAfter = "expires_after"
    }
}

struct VectorStoreExpiresAfter: Codable {
    let anchor: String
    let days: Int
}

struct VectorStoreFileRequest: Codable {
    let fileId: String

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
    }
}