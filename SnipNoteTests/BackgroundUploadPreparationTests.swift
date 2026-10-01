import AVFoundation
import Foundation
import Testing
@testable import SnipNote

struct BackgroundUploadPreparationTests {
  private func fixture(in root: URL) throws -> URL {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("fixture.wav")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32000))
    buffer.frameLength = 32000
    let channel = try #require(buffer.floatChannelData?[0])
    for i in 0..<32000 { channel[i] = Float(sin(Double(i) * 0.1)) * 0.1 }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
  }
  @Test func preparationPreservesOrderedAudioCoverage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(in: root)
    let files = try await AudioChunker.prepareUploadFiles(from: source, directory: root.appendingPathComponent("prepared"), targetBytes: 16 * 1024)
    #expect(files.map(\.index) == Array(0..<files.count))
    #expect(abs(files.reduce(0) { $0 + $1.duration } - 2) < 0.01)
    #expect(files.allSatisfy { $0.expectedBytes > 0 && $0.expectedBytes <= 16 * 1024 })
    for file in files {
      let asset = AVURLAsset(url: root.appendingPathComponent("prepared").appendingPathComponent(file.relativePath))
      let duration = try await asset.load(.duration).seconds
      #expect(abs(duration - file.duration) < 0.1)
    }
  }
  @Test func smallAudioUsesStableFile() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(in: root)
    let directory = root.appendingPathComponent("prepared")
    let files = try await AudioChunker.prepareUploadFiles(from: source, directory: directory)
    #expect(files.count == 1)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(files[0].relativePath).path))
    #expect(FileManager.default.fileExists(atPath: source.path))
  }
  @Test func diskFullRetainsSourceAndReportsPreparationFailure() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(in: root)
    await #expect(throws: BackgroundUploadFailure.self) {
      try await AudioChunker.prepareUploadFiles(from: source, directory: root.appendingPathComponent("prepared"), availableBytes: { 0 })
    }
    #expect(FileManager.default.fileExists(atPath: source.path))
  }
}
