# Task List: Transcription System Production Hardening

Generated from: `0001-prd-transcription-system-production-hardening.md`

---

## Relevant Files

### Core Implementation Files
- `SnipNote/OpenAIService/OpenAIService.swift` - Main transcription service requiring timeout config, cancellation support, error handling improvements
- `SnipNote/OpenAIService/OpenAIError.swift` - Error enum requiring new error types for audio processing and disk space failures
- `SnipNote/AudioChunker.swift` - Audio chunking logic requiring streaming refactor, size validation, and disk space checks
- `SnipNote/NotificationService.swift` - Notification service requiring background task expiration notifications

### Test Files
- `SnipNoteTests/OpenAIServiceTests.swift` - Unit tests for OpenAIService (URLSession timeouts, cancellation, retry logic, error handling) ✅ Created
- `SnipNoteTests/AudioChunkerTests.swift` - Unit tests for AudioChunker (streaming, chunk size validation, disk space checks)

### Notes
- Tests use Swift Testing framework (`import Testing`, `@Test` attribute)
- Test files located in `SnipNoteTests/` directory
- Use `@MainActor` for async tests requiring main thread
- Use `#expect()` for assertions instead of XCTest's `XCTAssert()`
- Run tests via Xcode: Cmd+U or Product → Test

---

## Tasks

## Phase 1: Critical Fixes (Week 1)

- [x] 1.0 Implement URLSession Timeout Configuration (FR-1)
  - [x] 1.1 Create a private `URLSession` instance variable in `OpenAIService` class
  - [x] 1.2 Initialize URLSession with custom `URLSessionConfiguration` in `init()` method
  - [x] 1.3 Set `timeoutIntervalForRequest = 120` (2 minutes per request)
  - [x] 1.4 Set `timeoutIntervalForResource = 600` (10 minutes total)
  - [x] 1.5 Replace all `URLSession.shared` calls with custom session instance
  - [x] 1.6 Write unit test: Verify timeout configuration is applied correctly
  - [x] 1.7 Write unit test: Verify timeout triggers after expected duration (mock test)

- [x] 2.0 Add Cancellation Support Throughout Pipeline (FR-2)
  - [x] 2.1 Add `Task.checkCancellation()` at start of `transcribeAudioInChunks()` method
  - [x] 2.2 Add cancellation check before each chunk in the chunk processing loop
  - [x] 2.3 Add cancellation check in `speedUpAudio()` before processing
  - [x] 2.4 Add cancellation check in `AudioChunker.createChunks()` before creating each chunk
  - [x] 2.5 Wrap `Task.checkCancellation()` failures to provide user-friendly error message
  - [x] 2.6 Ensure all temp files are cleaned up when cancellation occurs (verify `defer` blocks)
  - [x] 2.7 Write unit test: Cancel during chunk processing, verify no API calls made after cancellation
  - [x] 2.8 Write unit test: Cancel during audio processing, verify resources cleaned up
  - [x] 2.9 Write unit test: Verify CancellationError is thrown with proper message

- [x] 3.0 Improve Audio Processing Error Handling (FR-3)
  - [x] 3.1 Add new error case to `OpenAIError` enum: `audioProcessingFailed(String)`
  - [x] 3.2 Remove fallback `return audioData` from `speedUpAudio()` catch block (line 226)
  - [x] 3.3 Replace fallback with `throw OpenAIError.audioProcessingFailed(error.localizedDescription)`
  - [x] 3.4 Add detailed logging before throwing error with full error context
  - [x] 3.5 Update error message to be user-friendly: "Audio processing failed: [reason]. Please try again or contact support."
  - [x] 3.6 Ensure error propagates correctly through `transcribeAudio()` method
  - [x] 3.7 Write unit test: Verify `audioProcessingFailed` error thrown when speed-up fails
  - [x] 3.8 Write unit test: Verify no transcription API call made when audio processing fails
  - [x] 3.9 Write unit test: Verify error message contains actionable details

