import AVFoundation
import Combine
import FluidAudio
import Foundation
import UIKit

/// Companion side of the SnipNote keyboard (personal test feature).
///
/// A session keeps the microphone running so iOS lets SnipNote stay alive in the background;
/// idle audio is discarded. Each Start/Stop from the keyboard captures one utterance, which is
/// transcribed with the installed Parakeet model and handed to the keyboard as one final text.
@MainActor
final class DictationSessionController: ObservableObject {
  static let shared = DictationSessionController()

  @Published private(set) var state = DictationCompanionState()
  @Published private(set) var lastTimings: String?
  @Published private(set) var utteranceCount = 0
  /// Which model is in memory and how long it took to load, for the Dictation screen.
  @Published private(set) var modelLoadInfo: String?

  private static let sampleRate: Double = 16_000
  private static let maxUtteranceSeconds: Double = 120
  private static let handledCommandsLimit = 40

  private let engine = AVAudioEngine()
  private let buffer = UtteranceBuffer()
  private var converter: AVAudioConverter?
  /// Kept after End session so the next session skips the ~10 s Core ML load, as long as
  /// iOS keeps SnipNote in memory. Released on memory warnings or when the model changes.
  private var loaded: LoadedModel?
  private var modelTask: Task<LoadedModel, Error>?
  private var keyboardObserver: DarwinObserver?
  private var heartbeatTimer: Timer?
  private var levelTimer: Timer?
  private var transcriptionTask: Task<Void, Never>?
  private var notificationTokens: [NSObjectProtocol] = []
  private var stopTappedAt: Date?

