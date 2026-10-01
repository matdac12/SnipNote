import Foundation
import Supabase

@MainActor protocol BackgroundUploadServing {
  func capabilities() async throws -> UploadCapabilities
  func bootstrap(_ manifest: BackgroundUploadManifest) async throws -> UploadSessionResponse
  func status(sessionID: UUID) async throws -> UploadSessionResponse
}

@MainActor final class BackgroundUploadAPI: BackgroundUploadServing {
  private let baseURL = "https://api.snipnote.app"
  private let transport: URLSession
  init(transport: URLSession = .shared) { self.transport = transport }
  private struct Bootstrap: Encodable {
    struct File: Encodable {
      var index: Int
      var expectedBytes: Int64
      var duration: Double
      var `extension`: String
      var contentType: String
    }
    var meetingId: UUID
    var transcriptionProvider: String
    var language: String?
    var duration: Double
    var files: [File]
  }
  func capabilities() async throws -> UploadCapabilities {
    try await request(path: "upload-capabilities", body: nil)
  }
  func bootstrap(_ manifest: BackgroundUploadManifest) async throws -> UploadSessionResponse {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let body = Bootstrap(meetingId: manifest.meetingID, transcriptionProvider: manifest.options.provider, language: manifest.options.language, duration: manifest.options.duration, files: manifest.files.map { Bootstrap.File(index: $0.file.index, expectedBytes: $0.file.expectedBytes, duration: $0.file.duration, extension: $0.file.fileExtension, contentType: $0.file.contentType) })
    return try await request(path: "upload-sessions", body: encoder.encode(body), expectedUser: manifest.userID)
  }
  func status(sessionID: UUID) async throws -> UploadSessionResponse {
    try await request(path: "upload-sessions/\(sessionID.uuidString)", body: nil)
  }
  private func request<T: Decodable>(path: String, body: Data?, expectedUser: UUID? = nil) async throws -> T {
    let session = try await SupabaseManager.shared.client.auth.session
    if let expectedUser, expectedUser != session.user.id { throw BackgroundUploadFailure.accountMismatch }
    guard let endpoint = URL(string: "\(baseURL)/\(path)") else { throw BackgroundUploadFailure.unavailable }
    var request = URLRequest(url: endpoint)
    request.httpMethod = body == nil ? "GET" : "POST"
    request.httpBody = body
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30
    let (data, response) = try await transport.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw BackgroundUploadFailure.unavailable }
    guard (200..<300).contains(http.statusCode) else {
      if http.statusCode == 403,
         let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let detail = envelope["detail"] as? [String: Any], detail["code"] as? String == "background_upload_disabled" {
        throw BackgroundUploadFailure.disabled
      }
      throw BackgroundUploadFailure.unavailable
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      guard let date = formatter.date(from: value) else { throw BackgroundUploadFailure.invalidManifest }
      return date
    }
    return try decoder.decode(T.self, from: data)
  }
}
