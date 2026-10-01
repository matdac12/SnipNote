import Foundation

struct AnalysisPresentation: Equatable {
  enum Phase: Equatable {
    case preparing, uploading, confirmingUpload, queued, transcribing, analyzing
    case processing, pausedUpload, failed, foreground, results
  }
  enum Guidance: Equatable { case keepOpen, safeUpload, safeServer, needsAttention, none }
  var meetingID: UUID
  var jobID: String?
  var phase: Phase
  var guidance: Guidance
  var uploadFraction: Double? = nil
  var sentBytes: Int64? = nil
  var totalBytes: Int64? = nil
  var canRetryUpload: Bool = false
  var canLeave: Bool { guidance == .safeUpload || guidance == .safeServer }
}
