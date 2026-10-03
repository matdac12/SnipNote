//
//  TranscriptionSettingsView.swift
//  SnipNote
//
//  Setup page for transcription: backend, cloud provider and on-device models.
//  Day-to-day switching happens from the Transcription menu in Settings.
//

import SwiftUI

struct TranscriptionSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @ObservedObject private var cloudTranscriptionSettings = CloudTranscriptionSettings.shared
    @ObservedObject private var localTranscriptionManager = LocalTranscriptionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(localized("settings.localTranscription.backendTitle"))
                card {
                    Picker(localized("settings.localTranscription.backendTitle"), selection: Binding(
                        get: { localTranscriptionManager.transcriptionMode },
                        set: { localTranscriptionManager.setTranscriptionMode($0) }
                    )) {
                        ForEach(TranscriptionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.transcription.mode")
                }
                sectionFooter(localTranscriptionManager.isLocalModeEnabled
                              ? localized("settings.localTranscription.backendDescription.local")
                              : localized("settings.localTranscription.backendDescription.cloud"))

                if localTranscriptionManager.isLocalModeEnabled {
                    sectionHeader(localized("settings.localTranscription.availableModels"))
                    VStack(spacing: 10) {
                        ForEach(LocalTranscriptionModel.allCases) { model in
                            LocalModelCard(
                                model: model,
                                isSelected: localTranscriptionManager.selectedModel == model,
                                isBusy: localTranscriptionManager.isBusy(model),
                                status: localTranscriptionManager.modelStatuses[model] ?? .checking,
                                onSelect: {
                                    localTranscriptionManager.setSelectedModel(model)
                                },
                                onDownload: {
                                    Task { await localTranscriptionManager.download(model) }
                                },
                                onDelete: {
                                    Task { await localTranscriptionManager.delete(model) }
                                }
                            )
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius))
                        }
                    }
                    sectionFooter(localized("settings.localTranscription.installHint"))
                } else {
                    sectionHeader(localized("settings.cloudTranscription.provider.title"))
                    CloudTranscriptionProviderPickerView(selectedProvider: $cloudTranscriptionSettings.selectedProvider)
                    sectionFooter(localized("settings.cloudTranscription.provider.description"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(localized("settings.transcription.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await localTranscriptionManager.refreshModelStatuses() }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 16)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func localized(_ key: String) -> String {
        localizationManager.localizedString(key)
    }
}
