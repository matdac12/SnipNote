import Foundation
import Testing
@testable import SnipNote

struct LocalModelMigrationTests {
  @Test func retiredModelCleanupPreservesParakeetAndOtherDocuments() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let models = root.appendingPathComponent("LocalModels")
    let documents = root.appendingPathComponent("Documents")
    let retiredPaths = [
      "LocalModels/Installed/openai_whisper-base",
      "LocalModels/Installed/openai_whisper-small",
      "LocalModels/Staging/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-small",
      "Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-base"
    ]
    let preservedPaths = ["LocalModels/ParakeetUltra/parakeet-ultra", "LocalModels/ParakeetRedux/parakeet-redux", "Documents/recordings"]
    for path in retiredPaths + preservedPaths {
      try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    try LocalTranscriptionService.removeRetiredWhisperModels(modelRoot: models, documentsDirectory: documents)
    for path in retiredPaths { #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)) }
    for path in preservedPaths { #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)) }
  }

  @MainActor @Test(arguments: ["base", "small", "unknown", ""])
  func retiredOrMissingSelectionsPersistUltra(_ rawValue: String) throws {
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    if !rawValue.isEmpty { defaults.set(rawValue, forKey: "localTranscription.selectedModel") }
    let manager = LocalTranscriptionManager(defaults: defaults)
    #expect(manager.selectedModel == .parakeetUltra)
    #expect(defaults.string(forKey: "localTranscription.selectedModel") == "parakeetUltra")
  }

  @MainActor @Test func reduxSelectionSurvivesRelaunch() throws {
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("parakeetRedux", forKey: "localTranscription.selectedModel")
    #expect(LocalTranscriptionManager(defaults: defaults).selectedModel == .parakeetRedux)
  }

  @Test(arguments: ["base", "small"])
  func retiredWhisperJobsResolveToUltra(_ rawValue: String) {
    let meeting = Meeting()
    meeting.localTranscriptionModelRaw = rawValue
    #expect(meeting.localTranscriptionModel == .parakeetUltra)
  }

  @Test func migratingIncompleteWhisperJobDiscardsIncompatibleCheckpoint() {
    let meeting = Meeting(audioTranscript: "Partial Whisper transcript")
    meeting.localTranscriptionModelRaw = "small"
    meeting.updateProcessingPhase(.transcribing)
    meeting.lastProcessedChunk = 2
    meeting.totalChunks = 6
    meeting.localSpeechPlanJSON = "old plan"
    meeting.localSpeechPlanFingerprint = "old fingerprint"
    meeting.migrateRetiredLocalModel()
    #expect(meeting.localTranscriptionModelRaw == "parakeetUltra")
    #expect(meeting.audioTranscript.isEmpty)
    #expect(meeting.lastProcessedChunk == 0)
    #expect(meeting.totalChunks == 0)
    #expect(meeting.localSpeechPlanJSON == nil)
    #expect(meeting.localSpeechPlanFingerprint == nil)
  }

  @Test func migratingWhisperSummaryJobPreservesFinishedTranscript() {
    let meeting = Meeting(audioTranscript: "Completed transcript")
    meeting.localTranscriptionModelRaw = "base"
    meeting.updateProcessingPhase(.generatingSummary)
    meeting.migrateRetiredLocalModel()
    #expect(meeting.audioTranscript == "Completed transcript")
    #expect(meeting.localTranscriptionModel == .parakeetUltra)
  }

  @Test func migratingFailedWhisperAnalysisPreservesCompletedTranscript() {
    let meeting = Meeting(audioTranscript: "Completed transcript")
    meeting.localTranscriptionModelRaw = "small"
    meeting.lastProcessedChunk = 4
    meeting.totalChunks = 4
    meeting.updateProcessingPhase(.generatingOverview)
    meeting.markLocalJobFailed("Analysis failed")
    meeting.migrateRetiredLocalModel()
    #expect(meeting.audioTranscript == "Completed transcript")
    #expect(meeting.resumePhase == .generatingOverview)
  }
}
