import Foundation

// MARK: - Job Status Enum
enum JobStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed

    var displayText: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    var isInProgress: Bool {
        return self == .pending || self == .processing
    }
}

// MARK: - Request/Response Models

struct CreateJobRequest: Codable {
    let userId: String
    let meetingId: String
    let audioUrl: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case meetingId = "meeting_id"
        case audioUrl = "audio_url"
    }
}

struct CreateChunkedJobRequest: Codable {
    let userId: String
    let meetingId: String
    let isChunked: Bool
    let totalChunks: Int
    let duration: Double

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case meetingId = "meeting_id"
        case isChunked = "is_chunked"
        case totalChunks = "total_chunks"
        case duration
    }
}

struct CreateJobResponse: Codable {
    let jobId: String
    let status: JobStatus
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
        case createdAt = "created_at"
    }
}

struct JobStatusResponse: Codable {
    let id: String
    let userId: String
    let meetingId: String
    let audioUrl: String?           // Optional for chunked jobs
    let status: JobStatus
    let transcript: String?
    let overview: String?       // 1-sentence overview
    let summary: String?         // Full summary
    let actions: [ActionItemJSON]?  // Action items from backend
    let duration: Double?
    let errorMessage: String?
    let progressPercentage: Int?    // Progress from 0-100
    let currentStage: String?        // Human-readable stage description
    let createdAt: String
    let updatedAt: String
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case meetingId = "meeting_id"
        case audioUrl = "audio_url"
        case status
        case transcript
        case overview
        case summary
        case actions
        case duration
        case errorMessage = "error_message"
        case progressPercentage = "progress_percentage"
        case currentStage = "current_stage"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }
}

// Action item model matching Python backend JSON format
struct ActionItemJSON: Codable {
    let action: String
    let priority: String
}