- [x] 4.0 Implement Enhanced Retry Logic (FR-5)
  - [x] 4.1 Update `shouldRetry()` method to check for `NSURLError` cases
  - [x] 4.2 Add retry for `NSURLErrorNetworkConnectionLost` (-1005)
  - [x] 4.3 Add retry for `NSURLErrorNotConnectedToInternet` (-1009)
  - [x] 4.4 Add retry for `NSURLErrorTimedOut` (-1001)
  - [x] 4.5 Add retry for `NSURLErrorCannotConnectToHost` (-1004)
  - [x] 4.6 Add retry for HTTP 408 (Request Timeout)
  - [x] 4.7 Add retry for HTTP 503 (Service Unavailable)
  - [x] 4.8 Add explicit NO retry for HTTP 400, 401, 403, 413
  - [x] 4.9 Add explicit NO retry for `CancellationError`
  - [x] 4.10 Write unit test: Verify each retryable error triggers retry
  - [x] 4.11 Write unit test: Verify non-retryable errors fail immediately
  - [x] 4.12 Write unit test: Verify exponential backoff timing (1s, 2s, 4s)

## Phase 2: High Priority (Week 1-2)

- [x] 5.0 Add Disk Space Validation (FR-4)
  - [x] 5.1 Create private helper method `checkDiskSpace(required: UInt64) throws` in `OpenAIService`
  - [x] 5.2 Use `FileManager.default.attributesOfFileSystem()` to get available disk space
  - [x] 5.3 Calculate required space: `(fileSize × 2) + (estimatedChunks × 2MB)`
  - [x] 5.4 Add 100MB safety buffer to required space calculation
  - [x] 5.5 Add new error case to `OpenAIError`: `insufficientDiskSpace(required: UInt64, available: UInt64)`
  - [x] 5.6 Call `checkDiskSpace()` at start of `transcribeAudioFromURL()` before processing
  - [x] 5.7 Call `checkDiskSpace()` at start of `AudioChunker.createChunks()` before chunking
  - [x] 5.8 Format error message: "Insufficient storage. Need [X]MB free, but only [Y]MB available."
  - [x] 5.9 Write unit test: Verify disk space check passes when sufficient space
  - [x] 5.10 Write unit test: Verify error thrown when insufficient space (mock FileManager)
  - [x] 5.11 Write unit test: Verify required space calculation is accurate

- [x] 6.0 Implement Background Task Expiration Handling (FR-6)
  - [x] 6.1 Add `backgroundTaskID` property to track active background task in relevant view model
  - [x] 6.2 Call `UIApplication.shared.beginBackgroundTask()` when transcription starts
  - [x] 6.3 Store task ID and register expiration handler
  - [x] 6.4 In expiration handler: Send local notification "Transcription paused - Open SnipNote to continue"
  - [x] 6.5 In expiration handler: Save current chunk index to `UserDefaults` with key `pausedTranscription_[meetingId]`
  - [x] 6.6 In expiration handler: Update meeting status to "paused" in database
  - [x] 6.7 Add meeting name to notification body for user context
  - [x] 6.8 Make notification actionable (tapping opens app to meeting detail)
  - [x] 6.9 On app foreground: Check for paused transcriptions in UserDefaults
  - [x] 6.10 Show resume dialog: "Continue transcription of '[Meeting Name]'?"
  - [x] 6.11 If user selects "Yes": Resume from saved chunk index
  - [x] 6.12 If user selects "No": Mark transcription as cancelled, clean up UserDefaults
  - [x] 6.13 Call `UIApplication.shared.endBackgroundTask()` when transcription completes or cancels
  - [x] 6.14 Add notification content to `NotificationService.swift` with proper category/identifier

## Phase 3: Optimizations and Polish (Week 2-3)

