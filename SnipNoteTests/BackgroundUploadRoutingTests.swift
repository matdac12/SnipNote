import Foundation
import SwiftData
import Testing
@testable import SnipNote

@MainActor struct BackgroundUploadRoutingTests {
  private func router(enabled: Bool?, existing: Bool = false, optOut: Bool = false, failure: BackgroundUploadFailure? = nil, starts: @escaping () -> Void = {}) -> BackgroundUploadRouting {
    let settings = BackgroundUploadSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    settings.useLegacyUpload = optOut
    return BackgroundUploadRouting(settings: settings, capabilities: {
      guard let enabled else { throw BackgroundUploadFailure.unavailable }
      return UploadCapabilities(backgroundUploadEnabled: enabled)
    }, hasExisting: { existing }, startBackground: {
      starts()
      if let failure { throw failure }
    }, recover: { starts() })
  }
  @Test func flagOffKeepsLegacyBootstrap() async throws {
    #expect(try await router(enabled: false).start() == .legacy)
  }
  @Test func flagOnStartsCoordinator() async throws {
    var calls = 0
    #expect(try await router(enabled: true, starts: { calls += 1 }).start() == .background)
    #expect(calls == 1)
  }
  @Test func unavailableCapabilitiesUseLegacyForNewUpload() async throws {
    #expect(try await router(enabled: nil).start() == .legacy)
  }
  @Test func disabledBootstrapBeforeSessionCreationUsesLegacy() async throws {
    #expect(try await router(enabled: true, failure: .disabled).start() == .legacy)
  }
  @Test func flagOffOrOptOutDoesNotDuplicateExistingSession() async throws {
    for optOut in [true, false] {
      var recoveries = 0
      #expect(try await router(enabled: false, existing: true, optOut: optOut, starts: { recoveries += 1 }).start() == .background)
      #expect(recoveries == 1)
    }
  }
  @Test func capabilityAuthenticationFailureDoesNotFallBack() async throws {
    let settings = BackgroundUploadSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let router = BackgroundUploadRouting(settings: settings, capabilities: { throw BackgroundUploadFailure.accountMismatch }, hasExisting: { false }, startBackground: {}, recover: {})
    await #expect(throws: BackgroundUploadFailure.self) { try await router.start() }
  }
  @Test func networkFailureDoesNotStartLocalFallback() async throws {
    await #expect(throws: BackgroundUploadFailure.self) { try await router(enabled: true, failure: .unavailable).start() }
    #expect(!BackgroundUploadReconciler.permitsLocalFallback(remoteStatus: nil, activeUpload: true))
    #expect(!BackgroundUploadReconciler.permitsLocalFallback(remoteStatus: .processing, activeUpload: false))
    #expect(BackgroundUploadReconciler.permitsLocalFallback(remoteStatus: .failed, activeUpload: false))
  }
  private func result(user: UUID, meeting: UUID, job: UUID) -> JobStatusResponse {
    JobStatusResponse(id: job.uuidString, userId: user.uuidString, meetingId: meeting.uuidString, audioUrl: nil, status: .completed, transcript: "Recorded words", overview: "Overview", summary: "Summary", duration: 10, errorMessage: nil, progressPercentage: 100, currentStage: "Complete", createdAt: "", updatedAt: "", completedAt: nil)
  }
  @Test func reopeningRestoresJobAndResultWithoutDetailView() async throws {
    let container = try ModelContainer(for: Meeting.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let user = UUID(), job = UUID()
    let meeting = Meeting(name: "Fixture")
    meeting.updateProcessingState(.transcribing)
    meeting.transcriptionBackend = .cloud
    context.insert(meeting)
    let store = BackgroundUploadStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let transport = UploadFakeTransport(), api = UploadFakeAPI()
    var manifest = BackgroundUploadManifest(userID: user, meetingID: meeting.id, sourceRelativePath: "source.m4a", options: UploadOptions(provider: "xai", language: "it", duration: 10))
    manifest.sessionID = api.reply.sessionId;manifest.jobID = job;manifest.phase = .queued
    try store.save(manifest)
    api.reply.status = "queued";api.reply.jobId = job
    let coordinator = BackgroundUploadCoordinator(api: api, store: store, transport: transport, identity: { user }, ensureMeeting: { _, _ in })
    await coordinator.recover(userID: user)
    let status = result(user: user, meeting: meeting.id, job: job)
    let reconciler = BackgroundUploadReconciler(coordinator: coordinator, status: { _ in status }, identity: { user }, sync: { _ in })
    await reconciler.reconcile(context: context, userID: user)
    #expect(meeting.audioTranscript == "Recorded words")
    #expect(meeting.processingState == .completed)
    #expect(coordinator.snapshots[meeting.id]?.phase == .completed)
    meeting.audioTranscript = "User edited"
    await reconciler.reconcile(context: context, userID: user)
    #expect(meeting.audioTranscript == "User edited")
  }
  @Test func resultMetadataSyncFailureRetriesWithoutReapplying() async throws {
    let container = try ModelContainer(for: Meeting.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext, user = UUID(), job = UUID()
    let meeting = Meeting(name: "Sync retry")
    meeting.updateProcessingState(.transcribing)
    context.insert(meeting)
    let store = BackgroundUploadStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let api = UploadFakeAPI(), transport = UploadFakeTransport()
    var manifest = BackgroundUploadManifest(userID: user, meetingID: meeting.id, sourceRelativePath: "source.m4a", options: UploadOptions(provider: "xai", language: "it", duration: 10))
    manifest.sessionID = api.reply.sessionId; manifest.jobID = job; manifest.phase = .queued
    try store.save(manifest)
    api.reply.status = "queued"; api.reply.jobId = job
    let coordinator = BackgroundUploadCoordinator(api: api, store: store, transport: transport, identity: { user }, ensureMeeting: { _, _ in })
    await coordinator.recover(userID: user)
    let status = result(user: user, meeting: meeting.id, job: job)
    var syncs = 0
    let reconciler = BackgroundUploadReconciler(coordinator: coordinator, status: { _ in status }, identity: { user }, sync: { _ in
      syncs += 1
      if syncs == 1 { throw BackgroundUploadFailure.unavailable }
    })
    await reconciler.reconcile(context: context, userID: user)
    meeting.audioTranscript = "Edited after completion"
    await reconciler.reconcile(context: context, userID: user)
    #expect(syncs == 2)
    #expect(meeting.audioTranscript == "Edited after completion")
    #expect(coordinator.snapshots[meeting.id]?.phase == .completed)
  }
  @Test func simultaneousReconciliationMakesOneStatusRequest() async throws {
    let container = try ModelContainer(for: Meeting.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext, user = UUID(), job = UUID()
    let meeting = Meeting(name: "One poll")
    meeting.updateProcessingState(.transcribing)
    context.insert(meeting)
    let store = BackgroundUploadStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let api = UploadFakeAPI(), transport = UploadFakeTransport()
    var manifest = BackgroundUploadManifest(userID: user, meetingID: meeting.id, sourceRelativePath: "source.m4a", options: UploadOptions(provider: "xai", language: "it", duration: 10))
    manifest.sessionID = api.reply.sessionId; manifest.jobID = job; manifest.phase = .queued
    try store.save(manifest)
    api.reply.status = "queued"; api.reply.jobId = job
    let coordinator = BackgroundUploadCoordinator(api: api, store: store, transport: transport, identity: { user }, ensureMeeting: { _, _ in })
    await coordinator.recover(userID: user)
    let status = result(user: user, meeting: meeting.id, job: job)
    var calls = 0
    let reconciler = BackgroundUploadReconciler(coordinator: coordinator, status: { _ in calls += 1; await Task.yield(); return status }, identity: { await Task.yield(); return user }, sync: { _ in })
    async let first: Void = reconciler.reconcile(context: context, userID: user)
    async let second: Void = reconciler.reconcile(context: context, userID: user)
    _ = await (first, second)
    #expect(calls == 1)
  }
  @Test func queuedPromotionUsesLegacyMeetingStates() {
    let meeting = Meeting(name: "Queued")
    BackgroundUploadReconciler.applyQueued(jobID: UUID(), to: meeting)
    #expect(meeting.processingState == .transcribing)
    #expect(meeting.transcriptionJobId != nil)
  }
  @Test func deletedCancelledAndForeignResultsAreIgnored() async throws {
    let container = try ModelContainer(for: Meeting.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext, user = UUID(), job = UUID()
    let meeting = Meeting(name: "Cancelled")
    meeting.setProcessingError("Cancelled")
    context.insert(meeting)
    let status = result(user: user, meeting: meeting.id, job: job)
    #expect(!BackgroundUploadReconciler.applyResult(status, to: meeting, userID: user, jobID: job))
    meeting.updateProcessingState(.transcribing)
    #expect(!BackgroundUploadReconciler.applyResult(status, to: meeting, userID: UUID(), jobID: job))
    context.delete(meeting)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<Meeting>()).isEmpty)
  }
}
