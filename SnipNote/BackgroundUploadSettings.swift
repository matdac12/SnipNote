import Combine
import Foundation

@MainActor final class BackgroundUploadSettings: ObservableObject {
  static let shared = BackgroundUploadSettings()
  private let defaults: UserDefaults
  @Published var useLegacyUpload: Bool {
    didSet { defaults.set(useLegacyUpload, forKey: "backgroundUpload.useLegacy") }
  }
  @Published var serverOffered = false
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    useLegacyUpload = defaults.bool(forKey: "backgroundUpload.useLegacy")
  }
  func shouldStartBackgroundUpload(serverEnabled: Bool) -> Bool {
    serverEnabled && !useLegacyUpload
  }
}
