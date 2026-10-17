import SwiftUI

/// Settings screen for the SnipNote keyboard: arm the microphone session here, then dictate
/// from the keyboard in any app.
struct DictationSessionView: View {
  @ObservedObject private var controller = DictationSessionController.shared
  @ObservedObject private var localTranscription = LocalTranscriptionManager.shared
  @EnvironmentObject private var localizationManager: LocalizationManager

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
            Text(localized("dictation.session.end"))
          }
        } else {
          Button {
            Task { await controller.startSession() }
          } label: {
            Text(localized("dictation.session.start"))
          }
        }
      } footer: {
        Text(String(format: localized("dictation.session.footer"), localTranscription.selectedModel.displayName, Int(DictationSessionController.idleLimit / 60)))
      }

      if controller.state.result != nil {
        Section {
          Button(role: .destructive) {
            controller.discardPendingResult()
          } label: {
            Text(localized("dictation.pending.discard"))
          }
        } footer: {
          Text(localized("dictation.pending.footer"))
        }
      }

      Section {
        Text(localized("dictation.setup.step1"))
        Text(localized("dictation.setup.step2"))
        Text(localized("dictation.setup.step3"))
      } header: {
        Text(localized("dictation.setup.header"))
      }
    }
    .navigationTitle(localized("settings.dictation.title"))
  }

  private func localized(_ key: String) -> String {
    localizationManager.localizedString(key)
  }

  private var statusText: String {
    switch controller.state.session {
    case .inactive: localized("dictation.status.notRunning")
    case .preparing: localized("dictation.status.preparing")
    case .interrupted: localized("dictation.status.interrupted")
    case .armed:
      switch controller.state.utterance {
      case .idle: localized("dictation.status.ready")
      case .recording: localized("dictation.status.recording")
      case .transcribing: localized("dictation.status.transcribing")
      case .failed: localized("dictation.status.readyAfterFailure")
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
  @EnvironmentObject private var localizationManager: LocalizationManager
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
        Text(localized("account.close"))
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
    case .armed: localized("dictation.launch.ready.title")
    case .interrupted: localized("dictation.launch.failed.title")
    default: localized("dictation.launch.starting.title")
    }
  }

  private var detail: String {
    if controller.state.session == .interrupted {
      return controller.state.message ?? localized("dictation.launch.failed.detail")
    }
    return isReady
      ? localized("dictation.launch.ready.detail")
      : localized("dictation.launch.starting.detail")
  }

  private func localized(_ key: String) -> String {
    localizationManager.localizedString(key)
  }
}
