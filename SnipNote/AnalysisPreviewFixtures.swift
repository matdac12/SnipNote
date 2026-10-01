#if DEBUG
import Foundation
import SwiftUI

enum AnalysisPreviewFixtures {
  struct MotionKey: EnvironmentKey { static let defaultValue: Bool? = nil }
  static func input(stage: String, meetingID: UUID, jobID: String?) -> AnalysisPresentationInput {
    var input = AnalysisPresentationInput(meetingID: meetingID)
    switch stage {
    case "local": input.backend = .local; input.processingPhase = .transcribing
    case "legacy": input.processingPhase = .transcribing
    case "complete": input.processingState = .completed
    default:
      if stage != "preparing" {
        var upload = BackgroundUploadManifest(userID: UUID(), meetingID: meetingID, sourceRelativePath: "fixture.m4a", options: .init(provider: "xai", language: nil, duration: 600))
        upload.phase = ["queued", "processing"].contains(stage) ? .queued : stage == "retry" ? .retry : .uploading
        let total: Int64 = 10_000_000
        let sent: Int64 = stage == "upload-half" || stage == "retry" ? total / 2 : stage == "confirming" ? total : 0
        upload.files = [.init(file: .init(index: 0, relativePath: "fixture.m4a", expectedBytes: total, duration: 600, contentType: "audio/mp4", fileExtension: "m4a"), state: stage == "retry" ? .retry : .scheduled, sentBytes: sent)]
        input.upload = upload
      }
      if ["queued", "processing"].contains(stage) {
        input.jobID = jobID
        input.processingPhase = stage == "queued" ? .queued : .transcribing
        input.serverStatus = stage == "queued" ? .pending : .processing
        input.serverStage = stage == "processing" ? "Transcribing audio..." : nil
      }
      if stage == "failed" { input.processingState = .failed }
    }
    return input
  }
}
extension EnvironmentValues {
  var analysisPreviewReduceMotion: Bool? {
    get { self[AnalysisPreviewFixtures.MotionKey.self] }
    set { self[AnalysisPreviewFixtures.MotionKey.self] = newValue }
  }
}
#endif
