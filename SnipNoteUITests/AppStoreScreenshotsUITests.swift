import XCTest

/// Captures the App Store screenshots from the debug screenshot mode (`--screenshot-seed`).
/// Run on a booted simulator with, for example:
///   TEST_RUNNER_SNIPNOTE_SHOTS_DIR=~/Desktop/shots xcodebuild test -scheme SnipNote \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
///     -only-testing:SnipNoteUITests/AppStoreScreenshotsUITests
/// Optional: TEST_RUNNER_SNIPNOTE_SCREENSHOT_THEME (Light/Dark), TEST_RUNNER_SNIPNOTE_SCREENSHOT_LANGUAGE (en/it).
final class AppStoreScreenshotsUITests: XCTestCase {
  private var app: XCUIApplication!
  private var outputDirectory: URL!
  private var language = "en"

  override func setUpWithError() throws {
    continueAfterFailure = true
    let environment = ProcessInfo.processInfo.environment
    guard let directory = environment["SNIPNOTE_SHOTS_DIR"] else {
      throw XCTSkip("Set TEST_RUNNER_SNIPNOTE_SHOTS_DIR to capture App Store screenshots.")
    }
    language = environment["SNIPNOTE_SCREENSHOT_LANGUAGE"] ?? "en"
    outputDirectory = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    app = XCUIApplication()
    app.launchArguments = ["--screenshot-seed", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "it" ? "it_IT" : "en_US"]
    app.launchEnvironment["SNIPNOTE_SCREENSHOT_THEME"] = environment["SNIPNOTE_SCREENSHOT_THEME"] ?? "Dark"
    app.launchEnvironment["SNIPNOTE_SCREENSHOT_LANGUAGE"] = language
  }

  @MainActor
  func testCaptureAppStoreScreenshots() throws {
    app.launch()
    XCTAssertTrue(tab(0).waitForExistence(timeout: 20))
    shot("01-home")

    // Transcriptions list
    tab(1).tap()
    shot("02-transcriptions")

    // Meeting detail
    let roadmap = app.staticTexts["Product Roadmap Q1"].firstMatch
    if roadmap.waitForExistence(timeout: 5) {
      roadmap.tap()
      shot("03-detail")
      app.swipeUp()
      shot("04-detail-scrolled")
      app.swipeUp()
      shot("05-detail-scrolled-more")
      app.buttons["BackButton"].firstMatch.tapIfExists()
    }

    // Search
    let search = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH[c] %@", language == "it" ? "Cerca" : "Search")).firstMatch
    if search.waitForExistence(timeout: 3) {
      search.tap()
      search.typeText("📍 ⏱️ ")
      shot("00-emoji-probe")
      search.clearText()
      search.typeText("budget")
      shot("06-search")
      search.clearText()
      // The keyboard covers the tab bar; Return dismisses it.
      search.typeText("\n")
      if app.keyboards.count > 0 { app.swipeDown(velocity: .fast) }
      Thread.sleep(forTimeInterval: 1)
    }

    // Settings
    tab(2).tap()
    shot("08-settings")
    let menu = app.buttons["settings.transcription.menu"].firstMatch
    if menu.waitForExistence(timeout: 3) {
      menu.tap()
      shot("08b-menu")
      let manage = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@",
                                                    "settings.transcription.manage", language == "it" ? "Gestisci" : "Manage")).firstMatch
      if manage.waitForExistence(timeout: 3) {
        manage.tap()
        shot("09-transcription")
        app.swipeUp()
        shot("09b-transcription-scrolled")
        dismissSheetOrGoBack()
      } else {
        // Close the menu so the rest of the run can continue.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
      }
    }
    let dictation = app.buttons["settings.dictation"].firstMatch
    for _ in 0..<8 where !(dictation.exists && dictation.isHittable) { app.swipeUp() }
    if dictation.exists {
      dictation.tap()
      shot("10-dictation")
      dismissSheetOrGoBack()
    }

    // Recording, last: leaving a running recording asks for confirmation.
    tab(0).tap()
    let record = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", language == "it" ? "Registra" : "Record")).firstMatch
    if record.waitForExistence(timeout: 5) {
      record.tap()
      let name = app.textFields.firstMatch
      if name.waitForExistence(timeout: 3) {
        name.tap()
        name.typeText(language == "it" ? "Riunione settimanale" : "Weekly Team Sync")
        app.keyboards.buttons.element(boundBy: app.keyboards.buttons.count - 1).tapIfExists()
        shot("07-record-setup")
        let start = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", language == "it" ? "Avvia" : "Start")).firstMatch
        if start.waitForExistence(timeout: 3), start.isEnabled {
          start.tap()
          Thread.sleep(forTimeInterval: 8)
          shot("11-recording")
        }
      }
    }
  }

  /// Closes a sheet with a swipe, or pops a pushed screen with the back button.
  private func dismissSheetOrGoBack() {
    let back = app.buttons["BackButton"].exists ? app.buttons["BackButton"].firstMatch : app.navigationBars.buttons.firstMatch
    if back.exists && back.isHittable {
      back.tap()
    } else {
      app.swipeDown(velocity: .fast)
    }
    Thread.sleep(forTimeInterval: 1)
  }

  /// The iPhone tab bar, or on iPad the top tab buttons, which carry the tab's symbol as identifier.
  private func tab(_ index: Int) -> XCUIElement {
    if app.tabBars.firstMatch.exists { return app.tabBars.buttons.element(boundBy: index) }
    return app.buttons[["house.fill", "waveform", "gearshape"][index]].firstMatch
  }

  /// Saves the screen as PNG plus the element tree, for adjusting taps.
  private func shot(_ name: String) {
    Thread.sleep(forTimeInterval: 1.5)
    let png = XCUIScreen.main.screenshot().pngRepresentation
    try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    try? app.debugDescription.write(to: outputDirectory.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
  }
}

private extension XCUIElement {
  func tapIfExists() {
    if exists && isHittable { tap() }
  }

  func clearText() {
    guard let text = value as? String, !text.isEmpty else { return }
    typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count + 2))
  }
}
