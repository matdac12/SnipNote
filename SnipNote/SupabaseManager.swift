//
//  SupabaseManager.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import Foundation
import Supabase

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
        
        // Read audio data
        let audioData = try Data(contentsOf: audioURL)
        let fileSize = audioData.count
        
        // Create file path: userId/meetingId.m4a
        let userIdString = userId.uuidString.lowercased()
        let fileName = "\(meetingId.uuidString.lowercased()).m4a"
        let filePath = "\(userIdString)/\(fileName)"
        
        print("🎵 Uploading audio to path: \(filePath)")
        print("🎵 User ID: \(userIdString)")
        print("🎵 File size: \(fileSize) bytes")
        
        // Upload to storage
        _ = try await client.storage
            .from("recordings")
            .upload(
                filePath,
                data: audioData,
                options: FileOptions(contentType: "audio/m4a")
            )
        
        // Create database record
        let recording = AudioRecording(
            userId: userId,
            meetingId: meetingId,
            filePath: filePath,
            duration: Int(duration),
            fileSize: fileSize
        )
        
        print("🎵 Creating database record for recording")
        
        try await client
            .from("recordings")
            .insert(recording)
            .execute()
        
        return filePath
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
}

// MARK: - Supporting Types

enum SupabaseError: LocalizedError {
    case authRequired
    
    var errorDescription: String? {
        switch self {
        case .authRequired:
            return "User must be authenticated"
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