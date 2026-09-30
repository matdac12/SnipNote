import XCTest
@testable import SnipNote

@MainActor
final class CloudTranscriptionRoutingTests: XCTestCase {
  func testProviderSurvivesPreferenceChangeBetweenChunks() async throws {
    try await runRouting(duration: 65, retry: false)
  }

  func testProviderSurvivesRequestRetry() async throws {
    try await runRouting(duration: 1, retry: true)
  }

  private func runRouting(duration: TimeInterval, retry: Bool) async throws {
    let settings = CloudTranscriptionSettings.shared
    let manager = LocalTranscriptionManager.shared
    let oldProvider = settings.selectedProvider
    let oldMode = manager.transcriptionMode
    settings.selectedProvider = .xai
    manager.setTranscriptionMode(.cloud)
    TestURLProtocol.reset()
    defer {
      settings.selectedProvider = oldProvider
      manager.setTranscriptionMode(oldMode)
      TestURLProtocol.reset()
    }
    let url = try TranscriptionAudioFixture.make(duration: duration)
    defer { try? FileManager.default.removeItem(at: url) }
    if !retry { XCTAssertTrue(try AudioChunker.needsChunking(url: url)) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TestURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let service = OpenAIService(urlSession: session, accessTokenProvider: { "fixture-token" })
    let transcript = Data(#"{"text":"Meeting transcript"}"#.utf8)
    TestURLProtocol.addStub(matcher: { _ in
      // Complete the preference change before returning the first HTTP response.
      let changed = DispatchSemaphore(value: 0)
      Task { @MainActor in
        CloudTranscriptionSettings.shared.selectedProvider = .openai
        changed.signal()
      }
      changed.wait()
      return true
    }, response: .success(statusCode: retry ? 500 : 200, body: retry ? Data(#"{"error":{"message":"HTTP 500"}}"#.utf8) : transcript))
    for _ in 0..<5 { TestURLProtocol.addStub(response: .success(body: transcript)) }
    let output = try await TranscriptionRouter(openAIService: service).transcribeAudioFromURL(audioURL: url, progressCallback: { _ in })
    XCTAssertTrue(output.contains("Meeting transcript"))
    let requests = TestURLProtocol.requests()
    XCTAssertGreaterThanOrEqual(requests.count, 2)
    XCTAssertEqual(settings.selectedProvider, .openai)
    for request in requests {
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-SnipNote-Transcription-Provider"), "xai")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
    }
  }
}
