# PRD: Smart Transcription Mode Selection & Server-Side Notifications

## Introduction/Overview

SnipNote currently offers two transcription processing methods:
1. **On-device processing** (legacy): Fast, local transcription using OpenAI Whisper API
2. **Server-side processing** (new): Cloud-based transcription for long recordings, allows users to leave the app

**Problem**: Users must manually toggle between these modes, and server-side processing lacks completion notifications. This creates confusion and a poor user experience when long transcriptions complete while the app is closed.

**Goal**: Automatically select the optimal transcription method based on audio duration, provide consistent notifications for all processing types, and optimize audio before server upload to reduce costs and processing time.

---

## Goals

1. **Eliminate user confusion** by automatically selecting the appropriate transcription method based on audio duration
2. **Provide consistent notifications** for server-side transcription (matching on-device behavior)
3. **Optimize server processing** by applying 1.5x speed-up and compression before upload
4. **Reduce costs** by 33% through audio optimization (shorter duration = less transcription time)
5. **Improve reliability** through automatic retry logic with fallback to on-device processing
6. **Maintain storage efficiency** by cleaning up local audio files after successful processing

---

## User Stories

1. **As a user recording a quick 2-minute meeting**, I want the transcription to complete in ~30 seconds so I can immediately see results and move on with my day.

2. **As a user uploading a 2-hour lecture recording**, I want the app to process it in the background so I can close the app and get notified when it's ready, without worrying about battery drain or keeping the app open.

3. **As a user**, I want to receive notifications when my meeting transcription completes, regardless of whether it was processed on-device or on the server.

4. **As a user**, I don't want to think about technical details like "server vs local processing" - I just want my meeting transcribed reliably and efficiently.

5. **As a user**, if server processing fails, I want the app to automatically retry or fall back to local processing without requiring manual intervention.

---

## Functional Requirements

### Auto-Selection Logic

1. The system **must** automatically determine the transcription method based on audio duration:
   - Audio ≤ 5 minutes (300 seconds): Use on-device processing
   - Audio > 5 minutes (301+ seconds): Use server-side processing

2. The system **must not** display any UI toggle or option for users to manually select transcription mode.

3. The selection logic **must** execute silently without user awareness or confirmation.

### Server-Side Notifications

4. The system **must** send a "Processing Started" notification when a server-side transcription job is created.

5. The system **must** send progress update notifications at key milestones:
   - Upload complete
   - Transcription in progress
   - AI summary generation in progress

6. The system **must** send a "Meeting Ready!" notification when server-side processing completes successfully.

7. The system **must** send a failure notification if server-side processing fails, with a clear error message.

8. All notifications **must** be deep-linkable, navigating the user directly to the meeting detail view when tapped.

### Audio Optimization (Server-Side)

9. Before uploading audio to Supabase for server processing, the system **must**:
   - Speed up audio to 1.5x (reduces duration by 33%)
   - Apply M4A compression to reduce file size

10. The system **must** adjust the stored meeting duration to reflect the sped-up audio (original duration ÷ 1.5).

11. The optimization process **must** match the existing on-device behavior for imported audio (speed-up + compression).

12. For in-app recordings, the system **must** use speed-up without re-compression (audio already optimized).

### Storage Management

13. During processing, the system **must** retain the local audio file at `meeting.localAudioPath` to enable retry functionality.

14. After successful server transcription and AI processing, the system **must**:
   - Delete the local audio file from device storage
   - Set `meeting.localAudioPath = nil`
   - Maintain `meeting.hasRecording = true` (audio available in Supabase)

15. For audio playback, the system **must** download audio from Supabase on-demand when the user taps the play button.

### Retry & Fallback Logic

16. If a server-side transcription job fails, the system **must** automatically retry the job up to 3 times with exponential backoff (5s, 15s, 45s).

17. After 3 failed retry attempts, the system **must** automatically fall back to on-device processing if:
   - The local audio file still exists
   - The user has sufficient minutes in their balance

