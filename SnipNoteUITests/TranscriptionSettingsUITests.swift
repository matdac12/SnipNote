import XCTest

final class TranscriptionSettingsUITests: XCTestCase {
  @MainActor
  func testParakeetUltraCanBeSelectedAndPersistsAfterRelaunch() throws {
    try verifyModelSelectionPersists("parakeetUltra")
  }

  @MainActor
  func testParakeetReduxCanBeSelectedAndPersistsAfterRelaunch() throws {
    try verifyModelSelectionPersists("parakeetRedux")
  }

  @MainActor
  private func verifyModelSelectionPersists(_ model: String) throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let settingsTab = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Settings", "Impostazioni"])).firstMatch
    guard settingsTab.waitForExistence(timeout: 15) else {
      throw XCTSkip("Requires a signed-in test account with onboarding completed on this simulator.")
    }
    settingsTab.tap()
    openTranscriptionSettings(app)
    let mode = app.segmentedControls["settings.transcription.mode"]
    XCTAssertTrue(mode.waitForExistence(timeout: 5))
    let local = mode.buttons.matching(NSPredicate(format: "label IN %@", ["Local", "Locale"])).firstMatch
    let wasLocal = local.isSelected
    local.tap()
    let previousModel = ["parakeetUltra", "parakeetRedux"].first {
      let button = app.buttons["settings.localTranscription.select.\($0)"]
      return button.exists && !button.isEnabled
    }
    defer {
      if let previousModel {
        let previous = app.buttons["settings.localTranscription.select.\(previousModel)"]
        for _ in 0..<8 where !previous.isHittable { app.swipeDown() }
        if previous.isEnabled && previous.isHittable { previous.tap() }
      }
      if !wasLocal {
        for _ in 0..<8 where !mode.isHittable { app.swipeDown() }
        mode.buttons["Cloud"].tap()
      }
    }
    let ultra = app.buttons["settings.localTranscription.select.\(model)"]
    for _ in 0..<8 where !ultra.isHittable { app.swipeUp() }
    XCTAssertTrue(ultra.waitForExistence(timeout: 5))
    if ultra.isEnabled { ultra.tap() }
    XCTAssertFalse(ultra.isEnabled)
    app.terminate()
    app.launch()
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 15))
    settingsTab.tap()
    openTranscriptionSettings(app)
    for _ in 0..<10 where !ultra.isHittable { app.swipeUp() }
    XCTAssertTrue(ultra.waitForExistence(timeout: 5))
    XCTAssertFalse(ultra.isEnabled)
  }

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
    openTranscriptionSettings(app)
    let mode = app.segmentedControls["settings.transcription.mode"]
    XCTAssertTrue(mode.waitForExistence(timeout: 5))
    let cloud = mode.buttons["Cloud"]
    let wasLocal = mode.buttons.matching(NSPredicate(format: "label IN %@", ["Local", "Locale"])).firstMatch.isSelected
    cloud.tap()
    let openAI = app.buttons["settings.cloudTranscription.provider.openai"]
    let xAI = app.buttons["settings.cloudTranscription.provider.xai"]
    XCTAssertTrue(xAI.waitForExistence(timeout: 5))
    XCTAssertTrue(openAI.exists)
    let previousProvider = xAI.isSelected ? xAI : openAI
    let nextProvider = xAI.isSelected ? openAI : xAI
    defer {
      if previousProvider.exists {
        previousProvider.tap()
      }
      if wasLocal {
        mode.buttons.matching(NSPredicate(format: "label IN %@", ["Local", "Locale"])).firstMatch.tap()
      }
    }
    nextProvider.tap()
    XCTAssertTrue(nextProvider.isSelected)
    XCTAssertFalse(previousProvider.isSelected)
    XCTAssertGreaterThanOrEqual(nextProvider.frame.height, 44)
    app.terminate()
    app.launch()
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 15))
    settingsTab.tap()
    openTranscriptionSettings(app)
    XCTAssertTrue(nextProvider.waitForExistence(timeout: 5))
    XCTAssertTrue(nextProvider.isSelected)
    let local = mode.buttons.matching(NSPredicate(format: "label IN %@", ["Local", "Locale"])).firstMatch
    local.tap()
    XCTAssertFalse(openAI.exists)
    XCTAssertFalse(xAI.exists)
    cloud.tap()
    XCTAssertTrue(nextProvider.waitForExistence(timeout: 5))
    XCTAssertTrue(nextProvider.isSelected)
  }

  /// Transcription setup lives on its own page, opened from the Transcription menu in Settings.
  @MainActor
  private func openTranscriptionSettings(_ app: XCUIApplication) {
    let menu = app.buttons["settings.transcription.menu"]
    for _ in 0..<6 where !menu.isHittable { app.swipeUp() }
    XCTAssertTrue(menu.waitForExistence(timeout: 5))
    menu.tap()
    let manage = app.buttons["settings.transcription.manage"]
    XCTAssertTrue(manage.waitForExistence(timeout: 5))
    manage.tap()
  }
}
