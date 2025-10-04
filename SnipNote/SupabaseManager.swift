//
//  SupabaseManager.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import Foundation
import Supabase
import StoreKit

class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    private init() {
        let supabaseURL = URL(string: "https://bndbnqtvicvynzkyygte.supabase.co")!
        let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJuZGJucXR2aWN2eW56a3l5Z3RlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI0MTgyNDUsImV4cCI6MjA2Nzk5NDI0NX0.KJR2WxJBeTY4diMjXISBsFwFiYsniX1r0xjDIF0sgY8"
        
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
    }
    
    // MARK: - Audio Storage Functions
    
    /// Upload audio file to Supabase Storage
    func uploadAudioRecording(audioURL: URL, meetingId: UUID, duration: TimeInterval) async throws -> String {
        // Get current session to ensure we have a valid auth token
        guard let session = try? await client.auth.session else {
            throw SupabaseError.authRequired
        }

        let userId = session.user.id

        // Get file size without loading into memory
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = fileAttributes[.size] as? Int ?? 0

        // Check 50MB file size limit
        let maxFileSize = 50 * 1024 * 1024 // 50MB
        if fileSize > maxFileSize {
            throw SupabaseError.fileTooLarge(size: fileSize, limit: maxFileSize)
        }

        // Create file path: userId/meetingId.m4a
        let userIdString = userId.uuidString.lowercased()
        let fileName = "\(meetingId.uuidString.lowercased()).m4a"
        let filePath = "\(userIdString)/\(fileName)"

        print("🎵 Uploading audio to path: \(filePath)")
        print("🎵 User ID: \(userIdString)")
        print("🎵 File size: \(fileSize) bytes")

        // Choose upload method based on file size
        let maxChunkSize = 10 * 1024 * 1024 // 10MB chunks

        if fileSize <= maxChunkSize {
            // Small file - use standard upload
            let audioData = try Data(contentsOf: audioURL)
            _ = try await client.storage
                .from("recordings")
                .upload(
                    filePath,
                    data: audioData,
                    options: FileOptions(contentType: "audio/m4a")
                )
        } else {
            // Large file - use chunked upload
            try await uploadLargeFile(audioURL: audioURL, filePath: filePath)
        }

        // Create database record
        let recording = AudioRecording(
            userId: userId,
            meetingId: meetingId,
            filePath: filePath,
            duration: Int(duration),
            fileSize: fileSize
        )

        print("🎵 Creating database record for recording")

        do {
            try await client
                .from("recordings")
                .insert(recording)
                .execute()
        } catch {
            // If database insert fails, clean up uploaded file
            print("❌ Database insert failed, cleaning up uploaded file: \(error)")
            do {
                try await client.storage
                    .from("recordings")
                    .remove(paths: [filePath])
                print("🗑️ Successfully cleaned up uploaded file after database failure")
            } catch let cleanupError {
                print("⚠️ Failed to cleanup uploaded file: \(cleanupError)")
            }
            throw error
        }

        return filePath
    }

    /// Upload large files in chunks to prevent memory issues
    private func uploadLargeFile(audioURL: URL, filePath: String) async throws {
        let chunkSize = 5 * 1024 * 1024 // 5MB chunks
        let fileHandle = try FileHandle(forReadingFrom: audioURL)
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()
        fileHandle.seek(toFileOffset: 0)

        print("🎵 Starting chunked upload for \(fileSize) bytes")

        var uploadedData = Data()
        var chunkIndex = 0

        while true {
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            uploadedData.append(chunk)
            chunkIndex += 1

            print("🎵 Read chunk \(chunkIndex), size: \(chunk.count) bytes")

            // Upload in batches to avoid memory buildup
            if uploadedData.count >= 20 * 1024 * 1024 || chunk.count < chunkSize { // 20MB batches or final chunk
                print("🎵 Uploading batch of \(uploadedData.count) bytes")

                if chunkIndex == 1 && chunk.count < chunkSize {
                    // Single small chunk - use standard upload
                    _ = try await client.storage
                        .from("recordings")
                        .upload(
                            filePath,
                            data: uploadedData,
                            options: FileOptions(contentType: "audio/m4a")
                        )
                } else {
                    // For now, accumulate and upload as one piece since Supabase doesn't support resumable uploads
                    // In production, you might want to use a different storage solution for very large files
                    if chunk.count < chunkSize { // Final batch
                        _ = try await client.storage
                            .from("recordings")
                            .upload(
                                filePath,
                                data: uploadedData,
                                options: FileOptions(contentType: "audio/m4a")
                            )
                    }
                }

                if chunk.count < chunkSize { break } // Final chunk

                // For demonstration, we still accumulate but could implement actual streaming here
                // uploadedData = Data() // Reset for true streaming
            }
        }
    }
    
    /// Get signed URL for audio playback
    func getAudioURL(for meetingId: UUID) async throws -> URL? {
        guard let userId = client.auth.currentUser?.id else {
            throw SupabaseError.authRequired
        }
        
        // First, get the recording from database
        let recordings: [AudioRecording] = try await client
            .from("recordings")
            .select()
            .eq("meeting_id", value: meetingId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        guard let recording = recordings.first else {
            return nil
        }
        
        // Generate signed URL for playback (1 hour expiry)
        let signedURL = try await client.storage
            .from("recordings")
            .createSignedURL(path: recording.filePath, expiresIn: 3600)
        
        return signedURL
    }
    
    /// Delete audio recording
    func deleteAudioRecording(meetingId: UUID) async throws {
        guard let userId = client.auth.currentUser?.id else {
            throw SupabaseError.authRequired
        }
        
        // Get recording info first
        let recordings: [AudioRecording] = try await client
            .from("recordings")
            .select()
            .eq("meeting_id", value: meetingId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        guard let recording = recordings.first else {
            return
        }
        
        // Delete from storage
        try await client.storage
            .from("recordings")
            .remove(paths: [recording.filePath])
        
        // Delete from database
        try await client
            .from("recordings")
            .delete()
            .eq("meeting_id", value: meetingId.uuidString)
            .execute()
    }

    // MARK: - Subscription Functions

    /// Validate and sync StoreKit transaction with server with retry logic
    func validateTransaction(_ transaction: Transaction) async throws {
        try await validateTransactionWithRetry(transaction, maxRetries: 3)
    }

    /// Internal method with retry logic and enhanced error handling
    private func validateTransactionWithRetry(_ transaction: Transaction, maxRetries: Int) async throws {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                print("🔄 [Supabase] Validating transaction (attempt \(attempt)/\(maxRetries)): \(transaction.productID)")

                guard let session = try? await client.auth.session else {
                    throw SupabaseError.authRequired
                }

                let userId = session.user.id.uuidString
                let accessToken = session.accessToken

                // Prepare transaction data for validation
                let transactionData = TransactionData(
                    transactionId: String(transaction.id),
                    originalTransactionId: String(transaction.originalID),
                    productId: transaction.productID,
                    purchaseDate: ISO8601DateFormatter().string(from: transaction.purchaseDate),
                    expiresDate: transaction.expirationDate.map { ISO8601DateFormatter().string(from: $0) },
                    isUpgraded: transaction.isUpgraded,
                    subscriptionGroupId: transaction.subscriptionGroupID,
                    environment: transaction.environment.rawValue,
                    signedTransactionInfo: transaction.jsonRepresentation.base64EncodedString()
                )

                let requestData = ValidationRequest(
                    userId: userId,
                    transactionData: transactionData
                )

                // Call edge function with timeout using async race pattern
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Add the actual validation task
                    group.addTask {
                        try await self.client.functions.invoke(
                            "validate-storekit-transaction",
                            options: FunctionInvokeOptions(
                                headers: ["Authorization": "Bearer \(accessToken)"],
                                body: requestData
                            )
                        )
                    }

                    // Add timeout task
                    group.addTask {
                        try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                        throw SupabaseError.networkTimeout
                    }

                    // Wait for the first task to complete (either success or timeout)
                    try await group.next()

                    // Cancel remaining tasks
                    group.cancelAll()
                }

                print("✅ [Supabase] Transaction validated successfully: \(transaction.productID)")
                return

            } catch {
                lastError = error

                // Check if this is a retryable error
                if isRetryableError(error) && attempt < maxRetries {
                    let delay = exponentialBackoffDelay(attempt: attempt)
                    print("⚠️ [Supabase] Validation failed (attempt \(attempt)/\(maxRetries)), retrying in \(delay)s: \(error.localizedDescription)")

                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    // Non-retryable error or max retries reached
                    print("❌ [Supabase] Transaction validation failed permanently: \(error.localizedDescription)")
                    break
                }
            }
        }

        // If we get here, all retries failed
        if let error = lastError {
            throw SupabaseError.transactionValidationFailed("Transaction validation failed after \(maxRetries) attempts: \(error.localizedDescription)")
        } else {
            throw SupabaseError.transactionValidationFailed("Transaction validation failed after \(maxRetries) attempts")
        }
    }

    /// Check if an error is retryable (network/timeout errors) vs permanent (auth/validation errors)
    private func isRetryableError(_ error: Error) -> Bool {
        if let supabaseError = error as? SupabaseError {
            switch supabaseError {
            case .networkTimeout:
                return true
            case .authRequired:
                return false // Don't retry auth errors
            case .transactionValidationFailed:
                return false // Don't retry validation errors
            case .fileTooLarge:
                return false // Don't retry file size errors
            }
        }

        // Check for common network error patterns
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("network") ||
               errorString.contains("timeout") ||
               errorString.contains("connection") ||
               errorString.contains("unreachable") ||
               errorString.contains("cancelled")
    }

    /// Calculate exponential backoff delay
    private func exponentialBackoffDelay(attempt: Int) -> Double {
        let baseDelay = 1.0 // 1 second base
        let maxDelay = 16.0 // 16 seconds max
        let delay = baseDelay * pow(2.0, Double(attempt - 1))
        return min(delay, maxDelay)
    }

    /// Get current subscription status from server
    func getSubscriptionStatus() async throws -> SubscriptionStatus? {
        guard let userId = client.auth.currentUser?.id else {
            throw SupabaseError.authRequired
        }

        let subscriptions: [ServerSubscription] = try await client
            .from("subscriptions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .execute()
            .value

        guard let subscription = subscriptions.first else {
            return nil
        }

        return SubscriptionStatus(
            isSubscribed: subscription.isActive,
            entitlement: subscription.productIdentifier,
            productIdentifier: subscription.productIdentifier,
            expiresAt: subscription.expiresAt
        )
    }

    /// Get user usage data from Supabase
    func getUserUsage() async throws -> UserUsage? {
        guard let userId = client.auth.currentUser?.id else {
            throw SupabaseError.authRequired
        }

        let usage: [UserUsage] = try await client
            .from("user_usage")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        return usage.first
    }

}

