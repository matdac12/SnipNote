//
//  UsageTracker.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import Foundation
import Supabase

// MARK: - RPC Parameter Structs


struct MeetingUsageParams: Encodable {
    let p_transcribed: Bool
    let p_meeting_seconds: Int
}

struct AIUsageParams: Encodable {
    let p_summaries: Int
    /// Kept only because the `increment_ai_usage` RPC still declares this argument.
    /// Always 0 now that action extraction no longer exists.
    var p_actions_extracted: Int = 0
    let p_tokens_used: Int
}

class UsageTracker {
    static let shared = UsageTracker()
    
    private init() {}
    
    
    // MARK: - Meeting Tracking
    
    func trackMeetingCreated(transcribed: Bool = false, meetingSeconds: Int = 0) async {
        do {
            let params = MeetingUsageParams(
                p_transcribed: transcribed,
                p_meeting_seconds: meetingSeconds
            )
            try await SupabaseManager.shared.client
                .rpc("increment_meeting_usage", params: params)
                .execute()
        } catch {
            print("Failed to track meeting usage: \(error)")
        }
    }
    
    // MARK: - AI Usage Tracking
    
    func trackAIUsage(summaries: Int = 0, tokensUsed: Int = 0) async {
        do {
            let params = AIUsageParams(
                p_summaries: summaries,
                p_tokens_used: tokensUsed
            )
            try await SupabaseManager.shared.client
                .rpc("increment_ai_usage", params: params)
                .execute()
        } catch {
            print("Failed to track AI usage: \(error)")
        }
    }
    
    // MARK: - Get Usage Stats
    
    func getMyUsageStats() async -> UsageStats? {
        do {
            let response = try await SupabaseManager.shared.client
                .rpc("get_my_usage")
                .execute()
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            let data = response.data
            if let stats = try? decoder.decode([UsageStats].self, from: data),
               let firstStat = stats.first {
                return firstStat
            }
        } catch {
            print("Failed to get usage stats: \(error)")
        }
        return nil
    }
}

// MARK: - Usage Stats Model

struct UsageStats: Codable {
    let totalNotes: Int
    let totalNotesTranscribed: Int
    let totalTranscriptionSeconds: Int
    let totalMeetings: Int
    let totalMeetingsTranscribed: Int
    let totalMeetingSeconds: Int
    let totalAiSummaries: Int
    let totalAiTokensUsed: Int
    let lastActivityAt: Date
    
    var formattedTranscriptionTime: String {
        let minutes = totalTranscriptionSeconds / 60
        let seconds = totalTranscriptionSeconds % 60
        return "\(minutes)m \(seconds)s"
    }
    
    var formattedMeetingTime: String {
        let minutes = totalMeetingSeconds / 60
        let seconds = totalMeetingSeconds % 60
        return "\(minutes)m \(seconds)s"
    }
}