18. If fallback to on-device is not possible (no local file or insufficient minutes), the system **must**:
   - Display an error notification
   - Mark the meeting as failed with a clear error message
   - Allow manual retry from meeting detail view

### Failure Edge Cases

19. If audio upload to Supabase fails, the system **must** retry the upload up to 3 times before marking as failed.

20. If the server worker is unavailable or times out (no status updates for 10+ minutes), the system **must** trigger the fallback logic.

21. If on-device fallback also fails, the system **must** preserve the local audio file and mark the meeting as retryable.

---

## Non-Goals (Out of Scope)

1. **User-configurable threshold**: The 5-minute threshold is fixed and not user-adjustable in this version.

2. **Batch processing**: Processing multiple meetings simultaneously is out of scope.

3. **Custom audio optimization settings**: Users cannot configure speed-up multiplier or compression quality.

4. **Migration of existing meetings**: This feature only applies to new meetings created after deployment.

5. **Background upload progress UI**: Upload happens silently; no progress bar shown to user during upload phase.

6. **Success metrics tracking**: No analytics or A/B testing infrastructure for this feature.

---

## Design Considerations

### UI Changes

- **Remove**: The existing transcription mode toggle in `CreateMeetingView`
- **No visual changes**: The feature operates entirely behind the scenes
- **Notifications**: Use existing notification templates with updated copy for server-side jobs

### User Feedback

- Processing state indicators remain unchanged (spinner, progress percentage)
- Detail view shows processing status updates from server polling
- Error states display clear, actionable messages

---

## Technical Considerations

### Dependencies

- **OpenAIService.swift**: Extract `speedUpAudio()` method to be called before server upload
- **NotificationService.swift**: Extend existing notification methods to support server-side jobs
- **MeetingDetailView.swift**: Add notification calls in job status polling logic
- **CreateMeetingView.swift**:
  - Remove `transcriptionModeToggle()` UI component
  - Update `analyzeImportedAudio()` to use duration-based auto-selection
  - Add audio optimization before `processServerSide()`

### Backend Integration

- **Python worker**: No changes required (already handles progress tracking)
- **Supabase storage**: Will store optimized (smaller) audio files
- **API endpoints**: No changes needed

### Performance Considerations

- Audio optimization adds 10-20 seconds before upload starts (acceptable for long audio)
- Optimized audio = faster server transcription + lower Whisper API costs
- Smaller file uploads = faster network transfer

### Data Flow

```
User uploads/records audio
    ↓
Check duration
    ↓
≤ 5 min? → Speed-up → On-device transcription → Notify complete
    ↓
> 5 min? → Speed-up + Compress → Upload to Supabase → Create server job → Notify started
                                        ↓
                                   Poll job status (5s interval)
                                        ↓
                                   Job complete? → Notify complete → Delete local file
                                        ↓
                                   Job failed? → Retry 3x → Fallback to on-device
```

---

## Open Questions

1. **Network failure during upload**: Should we pause/resume upload or start over?
   - *Suggested answer*: Start over with 3 retry attempts

2. **User deletes meeting during server processing**: Should we cancel the server job?
   - *Suggested answer*: Yes, call job cancellation endpoint if available, or let it complete and ignore results

3. **Audio optimization failure**: If speed-up/compression fails, should we upload original audio or fail entirely?
   - *Suggested answer*: Upload original audio and log error for monitoring

4. **Notification permissions denied**: How should we handle server job completion if user denied notifications?
   - *Suggested answer*: Update meeting state silently, user sees results when they open the app

5. **Very long audio (> 2 hours)**: Should we enforce a maximum duration for server processing?
   - *Suggested answer*: No hard limit for now, monitor server performance and add if needed

---

## Acceptance Criteria

### Auto-Selection

