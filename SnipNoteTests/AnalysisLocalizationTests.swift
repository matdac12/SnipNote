import Foundation
import Testing
@testable import SnipNote

struct AnalysisLocalizationTests {
  @Test(arguments: ["en", "it"])
  func exactSafetyCopy(language: String) throws {
    let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    let expected = language == "en" ? [
      "analysis.title.preparing": "Preparing your audio",
      "analysis.guidance.keep_open.title": "Keep SnipNote open for now",
      "analysis.guidance.keep_open.detail": "This is brief. We’ll let you know when you can leave.",
      "analysis.guidance.safe.title": "You can leave now",
      "analysis.guidance.upload.detail": "Switch apps or lock your phone. Uploading continues."
    ] : [
      "analysis.title.preparing": "Preparazione dell’audio",
      "analysis.guidance.keep_open.title": "Tieni SnipNote aperta per ora",
      "analysis.guidance.keep_open.detail": "Ci vorrà poco. Ti avviseremo quando potrai uscire.",
      "analysis.guidance.safe.title": "Ora puoi uscire dall’app",
      "analysis.guidance.upload.detail": "Puoi cambiare app o bloccare il telefono. Il caricamento continua."
    ]
    for (key, value) in expected { #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == value) }
    let suffixes = ["phase.preparing", "phase.uploading", "phase.server", "title.preparing", "title.uploading", "title.confirming", "title.queued", "title.transcribing", "title.analyzing", "title.processing", "title.paused", "title.failed", "guidance.keep_open.title", "guidance.keep_open.detail", "guidance.safe.title", "guidance.upload.detail", "guidance.queue.detail", "guidance.server.detail", "guidance.attention.title", "guidance.attention.detail", "action.retry", "progress.accessibility"]
    for suffix in suffixes {
      let key = "analysis." + suffix
      #expect(bundle.localizedString(forKey: key, value: nil, table: nil) != key)
    }
  }
}
