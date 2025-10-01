# PRD: Transcription System Production Hardening

## Introduction/Overview

The current transcription system successfully processes audio files and converts them to text using OpenAI's gpt-4o-transcribe API. However, a comprehensive production readiness audit revealed critical reliability, user experience, and resource management issues that must be addressed before production launch.

This PRD outlines the necessary improvements to make the transcription system production-ready, focusing on network reliability, cancellation support, resource management, error handling, and user experience enhancements.

**Problem Statement:** The transcription system has 7 critical and moderate issues that could cause:
- Infinite hangs due to missing network timeouts
- Poor UX from inability to cancel long transcriptions
- Memory issues on 2+ hour recordings
- Unnecessary costs from fallback behaviors
- Failed transcriptions from missing disk space checks

**Goal:** Achieve 95%+ production readiness by implementing 11 critical fixes across reliability, UX, and resource management.

---

## Goals

1. **Reliability:** Prevent infinite hangs and improve error recovery with proper timeouts and retry logic
2. **User Control:** Enable users to cancel in-progress transcriptions
3. **Resource Management:** Optimize memory usage and prevent disk space failures
4. **Error Transparency:** Provide clear error messages and fail fast when processing cannot succeed
5. **Background Handling:** Gracefully handle iOS background task limitations
6. **Cost Efficiency:** Ensure consistent cost savings by removing risky fallback behaviors
7. **Maintainability:** Improve code quality with unit tests for all new implementations

---

## User Stories

### US-1: Network Reliability
**As a** user with unstable internet connection
**I want** transcriptions to timeout gracefully instead of hanging forever
**So that** I can retry or cancel without force-closing the app

### US-2: Cancellation Support
**As a** user who accidentally starts a long transcription
**I want** to cancel the transcription in progress
**So that** I don't waste API credits or wait unnecessarily

### US-3: Background Handling
**As a** user transcribing long recordings
**I want** to be notified if the app needs to return to foreground
**So that** I can keep my transcription running to completion

### US-4: Disk Space Protection
**As a** user with limited storage
**I want** to be warned before starting transcription if disk space is insufficient
**So that** I don't waste time on a transcription that will fail

### US-5: Clear Error Messages
**As a** user experiencing transcription failures
**I want** clear, actionable error messages
**So that** I understand what went wrong and what to do next

### US-6: Memory Efficiency
**As a** user transcribing 2+ hour meetings
**I want** the app to use memory efficiently
**So that** the app doesn't crash or slow down my device

---

## Functional Requirements

### FR-1: URLSession Timeout Configuration
**Priority:** CRITICAL (Must Fix Now)

1.1. The system MUST configure URLSession with explicit timeout values:
- Request timeout: 120 seconds (2 minutes per individual request)
- Resource timeout: 600 seconds (10 minutes total per transcription attempt)

1.2. The system MUST use this configured URLSession for all OpenAI API calls

1.3. When a timeout occurs, the system MUST retry according to retry logic (see FR-5)

1.4. After all retries exhausted, the system MUST throw a clear timeout error to the user

**Files to Modify:** `OpenAIService.swift`

---

### FR-2: Cancellation Support
**Priority:** CRITICAL (Must Fix Now)

2.1. The system MUST support Task cancellation throughout the transcription pipeline

2.2. Cancellation MUST be checkable at these points:
- Before starting each chunk transcription
- During audio processing (speed-up/compression)
- During chunk creation

2.3. When cancellation is detected:
- Stop all processing immediately
- Discard all progress (partial transcripts)
- Throw `CancellationError`
- Show user-friendly "Transcription cancelled" message

2.4. The system MUST NOT charge for cancelled transcriptions (no API calls after cancellation)

**Files to Modify:** `OpenAIService.swift`, `AudioChunker.swift`

**Technical Note:** Use `Task.checkCancellation()` or `Task.isCancelled` before expensive operations

---

### FR-3: Improved Error Handling for Audio Processing
**Priority:** CRITICAL (Must Fix Now)

3.1. The system MUST remove the "fallback to original audio" behavior in `speedUpAudio()`

3.2. When audio speed-up/compression fails, the system MUST:
- Log the specific error with full context
- Throw `OpenAIError.audioProcessingFailed(String)` with details
- Show user error message: "Audio processing failed: [reason]. Please try again or contact support."

3.3. The system MUST NOT attempt transcription with unprocessed audio

3.4. The system MUST differentiate between:
- Processing errors (fail immediately)
- Network errors (retry according to FR-5)
- API errors (fail with specific message)

