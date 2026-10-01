import SwiftUI

struct AnalysisStatusView: View {
  let presentation: AnalysisPresentation
  var retryUpload: (() -> Void)? = nil
  @EnvironmentObject private var themeManager: ThemeManager
  @EnvironmentObject private var localization: LocalizationManager
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var percentageSize = 56.0
  @State private var tracker = AnalysisAnnouncementTracker()
  @State private var lastCanLeave = false

#if DEBUG
  @Environment(\.analysisPreviewReduceMotion) private var previewReduceMotion
#endif
  private var reduceMotion: Bool {
#if DEBUG
    return previewReduceMotion ?? systemReduceMotion
#else
    return systemReduceMotion
#endif
  }

  private var theme: AppTheme { themeManager.currentTheme }
  private var transitionAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.25) }
  private var active: Bool { ![.pausedUpload, .failed, .results].contains(presentation.phase) }
  private var titleKey: String {
    switch presentation.phase {
    case .preparing: return "analysis.title.preparing"
    case .uploading: return "analysis.title.uploading"
    case .confirmingUpload: return "analysis.title.confirming"
    case .queued: return "analysis.title.queued"
    case .transcribing, .foreground: return "analysis.title.transcribing"
    case .analyzing: return "analysis.title.analyzing"
    case .processing, .results: return "analysis.title.processing"
    case .pausedUpload: return "analysis.title.paused"
    case .failed: return "analysis.title.failed"
    }
  }
  private var phaseKey: String {
    switch presentation.phase {
    case .preparing: return "analysis.phase.preparing"
    case .uploading, .confirmingUpload, .pausedUpload: return "analysis.phase.uploading"
    default: return "analysis.phase.server"
    }
  }
  private var guidanceTitleKey: String {
    switch presentation.guidance {
    case .safeUpload, .safeServer: return "analysis.guidance.safe.title"
    case .needsAttention: return "analysis.guidance.attention.title"
    default: return "analysis.guidance.keep_open.title"
    }
  }
  private var guidanceDetailKey: String {
    switch presentation.guidance {
    case .keepOpen, .none: return "analysis.guidance.keep_open.detail"
    case .safeUpload: return "analysis.guidance.upload.detail"
    case .safeServer: return presentation.phase == .queued ? "analysis.guidance.queue.detail" : "analysis.guidance.server.detail"
    case .needsAttention: return "analysis.guidance.attention.detail"
    }
  }

  var body: some View {
    VStack(spacing: 24) {
      VStack(spacing: 16) {
        if presentation.phase != .failed {
          Text(localization.localizedString(phaseKey))
            .font(.caption.weight(.medium)).foregroundStyle(theme.secondaryTextColor)
        }
        Text(localization.localizedString(titleKey))
          .font(.title2.weight(.semibold)).foregroundStyle(theme.textColor)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("analysis.stage")
          .id(titleKey).transition(.opacity)
      }
      .animation(transitionAnimation, value: titleKey)

      VStack(spacing: 16) {
        Group {
          if let fraction = presentation.uploadFraction {
            Text(fraction.formatted(.percent.precision(.fractionLength(0)).locale(localization.locale)))
              .font(.system(size: percentageSize, weight: .semibold)).monospacedDigit()
              .foregroundStyle(theme.textColor)
              .accessibilityLabel(localization.localizedString("analysis.phase.uploading"))
              .accessibilityValue(String(format: localization.localizedString("analysis.progress.accessibility"), locale: localization.locale, Int((fraction * 100).rounded())))
              .accessibilityIdentifier("analysis.upload.progress")
          } else {
            Image(systemName: active ? "ellipsis" : "exclamationmark.circle")
              .font(.largeTitle).foregroundStyle(theme.secondaryTextColor)
              .accessibilityHidden(true)
          }
        }
        .frame(minHeight: 80)
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule().fill(theme.secondaryBackgroundColor)
            if let fraction = presentation.uploadFraction {
              Capsule().fill(theme.accentColor).frame(width: geometry.size.width * fraction)
                .animation(transitionAnimation, value: fraction)
            } else if active && !reduceMotion {
              TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                Capsule().fill(theme.accentColor).frame(width: geometry.size.width * 0.28)
                  .offset(x: geometry.size.width * (cycle * 1.28 - 0.28))
              }
            } else {
              Capsule().fill(theme.accentColor).frame(width: geometry.size.width * 0.28)
            }
          }.clipped()
        }
        .frame(height: 4).accessibilityHidden(true)
        if let sent = presentation.sentBytes, let total = presentation.totalBytes {
          HStack(spacing: 8) {
            Text("\(sent.formatted(.byteCount(style: .file).locale(localization.locale))) / \(total.formatted(.byteCount(style: .file).locale(localization.locale)))")
              .monospacedDigit().fixedSize(horizontal: false, vertical: true)
            if presentation.phase == .confirmingUpload {
              Image(systemName: "ellipsis").accessibilityHidden(true)
            }
          }
          .font(.caption).foregroundStyle(theme.secondaryTextColor)
        }
      }

      if presentation.guidance != .none {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            if presentation.canLeave {
              Image(systemName: "checkmark.circle").accessibilityHidden(true)
            }
            Text(localization.localizedString(guidanceTitleKey))
              .font(.subheadline.weight(.semibold))
              .accessibilityIdentifier("analysis.guidance.title")
          }
          Text(localization.localizedString(guidanceDetailKey)).font(.footnote)
            .accessibilityIdentifier("analysis.guidance.detail")
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .foregroundStyle(presentation.canLeave ? theme.successColor : theme.textColor)
        .background(presentation.canLeave ? theme.successBackgroundColor : theme.secondaryBackgroundColor,
                    in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .id(guidanceDetailKey).transition(.opacity)
        .animation(transitionAnimation, value: presentation.guidance)
        .animation(transitionAnimation, value: guidanceDetailKey)
      }
      if presentation.canRetryUpload, let retryUpload {
        Button(action: retryUpload) {
          Text(localization.localizedString("analysis.action.retry"))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
          .buttonStyle(.bordered).tint(theme.accentColor)
          .accessibilityIdentifier("analysis.retry")
      }
    }
    .padding(.horizontal, 24).padding(.vertical, 32)
    .frame(maxWidth: 480).frame(maxWidth: .infinity)
    .onAppear {
      tracker = AnalysisAnnouncementTracker()
      _ = tracker.update(presentation)
      lastCanLeave = presentation.canLeave
    }
    .onChange(of: presentation) { _, current in
      let newlySafe = !lastCanLeave && current.canLeave
      lastCanLeave = current.canLeave
      guard tracker.update(current) != nil else { return }
      var announcement = localization.localizedString(titleKey)
      if newlySafe { announcement += ". " + localization.localizedString("analysis.guidance.safe.title") }
      UIAccessibility.post(notification: .announcement, argument: announcement)
    }
  }
}
