import Foundation
import Testing
@testable import SnipNote

struct AnalysisAnnouncementTests {
  private func preparing(_ id: UUID) -> AnalysisPresentation { AnalysisPresentationResolver.resolve(.init(meetingID: id)) }
  private func safe(_ id: UUID) -> AnalysisPresentation {
    var upload = BackgroundUploadManifest(userID: UUID(), meetingID: id, sourceRelativePath: "source.m4a", options: .init(provider: "xai", language: nil, duration: 10))
    upload.phase = .uploading
    upload.files = [.init(file: .init(index: 0, relativePath: "audio.m4a", expectedBytes: 100, duration: 10, contentType: "audio/mp4", fileExtension: "m4a"), state: .scheduled)]
    return AnalysisPresentationResolver.resolve(.init(meetingID: id, upload: upload))
  }
  @Test func firstRenderDoesNotAnnounce() {
    var tracker = AnalysisAnnouncementTracker()
    #expect(tracker.update(preparing(UUID())) == nil)
  }
  @Test func handoffAnnouncesOnce() {
    let id = UUID(); var tracker = AnalysisAnnouncementTracker()
    #expect(tracker.update(preparing(id)) == nil)
    #expect(tracker.update(safe(id))?.guidance == .safeUpload)
    #expect(tracker.update(safe(id)) == nil)
  }
  @Test func bytesAndRepeatedPollsDoNotAnnounce() {
    var tracker = AnalysisAnnouncementTracker(); var value = safe(UUID())
    #expect(tracker.update(value) == nil)
    value.sentBytes = 50; value.uploadFraction = 0.5
    #expect(tracker.update(value) == nil)
    #expect(tracker.update(value) == nil)
  }
  @Test func reentrySeedsWithoutAnnouncement() {
    var tracker = AnalysisAnnouncementTracker()
    #expect(tracker.update(safe(UUID())) == nil)
  }
  @Test func retryThenReregisterAnnouncesNewSafety() {
    let id = UUID(); var tracker = AnalysisAnnouncementTracker(); let upload = safe(id)
    #expect(tracker.update(upload) == nil)
    var retry = upload; retry.phase = .pausedUpload; retry.guidance = .needsAttention
    #expect(tracker.update(retry)?.canLeave == false)
    #expect(tracker.update(upload)?.canLeave == true)
  }
  @Test func differentJobSeedsWithoutOldPermission() {
    let id = UUID(); var tracker = AnalysisAnnouncementTracker()
    let one = AnalysisPresentationResolver.resolve(.init(meetingID: id, jobID: "one", serverStatus: .processing))
    let two = AnalysisPresentationResolver.resolve(.init(meetingID: id, jobID: "two", serverStatus: .pending))
    #expect(tracker.update(one) == nil)
    #expect(tracker.update(two) == nil)
    #expect(tracker.update(safe(UUID())) == nil)
  }
  @Test func terminalFailureWithClearedJobAnnouncesOnce() {
    let id = UUID(); var tracker = AnalysisAnnouncementTracker()
    let processing = AnalysisPresentationResolver.resolve(.init(meetingID: id, jobID: "job", serverStatus: .processing))
    #expect(tracker.update(processing) == nil)
    let failed = AnalysisPresentationResolver.resolve(.init(meetingID: id, processingState: .failed))
    #expect(tracker.update(failed)?.phase == .failed)
    #expect(tracker.update(failed) == nil)
  }
  @Test func jobAssignedDuringLiveFlowAnnouncesQueueOnly() {
    let id = UUID(); var tracker = AnalysisAnnouncementTracker(); let uploading = safe(id)
    #expect(tracker.update(uploading) == nil)
    let queued = AnalysisPresentationResolver.resolve(.init(meetingID: id, jobID: "one", serverStatus: .pending))
    #expect(tracker.update(queued)?.phase == .queued)
    #expect(uploading.canLeave && queued.canLeave) // The view adds permission only on false→true.
    #expect(tracker.update(queued) == nil)
  }
}
