//
//  OpenAIServiceTests.swift
//  SnipNoteTests
//
//  Created for Transcription System Production Hardening
//

import Foundation
import Testing
@testable import SnipNote

struct OpenAIServiceTests {

    // MARK: - Task 1.6: URLSession Timeout Configuration Tests

    @Test("URLSession should have correct timeout configuration")
    @MainActor
    func testURLSessionTimeoutConfiguration() async throws {
        // Given: OpenAIService instance
        let service = OpenAIService.shared

        // When: Accessing the URLSession configuration through reflection
        let mirror = Mirror(reflecting: service)
        guard let urlSessionProperty = mirror.children.first(where: { $0.label == "urlSession" }),
              let urlSession = urlSessionProperty.value as? URLSession else {
            throw TestError.propertyNotFound
        }

        // Then: Verify timeout intervals are configured correctly
        #expect(urlSession.configuration.timeoutIntervalForRequest == 120, "Request timeout should be 120 seconds (2 minutes)")
        #expect(urlSession.configuration.timeoutIntervalForResource == 600, "Resource timeout should be 600 seconds (10 minutes)")

        print("✅ URLSession timeout configuration test passed")
    }

    @Test("URLSession should timeout after expected duration")
    @MainActor
    func testURLSessionTimeoutTriggers() async throws {
        // Given: A URLSession with short timeout for testing
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 1 // 1 second timeout for fast test
        let testSession = URLSession(configuration: configuration)

        // When: Making a request to a slow/hanging endpoint
        // Using httpbin.org/delay endpoint which intentionally delays response
        guard let url = URL(string: "https://httpbin.org/delay/5") else {
            throw TestError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        var didTimeout = false

        do {
            // This should timeout after 1 second (before the 5 second delay completes)
            _ = try await testSession.data(for: request)
        } catch let error as URLError {
            // Verify it's a timeout error
            if error.code == .timedOut {
                didTimeout = true
                print("✅ Request timed out as expected: \(error.localizedDescription)")
            }
        } catch {
            print("⚠️ Unexpected error type: \(error)")
        }

        // Then: Verify timeout occurred
        #expect(didTimeout, "Request should have timed out after 1 second")

        print("✅ URLSession timeout trigger test passed")
    }
}

// MARK: - Test Errors

enum TestError: Error {
    case propertyNotFound
    case invalidURL
}
