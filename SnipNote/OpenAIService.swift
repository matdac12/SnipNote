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
            return getAPIKeyFromKeychain()
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
    
    func transcribeAudio(audioData: Data) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120.0 // 2 minute timeout for each chunk
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode != 200 {
                throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "Unknown error")")
            }
        }
        
        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return transcriptionResponse.text
    }
    
    func transcribeAudioFromURL(
        audioURL: URL,
        progressCallback: @escaping (AudioChunkerProgress) -> Void
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
                percentComplete: 50.0
            ))
            
            let audioData = try Data(contentsOf: audioURL)
            let transcript = try await transcribeAudio(audioData: audioData)
            
            progressCallback(AudioChunkerProgress(
                currentChunk: 1,
                totalChunks: 1,
                currentStage: "Transcription complete",
                percentComplete: 100.0
            ))
            
            return transcript
        } else {
            // For large files, use chunked processing
            return try await transcribeAudioInChunks(
                audioURL: audioURL,
                progressCallback: progressCallback
            )
        }
    }
    
    private func transcribeAudioInChunks(
        audioURL: URL,
        progressCallback: @escaping (AudioChunkerProgress) -> Void
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
                    percentComplete: chunkProgress.percentComplete * 0.3
                )
                progressCallback(adjustedProgress)
            }
        )
        
        var transcripts: [String] = []
        let totalChunks = chunks.count
        
        // Process each chunk
        for (index, chunk) in chunks.enumerated() {
            let chunkNumber = index + 1
            
            progressCallback(AudioChunkerProgress(
                currentChunk: chunkNumber,
                totalChunks: totalChunks,
                currentStage: "Transcribing chunk \(chunkNumber) of \(totalChunks)",
                percentComplete: 30.0 + (Double(index) / Double(totalChunks)) * 70.0
            ))
            
            print("🎵 Transcribing chunk \(chunkNumber)/\(totalChunks)")
            
            do {
                let chunkTranscript = try await transcribeAudio(audioData: chunk.data)
                transcripts.append(chunkTranscript)
                print("🎵 Chunk \(chunkNumber) transcribed successfully")
                
            } catch {
                // Retry once before giving up
                print("🎵 Retrying chunk \(chunkNumber)...")
                do {
                    let retryTranscript = try await transcribeAudio(audioData: chunk.data)
                    transcripts.append(retryTranscript)
                    print("🎵 Chunk \(chunkNumber) retry successful")
                } catch {
                    print("🎵 Chunk \(chunkNumber) failed after retry")
                    transcripts.append("[Transcription failed for chunk \(chunkNumber) after retry]")
                }
            }
        }
        
        progressCallback(AudioChunkerProgress(
            currentChunk: totalChunks,
            totalChunks: totalChunks,
            currentStage: "Combining transcripts",
            percentComplete: 100.0
        ))
        
        // Combine all transcripts
        let fullTranscript = transcripts
            .filter { !$0.isEmpty && !$0.contains("[Transcription failed") }
            .joined(separator: " ")
        
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
            model: "gpt-4.1",
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
        Generate an appropriate title for this note transcript in exactly 2-3 words. The title should be concise, descriptive, and capture the main topic or purpose.
        
        Examples:
        - "Meeting Notes Summary"
        - "Weekly Project Update"  
        - "Shopping List Items"
        - "Travel Planning Ideas"
        
        Transcript: \(text)
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4.1",
            messages: [
                ChatMessage(role: "system", content: "You generate concise, descriptive titles for notes. Always respond with exactly 2-3 words, properly capitalized."),
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
        Summarize this meeting transcript in exactly one short, clear sentence. Capture the main topic and key outcome or focus of the meeting.
        
        Examples:
        - "Team discussed Q4 goals and assigned project leads for upcoming initiatives."
        - "Budget review meeting where department heads presented spending proposals."
        - "Weekly standup covering project progress and addressing technical blockers."
        - "Client presentation meeting to review design mockups and gather feedback."
        
        Meeting Transcript: \(text)
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4.1",
            messages: [
                ChatMessage(role: "system", content: "You create concise one-sentence meeting overviews. Always respond with exactly one clear, informative sentence."),
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
            model: "gpt-4.1",
            messages: [
                ChatMessage(role: "system", content: "You are a professional meeting summarizer. Create structured, comprehensive summaries that capture key decisions, action items, and next steps."),
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
        Extract actionable items from this transcript. For each action item, provide:
        1. A clear, concise action description
        2. Priority level (HIGH, MED, LOW)
        
        Return ONLY a JSON array with this exact format:
        [{"action": "action description", "priority": "HIGH|MED|LOW"}]
        
        If no actionable items exist, return an empty array: []
        
        Transcript: \(text)
        """
        
        let requestBody = ChatRequest(
            model: "gpt-4.1",
            messages: [
                ChatMessage(role: "system", content: "You extract actionable items from text and return them as JSON. Be precise and only return valid JSON."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 300
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        
        guard let content = response.choices.first?.message.content else {
            print("🎵 No content in actions response")
            return []
        }
        
        // Clean the content to extract just the JSON
        let cleanedContent = cleanJSONContent(content)
        
        // Parse the JSON response
        do {
            guard let actionData = cleanedContent.data(using: .utf8) else {
                return []
            }
            let actions = try JSONDecoder().decode([ActionItem].self, from: actionData)
            return actions
        } catch {
            return []
        }
    }
    
    private func cleanJSONContent(_ content: String) -> String {
        // Remove common prefixes and suffixes that OpenAI might add
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Look for the start and end of JSON array
        if let startIndex = trimmed.firstIndex(of: "["),
           let endIndex = trimmed.lastIndex(of: "]") {
            let jsonString = String(trimmed[startIndex...endIndex])
            return jsonString
        }
        
        // If no brackets found, check if it's a simple "no actions" response
        if trimmed.lowercased().contains("no action") || 
           trimmed.lowercased().contains("empty") ||
           trimmed.isEmpty {
            return "[]"
        }
        
        // Return original if we can't clean it
        return trimmed
    }
}

struct ActionItem: Codable {
    let action: String
    let priority: String
}

struct TranscriptionResponse: Codable {
    let text: String
}

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatResponse: Codable {
    let choices: [ChatChoice]
}

struct ChatChoice: Codable {
    let message: ChatMessage
}

enum OpenAIError: Error {
    case noAPIKey
    case transcriptionFailed
    case summarizationFailed
    case apiError(String)
}
