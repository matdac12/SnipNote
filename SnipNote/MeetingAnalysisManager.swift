//
//  MeetingAnalysisManager.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

enum MeetingAnalysisProviderType: String, CaseIterable, Identifiable {
    case openAI
    case appleIntelligence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .appleIntelligence:
            return "Local"
        }
    }
}

@MainActor
final class MeetingAnalysisManager: ObservableObject {
    static let shared = MeetingAnalysisManager()

    @Published private(set) var selectedProvider: MeetingAnalysisProviderType

    private let defaults: UserDefaults

    private enum Keys {
        static let selectedProvider = "meetingAnalysis.selectedProvider"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedProvider = defaults.string(forKey: Keys.selectedProvider)
            .flatMap(MeetingAnalysisProviderType.init(rawValue:))
            ?? .openAI
    }

    func setSelectedProvider(_ provider: MeetingAnalysisProviderType) {
        selectedProvider = provider
        defaults.set(provider.rawValue, forKey: Keys.selectedProvider)
    }

    var appleIntelligenceStatusText: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if !model.supportsLocale() {
                return "Current app language is not supported."
            }

            switch model.availability {
            case .available:
                return LocalizationManager.localizedAppString("settings.aiAnalysis.appleIntelligenceAvailable")
            case .unavailable(.deviceNotEligible):
                return "This device does not support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence is turned off in Settings."
            case .unavailable(.modelNotReady):
                return "The on-device model is not ready yet."
            case .unavailable(let reason):
                return "Apple Intelligence unavailable: \(String(describing: reason))."
            }
        }
        return "Apple Intelligence requires iOS 26 or later."
        #else
        return "Foundation Models is unavailable in this build."
        #endif
    }
}
