# Task List: Smart Transcription Mode Selection & Server-Side Notifications

Based on PRD: `0001-prd-smart-transcription-mode-and-notifications.md`

## Relevant Files

- `SnipNote/CreateMeetingView.swift` - Main view containing transcription mode toggle (to be removed) and processing logic (to be updated with auto-selection)
- `SnipNote/OpenAIService/OpenAIService.swift` - Contains audio speed-up and compression methods (to be made public/extracted)
- `SnipNote/MeetingDetailView.swift` - Displays meeting details and polls job status (to be updated with notifications and cleanup)
- `SnipNote/NotificationService.swift` - Handles all app notifications (to be extended for server-side jobs)
- `SnipNote/RenderTranscriptionService.swift` - Manages server-side transcription API calls (to be enhanced with retry logic)
- `SnipNote/Meeting.swift` - SwiftData model for meetings (may need duration threshold constant)
- `SnipNote/SupabaseManager.swift` - Handles Supabase storage uploads (to receive optimized audio)

## Tasks

- [x] 1.0 Remove transcription mode toggle and implement auto-selection logic
  - [x] 1.1 Remove `@State private var useServerTranscription` from CreateMeetingView.swift (line 97)
  - [x] 1.2 Remove `transcriptionModeToggle(theme:)` function from CreateMeetingView.swift (lines 1047-1084)
  - [x] 1.3 Remove both calls to `transcriptionModeToggle(theme: theme)` in the UI (lines 690 and 1031)
  - [x] 1.4 Update `analyzeImportedAudio()` function to implement duration-based auto-selection:
    - Check if `cachedAudioDuration <= 300` (5 minutes)
    - If true, call `processOnDevice(audioURL: audioURL)`
    - If false, call `processServerSide(audioURL: audioURL)`
  - [x] 1.5 Remove the `if useServerTranscription` check on line 1285 (always use auto-selection logic)
  - [x] 1.6 Update any console logs to indicate auto-selected mode (e.g., "📱 Auto-selected on-device (duration: X)" or "☁️ Auto-selected server-side (duration: X)")

- [x] 2.0 Extract and expose audio optimization methods
  - [x] 2.1 In `OpenAIService.swift`, change `private func speedUpAudio()` to `public func speedUpAudio()` (line 202)
  - [x] 2.2 Add a new public method `func optimizeAudioForUpload(audioURL: URL) async throws -> URL` that:
    - Takes the audio file URL as input
    - Calls the existing `speedUpAudio()` logic
    - Returns a URL to the optimized audio file
    - Handles cleanup of temporary files
  - [x] 2.3 Update the method to accept a URL parameter instead of Data for easier file handling
  - [x] 2.4 Ensure the method preserves the original file and creates a new optimized file in the temp directory
  - [x] 2.5 Add console logs: "⚡ Optimizing audio for server upload (1.5x speed-up + compression)..."

- [ ] 3.0 Add server-side notification support
  - [ ] 3.1 In `CreateMeetingView.processServerSide()`, after job creation (around line 1576), add:
    ```swift
    await NotificationService.shared.scheduleProcessingNotification(
        for: meetingId,
        meetingName: meeting.name
    )
    ```
  - [ ] 3.2 In `MeetingDetailView.applyJobStatusUpdate()`, when `status == .completed` (around line 1274), add:
    ```swift
    await NotificationService.shared.sendProcessingCompleteNotification(
        for: meeting.id,
        meetingName: meeting.name
    )
    ```
  - [ ] 3.3 In `MeetingDetailView.applyJobStatusUpdate()`, when `status == .failed` (around line 1285), add:
    ```swift
    // Send failure notification with error message
    await NotificationService.shared.sendProcessingFailedNotification(
        for: meeting.id,
        meetingName: meeting.name,
        errorMessage: jobErrorMessage ?? "Unknown error"
    )
    ```
  - [ ] 3.4 Add the new `sendProcessingFailedNotification()` method to `NotificationService.swift`:
    - Copy pattern from `sendProcessingCompleteNotification()`
    - Title: "Transcription Failed"
    - Body: "'\(meetingName)' failed to process: \(errorMessage)"
    - Category: "MEETING_FAILED_NOTIFICATION"
  - [ ] 3.5 Test notification deep-linking: ensure tapping notification navigates to the meeting detail view