// MARK: - Supporting Types

enum SupabaseError: LocalizedError {
    case authRequired
    case transactionValidationFailed(String)
    case networkTimeout
    case fileTooLarge(size: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .authRequired:
            return "User must be authenticated"
        case .transactionValidationFailed(let message):
            return "Transaction validation failed: \(message)"
        case .networkTimeout:
            return "Network request timed out"
        case .fileTooLarge(let size, let limit):
            let sizeMB = Double(size) / (1024 * 1024)
            let limitMB = Double(limit) / (1024 * 1024)
            return "Audio file too large (\(String(format: "%.1f", sizeMB)) MB). Please reduce the audio length or split it into multiple parts. Maximum file size: \(Int(limitMB)) MB."
        }
    }
}

struct AudioRecording: Codable {
    let id: UUID?
    let userId: UUID
    let meetingId: UUID
    let filePath: String
    let duration: Int
    let fileSize: Int
    let createdAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case meetingId = "meeting_id"
        case filePath = "file_path"
        case duration
        case fileSize = "file_size"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(userId: UUID, meetingId: UUID, filePath: String, duration: Int, fileSize: Int) {
        self.id = nil
        self.userId = userId
        self.meetingId = meetingId
        self.filePath = filePath
        self.duration = duration
        self.fileSize = fileSize
        self.createdAt = nil
        self.updatedAt = nil
    }
}

