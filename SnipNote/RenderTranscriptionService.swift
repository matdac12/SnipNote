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
class RenderTranscriptionService: ObservableObject {
    private let baseURL = "https://snipnote-transcription.onrender.com"
    private var pollingTimer: Timer?

    // MARK: - Async Job Methods

    func createJob(userId: UUID, meetingId: UUID, audioURL: String) async throws -> CreateJobResponse {
        guard let endpoint = URL(string: "\(baseURL)/jobs") else {
            throw TranscriptionError.invalidURL
        }

        print("📤 Creating transcription job for meeting: \(meetingId)")

        // Create request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Create request body
        let jobRequest = CreateJobRequest(
            userId: userId.uuidString,
            meetingId: meetingId.uuidString,
            audioUrl: audioURL
        )

        do {
            request.httpBody = try JSONEncoder().encode(jobRequest)
        } catch {
            throw TranscriptionError.networkError(error)
        }

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

        print("📥 Create job response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Decode response
        do {
            let result = try JSONDecoder().decode(CreateJobResponse.self, from: data)
            print("✅ Job created successfully: \(result.jobId)")
            return result
        } catch {
            print("❌ Decoding error: \(error)")
            throw TranscriptionError.decodingError
        }
    }

    func getJobStatus(jobId: String) async throws -> JobStatusResponse {
        guard let endpoint = URL(string: "\(baseURL)/jobs/\(jobId)") else {
            throw TranscriptionError.invalidURL
        }

        // Create request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

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

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Decode response
        do {
            let result = try JSONDecoder().decode(JobStatusResponse.self, from: data)
            print("📊 Job status: \(result.status.displayText)")
            return result
        } catch {
            print("❌ Decoding error: \(error)")
            throw TranscriptionError.decodingError
        }
    }

    func pollJobStatus(jobId: String, interval: TimeInterval = 15.0, completion: @escaping (JobStatusResponse) -> Void) {
        print("🔄 Starting job polling for: \(jobId) (interval: \(interval)s)")

        // Stop any existing polling
        stopPolling()

        // Create timer for periodic polling
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                do {
                    let status = try await self.getJobStatus(jobId: jobId)

                    // Call completion handler
                    completion(status)

                    // Stop polling if job is no longer in progress
                    if !status.status.isInProgress {
                        print("✅ Job polling complete - final status: \(status.status.displayText)")
                        self.stopPolling()
                    }
                } catch {
                    print("⚠️ Polling error: \(error.localizedDescription)")
                    // Continue polling even on error - could be temporary network issue
                }
            }
        }

        // Fire immediately for first status check
        pollingTimer?.fire()
    }

    func stopPolling() {
        if pollingTimer != nil {
            print("🛑 Stopping job polling")
            pollingTimer?.invalidate()
            pollingTimer = nil
        }
    }

    // MARK: - Synchronous Transcription

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
