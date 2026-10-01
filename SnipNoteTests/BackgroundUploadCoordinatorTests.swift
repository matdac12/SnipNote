import Foundation
import Testing
@testable import SnipNote

@MainActor final class UploadFakeAPI: BackgroundUploadServing {
  var reply: UploadSessionResponse
  var bootstraps = 0
  init(sessionID: UUID = UUID()) {
    reply = UploadSessionResponse(sessionId: sessionID, status: "awaiting_upload", uploadDeadline: .distantFuture, files: [UploadInstructions(index: 0, verified: false, uploadUrl: URL(string: "https://storage.invalid/upload"), method: "PUT", headers: ["Content-Type": "multipart/form-data; boundary=fixture"], expiresAt: .distantFuture)])
  }
  func capabilities() async throws -> UploadCapabilities { UploadCapabilities(backgroundUploadEnabled: true) }
  func bootstrap(_ manifest: BackgroundUploadManifest) async throws -> UploadSessionResponse { bootstraps += 1; return reply }
  func status(sessionID: UUID) async throws -> UploadSessionResponse { reply }
}

@MainActor final class UploadFakeTransport: BackgroundUploadTransporting {
  var tasks: [UploadTaskSnapshot] = []
  var scheduled: [String] = []
  var completion: ((String, Int?, Bool) -> Void)?
  var progress: ((String, Int64, Int64) -> Void)?
  var finished: (() -> Void)?
  func allTasks() async -> [UploadTaskSnapshot] { tasks }
  func schedule(_ request: URLRequest, file: URL, description: String) throws {
    scheduled.append(description)
    tasks.append(UploadTaskSnapshot(id: tasks.count + 1, description: description))
  }
  func cancel(_ id: Int) { tasks.removeAll { $0.id == id } }
}

@MainActor struct BackgroundUploadCoordinatorTests {
  private func fixture() throws -> (BackgroundUploadCoordinator, BackgroundUploadStore, UploadFakeAPI, UploadFakeTransport, BackgroundUploadManifest) {
    let store = BackgroundUploadStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let api = UploadFakeAPI(), transport = UploadFakeTransport()
    var manifest = BackgroundUploadManifest(userID: UUID(), meetingID: UUID(), sourceRelativePath: "source.m4a", options: UploadOptions(provider: "xai", language: "it", duration: 10))
    manifest.sessionID = api.reply.sessionId
    manifest.files = [UploadFileState(file: PreparedUploadFile(index: 0, relativePath: "chunk.m4a", expectedBytes: 3, duration: 10, contentType: "audio/mp4", fileExtension: "m4a"))]
    try store.save(manifest)
    try Data([1,2,3]).write(to: store.fileURL("chunk.m4a", userID: manifest.userID, meetingID: manifest.meetingID))
    let user = manifest.userID
    let coordinator = BackgroundUploadCoordinator(api: api, store: store, transport: transport, identity: { user }, ensureMeeting: { _, _ in })
    return (coordinator, store, api, transport, manifest)
  }
  @Test func crashAfterBootstrapReschedulesMissingTasks() async throws {
    let (coordinator, store, _, transport, manifest) = try fixture()
    await coordinator.recover(userID: manifest.userID)
    #expect(transport.scheduled.count == 1)
    #expect(try store.load(userID: manifest.userID).first?.transferRegistered == true)
  }
  @Test func existingTasksAreReattachedWithoutDuplicateUpload() async throws {
    let (coordinator, _, _, transport, manifest) = try fixture()
    transport.tasks = [UploadTaskSnapshot(id: 42, description: BackgroundUploadCoordinator.taskDescription(manifest, index: 0))]
    await coordinator.recover(userID: manifest.userID)
    #expect(transport.scheduled.isEmpty)
  }
  @Test func expiredURLRetriesOnlyUnverifiedChunk() async throws {
    let (coordinator, store, api, transport, original) = try fixture()
    var manifest = original
    manifest.files[0].state = .uploaded
    manifest.files.append(UploadFileState(file: PreparedUploadFile(index: 1, relativePath: "chunk1.m4a", expectedBytes: 3, duration: 10, contentType: "audio/mp4", fileExtension: "m4a"), state: .retry))
    manifest.options.duration = 20
    try store.save(manifest)
    try Data([4,5,6]).write(to: store.fileURL("chunk1.m4a", userID: manifest.userID, meetingID: manifest.meetingID))
    api.reply.files.append(UploadInstructions(index: 1, verified: false, uploadUrl: URL(string: "https://storage.invalid/upload"), method: "PUT", headers: ["Content-Type":"multipart/form-data; boundary=fixture1"], expiresAt: .distantFuture))
    await coordinator.recover(userID: manifest.userID)
    #expect(transport.scheduled == [BackgroundUploadCoordinator.taskDescription(manifest, index: 1)])
  }
  @Test func duplicateCallbackCannotRegressState() async throws {
    let (coordinator, store, _, _, manifest) = try fixture()
    await coordinator.recover(userID: manifest.userID)
    let description = BackgroundUploadCoordinator.taskDescription(manifest, index: 0)
    coordinator.acceptCompletion(description, statusCode: 200, failed: false)
    coordinator.acceptCompletion(description, statusCode: 403, failed: true)
    #expect(try store.load(userID: manifest.userID).first?.files[0].state == .uploaded)
  }
  @Test func accountMismatchNeverAppliesResult() async throws {
    let (coordinator, store, _, transport, manifest) = try fixture()
    await coordinator.recover(userID: UUID())
    coordinator.acceptCompletion(BackgroundUploadCoordinator.taskDescription(manifest, index: 0), statusCode: 200, failed: false)
    #expect(transport.scheduled.isEmpty)
    #expect(try store.load(userID: manifest.userID).first?.files[0].state == .pending)
  }
  @Test func completionHandlerWaitsForDurableDelegateUpdates() async throws {
    let (coordinator, store, _, _, manifest) = try fixture()
    await coordinator.recover(userID: manifest.userID)
    let drain = UploadDelegateDrain()
    let description = BackgroundUploadCoordinator.taskDescription(manifest, index: 0)
    await withCheckedContinuation { continuation in
      drain.enqueue { coordinator.acceptCompletion(description, statusCode: 200, failed: false) }
      drain.finish {
        #expect((try? store.load(userID: manifest.userID).first?.files[0].state) == .uploaded)
        continuation.resume()
      }
    }
  }
}
