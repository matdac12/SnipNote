//
//  LocalModelDownloadBanner.swift
//  SnipNote
//
//  Shows the Local mode model download state with a Download / Retry action.
//  Visible only while Local mode is on and the selected model is not installed.
//

import SwiftUI

struct LocalModelDownloadBanner: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var manager = LocalTranscriptionManager.shared
    @State private var showingCellularConfirmation = false

    private var theme: AppTheme { themeManager.currentTheme }
    private var model: LocalTranscriptionModel { manager.selectedModel }

    var body: some View {
        if manager.isLocalModeEnabled, !manager.selectedModelStatus.isInstalled, manager.selectedModelStatus != .checking {
            content
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.secondaryBackgroundColor.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .stroke(theme.accentColor.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(theme.cornerRadius)
                .confirmationDialog(
                    LocalizationManager.localizedAppString("transcription.local.banner.cellular.title"),
                    isPresented: $showingCellularConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(LocalizationManager.localizedAppString("transcription.local.banner.download")) {
                        start(allowCellular: true)
                    }
                    Button(LocalizationManager.localizedAppString("transcription.local.banner.cellular.cancel"), role: .cancel) {}
                } message: {
                    Text(LocalizationManager.localizedAppString(
                        "transcription.local.banner.cellular.message",
                        model.approximateSizeDescription
                    ))
                }
                .accessibilityIdentifier("localModel.downloadBanner")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.selectedModelStatus {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizationManager.localizedAppString("transcription.local.banner.downloading", Int64(progress * 100)))
                    .themedBody()
                    .fontWeight(.semibold)
                ProgressView(value: progress)
                    .tint(theme.accentColor)
                Text(LocalizationManager.localizedAppString("transcription.local.banner.recordingLocked"))
                    .themedCaption()
            }
        case .verifying:
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizationManager.localizedAppString("transcription.local.banner.verifying"))
                    .themedBody()
                    .fontWeight(.semibold)
                ProgressView()
                    .tint(theme.accentColor)
                Text(LocalizationManager.localizedAppString("transcription.local.banner.recordingLocked"))
                    .themedCaption()
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .themedBody()
                    .fixedSize(horizontal: false, vertical: true)
                actionButton(titleKey: "transcription.local.banner.retry")
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizationManager.localizedAppString("transcription.local.banner.title"))
                    .themedBody()
                    .fontWeight(.semibold)
                Text(LocalizationManager.localizedAppString(
                    "transcription.local.banner.detail",
                    model.approximateSizeDescription
                ))
                .themedCaption()
                .fixedSize(horizontal: false, vertical: true)
                actionButton(titleKey: "transcription.local.banner.download")
            }
        }
    }

    private func actionButton(titleKey: String) -> some View {
        Button(LocalizationManager.localizedAppString(titleKey)) {
            start(allowCellular: false)
        }
        .font(.system(.callout, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(theme.accentColor)
        .cornerRadius(theme.cornerRadius)
    }

    private func start(allowCellular: Bool) {
        let model = model
        Task {
            if await manager.startDownload(model, allowCellular: allowCellular) {
                showingCellularConfirmation = true
            }
        }
    }
}
