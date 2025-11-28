//
//  EveView.swift
//  SnipNote
//
//  Created by Eve AI Assistant on 03/08/25.
//

import SwiftUI
import SwiftData
import StoreKit

struct EveView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var openAIService = OpenAIService.shared
    @StateObject private var storeManager = StoreManager.shared

    // Pre-selected meeting ID when navigating from MeetingDetailView
    private let preSelectedMeetingId: UUID?

    @Query private var meetings: [Meeting]
    @Query(sort: \ChatConversation.dateModified, order: .reverse) private var conversations: [ChatConversation]

    @State private var currentConversation: ChatConversation?
    @State private var messageText = ""
    @State private var isProcessing = false
    @State private var showClearChatAlert = false
    @FocusState private var isInputFocused: Bool
    @State private var showingPaywall = false

    init(preSelectedMeetingId: UUID? = nil) {
        self.preSelectedMeetingId = preSelectedMeetingId
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and context info
            headerView

            // Check subscription for AI features
            if !storeManager.hasActiveSubscription {
                // Show upgrade prompt for free users
                VStack {
                    Spacer()
                    UpgradePromptView(
                        title: "Eve is a Pro Feature",
                        message: "AI-powered chat assistant is available exclusively for Pro members. Upgrade to unlock Eve and all premium features.",
                        icon: "wand.and.stars.inverse"
                    )
                    Spacer()
                }
                .padding()
            } else {
                // Chat messages for Pro users
                if let conversation = currentConversation {
                    chatMessagesView(for: conversation)
                } else {
                    emptyStateView
                }

                // Input area for Pro users
                inputView
            }
        }
        .themedBackground()
        .navigationBarHidden(true)
        .onAppear {
            createNewConversationIfNeeded()
        }
        .alert("Start New Chat", isPresented: $showClearChatAlert) {
            Button("Cancel", role: .cancel) { }
            Button("New Chat", role: .destructive) {
                startNewConversation()
            }
        } message: {
            Text("Are you sure you want to start a new chat? Current conversation will be cleared.")
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eve")
                        .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))

                    Text("Your AI Assistant")
                        .themedCaption()
                }

                Spacer()

                HStack(spacing: 12) {
                    // Show current meeting context
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text(currentMeetingName)
                            .themedCaption()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(themeManager.currentTheme.materialStyle)
                    .cornerRadius(themeManager.currentTheme.cornerRadius)

                    Button(action: { showClearChatAlert = true }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                }
            }
            .padding()

            Divider()
        }
        .background(themeManager.currentTheme.materialStyle)
    }

    private var currentMeetingName: String {
        guard let meetingId = preSelectedMeetingId,
              let meeting = meetings.first(where: { $0.id == meetingId }) else {
            return "No Meeting"
        }
        return meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
    }

    private var currentMeeting: Meeting? {
        guard let meetingId = preSelectedMeetingId else { return nil }
        return meetings.first(where: { $0.id == meetingId })
    }

    // MARK: - Chat Messages View

    private func chatMessagesView(for conversation: ChatConversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(conversation.messages.sorted(by: { $0.timestamp < $1.timestamp })) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }

                    if isProcessing {
                        HStack {
                            EveTypingIndicator()
                                .padding()
                                .background(themeManager.currentTheme.materialStyle)
                                .cornerRadius(20)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .onChange(of: conversation.messages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        ZStack {
            themeManager.currentTheme.gradient
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "star.fill")
                    .font(.system(size: 60))
                    .foregroundColor(themeManager.currentTheme.accentColor.opacity(0.5))

                VStack(spacing: 8) {
                    Text("Welcome to Eve")
                        .font(.system(.title, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))

                    Text("Ask me anything about your meetings")
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .regular))
                        .multilineTextAlignment(.center)
                        .foregroundColor(themeManager.currentTheme.secondaryTextColor)
                }

                // Quick action buttons
                VStack(spacing: 12) {
                    quickActionButton("What are my pending actions?", systemImage: "checklist")
                    quickActionButton("Summarize today's meetings", systemImage: "calendar")
                    quickActionButton("What did we discuss recently?", systemImage: "bubble.left.and.bubble.right")
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .padding()
        }
    }

    private func quickActionButton(_ text: String, systemImage: String) -> some View {
        Button(action: {
            messageText = text
            sendMessage()
        }) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                Text(text)
                    .themedBody()
                Spacer()
            }
            .padding()
            .background(themeManager.currentTheme.materialStyle)
            .cornerRadius(themeManager.currentTheme.cornerRadius)
        }
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                TextField("Ask Eve...", text: $messageText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(themeManager.currentTheme.materialStyle)
                    .cornerRadius(20)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20))
                        .foregroundColor(messageText.isEmpty || isProcessing ? themeManager.currentTheme.secondaryTextColor : themeManager.currentTheme.accentColor)
                }
                .disabled(messageText.isEmpty || isProcessing)
            }
            .padding()
        }
        .background(themeManager.currentTheme.backgroundColor)
    }

    // MARK: - Helper Methods

    private func createNewConversationIfNeeded() {
        if currentConversation == nil && conversations.isEmpty {
            let newConversation = ChatConversation()
            modelContext.insert(newConversation)
            currentConversation = newConversation

            do {
                try modelContext.save()
            } catch {
                print("Error creating conversation: \(error)")
            }
        } else if currentConversation == nil {
            currentConversation = conversations.first
        }
    }

    private func startNewConversation() {
        guard let conversation = currentConversation else { return }

        isProcessing = false
        messageText = ""

        // Delete all messages from the current conversation
        for message in conversation.messages {
            modelContext.delete(message)
        }

        conversation.messages.removeAll()
        conversation.openAIConversationId = nil
        conversation.dateModified = Date()

        do {
            try modelContext.save()
        } catch {
            print("Error clearing chat history: \(error)")
        }

        Task { @MainActor in
            do {
                let newConversationId = try await openAIService.createConversation()
                conversation.openAIConversationId = newConversationId
                do {
                    try modelContext.save()
                } catch {
                    print("Error saving new conversation ID: \(error)")
                }
            } catch {
                print("Error creating new Eve conversation: \(error)")
            }
        }
    }

    private func sendMessage() {
        guard !messageText.isEmpty, !isProcessing, let conversation = currentConversation else { return }
        guard let meeting = currentMeeting else {
            print("No meeting selected for Eve chat")
            return
        }

        let promptVariables = meetingPromptVariables(for: meeting)

        let userMessage = EveMessage(content: messageText, role: .user, conversationId: conversation.id)
        conversation.addMessage(userMessage)
        modelContext.insert(userMessage)

        let currentMessage = messageText
        messageText = ""
        isProcessing = true

        Task { @MainActor in
            do {
                let result = try await openAIService.chatWithEve(
                    message: currentMessage,
                    promptVariables: promptVariables,
                    conversationId: conversation.openAIConversationId
                )

                conversation.openAIConversationId = result.conversationId
                let assistantMessage = EveMessage(content: result.responseText, role: .assistant, conversationId: conversation.id)
                conversation.addMessage(assistantMessage)
                modelContext.insert(assistantMessage)

                do {
                    try modelContext.save()
                } catch {
                    print("Error saving messages: \(error)")
                }

                isProcessing = false
            } catch {
                print("Error getting Eve response: \(error)")
                isProcessing = false
            }
        }
    }

    @MainActor
    private func meetingPromptVariables(for meeting: Meeting) -> EvePromptVariables {
        let name = meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
        let dateString = meeting.dateCreated.formatted(date: .abbreviated, time: .shortened)
        let overviewSource = [meeting.shortSummary, meeting.meetingNotes, meeting.aiSummary]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "No overview available."
        let overview = "• \(name) (\(dateString)): \(overviewSource)"

        let summarySource = meeting.aiSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = summarySource.isEmpty ? "Summary not available yet." : "\(name):\n\(summarySource)"

        let transcript = meeting.audioTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        return EvePromptVariables(
            meetingOverview: overview,
            meetingSummary: summary,
            meetingTranscription: transcript
        )
    }

}
