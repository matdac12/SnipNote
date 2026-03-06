import XCTest
@testable import SnipNote

final class SupabaseManagerTests: XCTestCase {
    func testCompletedTranscriptionJobPayloadEncodesNullAudioURLForLocalMode() throws {
        let payload = CompletedTranscriptionJobPayload(
            userId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            meetingId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            audioURL: nil,
            status: "completed",
            transcript: "Transcript",
            duration: 120,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            overview: "Overview",
            summary: "Summary",
            actions: [ActionItem(action: "Follow up", priority: "high")],
            progressPercentage: 100,
            currentStage: "Completed"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertTrue(json.keys.contains("audio_url"))
        XCTAssertTrue(json["audio_url"] is NSNull)
        XCTAssertEqual(json["status"] as? String, "completed")
        XCTAssertEqual(json["transcript"] as? String, "Transcript")
        XCTAssertEqual(json["overview"] as? String, "Overview")
        XCTAssertEqual(json["summary"] as? String, "Summary")
    }

    func testCompletedTranscriptionJobPayloadEncodesAudioURLWhenPresent() throws {
        let payload = CompletedTranscriptionJobPayload(
            userId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            meetingId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            audioURL: "https://example.com/audio.m4a",
            status: "completed",
            transcript: "Transcript",
            duration: 120,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            overview: "Overview",
            summary: "Summary",
            actions: [],
            progressPercentage: 100,
            currentStage: "Completed"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["audio_url"] as? String, "https://example.com/audio.m4a")
    }
}
