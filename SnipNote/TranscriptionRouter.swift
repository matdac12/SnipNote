//
//  TranscriptionRouter.swift
//  SnipNote
//
//  Created by Codex on 06/03/26.
//

import Foundation

final class TranscriptionRouter {
    static let shared = TranscriptionRouter()

    private let localService = LocalTranscriptionService.shared
    private let openAIService: OpenAIService

    init(openAIService: OpenAIService = .shared) {
        self.openAIService = openAIService
    }

    func transcribeAudioFromURL(
        audioURL: URL,
        progressCallback: @escaping @Sendable (AudioChunkerProgress) -> Void,
        meetingName: String = "",
        meetingId: UUID? = nil,
        language: String? = nil,
        localModel: LocalTranscriptionModel? = nil,
        localResumeCompletedChunks: Int = 0,
        localExistingTranscript: String? = nil
    ) async throws -> String {
        let mode: TranscriptionMode = if localModel != nil {
            .local
        } else {
            await MainActor.run { LocalTranscriptionManager.shared.transcriptionMode }
        }

        switch mode {
        case .cloud:
            let provider = await MainActor.run { CloudTranscriptionSettings.shared.selectedProvider }
            return try await openAIService.transcribeAudioFromURL(
                audioURL: audioURL,
                progressCallback: progressCallback,
                meetingName: meetingName,
                meetingId: meetingId,
                language: language,
                provider: provider
            )
        case .local:
            let model: LocalTranscriptionModel
            if let localModel {
                model = localModel
            } else {
                model = await MainActor.run { LocalTranscriptionManager.shared.selectedModel }
            }
            return try await localService.transcribeAudio(
                from: audioURL,
                model: model,
                language: language,
                meetingId: meetingId,
                resumeFromCompletedChunks: localResumeCompletedChunks,
                existingTranscript: localExistingTranscript,
                progressCallback: progressCallback
            )
        }
    }
}
