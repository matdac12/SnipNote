import Testing
@testable import SnipNote

struct LocalTranscriptionCheckpointTests {
  @Test func completedSnapshotUpdatesCheckpointAndRejectsLateOlderText() {
    let meeting = Meeting(audioTranscript: "First.")
    meeting.updateDetailedProgress(completed: 1, total: 3, percent: 40, stage: "Ready")
    meeting.applyLocalTranscriptionProgress(AudioChunkerProgress(
      currentChunk: 3, totalChunks: 3, currentStage: "Complete", percentComplete: 100,
      partialTranscript: "Third.", completedChunks: 3, cumulativeTranscript: "First. Second. Third."))
    meeting.applyLocalTranscriptionProgress(AudioChunkerProgress(
      currentChunk: 2, totalChunks: 3, currentStage: "Complete", percentComplete: 70,
      partialTranscript: "Second.", completedChunks: 2, cumulativeTranscript: "First. Second."))
    #expect(meeting.lastProcessedChunk == 3)
    #expect(meeting.audioTranscript == "First. Second. Third.")
  }

  @Test func runningAndPreparationProgressPreserveCompletedCheckpoint() {
    let meeting = Meeting(audioTranscript: "First chunk.")
    meeting.updateDetailedProgress(completed: 1, total: 3, percent: 40, stage: "Ready")
    meeting.applyLocalTranscriptionProgress(AudioChunkerProgress(
      currentChunk: 2, totalChunks: 3, currentStage: "Running", percentComplete: 40, partialTranscript: nil))
    #expect(meeting.lastProcessedChunk == 1)
    meeting.applyLocalTranscriptionProgress(AudioChunkerProgress(
      currentChunk: 0, totalChunks: 0, currentStage: "Loading", percentComplete: 5, partialTranscript: nil))
    #expect(meeting.lastProcessedChunk == 1)
    #expect(meeting.totalChunks == 3)
    #expect(meeting.audioTranscript == "First chunk.")
  }

  @Test func pausedMeetingIgnoresLateProgress() {
    let meeting = Meeting(audioTranscript: "Saved words.")
    meeting.updateDetailedProgress(completed: 1, total: 3, percent: 40, stage: "Ready")
    meeting.markLocalJobPaused(reason: "Paused")
    meeting.applyLocalTranscriptionProgress(AudioChunkerProgress(
      currentChunk: 2, totalChunks: 3, currentStage: "Complete", percentComplete: 70, partialTranscript: "Late words."))
    #expect(meeting.processingPhase == .paused)
    #expect(meeting.lastProcessedChunk == 1)
    #expect(meeting.audioTranscript == "Saved words.")
  }
}
