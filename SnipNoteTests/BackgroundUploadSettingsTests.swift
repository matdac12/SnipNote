import Foundation
import Testing
@testable import SnipNote

@MainActor struct BackgroundUploadSettingsTests {
  private func settings() -> BackgroundUploadSettings {
    BackgroundUploadSettings()
  }
  @Test func serverDisabledUsesLegacyUpload() {
    #expect(!settings().shouldStartBackgroundUpload(serverEnabled: false))
  }
  @Test func serverEnabledUsesBackgroundUpload() {
    #expect(settings().shouldStartBackgroundUpload(serverEnabled: true))
  }
}
