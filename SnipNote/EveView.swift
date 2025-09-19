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
    @Binding var selectedMeetingForEve: UUID?
    
    @Query private var meetings: [Meeting]
    @Query(sort: \ChatConversation.dateModified, order: .reverse) private var conversations: [ChatConversation]
    
    @State private var currentConversation: ChatConversation?
    @State private var messageText = ""
    @State private var isProcessing = false
    @State private var showContextSelector = false
    @State private var showClearChatAlert = false
    @State private var selectedMeetings: Set<UUID> = []
    @FocusState private var isInputFocused: Bool
    @State private var showingPaywall = false
    @State private var userAIContext: UserAIContext?
    @State private var vectorStoreId: String?
    @State private var isSyncingContext = false
    @State private var contextWarning: String?

    init(selectedMeetingForEve: Binding<UUID?> = .constant(nil)) {
        self._selectedMeetingForEve = selectedMeetingForEve
    }

    var body: some View {
        NavigationView {
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
                    
                    if let warning = contextWarning {
                        Text(warning)
                            .font(.system(.footnote, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(themeManager.currentTheme.warningColor)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .background(themeManager.currentTheme.materialStyle)
                            .cornerRadius(themeManager.currentTheme.cornerRadius)
                            .padding(.horizontal)
                    }
                    
                    // Input area for Pro users
                    inputView
                }
            }
            .themedBackground()
            .navigationBarHidden(true)
        }
        .onAppear {
            createNewConversationIfNeeded()
            initializeSelectedMeetings()
            Task { @MainActor in
                await prepareUserAIContextIfNeeded()
                await synchronizeVectorStoreForCurrentSelection()
            }
        }
        .sheet(isPresented: $showContextSelector) {
            contextSelectorView
        }
        .alert("Start New Chat", isPresented: $showClearChatAlert) {
            Button("Cancel", role: .cancel) { }
            Button("New Chat", role: .destructive) {
                startNewConversation()
            }
        } message: {
            Text("Are you sure you want to start a new chat? Current conversation will be cleared.")
        }
        .onChange(of: meetings) { _, _ in
            initializeSelectedMeetings()
            Task { @MainActor in
                await synchronizeVectorStoreForCurrentSelection()
            }
        }
        .onChange(of: selectedMeetingForEve) { _, newValue in
            if newValue != nil {
                initializeSelectedMeetings()
                Task { @MainActor in
                    await synchronizeVectorStoreForCurrentSelection()
                }
            }
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
        if meetings.isEmpty {
            return "No Meetings"
        }

        if selectedMeetings.isEmpty || selectedMeetings.count == meetings.count {
            return "All Meetings"
        }

        if selectedMeetings.count == 1,
           let meeting = meetings.first(where: { selectedMeetings.contains($0.id) }) {
            let name = meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
            return name
        }

        return "\(selectedMeetings.count) Meetings"
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


    private func selectAll() {
        selectedMeetings = Set(meetings.map { $0.id })
    }
    
    private func deselectAll() {
        selectedMeetings.removeAll()
    }
    
    private func startNewConversation() {
        guard let conversation = currentConversation else { return }
        
        isProcessing = false
        messageText = ""
        contextWarning = nil

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

        Task { @MainActor in
            await synchronizeVectorStoreForCurrentSelection()
        }
    }
    
    private func updateConversationContext() {
        guard let conversation = currentConversation else { return }

        let allMeetingIds = Set(meetings.map { $0.id })
        let effectiveSelection = selectedMeetings.isEmpty ? allMeetingIds : selectedMeetings

        conversation.isSelectingAllContent = effectiveSelection.count == allMeetingIds.count
        conversation.selectedMeetingIds = Array(effectiveSelection)
        conversation.selectedNoteIds = []
        
        do {
            try modelContext.save()
        } catch {
            print("Error updating conversation context: \(error)")
        }

        Task {
            await synchronizeVectorStoreForCurrentSelection()
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty, !isProcessing, let conversation = currentConversation else { return }
        let allMeetingIds = Set(meetings.map { $0.id })
        let effectiveSelection = selectedMeetings.isEmpty ? allMeetingIds : selectedMeetings
        let selectedMeetingsList = meetings.filter { effectiveSelection.contains($0.id) }

        let promptVariables = meetingPromptVariables(for: selectedMeetingsList)

        let userMessage = EveMessage(content: messageText, role: .user, conversationId: conversation.id)
        conversation.addMessage(userMessage)
        modelContext.insert(userMessage)

        let currentMessage = messageText
        messageText = ""
        isProcessing = true
        
        Task { @MainActor in
            do {
                let vectorStoreId = try await ensureVectorStoreAndSync(for: effectiveSelection)
                contextWarning = nil

                let result = try await openAIService.chatWithEve(
                    message: currentMessage,
                    promptVariables: promptVariables,
                    conversationId: conversation.openAIConversationId,
                    vectorStoreId: vectorStoreId
                )

                conversation.openAIConversationId = result.conversationId
                self.vectorStoreId = vectorStoreId
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
                handleVectorStoreFailure(error)

                do {
                    let result = try await openAIService.chatWithEve(
                        message: currentMessage,
                        promptVariables: promptVariables,
                        conversationId: conversation.openAIConversationId,
                        vectorStoreId: nil
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
                } catch {
                    print("Error getting Eve response: \(error)")
                }

                isProcessing = false
            }
        }
    }

    @MainActor
    private func meetingPromptVariables(for meetings: [Meeting]) -> EvePromptVariables {
        guard !meetings.isEmpty else {
            return EvePromptVariables(
                meetingOverview: "No meetings selected.",
                meetingSummary: ""
            )
        }

        let overviewComponents = meetings.map { meeting -> String in
            let name = meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
            let dateString = meeting.dateCreated.formatted(date: .abbreviated, time: .shortened)
            let overviewSource = [meeting.shortSummary, meeting.meetingNotes, meeting.aiSummary]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "No overview available."
            return "• \(name) (\(dateString)): \(overviewSource)"
        }

        let summaryComponents = meetings.compactMap { meeting -> String? in
            let summarySource = meeting.aiSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summarySource.isEmpty else { return nil }
            let name = meeting.name.isEmpty ? "Untitled Meeting" : meeting.name
            return "\(name):\n\(summarySource)"
        }

        let overview = overviewComponents.joined(separator: "\n")
        let summary = summaryComponents.isEmpty ? "Summaries not available yet." : summaryComponents.joined(separator: "\n\n")

        return EvePromptVariables(
            meetingOverview: overview,
            meetingSummary: summary
        )
    }

    @MainActor
    private func initializeSelectedMeetings() {
        let availableIds = Set(meetings.map { $0.id })
        guard !availableIds.isEmpty else {
            selectedMeetings.removeAll()
            return
        }

        // Check if we have a pre-selected meeting from navigation
        if let preSelectedId = selectedMeetingForEve, availableIds.contains(preSelectedId) {
            selectedMeetings = [preSelectedId]
            // Clear the binding so it doesn't persist
            selectedMeetingForEve = nil
            // Start a new conversation when navigating with a specific meeting
            startNewConversation()
            return
        }

        if selectedMeetings.isEmpty {
            let storedIds = Set(currentConversation?.selectedMeetingIds ?? [])
            let intersection = storedIds.intersection(availableIds)
            selectedMeetings = intersection.isEmpty ? availableIds : intersection
        } else {
            let filtered = selectedMeetings.intersection(availableIds)
            selectedMeetings = filtered.isEmpty ? availableIds : filtered
        }
    }

    @MainActor
    private func prepareUserAIContextIfNeeded() async {
        guard let userId = authManager.currentUser?.id else { return }

        do {
            let context: UserAIContext
            if let existing = userAIContext {
                context = existing
            } else {
                let created = try ensureUserAIContext(for: userId)
                userAIContext = created
                context = created
            }

            let storeId = try await openAIService.ensureVectorStore(userId: userId, existingVectorStoreId: context.vectorStoreId)

            context.vectorStoreId = storeId
            vectorStoreId = storeId
            context.updatedAt = Date()
            do {
                try modelContext.save()
            } catch {
                print("Error saving vector store id: \(error)")
            }
        } catch {
            handleVectorStoreFailure(error)
        }
    }

    @MainActor
    private func ensureVectorStoreAndSync(for selectedIds: Set<UUID>) async throws -> String? {
        guard let userId = authManager.currentUser?.id else { return nil }

        let context: UserAIContext
        if let existing = userAIContext {
            context = existing
        } else {
            let created = try ensureUserAIContext(for: userId)
            userAIContext = created
            context = created
        }

        let storeId = try await openAIService.ensureVectorStore(userId: userId, existingVectorStoreId: context.vectorStoreId)

        context.vectorStoreId = storeId
        vectorStoreId = storeId
        context.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            print("Error saving vector store id: \(error)")
        }

        let meetingsSnapshot = meetings
        _ = try await syncVectorStore(context: context, vectorStoreId: storeId, selectedIds: selectedIds, meetingsSnapshot: meetingsSnapshot)
        contextWarning = nil
        return storeId
    }

    @MainActor
    private func synchronizeVectorStoreForCurrentSelection() async {
        guard !isSyncingContext else { return }
        isSyncingContext = true
        defer { isSyncingContext = false }

        guard let userId = authManager.currentUser?.id else { return }

        do {
            let context: UserAIContext
            if let existing = userAIContext {
                context = existing
            } else {
                let created = try ensureUserAIContext(for: userId)
                userAIContext = created
                context = created
            }

            let storeId = try await openAIService.ensureVectorStore(userId: userId, existingVectorStoreId: context.vectorStoreId)

            context.vectorStoreId = storeId
            vectorStoreId = storeId
            context.updatedAt = Date()
            do {
                try modelContext.save()
            } catch {
                print("Error saving vector store id: \(error)")
            }

            let meetingsSnapshot = meetings
            let effectiveSelection = effectiveMeetingSelection(allMeetingIds: Set(meetingsSnapshot.map { $0.id }))
            _ = try await syncVectorStore(context: context, vectorStoreId: storeId, selectedIds: effectiveSelection, meetingsSnapshot: meetingsSnapshot)
            contextWarning = nil
        } catch {
            handleVectorStoreFailure(error)
        }
    }

    @MainActor
    private func syncVectorStore(
        context: UserAIContext,
        vectorStoreId: String,
        selectedIds: Set<UUID>,
        meetingsSnapshot: [Meeting]
    ) async throws -> Bool {
        let meetingsById = Dictionary(uniqueKeysWithValues: meetingsSnapshot.map { ($0.id, $0) })
        var attachedAny = false

        for meetingId in selectedIds {
            guard let meeting = meetingsById[meetingId] else { continue }
            let transcript = meeting.audioTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                if let state = context.meetingFile(for: meetingId), state.isAttached {
                    do {
                        try await openAIService.detachFileFromVectorStore(fileId: state.fileId, vectorStoreId: vectorStoreId)
                        state.isAttached = false
                    } catch {
                        print("Error detaching empty transcript file: \(error)")
                    }
                }
                context.markDetached(meetingId: meetingId)
                do {
                    try modelContext.save()
                } catch {
                    print("Error saving detached state: \(error)")
                }
                continue
            }

            let didAttach = try await syncMeetingFile(
                meeting: meeting,
                transcript: transcript,
                context: context,
                vectorStoreId: vectorStoreId
            )
            attachedAny = attachedAny || didAttach
        }

        let statesToDetach = context.meetingFiles.filter { $0.isAttached && !selectedIds.contains($0.meetingId) }

        for state in statesToDetach {
            do {
                try await openAIService.detachFileFromVectorStore(fileId: state.fileId, vectorStoreId: vectorStoreId)
                state.isAttached = false
                state.updatedAt = Date()
                context.updatedAt = Date()
                if meetingsById[state.meetingId] == nil {
                    context.removeMeetingFile(meetingId: state.meetingId)
                    modelContext.delete(state)
                }
                do {
                    try modelContext.save()
                } catch {
                    print("Error saving detached state: \(error)")
                }
            } catch {
                print("Error detaching file from vector store: \(error)")
            }
        }

        return attachedAny
    }

    @MainActor
    private func syncMeetingFile(
        meeting: Meeting,
        transcript: String,
        context: UserAIContext,
        vectorStoreId: String
    ) async throws -> Bool {
        let state = context.meetingFile(for: meeting.id)
        let fileName = "meeting-\(meeting.id.uuidString).txt"

        if let state {
            let needsReupload: Bool = {
                if let expiresAt = state.expiresAt {
                    return expiresAt <= Date()
                }
                return false
            }()

            if needsReupload {
                do {
                    try await openAIService.detachFileFromVectorStore(fileId: state.fileId, vectorStoreId: vectorStoreId)
                } catch {
                    print("Error detaching expired file: \(error)")
                }

                let upload = try await openAIService.uploadTranscriptFile(transcript: transcript, fileName: fileName)
                try await openAIService.attachFileToVectorStore(fileId: upload.id, vectorStoreId: vectorStoreId)

                state.fileId = upload.id
                state.expiresAt = upload.expiresAt
                state.isAttached = true
                state.updatedAt = Date()
                context.updatedAt = Date()
                do {
                    try modelContext.save()
                } catch {
                    print("Error saving meeting file state: \(error)")
                }
                return true
            }

            if !state.isAttached {
                try await openAIService.attachFileToVectorStore(fileId: state.fileId, vectorStoreId: vectorStoreId)
                state.isAttached = true
                state.updatedAt = Date()
                context.updatedAt = Date()
                do {
                    try modelContext.save()
                } catch {
                    print("Error saving meeting file state: \(error)")
                }
            }
            return true
        } else {
            let upload = try await openAIService.uploadTranscriptFile(transcript: transcript, fileName: fileName)
            try await openAIService.attachFileToVectorStore(fileId: upload.id, vectorStoreId: vectorStoreId)

            let newState = MeetingFileState(
                meetingId: meeting.id,
                fileId: upload.id,
                expiresAt: upload.expiresAt,
                isAttached: true,
                context: context
            )
            context.upsertMeetingFile(newState)
            context.updatedAt = Date()
            do {
                try modelContext.save()
            } catch {
                print("Error saving new meeting file state: \(error)")
            }
            return true
        }
    }

    @MainActor
    private func ensureUserAIContext(for userId: UUID) throws -> UserAIContext {
        let descriptor = FetchDescriptor<UserAIContext>(predicate: #Predicate { $0.userId == userId })
        let contexts = try modelContext.fetch(descriptor)
        if let existing = contexts.first {
            return existing
        }
        let newContext = UserAIContext(userId: userId)
        modelContext.insert(newContext)
        try modelContext.save()
        return newContext
    }

    @MainActor
    private func effectiveMeetingSelection(allMeetingIds: Set<UUID>) -> Set<UUID> {
        if selectedMeetings.isEmpty {
            return allMeetingIds
        }
        let filtered = selectedMeetings.intersection(allMeetingIds)
        return filtered.isEmpty ? allMeetingIds : filtered
    }

    @MainActor
    private func handleVectorStoreFailure(_ error: Error) {
        print("Vector store operation failed: \(error)")
        if case OpenAIError.vectorStoreUnavailable(let message) = error {
            contextWarning = "Eve can't access meeting transcripts right now (\(message)). I'll use summaries until connection recovers."
        } else {
            contextWarning = "Eve is temporarily using summaries only until meeting transcripts are available."
        }
        vectorStoreId = nil
    }

}
