import Foundation
import Testing
@testable import SnipNote

struct ParakeetModelStoreTests {
  @Test func deletingReduxLeavesInstalledUltraUntouched() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let ultra = ParakeetModelStore(rootDirectory: root.appendingPathComponent("ParakeetUltra"))
    let redux = ParakeetModelStore(model: .parakeetRedux, rootDirectory: root.appendingPathComponent("ParakeetRedux"))
    for store in [ultra, redux] {
      try store.prepareDirectories()
      try makeModelFixture(at: store.stagedModelDirectory)
      try store.installDownloadedModel()
    }
    #expect(ultra.isInstalled)
    #expect(redux.isInstalled)
    #expect(redux.installedModelDirectory.lastPathComponent == "parakeet-redux")
    try makeModelFixture(at: ultra.stagedModelDirectory)
    try redux.deleteModel()
    #expect(!redux.isInstalled)
    #expect(ultra.isInstalled)
    #expect(ultra.isComplete(at: ultra.stagedModelDirectory))
  }

  @Test func installsFilesFromFluidAudioDownloadFolder() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ParakeetModelStore(rootDirectory: root)
    try store.prepareDirectories()
    // FluidAudio Repo.folderName strips "-coreml" from the repository name.
    let sdkDownloadDirectory = store.stagingRootDirectory.appendingPathComponent("parakeet-ultra")
    try makeModelFixture(at: sdkDownloadDirectory)
    try store.installDownloadedModel()
    #expect(store.isInstalled)
  }

  @Test func incompleteDownloadCannotBeInstalled() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ParakeetModelStore(rootDirectory: root)
    try store.prepareDirectories()
    #expect(!store.isInstalled)
    #expect(throws: (any Error).self) { try store.installDownloadedModel() }
    #expect(!store.isInstalled)
  }

  @Test func installedModelRequiresCompleteFilesAndDeletionRemovesStaging() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ParakeetModelStore(rootDirectory: root)
    try store.prepareDirectories()
    try makeModelFixture(at: store.stagedModelDirectory)
    try store.installDownloadedModel()
    #expect(store.isInstalled)
    try Data([1]).write(to: store.installedModelDirectory.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin.partial"))
    #expect(!store.isInstalled)
    try store.deleteModel()
    #expect(!FileManager.default.fileExists(atPath: store.installedModelDirectory.path))
    #expect(!FileManager.default.fileExists(atPath: store.stagingRootDirectory.path))
  }

  @Test func missingWeightsInvalidatesInstalledModel() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ParakeetModelStore(rootDirectory: root)
    try store.prepareDirectories()
    try makeModelFixture(at: store.stagedModelDirectory)
    try store.installDownloadedModel()
    try FileManager.default.removeItem(at: store.installedModelDirectory.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin"))
    #expect(!store.isInstalled)
  }

  private func makeModelFixture(at directory: URL) throws {
    for name in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
      let bundle = directory.appendingPathComponent("\(name).mlmodelc")
      try FileManager.default.createDirectory(at: bundle.appendingPathComponent("weights"), withIntermediateDirectories: true)
      try Data([1]).write(to: bundle.appendingPathComponent("coremldata.bin"))
      try Data([1]).write(to: bundle.appendingPathComponent("model.mil"))
      if name != "Preprocessor" {
        try Data([1]).write(to: bundle.appendingPathComponent("weights/weight.bin"))
      }
    }
    try Data("{\"0\":\"a\"}".utf8).write(to: directory.appendingPathComponent("parakeet_vocab.json"))
  }
}
