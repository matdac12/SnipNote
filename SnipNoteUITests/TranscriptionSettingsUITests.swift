import XCTest

final class TranscriptionSettingsUITests: XCTestCase {
  @MainActor
  func testCloudProviderPersistsAfterRelaunch() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let settingsTab = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Settings", "Impostazioni"])).firstMatch
    guard settingsTab.waitForExistence(timeout: 15) else {
      throw XCTSkip("Requires a signed-in test account with onboarding completed on this simulator.")
    }
    settingsTab.tap()
    let mode = app.segmentedControls["settings.transcription.mode"]
    for _ in 0..<8 where !mode.isHittable { app.swipeUp() }
    XCTAssertTrue(mode.waitForExistence(timeout: 5))
    let cloud = mode.buttons["Cloud"]
    let wasLocal = mode.buttons.matching(NSPredicate(format: "label IN %@", ["Local", "Locale"])).firstMatch.isSelected
    cloud.tap()
    let provider = app.buttons["settings.cloudTranscription.provider"]
    XCTAssertTrue(provider.waitForExistence(timeout: 5))
    let previousProvider = provider.label.contains("xAI") ? "xAI (Grok)" : "OpenAI"
    defer {
      if provider.exists {
        provider.tap()
        app.buttons[previousProvider].firstMatch.tap()
      }
      if wasLocal {
        mode.buttons.matching(NSPredicate(format: "label IN %@", ["Local", "Locale"])).firstMatch.tap()
      }
    }
    provider.tap()
    app.buttons["xAI (Grok)"].firstMatch.tap()
    XCTAssertTrue(provider.label.contains("xAI (Grok)"))
    app.terminate()
    app.launch()
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 15))
    settingsTab.tap()
    for _ in 0..<8 where !mode.isHittable { app.swipeUp() }
    XCTAssertTrue(provider.waitForExistence(timeout: 5))
    XCTAssertTrue(provider.label.contains("xAI (Grok)"))
    let local = mode.buttons.matching(NSPredicate(format: "label IN %@", ["Local", "Locale"])).firstMatch
    local.tap()
    XCTAssertFalse(provider.exists)
    cloud.tap()
    XCTAssertTrue(provider.waitForExistence(timeout: 5))
    XCTAssertTrue(provider.label.contains("xAI (Grok)"))
  }
}
