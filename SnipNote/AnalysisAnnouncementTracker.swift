struct AnalysisAnnouncementTracker {
  private var previous: AnalysisPresentation?

  mutating func update(_ presentation: AnalysisPresentation) -> AnalysisPresentation? {
    defer { previous = presentation }
    guard let previous, previous.meetingID == presentation.meetingID else { return nil }
    let clearedTerminalJob = presentation.jobID == nil && [.failed, .results].contains(presentation.phase)
    if previous.jobID != presentation.jobID, previous.jobID != nil, !clearedTerminalJob { return nil }
    guard previous.phase != presentation.phase || previous.guidance != presentation.guidance else { return nil }
    return presentation
  }
}
