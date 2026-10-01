import Combine
import Foundation
import Supabase

struct UploadTaskSnapshot: Sendable {
  var id: Int
  var description: String?
}

@MainActor protocol BackgroundUploadTransporting: AnyObject {
  var completion: ((String, Int?, Bool) -> Void)? { get set }
  var progress: ((String, Int64, Int64) -> Void)? { get set }
  var finished: (() -> Void)? { get set }
  func allTasks() async -> [UploadTaskSnapshot]
  func schedule(_ request: URLRequest, file: URL, description: String) throws
  func cancel(_ id: Int)
}

/// Enter synchronously on the serial delegate queue, leave after durable actor work.
final class UploadDelegateDrain: @unchecked Sendable {
  private let group = DispatchGroup()
  func enqueue(_ work: @escaping @MainActor @Sendable () -> Void) {
    group.enter()
    Task { @MainActor in
      work()
      group.leave()
    }
  }
  func finish(_ work: @escaping @MainActor @Sendable () -> Void) {
    group.notify(queue: .main) { Task { @MainActor in work() } }
  }
}

@MainActor final class BackgroundURLTransport: NSObject, BackgroundUploadTransporting, URLSessionTaskDelegate {
  var completion: ((String, Int?, Bool) -> Void)?
  var progress: ((String, Int64, Int64) -> Void)?
  var finished: (() -> Void)?
  nonisolated private let drain = UploadDelegateDrain()
  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: BackgroundUploadCoordinator.sessionIdentifier)
    config.waitsForConnectivity = true
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.allowsCellularAccess = URLSessionConfiguration.default.allowsCellularAccess
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return URLSession(configuration: config, delegate: self, delegateQueue: queue)
  }()
  func allTasks() async -> [UploadTaskSnapshot] {
    await withCheckedContinuation { continuation in
      session.getAllTasks { tasks in continuation.resume(returning: tasks.map { UploadTaskSnapshot(id: $0.taskIdentifier, description: $0.taskDescription) }) }
    }
  }
  func schedule(_ request: URLRequest, file: URL, description: String) throws {
    let task = session.uploadTask(with: request, fromFile: file)
    task.taskDescription = description
    task.resume()
  }
  func cancel(_ id: Int) {
    session.getAllTasks { tasks in tasks.first { $0.taskIdentifier == id }?.cancel() }
  }
  func reconnect() { _ = session }
  nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let description = task.taskDescription else { return }
    let status = (task.response as? HTTPURLResponse)?.statusCode
    let failed = error != nil
    drain.enqueue { [weak self] in self?.completion?(description, status, failed) }
  }
  nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
    guard let description = task.taskDescription else { return }
    drain.enqueue { [weak self] in self?.progress?(description, totalBytesSent, totalBytesExpectedToSend) }
  }
  nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    drain.finish { [weak self] in self?.finished?() }
  }
}

@MainActor final class BackgroundUploadCoordinator: ObservableObject {
  static let sessionIdentifier = "com.mattianalytics.snipnote.background-audio-upload.v1"
  static let shared = BackgroundUploadCoordinator()
  @Published private(set) var snapshots: [UUID: BackgroundUploadManifest] = [:]
  private let api: BackgroundUploadServing
  let store: BackgroundUploadStore
  private let transport: BackgroundUploadTransporting
  private let identity: () async throws -> UUID
  private let productionIdentity: Bool
  var ensureMeeting: (UUID, UUID) async throws -> Void
  var onUpdate: (() -> Void)?
  private var activeUser: UUID?
  private var systemCompletion: (() -> Void)?
  private var recovering = false
  private var operating: Set<UUID> = []
  private var retryTasks: [UUID: Task<Void, Never>] = [:]

  init(api: BackgroundUploadServing? = nil, store: BackgroundUploadStore? = nil, transport: BackgroundUploadTransporting? = nil,
       identity: (() async throws -> UUID)? = nil, ensureMeeting: @escaping (UUID, UUID) async throws -> Void = { _, _ in throw BackgroundUploadFailure.unavailable }) {
    productionIdentity = identity == nil
    self.api = api ?? BackgroundUploadAPI()
    self.store = store ?? BackgroundUploadStore()
    self.transport = transport ?? BackgroundURLTransport()
    self.identity = identity ?? { try await SupabaseManager.shared.client.auth.session.user.id }
    self.ensureMeeting = ensureMeeting
    self.transport.completion = { [weak self] description, status, failed in self?.acceptCompletion(description, statusCode: status, failed: failed) }
    self.transport.progress = { [weak self] description, sent, total in self?.acceptProgress(description, sent: sent, total: total) }
    if let user = SupabaseManager.shared.client.auth.currentUser?.id, let manifests = try? self.store.load(userID: user) {
      activeUser = user
      snapshots = Dictionary(uniqueKeysWithValues: manifests.map { ($0.meetingID, $0) })
    }
    self.transport.finished = { [weak self] in
      guard let self else { return }
      let completion = self.systemCompletion
      self.systemCompletion = nil
      completion?()
      self.onUpdate?()
    }
  }

