import Foundation
import Testing
@testable import SnipNote

struct AnalysisPresentationTests {
  private func upload(phase: BackgroundUploadPhase = .uploading, sent: Int64 = 0, total: Int64 = 100, registered: Bool = true) -> BackgroundUploadManifest {
    var manifest = BackgroundUploadManifest(userID: UUID(), meetingID: UUID(), sourceRelativePath: "source.m4a", options: .init(provider: "xai", language: nil, duration: 10))
    manifest.phase = phase
    manifest.files = [.init(file: .init(index: 0, relativePath: "audio.m4a", expectedBytes: total, duration: 10, contentType: "audio/mp4", fileExtension: "m4a"), state: registered ? .scheduled : .pending, sentBytes: sent)]
    return manifest
  }
  private func input(_ manifest: BackgroundUploadManifest) -> AnalysisPresentationInput {
    .init(meetingID: manifest.meetingID, upload: manifest)
  }
  @Test func noSnapshotStartsPreparing() {
    let value = AnalysisPresentationResolver.resolve(.init(meetingID: UUID()))
    #expect(value.phase == .preparing && value.guidance == .keepOpen && value.uploadFraction == nil)
  }
  @Test func safeAtZeroBytesOnlyAfterRegistration() {
    var ready = upload()
    let safe = AnalysisPresentationResolver.resolve(input(ready))
    #expect(safe.phase == .uploading && safe.canLeave && safe.uploadFraction == 0)
    ready.files[0].state = .pending
    let waiting = AnalysisPresentationResolver.resolve(input(ready), previous: safe)
    #expect(waiting.phase == .preparing && !waiting.canLeave)
  }
  @Test func allBytesSentMeansConfirmation() {
    let value = AnalysisPresentationResolver.resolve(input(upload(sent: 100)))
    #expect(value.phase == .confirmingUpload && value.guidance == .safeUpload && value.uploadFraction == 1)
  }
  @Test func emptyOrZeroTotalFilesNeverAuthorizeLeaving() {
    var empty = upload(); empty.files = []
    for manifest in [empty, upload(total: 0)] {
      let value = AnalysisPresentationResolver.resolve(input(manifest))
      #expect(!value.canLeave && value.uploadFraction == nil)
    }
  }
  @Test func retryOverridesStaleSafeState() {
    var manifest = upload(sent: 25)
    let safe = AnalysisPresentationResolver.resolve(input(manifest))
    manifest.phase = .retry
    let value = AnalysisPresentationResolver.resolve(.init(meetingID: manifest.meetingID, upload: manifest, canRetry: true), previous: safe)
    #expect(value.phase == .pausedUpload && value.guidance == .needsAttention && value.canRetryUpload && !value.canLeave)
  }
  @Test func localAndForegroundCloudNeverInheritSafety() {
    for backend in [TranscriptionBackend.local, .cloud] {
      let value = AnalysisPresentationResolver.resolve(.init(meetingID: UUID(), backend: backend, processingPhase: .transcribing))
      #expect(value.phase == .foreground && value.guidance == .keepOpen)
    }
  }
  @Test func foreignManifestIsIgnored() {
    #expect(!AnalysisPresentationResolver.resolve(.init(meetingID: UUID(), upload: upload())).canLeave)
  }
  @Test func cancelledManifestDoesNotConferSafety() {
    let value = AnalysisPresentationResolver.resolve(input(upload(phase: .cancelled)))
    #expect(value.guidance == .needsAttention && !value.canLeave)
  }
  @Test func terminalMeetingWins() {
    let manifest = upload()
    let complete = AnalysisPresentationResolver.resolve(.init(meetingID: manifest.meetingID, processingState: .completed, upload: manifest))
    let failed = AnalysisPresentationResolver.resolve(.init(meetingID: manifest.meetingID, processingState: .failed, upload: manifest))
    #expect(complete.phase == .results && complete.guidance == .none)
    #expect(failed.phase == .failed && !failed.canLeave)
  }
  @Test func queuedManifestUsesRunningJob() {
    let manifest = upload(phase: .queued)
    let value = AnalysisPresentationResolver.resolve(.init(meetingID: manifest.meetingID, upload: manifest, serverStatus: .processing, serverStage: "Transcribing audio..."))
    #expect(value.phase == .transcribing && value.guidance == .safeServer)
  }
  @Test func serverFailureWinsQueuedManifest() {
    let manifest = upload(phase: .queued)
    let value = AnalysisPresentationResolver.resolve(.init(meetingID: manifest.meetingID, upload: manifest, serverStatus: .failed))
    #expect(value.phase == .failed && !value.canLeave)
  }
  @Test func remoteCompleteWaitsForAppliedResults() {
    let value = AnalysisPresentationResolver.resolve(.init(meetingID: UUID(), jobID: "job", serverStatus: .completed))
    #expect(value.phase == .processing && value.guidance == .safeServer)
  }
  @Test func statusGapPreservesSameJobOnly() {
    let id = UUID()
    let previous = AnalysisPresentationResolver.resolve(.init(meetingID: id, jobID: "one", serverStatus: .processing, serverStage: "Generating overview"))
    #expect(AnalysisPresentationResolver.resolve(.init(meetingID: id, jobID: "one"), previous: previous).phase == .analyzing)
    #expect(AnalysisPresentationResolver.resolve(.init(meetingID: id, jobID: "two"), previous: previous).phase == .queued)
    #expect(!AnalysisPresentationResolver.resolve(.init(meetingID: id), previous: previous).canLeave)
  }
  @Test func freshReturnUsesPersistedPhase() {
    let value = AnalysisPresentationResolver.resolve(.init(meetingID: UUID(), jobID: "job", processingPhase: .generatingSummary))
    #expect(value.phase == .analyzing && value.guidance == .safeServer)
  }
  @Test func stalledBytesDoNotAdvance() {
    let sample = input(upload(sent: 33))
    let previous = AnalysisPresentationResolver.resolve(sample)
    #expect(AnalysisPresentationResolver.resolve(sample, previous: previous) == previous)
    #expect(previous.uploadFraction == 0.33)
  }
  @Test func malformedProgressIsBounded() {
    #expect(AnalysisPresentationResolver.resolve(input(upload(sent: -20))).uploadFraction == 0)
    #expect(AnalysisPresentationResolver.resolve(input(upload(sent: 200))).uploadFraction == 1)
    #expect(AnalysisPresentationResolver.resolve(input(upload(total: -1))).uploadFraction == nil)
  }
  @Test(arguments: ["Transcribing", "Merging transcripts", "Combining transcripts", "Transcription complete"])
  func knownTranscriptionStages(stage: String) {
    #expect(AnalysisPresentationResolver.serverPhase(status: .processing, stage: "  \(stage.uppercased())... ") == .transcribing)
  }
  @Test(arguments: ["Generating summary", "Summary generated", "Generating overview", "AI content generated"])
  func knownAnalysisStages(stage: String) {
    #expect(AnalysisPresentationResolver.serverPhase(status: .processing, stage: stage) == .analyzing)
  }
  @Test func unknownStageIsGeneric() {
    #expect(AnalysisPresentationResolver.serverPhase(status: .processing, stage: "Internal secret stage") == .processing)
    #expect(AnalysisPresentationResolver.serverPhase(status: .processing, stage: nil) == .processing)
  }
  @MainActor @Test func newServerEntryIsPreparingBeforeManifest() {
    let meeting = Meeting(name: "New")
    meeting.updateProcessingState(.transcribing)
    meeting.transcriptionBackend = .cloud
    meeting.processingPhase = .preparing
    let value = AnalysisPresentationResolver.resolve(.init(meeting: meeting, upload: nil, serverStatus: nil, serverStage: nil))
    #expect(value.phase == .preparing && value.guidance == .keepOpen)
  }

}
