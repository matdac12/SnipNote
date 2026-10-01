import Foundation
import Testing
@testable import SnipNote

@MainActor struct BackgroundUploadSettingsTests {
  private func settings() -> BackgroundUploadSettings {
    BackgroundUploadSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  }
  @Test func serverDisabledUsesLegacyUpload() {
    #expect(!settings().shouldStartBackgroundUpload(serverEnabled: false))
  }
  @Test func localOptOutUsesLegacyUpload() {
    let setting = settings()
    setting.useLegacyUpload = true
    #expect(!setting.shouldStartBackgroundUpload(serverEnabled: true))
    #expect(!setting.shouldStartBackgroundUpload(serverEnabled: false))
  }
  @Test func serverEnabledAndNoOptOutUsesBackgroundUpload() {
    #expect(settings().shouldStartBackgroundUpload(serverEnabled: true))
  }
}
