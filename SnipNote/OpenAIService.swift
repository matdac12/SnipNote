//
//  OpenAIService.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import Foundation
import Security

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
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return response.text
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
}
