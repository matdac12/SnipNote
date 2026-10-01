import Foundation

struct UploadOptions: Codable, Equatable, Sendable {
  var provider: String
  var language: String?
  var duration: Double
}

struct PreparedUploadFile: Codable, Equatable, Sendable {
  var index: Int
  var relativePath: String
  var expectedBytes: Int64
  var duration: Double
  var contentType: String
  var fileExtension: String
}

enum BackgroundUploadPhase: String, Codable, Sendable {
  case preparing, uploading, retry, queued, completed, cancelled
}

enum UploadTransferState: String, Codable, Sendable {
  case pending, scheduled, uploaded, verified, retry
}

struct UploadFileState: Codable, Equatable, Sendable {
  var file: PreparedUploadFile
  var state: UploadTransferState = .pending
  var sentBytes: Int64 = 0
  var attempts: Int = 0
}

struct BackgroundUploadManifest: Codable, Sendable, Identifiable {
  var version = 1
  var userID: UUID
  var meetingID: UUID
  var sessionID: UUID?
  var jobID: UUID?
  var sourceRelativePath: String
  var options: UploadOptions
  var files: [UploadFileState] = []
  var phase: BackgroundUploadPhase = .preparing
  var errorCode: String?
  var id: UUID { meetingID }
  var bytesSent: Int64 { files.reduce(0) { $0 + min($1.sentBytes, $1.file.expectedBytes) } }
  var totalBytes: Int64 { files.reduce(0) { $0 + $1.file.expectedBytes } }
  var transferRegistered: Bool { phase == .uploading && files.allSatisfy { $0.state != .pending && $0.state != .retry } }
}

struct UploadCapabilities: Codable, Sendable {
  var backgroundUploadEnabled: Bool
}

struct UploadInstructions: Codable, Sendable {
  var index: Int
  var verified: Bool
  var uploadUrl: URL?
  var method: String?
  var headers: [String: String]?
  var expiresAt: Date?
}

struct UploadSessionResponse: Codable, Sendable {
  var sessionId: UUID
  var status: String
  var jobId: UUID?
  var uploadDeadline: Date
  var files: [UploadInstructions]
}

enum BackgroundUploadFailure: Error, LocalizedError {
  case invalidPath, diskFull, invalidManifest, accountMismatch, disabled, unavailable, cancelled
  var errorDescription: String? {
    switch self {
    case .diskFull: return localized("background_upload.disk_full")
    case .accountMismatch: return localized("background_upload.account_changed")
    default: return localized("background_upload.retry")
    }
  }
}
