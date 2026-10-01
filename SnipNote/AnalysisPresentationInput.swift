import Foundation

struct AnalysisPresentationInput {
  var meetingID: UUID
  var jobID: String? = nil
  var backend: TranscriptionBackend? = .cloud
  var processingState: ProcessingState = .transcribing
  var processingPhase: MeetingProcessingPhase = .preparing
  var upload: BackgroundUploadManifest? = nil
  var serverStatus: JobStatus? = nil
  var serverStage: String? = nil
  var canRetry: Bool = false
  var canRetryAnalysis: Bool = false

  init(meetingID: UUID, jobID: String? = nil, backend: TranscriptionBackend? = .cloud,
       processingState: ProcessingState = .transcribing, processingPhase: MeetingProcessingPhase = .preparing,
       upload: BackgroundUploadManifest? = nil, serverStatus: JobStatus? = nil, serverStage: String? = nil,
       canRetry: Bool = false, canRetryAnalysis: Bool = false) {
    self.meetingID = meetingID; self.jobID = jobID; self.backend = backend
    self.processingState = processingState; self.processingPhase = processingPhase
    self.upload = upload; self.serverStatus = serverStatus; self.serverStage = serverStage
    self.canRetry = canRetry; self.canRetryAnalysis = canRetryAnalysis
  }

  @MainActor init(meeting: Meeting, upload: BackgroundUploadManifest?, serverStatus: JobStatus?, serverStage: String?) {
    let accepted = meeting.transcriptionJobId != nil || (upload?.meetingID == meeting.id && upload?.phase == .queued)
    let supplied = serverStage?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.init(meetingID: meeting.id, jobID: meeting.transcriptionJobId, backend: meeting.transcriptionBackend,
              processingState: meeting.processingState, processingPhase: meeting.processingPhase, upload: upload,
              serverStatus: serverStatus, serverStage: supplied?.isEmpty == false ? supplied : (accepted ? meeting.currentStageDescription : nil),
              canRetry: meeting.canRetry, canRetryAnalysis: meeting.canRetryAnalysis)
  }
}