  private init() {
    // A previous run may have died with a stale "armed" file; the keyboard must not trust it.
    publish()
    NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.releaseModelIfIdle() }
    }
  }

  var isSessionActive: Bool { state.session == .preparing || state.session == .armed }

  // MARK: - Session

  func startSession() async {
    guard !isSessionActive else { return }
    let sessionID = UUID()
    state = DictationCompanionState(sessionID: sessionID, session: .preparing)
    publish()

    do {
      guard await AVAudioApplication.requestRecordPermission() else {
        throw DictationSessionError.microphoneDenied
      }
      let model = LocalTranscriptionManager.shared.selectedModel
      guard await ParakeetTranscriptionService.service(for: model).status() == .installed else {
        throw DictationSessionError.modelMissing
      }
      // The microphone starts first; the model loads meanwhile. Only a Stop that arrives
      // before loading finishes has to wait for it.
      let modelTask = prepareModel(model)
      self.modelTask = modelTask
      Task { [weak self] in
        do {
          _ = try await modelTask.value
        } catch {
          guard let self, self.state.sessionID == sessionID, self.isSessionActive else { return }
          self.interrupt(reason: "Could not load the model: \(error.localizedDescription)")
        }
      }

      let armStart = Date()
      try startCapture()
      observeAudioSession()
      keyboardObserver = DarwinObserver(DictationBridge.keyboardChanged) { [weak self] in
        self?.handleKeyboardCommands()
      }
      startHeartbeat()
      // Ignore commands that were waiting from before this session.
      if let keyboard = DictationBridge.read(DictationKeyboardState.self, from: DictationBridge.keyboardFile) {
        state.handledCommandIDs = Array(keyboard.commands.map(\.id).suffix(Self.handledCommandsLimit))
      }
      state.session = .armed
      state.message = nil
      publish()
      print("✅ [Dictation] Session armed \(sessionID): capture started in \(Self.ms(since: armStart)) ms")
    } catch {
      print("❌ [Dictation] Session failed to start: \(error)")
      await teardown()
      state.session = .interrupted
      state.message = error.localizedDescription
      publish()
    }
  }

  func endSession() async {
    print("🛑 [Dictation] Ending session")
    let pending = state.result
    await teardown()
    // A completed result stays available for explicit Insert; in-flight work is dropped.
    state = DictationCompanionState(result: pending)
    publish()
  }

  private func teardown() async {
    transcriptionTask?.cancel()
    transcriptionTask = nil
    heartbeatTimer?.invalidate()
    heartbeatTimer = nil
    stopLevelTimer()
    keyboardObserver = nil
    notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    notificationTokens.removeAll()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    buffer.stopAndClear()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // MARK: - Model

  private struct LoadedModel {
    let model: LocalTranscriptionModel
    let service: ParakeetTranscriptionService
    let asr: AsrManager
  }

  /// Reuses the model in memory when it is still the selected one; otherwise loads it.
  private func prepareModel(_ model: LocalTranscriptionModel) -> Task<LoadedModel, Error> {
    // Already loaded, or a load of the same model is still running.
    if let modelTask, pendingModel == model {
      print("♻️ [Dictation] Reusing \(model.rawValue) (\(loaded == nil ? "still loading" : "in memory"))")
      return modelTask
    }
    let previous = loaded
    loaded = nil
    pendingModel = model
    modelLoadInfo = "Loading \(model.displayName)…"
    return Task { [weak self] in
      if let previous {
        await previous.service.finishSession(previous.asr)
      }
      let service = ParakeetTranscriptionService.service(for: model)
      let started = Date()
      let asr: AsrManager
      do {
        asr = try await service.makeSession()
      } catch {
        // A failed load must not be reused by the next session.
        self?.modelTask = nil
        self?.pendingModel = nil
        self?.modelLoadInfo = nil
        throw error
      }
      let ms = Self.ms(since: started)
      let result = LoadedModel(model: model, service: service, asr: asr)
      print("🎙️ [Dictation] Parakeet \(model.rawValue) loaded in \(ms) ms")
      self?.loaded = result
      self?.modelLoadInfo = "\(model.displayName) loaded in \(ms) ms"
      return result
    }
  }

  private var pendingModel: LocalTranscriptionModel?

  /// Frees the model's memory when no session needs it.
  private func releaseModelIfIdle() {
    guard !isSessionActive, let loaded else { return }
    print("🧹 [Dictation] Releasing \(loaded.model.rawValue) (memory warning)")
    self.loaded = nil
    modelTask = nil
    pendingModel = nil
    modelLoadInfo = nil
    Task { await loaded.service.finishSession(loaded.asr) }
  }

  // MARK: - Capture

  private func startCapture() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
    try session.setActive(true)
    try installTapAndStart()
  }

  private func installTapAndStart() throws {
    let input = engine.inputNode
    input.removeTap(onBus: 0)
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
          let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
          let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
      throw DictationSessionError.audioUnavailable
    }
    self.converter = converter
    input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat,
                     block: Self.makeTapBlock(buffer: buffer, converter: converter, from: inputFormat, to: targetFormat))
    engine.prepare()
    try engine.start()
  }

  /// Built outside the main actor: the tap runs on the audio thread.
  private nonisolated static func makeTapBlock(
    buffer: UtteranceBuffer, converter: AVAudioConverter, from inputFormat: AVAudioFormat, to targetFormat: AVAudioFormat
  ) -> AVAudioNodeTapBlock {
    { pcm, _ in
      // Idle audio is converted nowhere and kept nowhere.
      guard buffer.isRecording else { return }
      let ratio = targetFormat.sampleRate / inputFormat.sampleRate
      let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 32
      guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
      var consumed = false
      var error: NSError?
      converter.convert(to: output, error: &error) { _, status in
        if consumed {
          status.pointee = .noDataNow
          return nil
        }
        consumed = true
        status.pointee = .haveData
        return pcm
      }
      guard error == nil, let channel = output.floatChannelData?[0] else { return }
      buffer.append(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
  }

  private func observeAudioSession() {
    let center = NotificationCenter.default
    notificationTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
      let info = note.userInfo
      MainActor.assumeIsolated { self?.handleInterruption(info) }
    })
    notificationTokens.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleConfigurationChange() }
    })
    notificationTokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.interrupt(reason: "Audio services were reset") }
    })
  }

  private func handleInterruption(_ info: [AnyHashable: Any]?) {
    guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    switch type {
    case .began:
      print("⚠️ [Dictation] Audio interruption began")
      if state.utterance == .recording { failUtterance("Interrupted while recording") }
    case .ended:
      print("🔄 [Dictation] Audio interruption ended, trying to resume capture")
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        try installTapAndStart()
        print("✅ [Dictation] Capture resumed after interruption")
      } catch {
        interrupt(reason: "Could not resume after interruption: \(error.localizedDescription)")
      }
    @unknown default:
      break
    }
  }

  /// Route changes (AirPods in/out) stop the engine; restart it with the new input format.
  private func handleConfigurationChange() {
    guard state.session == .armed else { return }
    print("🔄 [Dictation] Audio route changed, restarting capture")
    if state.utterance == .recording { failUtterance("Audio route changed while recording") }
    do {
      try installTapAndStart()
    } catch {
      interrupt(reason: "Could not restart capture: \(error.localizedDescription)")
    }
  }

  private func interrupt(reason: String) {
    print("❌ [Dictation] \(reason)")
    Task {
      await teardown()
      state.session = .interrupted
      state.utterance = .idle
      state.message = reason
      publish()
    }
  }

  // MARK: - Commands

  private func handleKeyboardCommands() {
    guard let keyboard = DictationBridge.read(DictationKeyboardState.self, from: DictationBridge.keyboardFile) else { return }

    if let result = state.result, keyboard.consumedResultIDs.contains(result.id) {
      state.result = nil
      publish()
    }
    guard state.session == .armed else { return }

    for command in keyboard.commands where !state.handledCommandIDs.contains(command.id) {
      markHandled(command.id)
      guard command.sessionID == state.sessionID else {
        print("⏭️ [Dictation] Ignoring \(command.kind.rawValue) for a stale session")
        continue
      }
      print("📥 [Dictation] \(command.kind.rawValue) (\(Self.ms(since: command.issuedAt)) ms after tap)")
      switch command.kind {
      case .start: startUtterance(interactionID: command.interactionID)
      case .stop: stopUtterance()
      case .cancel: cancelUtterance()
      case .endSession: Task { await endSession() }
      }
    }
    publish()
  }

  private func markHandled(_ id: UUID) {
    state.handledCommandIDs.append(id)
    if state.handledCommandIDs.count > Self.handledCommandsLimit {
      state.handledCommandIDs.removeFirst(state.handledCommandIDs.count - Self.handledCommandsLimit)
    }
  }

  private func startUtterance(interactionID: UUID) {
    // One utterance at a time; an unclaimed result must be inserted or discarded first.
    guard state.utterance == .idle || state.utterance == .failed, state.result == nil else {
      print("⏭️ [Dictation] Start ignored: utterance \(state.utterance.rawValue), pending result \(state.result != nil)")
      return
    }
    state.utteranceID = UUID()
    state.interactionID = interactionID
    state.utterance = .recording
    state.message = nil
    buffer.start()
    startLevelTimer()
  }

  private func stopUtterance() {
    guard state.utterance == .recording, let utteranceID = state.utteranceID,
          let interactionID = state.interactionID, let modelTask else { return }
    stopTappedAt = Date()
    let samples = buffer.stop()
    stopLevelTimer()
    state.utterance = .transcribing
    state.level = 0
    publish()

    let seconds = Double(samples.count) / Self.sampleRate
    transcriptionTask = Task { [weak self] in
      var started = Date()
      do {
        let waitStart = Date()
        let asr = try await modelTask.value.asr
        let waitedMs = Self.ms(since: waitStart)
        if waitedMs > 50 { print("⏳ [Dictation] Waited \(waitedMs) ms for the model to finish loading") }
        started = Date()
        var decoderState = try TdtDecoderState()
        let result = try await asr.transcribe(
          ParakeetTranscriptionService.prepareChunkSamples(samples), decoderState: &decoderState, language: nil)
        guard let self, !Task.isCancelled, self.state.utteranceID == utteranceID else { return }
        self.finishUtterance(text: result.text, utteranceID: utteranceID, interactionID: interactionID,
                             audioSeconds: seconds, transcribeMs: Self.ms(since: started))
      } catch {
        guard let self, !Task.isCancelled, self.state.utteranceID == utteranceID else { return }
        if case LocalTranscriptionError.emptyTranscript = error {
          self.finishUtterance(text: "", utteranceID: utteranceID, interactionID: interactionID,
                               audioSeconds: seconds, transcribeMs: Self.ms(since: started))
        } else {
          self.failUtterance("Transcription failed: \(error.localizedDescription)")
        }
      }
    }
  }

  private func finishUtterance(text: String, utteranceID: UUID, interactionID: UUID, audioSeconds: Double, transcribeMs: Int) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let stopToResult = stopTappedAt.map { Self.ms(since: $0) } ?? 0
    lastTimings = String(format: "%.1f s audio · transcribe %d ms · Stop→result %d ms", audioSeconds, transcribeMs, stopToResult)
    print("✅ [Dictation] \(lastTimings ?? "") · \(trimmed.count) chars")
    utteranceCount += 1
    state.utterance = .idle
    state.utteranceID = nil
    if !trimmed.isEmpty {
      state.result = DictationResult(id: UUID(), utteranceID: utteranceID, interactionID: interactionID, text: trimmed, createdAt: Date())
    }
    publish()
  }

  private func cancelUtterance() {
    transcriptionTask?.cancel()
    transcriptionTask = nil
    buffer.stopAndClear()
    stopLevelTimer()
    state.utterance = .idle
    state.utteranceID = nil
    state.level = 0
    state.message = nil
  }

  private func failUtterance(_ message: String) {
    print("❌ [Dictation] \(message)")
    buffer.stopAndClear()
    stopLevelTimer()
    state.utterance = .failed
    state.utteranceID = nil
    state.level = 0
    state.message = message
    publish()
  }

  /// Lets the user discard a result from SnipNote when no keyboard is around.
  func discardPendingResult() {
    state.result = nil
    publish()
  }

  // MARK: - Publishing

  private func startHeartbeat() {
    heartbeatTimer?.invalidate()
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        // Also a fallback in case a Darwin hint was missed.
        self.handleKeyboardCommands()
        self.publish()
      }
    }
  }

  private func startLevelTimer() {
    stopLevelTimer()
    levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.state.utterance == .recording else { return }
        if self.buffer.seconds(sampleRate: Self.sampleRate) >= Self.maxUtteranceSeconds {
          print("⏱️ [Dictation] Utterance limit reached, stopping")
          self.stopUtterance()
          return
        }
        self.state.level = self.buffer.takeLevel()
        self.publish()
      }
    }
  }

  private func stopLevelTimer() {
    levelTimer?.invalidate()
    levelTimer = nil
  }

  private func publish() {
    state.heartbeat = Date()
    do {
      try DictationBridge.write(state, to: DictationBridge.companionFile, notify: DictationBridge.companionChanged)
    } catch {
      print("❌ [Dictation] Could not write companion state: \(error)")
    }
  }

  private nonisolated static func ms(since date: Date) -> Int {
    Int(Date().timeIntervalSince(date) * 1_000)
  }
}

