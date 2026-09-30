import Foundation

enum CloudTranscriptionRequest {
  static func make(
    baseRequest: URLRequest,
    audioData: Data,
    language: String?,
    provider: CloudTranscriptionProvider,
    boundary: String
  ) -> URLRequest {
    var request = baseRequest
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue("transcription", forHTTPHeaderField: "X-SnipNote-Task")
    request.setValue(provider.rawValue, forHTTPHeaderField: "X-SnipNote-Transcription-Provider")
    var body = Data()
    if let language {
      body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n".utf8))
    }
    body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/m4a\r\n\r\n".utf8))
    body.append(audioData)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    request.httpBody = body
    return request
  }
}
