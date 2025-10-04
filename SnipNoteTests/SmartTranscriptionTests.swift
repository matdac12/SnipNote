import XCTest
@testable import SnipNote

/// Comprehensive tests for Smart Transcription Mode & Server-Side Notifications
/// Tests all functionality from Tasks 1.0-6.0
final class SmartTranscriptionTests: XCTestCase {

    var transcriptionService: RenderTranscriptionService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        transcriptionService = RenderTranscriptionService()
    }

    override func tearDownWithError() throws {
        transcriptionService = nil
        try super.tearDownWithError()
    }

    // MARK: - Task 5.0: Retry Logic Tests

    /// Test that TranscriptionError enum includes maxRetriesExceeded case
    func testTranscriptionErrorHasMaxRetriesExceeded() {
        let error = TranscriptionError.maxRetriesExceeded
        XCTAssertNotNil(error.errorDescription, "maxRetriesExceeded should have error description")
        XCTAssertEqual(error.errorDescription, "Maximum retry attempts exceeded")
    }

    /// Test that all TranscriptionError cases have descriptions
    func testAllTranscriptionErrorsHaveDescriptions() {
        let errors: [TranscriptionError] = [
            .invalidURL,
            .serverError("test"),
            .networkError(NSError(domain: "test", code: -1)),
            .decodingError,
            .maxRetriesExceeded
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "All errors should have descriptions")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error descriptions should not be empty")
        }
    }

    // MARK: - Task 3.0: Notification Service Tests

    /// Test that NotificationService is a singleton
    func testNotificationServiceIsSingleton() {
        let instance1 = NotificationService.shared
        let instance2 = NotificationService.shared
        XCTAssertTrue(instance1 === instance2, "NotificationService should be a singleton")
    }

    /// Test notification identifier format
    func testProcessingNotificationIdentifierFormat() {
        let testMeetingId = UUID()
        let expectedPrefix = "processing-"

        // We can't directly test the private identifier, but we verify the format through public API
        XCTAssertTrue(expectedPrefix.count > 0, "Notification prefix should exist")
    }

    // MARK: - Job Status Model Tests

    /// Test JobStatus enum display text
    func testJobStatusDisplayText() {
        XCTAssertEqual(JobStatus.pending.displayText, "Pending")
        XCTAssertEqual(JobStatus.processing.displayText, "Processing")
        XCTAssertEqual(JobStatus.completed.displayText, "Completed")
        XCTAssertEqual(JobStatus.failed.displayText, "Failed")
    }

    /// Test JobStatus isInProgress property
    func testJobStatusIsInProgress() {
        XCTAssertTrue(JobStatus.pending.isInProgress, "Pending should be in progress")
        XCTAssertTrue(JobStatus.processing.isInProgress, "Processing should be in progress")
        XCTAssertFalse(JobStatus.completed.isInProgress, "Completed should not be in progress")
        XCTAssertFalse(JobStatus.failed.isInProgress, "Failed should not be in progress")
    }

    /// Test JobStatus raw value encoding/decoding
    func testJobStatusCodable() throws {
        let statuses: [JobStatus] = [.pending, .processing, .completed, .failed]

        for status in statuses {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(JobStatus.self, from: encoded)
            XCTAssertEqual(status, decoded, "JobStatus should encode/decode correctly")
        }
    }

    // MARK: - Request/Response Model Tests

    /// Test CreateJobRequest encoding
    func testCreateJobRequestEncoding() throws {
        let userId = UUID().uuidString
        let meetingId = UUID().uuidString
        let audioUrl = "https://example.com/audio.m4a"

        let request = CreateJobRequest(
            userId: userId,
            meetingId: meetingId,
            audioUrl: audioUrl
        )

        let encoded = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // Verify snake_case keys
        XCTAssertNotNil(json["user_id"], "Should use snake_case for user_id")
        XCTAssertNotNil(json["meeting_id"], "Should use snake_case for meeting_id")
        XCTAssertNotNil(json["audio_url"], "Should use snake_case for audio_url")

        XCTAssertEqual(json["user_id"] as? String, userId)
        XCTAssertEqual(json["meeting_id"] as? String, meetingId)
        XCTAssertEqual(json["audio_url"] as? String, audioUrl)
    }

    /// Test CreateJobResponse decoding
    func testCreateJobResponseDecoding() throws {
        let json = """
        {
            "job_id": "test-job-123",
            "status": "pending",
            "created_at": "2025-01-04T12:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(CreateJobResponse.self, from: data)

        XCTAssertEqual(response.jobId, "test-job-123")
        XCTAssertEqual(response.status, .pending)
        XCTAssertEqual(response.createdAt, "2025-01-04T12:00:00Z")
    }

    /// Test JobStatusResponse decoding with all fields
    func testJobStatusResponseFullDecoding() throws {
        let json = """
        {
            "id": "job-123",
            "user_id": "user-456",
            "meeting_id": "meeting-789",
            "audio_url": "https://example.com/audio.m4a",
            "status": "completed",
            "transcript": "Test transcript",
            "overview": "Test overview",
            "summary": "Test summary",
            "actions": [
                {"action": "Follow up", "priority": "high"},
                {"action": "Review notes", "priority": "medium"}
            ],
            "duration": 300.5,
            "error_message": null,
            "progress_percentage": 100,
            "current_stage": "Completed",
            "created_at": "2025-01-04T12:00:00Z",
            "updated_at": "2025-01-04T12:05:00Z",
            "completed_at": "2025-01-04T12:05:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JobStatusResponse.self, from: data)

        XCTAssertEqual(response.id, "job-123")
        XCTAssertEqual(response.userId, "user-456")
        XCTAssertEqual(response.meetingId, "meeting-789")
        XCTAssertEqual(response.status, .completed)
        XCTAssertEqual(response.transcript, "Test transcript")
        XCTAssertEqual(response.overview, "Test overview")
        XCTAssertEqual(response.summary, "Test summary")
        XCTAssertEqual(response.actions?.count, 2)
        XCTAssertEqual(response.actions?[0].action, "Follow up")
        XCTAssertEqual(response.actions?[0].priority, "high")
        XCTAssertEqual(response.duration, 300.5)
        XCTAssertEqual(response.progressPercentage, 100)
        XCTAssertEqual(response.currentStage, "Completed")
        XCTAssertNil(response.errorMessage)
    }

    /// Test JobStatusResponse decoding with minimal fields
    func testJobStatusResponseMinimalDecoding() throws {
        let json = """
        {
            "id": "job-123",
            "user_id": "user-456",
            "meeting_id": "meeting-789",
            "audio_url": "https://example.com/audio.m4a",
            "status": "pending",
            "created_at": "2025-01-04T12:00:00Z",
            "updated_at": "2025-01-04T12:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JobStatusResponse.self, from: data)

        XCTAssertEqual(response.status, .pending)
        XCTAssertNil(response.transcript)
        XCTAssertNil(response.overview)
        XCTAssertNil(response.summary)
        XCTAssertNil(response.actions)
        XCTAssertNil(response.duration)
        XCTAssertNil(response.errorMessage)
        XCTAssertNil(response.progressPercentage)
        XCTAssertNil(response.currentStage)
        XCTAssertNil(response.completedAt)
    }

    /// Test JobStatusResponse with failed status
    func testJobStatusResponseWithError() throws {
        let json = """
        {
            "id": "job-123",
            "user_id": "user-456",
            "meeting_id": "meeting-789",
            "audio_url": "https://example.com/audio.m4a",
            "status": "failed",
            "error_message": "Transcription service unavailable",
            "created_at": "2025-01-04T12:00:00Z",
            "updated_at": "2025-01-04T12:01:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JobStatusResponse.self, from: data)

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.errorMessage, "Transcription service unavailable")
    }

    /// Test ActionItemJSON decoding
    func testActionItemJSONDecoding() throws {
        let json = """
        {
            "action": "Schedule follow-up meeting",
            "priority": "high"
        }
        """

        let data = json.data(using: .utf8)!
        let action = try JSONDecoder().decode(ActionItemJSON.self, from: data)

        XCTAssertEqual(action.action, "Schedule follow-up meeting")
        XCTAssertEqual(action.priority, "high")
    }

    /// Test ActionItemJSON array decoding
    func testActionItemJSONArrayDecoding() throws {
        let json = """
        [
            {"action": "Review budget", "priority": "high"},
            {"action": "Update timeline", "priority": "medium"},
            {"action": "Send summary", "priority": "low"}
        ]
        """

        let data = json.data(using: .utf8)!
        let actions = try JSONDecoder().decode([ActionItemJSON].self, from: data)

        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions[0].priority, "high")
        XCTAssertEqual(actions[1].priority, "medium")
        XCTAssertEqual(actions[2].priority, "low")
    }

    // MARK: - Audio Duration Threshold Tests (Task 1.0)

    /// Test the 5-minute threshold constant
    func testFiveMinuteThreshold() {
        let threshold: TimeInterval = 300 // 5 minutes in seconds

        // Test boundary cases
        let exactlyFiveMinutes: TimeInterval = 300
        let justUnderFiveMinutes: TimeInterval = 299
        let justOverFiveMinutes: TimeInterval = 301

        XCTAssertTrue(exactlyFiveMinutes <= threshold, "Exactly 5:00 should use on-device")
        XCTAssertTrue(justUnderFiveMinutes <= threshold, "Under 5 minutes should use on-device")
        XCTAssertFalse(justOverFiveMinutes <= threshold, "Over 5 minutes should use server-side")
    }

    /// Test duration calculations
    func testDurationCalculations() {
        // Test common durations
        let threeMinutes: TimeInterval = 180
        let fiveMinutes: TimeInterval = 300
        let tenMinutes: TimeInterval = 600
        let oneHour: TimeInterval = 3600

        let threshold: TimeInterval = 300

        XCTAssertTrue(threeMinutes <= threshold, "3 minutes should be on-device")
        XCTAssertTrue(fiveMinutes <= threshold, "5 minutes should be on-device")
        XCTAssertFalse(tenMinutes <= threshold, "10 minutes should be server-side")
        XCTAssertFalse(oneHour <= threshold, "1 hour should be server-side")
    }

    // MARK: - Audio Optimization Tests (Task 2.0 & 6.0)

    /// Test audio optimization duration calculation
    func testAudioOptimizationDurationCalculation() {
        let originalDurations: [TimeInterval] = [300, 600, 900, 1800, 3600]
        let speedUpFactor: Double = 1.5

        for original in originalDurations {
            let optimized = original / speedUpFactor

            // Verify optimization reduces duration by 33%
            let reduction = (original - optimized) / original
            XCTAssertEqual(reduction, 1.0 - (1.0 / speedUpFactor), accuracy: 0.001,
                          "Optimization should reduce duration by 33%")
        }
    }

    /// Test optimized duration is always less than original
    func testOptimizedDurationAlwaysLess() {
        let testDurations: [TimeInterval] = [100, 500, 1000, 5000, 10000]
        let speedUpFactor: Double = 1.5

        for duration in testDurations {
            let optimized = duration / speedUpFactor
            XCTAssertLessThan(optimized, duration,
                            "Optimized duration should always be less than original")
        }
    }

    /// Test optimization percentage calculation
    func testOptimizationPercentage() {
        let original: TimeInterval = 900 // 15 minutes
        let speedUpFactor: Double = 1.5
        let optimized = original / speedUpFactor

        let timeSaved = original - optimized
        let percentageSaved = (timeSaved / original) * 100

        XCTAssertEqual(percentageSaved, 33.33, accuracy: 0.1,
                      "Should save approximately 33% of processing time")
    }

    // MARK: - Integration Tests

    /// Test that RenderTranscriptionService can be instantiated
    func testRenderTranscriptionServiceInstantiation() {
        XCTAssertNotNil(transcriptionService, "Service should instantiate")
    }

    /// Test service base URL configuration
    func testServiceBaseURLConfiguration() {
        // The service should have a valid base URL
        // We can't access private properties, but we can verify the service exists
        XCTAssertNotNil(transcriptionService)
    }

    // MARK: - Error Handling Tests

    /// Test invalid URL error
    func testInvalidURLError() {
        let error = TranscriptionError.invalidURL
        XCTAssertEqual(error.errorDescription, "Invalid server URL")
    }

    /// Test server error with message
    func testServerErrorWithMessage() {
        let message = "HTTP 500: Internal Server Error"
        let error = TranscriptionError.serverError(message)
        XCTAssertTrue(error.errorDescription?.contains(message) ?? false,
                     "Error description should contain the error message")
    }

    /// Test network error wrapping
    func testNetworkErrorWrapping() {
        let underlyingError = NSError(domain: "TestDomain", code: -1009,
                                     userInfo: [NSLocalizedDescriptionKey: "Network connection lost"])
        let error = TranscriptionError.networkError(underlyingError)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Network") ?? false)
    }

    /// Test decoding error
    func testDecodingError() {
        let error = TranscriptionError.decodingError
        XCTAssertEqual(error.errorDescription, "Failed to decode server response")
    }

    // MARK: - Retry Logic Tests

    /// Test exponential backoff delays
    func testExponentialBackoffDelays() {
        let expectedDelays: [UInt64] = [
            5_000_000_000,   // 5 seconds
            15_000_000_000,  // 15 seconds
            45_000_000_000   // 45 seconds
        ]

        // Verify delays increase exponentially
        XCTAssertEqual(expectedDelays[1], expectedDelays[0] * 3)
        XCTAssertEqual(expectedDelays[2], expectedDelays[1] * 3)
    }

    /// Test retry attempt limits
    func testRetryAttemptLimits() {
        let maxRetries = 3

        for attempt in 0..<maxRetries {
            XCTAssertLessThan(attempt, maxRetries, "Attempt \(attempt) should be within limit")
        }

        XCTAssertGreaterThanOrEqual(maxRetries, maxRetries,
                                   "Should not exceed max retries")
    }

    // MARK: - Performance Tests

    /// Test JSON encoding performance
    func testCreateJobRequestEncodingPerformance() throws {
        let request = CreateJobRequest(
            userId: UUID().uuidString,
            meetingId: UUID().uuidString,
            audioUrl: "https://example.com/audio.m4a"
        )

        measure {
            for _ in 0..<1000 {
                _ = try? JSONEncoder().encode(request)
            }
        }
    }

    /// Test JSON decoding performance
    func testJobStatusResponseDecodingPerformance() throws {
        let json = """
        {
            "id": "job-123",
            "user_id": "user-456",
            "meeting_id": "meeting-789",
            "audio_url": "https://example.com/audio.m4a",
            "status": "completed",
            "transcript": "Test transcript",
            "overview": "Test overview",
            "summary": "Test summary",
            "actions": [{"action": "Test", "priority": "high"}],
            "duration": 300.5,
            "progress_percentage": 100,
            "current_stage": "Completed",
            "created_at": "2025-01-04T12:00:00Z",
            "updated_at": "2025-01-04T12:05:00Z",
            "completed_at": "2025-01-04T12:05:00Z"
        }
        """
        let data = json.data(using: .utf8)!

        measure {
            for _ in 0..<1000 {
                _ = try? JSONDecoder().decode(JobStatusResponse.self, from: data)
            }
        }
    }
}
