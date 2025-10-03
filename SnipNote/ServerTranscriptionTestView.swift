import SwiftUI

struct ServerTranscriptionTestView: View {
    @State private var isTranscribing = false
    @State private var transcript = ""
    @State private var errorMessage = ""
    @State private var duration: Double?
    @State private var processingTime: Date?

    private let service = RenderTranscriptionService()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("Server Transcription Test")
                        .font(.title2)
                        .bold()

                    Text("Testing Render + OpenAI Whisper")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // Test Button
                Button(action: { Task { await testTranscription() } }) {
                    HStack {
                        Image(systemName: isTranscribing ? "hourglass" : "play.circle.fill")
                        Text(isTranscribing ? "Transcribing..." : "Transcribe Server-Side")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isTranscribing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isTranscribing)
                .padding(.horizontal)

                // Loading State
                if isTranscribing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)

                        Text("Uploading audio to Render server...")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let startTime = processingTime {
                            Text("Elapsed: \(Int(Date().timeIntervalSince(startTime)))s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Error Message
                if !errorMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Error")
                                .font(.headline)
                                .foregroundColor(.red)
                        }

                        Text(errorMessage)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Transcript Result
                if !transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Transcript")
                                .font(.headline)
                        }

                        Text(transcript)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)

                        if let duration = duration {
                            HStack {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text("Duration: \(String(format: "%.1f", duration))s")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Instructions
                if transcript.isEmpty && errorMessage.isEmpty && !isTranscribing {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Instructions:")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            instructionRow(number: "1", text: "Place test-audio.m4a in Resources folder")
                            instructionRow(number: "2", text: "Deploy Python service to Render")
                            instructionRow(number: "3", text: "Update Render URL in RenderTranscriptionService.swift")
                            instructionRow(number: "4", text: "Tap 'Transcribe Server-Side' button")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
        .navigationTitle("🧪 Server Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .bold()
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func testTranscription() async {
        isTranscribing = true
        errorMessage = ""
        transcript = ""
        duration = nil
        processingTime = Date()

        do {
            // Load test audio from bundle
            guard let audioURL = Bundle.main.url(forResource: "test-audio", withExtension: "m4a") else {
                errorMessage = "Test audio file not found in bundle. Please add 'test-audio.m4a' to Resources folder and ensure it's included in the Xcode target."
                isTranscribing = false
                processingTime = nil
                return
            }

            print("📤 Sending audio to server...")
            let result = try await service.transcribe(audioFileURL: audioURL)

            print("✅ Received transcript: \(result.transcript)")
            transcript = result.transcript
            duration = result.duration

        } catch let error as TranscriptionError {
            print("❌ Transcription error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        } catch {
            print("❌ Unexpected error: \(error)")
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }

        isTranscribing = false
        processingTime = nil
    }
}

#Preview {
    NavigationStack {
        ServerTranscriptionTestView()
    }
}
