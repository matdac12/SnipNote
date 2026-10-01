import Foundation

@MainActor final class BackgroundUploadRouting {
  enum Route { case legacy, background }
  private let settings: BackgroundUploadSettings
  private let capabilities: () async throws -> UploadCapabilities
  private let hasExisting: () -> Bool
  private let startBackground: () async throws -> Void
  private let onLegacySelected: () -> Void
  private let recover: () async -> Void
  init(settings: BackgroundUploadSettings, capabilities: @escaping () async throws -> UploadCapabilities,
       hasExisting: @escaping () -> Bool, startBackground: @escaping () async throws -> Void, recover: @escaping () async -> Void, onLegacySelected: @escaping () -> Void = {}) {
    self.onLegacySelected = onLegacySelected
    self.settings = settings; self.capabilities = capabilities
    self.hasExisting = hasExisting; self.startBackground = startBackground; self.recover = recover
  }
  func start() async throws -> Route {
    if hasExisting() { await recover(); return .background }
    let enabled: Bool
    do { enabled = try await capabilities().backgroundUploadEnabled }
    catch BackgroundUploadFailure.accountMismatch { throw BackgroundUploadFailure.accountMismatch }
    catch { onLegacySelected(); return .legacy }
    settings.serverOffered = enabled
    guard settings.shouldStartBackgroundUpload(serverEnabled: enabled) else { onLegacySelected(); return .legacy }
    do { try await startBackground(); return .background }
    catch BackgroundUploadFailure.disabled {
      guard !hasExisting() else { throw BackgroundUploadFailure.unavailable }
      onLegacySelected()
      return .legacy
    }
    // All ambiguous failures propagate; none chooses local or legacy processing.
  }
}
