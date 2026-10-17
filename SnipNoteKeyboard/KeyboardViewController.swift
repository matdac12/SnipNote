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

  private let statusLabel = UILabel()
  private let levelView = UIProgressView(progressViewStyle: .bar)
  private let mainButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)
  private let insertButton = UIButton(type: .system)
  private let discardButton = UIButton(type: .system)
  private let globeButton = UIButton(type: .system)
  private let spaceButton = UIButton(type: .system)
  private let deleteButton = UIButton(type: .system)
  private let returnButton = UIButton(type: .system)
  private let resultRow = UIStackView()
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
    observer = nil
    pollTimer?.invalidate()
    pollTimer = nil
  }

  override func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
    updateKeyColors()
  }

  // MARK: - State

  private func refresh() {
    companion = DictationBridge.read(DictationCompanionState.self, from: DictationBridge.companionFile) ?? DictationCompanionState()
    if let pending = awaitingAckFor, companion.handledCommandIDs.contains(where: { id in keyboard.commands.contains { $0.id == id && $0.kind == pending } }) {
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
    textDocumentProxy.insertText((needsSpace ? " " : "") + result.text)
    let latency = Int(Date().timeIntervalSince(result.createdAt) * 1_000)
    print("✅ [Keyboard] Inserted \(result.text.count) chars, \(latency) ms after result")
    stopSnapshot = nil
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

  @objc private func mainTapped() {
    UIDevice.current.playInputClick()
    switch companion.utterance {
    case .recording: send(.stop)
    default: send(.start)
    }
  }

  @objc private func cancelTapped() { send(.cancel) }

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
    textDocumentProxy.insertText(" ")
  }

  @objc private func returnTapped() {
    UIDevice.current.playInputClick()
    textDocumentProxy.insertText("\n")
  }

  @objc private func deleteDown() {
    UIDevice.current.playInputClick()
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

  private func render() {
    let alive = companion.isAlive && companion.session == .armed
    let pending = pendingResult
    var status: String
    var mainTitle = "Start"
    var mainEnabled = false
    var mainColor = UIColor.systemBlue
    var showCancel = false

    if !hasFullAccess {
      status = "Turn on Allow Full Access for SnipNote in Settings > General > Keyboard."
    } else if pending != nil {
      status = "Text ready"
    } else if !alive {
      switch companion.session {
      case .interrupted: status = "Session interrupted. Open SnipNote > Settings > Dictation keyboard."
      case .preparing: status = "SnipNote is preparing…"
      default: status = "Open SnipNote > Settings > Dictation keyboard > Start session."
      }
    } else if let waiting = awaitingAckFor {
      status = waiting == .start ? "Starting…" : waiting == .stop ? "Stopping…" : "Cancelling…"
      showCancel = waiting != .cancel
    } else {
      switch companion.utterance {
      case .idle:
        status = "Ready"
        mainEnabled = true
      case .recording:
        status = "Recording"
        mainTitle = "Stop"
        mainColor = .systemRed
        mainEnabled = true
        showCancel = true
      case .transcribing:
        status = "Transcribing…"
        showCancel = true
      case .failed:
        status = companion.message ?? "Last dictation failed"
        mainEnabled = true
      }
    }

    statusLabel.text = status
    levelView.isHidden = !(alive && companion.utterance == .recording)
    levelView.setProgress(companion.level, animated: true)
    var config = mainButton.configuration ?? .filled()
    config.title = mainTitle
    config.baseBackgroundColor = mainColor
    mainButton.configuration = config
    mainButton.isEnabled = mainEnabled && hasFullAccess && pending == nil
    cancelButton.isHidden = !showCancel || pending != nil
    resultRow.isHidden = pending == nil
    mainButton.isHidden = pending != nil
  }

  private func updateKeyColors() {
    let dark = textDocumentProxy.keyboardAppearance == .dark
    view.tintColor = dark ? .white : .label
  }

  private func buildLayout() {
    let root = UIStackView()
    root.axis = .vertical
    root.spacing = 10
    root.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      root.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
      root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
      view.heightAnchor.constraint(equalToConstant: 250),
    ])

    statusLabel.font = .preferredFont(forTextStyle: .subheadline)
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 2
    statusLabel.textColor = .secondaryLabel
    levelView.trackTintColor = .tertiarySystemFill
    levelView.progressTintColor = .systemRed

    var main = UIButton.Configuration.filled()
    main.cornerStyle = .capsule
    main.title = "Start"
    main.buttonSize = .large
    mainButton.configuration = main
    mainButton.addTarget(self, action: #selector(mainTapped), for: .touchUpInside)
    mainButton.heightAnchor.constraint(equalToConstant: 72).isActive = true

    configure(cancelButton, title: "Cancel", style: .gray(), action: #selector(cancelTapped))
    configure(insertButton, title: "Insert", style: .filled(), action: #selector(insertTapped))
    configure(discardButton, title: "Discard", style: .gray(), action: #selector(discardTapped))
    insertButton.heightAnchor.constraint(equalToConstant: 72).isActive = true
    discardButton.heightAnchor.constraint(equalToConstant: 72).isActive = true

    resultRow.addArrangedSubview(discardButton)
    resultRow.addArrangedSubview(insertButton)
    resultRow.spacing = 10
    resultRow.distribution = .fillEqually

    var globe = UIButton.Configuration.gray()
    globe.image = UIImage(systemName: "globe")
    globeButton.configuration = globe
    globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

    configure(spaceButton, title: "space", style: .gray(), action: #selector(spaceTapped))
    var delete = UIButton.Configuration.gray()
    delete.image = UIImage(systemName: "delete.left")
    deleteButton.configuration = delete
    deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
    deleteButton.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    var ret = UIButton.Configuration.gray()
    ret.image = UIImage(systemName: "return")
    returnButton.configuration = ret
    returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)

    let bottomRow = UIStackView(arrangedSubviews: [globeButton, spaceButton, deleteButton, returnButton])
    bottomRow.spacing = 8
    for button in [globeButton, deleteButton, returnButton] {
      button.widthAnchor.constraint(equalToConstant: 56).isActive = true
    }
    bottomRow.heightAnchor.constraint(equalToConstant: 44).isActive = true

    let spacer = UIView()
    for subview in [statusLabel, levelView, mainButton, resultRow, cancelButton, spacer, bottomRow] {
      root.addArrangedSubview(subview)
    }
    spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
    updateKeyColors()
    render()
  }

  private func configure(_ button: UIButton, title: String, style: UIButton.Configuration, action: Selector) {
    var config = style
    config.title = title
    config.cornerStyle = .large
    button.configuration = config
    button.addTarget(self, action: action, for: .touchUpInside)
  }
}
