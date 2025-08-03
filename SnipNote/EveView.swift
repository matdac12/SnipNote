//
//  EveView.swift
//  SnipNote
//
//  Created by Eve AI Assistant on 03/08/25.
//

import SwiftUI
import SwiftData

struct EveView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var openAIService = OpenAIService.shared
    
    @Query private var meetings: [Meeting]
    @Query private var notes: [Note]
    @Query private var actions: [Action]
    @Query(sort: \ChatConversation.dateModified, order: .reverse) private var conversations: [ChatConversation]
    
    @State private var currentConversation: ChatConversation?
    @State private var messageText = ""
    @State private var isProcessing = false
    @State private var showContextSelector = false
    @State private var showClearChatAlert = false
    @State private var selectedMeetings: Set<UUID> = []
    @State private var selectedNotes: Set<UUID> = []
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with title and context info
                headerView
                
                // Chat messages
                if let conversation = currentConversation {
                    chatMessagesView(for: conversation)
                } else {
                    emptyStateView
                }
                
                // Input area
                inputView
            }
            .themedBackground()
            .navigationBarHidden(true)
        }
        .onAppear {
            createNewConversationIfNeeded()
            // Initialize with all content selected
            if selectedMeetings.isEmpty && selectedNotes.isEmpty {
                selectedMeetings = Set(meetings.map { $0.id })
                selectedNotes = Set(notes.map { $0.id })
            }
        }
        .sheet(isPresented: $showContextSelector) {
            contextSelectorView
        }
        .alert("Start New Chat", isPresented: $showClearChatAlert) {
            Button("Cancel", role: .cancel) { }
            Button("New Chat", role: .destructive) {
                clearChatHistory()
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
                    Text(themeManager.currentTheme.headerStyle == .brackets ? "[ EVE ]" : "Eve")
                        .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    
                    Text("Your AI Assistant")
                        .themedCaption()
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { showClearChatAlert = true }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                    
                    Button(action: { showContextSelector = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text(contextSummary)
                                .themedCaption()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(themeManager.currentTheme.materialStyle)
                        .cornerRadius(themeManager.currentTheme.cornerRadius)
                    }
                }
            }
            .padding()
            
            Divider()
        }
        .background(themeManager.currentTheme.materialStyle)
    }
    
    private var contextSummary: String {
        let meetingCount = selectedMeetings.count
        let noteCount = selectedNotes.count
        let totalMeetings = meetings.count
        let totalNotes = notes.count
        
        if meetingCount == totalMeetings && noteCount == totalNotes {
            return "All Content"
        } else if meetingCount == 0 && noteCount == 0 {
            return "No Context"
        } else if meetingCount > 0 && noteCount == 0 {
            return "\(meetingCount) Meeting\(meetingCount > 1 ? "s" : "")"
        } else if meetingCount == 0 && noteCount > 0 {
            return "\(noteCount) Note\(noteCount > 1 ? "s" : "")"
        } else {
            return "\(meetingCount) Meeting\(meetingCount > 1 ? "s" : ""), \(noteCount) Note\(noteCount > 1 ? "s" : "")"
        }
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
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "star.fill")
                .font(.system(size: 60))
                .foregroundColor(themeManager.currentTheme.accentColor.opacity(0.3))
            
            VStack(spacing: 8) {
                Text("Welcome to Eve")
                    .font(.system(.title2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                
                Text("Ask me anything about your meetings and notes")
                    .themedBody()
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
    
    // MARK: - Context Selector View
    
    private var contextSelectorView: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Smart selection buttons
                HStack(spacing: 16) {
                    Button(action: selectAll) {
                        HStack {
                            Image(systemName: "checkmark.square.fill")
                            Text("Select All")
                        }
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                    }
                    
                    Button(action: deselectAll) {
                        HStack {
                            Image(systemName: "square")
                            Text("Deselect All")
                        }
                        .font(.system(.body, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(themeManager.currentTheme.destructiveColor)
                    }
                    
                    Spacer()
                }
                .padding()
                
                List {
                    if !meetings.isEmpty {
                        Section("Meetings") {
                            ForEach(meetings.sorted(by: { $0.dateCreated > $1.dateCreated })) { meeting in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(meeting.name.isEmpty ? "Untitled Meeting" : meeting.name)
                                            .themedBody()
                                        Text(meeting.dateCreated.formatted())
                                            .themedCaption()
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: selectedMeetings.contains(meeting.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedMeetings.contains(meeting.id) ? themeManager.currentTheme.accentColor : themeManager.currentTheme.secondaryTextColor)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleMeetingSelection(meeting.id)
                                }
                            }
                        }
                    }
                    
                    if !notes.isEmpty {
                        Section("Notes") {
                            ForEach(notes.sorted(by: { $0.dateCreated > $1.dateCreated })) { note in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(note.title.isEmpty ? "Untitled Note" : note.title)
                                            .themedBody()
                                        Text(note.dateCreated.formatted())
                                            .themedCaption()
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: selectedNotes.contains(note.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedNotes.contains(note.id) ? themeManager.currentTheme.accentColor : themeManager.currentTheme.secondaryTextColor)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleNoteSelection(note.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showContextSelector = false
                        updateConversationContext()
                    }
                }
            }
        }
        .environmentObject(themeManager)
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
    
    private func toggleMeetingSelection(_ id: UUID) {
        if selectedMeetings.contains(id) {
            selectedMeetings.remove(id)
        } else {
            selectedMeetings.insert(id)
        }
    }
    
    private func toggleNoteSelection(_ id: UUID) {
        if selectedNotes.contains(id) {
            selectedNotes.remove(id)
        } else {
            selectedNotes.insert(id)
        }
    }
    
    private func selectAll() {
        selectedMeetings = Set(meetings.map { $0.id })
        selectedNotes = Set(notes.map { $0.id })
    }
    
    private func deselectAll() {
        selectedMeetings.removeAll()
        selectedNotes.removeAll()
    }
    
    private func clearChatHistory() {
        guard let conversation = currentConversation else { return }
        
        // Delete all messages
        for message in conversation.messages {
            modelContext.delete(message)
        }
        
        // Clear the messages array
        conversation.messages.removeAll()
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Error clearing chat history: \(error)")
        }
    }
    
    private func updateConversationContext() {
        guard let conversation = currentConversation else { return }
        
        conversation.isSelectingAllContent = selectedMeetings.count == meetings.count && selectedNotes.count == notes.count
        conversation.selectedMeetingIds = Array(selectedMeetings)
        conversation.selectedNoteIds = Array(selectedNotes)
        
        do {
            try modelContext.save()
        } catch {
            print("Error updating conversation context: \(error)")
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty, !isProcessing, let conversation = currentConversation else { return }
        
        let userMessage = EveMessage(content: messageText, role: .user, conversationId: conversation.id)
        conversation.addMessage(userMessage)
        modelContext.insert(userMessage)
        
        let currentMessage = messageText
        messageText = ""
        isProcessing = true
        
        Task {
            do {
                // Build context from selected content
                let context = buildContext()
                
                // Get response from Eve
                let response = try await openAIService.chatWithEve(
                    message: currentMessage,
                    context: context,
                    conversationHistory: conversation.messages.sorted(by: { $0.timestamp < $1.timestamp })
                )
                
                await MainActor.run {
                    let assistantMessage = EveMessage(content: response, role: .assistant, conversationId: conversation.id)
                    conversation.addMessage(assistantMessage)
                    modelContext.insert(assistantMessage)
                    
                    do {
                        try modelContext.save()
                    } catch {
                        print("Error saving messages: \(error)")
                    }
                    
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    print("Error getting Eve response: \(error)")
                    isProcessing = false
                }
            }
        }
    }
    
    private func buildContext() -> String {
        var context = ""
        
        // Include content from selected items
        let selectedMeetingsList = meetings.filter { selectedMeetings.contains($0.id) }.sorted(by: { $0.dateCreated > $1.dateCreated })
        let selectedNotesList = notes.filter { selectedNotes.contains($0.id) }.sorted(by: { $0.dateCreated > $1.dateCreated })
        
        if !selectedMeetingsList.isEmpty {
            context += "Selected Meetings:\n"
            for meeting in selectedMeetingsList {
                context += "\nMeeting: \(meeting.name.isEmpty ? "Untitled Meeting" : meeting.name) (\(meeting.dateCreated.formatted()))\n"
                if !meeting.location.isEmpty {
                    context += "Location: \(meeting.location)\n"
                }
                context += "Overview: \(meeting.shortSummary)\n"
                if !meeting.aiSummary.isEmpty {
                    context += "Summary: \(meeting.aiSummary)\n"
                }
                if !meeting.audioTranscript.isEmpty && meeting.audioTranscript.count < 1000 {
                    // Include full transcript if it's short
                    context += "Transcript: \(meeting.audioTranscript)\n"
                } else if !meeting.audioTranscript.isEmpty {
                    // Include excerpt for long transcripts
                    context += "Transcript excerpt: \(meeting.audioTranscript.prefix(500))...\n"
                }
            }
            context += "\n"
        }
        
        if !selectedNotesList.isEmpty {
            context += "Selected Notes:\n"
            for note in selectedNotesList {
                context += "\nNote: \(note.title.isEmpty ? "Untitled Note" : note.title) (\(note.dateCreated.formatted()))\n"
                if !note.aiSummary.isEmpty {
                    context += "Summary: \(note.aiSummary)\n"
                }
                if !note.originalTranscript.isEmpty && note.originalTranscript.count < 1000 {
                    // Include full transcript if it's short
                    context += "Content: \(note.originalTranscript)\n"
                } else if !note.originalTranscript.isEmpty {
                    // Include excerpt for long transcripts
                    context += "Content excerpt: \(note.originalTranscript.prefix(500))...\n"
                }
            }
        }
        
        // Add related actions
        let allSelectedIds = selectedMeetings.union(selectedNotes)
        let selectedActions = actions.filter { action in
            if let sourceId = action.sourceNoteId {
                return allSelectedIds.contains(sourceId)
            }
            return false
        }
        
        if !selectedActions.isEmpty {
            context += "\nRelated Action Items:\n"
            for action in selectedActions {
                context += "- [\(action.priority.rawValue)] \(action.title) (Completed: \(action.isCompleted ? "Yes" : "No"))\n"
            }
        }
        
        return context
    }
}