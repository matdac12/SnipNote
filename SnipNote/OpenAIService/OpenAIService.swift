//
//  OpenAIService.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import Security
import AVFoundation

class OpenAIService: ObservableObject {
    static let shared = OpenAIService()
    
    private let baseURL = "https://api.openai.com/v1"
    private let keychainService = "com.mattia.snipnote.apikey"
    private let keychainAccount = "openai_api_key"
    
    private init() {}
    
    var apiKey: String? {
        get {
            // First check if API key is set in Config
            if Config.openAIAPIKey != "YOUR_OPENAI_API_KEY_HERE" && !Config.openAIAPIKey.isEmpty {
                return Config.openAIAPIKey
                
            }
            // Fallback to keychain
            if let key = getAPIKeyFromKeychain(), !key.isEmpty {
                return key
            }
            return nil
        }
        set {
            if let key = newValue {
                saveAPIKeyToKeychain(key)
            } else {
                deleteAPIKeyFromKeychain()
            }
        }
    }
    
    private func saveAPIKeyToKeychain(_ key: String) {
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func getAPIKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    private func deleteAPIKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Audio Processing

    /// Speed up audio to 1.5x to reduce transcription costs by 33%
    private func speedUpAudio(audioData: Data) async throws -> Data {
        // Create temporary input file
        let tempInputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("input_\(UUID().uuidString).m4a")
        let tempOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("output_\(UUID().uuidString).m4a")

        defer {
            // Clean up temp files
            try? FileManager.default.removeItem(at: tempInputURL)
            try? FileManager.default.removeItem(at: tempOutputURL)
        }

        // Write audio data to temp file
        try audioData.write(to: tempInputURL)

        // Create asset and export session
        let asset = AVURLAsset(url: tempInputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw OpenAIError.apiError("Failed to create export session")
        }

        exportSession.outputURL = tempOutputURL
        exportSession.outputFileType = .m4a
        exportSession.audioTimePitchAlgorithm = .spectral // Maintains pitch quality

        // Speed up by 1.5x (reduce duration by 1/1.5 = 0.667)
        let originalDuration = try await asset.load(.duration)
        let newDuration = CMTimeMultiplyByFloat64(originalDuration, multiplier: 1.0 / 1.5)
        exportSession.timeRange = CMTimeRange(start: .zero, duration: originalDuration)

        // Use a custom audio mix to change playback rate
        _ = AVMutableAudioMix()
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        if let track = audioTrack {
            let audioMixParams = AVMutableAudioMixInputParameters(track: track)
            audioMixParams.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 1.0, timeRange: CMTimeRange(start: .zero, duration: originalDuration))

            // Create time mapping for 1.5x speed
            let timeMapping = AVMutableComposition()
            let audioCompositionTrack = timeMapping.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

            try audioCompositionTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: originalDuration),
                of: track,
                at: .zero
            )

            // Scale time to 1.5x speed
            audioCompositionTrack?.scaleTimeRange(
                CMTimeRange(start: .zero, duration: originalDuration),
                toDuration: newDuration
            )

            // Create new export session with composition
            guard let compositionExportSession = AVAssetExportSession(asset: timeMapping, presetName: AVAssetExportPresetAppleM4A) else {
                throw OpenAIError.apiError("Failed to create composition export session")
            }

            compositionExportSession.outputURL = tempOutputURL
            compositionExportSession.outputFileType = .m4a
            compositionExportSession.audioTimePitchAlgorithm = .spectral

