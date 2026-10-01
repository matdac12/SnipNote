import Foundation

enum AnalysisPresentationResolver {
  static func resolve(_ input: AnalysisPresentationInput, previous: AnalysisPresentation? = nil) -> AnalysisPresentation {
    let upload = input.upload.flatMap { $0.meetingID == input.meetingID ? $0 : nil }
    let jobID = input.jobID ?? upload?.jobID?.uuidString
    func value(_ phase: AnalysisPresentation.Phase, _ guidance: AnalysisPresentation.Guidance) -> AnalysisPresentation {
      .init(meetingID: input.meetingID, jobID: jobID, phase: phase, guidance: guidance)
    }
    if input.processingState == .completed { return value(.results, .none) }
    if input.processingState == .failed { return value(.failed, .needsAttention) }
    if input.backend == .local { return value(.foreground, .keepOpen) }
    if let upload {
      if upload.phase == .cancelled { return value(.failed, .needsAttention) }
      if upload.phase == .retry || upload.files.contains(where: { $0.state == .retry }) {
        var result = value(.pausedUpload, .needsAttention)
        result.canRetryUpload = true
        applyProgress(upload, to: &result)
        return result
      }
      if upload.phase == .preparing || upload.phase == .uploading {
        guard upload.transferRegistered, !upload.files.isEmpty,
              upload.files.allSatisfy({ $0.file.expectedBytes > 0 }) else { return value(.preparing, .keepOpen) }
        var result = value(.uploading, .safeUpload)
        applyProgress(upload, to: &result)
        guard result.totalBytes != nil else { return value(.preparing, .keepOpen) }
        if result.uploadFraction == 1 { result.phase = .confirmingUpload }
        return result
      }
    }
    let accepted = jobID != nil || upload?.phase == .queued
    if accepted {
      if let status = input.serverStatus {
        let phase = serverPhase(status: status, stage: input.serverStage)
        return value(phase, status == .failed ? .needsAttention : .safeServer)
      }
      if let previous, previous.meetingID == input.meetingID, previous.jobID == jobID,
         previous.phase == .failed, previous.guidance == .needsAttention {
        return previous
      }
      if let stage = input.serverStage, !stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
         input.processingPhase != .queued {
        return value(serverPhase(status: .processing, stage: stage), .safeServer)
      }
      switch input.processingPhase {
      case .generatingOverview, .generatingSummary: return value(.analyzing, .safeServer)
      case .transcribing: return value(.transcribing, .safeServer)
      default: break
      }
      if let previous, previous.meetingID == input.meetingID, previous.jobID == jobID,
         previous.guidance == .safeServer {
        return previous
      }
      return value(.queued, .safeServer)
    }
    return input.processingPhase == .preparing ? value(.preparing, .keepOpen) : value(.foreground, .keepOpen)
  }

  static func serverPhase(status: JobStatus, stage: String?) -> AnalysisPresentation.Phase {
    switch status {
    case .pending: return .queued
    case .failed: return .failed
    case .completed: return .processing // Local results have not necessarily been applied.
    case .processing:
      let text = stage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
      if ["transcribing", "merging transcripts", "combining transcripts", "transcription complete"].contains(where: { text.hasPrefix($0) }) { return .transcribing }
      if ["generating summary", "summary generated", "generating overview", "ai content generated"].contains(where: { text.hasPrefix($0) }) { return .analyzing }
      return .processing
    }
  }

  private static func applyProgress(_ upload: BackgroundUploadManifest, to value: inout AnalysisPresentation) {
    guard !upload.files.isEmpty, upload.files.allSatisfy({ $0.file.expectedBytes > 0 }) else { return }
    var total: Int64 = 0, sent: Int64 = 0
    for entry in upload.files {
      let next = total.addingReportingOverflow(entry.file.expectedBytes)
      guard !next.overflow else { return }
      total = next.partialValue
      sent += max(0, min(entry.sentBytes, entry.file.expectedBytes))
    }
    value.totalBytes = total; value.sentBytes = sent
    value.uploadFraction = Double(sent) / Double(total)
  }
}