  static func taskDescription(_ manifest: BackgroundUploadManifest, index: Int) -> String {
    "\(manifest.userID.uuidString)/\(manifest.meetingID.uuidString)/\(index)"
  }
  func contains(meetingID: UUID) -> Bool {
    if let manifest = snapshots[meetingID] { return manifest.phase != .cancelled && manifest.phase != .completed }
    if let user = SupabaseManager.shared.client.auth.currentUser?.id,
       let manifest = try? store.load(userID: user).first(where: { $0.meetingID == meetingID }) {
      return manifest.phase != .cancelled && manifest.phase != .completed
    }
    return false
  }
  func refreshStatuses(userID: UUID) async {
    guard activeUser == userID else { return }
    for manifest in Array(snapshots.values) where manifest.userID == userID && manifest.phase != .completed && manifest.phase != .cancelled {
      guard let sid = manifest.sessionID else { continue }
      do {
        let remote = try await api.status(sessionID: sid)
        try await assertAccount(userID)
        guard let latest = snapshots[manifest.meetingID], latest.phase != .cancelled && latest.phase != .completed else { continue }
        _ = try apply(remote, to: latest)
      } catch { /* Status errors preserve identity and transfer state. */ }
    }
  }
  func markResultApplied(meetingID: UUID) throws {
    guard var manifest = snapshots[meetingID] else { return }
    manifest.resultApplied = true
    try persist(manifest)
  }
  func finish(meetingID: UUID) {
    guard var manifest = snapshots[meetingID] else { return }
    manifest.phase = .completed
    try? persist(manifest)
    // Keep source for existing playback. Release only remotely verified chunk/body files.
    for state in manifest.files where state.state == .verified {
      for relative in [state.file.relativePath, "body-\(state.file.index).multipart"] {
        if let url = try? store.fileURL(relative, userID: manifest.userID, meetingID: meetingID) { try? FileManager.default.removeItem(at: url) }
      }
    }
  }
  func cancel(meetingID: UUID) {
    guard var manifest = snapshots[meetingID], manifest.phase != .completed else { return }
    manifest.phase = .cancelled
    try? persist(manifest)
    retryTasks[meetingID]?.cancel()
    Task {
      for task in await transport.allTasks() where task.description?.hasPrefix("\(manifest.userID.uuidString)/\(meetingID.uuidString)/") == true { transport.cancel(task.id) }
    }
  }
  func signOut() async {
    activeUser = nil
    for retry in retryTasks.values { retry.cancel() }
    retryTasks.removeAll()
    snapshots = [:]
    for task in await transport.allTasks() { transport.cancel(task.id) }
  }
  func start(meetingID: UUID, source: URL, options: UploadOptions) async throws {
    let user = try await identity()
    activeUser = user
    if let existing = try store.load(userID: user).first(where: { $0.meetingID == meetingID }) {
      snapshots[meetingID] = existing
      try await resume(existing)
      return
    }
    let directory = store.directory(userID: user, meetingID: meetingID)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try BackgroundUploadStore.protect(directory)
    let relative = "source.\(source.pathExtension.isEmpty ? "m4a" : source.pathExtension)"
    let stableSource = try store.fileURL(relative, userID: user, meetingID: meetingID)
    let sourceSize = try AudioChunker.getFileSize(url: source)
    let available = try FileManager.default.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? UInt64 ?? 0
    guard available > sourceSize * 4 + 100 * 1024 * 1024 else { throw BackgroundUploadFailure.diskFull }
    var manifest = BackgroundUploadManifest(userID: user, meetingID: meetingID, sourceRelativePath: relative, options: options)
    // Original caller's file is retained even if this durable copy or preparation fails.
    try persist(manifest)
    do {
      try FileManager.default.copyItem(at: source, to: stableSource)
      try BackgroundUploadStore.protect(stableSource)
      manifest.files = try await AudioChunker.prepareUploadFiles(from: stableSource, directory: directory).map { UploadFileState(file: $0) }
      // Provider, language and duration remain captured for this attempt.

      try await assertAccount(user)
      try persist(manifest)
      try await resume(manifest)
    } catch BackgroundUploadFailure.disabled {
      // Only explicit rejection before any registered session can select legacy.
      if manifest.sessionID == nil { manifest.phase = .cancelled; try persist(manifest) }
      throw BackgroundUploadFailure.disabled
    } catch {
      manifest = snapshots[meetingID] ?? manifest
      manifest.phase = .retry
      manifest.errorCode = error is CancellationError ? "preparation_interrupted" : "recoverable"
      try persist(manifest)
      throw error
    }
  }

