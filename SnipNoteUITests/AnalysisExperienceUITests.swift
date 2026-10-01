import XCTest

final class AnalysisExperienceUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  private func launch(_ stage: String, language: String = "en", appearance: String = "light", largeText: Bool = false, reduceMotion: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["--analysis-preview"]
    app.launchEnvironment["SNIPNOTE_ANALYSIS_STAGE"] = stage
    app.launchEnvironment["SNIPNOTE_ANALYSIS_LANGUAGE"] = language
    app.launchEnvironment["SNIPNOTE_ANALYSIS_APPEARANCE"] = appearance
    if largeText { app.launchEnvironment["SNIPNOTE_ANALYSIS_LARGE_TEXT"] = "1" }
    if reduceMotion { app.launchEnvironment["SNIPNOTE_ANALYSIS_REDUCE_MOTION"] = "1" }
    app.launch()
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  func testPreparationRequiresOpenAndZeroByteUploadAllowsLeave() {
    let app = launch("preparing")
    XCTAssertTrue(app.staticTexts["Keep SnipNote open for now"].waitForExistence(timeout: 8))
    XCTAssertEqual(app.staticTexts["analysis.stage"].label, "Preparing your audio")
    capture(app, "Preparation — keep open")
    app.buttons["fixture.next"].tap()
    XCTAssertTrue(app.staticTexts["You can leave now"].waitForExistence(timeout: 3))
    XCTAssertTrue((app.staticTexts["analysis.upload.progress"].value as? String)?.contains("0%") == true)
    XCTAssertFalse(app.staticTexts["Overview"].exists)
    capture(app, "Registered upload — zero bytes, safe")
  }
  func testReturnKeepsUploadProgress() {
    let app = launch("upload-half")
    XCTAssertTrue(app.staticTexts["analysis.upload.progress"].waitForExistence(timeout: 8))
    app.buttons["fixture.back"].tap()
    app.buttons["fixture.return"].tap()
    XCTAssertTrue((app.staticTexts["analysis.upload.progress"].value as? String)?.contains("50%") == true)
    XCTAssertTrue(app.staticTexts["You can leave now"].exists)
    capture(app, "Return — measured 50 percent retained")
  }
  func testQueuedThenProcessingDoesNotBecomeUpload() {
    let app = launch("queued")
    XCTAssertTrue(app.staticTexts["Waiting to transcribe"].waitForExistence(timeout: 8))
    capture(app, "Server queue")
    app.buttons["fixture.next"].tap()
    XCTAssertTrue(app.staticTexts["Transcribing your meeting"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["analysis.upload.progress"].exists)
    XCTAssertFalse(app.staticTexts["Uploading your audio"].exists)
    capture(app, "Server processing — queued manifest retained")
  }
  func testRetryRemovesPermissionAndExposesAction() {
    let app = launch("retry")
    let retry = app.buttons["analysis.retry"]
    XCTAssertTrue(retry.waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["You can leave now"].exists)
    XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
    capture(app, "Upload paused — foreground recovery")
  }
  func testItalianSafetyCopy() {
    let app = launch("preparing", language: "it", appearance: "dark")
    XCTAssertTrue(app.staticTexts["Tieni SnipNote aperta per ora"].waitForExistence(timeout: 8))
    app.buttons["fixture.next"].tap()
    XCTAssertTrue(app.staticTexts["Ora puoi uscire dall’app"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Puoi cambiare app o bloccare il telefono. Il caricamento continua."].exists)
    capture(app, "Italian dark — safe at zero bytes")
  }
  func testLegacyAndLocalNeverSayCanLeave() {
    for stage in ["legacy", "local"] {
      let app = launch(stage)
      let keepOpen = stage == "local" ? "Local processing continues while SnipNote stays open." : "Keep SnipNote open for now"
      XCTAssertTrue(app.staticTexts[keepOpen].waitForExistence(timeout: 8))
      XCTAssertFalse(app.staticTexts["You can leave now"].exists)
      capture(app, "\(stage) — keep open")
      app.terminate()
    }
  }
  func testCompletionShowsExistingResults() {
    let app = launch("complete")
    XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["Summary"].exists)
    XCTAssertTrue(app.staticTexts["Transcript"].exists)
    XCTAssertFalse(app.staticTexts["analysis.stage"].exists)
    XCTAssertTrue(app.staticTexts["The team agreed on the next steps."].exists)
    capture(app, "Completed — existing result sections")
  }
  func testLargestTextRetryActionIsReachable() {
    for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
      XCUIDevice.shared.orientation = orientation
      for (language, appearance) in [("en", "light"), ("en", "dark"), ("it", "light"), ("it", "dark")] {
        let app = launch("retry", language: language, appearance: appearance, largeText: true, reduceMotion: true)
        let retry = app.buttons["analysis.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<6 where !retry.isHittable { scroll.swipeUp() }
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertFalse(app.staticTexts["You can leave now"].exists)
        capture(app, "Largest text \(orientation.rawValue) \(language) \(appearance) — retry reachable")
        app.buttons["fixture.next"].tap()
        XCTAssertEqual(app.staticTexts["analysis.guidance.title"].label, language == "it" ? "Tieni SnipNote aperta per ora" : "Keep SnipNote open for now")
        app.buttons["fixture.next"].tap()
        XCTAssertEqual(app.staticTexts["analysis.guidance.title"].label, language == "it" ? "Ora puoi uscire dall’app" : "You can leave now")
        app.terminate()
      }
    }
    XCUIDevice.shared.orientation = .portrait
  }
  func testUploadFailureDoesNotClaimServerProcessing() {
    let app = launch("failed")
    XCTAssertTrue(app.staticTexts["Analysis needs attention"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["On the server"].exists)
    XCTAssertFalse(app.staticTexts["You can leave now"].exists)
    capture(app, "Failed upload — no server claim")
  }
  func testMotionAndStalledProgressWalk() {
    let app = launch("preparing")
    XCTAssertTrue(app.staticTexts["analysis.stage"].waitForExistence(timeout: 8))
    capture(app, "Motion — preparation first frame")
    Thread.sleep(forTimeInterval: 0.6)
    capture(app, "Motion — preparation second frame")
    for stage in ["upload-zero", "upload-half"] {
      app.buttons["fixture.next"].tap()
      capture(app, "Motion — \(stage)")
    }
    let progress = app.staticTexts["analysis.upload.progress"]
    let measured = progress.value as? String
    Thread.sleep(forTimeInterval: 1.2)
    XCTAssertEqual(progress.value as? String, measured)
    capture(app, "Motion — stalled value retained")
    app.buttons["fixture.back"].tap()
    app.buttons["fixture.return"].tap()
    XCTAssertEqual(app.staticTexts["analysis.upload.progress"].value as? String, measured)
    for stage in ["confirming", "queued", "processing", "complete"] {
      app.buttons["fixture.next"].tap()
      capture(app, "Motion — \(stage)")
    }
    XCTAssertTrue(app.staticTexts["Overview"].exists)
    app.terminate()
    let retry = launch("retry")
    retry.buttons["fixture.next"].tap()
    capture(retry, "Motion — retry recovery preparing")
    retry.buttons["fixture.next"].tap()
    XCTAssertTrue(retry.staticTexts["You can leave now"].exists)
    capture(retry, "Motion — reregistered safe")
  }
  func testLayoutAndAccessibilityMatrix() { walkLayoutMatrix() }
  func testLargestTextAndReducedMotionMatrix() { walkLayoutMatrix(largeText: true, reduceMotion: true) }

  private func walkLayoutMatrix(largeText: Bool = false, reduceMotion: Bool = false) {
    let variants: [(String, String)] = [("en", "light"), ("en", "dark"), ("it", "light"), ("it", "dark")]
    let stages = ["preparing", "upload-zero", "upload-half", "confirming", "queued", "processing", "complete"]
    for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
      XCUIDevice.shared.orientation = orientation
      for (language, appearance) in variants {
        let app = launch("preparing", language: language, appearance: appearance, largeText: largeText, reduceMotion: reduceMotion)
        XCTAssertTrue(app.staticTexts["analysis.stage"].waitForExistence(timeout: 8))
        let scroll = app.scrollViews.firstMatch
        XCTAssertGreaterThan(scroll.frame.height, 44, "Analysis must retain usable scrolling space")
        for stage in stages {
          if stage != "complete" {
            let title = app.staticTexts["analysis.stage"]
            XCTAssertTrue(title.exists)
            let guidance = app.staticTexts["analysis.guidance.detail"]
            XCTAssertTrue(guidance.exists)
            XCTAssertLessThanOrEqual(guidance.frame.width, scroll.frame.width)
            for _ in 0..<5 where !guidance.isHittable { scroll.swipeUp() }
            XCTAssertTrue(guidance.isHittable, "Permission detail must be reachable by scrolling")
            XCTAssertFalse(guidance.label.contains("..."))
          } else {
            XCTAssertTrue(app.staticTexts["Overview"].exists)
            XCTAssertFalse(app.staticTexts["analysis.stage"].exists)
          }
          capture(app, "Layout \(orientation.rawValue) \(language) \(appearance) \(stage)")
          if stage != "complete" { app.buttons["fixture.next"].tap() }
        }
        app.terminate()
      }
    }
    XCUIDevice.shared.orientation = .portrait
  }
}
