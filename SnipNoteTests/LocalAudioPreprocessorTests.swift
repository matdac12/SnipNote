import XCTest
@testable import SnipNote

final class LocalAudioPreprocessorTests: XCTestCase {
    func testMergeActiveRangesPadsAndMergesCloseSpeech() {
        let merged = LocalAudioPreprocessor.mergeActiveRanges(
            [
                (startIndex: 1_600, endIndex: 3_200),
                (startIndex: 3_600, endIndex: 5_000),
                (startIndex: 20_000, endIndex: 20_800)
            ],
            totalSampleCount: 40_000,
            sampleRate: 16_000,
            mergeGapSeconds: 0.8,
            leadingPaddingSeconds: 0.2,
            trailingPaddingSeconds: 0.35,
            minimumChunkDurationSeconds: 0.35
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0], LocalSpeechChunk(startSample: 0, endSample: 10_600))
        XCTAssertEqual(merged[1], LocalSpeechChunk(startSample: 16_800, endSample: 26_400))
    }

    func testMergeActiveRangesDropsTinySegments() {
        let merged = LocalAudioPreprocessor.mergeActiveRanges(
            [(startIndex: 5_000, endIndex: 5_600)],
            totalSampleCount: 20_000,
            sampleRate: 16_000,
            mergeGapSeconds: 0.8,
            leadingPaddingSeconds: 0.0,
            trailingPaddingSeconds: 0.0,
            minimumChunkDurationSeconds: 0.35
        )

        XCTAssertTrue(merged.isEmpty)
    }

    func testSpeechPlanEncodingRoundTrip() {
        let plan = LocalSpeechChunkPlan(
            sourceAudioPath: "/tmp/audio.m4a",
            fingerprint: "abc123",
            sampleRate: 16_000,
            chunks: [
                LocalSpeechChunk(startSample: 0, endSample: 1_600),
                LocalSpeechChunk(startSample: 3_200, endSample: 4_800)
            ]
        )

        let encoded = LocalAudioPreprocessor.encodePlan(plan)
        let decoded = encoded.flatMap(LocalAudioPreprocessor.decodePlan)

        XCTAssertEqual(decoded, plan)
    }

    func testSplitMergedRangesRespectsMaxChunkLength() {
        let chunks = LocalAudioPreprocessor.splitMergedRanges(
            [LocalSpeechChunk(startSample: 0, endSample: 1_100_000)],
            maxChunkLength: 480_000
        )

        XCTAssertEqual(chunks, [
            LocalSpeechChunk(startSample: 0, endSample: 480_000),
            LocalSpeechChunk(startSample: 480_000, endSample: 960_000),
            LocalSpeechChunk(startSample: 960_000, endSample: 1_100_000)
        ])
    }
}
