import Foundation

/// Owns only one of SnipNote's Parakeet models. A completed download is promoted atomically
/// after the caller has verified that Core ML can load it.
struct ParakeetModelStore: Sendable {
  private let rootDirectory: URL
  // FluidAudio strips "-coreml" from the repository name for its download folder.
  let model: LocalTranscriptionModel
  private var folderName: String { model == .parakeetUltra ? "parakeet-ultra" : "parakeet-redux" }

  init(model: LocalTranscriptionModel = .parakeetUltra, rootDirectory: URL? = nil) {
    self.model = model
    let storageName = model == .parakeetUltra ? "ParakeetUltra" : "ParakeetRedux"
    self.rootDirectory = rootDirectory ?? URL.applicationSupportDirectory
      .appendingPathComponent("SnipNote/LocalModels/\(storageName)", isDirectory: true)
  }

  var stagingRootDirectory: URL { rootDirectory.appendingPathComponent("Staging", isDirectory: true) }
  var stagedModelDirectory: URL { stagingRootDirectory.appendingPathComponent(folderName, isDirectory: true) }
  var installedModelDirectory: URL { rootDirectory.appendingPathComponent(folderName, isDirectory: true) }
  private var markerURL: URL { installedModelDirectory.appendingPathComponent(".snipnote-installed") }

  var isInstalled: Bool {
    FileManager.default.fileExists(atPath: markerURL.path) && isComplete(at: installedModelDirectory)
  }

  func prepareDirectories() throws {
    for directory in [rootDirectory, stagingRootDirectory] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try excludeFromBackup(directory)
    }
  }

  func installDownloadedModel() throws {
    guard isComplete(at: stagedModelDirectory) else { throw LocalTranscriptionError.downloadIncomplete }
    if FileManager.default.fileExists(atPath: installedModelDirectory.path) {
      try FileManager.default.removeItem(at: installedModelDirectory)
    }
    try FileManager.default.moveItem(at: stagedModelDirectory, to: installedModelDirectory)
    try excludeFromBackup(installedModelDirectory)
    try Data("\(model.rawValue)-v1".utf8).write(to: markerURL, options: .atomic)
  }

  func deleteModel() throws {
    for directory in [installedModelDirectory, stagingRootDirectory] where FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  func isComplete(at directory: URL) -> Bool {
    let fileManager = FileManager.default
    for name in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
      let bundle = directory.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
      for file in ["coremldata.bin", "model.mil"] {
        guard isNonemptyFile(bundle.appendingPathComponent(file)) else { return false }
      }
      if name != "Preprocessor", !isNonemptyFile(bundle.appendingPathComponent("weights/weight.bin")) {
        return false
      }
    }
    guard isNonemptyFile(directory.appendingPathComponent("parakeet_vocab.json")),
          let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return false }
    for case let file as URL in enumerator where file.pathExtension == "partial" { return false }
    return true
  }

  private func isNonemptyFile(_ url: URL) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          attributes[.type] as? FileAttributeType == .typeRegular,
          let size = attributes[.size] as? NSNumber else { return false }
    return size.int64Value > 0
  }

  private func excludeFromBackup(_ directory: URL) throws {
    var url = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }
}
