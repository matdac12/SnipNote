import Foundation
import Testing
@testable import SnipNote

@MainActor struct BackgroundUploadStoreTests {
  @Test func atomicSaveRetainsPreviousManifestOnFailure() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = BackgroundUploadStore(root: root)
    var manifest = BackgroundUploadManifest(userID: UUID(), meetingID: UUID(), sourceRelativePath: "source.m4a", options: UploadOptions(provider: "xai", language: "it", duration: 10))
    try store.save(manifest)
    manifest.phase = .retry
    let failing = BackgroundUploadStore(root: root, write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
    #expect(throws: CocoaError.self) { try failing.save(manifest) }
    #expect(try store.load(userID: manifest.userID).first?.phase == .preparing)
  }
  @Test func manifestPathsCannotEscapeUploadDirectory() throws {
    let store = BackgroundUploadStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    var manifest = BackgroundUploadManifest(userID: UUID(), meetingID: UUID(), sourceRelativePath: "../secret", options: UploadOptions(provider: "xai", language: nil, duration: 10))
    #expect(throws: BackgroundUploadFailure.self) { try store.save(manifest) }
    manifest.sourceRelativePath = "/absolute"
    #expect(throws: BackgroundUploadFailure.self) { try store.save(manifest) }
  }
}
