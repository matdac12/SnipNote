import SwiftUI

/// Personal test screen for the SnipNote keyboard: arm the microphone session here, then
/// dictate from the keyboard in any app. Strings are verbatim on purpose (not localized yet).
struct DictationSessionView: View {
  @ObservedObject private var controller = DictationSessionController.shared
  @ObservedObject private var localTranscription = LocalTranscriptionManager.shared

  var body: some View {
    List {
      Section {
        HStack {
          Circle().fill(statusColor).frame(width: 10, height: 10)
          Text(verbatim: statusText).font(.headline)
        }
        if let message = controller.state.message {
          Text(verbatim: message).font(.footnote).foregroundStyle(.secondary)
        }
        if controller.isSessionActive {
          Button(role: .destructive) {
            Task { await controller.endSession() }
          } label: {
            Text(verbatim: "End session")
          }
        } else {
          Button {
            Task { await controller.startSession() }
          } label: {
            Text(verbatim: "Start session")
          }
        }
      } footer: {
        Text(verbatim: "Model: \(localTranscription.selectedModel.displayName). The microphone stays on while the session is armed; audio between dictations is discarded.")
      }

      if controller.state.result != nil {
        Section {
          Button(role: .destructive) {
            controller.discardPendingResult()
          } label: {
            Text(verbatim: "Discard pending text")
          }
        } footer: {
          Text(verbatim: "A transcript is waiting to be inserted from the keyboard.")
        }
      }

      Section {
        LabeledContent { Text(verbatim: "\(controller.utteranceCount)") } label: { Text(verbatim: "Dictations this run") }
        if let info = controller.modelLoadInfo {
          Text(verbatim: info).font(.footnote.monospacedDigit())
        }
        if let timings = controller.lastTimings {
          Text(verbatim: timings).font(.footnote.monospacedDigit())
        }
      } header: {
        Text(verbatim: "Measurements")
      }

      Section {
        Text(verbatim: "1. Settings > General > Keyboard > Keyboards > Add New Keyboard > SnipNote.")
        Text(verbatim: "2. Tap SnipNote in that list and turn on Allow Full Access (needed to talk to this app; the keyboard has no network code).")
        Text(verbatim: "3. Tap Start session here, go to any app, switch to the SnipNote keyboard with the globe key, tap Start and Stop.")
      } header: {
        Text(verbatim: "Setup")
      }
    }
    .navigationTitle(Text(verbatim: "Dictation keyboard"))
  }

  private var statusText: String {
    switch controller.state.session {
    case .inactive: "Not running"
    case .preparing: "Preparing…"
    case .interrupted: "Interrupted"
    case .armed:
      switch controller.state.utterance {
      case .idle: "Ready"
      case .recording: "Recording"
      case .transcribing: "Transcribing"
      case .failed: "Ready (last dictation failed)"
      }
    }
  }

  private var statusColor: Color {
    switch controller.state.session {
    case .armed: controller.state.utterance == .recording ? .red : .green
    case .preparing: .orange
    case .inactive: .gray
    case .interrupted: .red
    }
  }
}

/// Shown when the keyboard opens SnipNote to start a session: the session starts at once and
/// the user goes back with iOS's "◀ App" button. Closes itself when SnipNote leaves the screen.
struct DictationLaunchView: View {
  @ObservedObject private var controller = DictationSessionController.shared
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(spacing: 20) {
      Spacer()
      Image(systemName: icon)
        .font(.system(size: 56, weight: .semibold))
        .foregroundStyle(color)
        .symbolEffect(.pulse, isActive: controller.state.session == .preparing)
      Text(verbatim: title).font(.title2.bold())
      Text(verbatim: detail)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
      Spacer()
      Button {
        dismiss()
      } label: {
        Text(verbatim: "Close")
      }
      .padding(.bottom, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { dismiss() }
    }
  }

  private var isReady: Bool { controller.state.session == .armed }

  private var icon: String {
    switch controller.state.session {
    case .armed: "checkmark.circle.fill"
    case .interrupted: "exclamationmark.triangle.fill"
    default: "mic.circle.fill"
    }
  }

  private var color: Color {
    switch controller.state.session {
    case .armed: .green
    case .interrupted: .red
    default: .orange
    }
  }

  private var title: String {
    switch controller.state.session {
    case .armed: "Dictation ready"
    case .interrupted: "Could not start"
    default: "Starting…"
    }
  }

  private var detail: String {
    if controller.state.session == .interrupted {
      return controller.state.message ?? "Try again from Settings > Dictation keyboard."
    }
    return isReady
      ? "Go back with ◀ at the top left, or swipe right along the bottom edge."
      : "Starting the microphone."
  }
}
