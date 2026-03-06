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
}
