struct AnalysisAnnouncementTracker {
  private var previous: AnalysisPresentation?

  mutating func update(_ presentation: AnalysisPresentation) -> AnalysisPresentation? {
    defer { previous = presentation }
    guard let previous, previous.meetingID == presentation.meetingID else { return nil }
    if previous.jobID != presentation.jobID, previous.jobID != nil { return nil }
    guard previous.phase != presentation.phase || previous.guidance != presentation.guidance else { return nil }
    return presentation
  }
}
