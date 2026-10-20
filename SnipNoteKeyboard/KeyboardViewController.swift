import UIKit

/// A remote control for SnipNote's dictation session. Keyboards cannot use the microphone,
/// so SnipNote records and transcribes; this only sends Start/Stop/Cancel and inserts the
/// final text. Partial transcripts are never shown.
final class KeyboardViewController: UIInputViewController {
  private var companion = DictationCompanionState()
  private var keyboard = DictationKeyboardState()
  /// New every time the keyboard appears; a result asked for elsewhere needs explicit Insert.
  private var interactionID = UUID()
  private var isVisible = false
  /// Where the text cursor was when Stop was tapped; must still match to auto-insert.
  private var stopSnapshot: (document: UUID?, before: String?)?
  /// Commands sent but not yet acknowledged, to show "Starting…" instead of a stale state.
  private var awaitingAckFor: DictationKeyboardState.Command.Kind?
  private var observer: DarwinObserver?
  private var pollTimer: Timer?

  /// When recording started (from the Start tap), for the elapsed time.
  private var recordingStartedAt: Date?
  /// Drives the waveform and the elapsed time while recording; off otherwise.
  private var recordingTimer: Timer?
  private let haptics = UIImpactFeedbackGenerator(style: .light)
  /// The last inserted dictation, removable with Undo for `undoWindow` seconds.
  private var lastInsertion: (text: String, document: UUID?, expires: Date)?
  private var undoTimer: Timer?
  private static let undoWindow: TimeInterval = 5

  // B1 "Quiet" layout: the whole pad is the tap target; the only colour is a small red dot.
  private let pad = UIView()
  private lazy var padTap = UITapGestureRecognizer(target: self, action: #selector(padTapped))
  private let iconView = UIImageView()
  private let waveform = WaveformView()
  private let recordingDot = UIView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let cancelButton = UIButton(type: .system)
  private let endButton = UIButton(type: .system)
  private let undoButton = UIButton(type: .system)
  private let microphoneLabel = UILabel()
  private let resultRow = UIStackView()
  private let globeButton = KeyButton(symbol: "globe", special: true)
  private let spaceButton = KeyButton(title: String(localized: "keyboard.key.space"), special: false)
  private let deleteButton = KeyButton(symbol: "delete.left", special: true)
  private let returnButton = KeyButton(symbol: "return", special: true)
  private var deleteRepeatTimer: Timer?

  override func viewDidLoad() {
    super.viewDidLoad()
    buildLayout()
    keyboard = DictationBridge.read(DictationKeyboardState.self, from: DictationBridge.keyboardFile) ?? DictationKeyboardState()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    isVisible = true
    globeButton.isHidden = !needsInputModeSwitchKey
    interactionID = UUID()
    stopSnapshot = nil
    observer = DarwinObserver(DictationBridge.companionChanged) { [weak self] in self?.refresh() }
    // Fallback while visible in case a hint is missed; no polling while hidden.
    pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    refresh()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    isVisible = false
    clearUndo()
    stopRecordingTimer()
    observer = nil
    pollTimer?.invalidate()
    pollTimer = nil
  }

  override func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
  }

  // MARK: - State

  private func refresh() {
    companion = DictationBridge.read(DictationCompanionState.self, from: DictationBridge.companionFile) ?? DictationCompanionState()
    // End session resets the companion's acknowledgments; nothing is pending without a session.
    if !isSessionArmed {
      awaitingAckFor = nil
    } else if let pending = awaitingAckFor, companion.handledCommandIDs.contains(where: { id in keyboard.commands.contains { $0.id == id && $0.kind == pending } }) {
      awaitingAckFor = nil
    }
    deliverResultIfPossible()
    render()
  }

  private var pendingResult: DictationResult? {
    guard let result = companion.result, !keyboard.consumedResultIDs.contains(result.id) else { return nil }
    return result
  }

