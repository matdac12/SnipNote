import Testing
@testable import SnipNote

struct LocalSpeechPlanValidationTests {
  @Test func longSpeechSplitsAtNearbySilenceWithoutDroppingSamples() {
    var samples = [Float](repeating: 0.5, count: 22_000)
    for index in 14_000..<15_000 { samples[index] = 0 }
    let chunks = LocalAudioPreprocessor.splitAtSilence(
      [LocalSpeechChunk(startSample: 0, endSample: 22_000)],
      audioSamples: samples, maxChunkLength: 16_000, sampleRate: 1_000)
    #expect(chunks.count == 2)
    #expect(chunks[0].endSample >= 14_000 && chunks[0].endSample <= 15_000)
    #expect(chunks[0].startSample == 0)
    #expect(chunks[1].startSample == chunks[0].endSample)
    #expect(chunks[1].endSample == 22_000)
  }

  @Test func whisperSizedCachedChunkIsRejectedForParakeet() {
    let plan = LocalSpeechChunkPlan(sourceAudioPath: "/audio", fingerprint: "a", sampleRate: 16_000,
      chunks: [LocalSpeechChunk(startSample: 0, endSample: 480_000)])
    #expect(!LocalAudioPreprocessor.isValidCachedPlan(plan, totalSampleCount: 480_000, maxChunkLength: 240_000))
    #expect(LocalAudioPreprocessor.isValidCachedPlan(plan, totalSampleCount: 480_000, maxChunkLength: 480_000))
  }

  @Test func corruptCachedSampleRangesAreRejected() {
    for chunk in [LocalSpeechChunk(startSample: -1, endSample: 100),
                  LocalSpeechChunk(startSample: 20, endSample: 10),
                  LocalSpeechChunk(startSample: 0, endSample: 101)] {
      let plan = LocalSpeechChunkPlan(sourceAudioPath: "/audio", fingerprint: "a", sampleRate: 16_000, chunks: [chunk])
      #expect(!LocalAudioPreprocessor.isValidCachedPlan(plan, totalSampleCount: 100, maxChunkLength: 240_000))
    }
  }
}
