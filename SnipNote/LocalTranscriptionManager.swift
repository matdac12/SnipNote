//
//  LocalTranscriptionManager.swift
//  SnipNote
//
//  Created by Codex on 06/03/26.
//

import Foundation
import Combine

enum TranscriptionMode: String, CaseIterable, Identifiable {
    case cloud
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cloud:
            return "Cloud"
        case .local:
            return "Local"
        }
    }
}

enum LocalTranscriptionModel: String, CaseIterable, Identifiable {
    case tiny
    case base

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny:
            return "Fast"
        case .base:
            return "Balanced"
        }
    }

    var detailText: String {
        switch self {
        case .tiny:
            return "Smallest download, quickest testing."
        case .base:
            return "Better accuracy with a larger download."
        }
    }

    var approximateSizeDescription: String {
        switch self {
        case .tiny:
            return "~75 MB"
        case .base:
            return "~142 MB"
        }
    }

    var whisperVariant: String {
        rawValue
    }
}

enum LocalModelStatus: Equatable {
    case checking
    case notInstalled
    case downloading(Double)
    case installed
    case failed(String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }

        return false
    }

    var statusText: String {
        switch self {
        case .checking:
            return "Checking model files..."
        case .notInstalled:
            return "Not downloaded"
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .installed:
            return "Installed"
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class LocalTranscriptionManager: ObservableObject {
    static let shared = LocalTranscriptionManager()

    @Published private(set) var transcriptionMode: TranscriptionMode
    @Published private(set) var selectedModel: LocalTranscriptionModel
    @Published private(set) var modelStatuses: [LocalTranscriptionModel: LocalModelStatus]

    private let defaults: UserDefaults
    private let service = LocalTranscriptionService.shared

    private enum Keys {
        static let transcriptionMode = "localTranscription.mode"
        static let selectedModel = "localTranscription.selectedModel"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedMode = defaults.string(forKey: Keys.transcriptionMode)
            .flatMap(TranscriptionMode.init(rawValue:))
            ?? .cloud
        let storedModel = defaults.string(forKey: Keys.selectedModel)
            .flatMap(LocalTranscriptionModel.init(rawValue:))
            ?? .base

        transcriptionMode = storedMode
        selectedModel = storedModel
        modelStatuses = Dictionary(
            uniqueKeysWithValues: LocalTranscriptionModel.allCases.map { ($0, .checking) }
        )

        Task {
            await refreshModelStatuses()
        }
    }

    var isLocalModeEnabled: Bool {
        transcriptionMode == .local
    }

    var selectedModelStatus: LocalModelStatus {
        modelStatuses[selectedModel] ?? .checking
    }

    var isSelectedModelInstalled: Bool {
        selectedModelStatus.isInstalled
    }

    func setTranscriptionMode(_ mode: TranscriptionMode) {
        transcriptionMode = mode
        defaults.set(mode.rawValue, forKey: Keys.transcriptionMode)
    }

    func setSelectedModel(_ model: LocalTranscriptionModel) {
        selectedModel = model
        defaults.set(model.rawValue, forKey: Keys.selectedModel)
    }

    func refreshModelStatuses() async {
        for model in LocalTranscriptionModel.allCases {
            modelStatuses[model] = .checking
            let status = await service.status(for: model)
            modelStatuses[model] = status
        }
    }

    func download(_ model: LocalTranscriptionModel) async {
        modelStatuses[model] = .downloading(0)

        do {
            try await service.downloadModel(model) { [weak self] progress in
                Task { @MainActor in
                    self?.modelStatuses[model] = .downloading(progress)
                }
            }

            modelStatuses[model] = .installed
        } catch {
            modelStatuses[model] = .failed(error.localizedDescription)
        }
    }

    func delete(_ model: LocalTranscriptionModel) async {
        do {
            try await service.deleteModel(model)
            modelStatuses[model] = .notInstalled
        } catch {
            modelStatuses[model] = .failed(error.localizedDescription)
        }
    }
}
