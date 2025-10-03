import Foundation

struct TranscriptionResult: Codable {
    let transcript: String
    let duration: Double
}

enum TranscriptionError: LocalizedError {
    case invalidURL
    case serverError(String)
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError:
            return "Failed to decode server response"
        }
    }
}

@MainActor
class RenderTranscriptionService {
    private let baseURL = "https://snipnote-transcription-service.onrender.com"

    func transcribe(audioFileURL: URL) async throws -> TranscriptionResult {
        guard let endpoint = URL(string: "\(baseURL)/transcribe") else {
            throw TranscriptionError.invalidURL
        }

        print("📤 Sending audio to Render server: \(endpoint)")

        // Create multipart request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120 // 2 minute timeout for transcription

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Load audio data
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioFileURL)
            print("📦 Audio file size: \(audioData.count) bytes")
        } catch {
            throw TranscriptionError.networkError(error)
        }

        // Build multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Send request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionError.networkError(error)
        }

        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.serverError("Invalid response from server")
        }

        print("📥 Server response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Decode response
        do {
            let result = try JSONDecoder().decode(TranscriptionResult.self, from: data)
            print("✅ Transcription successful: \(result.transcript.prefix(50))...")
            return result
        } catch {
            print("❌ Decoding error: \(error)")
            throw TranscriptionError.decodingError
        }
    }
}
