import XCTest

final class AnalysisExperienceUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  private func launch(_ stage: String, language: String = "en", appearance: String = "light") -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["--analysis-preview"]
    app.launchEnvironment["SNIPNOTE_ANALYSIS_STAGE"] = stage
    app.launchEnvironment["SNIPNOTE_ANALYSIS_LANGUAGE"] = language
    app.launchEnvironment["SNIPNOTE_ANALYSIS_APPEARANCE"] = appearance
    app.launch()
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
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
}