- [ ] 4.0 Implement automatic storage cleanup after successful processing
  - [ ] 4.1 In `MeetingDetailView.applyJobStatusUpdate()`, after successful completion (around line 1273), add local file cleanup:
    ```swift
    // Clean up local audio file after successful server processing
    if meeting.hasRecording,
       let localPath = meeting.localAudioPath,
       FileManager.default.fileExists(atPath: localPath) {
        try? FileManager.default.removeItem(atPath: localPath)
        meeting.localAudioPath = nil
        print("🗑️ Deleted local audio file after successful server processing")
    }
    ```
  - [ ] 4.2 Ensure this cleanup only happens for server-side jobs (check `meeting.transcriptionJobId` was not nil)
  - [ ] 4.3 Verify that `meeting.hasRecording` remains true (audio still accessible via Supabase)
  - [ ] 4.4 Add error handling for file deletion failures (log but don't fail the entire operation)

- [ ] 5.0 Add retry logic with fallback to on-device processing
  - [ ] 5.1 In `RenderTranscriptionService.swift`, add retry counter state:
    ```swift
    private var retryAttempts: [String: Int] = [:] // jobId -> attempt count
    ```
  - [ ] 5.2 Update `getJobStatus()` to track failures and implement exponential backoff:
    - If error occurs, increment retry counter for that jobId
    - If retryAttempts < 3, wait with backoff: 5s, 15s, 45s (use `try await Task.sleep()`)
    - If retryAttempts >= 3, throw a specific error indicating max retries exceeded
  - [ ] 5.3 In `MeetingDetailView.pollJobStatus()`, catch max retry errors and trigger fallback:
    ```swift
    catch let error as TranscriptionError where error == .maxRetriesExceeded {
        // Attempt fallback to on-device
        await attemptOnDeviceFallback()
    }
    ```
  - [ ] 5.4 Implement `attemptOnDeviceFallback()` method in `MeetingDetailView`:
    - Check if `meeting.localAudioPath` exists
    - Check if `minutesManager.currentBalance` is sufficient
    - If both true, call existing retry logic (`retryTranscription()`)
    - If not possible, set error state and notify user
  - [ ] 5.5 Add new error case to `TranscriptionError` enum:
    ```swift
    case maxRetriesExceeded
    ```
  - [ ] 5.6 Update console logs to show retry attempts: "🔄 Retry attempt 1/3 for job \(jobId) (waiting 5s...)"
  - [ ] 5.7 Clear retry counter when job succeeds or is manually retried

- [ ] 6.0 Integrate audio optimization into server upload flow
  - [ ] 6.1 In `CreateMeetingView.processServerSide()`, before uploading to Supabase (around line 1546), add:
    ```swift
    // Optimize audio before upload (1.5x speed-up + compression)
    print("⚡ Optimizing audio for server upload...")
    let optimizedURL = try await openAIService.optimizeAudioForUpload(audioURL: audioURL)
    let optimizedDuration = cachedAudioDuration / 1.5
    ```
  - [ ] 6.2 Update the upload call to use `optimizedURL` instead of `audioURL`
  - [ ] 6.3 Update the duration parameter to use `optimizedDuration` instead of `cachedAudioDuration`
  - [ ] 6.4 Add cleanup for optimized file after successful upload:
    ```swift
    try? FileManager.default.removeItem(at: optimizedURL)
    ```
  - [ ] 6.5 Handle optimization failures gracefully:
    - If optimization fails, log error and fall back to uploading original audio
    - Use try-catch around optimization call
    - Log: "⚠️ Audio optimization failed, uploading original audio"
  - [ ] 6.6 Update `meeting.duration` if needed to reflect optimized duration (verify this doesn't break existing logic)

## Testing Checklist

After completing all tasks, verify the following:

- [ ] Upload 3-minute audio → auto-selects on-device, completes quickly
- [ ] Upload 10-minute audio → auto-selects server-side, receives notifications
- [ ] Upload exactly 5:00 audio → uses on-device
- [ ] Upload exactly 5:01 audio → uses server-side
- [ ] No transcription mode toggle visible in UI
- [ ] Server job sends "Processing Started" notification
- [ ] Server job sends "Meeting Ready!" notification on completion
- [ ] Server job sends failure notification if processing fails
- [ ] Local audio file deleted after successful server completion
- [ ] Local audio file retained if server job fails
- [ ] Audio playback still works after local file deletion (downloads from Supabase)
- [ ] Server job retries automatically on failure (check logs for retry attempts)
- [ ] After 3 retry failures, system falls back to on-device processing
- [ ] Optimized audio is uploaded to Supabase (check file size is smaller)
- [ ] Meeting duration reflects optimized duration (verify in meeting details)
- [ ] App closed during server processing → notification still appears
- [ ] Tapping notification navigates to correct meeting detail view

## Notes

- The 5-minute threshold (300 seconds) is hardcoded. If this needs to be configurable in the future, extract it as a constant.
- Retry logic uses exponential backoff: 5s, 15s, 45s between attempts.
- Audio optimization reduces duration by 33% (1.5x speed-up) and applies M4A compression.
- Local file cleanup only happens after successful server completion to preserve retry capability.
- All notification methods already exist in `NotificationService.swift` except `sendProcessingFailedNotification()` which needs to be added.
- The existing `retryTranscription()` method in `MeetingDetailView` can be reused for fallback logic.

---

**Implementation Priority**: Complete tasks in order (1.0 → 6.0) as later tasks depend on earlier changes.

**Estimated Time**: 3-4 hours total (30-40 min per task)
