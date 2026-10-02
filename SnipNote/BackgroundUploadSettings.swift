import Combine
import Foundation

@MainActor final class BackgroundUploadSettings: ObservableObject {
  static let shared = BackgroundUploadSettings()
  func shouldStartBackgroundUpload(serverEnabled: Bool) -> Bool {
    serverEnabled
  }
}
