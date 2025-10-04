import XCTest
@testable import SnipNote

@MainActor
final class RenderTranscriptionServiceTests: XCTestCase {
    private var service: RenderTranscriptionService!

    override func setUp() async throws {
        try await super.setUp()
        TestURLProtocol.register()
        TestURLProtocol.reset()
        service = RenderTranscriptionService()
    }

    override func tearDown() {
        service = nil
        TestURLProtocol.reset()
        super.tearDown()
    }

    func testCreateJobPostsExpectedJSONBody() async throws {
        let expectedJobId = "job-123"
        let responseJSON = """
        {"job_id":"\(expectedJobId)","status":"pending","created_at":"2025-01-01T12:00:00Z"}
        """.data(using: .utf8)!

        TestURLProtocol.addStub(matcher: { request in
            request.url?.path == "/jobs"
        }, response: .success(statusCode: 201, headers: ["Content-Type": "application/json"], body: responseJSON))

        let userId = UUID()
        let meetingId = UUID()
        let audioURL = "https://example.com/audio.m4a"

        let result = try await service.createJob(userId: userId, meetingId: meetingId, audioURL: audioURL)

        XCTAssertEqual(result.jobId, expectedJobId)
        XCTAssertEqual(result.status, .pending)

        let recorded = TestURLProtocol.recordedRequests()
        XCTAssertEqual(recorded.count, 1)

        guard let entry = recorded.first else {
            XCTFail("Expected request to be recorded")
            return
        }

        let request = entry.request
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(entry.body)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]

        XCTAssertEqual(decoded?["user_id"] as? String, userId.uuidString)
        XCTAssertEqual(decoded?["meeting_id"] as? String, meetingId.uuidString)
        XCTAssertEqual(decoded?["audio_url"] as? String, audioURL)
    }

    func testCreateJobSurfaceServerErrorMessage() async {
        let errorBody = "Server exploded"
        TestURLProtocol.addStub(matcher: { request in
            request.url?.path == "/jobs"
        }, response: .success(statusCode: 500, body: Data(errorBody.utf8)))

        do {
            _ = try await service.createJob(userId: UUID(), meetingId: UUID(), audioURL: "https://example.com/file.m4a")
            XCTFail("Expected error")
        } catch let error as TranscriptionError {
            if case .serverError(let message) = error {
                XCTAssertTrue(message.contains("500"))
                XCTAssertTrue(message.contains(errorBody))
            } else {
                XCTFail("Unexpected TranscriptionError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateJobPropagatesNetworkError() async {
        TestURLProtocol.addStub(matcher: { request in
            request.url?.path == "/jobs"
        }, response: .failure(URLError(.notConnectedToInternet)))

        do {
            _ = try await service.createJob(userId: UUID(), meetingId: UUID(), audioURL: "https://example.com/file.m4a")
            XCTFail("Expected network error")
        } catch let error as TranscriptionError {
            if case .networkError(let underlying) = error {
                XCTAssertEqual((underlying as? URLError)?.code, .notConnectedToInternet)
            } else {
                XCTFail("Unexpected TranscriptionError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