- [x] 7.0 Refactor to Memory-Efficient Chunk Streaming (FR-7)
  - [x] 7.1 Create new method in `AudioChunker`: `static func streamChunks() -> AsyncThrowingStream<AudioChunk, Error>`
  - [x] 7.2 Refactor `createAudioChunks()` logic to yield chunks one at a time using AsyncStream
  - [x] 7.3 Extract chunk from audio, yield it immediately, then continue to next
  - [x] 7.4 Update `transcribeAudioInChunks()` to use `for try await chunk in AudioChunker.streamChunks()`
  - [x] 7.5 Remove `chunks` array storage, process each chunk immediately
  - [x] 7.6 Ensure progress tracking still works correctly with streaming model
  - [x] 7.7 Update total chunks count estimation for progress updates
  - [x] 7.8 Verify temp file cleanup happens after each chunk (not at end)
  - [x] 7.9 Write unit test: Verify only one chunk in memory at a time (measure memory usage)
  - [x] 7.10 Write unit test: Verify progress updates correctly with streaming
  - [x] 7.11 Write unit test: Verify all chunks are processed in correct order

- [x] 8.0 Adjust Progress Weighting (FR-8)
  - [x] 8.1 Update progress calculation in `transcribeAudioInChunks()` method
  - [x] 8.2 Change chunking phase progress: `chunkProgress.percentComplete * 0.1` (was 0.3)
  - [x] 8.3 Change transcription phase base: `10.0 + (progress) * 90.0` (was 30.0 + 70.0)
  - [x] 8.4 Update progress formula: `10.0 + (Double(chunkNumber) / Double(totalChunks)) * 90.0`
  - [x] 8.5 Verify progress reaches exactly 100% at completion
  - [x] 8.6 Test with small file (1 chunk) to ensure progress updates correctly

- [ ] 9.0 Add API Cost Logging (FR-9)
  - [ ] 9.1 Add helper method `calculateTranscriptionCost(duration: TimeInterval) -> Double`
  - [ ] 9.2 Implement cost formula: `duration × $0.006 / 60` (gpt-4o-transcribe rate)
  - [ ] 9.3 Log cost in `transcribeAudioWithRetry()` after successful transcription
  - [ ] 9.4 Log format: `💰 [OpenAI] Transcription cost estimate: $[X.XX] ([Y]s @ $0.006/min)`
  - [ ] 9.5 Include original duration and processed duration (after 1.5x speed)
  - [ ] 9.6 Log file size before and after compression
  - [ ] 9.7 Log model used (gpt-4o-transcribe)
  - [ ] 9.8 Add cost logging to chunk transcription as well (per-chunk breakdown)

- [x] 10.0 Fix Transcript Merge Edge Cases (FR-10)
  - [x] 10.1 Locate `mergeChunkTranscripts()` method in `OpenAIService.swift`
  - [x] 10.2 Replace `transcripts.first?.trimmingCharacters()` with `transcripts.first(where: { !$0.trimmingCharacters().isEmpty })`
  - [x] 10.3 Add logging when skipping empty chunks: `⚠️ Chunk [N] returned empty transcript, skipping`
  - [x] 10.4 Ensure guard statement only returns empty if ALL chunks are empty
  - [x] 10.5 Write unit test: Verify merge succeeds when first chunk is empty but others have content
  - [x] 10.6 Write unit test: Verify merge returns empty only when all chunks are empty
  - [x] 10.7 Write unit test: Verify warning logged for empty chunks

- [ ] 11.0 Implement Chunk Size Validation (FR-11)
  - [ ] 11.1 Add size validation in `AudioChunker.createAudioChunks()` after extracting segment
  - [ ] 11.2 Check if `chunkData.count > maxChunkSizeBytes * 1.2` (20% tolerance = 1.8MB)
  - [ ] 11.3 If oversized: Log warning `⚠️ Chunk oversized: [X]MB, reducing duration`
  - [ ] 11.4 Reduce chunk duration by 50%: `let reducedDuration = chunkDuration * 0.5`
  - [ ] 11.5 Retry `extractAudioSegment()` with reduced duration
  - [ ] 11.6 Add maximum retry limit (2 attempts) to prevent infinite loops
  - [ ] 11.7 If still oversized after retries: Throw error `ChunkerError.chunkTooLarge`
  - [ ] 11.8 Add new error case to `ChunkerError` enum: `chunkTooLarge`
  - [ ] 11.9 Write unit test: Verify oversized chunks trigger duration reduction
  - [ ] 11.10 Write unit test: Verify error thrown if chunk remains oversized after retries
  - [ ] 11.11 Write unit test: Verify final chunk size never exceeds 1.8MB
