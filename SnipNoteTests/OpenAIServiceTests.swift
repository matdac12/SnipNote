import XCTest
@testable import SnipNote

final class OpenAIServiceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        TestURLProtocol.register()
        TestURLProtocol.reset()
    }

    override func tearDown() {
        super.tearDown()
        TestURLProtocol.reset()
    }

    func testURLSessionIsConfiguredWithCustomTimeouts() throws {
        let service = OpenAIService.shared
        let mirror = Mirror(reflecting: service)

        guard let urlSessionProperty = mirror.children.first(where: { $0.label == "urlSession" })?.value as? URLSession else {
            XCTFail("Unable to access urlSession via reflection")
            return
        }

        XCTAssertEqual(urlSessionProperty.configuration.timeoutIntervalForRequest, 120)
        XCTAssertEqual(urlSessionProperty.configuration.timeoutIntervalForResource, 600)
    }

    func testMergeSkipsLeadingEmptyChunk() {
        let service = OpenAIService.shared
        let transcripts = ["", "Second chunk text", "Third chunk"]

        #if DEBUG
        let merged = service.testMergeChunkTranscripts(transcripts)
        #else
        let merged = ""
        #endif

        XCTAssertTrue(merged.contains("Second chunk text"))
        XCTAssertTrue(merged.contains("Third chunk"))
        XCTAssertFalse(merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testMergeReturnsEmptyWhenAllChunksEmpty() {
        let service = OpenAIService.shared
        let transcripts = ["   ", "", "\n"]

        #if DEBUG
        let merged = service.testMergeChunkTranscripts(transcripts)
        #else
        let merged = ""
        #endif

        XCTAssertTrue(merged.isEmpty)
    }
}
