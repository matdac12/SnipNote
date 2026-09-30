import AVFoundation
import Foundation

/// Valid PCM audio: long fixture crosses the real 1.5 MB chunk threshold.
enum TranscriptionAudioFixture {
  static func make(duration: TimeInterval) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("provider-\(UUID()).wav")
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000),
          let samples = buffer.floatChannelData?[0] else {
      throw CocoaError(.fileWriteUnknown)
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    var remaining = Int(duration * 16_000)
    var frame = 0
    while remaining > 0 {
      let count = min(remaining, 16_000)
      buffer.frameLength = AVAudioFrameCount(count)
      for index in 0..<count {
        samples[index] = Float(sin(Double(frame + index) * 2 * .pi * 440 / 16_000)) * 0.1
      }
      try file.write(from: buffer)
      remaining -= count
      frame += count
    }
    return url
  }
}
