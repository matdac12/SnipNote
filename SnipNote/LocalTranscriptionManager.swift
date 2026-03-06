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
            return LocalizationManager.localizedAppString("transcription.mode.cloud")
        case .local:
            return LocalizationManager.localizedAppString("transcription.mode.local")
        }
    }
}

enum LocalTranscriptionModel: String, CaseIterable, Identifiable {
    case base
    case small

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .base:
            return LocalizationManager.localizedAppString("transcription.local.model.base.name")
        case .small:
            return LocalizationManager.localizedAppString("transcription.local.model.small.name")
        }
    }

    var detailText: String {
        switch self {
        case .base:
            return LocalizationManager.localizedAppString("transcription.local.model.base.detail")
        case .small:
            return LocalizationManager.localizedAppString("transcription.local.model.small.detail")
        }
    }

    var approximateSizeDescription: String {
        switch self {
        case .base:
            return "~142 MB"
        case .small:
            return "~466 MB"
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
    case verifying
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
            return LocalizationManager.localizedAppString("transcription.local.status.checking")
        case .notInstalled:
            return LocalizationManager.localizedAppString("transcription.local.status.notInstalled")
        case .downloading(let progress):
            return LocalizationManager.localizedAppString(
                "transcription.local.status.downloading",
                Int64(progress * 100)
            )
        case .verifying:
            return LocalizationManager.localizedAppString("transcription.local.status.verifying")
        case .installed:
            return LocalizationManager.localizedAppString("transcription.local.status.installed")
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
    private var downloadingModels: Set<LocalTranscriptionModel> = []
    private var interruptedModels: Set<LocalTranscriptionModel> = []

    private enum Keys {
        static let transcriptionMode = "localTranscription.mode"
        static let selectedModel = "localTranscription.selectedModel"
        static let downloadInFlightPrefix = "localTranscription.downloadInFlight."
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
            await restoreInterruptedDownloads()
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

    func isBusy(_ model: LocalTranscriptionModel) -> Bool {
        downloadingModels.contains(model)
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
            if downloadingModels.contains(model) || interruptedModels.contains(model) {
                continue
            }

            modelStatuses[model] = .checking
            let status = await service.status(for: model)
            modelStatuses[model] = status
        }
    }

    func download(_ model: LocalTranscriptionModel) async {
        guard !downloadingModels.contains(model) else { return }

        interruptedModels.remove(model)
        downloadingModels.insert(model)
        setInFlightFlag(true, for: model)
        modelStatuses[model] = .downloading(0)

        defer {
            downloadingModels.remove(model)
            setInFlightFlag(false, for: model)
        }

        do {
            try await service.downloadModel(model) { [weak self] status in
                Task { @MainActor in
                    self?.modelStatuses[model] = status
                }
            }

            modelStatuses[model] = .installed
        } catch {
            modelStatuses[model] = .failed(error.localizedDescription)
        }
    }

    func delete(_ model: LocalTranscriptionModel) async {
        guard !downloadingModels.contains(model) else { return }

        interruptedModels.remove(model)
        setInFlightFlag(false, for: model)

        do {
            try await service.deleteModel(model)
            modelStatuses[model] = .notInstalled
        } catch {
            modelStatuses[model] = .failed(error.localizedDescription)
        }
    }

    private func restoreInterruptedDownloads() async {
        for model in LocalTranscriptionModel.allCases where defaults.bool(forKey: inFlightKey(for: model)) {
            setInFlightFlag(false, for: model)

            let status = await service.status(for: model)
            if status.isInstalled {
                interruptedModels.remove(model)
                modelStatuses[model] = .installed
                continue
            }

            interruptedModels.insert(model)
            modelStatuses[model] = .failed(interruptedDownloadMessage())
        }
    }

    private func interruptedDownloadMessage() -> String {
        LocalizationManager.localizedAppString("transcription.local.error.downloadInterrupted")
    }

    private func inFlightKey(for model: LocalTranscriptionModel) -> String {
        Keys.downloadInFlightPrefix + model.rawValue
    }

    private func setInFlightFlag(_ isInFlight: Bool, for model: LocalTranscriptionModel) {
        if isInFlight {
            defaults.set(true, forKey: inFlightKey(for: model))
        } else {
            defaults.removeObject(forKey: inFlightKey(for: model))
        }
    }
}
