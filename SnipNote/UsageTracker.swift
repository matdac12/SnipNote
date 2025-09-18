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

struct ActionUsageParams: Encodable {
    let p_action_count: Int
}

struct CompletedActionsParams: Encodable {
    let p_count: Int
}

struct AIUsageParams: Encodable {
    let p_summaries: Int
    let p_actions_extracted: Int
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
    
    // MARK: - Action Tracking
    
    func trackActionsCreated(count: Int = 1) async {
        do {
            let params = ActionUsageParams(p_action_count: count)
            try await SupabaseManager.shared.client
                .rpc("increment_action_usage", params: params)
                .execute()
        } catch {
            print("Failed to track action creation: \(error)")
        }
    }
    
    func trackActionsCompleted(count: Int = 1) async {
        do {
            let params = CompletedActionsParams(p_count: count)
            try await SupabaseManager.shared.client
                .rpc("increment_completed_actions", params: params)
                .execute()
        } catch {
            print("Failed to track action completion: \(error)")
        }
    }
    
    // MARK: - AI Usage Tracking
    
    func trackAIUsage(summaries: Int = 0, actionsExtracted: Int = 0, tokensUsed: Int = 0) async {
        do {
            let params = AIUsageParams(
                p_summaries: summaries,
                p_actions_extracted: actionsExtracted,
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
    let totalActionsCreated: Int
    let totalActionsCompleted: Int
    let totalAiSummaries: Int
    let totalAiActionsExtracted: Int
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