enum DictationSessionError: LocalizedError {
  case microphoneDenied
  case modelMissing
  case audioUnavailable

  var errorDescription: String? {
    switch self {
    case .microphoneDenied: "Microphone access is off. Turn it on in Settings > SnipNote."
    case .modelMissing: "Download a Parakeet model in Settings > Transcription first."
    case .audioUnavailable: "No microphone input is available."
    }
  }
}

/// Utterance samples (16 kHz mono), filled on the audio thread.
private final class UtteranceBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var samples: [Float] = []
  private var recording = false
  private var peak: Float = 0

  var isRecording: Bool { lock.withLock { recording } }

  func start() {
    lock.withLock {
      samples.removeAll(keepingCapacity: true)
      peak = 0
      recording = true
    }
  }

  func append(_ chunk: UnsafeBufferPointer<Float>) {
    lock.withLock {
      guard recording else { return }
      samples.append(contentsOf: chunk)
      for sample in chunk { peak = max(peak, abs(sample)) }
    }
  }

  func stop() -> [Float] {
    lock.withLock {
      recording = false
      defer { samples = [] }
      return samples
    }
  }

  func stopAndClear() {
    lock.withLock {
      recording = false
      samples = []
      peak = 0
    }
  }

  func seconds(sampleRate: Double) -> Double {
    lock.withLock { Double(samples.count) / sampleRate }
  }

  /// Peak since the last call, mapped to 0...1 on a rough dB scale.
  func takeLevel() -> Float {
    lock.withLock {
      defer { peak = 0 }
      guard peak > 0 else { return 0 }
      let db = 20 * log10(peak)
      return max(0, min(1, (db + 50) / 50))
    }
  }
}