**Files to Modify:** `OpenAIService.swift`, `OpenAIError.swift`

---

### FR-4: Disk Space Validation
**Priority:** HIGH (Should Fix This Week)

4.1. Before starting transcription, the system MUST check available disk space

4.2. The system MUST calculate required disk space as:
```
required = (originalFileSize × 2) + (estimatedChunks × 2MB)
```

4.3. Minimum free space after transcription MUST be 100MB (safety buffer)

4.4. If insufficient disk space:
- Show error: "Insufficient storage. Need [X]MB free, but only [Y]MB available. Please free up space and try again."
- Do NOT start transcription
- Log event for analytics

4.5. The system MUST perform this check:
- Before chunking large files
- Before processing small files

**Files to Modify:** `OpenAIService.swift`, `AudioChunker.swift`

**Technical Note:** Use `FileManager.default.attributesOfFileSystem(forPath:)[.systemFreeSize]`

---

### FR-5: Enhanced Retry Logic
**Priority:** HIGH (Should Fix This Week)

5.1. The system MUST retry on these additional error conditions:
- `NSURLErrorNetworkConnectionLost` (-1005)
- `NSURLErrorNotConnectedToInternet` (-1009)
- `NSURLErrorTimedOut` (-1001)
- `NSURLErrorCannotConnectToHost` (-1004)
- HTTP 408 (Request Timeout)
- HTTP 503 (Service Unavailable - temporary)

5.2. The system MUST NOT retry on these errors (fail fast):
- HTTP 400 (Bad Request)
- HTTP 401 (Unauthorized/Invalid API Key)
- HTTP 403 (Forbidden)
- HTTP 413 (Payload Too Large)
- `CancellationError`

5.3. Retry behavior MUST remain:
- Maximum 3 attempts
- Exponential backoff: 1s, 2s, 4s
- Log each retry attempt

**Files to Modify:** `OpenAIService.swift` (update `shouldRetry()` method)

---

### FR-6: Background Task Expiration Handling
**Priority:** HIGH (Should Fix This Week)

6.1. When iOS background task is about to expire (30 seconds warning), the system MUST:
- Show local notification: "Transcription paused - Open SnipNote to continue"
- Include meeting name in notification
- Save current chunk index to UserDefaults
- Set meeting status to "paused"

6.2. When user returns to app with paused transcription:
- Show alert: "Continue transcription of '[Meeting Name]'?"
- If yes: Resume from saved chunk index
- If no: Mark transcription as cancelled

6.3. The system MUST register background task expiration handler when transcription starts

6.4. Notification MUST be actionable (tapping opens app to specific meeting)

**Files to Modify:** `OpenAIService.swift`, `NotificationService.swift`, Meeting view model

**Technical Note:** Use `UIApplication.shared.beginBackgroundTask(expirationHandler:)`

---

### FR-7: Memory-Efficient Chunk Streaming
**Priority:** MEDIUM (Can Fix Later - but recommended)

7.1. The system MUST refactor chunk processing from batch to streaming model

7.2. Current behavior (REMOVE):
```swift
let chunks = try await AudioChunker.createChunks(...) // All chunks in memory
for chunk in chunks { ... }
```

7.3. New behavior (IMPLEMENT):
```swift
for try await chunk in AudioChunker.streamChunks(...) { // One chunk at a time
    let transcript = try await transcribe(chunk)
    // Chunk data released from memory here
}
```

7.4. Only ONE chunk MUST be in memory at a time (except 2s overlap data)

7.5. The system MUST maintain progress tracking accuracy with streaming model

**Files to Modify:** `AudioChunker.swift`, `OpenAIService.swift`

**Estimated Effort:** 3-4 hours

---

### FR-8: Progress Weighting Adjustment
**Priority:** LOW (Can Fix Later)

8.1. The system MUST adjust progress calculation to reflect actual time spent:
- Chunking phase: 10% (currently 30%)
- Transcription phase: 90% (currently 70%)

8.2. Progress percentage formula MUST be:
```swift
let progress = 10.0 + (Double(completedChunks) / Double(totalChunks)) × 90.0
```

8.3. The system MUST update progress after each chunk completes

**Files to Modify:** `OpenAIService.swift` (transcribeAudioInChunks method)

---

### FR-9: API Cost Logging
**Priority:** LOW (Can Fix Later)

9.1. The system MUST log actual transcription costs for analytics

9.2. For each transcription, log:
- Original duration (seconds)
- Processed duration (seconds after 1.5x speed)
- Cost estimate: `processedDuration × $0.006 / 60` (gpt-4o-transcribe rate)
- File size (before and after compression)
- Model used