  /// Insert automatically only if this same keyboard appearance asked for it and the cursor
  /// has not moved since Stop. Otherwise the user decides with Insert/Discard.
  private func deliverResultIfPossible() {
    guard let result = pendingResult, isVisible, result.interactionID == interactionID,
          let snapshot = stopSnapshot,
          snapshot.document == textDocumentProxy.documentIdentifier,
          snapshot.before == textDocumentProxy.documentContextBeforeInput else { return }
    insert(result)
  }

  private func insert(_ result: DictationResult) {
    // Claim before inserting: a crash after this may lose the text but never duplicates it.
    claim(result)
    let before = textDocumentProxy.documentContextBeforeInput ?? ""
    let needsSpace = !before.isEmpty && !(before.last?.isWhitespace ?? true)
    let inserted = (needsSpace ? " " : "") + result.text
    textDocumentProxy.insertText(inserted)
    rememberInsertion(inserted)
    let latency = Int(Date().timeIntervalSince(result.createdAt) * 1_000)
    print("✅ [Keyboard] Inserted \(result.text.count) chars, \(latency) ms after result")
    stopSnapshot = nil
  }

  private func rememberInsertion(_ text: String) {
    lastInsertion = (text, textDocumentProxy.documentIdentifier, Date().addingTimeInterval(Self.undoWindow))
    undoTimer?.invalidate()
    undoTimer = Timer.scheduledTimer(withTimeInterval: Self.undoWindow, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.lastInsertion = nil
        self?.render()
      }
    }
  }

  private var canUndo: Bool {
    guard let lastInsertion else { return false }
    return Date() < lastInsertion.expires && lastInsertion.document == textDocumentProxy.documentIdentifier
  }

  private func clearUndo() {
    undoTimer?.invalidate()
    undoTimer = nil
    lastInsertion = nil
  }

  /// Typing with the keyboard's own keys ends the chance to undo.
  private func dismissUndo() {
    guard lastInsertion != nil else { return }
    clearUndo()
    render()
  }

  private func claim(_ result: DictationResult) {
    keyboard.consume(result.id)
    saveKeyboard()
  }

  private func send(_ kind: DictationKeyboardState.Command.Kind) {
    guard let sessionID = companion.sessionID else { return }
    if kind == .stop {
      stopSnapshot = (textDocumentProxy.documentIdentifier, textDocumentProxy.documentContextBeforeInput)
    }
    if kind == .start {
      recordingStartedAt = Date()
      clearUndo()
    }
    keyboard.append(.init(id: UUID(), kind: kind, sessionID: sessionID, interactionID: interactionID, issuedAt: Date()))
    awaitingAckFor = kind
    saveKeyboard()
    render()
  }

  private func saveKeyboard() {
    do {
      try DictationBridge.write(keyboard, to: DictationBridge.keyboardFile, notify: DictationBridge.keyboardChanged)
    } catch {
      print("❌ [Keyboard] Could not write: \(error)")
    }
  }

  // MARK: - Actions

  @objc private func padTapped() {
    guard isSessionArmed else {
      openSnipNoteAndStartSession()
      return
    }
    guard awaitingAckFor == nil else { return }
    switch companion.utterance {
    case .recording:
      haptics.impactOccurred()
      send(.stop)
    case .idle, .failed:
      haptics.impactOccurred()
      send(.start)
    case .transcribing:
      break
    }
  }

  /// Keyboards cannot start the microphone, so SnipNote opens, starts the session at once,
  /// and the user returns with iOS's back button. Same responder-chain route as SnipNoteShare.
  private func openSnipNoteAndStartSession() {
    guard let url = URL(string: "snipnote://dictation/start") else { return }
    var responder: UIResponder? = self
    while let next = responder?.next {
      if let application = next as? UIApplication {
        application.open(url, options: [:], completionHandler: nil)
        return
      }
      responder = next
    }
    print("❌ [Keyboard] Could not find UIApplication to open SnipNote")
  }

  @objc private func cancelTapped() { send(.cancel) }

  @objc private func endTapped() {
    haptics.impactOccurred()
    clearUndo()
    send(.endSession)
  }

  /// Removes the last dictation, but only while the cursor is still right after it, so text
  /// typed or moved since is never deleted. The proxy may see only the end of a long text.
  @objc private func undoTapped() {
    defer {
      clearUndo()
      render()
    }
    guard canUndo, let text = lastInsertion?.text,
          (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(String(text.suffix(24))) else { return }
    haptics.impactOccurred()
    for _ in 0..<text.count { textDocumentProxy.deleteBackward() }
  }

  @objc private func insertTapped() {
    guard let result = pendingResult else { return }
    insert(result)
    render()
  }

  @objc private func discardTapped() {
    guard let result = pendingResult else { return }
    claim(result)
    render()
  }

  @objc private func spaceTapped() {
    UIDevice.current.playInputClick()
    dismissUndo()
    textDocumentProxy.insertText(" ")
  }

  @objc private func returnTapped() {
    UIDevice.current.playInputClick()
    dismissUndo()
    textDocumentProxy.insertText("\n")
  }

  @objc private func deleteDown() {
    UIDevice.current.playInputClick()
    dismissUndo()
    textDocumentProxy.deleteBackward()
    deleteRepeatTimer?.invalidate()
    deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
          MainActor.assumeIsolated { self?.textDocumentProxy.deleteBackward() }
        }
      }
    }
  }

  @objc private func deleteUp() {
    deleteRepeatTimer?.invalidate()
    deleteRepeatTimer = nil
  }

  // MARK: - Rendering

  private var isSessionArmed: Bool { companion.isAlive && companion.session == .armed }

  private enum Look {
    case message(icon: String?, title: String?, subtitle: String, tappable: Bool)
    case ready(note: String?)
    case recording
    case transcribing
    case textReady
  }

  private var currentLook: Look {
    if !hasFullAccess {
      return .message(icon: "lock", title: nil, subtitle: String(localized: "keyboard.fullAccessNeeded"), tappable: false)
    }
    if pendingResult != nil { return .textReady }
    if !isSessionArmed {
      if companion.isAlive && companion.session == .preparing {
        return .message(icon: "mic", title: nil, subtitle: String(localized: "keyboard.session.starting"), tappable: false)
      }
      let subtitle = companion.session == .interrupted
        ? String(localized: "keyboard.session.interrupted")
        : String(localized: "keyboard.session.tapToStart")
      return .message(icon: "mic", title: nil, subtitle: subtitle, tappable: true)
    }
    // Show the next state as soon as the tap is sent; the acknowledgment takes a few ms.
    switch awaitingAckFor {
    case .start: return .recording
    case .stop: return .transcribing
    case .cancel: return .ready(note: nil)
    case .endSession: return .message(icon: "mic", title: nil, subtitle: String(localized: "keyboard.session.tapToStart"), tappable: false)
    case nil: break
    }
    switch companion.utterance {
    case .idle: return .ready(note: nil)
    case .recording: return .recording
    case .transcribing: return .transcribing
    case .failed: return .ready(note: String(localized: "keyboard.dictation.failed"))
    }
  }

  private func render() {
    let look = currentLook
    var icon: String?
    var title: String?
    var subtitle: String?
    var showWaveform = false
    var showCancel = false
    var showEnd = false
    var showMicrophone = false
    var tappable = false
    var shimmer = false

    switch look {
    case let .message(messageIcon, messageTitle, messageSubtitle, isTappable):
      icon = messageIcon
      title = messageTitle
      subtitle = messageSubtitle
      tappable = isTappable
    case let .ready(note):
      icon = "mic"
      subtitle = note.map { String(format: String(localized: "keyboard.dictation.noteThenTap"), $0) }
        ?? String(localized: "keyboard.dictation.tap")
      tappable = true
      showEnd = true
      showMicrophone = true
    case .recording:
      showWaveform = true
      showCancel = true
      showMicrophone = true
      tappable = true
      title = elapsedText
    case .transcribing:
      title = String(localized: "keyboard.dictation.transcribing")
      showCancel = true
      shimmer = true
    case .textReady:
      title = String(localized: "keyboard.dictation.textReady")
    }

    if case .recording = look {
      if recordingStartedAt == nil { recordingStartedAt = Date() }
      startRecordingTimer()
    } else {
      recordingStartedAt = nil
      stopRecordingTimer()
      waveform.reset()
    }

    iconView.image = icon.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .light)) }
    iconView.isHidden = icon == nil
    waveform.isHidden = !showWaveform
    recordingDot.isHidden = !showWaveform
    titleLabel.text = title
    titleLabel.isHidden = title == nil
    subtitleLabel.text = subtitle
    subtitleLabel.isHidden = subtitle == nil
    cancelButton.isHidden = !showCancel
    endButton.isHidden = !showEnd
    undoButton.isHidden = !(showEnd && canUndo)
    microphoneLabel.isHidden = !showMicrophone
    if showMicrophone { microphoneLabel.attributedText = microphoneText }
    resultRow.isHidden = { if case .textReady = look { return false }; return true }()
    padTap.isEnabled = tappable
    setShimmer(shimmer)
  }

  /// Which microphone listens: headphones by name, or the device's own.
  private var microphoneText: NSAttributedString {
    let external = companion.microphoneName
    let name = external ?? String(format: String(localized: "keyboard.microphone.device"), UIDevice.current.model)
    let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.tertiaryLabel]
    let text = NSMutableAttributedString()
    let symbol = UIImage(systemName: external == nil ? "iphone" : "headphones",
                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .regular))
    if let symbol = symbol?.withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal) {
      text.append(NSAttributedString(attachment: NSTextAttachment(image: symbol)))
      text.append(NSAttributedString(string: " ", attributes: attributes))
    }
    text.append(NSAttributedString(string: name, attributes: attributes))
    return text
  }

  private var elapsedText: String {
    let seconds = Int(Date().timeIntervalSince(recordingStartedAt ?? Date()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func startRecordingTimer() {
    guard recordingTimer == nil else { return }
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.waveform.push(self.companion.level)
        self.titleLabel.text = self.elapsedText
      }
    }
  }

  private func stopRecordingTimer() {
    recordingTimer?.invalidate()
    recordingTimer = nil
  }

  /// A gentle fade instead of a spinner while transcribing.
  private func setShimmer(_ on: Bool) {
    let key = "shimmer"
    if on, titleLabel.layer.animation(forKey: key) == nil {
      let pulse = CABasicAnimation(keyPath: "opacity")
      pulse.fromValue = 1
      pulse.toValue = 0.35
      pulse.duration = 0.8
      pulse.autoreverses = true
      pulse.repeatCount = .infinity
      titleLabel.layer.add(pulse, forKey: key)
    } else if !on {
      titleLabel.layer.removeAnimation(forKey: key)
    }
  }

  private func buildLayout() {
    view.heightAnchor.constraint(equalToConstant: 236).isActive = true

    // Pad: everything above the bottom row; one tap starts or stops.
    pad.translatesAutoresizingMaskIntoConstraints = false
    // Keyboard extensions ignore touches on fully transparent areas; this stays invisible.
    pad.backgroundColor = UIColor.black.withAlphaComponent(0.001)
    // A gesture (not a control target) so taps on the centred text count too.
    pad.addGestureRecognizer(padTap)
    view.addSubview(pad)

    iconView.tintColor = .label
    iconView.contentMode = .center

    recordingDot.backgroundColor = .systemRed
    recordingDot.layer.cornerRadius = 3.5
    recordingDot.widthAnchor.constraint(equalToConstant: 7).isActive = true
    recordingDot.heightAnchor.constraint(equalToConstant: 7).isActive = true

    titleLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
    titleLabel.textColor = .label
    subtitleLabel.font = .systemFont(ofSize: 13)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.textAlignment = .center
    subtitleLabel.numberOfLines = 2

    let titleRow = UIStackView(arrangedSubviews: [recordingDot, titleLabel])
    titleRow.spacing = 6
    titleRow.alignment = .center

    for (button, title, action) in [(UIButton(type: .system), String(localized: "keyboard.result.discard"), #selector(discardTapped)),
                                    (UIButton(type: .system), String(localized: "keyboard.result.insert"), #selector(insertTapped))] {
      var config = UIButton.Configuration.gray()
      config.title = title
      config.baseForegroundColor = .label
      config.cornerStyle = .medium
      config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 22, bottom: 8, trailing: 22)
      button.configuration = config
      button.addTarget(self, action: action, for: .touchUpInside)
      resultRow.addArrangedSubview(button)
    }
    resultRow.spacing = 10

    microphoneLabel.textAlignment = .center

    let content = UIStackView(arrangedSubviews: [iconView, waveform, titleRow, subtitleLabel, microphoneLabel, resultRow])
    content.axis = .vertical
    content.alignment = .center
    content.spacing = 9
    content.isUserInteractionEnabled = true
    content.translatesAutoresizingMaskIntoConstraints = false
    pad.addSubview(content)
    // Taps on the labels must reach the pad; only the result buttons handle their own.
    for view in [iconView, waveform, titleRow, subtitleLabel, microphoneLabel] { view.isUserInteractionEnabled = false }

    var cancel = UIButton.Configuration.gray()
    cancel.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
    cancel.baseForegroundColor = .label
    cancel.cornerStyle = .capsule
    cancelButton.configuration = cancel
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(cancelButton)

    for (button, title, action) in [(endButton, String(localized: "keyboard.session.end"), #selector(endTapped)),
                                    (undoButton, String(localized: "keyboard.result.undo"), #selector(undoTapped))] {
      var config = UIButton.Configuration.gray()
      config.title = title
      config.baseForegroundColor = .label
      config.cornerStyle = .capsule
      config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = .systemFont(ofSize: 13, weight: .medium)
        return outgoing
      }
      button.configuration = config
      button.addTarget(self, action: action, for: .touchUpInside)
      button.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(button)
    }
    endButton.accessibilityLabel = String(localized: "keyboard.session.end.accessibility")

    globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
    spaceButton.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
    deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
    deleteButton.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
    let bottomRow = UIStackView(arrangedSubviews: [globeButton, spaceButton, deleteButton, returnButton])
    bottomRow.spacing = 6
    bottomRow.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bottomRow)

    NSLayoutConstraint.activate([
      pad.topAnchor.constraint(equalTo: view.topAnchor),
      pad.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      pad.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      pad.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -6),
      content.centerXAnchor.constraint(equalTo: pad.centerXAnchor),
      content.centerYAnchor.constraint(equalTo: pad.centerYAnchor),
      content.leadingAnchor.constraint(greaterThanOrEqualTo: pad.leadingAnchor, constant: 24),
      waveform.widthAnchor.constraint(equalToConstant: 168),
      waveform.heightAnchor.constraint(equalToConstant: 30),
      cancelButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
      cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
      cancelButton.widthAnchor.constraint(equalToConstant: 28),
      cancelButton.heightAnchor.constraint(equalToConstant: 28),
      endButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
      endButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
      endButton.heightAnchor.constraint(equalToConstant: 28),
      undoButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
      undoButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
      undoButton.heightAnchor.constraint(equalToConstant: 28),
      bottomRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
      bottomRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
      bottomRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
      bottomRow.heightAnchor.constraint(equalToConstant: 42),
      globeButton.widthAnchor.constraint(equalToConstant: 46),
      deleteButton.widthAnchor.constraint(equalToConstant: 46),
      returnButton.widthAnchor.constraint(equalToConstant: 88),
    ])
    render()
  }
}
