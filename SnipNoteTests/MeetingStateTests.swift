import XCTest
@testable import SnipNote

final class MeetingStateTests: XCTestCase {
    func testHasTranscriptContentIgnoresPlaceholders() {
        let meeting = Meeting()

        meeting.audioTranscript = "Transcribing meeting audio..."
        XCTAssertFalse(meeting.hasTranscriptContent)

        meeting.audioTranscript = "Transcription failed"
        XCTAssertFalse(meeting.hasTranscriptContent)

        meeting.audioTranscript = "Actual transcript content"
        XCTAssertTrue(meeting.hasTranscriptContent)
    }

    func testCanRetryAnalysisRequiresTranscriptAndLocalAudioPath() {
        let meeting = Meeting()

        meeting.audioTranscript = "Actual transcript content"
        meeting.localAudioPath = "/tmp/audio.m4a"
        meeting.setProcessingError("Transcript saved, but AI analysis failed.")

        XCTAssertTrue(meeting.canRetryAnalysis)

        meeting.localAudioPath = nil
        XCTAssertFalse(meeting.canRetryAnalysis)
    }

    func testAnalysisUnavailableCompletesWithTranscriptAndNoError() {
        let meeting = Meeting()
        meeting.audioTranscript = "Actual transcript content"
        meeting.shortSummary = "Generating overview..."
        meeting.aiSummary = "Generating meeting summary..."
        meeting.updateProcessingState(.generatingSummary)

        meeting.markAnalysisUnavailable(.appleIntelligenceNotEnabled)

        XCTAssertEqual(meeting.processingState, .completed)
        XCTAssertNil(meeting.processingError)
        XCTAssertEqual(meeting.analysisUnavailableReason, .appleIntelligenceNotEnabled)
        XCTAssertTrue(meeting.shortSummary.isEmpty)
        XCTAssertTrue(meeting.aiSummary.isEmpty)
        XCTAssertTrue(meeting.hasTranscriptContent)
        XCTAssertFalse(meeting.canRetryAnalysis)
        XCTAssertTrue(meeting.canGenerateSummaryAfterUnavailable)

        meeting.markAnalysisUnavailable(.deviceNotEligible)
        XCTAssertFalse(meeting.canGenerateSummaryAfterUnavailable)

        meeting.markCompleted()
        XCTAssertNil(meeting.analysisUnavailableReason)
    }
}
