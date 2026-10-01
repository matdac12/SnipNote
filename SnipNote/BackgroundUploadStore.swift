import Foundation

/// All mutations serialized by the coordinator's main actor. Contains no credentials.
@MainActor final class BackgroundUploadStore {
  let root: URL
  private let write: (Data, URL) throws -> Void
  init(root: URL? = nil, write: @escaping (Data, URL) throws -> Void = { data, url in
    try data.write(to: url, options: .atomic)
  }) {
    self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BackgroundUploads", isDirectory: true)
    self.write = write
  }
  func directory(userID: UUID, meetingID: UUID) -> URL {
    root.appendingPathComponent(userID.uuidString).appendingPathComponent(meetingID.uuidString)
  }
  func fileURL(_ relative: String, userID: UUID, meetingID: UUID) throws -> URL {
    guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw BackgroundUploadFailure.invalidPath }
    let directory = directory(userID: userID, meetingID: meetingID).resolvingSymlinksInPath().standardizedFileURL
    let file = directory.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
    guard file.path.hasPrefix(directory.path + "/") else { throw BackgroundUploadFailure.invalidPath }
    return file
  }
  func save(_ manifest: BackgroundUploadManifest) throws {
    guard manifest.version == 1 else { throw BackgroundUploadFailure.invalidManifest }
    _ = try fileURL(manifest.sourceRelativePath, userID: manifest.userID, meetingID: manifest.meetingID)
    for state in manifest.files { _ = try fileURL(state.file.relativePath, userID: manifest.userID, meetingID: manifest.meetingID) }
    let directory = directory(userID: manifest.userID, meetingID: manifest.meetingID)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Self.protect(directory)
    let url = directory.appendingPathComponent("manifest.json")
    try write(JSONEncoder().encode(manifest), url)
    try Self.protect(url)
  }
  func load(userID: UUID) throws -> [BackgroundUploadManifest] {
    let account = root.appendingPathComponent(userID.uuidString)
    guard FileManager.default.fileExists(atPath: account.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(at: account, includingPropertiesForKeys: nil).compactMap { directory in
      let url = directory.appendingPathComponent("manifest.json")
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      let manifest = try JSONDecoder().decode(BackgroundUploadManifest.self, from: Data(contentsOf: url))
      guard manifest.version == 1, manifest.userID == userID, directory.lastPathComponent == manifest.meetingID.uuidString else { throw BackgroundUploadFailure.invalidManifest }
      _ = try fileURL(manifest.sourceRelativePath, userID: userID, meetingID: manifest.meetingID)
      for file in manifest.files { _ = try fileURL(file.file.relativePath, userID: userID, meetingID: manifest.meetingID) }
      return manifest
    }
  }
  static func protect(_ url: URL) throws {
    #if os(iOS)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    #endif
    var resource = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try resource.setResourceValues(values)
  }
}