            do {
                try await compositionExportSession.export(to: tempOutputURL, as: .m4a)
                print("🚀 [OpenAI] Audio sped up 1.5x - cost savings: 33%")
                return try Data(contentsOf: tempOutputURL)
            } catch {
                print("⚠️ [OpenAI] Audio speed-up failed, using original: \(error.localizedDescription)")
                return audioData // Fallback to original
            }
        } else {
            print("⚠️ [OpenAI] No audio track found, using original")
            return audioData // Fallback to original
        }
    }

    func transcribeAudio(audioData: Data) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }

        // Speed up audio by 1.5x to reduce costs by 33%
        let processedAudioData = try await speedUpAudio(audioData: audioData)

        let url = URL(string: "\(baseURL)/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(processedAudioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, urlResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            if let apiError = try? JSONDecoder().decode(OpenAIAPIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(apiError.error.message)
            }
            let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(rawBody)")
        }

        do {
            let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return response.text
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("Unexpected transcription response: \(rawBody)")
        }
    }

    func transcribeAudioFromURL(
        audioURL: URL,
        progressCallback: @escaping (AudioChunkerProgress) -> Void,
        meetingName: String = "",
        meetingId: UUID? = nil
    ) async throws -> String {
        // Validate audio file first
        try AudioChunker.validateAudioFile(url: audioURL)

        // Check if file needs chunking
        let needsChunking = try AudioChunker.needsChunking(url: audioURL)

        if !needsChunking {
            // For small files, use direct processing
            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: "Processing audio file",
                percentComplete: 50.0,
                partialTranscript: nil
            ))

            let audioFile = try AVAudioFile(forReading: audioURL)
            let durationSeconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            let audioData = try Data(contentsOf: audioURL)
            let transcript = try await transcribeAudioWithRetry(audioData: audioData, duration: durationSeconds)

            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: "Transcription complete",
                percentComplete: 100.0,
                partialTranscript: transcript
            ))

            return transcript
        } else {
            // For large files, use chunked processing
            return try await transcribeAudioInChunks(
                audioURL: audioURL,
                progressCallback: progressCallback,
                meetingName: meetingName,
                meetingId: meetingId
            )
        }
    }

    private func transcribeAudioInChunks(
        audioURL: URL,
        progressCallback: @escaping (AudioChunkerProgress) -> Void,
        meetingName: String = "",
        meetingId: UUID? = nil
    ) async throws -> String {

        // Create chunks
        let chunks = try await AudioChunker.createChunks(
            from: audioURL,
            progressCallback: { chunkProgress in
                // Update progress for chunking phase (0-30%)
                let adjustedProgress = AudioChunkerProgress(
                    currentChunk: chunkProgress.currentChunk,
                    totalChunks: chunkProgress.totalChunks,
                    currentStage: chunkProgress.currentStage,
                    percentComplete: chunkProgress.percentComplete * 0.3,
                    partialTranscript: chunkProgress.partialTranscript
                )
                progressCallback(adjustedProgress)
            }
        )

        var transcripts: [String] = []
        let totalChunks = chunks.count

        // Progress notification tracking
        var halfwayNotificationSent = false

        // Process each chunk
        for (index, chunk) in chunks.enumerated() {
            let chunkNumber = index + 1

            progressCallback(AudioChunkerProgress(
                currentChunk: chunkNumber,
                totalChunks: totalChunks,
                currentStage: "Transcribing chunk \(chunkNumber) of \(totalChunks)",
                percentComplete: 30.0 + (Double(index) / Double(totalChunks)) * 70.0,
                partialTranscript: nil
            ))

            print("🎵 Transcribing chunk \(chunkNumber)/\(totalChunks)")

            do {
                // Use new retry logic with exponential backoff
                let chunkTranscript = try await transcribeChunkWithRetry(chunk: chunk)
                transcripts.append(chunkTranscript)

                // Calculate progress percentage
                let progressPercent = 30.0 + (Double(chunkNumber) / Double(totalChunks)) * 70.0

                // Send 50% progress notification
                if progressPercent >= 50.0 && !halfwayNotificationSent && !meetingName.isEmpty, let meetingId = meetingId {
                    halfwayNotificationSent = true
                    await NotificationService.shared.sendProgressNotification(
                        meetingId: meetingId,
                        meetingName: meetingName,
                        progress: 50
                    )
                }

                // Report progress with the completed chunk transcript
                progressCallback(AudioChunkerProgress(
                    currentChunk: chunkNumber,
                    totalChunks: totalChunks,
                    currentStage: "Chunk \(chunkNumber) completed",
                    percentComplete: progressPercent,
                    partialTranscript: chunkTranscript
                ))

            } catch {
                // FIXED: Don't continue with partial transcripts - fail completely if any chunk fails
                print("🎵 Chunk \(chunkNumber) failed after all retries: \(error)")
                throw OpenAIError.transcriptionFailed
            }
        }

        progressCallback(AudioChunkerProgress(
            currentChunk: totalChunks,
            totalChunks: totalChunks,
            currentStage: "Combining transcripts",
            percentComplete: 100.0,
            partialTranscript: nil
        ))

        // Send 100% completion notification for transcription phase
        if !meetingName.isEmpty, let meetingId = meetingId {
            await NotificationService.shared.sendProgressNotification(
                meetingId: meetingId,
                meetingName: meetingName,
                progress: 100
            )
        }

        // Combine all transcripts (all chunks succeeded if we reach here)
        let fullTranscript = transcripts.joined(separator: " ")

        // Validate that we got a meaningful transcript
        let trimmedTranscript = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTranscript.isEmpty {
            throw OpenAIError.transcriptionFailed
        }

        return fullTranscript
    }

    func summarizeText(_ text: String) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Please analyze the following transcript and provide:
        1. Key points and insights
        2. Actionable items or tasks mentioned
        3. Important decisions or conclusions
        
        Keep the summary concise but comprehensive. Format as bullet points.
        
        Transcript: \(text)
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4o",
            messages: [
                ChatMessage(role: "system", content: "You are a helpful assistant that summarizes spoken notes into actionable insights."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 500
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        
        return response.choices.first?.message.content ?? "No summary generated"
    }
    
    func generateTitle(_ text: String) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Identify the language spoken and always respond in the same language as the input transcript.
        Generate an appropriate title for this note transcript in exactly 3-4 words. The title should be concise, descriptive, and capture the main topic or purpose.

        Examples:
        - "Meeting Notes Summary"
        - "Weekly Project Update"
        - "Shopping List Items"
        - "Travel Planning Ideas"

        Transcript: \(text)
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4o",
            messages: [
                ChatMessage(role: "system", content: "You generate concise, descriptive titles for notes. Always respond with exactly 2-3 words, properly capitalized, in the same language as the input transcript."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 20
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Note"
    }
    
    func generateMeetingOverview(_ text: String) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Identify the language spoken and always respond in the same language as the input transcript.
        Summarize this meeting transcript in exactly one short, clear sentence. Capture the main topic and key outcome or focus of the meeting.

        Examples:
        - "Team discussed Q4 goals and assigned project leads for upcoming initiatives."
        - "Budget review meeting where department heads presented spending proposals."
        - "Weekly standup covering project progress and addressing technical blockers."
        - "Client presentation meeting to review design mockups and gather feedback."

        Meeting Transcript: \(text)
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4o",
            messages: [
                ChatMessage(role: "system", content: "You create concise one-sentence meeting overviews. Always respond with exactly one clear, informative sentence in the same language as the input transcript."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 50
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Meeting discussion on various topics."
    }
    
    func summarizeMeeting(_ text: String) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Identify the language spoken and always respond in the same language as the input transcript.
        Please create a comprehensive meeting summary from this transcript. Structure your response with the following sections:

        ## Key Discussion Points
        - Main topics discussed
        - Important insights shared

        ## Decisions Made
        - Key decisions reached during the meeting
        - Who is responsible for what

        ## Action Items
        - Tasks assigned with responsible parties
        - Deadlines mentioned

        ## Next Steps
        - Follow-up actions
        - Future meetings or milestones

        Meeting Transcript: \(text)
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4o",
            messages: [
                ChatMessage(role: "system", content: "You are a professional meeting summarizer. Create structured, comprehensive summaries that capture key decisions, action items, and next steps. Always respond in the same language as the input transcript."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 800
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        
        return response.choices.first?.message.content ?? "No meeting summary generated"
    }
    
    func extractActions(_ text: String) async throws -> [ActionItem] {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Identify the language spoken and always respond in the same language as the input transcript.
        Extract actionable items from this transcript. For each action item, provide:
        1. A clear, concise action description
        2. Priority level (HIGH, MED, LOW)

        Return ONLY a JSON array with this exact format:
        [{"action": "action description", "priority": "HIGH|MED|LOW"}]

        If no actionable items exist, return an empty array: []

        Transcript: \(text)
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4o",
            messages: [
                ChatMessage(role: "system", content: "You extract actionable items from text and return them as JSON. Be precise and only return valid JSON. Always use the same language as the input transcript for action descriptions."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 300
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        
        guard let content = response.choices.first?.message.content else {
            return []
        }
        
        // Parse the JSON response
        do {
            let actionData = content.data(using: .utf8) ?? Data()
            let actions = try JSONDecoder().decode([ActionItem].self, from: actionData)
            return actions
        } catch {
            print("Failed to parse actions JSON: \(error)")
            return []
        }
    }

    func chatWithEve(
        message: String,
        promptVariables: EvePromptVariables,
        conversationId: String?,
        vectorStoreId: String?
    ) async throws -> ChatWithEveResult {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }

        let activeConversationId = try await ensureConversationId(apiKey: apiKey, currentConversationId: conversationId)
        let sanitizedVariables = promptVariables.sanitized()

        let url = URL(string: "\(baseURL)/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var requestBody = ResponsesRequest(
            model: Config.openAIResponsesModel,
            prompt: ResponsesPrompt(
                id: Config.openAIPromptID,
                variables: ResponsesPromptVariables(
                    meetingOverview: sanitizedVariables.meetingOverview,
                    meetingSummary: sanitizedVariables.meetingSummary
                )
            ),
            input: [],
            conversation: activeConversationId,
            text: ResponseTextConfig(
                format: ResponseTextFormat(type: "text"),
                verbosity: "medium"
            ),
            reasoning: ResponseReasoningConfig(effort: "medium"),
            tools: nil
        )

        var contents: [ResponseInputContent] = []
        contents.append(ResponseInputContent(type: "input_text", text: message))

        let inputItem = ResponseInputItem(role: "user", content: contents)
        requestBody.input = [inputItem]

        if let vectorStoreId {
            let tool = ResponseTool(
                type: "file_search",
                vectorStoreIds: [vectorStoreId],
                maxNumResults: 20
            )
            requestBody.tools = [tool]
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenAIResponsesResponse.self, from: data)

        guard let text = response.combinedOutputText else {
            throw OpenAIError.apiError("No response content returned")
        }

        return ChatWithEveResult(responseText: text, conversationId: activeConversationId)
    }

    func createConversation() async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }

        return try await createConversation(apiKey: apiKey)
    }

    private func ensureConversationId(apiKey: String, currentConversationId: String?) async throws -> String {
        if let existingId = currentConversationId {
            return existingId
        }

        return try await createConversation(apiKey: apiKey)
    }

    private func createConversation(apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/conversations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ConversationCreateRequest(metadata: ["source": "SnipNote"])
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("Failed to create conversation. HTTP \(httpResponse.statusCode): \(body)")
        }

        let conversation = try JSONDecoder().decode(OpenAIConversation.self, from: data)
        return conversation.id
    }

    func uploadTranscriptFile(transcript: String, fileName: String) async throws -> UploadedFileInfo {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }

        guard let data = transcript.data(using: .utf8) else {
            throw OpenAIError.apiError("Unable to encode transcript")
        }

        let url = URL(string: "\(baseURL)/files")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let expiresSeconds = 7 * 24 * 60 * 60 // 7 days

        var body = Data()

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "purpose", value: "user_data")
        appendField(name: "expires_after[anchor]", value: "created_at")
        appendField(name: "expires_after[seconds]", value: "\(expiresSeconds)")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, urlResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let bodyString = String(data: responseData, encoding: .utf8) ?? "<binary>"
            throw OpenAIError.apiError("File upload failed: HTTP \(httpResponse.statusCode) - \(bodyString)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let fileResponse = try decoder.decode(OpenAIFileUploadResponse.self, from: responseData)

        let expiresDate: Date?
        if let timestamp = fileResponse.expiresAt {
            expiresDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
        } else {
            expiresDate = Date().addingTimeInterval(TimeInterval(expiresSeconds))
        }

        return UploadedFileInfo(id: fileResponse.id, expiresAt: expiresDate)
    }

    func ensureVectorStore(userId: UUID, existingVectorStoreId: String?) async throws -> String {
        if let existingVectorStoreId {
            return existingVectorStoreId
        }

        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }

        do {
            return try await executeWithRetry(operationDescription: "Create vector store") {
                let url = URL(string: "\(self.baseURL)/vector_stores")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let createRequest = CreateVectorStoreRequest(
                    name: "vector_store_\(userId.uuidString.lowercased())",
                    expiresAfter: VectorStoreExpiresAfter(anchor: "last_active_at", days: 14)
                )

                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                request.httpBody = try encoder.encode(createRequest)

                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? "<binary>"
                    throw OpenAIError.apiError("Failed to create vector store. HTTP \(httpResponse.statusCode): \(body)")
                }

                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let vectorStore = try decoder.decode(VectorStoreResponse.self, from: data)
                return vectorStore.id
            }
        } catch let error as OpenAIError {
            throw error
        } catch {
            throw OpenAIError.vectorStoreUnavailable("Create vector store failed: \(error.localizedDescription)")
        }
    }

    func attachFileToVectorStore(fileId: String, vectorStoreId: String) async throws {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }

        do {
            try await executeWithRetry(operationDescription: "Attach file to vector store") {
                let url = URL(string: "\(self.baseURL)/vector_stores/\(vectorStoreId)/files")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body = VectorStoreFileRequest(fileId: fileId)
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                request.httpBody = try encoder.encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
                    throw OpenAIError.apiError("Failed to attach file to vector store. HTTP \(httpResponse.statusCode): \(bodyString)")
                }
                return ()
            }
        } catch let error as OpenAIError {
            throw error
        } catch {
            throw OpenAIError.vectorStoreUnavailable("Attach file failed: \(error.localizedDescription)")
        }
    }

    func detachFileFromVectorStore(fileId: String, vectorStoreId: String) async throws {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }

        do {
            try await executeWithRetry(operationDescription: "Detach file from vector store") {
                let url = URL(string: "\(self.baseURL)/vector_stores/\(vectorStoreId)/files/\(fileId)")!
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    throw OpenAIError.apiError("Failed to detach file from vector store. HTTP \(httpResponse.statusCode)")
                }
                return ()
            }
        } catch let error as OpenAIError {
            throw error
        } catch {
            throw OpenAIError.vectorStoreUnavailable("Detach file failed: \(error.localizedDescription)")
        }
    }

    func generateActionsReport(groupedActions: [String: [(action: String, priority: String, isCompleted: Bool)]]) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Format the actions data for the prompt
        var promptContent = "Generate a comprehensive report for the following actions grouped by their source (notes or meetings):\n\n"

        let pendingCount = groupedActions.values.flatMap { $0 }.filter { !$0.isCompleted }.count
        let completedCount = groupedActions.values.flatMap { $0 }.filter { $0.isCompleted }.count

        promptContent += "SUMMARY: \(pendingCount) pending actions, \(completedCount) completed actions\n\n"

        for (source, actions) in groupedActions.sorted(by: { $0.key < $1.key }) {
            promptContent += "\(source):\n"
            for action in actions {
                let status = action.isCompleted ? "✓" : "○"
                promptContent += "  \(status) [\(action.priority.uppercased())] \(action.action)\n"
            }
            promptContent += "\n"
        }

        let systemPrompt = """
        You are an AI assistant that analyzes a list of tasks and outputs only the task names, grouped by priority level.
        For each priority (High, Medium, Low), list the task names one per line under the heading "High Priority:", "Medium Priority:", and "Low Priority:", with no additional commentary.
        Finally, include a minimal action plan, where you might suggest the order of the tasks.
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": promptContent]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 1500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return stripMarkdown(content.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        throw OpenAIError.apiError("Failed to generate report")
    }

    private func stripMarkdown(_ text: String) -> String {
        var cleaned = text

        // Remove bold markers (must be done before single asterisk removal)
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        cleaned = cleaned.replacingOccurrences(of: "__", with: "")

        // Remove italic markers
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        cleaned = cleaned.replacingOccurrences(of: "_", with: "")

        // Remove strikethrough
        cleaned = cleaned.replacingOccurrences(of: "~~", with: "")

        // Remove inline code markers
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")

        // Remove headers
        cleaned = cleaned.replacingOccurrences(of: "# ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "## ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "### ", with: "")

        return cleaned
    }

    // MARK: - Retry Helpers

    private func executeWithRetry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 0.4,
        operationDescription: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var delay = initialDelay

        while true {
            do {
                return try await operation()
            } catch {
                attempt += 1
                if attempt >= maxAttempts || !shouldRetry(error: error) {
                    throw OpenAIError.vectorStoreUnavailable("\(operationDescription) failed: \(error.localizedDescription)")
                }

                let nanoseconds = UInt64(delay * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                delay *= 2
            }
        }
    }

    private func shouldRetry(error: Error) -> Bool {
        if error is URLError { return true }
        if case OpenAIError.apiError(let message) = error {
            return message.contains("429") || message.contains("500") || message.contains("502") || message.contains("503") || message.contains("504")
        }
        return false
    }

    // MARK: - Timeout Protection

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw OpenAIError.apiError("Operation timed out after \(seconds) seconds")
            }

            guard let result = try await group.next() else {
                throw OpenAIError.apiError("Task group completed without result")
            }

            group.cancelAll()
            return result
        }
    }

    private func timeoutForAudio(duration: TimeInterval?, minimum: TimeInterval = 120, maximum: TimeInterval = 360) -> TimeInterval {
        guard let duration, duration > 0 else { return minimum }
        let scaled = duration * 2.5
        return min(maximum, max(minimum, scaled))
    }

    // MARK: - Enhanced Retry Logic for Transcription

    func transcribeAudioWithRetry(audioData: Data, duration: TimeInterval? = nil, maxRetries: Int = 3) async throws -> String {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                print("🎵 Transcribing audio data (attempt \(attempt + 1))")

                // Add timeout protection to each transcription attempt (duration-aware)
                let timeout = timeoutForAudio(duration: duration)
                let transcript = try await withTimeout(seconds: timeout) {
                    try await self.transcribeAudio(audioData: audioData)
                }

                print("🎵 Audio transcribed successfully (timeout window: \(Int(timeout))s)")
                return transcript

            } catch {
                lastError = error
                print("🎵 Audio transcription failed on attempt \(attempt + 1): \(error)")

                // Don't retry if it's not a retryable error
                if !shouldRetry(error: error) {
                    throw error
                }

                // Don't delay after the last attempt
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s exponential backoff
                    print("🎵 Retrying audio transcription in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // If we get here, all retries failed
        throw lastError ?? OpenAIError.transcriptionFailed
    }

    private func transcribeChunkWithRetry(chunk: AudioChunk, maxRetries: Int = 3) async throws -> String {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                print("🎵 Transcribing chunk \(chunk.chunkIndex + 1) (attempt \(attempt + 1))")

                // Add timeout protection to each chunk based on duration
                let timeout = timeoutForAudio(duration: chunk.duration)
                let transcript = try await withTimeout(seconds: timeout) {
                    try await self.transcribeAudio(audioData: chunk.data)
                }

                print("🎵 Chunk \(chunk.chunkIndex + 1) transcribed successfully (timeout window: \(Int(timeout))s)")
                return transcript

            } catch {
                lastError = error
                print("🎵 Chunk \(chunk.chunkIndex + 1) failed on attempt \(attempt + 1): \(error)")

                // Don't retry if it's not a retryable error
                if !shouldRetry(error: error) {
                    throw error
                }

                // Don't delay after the last attempt
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s exponential backoff
                    print("🎵 Retrying chunk \(chunk.chunkIndex + 1) in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // If we get here, all retries failed
        throw lastError ?? OpenAIError.transcriptionFailed
    }
}