  private func assertAccount(_ user: UUID) async throws {
    guard activeUser == user, try await identity() == user else { throw BackgroundUploadFailure.accountMismatch }
  }
  func recover(userID: UUID) async {
    guard !recovering else { return }
    recovering = true
    defer { recovering = false }
    activeUser = userID
    for task in retryTasks.values { task.cancel() }
    retryTasks.removeAll()
    do {
      let manifests = try store.load(userID: userID)
      snapshots = Dictionary(uniqueKeysWithValues: manifests.map { ($0.meetingID, $0) })
      for task in await transport.allTasks() {
        if task.description?.hasPrefix(userID.uuidString + "/") != true { transport.cancel(task.id) }
      }
      try await assertAccount(userID)
      for manifest in manifests where manifest.phase != .completed && manifest.phase != .cancelled {
        do { try await resume(manifest) }
        catch {
          var latest = snapshots[manifest.meetingID] ?? manifest
          latest.phase = .retry; latest.errorCode = "recoverable"
          try? persist(latest)
        }
      }
    } catch { /* Keep manifests on disk; an authentication/network failure is retryable. */ }
  }

  private func resume(_ initial: BackgroundUploadManifest) async throws {
    guard !operating.contains(initial.meetingID) else { return }
    operating.insert(initial.meetingID)
    defer { operating.remove(initial.meetingID) }
    try await assertAccount(initial.userID)
    var manifest = snapshots[initial.meetingID] ?? initial
    guard manifest.phase != .cancelled && manifest.phase != .completed && manifest.phase != .queued else { return }
    if manifest.files.isEmpty {
      manifest.phase = .preparing; try persist(manifest)
      let source = try store.fileURL(manifest.sourceRelativePath, userID: manifest.userID, meetingID: manifest.meetingID)
      manifest.files = try await AudioChunker.prepareUploadFiles(from: source, directory: store.directory(userID: manifest.userID, meetingID: manifest.meetingID)).map { UploadFileState(file: $0) }

      try await assertAccount(manifest.userID)
      try persist(manifest)
    }
    try await ensureMeeting(manifest.userID, manifest.meetingID)
    try await assertAccount(manifest.userID)
    // Query before replacing tasks, including after force quit.
    if let sid = manifest.sessionID {
      let remote = try await api.status(sessionID: sid)
      try await assertAccount(manifest.userID)
      manifest = try apply(remote, to: manifest)
      if manifest.phase == .queued || manifest.phase == .cancelled { return }
    }
    let tasks = await transport.allTasks()
    let existing = Set(tasks.compactMap(\.description))
    let response = try await api.bootstrap(manifest)
    try await assertAccount(manifest.userID)
    manifest = try apply(response, to: snapshots[manifest.meetingID] ?? manifest)
    guard manifest.phase != .queued && manifest.phase != .cancelled else { return }
    for instruction in response.files {
      guard let offset = manifest.files.firstIndex(where: { $0.file.index == instruction.index }) else { throw BackgroundUploadFailure.invalidManifest }
      let description = Self.taskDescription(manifest, index: instruction.index)
      if instruction.verified || [.uploaded, .verified].contains(manifest.files[offset].state) { continue }
      if existing.contains(description) { manifest.files[offset].state = .scheduled; continue }
      guard let url = instruction.uploadUrl, url.scheme == "https", let method = instruction.method, let headers = instruction.headers,
            let expiry = instruction.expiresAt, expiry > Date() else { throw BackgroundUploadFailure.unavailable }
      let body = try multipartBody(manifest: manifest, file: manifest.files[offset].file, headers: headers)
      var request = URLRequest(url: url)
      request.httpMethod = method
      for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
      manifest.files[offset].state = .scheduled
      manifest.files[offset].attempts += 1
      // Durable intent before task creation; enumeration repairs this crash window.
      try persist(manifest)
      try transport.schedule(request, file: body, description: description)
    }
    manifest.phase = .uploading
    manifest.errorCode = nil
    try persist(manifest)
  }

