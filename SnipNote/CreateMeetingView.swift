//
//  CreateMeetingView.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 26/06/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import StoreKit

#if canImport(AVFAudio)
import AVFAudio
#endif

struct CreateMeetingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var localizationManager: LocalizationManager
    
    var onMeetingCreated: ((Meeting) -> Void)?
    var importedAudioURL: URL? // For shared audio files
    
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var openAIService = OpenAIService.shared
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var minutesManager = MinutesManager.shared
    @StateObject private var backgroundTaskManager = BackgroundTaskManager.shared
    @Query private var allMeetings: [Meeting]
    
    @State private var meetingName = ""
    @State private var meetingLocation = ""
    @State private var meetingNotes = ""
    @State private var meetingDate = Date()
    @State private var isRecording = false
    @State private var currentRecordingURL: URL?
    @State private var createdMeeting: Meeting?
    @State private var createdMeetingId: UUID?
    @State private var showingAPIKeyAlert = false
    @State private var apiKeyInput = ""
    @State private var recordingStartTime: Date?
    @State private var hasFinishedRecording = false
    
    // Timer for recording duration display
    @State private var recordingTimer: Timer?
    @State private var recordingDuration: TimeInterval = 0

    // Processing state
    @State private var isProcessingAudio = false

    // Processing phases
    enum ProcessingPhase {
        case transcribing
        case generatingOverview
        case generatingSummary
        case extractingActions
        case complete
    }
    @State private var currentProcessingPhase: ProcessingPhase = .transcribing

    // Transcription progress tracking
    @State private var transcriptionProgress: Double = 0.0
    @State private var currentChunk: Int = 0
    @State private var totalChunks: Int = 0
    @State private var processingStage: String = ""
    @State private var partialTranscripts: [String] = []

    // AI-generated content as it's being created
    @State private var liveOverview: String = ""
    @State private var liveSummary: String = ""

    // Cached audio duration to prevent repeated calculations
    @State private var cachedAudioDuration: TimeInterval = 0

    // Minutes management
    @State private var showingInsufficientMinutesAlert = false
    @State private var showingMinutesPaywall = false
    @State private var estimatedMinutesNeeded = 0

    // Countdown state
    @State private var showingCountdown = false
    @State private var countdownValue = 3
    @State private var countdownTimer: Timer?
    
    // Paywall state
    @State private var showingPaywall = false

    // Background task tracking
    @State private var currentBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // Cancellation state
    @State private var showingCancelConfirmation = false

    // Server transcription service
    @StateObject private var transcriptionService = RenderTranscriptionService()

    private enum FocusedField: Hashable {
        case name
        case location
        case notes
    }

    // Focus state for meeting detail inputs
    @FocusState private var focusedField: FocusedField?
    @State private var meetingNameTouched = false
    @State private var showingDatePicker = false
    @State private var pendingMeetingDate = Date()
    @State private var isLocationExpanded = false
    @State private var isNotesExpanded = false

    // Recording animation state
    @State private var recordingDotScale: CGFloat = 1.0

    private enum MicrophonePermissionStatus: Equatable {
        case granted
        case denied
        case undetermined

        static func current() -> MicrophonePermissionStatus {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        }
    }

    // Microphone permission state
    @State private var microphonePermissionStatus: MicrophonePermissionStatus = MicrophonePermissionStatus.current()
    @State private var showingMicPermissionHelp = false

    // Meeting name validation
    @State private var showingNameRequiredAlert = false
    
    // Computed properties for imported audio mode
    private var hasImportedAudio: Bool {
        return importedAudioURL != nil
    }
    
    private func calculateAudioDuration() {
        guard let url = importedAudioURL else {
            print("❌ No imported audio URL")
            cachedAudioDuration = 0
            return
        }
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            print("🎵 Audio duration calculated: \(duration) seconds")
            cachedAudioDuration = duration
        } catch {
            print("❌ Failed to read audio file: \(error)")
            cachedAudioDuration = 0
        }
    }

    private var meetingNameTrimmed: String {
        meetingName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var meetingNameValidationMessage: String? {
        guard meetingNameTouched else { return nil }
        return meetingNameTrimmed.isEmpty ? "Meeting name is required." : nil
    }

    private var meetingNameHelperText: String {
        meetingNameTrimmed.isEmpty ? "Give this meeting a descriptive title." : "Clear names help Eve keep meetings organized."
    }

    private var meetingNotesHelperText: String {
        meetingNotes.isEmpty ? "Optional — capture agenda, attendees, or goals." : "\(meetingNotes.count) characters captured so far."
    }

    private var meetingLocationTrimmed: String {
        meetingLocation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var meetingNotesTrimmed: String {
        meetingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var meetingDateFormatted: String {
        CreateMeetingView.headerDateFormatter.string(from: meetingDate)
    }

    private var meetingLocationSummary: String {
        let trimmed = meetingLocationTrimmed
        return trimmed.isEmpty ? "Optional — include room, link, or dial-in." : trimmed
    }

    private var meetingNotesSummary: String {
        let trimmed = meetingNotesTrimmed
        guard !trimmed.isEmpty else {
            return "Optional — capture agenda, attendees, or goals."
        }

        let maxLength = 90
        if trimmed.count > maxLength {
            let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
            return String(trimmed[..<index]) + "…"
        }
        return trimmed
    }

    private func localized(_ key: String) -> String {
        localizationManager.localizedString(key)
    }

    @ViewBuilder
    private func headerView() -> some View {
        let theme = themeManager.currentTheme

        let localizedNewMeeting = localized("New Meeting")
        let defaultTitle = theme.headerStyle == .brackets ? "[ \(localizedNewMeeting.uppercased()) ]" : localizedNewMeeting
        let headerTitle = meetingNameTrimmed.isEmpty ? defaultTitle : meetingNameTrimmed

        HStack(alignment: .center, spacing: 12) {
            Text(headerTitle)
                .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(theme.textColor)

            Button {
                pendingMeetingDate = meetingDate
                showingDatePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(meetingDateFormatted)
                }
                .font(.system(.footnote, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                .foregroundColor(theme.accentColor)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(theme.secondaryBackgroundColor.opacity(theme.colorScheme == .dark ? 0.55 : 0.2))
                )
                .overlay(
                    Capsule()
                        .stroke(theme.accentColor.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select meeting date")

            Spacer()

            Image(systemName: "sparkles")
                .foregroundColor(theme.accentColor)
                .font(.system(.title3, weight: .semibold))
                .opacity(0.85)
        }
        .padding()
        .background(headerBackgroundGradient(for: theme))
        .overlay(headerBottomDivider(for: theme), alignment: .bottom)
    }

    private func headerBackgroundGradient(for theme: AppTheme) -> LinearGradient {
        LinearGradient(
            colors: [
                theme.secondaryBackgroundColor.opacity(0.9),
                theme.backgroundColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func headerBottomDivider(for theme: AppTheme) -> some View {
        Rectangle()
            .fill(theme.secondaryTextColor.opacity(0.1))
            .frame(height: 1)
    }

    @ViewBuilder
    private func meetingDetailsSection() -> some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 16) {
                MeetingInputCard(title: "Meeting Name",
                                  helper: meetingNameValidationMessage == nil ? meetingNameHelperText : nil,
                                  error: meetingNameValidationMessage,
                                  iconSystemName: "textformat") {
                    TextField("Enter meeting name", text: $meetingName)
                        .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .location
                        }
                        .onChange(of: meetingName) { _, _ in
                            meetingNameTouched = true
                        }
                }
                .id(FocusedField.name)

                optionalLocationInput(theme: theme)
                optionalNotesInput(theme: theme)
            }
        }
        .padding(.horizontal)
        .padding(.top, 1)
    }

    @ViewBuilder
    private func optionalLocationInput(theme: AppTheme) -> some View {
        if isLocationExpanded {
            expandedLocationCard(theme: theme)
                .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            optionalCollapsedCard(
                theme: theme,
                title: theme.headerStyle == .brackets ? "ADD LOCATION" : "Add Location",
                subtitle: "Optional — include room, link, or dial-in.",
                iconSystemName: "mappin.and.ellipse",
                summary: meetingLocationTrimmed.isEmpty ? nil : meetingLocationSummary
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLocationExpanded = true
                    focusedField = .location
                }
            }
        }
    }

    @ViewBuilder
    private func optionalNotesInput(theme: AppTheme) -> some View {
        if isNotesExpanded {
            expandedNotesCard(theme: theme)
                .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            optionalCollapsedCard(
                theme: theme,
                title: theme.headerStyle == .brackets ? "ADD NOTES" : "Add Notes",
                subtitle: "Optional — capture agenda, attendees, or goals.",
                iconSystemName: "note.text",
                summary: meetingNotesTrimmed.isEmpty ? nil : meetingNotesSummary
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isNotesExpanded = true
                    focusedField = .notes
                }
            }
        }
    }

    private func expandedLocationCard(theme: AppTheme) -> some View {
        MeetingInputCard(title: "Location",
                         helper: meetingLocationTrimmed.isEmpty ? "Optional — include room, link, or dial-in." : nil,
                         iconSystemName: "mappin.and.ellipse") {
            TextField("Enter meeting location", text: $meetingLocation)
                .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .location)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .notes
                }
        }
        .id(FocusedField.location)
        .overlay(alignment: .topTrailing) {
            collapseSectionButton(theme: theme, accessibilityLabel: "Hide location") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLocationExpanded = false
                    if focusedField == .location {
                        focusedField = nil
                    }
                }
            }
        }
    }

    private func expandedNotesCard(theme: AppTheme) -> some View {
        MeetingInputCard(title: "Notes",
                         helper: meetingNotesHelperText,
                         iconSystemName: "note.text",
                         contentPadding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
            ZStack(alignment: .topLeading) {
                if meetingNotesTrimmed.isEmpty {
                    Text("Jot down talking points, decisions to make, or context for Eve.")
                        .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(theme.secondaryTextColor.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $meetingNotes)
                    .focused($focusedField, equals: .notes)
                    .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default))
                    .frame(minHeight: 140)
            }
        }
        .id(FocusedField.notes)
        .overlay(alignment: .topTrailing) {
            collapseSectionButton(theme: theme, accessibilityLabel: "Hide notes") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isNotesExpanded = false
                    if focusedField == .notes {
                        focusedField = nil
                    }
                }
            }
        }
    }

    private func collapseSectionButton(theme: AppTheme, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.up.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.secondaryTextColor)
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel(accessibilityLabel)
    }

    private func optionalCollapsedCard(theme: AppTheme,
                                       title: String,
                                       subtitle: String,
                                       iconSystemName: String,
                                       summary: String?,
                                       action: @escaping () -> Void) -> some View {
        let displayTitle = theme.headerStyle == .brackets ? title.uppercased() : title
        let detailText = summary?.isEmpty == false ? (summary ?? subtitle) : subtitle

        return Button(action: action) {
        HStack(alignment: .center, spacing: 9) {
                Image(systemName: iconSystemName)
                    .font(.system(.title3, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle)
                        .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(theme.secondaryTextColor)

                    Text(detailText)
                        .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(theme.secondaryTextColor.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(theme.accentColor)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius + 6)
                .fill(theme.secondaryBackgroundColor.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius + 6)
                .stroke(theme.accentColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(theme.colorScheme == .dark ? 0.4 : 0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private func meetingDatePickerSheet() -> some View {
        let theme = themeManager.currentTheme

        NavigationView {
            VStack(spacing: 0) {
                DatePicker(
                    "Meeting Date",
                    selection: $pendingMeetingDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(theme.accentColor)
                .padding()

                Spacer()
            }
            .background(theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Meeting Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        pendingMeetingDate = meetingDate
                        showingDatePicker = false
                    }
                    .foregroundColor(theme.secondaryTextColor)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        meetingDate = pendingMeetingDate
                        showingDatePicker = false
                    }
                    .foregroundColor(theme.accentColor)
                }
            }
        }
        .themed()
        .onDisappear {
            pendingMeetingDate = meetingDate
        }
    }

    @ViewBuilder
    private func microphonePermissionSection() -> some View {
        let theme = themeManager.currentTheme

        if !isPermissionGranted(microphonePermissionStatus) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "mic.slash.fill")
                        .foregroundColor(isPermissionDenied(microphonePermissionStatus) ? theme.destructiveColor : theme.warningColor)
                        .font(.system(size: 16))

                    Text(isPermissionDenied(microphonePermissionStatus) ?
                         (theme.headerStyle == .brackets ? "MICROPHONE ACCESS DENIED" : "Microphone Access Denied") :
                         (theme.headerStyle == .brackets ? "MICROPHONE PERMISSION NEEDED" : "Microphone Permission Needed"))
                        .font(.system(.headline, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(isPermissionDenied(microphonePermissionStatus) ? theme.destructiveColor : theme.warningColor)

                    Spacer()

                    Button(action: {
                        showingMicPermissionHelp.toggle()
                    }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(theme.accentColor)
                            .font(.system(size: 16))
                    }
                }

                Text(isPermissionDenied(microphonePermissionStatus) ?
                     "Recording requires microphone access. Please enable it in Settings > Privacy & Security > Microphone > SnipNote." :
                     "To record meetings, SnipNote needs access to your microphone. Tap the record button and grant permission when prompted.")
                    .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(theme.secondaryTextColor)

                if showingMicPermissionHelp {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(theme.headerStyle == .brackets ? "TROUBLESHOOTING:" : "Troubleshooting:")
                            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(theme.accentColor)

                        Text("1. Go to iOS Settings\n2. Find Privacy & Security\n3. Tap Microphone\n4. Enable SnipNote\n5. Return to the app")
                            .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(theme.secondaryTextColor)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .background(isPermissionDenied(microphonePermissionStatus) ? theme.destructiveColor.opacity(0.1) : theme.warningColor.opacity(0.1))
            .cornerRadius(theme.cornerRadius)
            .animation(.easeInOut(duration: 0.3), value: showingMicPermissionHelp)
        }
    }

    @ViewBuilder
    private func progressStepsSection() -> some View {
        let theme = themeManager.currentTheme

        HStack(spacing: 8) {
            // Step 1: Record
            HStack(spacing: 4) {
                Circle()
                    .fill(audioRecorder.isRecording || hasFinishedRecording ? theme.accentColor : theme.secondaryTextColor.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(theme.headerStyle == .brackets ? "RECORD" : "Record")
                    .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                    .foregroundColor(audioRecorder.isRecording || hasFinishedRecording ? theme.accentColor : theme.secondaryTextColor)
            }

            Rectangle()
                .fill(hasFinishedRecording || isProcessingAudio ? theme.accentColor : theme.secondaryTextColor.opacity(0.3))
                .frame(width: 20, height: 2)

            // Step 2: Process
            HStack(spacing: 4) {
                Circle()
                    .fill(hasFinishedRecording || isProcessingAudio ? theme.accentColor : theme.secondaryTextColor.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(theme.headerStyle == .brackets ? "PROCESS" : "Process")
                    .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                    .foregroundColor(hasFinishedRecording || isProcessingAudio ? theme.accentColor : theme.secondaryTextColor)
            }

            Rectangle()
                .fill(theme.secondaryTextColor.opacity(0.3))
                .frame(width: 20, height: 2)

            // Step 3: Review
            HStack(spacing: 4) {
                Circle()
                    .fill(theme.secondaryTextColor.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(theme.headerStyle == .brackets ? "REVIEW" : "Review")
                    .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                    .foregroundColor(theme.secondaryTextColor)
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func recordingSection() -> some View {
        let theme = themeManager.currentTheme

        VStack(spacing: 20) {
            if isProcessingAudio && currentProcessingPhase == .transcribing {
                processingCard(theme: theme)
            } else if isProcessingAudio && (currentProcessingPhase == .generatingOverview || currentProcessingPhase == .generatingSummary || currentProcessingPhase == .extractingActions) {
                meetingResultsCard(theme: theme)
            } else if hasImportedAudio {
                importedAudioCard(theme: theme)
            } else if audioRecorder.isRecording {
                activeRecordingCard(theme: theme)
            } else if hasFinishedRecording {
                processingCard(theme: theme)
            } else if showingCountdown {
                countdownCard(theme: theme)
            } else {
                idleRecordingCard(theme: theme)
            }
        }
        .padding(.top, 17)
    }

    private func formBackgroundGradient() -> LinearGradient {
        let theme = themeManager.currentTheme
        return LinearGradient(
            colors: [
                theme.secondaryBackgroundColor.opacity(0.15),
                theme.backgroundColor
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func importedAudioCard(theme: AppTheme) -> some View {
        VStack(spacing: 20) {
            Text(theme.headerStyle == .brackets ? "IMPORTED AUDIO READY" : "Imported Audio Ready")
                .font(.system(.title, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(theme.accentColor)

            Text("Duration: \(formatDuration(cachedAudioDuration))")
                .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(theme.accentColor)

            let requiredMinutes = max(1, Int(ceil(cachedAudioDuration / 60.0)))
            // Only show minutes warning for short audio (≤5min) that will use on-device processing
            if cachedAudioDuration <= 300 && minutesManager.currentBalance < requiredMinutes {
                Text("This audio requires \(requiredMinutes) minutes. You have \(minutesManager.currentBalance) minutes remaining.")
                    .font(.system(.callout, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.warningColor)
                    .multilineTextAlignment(.center)
            }

            Rectangle()
                .fill(theme.accentColor)
                .frame(width: 200, height: 4)
                .opacity(0.7)

            Button(theme.headerStyle == .brackets ? "ANALYZE MEETING" : "Analyze Meeting") {
                analyzeImportedAudio()
            }
            .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
            .foregroundColor(theme.backgroundColor)
            .padding()
            .background(theme.accentColor)
            .cornerRadius(theme.cornerRadius)
            .disabled(meetingNameTrimmed.isEmpty)
        }
    }

    @ViewBuilder
    private func activeRecordingCard(theme: AppTheme) -> some View {
        VStack(spacing: 9) {
            HStack {
                if !audioRecorder.isPaused {
                    Circle()
                        .fill(theme.destructiveColor)
                        .frame(width: 12, height: 12)
                        .scaleEffect(recordingDotScale)
                        .opacity(0.9)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                recordingDotScale = 1.4
                            }
                        }
                        .onDisappear {
                            recordingDotScale = 1.0
                        }
                }

                Text(theme.headerStyle == .brackets ? (audioRecorder.isPaused ? "MEETING PAUSED" : "RECORDING MEETING...") : (audioRecorder.isPaused ? "Meeting Paused" : "Recording Meeting..."))
                    .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(audioRecorder.isPaused ? theme.warningColor : theme.destructiveColor)
            }

            Text(formatDuration(recordingDuration))
                .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(audioRecorder.isPaused ? theme.warningColor : theme.destructiveColor)

            WaveformView(
                level: audioRecorder.isPaused ? 0.3 : audioRecorder.recordingLevel,
                isRecording: !audioRecorder.isPaused,
                accentColor: audioRecorder.isPaused ? theme.warningColor : theme.destructiveColor
            )
            .frame(height: 60)

            let requiredMinutes = max(1, Int(ceil(recordingDuration / 60.0)))
            if recordingDuration > 0 && minutesManager.currentBalance < requiredMinutes {
                Text("This recording will require \(requiredMinutes) minutes. You have \(minutesManager.currentBalance) minutes remaining.")
                    .font(.system(.callout, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.warningColor)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            VStack(spacing: 8) {
                Button(theme.headerStyle == .brackets ? "STOP MEETING" : "Stop Meeting") {
                    stopMeetingRecording()
                }
                .font(.system(.callout, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                .foregroundColor(theme.backgroundColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.destructiveColor)
                .cornerRadius(theme.cornerRadius)

                HStack(spacing: 12) {
                    Button(audioRecorder.isPaused ? (theme.headerStyle == .brackets ? "RESUME" : "Resume") : (theme.headerStyle == .brackets ? "PAUSE" : "Pause")) {
                        if audioRecorder.isPaused {
                            resumeMeetingRecording()
                        } else {
                            pauseMeetingRecording()
                        }
                    }
                    .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(theme.secondaryTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.secondaryTextColor.opacity(0.2))
                    .cornerRadius(theme.cornerRadius)

                    Button(role: .destructive) {
                        cancelMeetingRecording()
                    } label: {
                        Text(theme.headerStyle == .brackets ? "CANCEL" : "Cancel")
                            .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(theme.secondaryTextColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(theme.secondaryTextColor.opacity(0.2))
                            .cornerRadius(theme.cornerRadius)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func processingCard(theme: AppTheme) -> some View {
        VStack(spacing: 20) {
            // Main title
            Text(theme.headerStyle == .brackets ? "PROCESSING MEETING..." : "Processing meeting...")
                .font(.system(.title, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(theme.warningColor)

            // Progress percentage and stage
            VStack(spacing: 8) {
                Text("\(Int(transcriptionProgress))% Complete")
                    .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                    .foregroundColor(theme.accentColor)

                // Progress bar
                ProgressView(value: transcriptionProgress, total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: theme.accentColor))
                    .frame(height: 8)
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)

                // Current stage description
                if !processingStage.isEmpty {
                    Text(processingStage)
                        .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                        .foregroundColor(theme.secondaryTextColor)
                        .multilineTextAlignment(.center)
                }

                // Chunk progress (only show if we have chunks)
                if totalChunks > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundColor(theme.accentColor)
                        Text("Chunk \(currentChunk) of \(totalChunks)")
                            .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                            .foregroundColor(theme.secondaryTextColor)
                    }
                }
            }

            // Live transcript preview (show last few chunks)
            if !partialTranscripts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "text.bubble")
                            .font(.caption)
                            .foregroundColor(theme.accentColor)
                        Text(theme.headerStyle == .brackets ? "PREVIEW:" : "Preview:")
                            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(theme.accentColor)
                        Spacer()
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        Text(partialTranscripts.suffix(3).joined(separator: " "))
                            .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(theme.secondaryTextColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(4)
                    }
                    .frame(maxHeight: 60)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: theme.cornerRadius)
                            .fill(theme.secondaryBackgroundColor.opacity(0.3))
                    )
                }
            }

            // Fallback spinner for when no detailed progress is available
            if transcriptionProgress == 0 && totalChunks == 0 {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func meetingResultsCard(theme: AppTheme) -> some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text(theme.headerStyle == .brackets ? "GENERATING MEETING INSIGHTS..." : "Generating meeting insights...")
                    .font(.system(.title2, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(theme.accentColor)

                // Current phase indicator
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(phaseDescription(for: currentProcessingPhase))
                        .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .medium))
                        .foregroundColor(theme.secondaryTextColor)
                }
            }

            Divider()
                .background(theme.secondaryTextColor.opacity(0.3))

            // Live content display
            VStack(alignment: .leading, spacing: 16) {
                // Overview section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "eye")
                            .font(.caption)
                            .foregroundColor(theme.accentColor)
                        Text(theme.headerStyle == .brackets ? "OVERVIEW:" : "Overview:")
                            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(theme.accentColor)
                        Spacer()
                        if currentProcessingPhase == .generatingOverview {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else if !liveOverview.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    Text(liveOverview.isEmpty ? "Analyzing meeting content..." : liveOverview)
                        .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default))
                        .foregroundColor(liveOverview.isEmpty ? theme.secondaryTextColor.opacity(0.6) : theme.secondaryTextColor)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: theme.cornerRadius)
                                .fill(theme.secondaryBackgroundColor.opacity(0.3))
                        )
                }

                // Summary section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundColor(theme.accentColor)
                        Text(theme.headerStyle == .brackets ? "SUMMARY:" : "Summary:")
                            .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                            .foregroundColor(theme.accentColor)
                        Spacer()
                        if currentProcessingPhase == .generatingSummary {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else if !liveSummary.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        Text(liveSummary.isEmpty ? "Generating detailed summary..." : liveSummary)
                            .font(.system(.caption2, design: theme.useMonospacedFont ? .monospaced : .default))
                            .foregroundColor(liveSummary.isEmpty ? theme.secondaryTextColor.opacity(0.6) : theme.secondaryTextColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: theme.cornerRadius)
                            .fill(theme.secondaryBackgroundColor.opacity(0.3))
                    )
                }

                // Actions section
                HStack {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                        .foregroundColor(theme.accentColor)
                    Text(theme.headerStyle == .brackets ? "EXTRACTING ACTIONS..." : "Extracting actions...")
                        .font(.system(.caption, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                        .foregroundColor(theme.accentColor)
                    Spacer()
                    if currentProcessingPhase == .extractingActions {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if currentProcessingPhase == .complete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func phaseDescription(for phase: ProcessingPhase) -> String {
        let theme = themeManager.currentTheme
        switch phase {
        case .transcribing:
            return theme.headerStyle == .brackets ? "TRANSCRIBING AUDIO..." : "Transcribing audio..."
        case .generatingOverview:
            return theme.headerStyle == .brackets ? "GENERATING OVERVIEW..." : "Generating overview..."
        case .generatingSummary:
            return theme.headerStyle == .brackets ? "CREATING SUMMARY..." : "Creating summary..."
        case .extractingActions:
            return theme.headerStyle == .brackets ? "EXTRACTING ACTIONS..." : "Extracting actions..."
        case .complete:
            return theme.headerStyle == .brackets ? "COMPLETE!" : "Complete!"
        }
    }

    @ViewBuilder
    private func countdownCard(theme: AppTheme) -> some View {
        VStack(spacing: 20) {
            Text(theme.headerStyle == .brackets ? "STARTING IN..." : "Starting in...")
                .font(.system(.title, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(theme.warningColor)

            Text("\(countdownValue)")
                .font(.system(.largeTitle, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                .foregroundColor(theme.accentColor)
                .scaleEffect(countdownValue > 0 ? 1.5 : 0.8)
                .animation(.easeOut(duration: 0.3), value: countdownValue)

            Button(theme.headerStyle == .brackets ? "CANCEL" : "Cancel") {
                cancelCountdown()
            }
            .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
            .foregroundColor(theme.destructiveColor)
            .padding()
            .background(theme.destructiveColor.opacity(0.2))
            .cornerRadius(theme.cornerRadius)
        }
    }

    @ViewBuilder
    private func idleRecordingCard(theme: AppTheme) -> some View {
        VStack(spacing: 16) {
            Button(theme.headerStyle == .brackets ? "START MEETING RECORDING" : "Start Meeting Recording") {
                startCountdown()
            }
            .font(.system(.body, design: theme.useMonospacedFont ? .monospaced : .default, weight: .bold))
            .foregroundColor(theme.backgroundColor)
            .padding()
            .background(meetingNameTrimmed.isEmpty ? theme.secondaryTextColor.opacity(0.6) : theme.accentColor)
            .cornerRadius(theme.cornerRadius)
            .disabled(meetingNameTrimmed.isEmpty)
            .opacity(meetingNameTrimmed.isEmpty ? 0.7 : 1.0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        // Only show meeting details section if not processing
                        if !isProcessingAudio {
                            meetingDetailsSection()
                        }
                        microphonePermissionSection()
                        progressStepsSection()
                        recordingSection()
                    }
                    .padding()
                }
                .background(formBackgroundGradient())
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }

            Spacer()
        }
        .themedBackground()
        .foregroundColor(themeManager.currentTheme.accentColor)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            // Cancel button in navigation bar (only shown during processing)
            if isProcessingAudio {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCancelConfirmation = true
                    } label: {
                        Text("Cancel")
                            .foregroundColor(themeManager.currentTheme.destructiveColor)
                    }
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button {
                    focusedField = nil
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Dismiss Keyboard")
            }
        }
        .alert("API Key Required", isPresented: $showingAPIKeyAlert) {
            TextField("OpenAI API Key", text: $apiKeyInput)
            Button("Save") {
                openAIService.apiKey = apiKeyInput
                apiKeyInput = ""
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Enter your OpenAI API key to enable transcription and summarization.")
        }
        .sheet(isPresented: $showingDatePicker) {
            meetingDatePickerSheet()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingMinutesPaywall) {
            MinutesPackPaywallView(onPurchaseComplete: {
                Task { await minutesManager.refreshBalance() }
            })
        }
        .alert("Insufficient Minutes", isPresented: $showingInsufficientMinutesAlert) {
            Button("Buy Minutes") {
                showingMinutesPaywall = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if estimatedMinutesNeeded > 0 {
                Text("This requires \(estimatedMinutesNeeded) minutes, but you only have \(minutesManager.currentBalance) minutes remaining.")
            } else {
                Text("You don't have enough minutes to start recording. Purchase minute packs to continue.")
            }
        }
        .alert("Meeting Name Required", isPresented: $showingNameRequiredAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter the name of the meeting")
        }
        .alert("Cancel Transcription?", isPresented: $showingCancelConfirmation) {
            Button("Cancel Transcription", role: .destructive) {
                cancelTranscription()
            }
            Button("Continue", role: .cancel) {}
        } message: {
            Text("Are you sure you want to cancel? All progress will be lost.")
        }
        .onAppear {
            print("🎵 CreateMeetingView appeared with importedAudioURL: \(importedAudioURL?.absoluteString ?? "nil")")
            print("🎵 hasImportedAudio: \(hasImportedAudio)")

            // Refresh minutes balance
            Task { await minutesManager.refreshBalance() }

            // Check microphone permission (iOS 17+ compatible)
            microphonePermissionStatus = getCurrentPermissionStatus()

            if let url = importedAudioURL {
                print("🎵 File exists: \(FileManager.default.fileExists(atPath: url.path))")

                // Calculate audio duration once
                calculateAudioDuration()

                // Use filename as default meeting name if it's empty
                if meetingName.isEmpty {
                    let fileName = url.lastPathComponent
                    // Remove file extension and clean up the name
                    let nameWithoutExtension = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
                    meetingName = nameWithoutExtension
                    print("🎵 Set default meeting name: \(meetingName)")
                }
            }

            isLocationExpanded = !meetingLocationTrimmed.isEmpty
            isNotesExpanded = !meetingNotesTrimmed.isEmpty
        }
    }
    
    private func startMeetingRecording() {
        guard openAIService.apiKey != nil else {
            showingAPIKeyAlert = true
            return
        }
        
        guard !meetingNameTrimmed.isEmpty else {
            return
        }

        // Check if user has sufficient minutes (estimate 1 minute minimum)
        if minutesManager.currentBalance <= 0 {
            showingInsufficientMinutesAlert = true
            return
        }

        recordingStartTime = Date()
        recordingDuration = 0
        currentRecordingURL = audioRecorder.startRecording()
        
        // Start timer for duration display
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let startTime = recordingStartTime {
                recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func pauseMeetingRecording() {
        audioRecorder.pauseRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    private func resumeMeetingRecording() {
        audioRecorder.resumeRecording()
        
        // Restart timer for duration display
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let startTime = recordingStartTime {
                recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func cancelMeetingRecording() {
        audioRecorder.cancelRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Reset state and dismiss
        recordingStartTime = nil
        recordingDuration = 0
        hasFinishedRecording = false
        
        dismiss()
    }
    
    private func analyzeImportedAudio() {
        guard let audioURL = importedAudioURL else {
            print("❌ No audio URL to analyze")
            return
        }

        // Auto-select transcription method based on audio duration
        let durationMinutes = Int(cachedAudioDuration / 60)
        let durationSeconds = Int(cachedAudioDuration)

        if cachedAudioDuration <= 300 {
            // 5 minutes or less: use on-device for speed
            print("📱 Auto-selected on-device transcription (duration: \(durationMinutes)m \(durationSeconds % 60)s)")
            processOnDevice(audioURL: audioURL)
        } else {
            // More than 5 minutes: use server-side for reliability
            print("☁️ Auto-selected server-side transcription (duration: \(durationMinutes)m \(durationSeconds % 60)s)")
            processServerSide(audioURL: audioURL)
        }
    }

    // MARK: - On-Device Transcription

    private func processOnDevice(audioURL: URL) {
        // Check if user has sufficient minutes for imported audio
        let requiredMinutes = max(1, Int(ceil(cachedAudioDuration / 60.0)))
        if minutesManager.currentBalance < requiredMinutes {
            estimatedMinutesNeeded = requiredMinutes
            showingInsufficientMinutesAlert = true
            return
        }

        print("🎵 Starting on-device analysis: \(audioURL)")
        isProcessingAudio = true
        currentProcessingPhase = .transcribing

        // Reset progress state
        transcriptionProgress = 0.0
        currentChunk = 0
        totalChunks = 0
        processingStage = "Starting transcription..."
        partialTranscripts.removeAll()

        // Reset live content
        liveOverview = ""
        liveSummary = ""

        // Create meeting immediately with form data
        createProcessingMeeting()

        // FIXED: Start background task AFTER meeting is created (so meetingId is available)
        if let meetingId = createdMeetingId {
            currentBackgroundTaskId = backgroundTaskManager.startBackgroundTask(
                for: meetingId,
                meetingName: meetingName,
                currentChunk: currentChunk,
                totalChunks: totalChunks
            )
        }

        // Track meeting creation (without transcription yet)
        Task {
            let duration = Int(cachedAudioDuration)
            await UsageTracker.shared.trackMeetingCreated(transcribed: false, meetingSeconds: duration)
        }

        // DON'T navigate immediately - let user see the enhanced processing UI
        // Navigation will happen after processing completes
        
        Task {
            do {
                // Use the chunked transcription method
                let transcript = try await openAIService.transcribeAudioFromURL(
                    audioURL: audioURL,
                    progressCallback: { progress in
                        Task { @MainActor in
                            transcriptionProgress = progress.percentComplete
                            currentChunk = progress.currentChunk
                            totalChunks = progress.totalChunks
                            processingStage = progress.currentStage

                            // Add completed chunk transcript to our array
                            if let chunkTranscript = progress.partialTranscript {
                                partialTranscripts.append(chunkTranscript)
                            }

                            if let meeting = createdMeeting {
                                let hasProgressChanged =
                                    meeting.lastProcessedChunk != progress.currentChunk ||
                                    meeting.totalChunks != progress.totalChunks

                                if hasProgressChanged {
                                    meeting.updateChunkProgress(
                                        completed: progress.currentChunk,
                                        total: progress.totalChunks
                                    )

                                    do {
                                        try modelContext.save()
                                    } catch {
                                        print("Error saving chunk progress: \(error)")
                                    }
                                }
                            }
                        }
                    },
                    meetingName: meetingNameTrimmed.isEmpty ? "Untitled Meeting" : meetingNameTrimmed,
                    meetingId: createdMeetingId
                )
                
                // Debit minutes for transcription
                let duration = Int(cachedAudioDuration)
                if let meetingId = createdMeetingId {
                    _ = await minutesManager.debitMinutes(seconds: duration, meetingID: meetingId.uuidString)
                }

                // Track successful transcription
                await UsageTracker.shared.trackMeetingCreated(transcribed: true, meetingSeconds: duration)
                
                await MainActor.run {
                    updateMeetingWithTranscript(transcript: transcript)
                }
                
                // Upload imported audio to Supabase
                if let meeting = createdMeeting {
                    do {
                        _ = try await SupabaseManager.shared.uploadAudioRecording(
                            audioURL: audioURL,
                            meetingId: meeting.id,
                            duration: cachedAudioDuration
                        )
                        
                        // Update meeting to indicate it has a recording
                        await MainActor.run {
                            meeting.hasRecording = true
                        }
                    } catch {
                        print("Error uploading imported audio to Supabase: \(error)")
                    }
                }
                
                // Process AI analysis with live updates
                await MainActor.run {
                    currentProcessingPhase = .generatingOverview
                }

                let overview = try await openAIService.generateMeetingOverview(transcript)
                await MainActor.run {
                    liveOverview = overview
                    currentProcessingPhase = .generatingSummary
                }

                let summary = try await openAIService.summarizeMeeting(transcript)
                await MainActor.run {
                    liveSummary = summary
                    currentProcessingPhase = .extractingActions
                }

                let actionItems = try await openAIService.extractActions(transcript)
                await MainActor.run {
                    currentProcessingPhase = .complete
                }
                
                // Track AI usage
                await UsageTracker.shared.trackAIUsage(
                    summaries: 1,
                    actionsExtracted: actionItems.count
                )
                
                await MainActor.run {
                    updateMeetingWithAI(overview: overview, summary: summary, actionItems: actionItems)
                    isProcessingAudio = false
                    currentProcessingPhase = .transcribing

                    // Reset progress state
                    transcriptionProgress = 0.0
                    currentChunk = 0
                    totalChunks = 0
                    processingStage = ""
                    partialTranscripts.removeAll()

                    // Reset live content
                    liveOverview = ""
                    liveSummary = ""

                    // End background task on success
                    if currentBackgroundTaskId != .invalid {
                        backgroundTaskManager.endBackgroundTask(currentBackgroundTaskId)
                        currentBackgroundTaskId = .invalid
                    }

                    // NOW navigate after processing is complete
                    if let meeting = createdMeeting {
                        onMeetingCreated?(meeting)
                    }
                }
                
            } catch {
                await MainActor.run {
                    print("Error processing imported audio: \(error)")
                    isProcessingAudio = false
                    currentProcessingPhase = .transcribing

                    // Reset progress state
                    transcriptionProgress = 0.0
                    currentChunk = 0
                    totalChunks = 0
                    processingStage = ""
                    partialTranscripts.removeAll()

                    // Reset live content
                    liveOverview = ""
                    liveSummary = ""

                    // Cancel processing notification on error
                    if let meetingId = createdMeetingId {
                        NotificationService.shared.cancelProcessingNotification(for: meetingId)
                    }

                    // End background task on failure
                    if currentBackgroundTaskId != .invalid {
                        backgroundTaskManager.endBackgroundTask(currentBackgroundTaskId)
                        currentBackgroundTaskId = .invalid
                    }

                    // FIXED: Properly handle meeting error state
                    if let meeting = createdMeeting {
                        meeting.setProcessingError("Transcription failed. Please try again.")
                        meeting.audioTranscript = "Transcription failed"
                        meeting.shortSummary = "Processing failed"
                        meeting.aiSummary = "This meeting could not be processed. You can try again using the retry button."

                        // Save the audio file path for retry
                        if let audioURL = importedAudioURL {
                            meeting.localAudioPath = audioURL.path
                        }

                        do {
                            try modelContext.save()
                        } catch {
                            print("Error saving meeting after failure: \(error)")
                        }

                        onMeetingCreated?(meeting)
                    }
                }
            }
        }
    }

    // MARK: - Server-Side Transcription

    private func processServerSide(audioURL: URL) {
        print("☁️ Starting server-side transcription: \(audioURL)")

        // Create meeting immediately
        createProcessingMeeting()

        guard let meeting = createdMeeting, let meetingId = createdMeetingId else {
            print("❌ Failed to create meeting for server transcription")
            return
        }

        // Track meeting creation (without transcription yet)
        Task {
            let duration = Int(cachedAudioDuration)
            await UsageTracker.shared.trackMeetingCreated(transcribed: false, meetingSeconds: duration)
        }

        // Navigate to detail view immediately
        onMeetingCreated?(meeting)

        Task {
            do {
                // 1. Optimize audio before upload (1.5x speed-up + compression)
                var uploadURL = audioURL
                var uploadDuration = cachedAudioDuration

                do {
                    print("⚡ Optimizing audio for server upload...")
                    let optimizedURL = try await openAIService.optimizeAudioForUpload(audioURL: audioURL)
                    uploadURL = optimizedURL
                    uploadDuration = cachedAudioDuration / 1.5
                    print("✅ Audio optimization complete - new duration: \(Int(uploadDuration))s")
                } catch {
                    print("⚠️ Audio optimization failed, uploading original audio: \(error.localizedDescription)")
                    // Continue with original audio - uploadURL and uploadDuration already set
                }

                // 2. Upload audio to Supabase Storage
                print("📤 Uploading audio to Supabase...")
                let audioPath = try await SupabaseManager.shared.uploadAudioRecording(
                    audioURL: uploadURL,
                    meetingId: meetingId,
                    duration: uploadDuration
                )

                // Clean up optimized file after successful upload (if we created one)
                if uploadURL != audioURL {
                    try? FileManager.default.removeItem(at: uploadURL)
                    print("🗑️ Cleaned up optimized audio file")
                }

                await MainActor.run {
                    meeting.hasRecording = true
                    // Update meeting duration to reflect optimized audio
                    if uploadDuration != cachedAudioDuration {
                        meeting.duration = uploadDuration
                        print("📝 Updated meeting duration to optimized value: \(Int(uploadDuration))s")
                    }
                }

                print("✅ Audio uploaded: \(audioPath)")

                // 3. Get public URL for the audio and user ID
                guard let session = try? await SupabaseManager.shared.client.auth.session else {
                    throw NSError(domain: "CreateMeeting", code: -1, userInfo: [NSLocalizedDescriptionKey: "No auth session"])
                }

                let userId = session.user.id
                let publicAudioURL = "https://bndbnqtvicvynzkyygte.supabase.co/storage/v1/object/public/recordings/\(audioPath)"
                print("📍 Public audio URL: \(publicAudioURL)")

                // 4. Create transcription job
                print("🔨 Creating transcription job...")
                let jobResponse = try await transcriptionService.createJob(
                    userId: userId,
                    meetingId: meetingId,
                    audioURL: publicAudioURL
                )

                print("✅ Job created: \(jobResponse.jobId)")

                // 5. Save job ID to meeting
                await MainActor.run {
                    meeting.transcriptionJobId = jobResponse.jobId
                    do {
                        try modelContext.save()
                        print("💾 Saved job ID to meeting")
                    } catch {
                        print("❌ Error saving job ID: \(error)")
                    }
                }

                print("✅ Server transcription job initiated - polling will happen in MeetingDetailView")

                // Schedule processing notification
                await NotificationService.shared.scheduleProcessingNotification(
                    for: meetingId,
                    meetingName: meeting.name
                )

            } catch {
                await MainActor.run {
                    print("❌ Error in server-side transcription: \(error)")
                    meeting.setProcessingError("Failed to upload audio or create transcription job: \(error.localizedDescription)")
                    meeting.isProcessing = false

                    do {
                        try modelContext.save()
                    } catch {
                        print("❌ Error saving meeting after failure: \(error)")
                    }
                }
            }
        }
    }

    private func stopMeetingRecording() {
        guard let recordingURL = audioRecorder.stopRecording() else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil

        // Check if user has sufficient minutes for recorded audio
        let requiredMinutes = max(1, Int(ceil(recordingDuration / 60.0)))
        if minutesManager.currentBalance < requiredMinutes {
            estimatedMinutesNeeded = requiredMinutes
            showingInsufficientMinutesAlert = true
            audioRecorder.deleteRecording(at: recordingURL)
            currentRecordingURL = nil
            recordingDuration = 0
            recordingStartTime = nil
            hasFinishedRecording = false
            return
        }

        hasFinishedRecording = true

        // Create meeting immediately with form data
        createProcessingMeeting()

        // FIXED: Store recording path immediately for retry capability
        if let meeting = createdMeeting {
            meeting.localAudioPath = recordingURL.path
            do {
                try modelContext.save()
            } catch {
                print("Error saving meeting with audio path: \(error)")
            }
        }

        // Start background task for recorded audio transcription
        if let meetingId = createdMeetingId {
            currentBackgroundTaskId = backgroundTaskManager.startBackgroundTask(
                for: meetingId,
                meetingName: meetingName,
                currentChunk: currentChunk,
                totalChunks: totalChunks
            )
        }

        // Track meeting creation (without transcription yet)
        Task {
            let duration = Int(recordingDuration)
            await UsageTracker.shared.trackMeetingCreated(transcribed: false, meetingSeconds: duration)
        }
        
        // Notify parent to handle navigation
        if let meeting = createdMeeting {
            onMeetingCreated?(meeting)
        }
        
        Task {
            do {
                let transcript = try await openAIService.transcribeAudioFromURL(
                    audioURL: recordingURL,
                    progressCallback: { progress in
                        Task { @MainActor in
                            guard let meeting = createdMeeting else { return }

                            let hasProgressChanged =
                                meeting.lastProcessedChunk != progress.currentChunk ||
                                meeting.totalChunks != progress.totalChunks

                            guard hasProgressChanged else { return }

                            meeting.updateChunkProgress(
                                completed: progress.currentChunk,
                                total: progress.totalChunks
                            )

                            do {
                                try modelContext.save()
                            } catch {
                                print("Error saving chunk progress: \(error)")
                            }
                        }
                    },
                    meetingName: meetingNameTrimmed.isEmpty ? "Untitled Meeting" : meetingNameTrimmed,
                    meetingId: createdMeetingId
                )
                
                // Debit minutes for transcription
                let duration = Int(recordingDuration)
                if let meetingId = createdMeetingId {
                    _ = await minutesManager.debitMinutes(seconds: duration, meetingID: meetingId.uuidString)
                }

                // Track successful transcription
                await UsageTracker.shared.trackMeetingCreated(transcribed: true, meetingSeconds: duration)
                
                await MainActor.run {
                    updateMeetingWithTranscript(transcript: transcript)
                }
                
                // Upload audio to Supabase before deleting local file
                if let meeting = createdMeeting {
                    do {
                        _ = try await SupabaseManager.shared.uploadAudioRecording(
                            audioURL: recordingURL,
                            meetingId: meeting.id,
                            duration: recordingDuration
                        )
                        
                        // Update meeting to indicate it has a recording
                        await MainActor.run {
                            meeting.hasRecording = true
                        }
                    } catch {
                        print("Error uploading audio to Supabase: \(error)")
                    }
                }

                // FIXED: Don't delete recording yet - wait until AI processing completes successfully
                // Deletion will happen in updateMeetingWithAI after everything succeeds

                // Process AI in background after navigation
                let overview = try await openAIService.generateMeetingOverview(transcript)
                let summary = try await openAIService.summarizeMeeting(transcript)
                let actionItems = try await openAIService.extractActions(transcript)
                
                // Track AI usage
                await UsageTracker.shared.trackAIUsage(
                    summaries: 1,
                    actionsExtracted: actionItems.count
                )
                
                await MainActor.run {
                    updateMeetingWithAI(overview: overview, summary: summary, actionItems: actionItems)

                    // End background task on success
                    if currentBackgroundTaskId != .invalid {
                        backgroundTaskManager.endBackgroundTask(currentBackgroundTaskId)
                        currentBackgroundTaskId = .invalid
                    }
                }
                
            } catch {
                await MainActor.run {
                    print("Error processing meeting audio: \(error)")

                    // Cancel processing notification on error
                    if let meetingId = createdMeetingId {
                        NotificationService.shared.cancelProcessingNotification(for: meetingId)
                    }

                    // End background task on failure
                    if currentBackgroundTaskId != .invalid {
                        backgroundTaskManager.endBackgroundTask(currentBackgroundTaskId)
                        currentBackgroundTaskId = .invalid
                    }

                    // FIXED: Properly handle meeting error state
                    if let meeting = createdMeeting {
                        meeting.setProcessingError("Transcription failed. Please try again.")
                        meeting.audioTranscript = "Transcription failed"
                        meeting.shortSummary = "Processing failed"
                        meeting.aiSummary = "This meeting could not be processed. You can try again using the retry button."

                        // Save the recorded audio file path for retry
                        meeting.localAudioPath = recordingURL.path

                        do {
                            try modelContext.save()
                        } catch {
                            print("Error saving meeting after failure: \(error)")
                        }
                    }
                }
            }
        }
    }

    private func cancelTranscription() {
        print("🚫 [CreateMeeting] User cancelled transcription")

        // End background task if active
        if currentBackgroundTaskId != .invalid {
            backgroundTaskManager.endBackgroundTask(currentBackgroundTaskId)
            currentBackgroundTaskId = .invalid
            print("🚫 [CreateMeeting] Ended background task")
        }

        // Stop processing state
        isProcessingAudio = false
        currentProcessingPhase = .transcribing
        transcriptionProgress = 0.0
        currentChunk = 0
        totalChunks = 0
        processingStage = ""
        partialTranscripts = []
        liveOverview = ""
        liveSummary = ""

        // Delete the meeting from database if it was created
        if let meetingId = createdMeetingId {
            let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
            if let meeting = try? modelContext.fetch(descriptor).first {
                modelContext.delete(meeting)
                try? modelContext.save()
                print("🚫 [CreateMeeting] Deleted cancelled meeting from database")
            }
        }

        // Clear imported audio state to ensure fresh start on next create
        if importedAudioURL != nil {
            // The imported audio will be cleared when view dismisses
            print("🚫 [CreateMeeting] Will clear imported audio state on dismiss")
        }

        // Dismiss the view
        dismiss()
        print("🚫 [CreateMeeting] Dismissed view")
    }

    private func createProcessingMeeting() {
        let meeting = Meeting(
            name: meetingNameTrimmed.isEmpty ? "Untitled Meeting" : meetingNameTrimmed,
            location: meetingLocation,
            meetingNotes: meetingNotes,
            audioTranscript: "Transcribing meeting audio...",
            shortSummary: "Generating overview...",
            aiSummary: "Generating meeting summary...",
            isProcessing: true
        )
        meeting.dateCreated = meetingDate

        // Initialize processing state for new error handling
        meeting.updateProcessingState(.transcribing)
        meeting.clearProcessingError()

        // Set local audio path for imported audio
        if let audioURL = importedAudioURL {
            meeting.localAudioPath = audioURL.path
        }
        // Note: For recorded audio, localAudioPath will be set in stopMeetingRecording()

        if let startTime = recordingStartTime {
            meeting.startTime = startTime
            meeting.stopRecording() // Sets end time
        }

        modelContext.insert(meeting)
        createdMeeting = meeting
        createdMeetingId = meeting.id

        // Schedule processing notification
        Task {
            await NotificationService.shared.scheduleProcessingNotification(
                for: meeting.id,
                meetingName: meeting.name
            )
        }

        do {
            try modelContext.save()
        } catch {
            print("Error saving meeting: \(error)")
        }
    }
    
    private func updateMeetingWithTranscript(transcript: String) {
        guard let meetingId = createdMeetingId else { return }
        
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
        
        do {
            let meetings = try modelContext.fetch(descriptor)
            guard let meeting = meetings.first else { return }
            
            meeting.audioTranscript = transcript
            meeting.dateModified = Date()
            
            try modelContext.save()
        } catch {
            print("Error updating meeting with transcript: \(error)")
        }
    }
    
    private func updateMeetingWithAI(overview: String, summary: String, actionItems: [ActionItem]) {
        guard let meetingId = createdMeetingId else { return }
        
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
        
        do {
            let meetings = try modelContext.fetch(descriptor)
            guard let meeting = meetings.first else { return }
            
            meeting.shortSummary = overview
            meeting.aiSummary = summary

            // FIXED: Use new state management methods
            meeting.markCompleted()

            // Clean up local audio file now that processing is complete (only after successful upload)
            if meeting.hasRecording,
               let localPath = meeting.localAudioPath,
               FileManager.default.fileExists(atPath: localPath) {
                try? FileManager.default.removeItem(atPath: localPath)
                meeting.localAudioPath = nil
            }

            // Send processing complete notification
            Task {
                await NotificationService.shared.sendProcessingCompleteNotification(
                    for: meeting.id,
                    meetingName: meeting.name
                )
            }
            
            // Create Action entities from extracted action items
            for actionItem in actionItems {
                let priority: ActionPriority
                switch actionItem.priority.uppercased() {
                case "HIGH":
                    priority = .high
                case "MED", "MEDIUM":
                    priority = .medium
                case "LOW":
                    priority = .low
                default:
                    priority = .medium
                }
                
                let action = Action(
                    title: actionItem.action,
                    priority: priority,
                    sourceNoteId: meeting.id // Reusing the same field for meetings
                )
                
                modelContext.insert(action)
            }
            
            try modelContext.save()
            
            // Track action creation
            if !actionItems.isEmpty {
                Task {
                    await UsageTracker.shared.trackActionsCreated(count: actionItems.count)
                }
            }
            
            // Update notifications after creating new actions
            Task { @MainActor in
                // Fetch all actions to update notifications
                let descriptor = FetchDescriptor<Action>()
                if let allActions = try? modelContext.fetch(descriptor) {
                    // Check if actions tab is enabled
                    let actionsEnabled = UserDefaults.standard.bool(forKey: "showActionsTab")
                    NotificationService.shared.scheduleNotification(with: allActions)
                    // Also update badge immediately
                    await NotificationService.shared.updateBadgeCount(with: allActions, actionsEnabled: actionsEnabled)
                }
            }
        } catch {
            print("Error updating meeting with AI: \(error)")
        }
    }
    
    private func startCountdown() {
        guard openAIService.apiKey != nil else {
            showingAPIKeyAlert = true
            return
        }

        meetingNameTouched = true

        guard !meetingNameTrimmed.isEmpty else {
            showingNameRequiredAlert = true
            return
        }

        // Check if user has minutes to start recording (minimum 1 minute)
        if minutesManager.currentBalance <= 0 {
            showingInsufficientMinutesAlert = true
            return
        }

        // Request microphone permission if not granted
        if !isPermissionGranted(microphonePermissionStatus) {
            requestMicrophonePermission { granted in
                DispatchQueue.main.async {
                    microphonePermissionStatus = granted ? .granted : .denied
                    if granted {
                        startCountdownAfterPermission()
                    }
                }
            }
            return
        }

        startCountdownAfterPermission()
    }

    private func startCountdownAfterPermission() {
        countdownValue = 3
        showingCountdown = true

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdownValue > 1 {
                countdownValue -= 1
            } else {
                timer.invalidate()
                countdownTimer = nil
                showingCountdown = false
                startMeetingRecording()
            }
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        showingCountdown = false
        countdownValue = 3
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func appendToMeetingNotes(_ snippet: String) {
        let trimmedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSnippet.isEmpty else { return }

        let snippetToAppend = snippet

        if meetingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meetingNotes = snippetToAppend
        } else if meetingNotes.hasSuffix("\n\n") {
            meetingNotes += snippetToAppend
        } else if meetingNotes.hasSuffix("\n") {
            meetingNotes += snippetToAppend
        } else {
            meetingNotes += "\n\n" + snippetToAppend
        }

        focusedField = .notes
    }

    // Microphone permission helpers
    private func getCurrentPermissionStatus() -> MicrophonePermissionStatus {
        MicrophonePermissionStatus.current()
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission(completionHandler: completion)
    }

    private func isPermissionGranted(_ permission: MicrophonePermissionStatus) -> Bool {
        permission == .granted
    }

    private func isPermissionDenied(_ permission: MicrophonePermissionStatus) -> Bool {
        permission == .denied
    }
}

private struct MeetingInputCard<Content: View>: View {
    @EnvironmentObject private var themeManager: ThemeManager

    let title: String
    let helper: String?
    let error: String?
    let iconSystemName: String?
    let contentPadding: EdgeInsets
    let content: Content

    init(title: String,
         helper: String? = nil,
         error: String? = nil,
         iconSystemName: String? = nil,
         contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14),
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.helper = helper
        self.error = error
        self.iconSystemName = iconSystemName
        self.contentPadding = contentPadding
        self.content = content()
    }

    private var hasError: Bool {
        error != nil
    }

    private var borderColor: Color {
        hasError ? themeManager.currentTheme.destructiveColor : themeManager.currentTheme.accentColor.opacity(0.25)
    }

    private var labelText: String {
        themeManager.currentTheme.headerStyle == .brackets ? title.uppercased() : title
    }

    private var outerBackgroundOpacity: Double {
        themeManager.currentTheme.colorScheme == .dark ? 0.45 : 0.18
    }

    private var shadowOpacity: Double {
        themeManager.currentTheme.colorScheme == .dark ? 0.5 : 0.18
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let iconSystemName {
                    Image(systemName: iconSystemName)
                        .font(.system(.callout, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .semibold))
                        .foregroundColor(themeManager.currentTheme.accentColor)
                }

                Text(labelText)
                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
            }

            content
                .padding(contentPadding)
                .background(
                    RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                        .fill(themeManager.currentTheme.materialStyle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius)
                        .stroke(borderColor, lineWidth: hasError ? 1.5 : 1)
                )

            if let error {
                Text(error)
                    .font(.system(.caption, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(themeManager.currentTheme.destructiveColor)
            } else if let helper {
                Text(helper)
                    .font(.system(.caption2, design: themeManager.currentTheme.useMonospacedFont ? .monospaced : .default))
                    .foregroundColor(themeManager.currentTheme.secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: themeManager.currentTheme.cornerRadius + 6)
                .fill(themeManager.currentTheme.secondaryBackgroundColor.opacity(outerBackgroundOpacity))
        )
        .shadow(color: Color.black.opacity(shadowOpacity), radius: 10, x: 0, y: 6)
    }
}

// MARK: - Waveform View
struct WaveformView: View {
    let level: Float
    let isRecording: Bool
    let accentColor: Color

    @State private var waveformData: [Float] = Array(repeating: 0.0, count: 30)
    @State private var animationTimer: Timer?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<waveformData.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(accentColor)
                    .frame(width: 3, height: CGFloat(max(4, waveformData[index] * 50)))
                    .opacity(isRecording ? 0.9 : 0.5)
                    .animation(.easeInOut(duration: 0.1), value: waveformData[index])
            }
        }
        .onAppear {
            if isRecording {
                startWaveformAnimation()
            }
        }
        .onDisappear {
            stopWaveformAnimation()
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startWaveformAnimation()
            } else {
                stopWaveformAnimation()
            }
        }
        .onChange(of: level) { _, newLevel in
            updateWaveform(with: newLevel)
        }
    }

    private func startWaveformAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // Simulate waveform movement by shifting data and adding new values
            waveformData.removeFirst()
            let newValue = level + Float.random(in: -0.2...0.2)
            waveformData.append(max(0.1, min(1.0, newValue)))
        }
    }

    private func stopWaveformAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateWaveform(with newLevel: Float) {
        guard isRecording else { return }

        // Add some variation to make it look more natural
        let variation = Float.random(in: -0.1...0.1)
        let adjustedLevel = max(0.1, min(1.0, newLevel + variation))

        // Update the last few values for smooth animation
        if waveformData.count > 3 {
            waveformData[waveformData.count - 1] = adjustedLevel
            waveformData[waveformData.count - 2] = adjustedLevel * 0.8
            waveformData[waveformData.count - 3] = adjustedLevel * 0.6
        }
    }
}
