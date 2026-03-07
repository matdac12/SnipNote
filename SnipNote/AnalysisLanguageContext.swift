//
//  AnalysisLanguageContext.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation

struct AnalysisLanguageContext: Sendable {
    enum Source: Sendable {
        case explicitPicker
        case transcriptDetection
        case none
    }

    let languageCode: String?
    let languageDisplayName: String?
    let source: Source

    static let none = AnalysisLanguageContext(
        languageCode: nil,
        languageDisplayName: nil,
        source: .none
    )
}