  private func apply(_ response: UploadSessionResponse, to initial: BackgroundUploadManifest) throws -> BackgroundUploadManifest {
    guard initial.sessionID == nil || initial.sessionID == response.sessionId else { throw BackgroundUploadFailure.invalidManifest }
    var manifest = initial
    manifest.sessionID = response.sessionId
    for instruction in response.files where instruction.verified {
      if let index = manifest.files.firstIndex(where: { $0.file.index == instruction.index }) {
        manifest.files[index].state = .verified
        manifest.files[index].sentBytes = manifest.files[index].file.expectedBytes
      }
    }
    if response.status == "queued", let job = response.jobId { manifest.jobID = job; manifest.phase = .queued }
    if response.status == "cancelled" { manifest.phase = .cancelled }
    try persist(manifest)
    return manifest
  }
  private func persist(_ manifest: BackgroundUploadManifest) throws {
    try store.save(manifest)
    snapshots[manifest.meetingID] = manifest
  }
  func acceptCompletion(_ description: String, statusCode: Int?, failed: Bool) {
    guard let (manifest, index) = callbackTarget(description), ![.uploaded, .verified].contains(manifest.files[index].state) else { return }
    var updated = manifest
    if !failed, let statusCode, (200..<300).contains(statusCode) {
      updated.files[index].state = .uploaded
      updated.files[index].sentBytes = updated.files[index].file.expectedBytes
    } else {
      updated.files[index].state = .retry; updated.phase = .retry; updated.errorCode = "upload_retry"
    }
    do { try persist(updated) } catch { return }
    onUpdate?()
    if updated.files[index].state == .retry, updated.files[index].attempts <= 3 {
      scheduleRetry(updated, delay: UInt64(1 << max(0, updated.files[index].attempts - 1)))
    }
  }
  private func scheduleRetry(_ manifest: BackgroundUploadManifest, delay: UInt64) {
    guard retryTasks[manifest.meetingID] == nil else { return }
    retryTasks[manifest.meetingID] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
      guard let self, !Task.isCancelled else { return }
      self.retryTasks[manifest.meetingID] = nil
      guard self.activeUser == manifest.userID else { return }
      try? await self.resume(self.snapshots[manifest.meetingID] ?? manifest)
    }
  }
  private func callbackTarget(_ description: String) -> (BackgroundUploadManifest, Int)? {
    if productionIdentity && SupabaseManager.shared.client.auth.currentUser?.id != activeUser { return nil }
    let parts = description.split(separator: "/")
    guard parts.count == 3, let user = UUID(uuidString: String(parts[0])), user == activeUser,
          let meeting = UUID(uuidString: String(parts[1])), let file = Int(parts[2]),
          let manifest = snapshots[meeting], manifest.userID == user,
          manifest.phase != .cancelled && manifest.phase != .completed,
          let index = manifest.files.firstIndex(where: { $0.file.index == file }) else { return nil }
    return (manifest, index)
  }
  private func acceptProgress(_ description: String, sent: Int64, total: Int64) {
    guard let (manifest, index) = callbackTarget(description), total > 0 else { return }
    var updated = manifest
    updated.files[index].sentBytes = max(updated.files[index].sentBytes, Int64(Double(sent) / Double(total) * Double(updated.files[index].file.expectedBytes)))
    // Byte progress is observational; completion state is persisted separately.
    snapshots[manifest.meetingID] = updated
  }
  func handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) {
    guard identifier == Self.sessionIdentifier else { completion(); return }
    systemCompletion = completion
    (transport as? BackgroundURLTransport)?.reconnect()
    // Load callback targets without scheduling or needing a network wake.
    Task {
      guard let user = try? await identity() else { return }
      activeUser = user
      if let manifests = try? store.load(userID: user) {
        snapshots = Dictionary(uniqueKeysWithValues: manifests.map { ($0.meetingID, $0) })
      }
    }
  }

  /// Multipart encoding streamed to another durable file; never loads audio into Data.
  private func multipartBody(manifest: BackgroundUploadManifest, file: PreparedUploadFile, headers: [String: String]) throws -> URL {
    guard let type = headers.first(where: { $0.key.lowercased() == "content-type" })?.value,
          let range = type.range(of: "boundary="), type.hasPrefix("multipart/form-data") else { throw BackgroundUploadFailure.invalidManifest }
    let boundary = String(type[range.upperBound...])
    guard !boundary.isEmpty, !boundary.contains("\r"), !boundary.contains("\n") else { throw BackgroundUploadFailure.invalidManifest }
    let source = try store.fileURL(file.relativePath, userID: manifest.userID, meetingID: manifest.meetingID)
    let destination = try store.fileURL("body-\(file.index).multipart", userID: manifest.userID, meetingID: manifest.meetingID)
    let temporary = destination.appendingPathExtension("tmp")
    FileManager.default.createFile(atPath: temporary.path, contents: nil)
    let output = try FileHandle(forWritingTo: temporary)
    let input = try FileHandle(forReadingFrom: source)
    defer { try? output.close(); try? input.close(); try? FileManager.default.removeItem(at: temporary) }
    try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"chunk.\(file.fileExtension)\"\r\nContent-Type: \(file.contentType)\r\n\r\n".utf8))
    while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { try output.write(contentsOf: data) }
    try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    try output.synchronize()
    try output.close()
    if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
    else { try FileManager.default.moveItem(at: temporary, to: destination) }
    try BackgroundUploadStore.protect(destination)
    return destination
  }
}
