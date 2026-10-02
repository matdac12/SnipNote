import XCTest
import AVFoundation
@testable import SnipNote

final class LocalAudioPreprocessorTests: XCTestCase {
    func testPrepareStereoAudioResamplesAndKeepsSpeechAtTheTail() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
        buffer.frameLength = 96_000
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<2 {
            for index in 0..<96_000 {
                channels[channel][index] = index >= 48_000 ? 0.25 : 0
            }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let prepared = try await LocalAudioPreprocessor.shared.prepareAudio(from: url, maxChunkLength: 16_000)
        XCTAssertEqual(prepared.plan.sampleRate, 16_000)
        XCTAssertEqual(Double(prepared.audioSamples.count), 32_000, accuracy: 20)
        XCTAssertEqual(prepared.plan.chunks.last?.endSample, prepared.audioSamples.count)
        XCTAssertTrue(prepared.plan.chunks.allSatisfy { $0.sampleCount <= 16_000 })
        XCTAssertGreaterThan(prepared.audioSamples.last ?? 0, 0.1)
    }

    func testSilentAudioDoesNotProduceATranscriptionPlan() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        let channel = try XCTUnwrap(buffer.floatChannelData)[0]
        channel.initialize(repeating: 0, count: 16_000)
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        do {
            _ = try await LocalAudioPreprocessor.shared.prepareAudio(from: url, maxChunkLength: 16_000)
            XCTFail("Silence must not produce a speech plan")
        } catch LocalTranscriptionError.emptyTranscript {
            // Expected: silence has no speech to transcribe.
        }
    }

    func testMergeActiveRangesPadsAndMergesCloseSpeech() {
        let merged = LocalAudioPreprocessor.mergeActiveRanges(
            [
                (startIndex: 1_600, endIndex: 3_200),
                (startIndex: 3_600, endIndex: 5_000),
                // Keep this span beyond the merge gap after padding is applied.
                (startIndex: 30_000, endIndex: 30_800)
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
        XCTAssertEqual(merged[1], LocalSpeechChunk(startSample: 26_800, endSample: 36_400))
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