9.3. Logs MUST include:
```swift
print("💰 [OpenAI] Transcription cost estimate: $[X.XX] ([Y]s @ $0.006/min)")
```

9.4. The system MAY expose this data via analytics dashboard (future enhancement)

**Files to Modify:** `OpenAIService.swift`

---

### FR-10: Transcript Merge Edge Case Fix
**Priority:** LOW (Can Fix Later)

10.1. The system MUST handle empty first chunk gracefully

10.2. Current behavior (BUG):
```swift
guard var merged = transcripts.first?.trimmingCharacters(...) else {
    return "" // Returns empty if first chunk is empty, ignoring remaining chunks
}
```

10.3. New behavior (FIX):
```swift
// Find first non-empty transcript
guard var merged = transcripts.first(where: { !$0.trimmingCharacters(...).isEmpty }) else {
    return "" // Only return empty if ALL chunks are empty
}
```

10.4. The system MUST log warning if any chunk returns empty transcript

**Files to Modify:** `OpenAIService.swift` (mergeChunkTranscripts method)

---

### FR-11: Chunk Duration vs Size Validation
**Priority:** LOW (Can Fix Later)

11.1. The system MUST validate actual chunk size, not just duration

11.2. Current behavior (BUG):
- Minimum 60s chunk duration can create chunks > 1.5MB for high-quality audio

11.3. New behavior (FIX):
```swift
let chunkDuration = max(targetChunkDuration, 60.0)
let chunkData = try await extractAudioSegment(...)

if chunkData.count > maxChunkSizeBytes * 1.2 { // 20% tolerance
    // Reduce chunk duration by 50% and retry
    let reducedDuration = chunkDuration * 0.5
    chunkData = try await extractAudioSegment(..., duration: reducedDuration)
}
```

11.4. The system MUST ensure no chunk exceeds 1.8MB (1.5MB target + 20% tolerance)

**Files to Modify:** `AudioChunker.swift` (createAudioChunks method)

---

## Non-Goals (Out of Scope)

1. **Server-side transcription:** This PRD does not include moving transcription to backend servers
2. **Offline transcription:** Does not include on-device speech recognition fallback
3. **Real-time transcription:** Does not include live transcription during recording
4. **Multi-language detection:** Does not include automatic language detection/switching
5. **Speaker diarization:** Does not include identifying different speakers in audio
6. **Custom model fine-tuning:** Does not include training custom transcription models
7. **Success metrics tracking:** Analytics dashboard for success rate/performance (future PRD)
8. **Rollback strategy:** Feature flags and gradual rollout (handled by release process)

---

## Design Considerations

### User-Facing Changes

1. **Cancellation UI:**
   - Add "Cancel" button to transcription progress screen
   - Confirmation dialog: "Cancel transcription? Progress will be lost."
   - Show cancellation feedback: "Transcription cancelled"

2. **Error Messages:**
   - Replace generic errors with specific, actionable messages
   - Examples:
     - "Network timeout - Please check your connection and try again"
     - "Insufficient storage - Free up 50MB and try again"
     - "Audio processing failed - File may be corrupted"

3. **Background Notification:**
   - Title: "Transcription Paused"
   - Body: "Open SnipNote to continue transcribing '[Meeting Name]'"
   - Action: Opens app to meeting detail view

### No Visual Design Changes
- Existing UI components remain unchanged
- Only error messaging and button behavior changes

---

## Technical Considerations

### Dependencies
- **Existing:** AVFoundation, Foundation, UIKit
- **No new dependencies required**

### Architecture Impact
- All changes are internal to `OpenAIService.swift` and `AudioChunker.swift`
- No changes to public API signatures (existing callers unaffected)
- Cancellation support uses Swift's built-in Task cancellation

### Performance Impact
- **Memory:** 30-50% reduction with chunk streaming (FR-7)
- **Disk I/O:** Minor increase from disk space checks (negligible)
- **Processing time:** No change (same transcription logic)

### Backwards Compatibility
- All changes are backwards compatible
- No database migrations required
- No breaking changes to existing meetings

### Error Handling Strategy
```swift
// New error types
enum OpenAIError: Error {
    case noAPIKey
    case transcriptionFailed
    case audioProcessingFailed(String) // NEW
    case insufficientDiskSpace(required: UInt64, available: UInt64) // NEW
    case apiError(String)
    case vectorStoreUnavailable(String)
}
```

---

## Testing Requirements

### Unit Tests (Required)

All new implementations MUST have unit tests covering:

**Test File:** `OpenAIServiceTests.swift`

1. **URLSession Timeout Tests:**
   - Test request timeout triggers after 120s
   - Test resource timeout triggers after 600s
   - Test timeout triggers retry logic

2. **Cancellation Tests:**
   - Test cancellation during chunk processing
   - Test cancellation during audio processing
   - Test cancellation prevents API calls
   - Test cancellation cleans up resources

3. **Disk Space Validation Tests:**
   - Test insufficient space prevents transcription
   - Test sufficient space allows transcription
   - Test space calculation accuracy

4. **Retry Logic Tests:**
   - Test retryable errors trigger retry
   - Test non-retryable errors fail immediately
   - Test max 3 retry attempts
   - Test exponential backoff timing

5. **Error Handling Tests:**
   - Test audio processing failures throw correct error
   - Test no fallback to original audio occurs

**Test File:** `AudioChunkerTests.swift`

6. **Chunk Streaming Tests:**
   - Test chunks yielded one at a time
   - Test memory usage stays constant
   - Test progress updates correctly

7. **Chunk Size Validation Tests:**
   - Test chunks don't exceed 1.8MB
   - Test duration reduction when size exceeded

### Manual Testing Scenarios

After implementation, manually test:

1. **Network conditions:**
   - Airplane mode during transcription
   - Slow 3G connection
   - WiFi disconnect mid-transcription

2. **Cancellation:**
   - Cancel after 1 chunk
   - Cancel after 50% progress
   - Cancel immediately after start

3. **Background behavior:**
   - Start transcription, background app
   - Wait 3+ minutes, check notification
   - Return to app, verify resume works

4. **Disk space:**
   - Fill device to < 50MB free
   - Attempt transcription
   - Verify error message accuracy

5. **Edge cases:**
   - 2+ hour recording (memory test)
   - First chunk returns empty transcript
   - Very high quality audio (chunk size test)

---

## Open Questions

1. **Background URLSession:** Should we investigate using `URLSessionConfiguration.background` for network requests to survive app suspension? (Future enhancement)

2. **Partial Transcript Recovery:** Should cancellation optionally save partial transcripts instead of discarding? (Future UX improvement)

3. **Analytics Integration:** Where should cost logs be sent for analytics tracking? (Requires analytics PRD)

4. **Chunk Size Tuning:** After memory optimization, should we further reduce chunk size from 1.5MB to 1MB for faster progress updates? (Monitor post-launch)

5. **Notification Permissions:** Should we request notification permission proactively for background transcriptions, or only when first needed?

---

## Implementation Notes for Developer

### Recommended Implementation Order

**Phase 1 - Critical Fixes (Week 1):**
1. FR-3: Error handling (1 hour)
2. FR-1: URLSession timeouts (30 min)
3. FR-2: Cancellation support (2 hours)
4. FR-5: Enhanced retry logic (1 hour)

**Phase 2 - High Priority (Week 1-2):**
5. FR-4: Disk space validation (1.5 hours)
6. FR-6: Background task handling (2 hours)

**Phase 3 - Nice to Have (Week 2-3):**
7. FR-7: Memory optimization (3-4 hours)
8. FR-8: Progress weighting (30 min)
9. FR-9: Cost logging (1 hour)
10. FR-10: Transcript merge fix (30 min)
11. FR-11: Chunk size validation (1 hour)

**Total Estimated Effort:** 14-15 hours

### Key Files to Modify

Primary files:
- `OpenAIService.swift` (most changes)
- `OpenAIError.swift` (new error types)
- `AudioChunker.swift` (streaming, validation)
- `NotificationService.swift` (background notifications)

Test files to create:
- `OpenAIServiceTests.swift`
- `AudioChunkerTests.swift`

### Success Criteria

Implementation is complete when:
- ✅ All 11 functional requirements implemented
- ✅ All unit tests pass with >80% code coverage
- ✅ Manual testing scenarios pass
- ✅ No regression in existing transcription success rate
- ✅ Code review approved by senior developer

---

## Appendix: Current System Audit Summary

**Production Readiness Score:** 7/10 → Target: 9.5/10

**Critical Issues Fixed:**
- URLSession timeout missing
- No cancellation support
- Risky fallback behavior
- Missing disk space checks

**High Priority Issues Fixed:**
- Incomplete retry logic
- Background task expiration unhandled

**Nice to Have Issues Fixed:**
- Memory inefficiency with large files
- Inaccurate progress weighting
- Missing cost visibility
- Edge case bugs

**Result:** System ready for production launch with confidence in reliability, UX, and resource management.
