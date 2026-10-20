import Foundation

/// Messages between SnipNote (the companion that records and transcribes) and the
/// SnipNote keyboard (a remote control: keyboards cannot use the microphone).
///
/// Both sides exchange small JSON files in the App Group. Each file has one writer:
/// SnipNote writes `companion.json`, the keyboard writes `keyboard.json`. A Darwin
/// notification after each write is only a hint to read again; the files stay authoritative.
enum DictationBridge {
  static let appGroup = "group.com.mattianalytics.snipnote"
  static let companionFile = "companion.json"
  static let keyboardFile = "keyboard.json"
  static let companionChanged = "com.mattianalytics.snipnote.dictation.companion"
  static let keyboardChanged = "com.mattianalytics.snipnote.dictation.keyboard"

  /// A companion heartbeat older than this means SnipNote is not running (or suspended).
  static let heartbeatTimeout: TimeInterval = 6

  static var directory: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appendingPathComponent("Dictation", isDirectory: true)
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }()

  static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
    guard let url = directory?.appendingPathComponent(name),
          let data = try? Data(contentsOf: url) else { return nil }
    return try? decoder.decode(type, from: data)
  }

  /// Atomic replace, then a Darwin hint so the other process reads immediately.
  static func write<T: Encodable>(_ value: T, to name: String, notify: String) throws {
    guard let directory else { throw CocoaError(.fileNoSuchFile) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try encoder.encode(value)
    try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    post(notify)
  }

  static func post(_ name: String) {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
  }
}

/// Observes one Darwin notification and calls `handler` on the main queue. Remove by releasing it.
final class DarwinObserver {
  private let name: String
  private let handler: () -> Void

  init(_ name: String, handler: @escaping () -> Void) {
    self.name = name
    self.handler = handler
    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), observer,
      { _, observer, _, _, _ in
        guard let observer else { return }
        let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async { me.handler() }
      },
      name as CFString, nil, .deliverImmediately)
  }

  deinit {
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
      CFNotificationName(name as CFString), nil)
  }
}

/// Written only by SnipNote.
struct DictationCompanionState: Codable, Equatable {
  enum Session: String, Codable {
    /// No microphone session. The keyboard asks the user to open SnipNote.
    case inactive
    /// Loading the model and starting capture.
    case preparing
    /// Capture is running; idle audio is discarded. Start/Stop work from the keyboard.
    case armed
    /// Interrupted or failed; the user must reopen SnipNote and start a new session.
    case interrupted
  }

  enum Utterance: String, Codable {
    case idle, recording, transcribing, failed
  }

  var sessionID: UUID?
  var session: Session = .inactive
  var utterance: Utterance = .idle
  var utteranceID: UUID?
  /// The keyboard interaction that started the current utterance.
  var interactionID: UUID?
  var heartbeat = Date()
  /// 0...1, updated a few times per second while recording.
  var level: Float = 0
  /// Name of the headphones or external microphone listening; nil for the device's own microphone.
  var microphoneName: String?
  var message: String?
  var result: DictationResult?
  /// Commands already applied, newest last (bounded). Lets the keyboard see acknowledgments.
  var handledCommandIDs: [UUID] = []

  var isAlive: Bool {
    session != .inactive && Date().timeIntervalSince(heartbeat) < DictationBridge.heartbeatTimeout
  }
}

/// A final transcript waiting for the keyboard. Never shown as a preview, only inserted.
struct DictationResult: Codable, Equatable {
  var id: UUID
  var utteranceID: UUID
  var interactionID: UUID
  var text: String
  var createdAt: Date
}

/// Written only by the keyboard.
struct DictationKeyboardState: Codable, Equatable {
  struct Command: Codable, Equatable {
    enum Kind: String, Codable { case start, stop, cancel, endSession }
    var id: UUID
    var kind: Kind
    var sessionID: UUID
    /// Changes every time the keyboard appears, so a result knows where it was asked for.
    var interactionID: UUID
    var issuedAt: Date
  }

  /// Recent commands, oldest first (bounded); SnipNote applies those it has not handled yet.
  var commands: [Command] = []
  /// Results the keyboard has claimed (inserted or discarded), newest last (bounded).
  var consumedResultIDs: [UUID] = []

  static let maxEntries = 20

  mutating func append(_ command: Command) {
    commands.append(command)
    if commands.count > Self.maxEntries { commands.removeFirst(commands.count - Self.maxEntries) }
  }

  mutating func consume(_ resultID: UUID) {
    guard !consumedResultIDs.contains(resultID) else { return }
    consumedResultIDs.append(resultID)
    if consumedResultIDs.count > Self.maxEntries {
      consumedResultIDs.removeFirst(consumedResultIDs.count - Self.maxEntries)
    }
  }
}
