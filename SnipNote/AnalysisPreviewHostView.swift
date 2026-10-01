#if DEBUG
import SwiftUI
import SwiftData

struct AnalysisPreviewHostView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var meeting: Meeting
  @State private var stage: String
  @State private var away = false
  private let jobID = UUID().uuidString
  @StateObject private var themeManager: ThemeManager
  @StateObject private var localization: LocalizationManager
  private let appearance: ColorScheme
  private let largeText: Bool
  private let reduceMotion: Bool

  init(stage: String = "preparing", language: String = "en", dark: Bool = false,
       largeText: Bool = false, reduceMotion: Bool = false) {
    _meeting = State(initialValue: Meeting(name: "Weekly planning", location: "Design team"))
    _stage = State(initialValue: stage)
    _themeManager = StateObject(wrappedValue: ThemeManager(previewTheme: dark ? DarkTheme() : LightTheme()))
    _localization = StateObject(wrappedValue: LocalizationManager(previewLanguageCode: language))
    appearance = dark ? .dark : .light
    self.largeText = largeText; self.reduceMotion = reduceMotion
  }

  private var input: AnalysisPresentationInput {
    AnalysisPreviewFixtures.input(stage: stage, meetingID: meeting.id, jobID: jobID)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        HStack {
          if away {
            Button("Return") { away = false }.accessibilityIdentifier("fixture.return")
          } else {
            Button("Back") { away = true }.accessibilityIdentifier("fixture.back")
            Spacer()
            Button("Next", action: advance).accessibilityIdentifier("fixture.next")
          }
        }
        .buttonStyle(.bordered).frame(minHeight: 44).padding(.horizontal, 16)
        .background(themeManager.currentTheme.secondaryBackgroundColor)
        if away {
          Text("Analysis preview — return to the same meeting")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          MeetingDetailView(meeting: meeting, analysisPreview: input)
        }
      }
      .navigationTitle("SnipNote")
      .navigationBarTitleDisplayMode(.inline)
      .background(themeManager.currentTheme.backgroundColor)
    }
    .environmentObject(themeManager).environmentObject(localization)
    .environment(\.locale, localization.locale)
    .preferredColorScheme(appearance)
    .modifier(AnalysisPreviewAccessibility(largeText: largeText, reduceMotion: reduceMotion))
    .onAppear {
      if meeting.modelContext == nil { modelContext.insert(meeting) }
      configureMeeting()
    }
  }

  private func advance() {
    let stages = ["preparing", "upload-zero", "upload-half", "confirming", "queued", "processing", "complete"]
    if stage == "retry" { stage = "preparing" }
    else if let index = stages.firstIndex(of: stage), index + 1 < stages.count { stage = stages[index + 1] }
    configureMeeting()
  }

  private func configureMeeting() {
    let fixture = input
    meeting.transcriptionBackend = fixture.backend
    meeting.processingState = fixture.processingState
    meeting.processingPhase = fixture.processingPhase
    meeting.transcriptionJobId = fixture.jobID
    meeting.currentStageDescription = fixture.serverStage ?? localization.localizedString("analysis.title.transcribing")
    meeting.processingError = stage == "failed" ? "Preview: connection interrupted." : nil
    if stage == "complete" {
      meeting.shortSummary = "The team agreed on the next steps."
      meeting.aiSummary = "## Next steps\n- Review the prototype.\n- Share feedback on Friday."
      meeting.audioTranscript = "We will review the prototype and share feedback on Friday."
      meeting.markCompleted()
    }
  }
}

private struct AnalysisPreviewAccessibility: ViewModifier {
  let largeText: Bool
  let reduceMotion: Bool
  @ViewBuilder func body(content: Content) -> some View {
    if largeText && reduceMotion {
      content.environment(\.dynamicTypeSize, .accessibility5).environment(\.analysisPreviewReduceMotion, true)
    } else if largeText {
      content.environment(\.dynamicTypeSize, .accessibility5)
    } else if reduceMotion {
      content.environment(\.analysisPreviewReduceMotion, true)
    } else { content }
  }
}

#Preview("Quiet transitions — English light") {
  AnalysisPreviewHostView().modelContainer(for: Meeting.self, inMemory: true)
}
#Preview("Quiet transitions — Italian dark") {
  AnalysisPreviewHostView(stage: "upload-half", language: "it", dark: true)
    .modelContainer(for: Meeting.self, inMemory: true)
}
#Preview("Largest text — Reduce Motion") {
  AnalysisPreviewHostView(stage: "upload-zero", language: "it", largeText: true, reduceMotion: true)
    .modelContainer(for: Meeting.self, inMemory: true)
}
#endif
