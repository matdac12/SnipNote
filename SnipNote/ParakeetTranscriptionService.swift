import Foundation
import FluidAudio

actor ParakeetTranscriptionService {
  static let shared = ParakeetTranscriptionService()
  static let redux = ParakeetTranscriptionService(store: ParakeetModelStore(model: .parakeetRedux))

  static func service(for model: LocalTranscriptionModel) -> ParakeetTranscriptionService {
    model == .parakeetUltra ? shared : redux
  }

  private var version: AsrModelVersion { store.model == .parakeetUltra ? .ultra : .redux }

  private let store: ParakeetModelStore
  private var isDownloading = false
  private var activeSessions = 0

  init(store: ParakeetModelStore = ParakeetModelStore()) {
    self.store = store
  }

  nonisolated static func languageHint(for code: String?) throws -> Language? {
    guard let code, !code.isEmpty else { return nil }
    let normalized = code.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? code
    let supported = Set(["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk"])
    guard supported.contains(normalized), let language = Language(rawValue: normalized) else {
      throw LocalTranscriptionError.unsupportedParakeetLanguage(code)
    }
    return language
  }

  func status() -> LocalModelStatus { store.isInstalled ? .installed : .notInstalled }

  nonisolated static func prepareChunkSamples(_ samples: [Float]) throws -> [Float] {
    guard !samples.isEmpty else { throw LocalTranscriptionError.emptyTranscript }
    // FluidAudio rejects less than 0.3 seconds, even for the final remainder.
    guard samples.count < 4_800 else { return samples }
    return samples + [Float](repeating: 0, count: 4_800 - samples.count)
  }

  func downloadModel(statusHandler: @escaping @Sendable (LocalModelStatus) -> Void) async throws {
    guard !isDownloading, activeSessions == 0 else { throw LocalTranscriptionError.modelBusy }
    isDownloading = true
    defer { isDownloading = false }
    try store.prepareDirectories()
    statusHandler(.downloading(0))
    // The SDK resumes interrupted byte transfers in this staging directory.
    try await ModelHub.download(store.model == .parakeetUltra ? .parakeetUltra : .parakeetRedux, to: store.stagingRootDirectory) { progress in
      switch progress.phase {
      case .listing, .downloading:
        statusHandler(.downloading(min(1, progress.fractionCompleted * 2)))
      case .compiling:
        statusHandler(.verifying)
      }
    }
    try Task.checkCancellation()
    statusHandler(.verifying)
    guard store.isComplete(at: store.stagedModelDirectory) else { throw LocalTranscriptionError.downloadIncomplete }
    let directory = store.stagedModelDirectory
    let modelVersion = version
    // loadLocal never downloads or repairs files. Verify on the destination device
    // before writing the installed marker; keep Core ML preparation off the UI actor.
    _ = try await Task.detached(priority: .userInitiated) {
      try AsrModels.loadLocal(from: directory, version: modelVersion)
    }.value
    try Task.checkCancellation()
    try store.installDownloadedModel()
  }

  func deleteModel() throws {
    guard !isDownloading, activeSessions == 0 else { throw LocalTranscriptionError.modelBusy }
    try store.deleteModel()
  }

  func makeSession() async throws -> AsrManager {
    guard !isDownloading else { throw LocalTranscriptionError.modelBusy }
    guard store.isInstalled else { throw LocalTranscriptionError.modelNotInstalled(store.model) }
    activeSessions += 1
    do {
      let directory = store.installedModelDirectory
      let modelVersion = version
      let models = try await Task.detached(priority: .userInitiated) {
        try AsrModels.loadLocal(from: directory, version: modelVersion)
      }.value
      try Task.checkCancellation()
      // Each job gets a separate decoder state; simultaneous jobs cannot mix text.
      return AsrManager(config: .default, models: models)
    } catch {
      activeSessions -= 1
      throw error
    }
  }

  func finishSession(_ session: AsrManager) async {
    await session.cleanup()
    activeSessions -= 1
  }
}
