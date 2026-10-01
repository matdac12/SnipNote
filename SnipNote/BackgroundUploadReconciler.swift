import Foundation
import SwiftData
import Supabase

@MainActor final class BackgroundUploadReconciler {
  static let shared = BackgroundUploadReconciler()
  private let coordinator: BackgroundUploadCoordinator
  private let status: (String) async throws -> JobStatusResponse
  private let identity: () async throws -> UUID
  private let sync: (Meeting) async throws -> Void
  private var reconciling = false
  private var polling: Task<Void, Never>?

  init(coordinator: BackgroundUploadCoordinator? = nil,
       status: ((String) async throws -> JobStatusResponse)? = nil,
       identity: (() async throws -> UUID)? = nil,
       sync: ((Meeting) async throws -> Void)? = nil) {
    self.coordinator = coordinator ?? .shared
    let jobs = RenderTranscriptionService()
    self.status = status ?? { try await jobs.getJobStatus(jobId: $0) }
    self.identity = identity ?? { try await SupabaseManager.shared.client.auth.session.user.id }
    self.sync = sync ?? { try await SupabaseManager.shared.saveMeeting($0) }
  }
  func activate(context: ModelContext, userID: UUID) async {
    stop()
    coordinator.ensureMeeting = { [weak self] user, meetingID in
      guard let self, try await self.identity() == user else { throw BackgroundUploadFailure.accountMismatch }
      let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
      guard let meeting = try context.fetch(descriptor).first, meeting.isProcessing else { throw BackgroundUploadFailure.cancelled }
      // Upsert only before server registration. Later sync must not clear its job link.
      if self.coordinator.snapshots[meetingID]?.sessionID == nil {
        try context.save()
        try await self.sync(meeting)
      }
    }
    coordinator.onUpdate = { [weak self] in
      Task { await self?.reconcile(context: context, userID: userID) }
    }
    await coordinator.recover(userID: userID)
    await reconcile(context: context, userID: userID)
    polling = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard !Task.isCancelled else { return }
        await self?.reconcile(context: context, userID: userID)
      }
    }
  }
  func stop() { polling?.cancel(); polling = nil }
  func reconcile(context: ModelContext, userID: UUID) async {
    guard !reconciling, (try? await identity()) == userID else { return }
    reconciling = true
    defer { reconciling = false }
    await coordinator.refreshStatuses(userID: userID)
    for manifest in coordinator.snapshots.values where manifest.userID == userID && manifest.phase != .cancelled && manifest.phase != .completed {
      let meetingID = manifest.meetingID
      do {
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
        guard let meeting = try context.fetch(descriptor).first else {
          coordinator.cancel(meetingID: meetingID)
          continue
        }
        if let jobID = manifest.jobID, meeting.transcriptionJobId == jobID.uuidString,
           manifest.resultApplied || meeting.processingState == .completed {
          try await sync(meeting)
          guard (try? await identity()) == userID else { continue }
          coordinator.finish(meetingID: meetingID)
          continue
        }
        guard meeting.isProcessing else {
          coordinator.cancel(meetingID: meetingID)
          continue
        }
        if let source = try? coordinator.store.fileURL(manifest.sourceRelativePath, userID: userID, meetingID: meetingID), FileManager.default.fileExists(atPath: source.path) {
          meeting.localAudioPath = source.path
          try context.save()
        }
        if let jobID = manifest.jobID {
          Self.applyQueued(jobID: jobID, to: meeting)
          try context.save()
          let result = try await status(jobID.uuidString)
          // Refetch after suspension: deletion/cancellation must not resurrect a model.
          guard (try? await identity()) == userID,
                let current = try context.fetch(descriptor).first, current.isProcessing,
                coordinator.snapshots[meetingID]?.phase != .cancelled else { continue }
          if Self.applyResult(result, to: current, userID: userID, jobID: jobID) {
            try context.save()
            try coordinator.markResultApplied(meetingID: meetingID)
            try await sync(current)
            coordinator.finish(meetingID: meetingID)
          }
        }
      } catch { /* Keep job/session identity on network or metadata failure. */ }
    }
  }
  static func applyQueued(jobID: UUID, to meeting: Meeting) {
    meeting.transcriptionJobId = jobID.uuidString
    meeting.updateProcessingState(.transcribing)
    meeting.hasRecording = true
  }
  @discardableResult static func applyResult(_ result: JobStatusResponse, to meeting: Meeting, userID: UUID, jobID: UUID) -> Bool {
    guard meeting.isProcessing, UUID(uuidString: result.userId) == userID,
          UUID(uuidString: result.meetingId) == meeting.id, UUID(uuidString: result.id) == jobID else { return false }
    switch result.status {
    case .completed:
      if let transcript = result.transcript { meeting.audioTranscript = transcript }
      if let overview = result.overview { meeting.shortSummary = overview }
      if let summary = result.summary { meeting.aiSummary = summary }
      meeting.markCompleted()
      return true
    case .failed:
      meeting.setProcessingError(result.errorMessage ?? LocalizationManager.localizedAppString("background_upload.remote_failed"))
      return true
    default: return false
    }
  }
  static func permitsLocalFallback(remoteStatus: JobStatus?, activeUpload: Bool) -> Bool {
    remoteStatus == .failed && !activeUpload
  }
}