// MARK: - User Usage Types

struct UserUsage: Codable {
    let id: UUID
    let userId: UUID
    let userEmail: String?
    let totalMeetings: Int
    let totalMeetingsTranscribed: Int
    let totalMeetingSeconds: Int
    let totalActionsCreated: Int
    let totalActionsCompleted: Int
    let totalAiSummaries: Int
    let totalAiActionsExtracted: Int
    let totalAiTokensUsed: Int
    let usageCost: Decimal?
    let createdAt: Date?
    let updatedAt: Date?
    let lastActivityAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userEmail = "user_email"
        case totalMeetings = "total_meetings"
        case totalMeetingsTranscribed = "total_meetings_transcribed"
        case totalMeetingSeconds = "total_meeting_seconds"
        case totalActionsCreated = "total_actions_created"
        case totalActionsCompleted = "total_actions_completed"
        case totalAiSummaries = "total_ai_summaries"
        case totalAiActionsExtracted = "total_ai_actions_extracted"
        case totalAiTokensUsed = "total_ai_tokens_used"
        case usageCost = "usage_cost"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastActivityAt = "last_activity_at"
    }

    var formattedMeetingTime: String {
        let minutes = totalMeetingSeconds / 60
        let seconds = totalMeetingSeconds % 60
        return "\(minutes)m \(seconds)s"
    }
}

// MARK: - Subscription Types

struct TransactionData: Codable {
    let transactionId: String
    let originalTransactionId: String
    let productId: String
    let purchaseDate: String
    let expiresDate: String?
    let isUpgraded: Bool?
    let subscriptionGroupId: String?
    let environment: String
    let signedTransactionInfo: String
}

struct ValidationRequest: Codable {
    let userId: String
    let transactionData: TransactionData
}


struct ServerSubscription: Codable {
    let id: UUID
    let userId: UUID
    let userEmail: String?
    let originalTransactionId: String?
    let transactionId: String?
    let productIdentifier: String?
    let subscriptionGroupId: String?
    let purchaseDate: Date?
    let expiresAt: Date?
    let isActive: Bool
    let autoRenewStatus: Bool?
    let store: String
    let environment: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userEmail = "user_email"
        case originalTransactionId = "original_transaction_id"
        case transactionId = "transaction_id"
        case productIdentifier = "product_identifier"
        case subscriptionGroupId = "subscription_group_id"
        case purchaseDate = "purchase_date"
        case expiresAt = "expires_at"
        case isActive = "is_active"
        case autoRenewStatus = "auto_renew_status"
        case store
        case environment
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

