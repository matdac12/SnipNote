import Foundation
import Testing
@testable import SnipNote

struct ParakeetTranscriptionServiceTests {
  @Test func uninstalledReduxReportsTheSelectedModelWithoutDownloading() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let service = ParakeetTranscriptionService(store: ParakeetModelStore(model: .parakeetRedux, rootDirectory: root))
    do {
      _ = try await service.makeSession()
      Issue.record("Missing Redux files must prevent inference")
    } catch let error as LocalTranscriptionError {
      guard case .modelNotInstalled(.parakeetRedux) = error else {
        Issue.record("Unexpected error: \(error)")
        return
      }
    }
    #expect(!FileManager.default.fileExists(atPath: root.path))
  }

  @Test func tinyTailChunkIsPaddedWithoutDroppingItsAudio() throws {
    let padded = try ParakeetTranscriptionService.prepareChunkSamples([0.25, -0.25])
    #expect(padded.count == 4_800)
    #expect(Array(padded.prefix(2)) == [0.25, -0.25])
    #expect(padded.dropFirst(2).allSatisfy { $0 == 0 })
    let regular = [Float](repeating: 0.5, count: 16_000)
    #expect(try ParakeetTranscriptionService.prepareChunkSamples(regular) == regular)
    #expect(throws: LocalTranscriptionError.self) {
      try ParakeetTranscriptionService.prepareChunkSamples([])
    }
  }

  @Test func uninstalledModelFailsLocallyWithoutDownloading() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let service = ParakeetTranscriptionService(store: ParakeetModelStore(rootDirectory: root))
    #expect(await service.status() == .notInstalled)
    do {
      _ = try await service.makeSession()
      Issue.record("Missing Ultra files should prevent inference")
    } catch let error as LocalTranscriptionError {
      guard case .modelNotInstalled(.parakeetUltra) = error else {
        Issue.record("Unexpected error: \(error)")
        return
      }
    }
    #expect(!FileManager.default.fileExists(atPath: root.path))
  }

  @Test func regionalLanguageCodesAreNormalizedAndAutoDetectionHasNoHint() throws {
    #expect(try ParakeetTranscriptionService.languageHint(for: "it-IT")?.rawValue == "it")
    #expect(try ParakeetTranscriptionService.languageHint(for: "EN_us")?.rawValue == "en")
    #expect(try ParakeetTranscriptionService.languageHint(for: nil) == nil)
    #expect(try ParakeetTranscriptionService.languageHint(for: "") == nil)
  }

  @Test func unsupportedLanguageDoesNotSilentlyFallBackToAutoDetection() {
    #expect(throws: LocalTranscriptionError.self) {
      try ParakeetTranscriptionService.languageHint(for: "ja")
    }
    #expect(throws: LocalTranscriptionError.self) {
      try ParakeetTranscriptionService.languageHint(for: "unknown")
    }
  }
}
