//
//  MeetingAnalysisPrompts.swift
//  SnipNote
//
//  Created by Codex on 07/03/26.
//

import Foundation

enum MeetingAnalysisPrompts {
    static let overviewInstructions = "You create concise one-sentence meeting overviews. Always respond with exactly one clear, informative sentence in the same language as the input transcript."

    static func overviewPrompt(transcript: String, languageContext: AnalysisLanguageContext) -> String {
        """
        \(languageDirective(for: languageContext))
        Summarize this meeting transcript in exactly one short, clear sentence. Capture the main topic and key outcome or focus of the meeting.

        Examples:
        - "Team discussed Q4 goals and assigned project leads for upcoming initiatives."
        - "Budget review meeting where department heads presented spending proposals."
        - "Weekly standup covering project progress and addressing technical blockers."
        - "Client presentation meeting to review design mockups and gather feedback."

        Meeting Transcript: \(transcript)
        """
    }

    static let summaryInstructions = "You are a professional meeting summarizer. Create structured, comprehensive summaries that capture key decisions, action items, and next steps. Always respond in the same language as the input transcript."

    static func summaryPrompt(transcript: String, languageContext: AnalysisLanguageContext) -> String {
        """
        \(languageDirective(for: languageContext))
        Please create a comprehensive meeting summary from this transcript. Structure your response with the following sections:

        ## Key Discussion Points
        - Main topics discussed
        - Important insights shared

        ## Decisions Made
        - Key decisions reached during the meeting
        - Who is responsible for what

        ## Action Items
        - Tasks assigned with responsible parties
        - Deadlines mentioned

        ## Next Steps
        - Follow-up actions
        - Future meetings or milestones

        Meeting Transcript: \(transcript)
        """
    }

    private static func languageDirective(for context: AnalysisLanguageContext) -> String {
        guard let languageCode = context.languageCode,
              let languageDisplayName = context.languageDisplayName else {
            return "Identify the language spoken and always respond in the same language as the input transcript."
        }

        return """
        The transcript language is \(languageDisplayName) (\(languageCode)).
        Respond only in \(languageDisplayName).
        Do not translate the output into any other language.
        """
    }
}
