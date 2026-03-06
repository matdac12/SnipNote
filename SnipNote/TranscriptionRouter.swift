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
    private let openAIService = OpenAIService.shared

    private init() {}

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
        let mode = await MainActor.run { LocalTranscriptionManager.shared.transcriptionMode }

        switch mode {
        case .cloud:
            return try await openAIService.transcribeAudioFromURL(
                audioURL: audioURL,
                progressCallback: progressCallback,
                meetingName: meetingName,
                meetingId: meetingId,
                language: language
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
                resumeFromCompletedChunks: localResumeCompletedChunks,
                existingTranscript: localExistingTranscript,
                progressCallback: progressCallback
            )
        }
    }
}