- [ ] Audio file of 5:00 or less triggers on-device processing
- [ ] Audio file of 5:01 or more triggers server-side processing
- [ ] No transcription mode toggle visible in UI
- [ ] Processing method selected automatically without user input

### Notifications

- [ ] "Processing Started" notification sent when server job created
- [ ] "Meeting Ready!" notification sent when server job completes
- [ ] Failure notification sent if server job fails
- [ ] Tapping notification navigates to meeting detail view
- [ ] Notifications match existing on-device notification style

### Audio Optimization

- [ ] Audio sped up to 1.5x before server upload
- [ ] M4A compression applied to imported audio
- [ ] In-app recordings use speed-up without re-compression
- [ ] Optimized audio uploads successfully to Supabase
- [ ] Meeting duration adjusted to reflect sped-up audio

### Storage Management

- [ ] Local audio file retained during server processing
- [ ] Local audio file deleted after successful server completion
- [ ] Audio playback downloads from Supabase on-demand
- [ ] `meeting.hasRecording = true` after successful upload

### Retry & Fallback

- [ ] Failed server jobs retry automatically (up to 3 times)
- [ ] After 3 failures, system falls back to on-device processing
- [ ] If fallback impossible, meeting marked as failed with retry option
- [ ] Exponential backoff applied between retry attempts (5s, 15s, 45s)

### Edge Cases

- [ ] Upload failures retry up to 3 times
- [ ] Stuck jobs (10+ min no updates) trigger fallback
- [ ] Network errors handled gracefully with user feedback
- [ ] Insufficient minutes shows proper error message
- [ ] Manual retry works for failed meetings

---

## Implementation Notes for Developers

### Phase 1: Remove Toggle & Add Auto-Selection
1. Remove `transcriptionModeToggle()` from `CreateMeetingView.swift`
2. Update `analyzeImportedAudio()` to check `cachedAudioDuration`
3. Route to `processOnDevice()` or `processServerSide()` based on duration

### Phase 2: Audio Optimization
1. Make `speedUpAudio()` public in `OpenAIService.swift`
2. Call before `SupabaseManager.shared.uploadAudioRecording()` in `processServerSide()`
3. Pass optimized URL to upload function
4. Adjust `duration` parameter: `cachedAudioDuration / 1.5`

### Phase 3: Server Notifications
1. Add `NotificationService.shared.scheduleProcessingNotification()` after job creation in `CreateMeetingView.swift`
2. Add `NotificationService.shared.sendProcessingCompleteNotification()` in `MeetingDetailView.applyJobStatusUpdate()` when status == .completed
3. Add failure notification in same location when status == .failed

### Phase 4: Storage Cleanup
1. Add local file deletion in `MeetingDetailView.applyJobStatusUpdate()` after successful completion
2. Check `meeting.hasRecording && meeting.localAudioPath != nil`
3. Delete file and set `meeting.localAudioPath = nil`

### Phase 5: Retry & Fallback Logic
1. Add retry counter to `RenderTranscriptionService.swift`
2. Implement exponential backoff in polling logic
3. After 3 failures, check for local audio and sufficient minutes
4. Call `processOnDevice()` with existing local audio path
5. Display appropriate error if fallback not possible

---

## Testing Checklist

- [ ] Test 3-minute audio → uses on-device, completes in ~30s
- [ ] Test 10-minute audio → uses server, sends notifications
- [ ] Test exactly 5:00 audio → uses on-device
- [ ] Test exactly 5:01 audio → uses server
- [ ] Verify audio is sped up before upload (check Supabase file size)
- [ ] Verify local file deleted after server completion
- [ ] Verify playback works from Supabase
- [ ] Test server failure → auto-retry → fallback to on-device
- [ ] Test insufficient minutes after server failure
- [ ] Test notification deep-linking to meeting detail
- [ ] Test upload failure retry logic
- [ ] Test app closed during server processing → notification works
- [ ] Test no notification permissions → meeting still completes

---

**End of PRD**
