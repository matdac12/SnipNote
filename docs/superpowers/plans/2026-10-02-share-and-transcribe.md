# Share and Transcribe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Submit audio from the iOS share sheet, dismiss without opening SnipNote, and restore the finished meeting later.

**Architecture:** Reuse existing 15 MiB audio preparation and server upload reconciliation. An extension-safe shared source group owns durable per-share files, Keychain access-token snapshots, and per-share background sessions. An authenticated backend endpoint atomically creates an owned meeting and upload session; foreground recovery imports it into the existing SwiftData container.

**Tech Stack:** Swift 5, SwiftUI hosted by the existing UIKit extension controller, AVFoundation, Foundation URLSession, Security Keychain, Swift Testing, FastAPI/Pydantic, Python unittest, Supabase/Postgres.

**Spec:** `docs/superpowers/specs/2026-10-02-share-and-transcribe-design.md`. Read both documents before execution. This is one coordinated feature; notifications and Live Activities require separate plans.

## Global Constraints

- Keep Swift 5 language mode and 2-space indentation; do not add third-party dependencies.
- Set the Share extension deployment target to iOS 18.5; keep the app's existing deployment target unchanged.
- Use App Group `group.com.mattianalytics.snipnote`; keep SwiftData in the app's existing private container.
- Use at most 15,728,640 bytes per prepared audio chunk and at most 1,000 chunks per submission.
- Require an internet connection and valid server authentication before accepting a transcription.
- Capture the current cloud provider and transcription language once per share; default provider is `xai` and default transcription language is auto-detect (`nil`).
- Do not charge minutes on submission; retain the existing server completion debit and its idempotency behavior.
- Never persist bearer tokens or signed upload URLs in manifests, preferences, diagnostics, or screenshots.
- Include English and Italian copy, Dynamic Type, VoiceOver, and Reduce Motion support.
- Live Activities, completion push notifications, offline submission, in-extension sign-in/purchases, and on-device transcription are out of scope.

## Review Focus

- Two recordings with identical filenames must retain separate audio and identities (Task 1).
- App sign-out/account change during share preparation must prevent admission/scheduling for the stale owner (Tasks 2 and 4).
- Server accepts but its response is lost: retry must recover one meeting/session/job, with no extra balance commitment (Tasks 3 and 4).
- Extension termination between scheduling chunk tasks must preserve successful tasks and recover only missing chunks (Tasks 4 and 5).
- Job finishes before first app launch: import must preserve completed state and charge only once (Tasks 3 and 5).

---

## Execution and verification setup

Work in an isolated worktree at execution time using using-git-worktrees. Inspect app and backend Git state; create compatible branches in both repositories without changing unrelated work. App root is this repository; backend root is `../snipnote-transcription-service`. SQL migrations and SQL tests belong to the app repository's `supabase/` directory, matching the existing background upload work.

Select an available iOS 18.5-or-later simulator and assign its UUID to `SNIPNOTE_TEST_SIMULATOR`. Swift unit test command used below:

```bash
xcodebuild test -project SnipNote.xcodeproj -scheme SnipNote -destination "platform=iOS Simulator,id=$SNIPNOTE_TEST_SIMULATOR" -only-testing:SnipNoteTests/TEST_SUITE
```

Replace TEST_SUITE with the suite named in each task. A valid red run compiles and fails an assertion; a missing symbol is useful during initial interface introduction, but never count toolchain/provisioning errors as red evidence. Pass means exit 0 and all selected tests passed.

Backend commands run in its existing/isolated Python environment with `requirements-test.txt` installed and no production secrets. Use `python -m unittest discover -s tests -p 'TEST_FILE.py' -v`. SQL/concurrency tests run only against an isolated disposable database via `SNIPNOTE_TEST_DATABASE_URL`; never default to production. Discover the installed Supabase CLI with `--help` before migration commands. Save deployment and physical-device checks for the owner rollout decision.

## File map

- `SharedTranscription/ShareSubmission.swift`: immutable captured input, manifest and state/error contracts.
- `SharedTranscription/ShareSubmissionStore.swift`: App Group paths, atomic persistence and process locking.
- `SharedTranscription/ShareAudioPreparer.swift`, `PreparedAudioFile.swift`, `AudioMultipartBody.swift`: extension-safe extraction of existing file export/body preparation.
- `SharedTranscription/ShareSessionCredentials.swift`, `SharePreferences.swift`: shared Keychain snapshot and nonsecret defaults.
- `SharedTranscription/ShareSubmissionAPI.swift`: authenticated share registration wire client.
- `SharedTranscription/ShareUploadSession.swift`, `ShareSessionOwnership.swift`, `ShareSubmissionCoordinator.swift`: system transfer adapter and submission state machine.
- `SnipNote/ShareTranscriptionRecovery.swift`: app-only model import, repair, delegate draining and cleanup.
- `SnipNoteShare/ShareTranscriptionView.swift`: share panel; controller continues to load NSItemProvider input.
- Backend `share_transcriptions.py`, `share_models.py`: admission endpoint service and strict request contracts.
- App SQL migration generated by CLI: atomic admission; backend tests and app SQL tests pin authorization and billing.
- Existing coordinator/preparer, auth/preferences, AppDelegate, activation and Xcode memberships receive targeted integration only.

### Task 1: Durable share input and extension-safe preparation

**Files:** Create all first-three-bullet shared files above; modify `SnipNote/AudioChunker.swift`, `SnipNote/BackgroundUploadModels.swift`, `SnipNote/BackgroundUploadCoordinator.swift` and `SnipNote.xcodeproj/project.pbxproj`; create `SnipNoteTests/ShareSubmissionStoreTests.swift`, `ShareAudioPreparerTests.swift`.

**Interfaces:**
- `ShareSubmission: Codable, Sendable, Identifiable` stores every manifest field/state from the spec; `id` equals meetingID. `ShareSubmissionInput` contains ownerID, meetingID, title, createdAt, provider, language, duration, sourceURL. IDs/createdAt are generated once per share attempt and retained through Retry.
- `PreparedAudioFile: Codable, Equatable, Sendable` has index:Int, relativePath:String, expectedBytes:Int64, duration:Double, contentType:String, fileExtension:String. Use a typealias for legacy `PreparedUploadFile` to preserve callers.
- `ShareSubmissionStore.init(root: URL)`; `create(input: ShareSubmissionInput) throws -> ShareSubmission`; `save(_ submission: ShareSubmission) throws`; `load(ownerID: UUID) throws -> [ShareSubmission]`; `fileURL(_ relative: String, submission: ShareSubmission) throws -> URL`; `withLock<T>(meetingID: UUID, ownerID: UUID, _ body: () throws -> T) throws -> T`.
- `ShareAudioPreparer.prepare(source: URL, directory: URL, targetBytes: Int = 15_728_640) async throws -> [PreparedAudioFile]`; `AudioMultipartBody.write(source: URL, destination: URL, boundary: String) throws -> URL`.

- [ ] **Step 1:** Write `sameFilenameKeepsSeparateSources`, `rejectsTraversalAndSymlinkEscape`, `partialManifestWritePreservesLastVersion`, `corruptManifestDoesNotHideOtherShares`, `preparedFilesCoverDuration`, `multipartMatchesLegacyBytes`, and `cancellationRetainsOriginal`. Assertions: distinct meeting directories and source contents; invalid paths throw; last valid version loads after injected write failure; valid neighbor still loads; indices consecutive, bytes <=15_728_640, total durations within max(0.1,total*0.001); streamed body matches current multipart format; original still exists after export cancellation. Inject store write and capacity functions for deterministic disk/partial-write tests.
- [ ] **Step 2:** Run both named Swift suites; confirm red evidence for the missing behavior.
- [ ] **Step 3:** Implement the interfaces. Extract the durable AVAsset export algorithm from AudioChunker lines around 658 onward and streamed multipart writing from BackgroundUploadCoordinator; keep legacy delegates/logic. Enforce the existing capacity guard (source bytes *3 +100 MiB) for export, plus copy/body overhead capacity checks. Use POSIX locks around synchronous state mutation, never around async/network work. Stage original copying under a unique directory while the NSItemProvider temporary URL is valid; atomically rename the completed copy before marking it usable. Interrupted copies must fail recovery rather than submitting partial audio. Limit title to 200 characters and apply the spec fallback. Quarantine corrupt entries independently. Wire shared source membership into app/extension/tests, with extension-safe APIs enabled.
- [ ] **Step 4:** Run the new suites and existing audio boundary/background upload suites selected from `SnipNoteTests`; all must pass with unchanged legacy chunk coverage.
- [ ] **Step 5:** Commit app changes: `Add durable shared audio preparation`.

### Task 2: Read-only shared authentication and captured preferences

**Files:** Create `SharedTranscription/ShareSessionCredentials.swift`, `SharePreferences.swift`, `SnipNoteTests/ShareSessionCredentialsTests.swift`, `SharePreferencesTests.swift`; modify `SnipNote/AuthenticationManager.swift`, `CloudTranscriptionSettings.swift`, `LocalizationManager.swift`, both target entitlements and Xcode configuration; update `SUPABASE_SETUP.md`.

**Interfaces:**
- `ShareAccessSession: Codable, Sendable, Equatable` contains userID:UUID, accessToken:String, expiresAt:Date, generation:UUID.
- `ShareSessionCredentials.publish(_ session: ShareAccessSession) throws`; `read(now: Date) throws -> ShareAccessSession`; `invalidate(generation: UUID?) throws`; missing/expired cases throw typed `ShareSubmissionError.authenticationRequired`. Optional generation invalidates only matching snapshots; nil invalidates unconditionally.
- `SharePreferencesSnapshot: Codable, Sendable` contains ownerID:UUID, provider:String, language:String?, interfaceLanguage:String. `SharePreferences.read(ownerID: UUID) -> SharePreferencesSnapshot`; `publish(_ snapshot: SharePreferencesSnapshot)`.

- [ ] **Step 1:** Write tests `expiredSessionRequiresAppRefresh` (expiry <= now throws), `staleInvalidationKeepsNewGeneration`, `signOutClearsSnapshotBeforeAwait`, `refreshEventPublishesNewToken`, `defaultsAreXAIAndAutomatic`, `interfaceItalianDoesNotSelectAudioItalian`, `preferencesDoNotLeakAcrossOwners`. Assert token absent from persisted non-Keychain files/defaults. Inject Keychain operations and clock; never use a real token fixture.
- [ ] **Step 2:** Run both new suites; confirm failures.
- [ ] **Step 3:** Implement read-only extension credentials and publish from AuthenticationManager's launch/session/event paths, including token refresh events. Clear snapshot before awaiting sign-out, keep it cleared if sign-out fails until a new verified launch/session publication. Use the exact Keychain group/service/account and accessibility in the spec. Publish interface language/provider changes to App Group defaults; transcription language remains nil unless a real persistent app preference exists. Keep current private Supabase storage and refresh ownership unchanged. Configure shared Keychain provisioning and extension iOS 18.5 floor; document first post-upgrade app launch requirement.
- [ ] **Step 4:** Run the new suites and `CloudTranscriptionSettingsTests`; all pass. Verify extension membership does not pull in UIApplication/StoreKit/app singletons.
- [ ] **Step 5:** Commit: `Share session snapshot with audio extension`.

### Task 3: Atomic server admission and balance commitments

**Files:** Backend create `share_models.py`, `share_transcriptions.py`, `tests/test_share_transcriptions.py`, `tests/test_share_admission_database.py`; modify `main.py`, `upload_sessions.py` only for additive capability/service reuse, `deploy/env.example`, `DEPLOYMENT.md`. App create `supabase/tests/share_admission.sql` and the CLI-generated migration; update `SUPABASE_SETUP.md`.

**Interfaces:**
- `ShareTranscriptionRequest(UploadBootstrapRequest)` adds title:str (1–200 trimmed characters); rejects extra fields.
- Python `submit_share_transcription(user_id: str, request: ShareTranscriptionRequest) -> UploadSessionResponse` in share_transcriptions.py; injectable repository/storage/gate for tests.
- `POST /share-transcriptions` uses `verify_upload_user` and returns UploadSessionResponse. Capability response adds optional-compatible `share_transcription_enabled: bool`.
- RPC signature: `register_share_transcription(p_owner uuid, p_title text, p_session jsonb, p_files jsonb) returns uuid`; caller is backend service_role only. Session digest includes title and existing manifest fields.

- [ ] **Step 1:** Write HTTP/service tests `test_same_identity_returns_one_session`, `test_foreign_owner_cannot_admit`, `test_conflicting_title_or_manifest_returns_409`, `test_balance_gate_returns_402_without_rows`, `test_disabled_rejects_new_but_allows_existing_retry`, `test_extra_user_id_is_rejected`. Representative assertions:

```python
self.assertEqual(first.json()['session_id'], retry.json()['session_id'])
self.assertEqual(repo.meeting_count, 1)
self.assertEqual(repo.session_count, 1)
self.assertEqual(rejected.status_code, 402)
self.assertEqual(repo.meeting_count, 0)
```

Define injectable fake repository fixtures in this test file following test_upload_api.py; count committed rows, not just method calls.
- [ ] **Step 2:** Run `python -m unittest discover -s tests -p 'test_share_transcriptions.py' -v`; confirm the intended failures.
- [ ] **Step 3:** Write SQL/database tests: with balance=5 and duration=180, first admission succeeds, a distinct second admission fails without orphan meeting/session; retry of first succeeds without another hold; duration=61 requires 2; completion of first leaves balance=2 and exactly one debit; cancellation/expiry/failure releases admission capacity; queued sessions and jobs count once; unrelated nonterminal cloud job reduces available capacity. Use two DB connections and a barrier for simultaneous 3-minute submissions; assert exactly one commits. Test service_role execute privilege, denial to anon/authenticated, caller-selected foreign UUID, same-ID concurrent retry and deletion races. Include ambiguous response simulation by discarding the first committed result and retrying.
- [ ] **Step 4:** Discover CLI migration creation syntax, then generate `register_share_transcription`; use the exact returned `supabase/migrations/<timestamp>_register_share_transcription.sql` filename (timestamp is supplied by CLI, not invented). Implement the RPC transaction: immutable-owner check, owner balance-row creation/lock, deduplicated nonterminal commitment calculation, consistent digest, meeting/session/file insertion or identical retry. Keep Storage signing outside the DB transaction. Restrict EXECUTE to service_role and fix search_path; no client role receives this privileged RPC. Validate bounds even when the RPC is called directly. Reuse current server storage signing/reconciler/promotion and completion trigger. Set capability false unless both share flag and background eligibility allow new registration. Map errors exactly as the spec requires.
- [ ] **Step 5:** Apply migration to the disposable test database; run `psql "$SNIPNOTE_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/share_admission.sql` from app root, and both new Python suites from backend root with that database configured. Run existing upload/auth/job suites and `completion_billing_idempotency.sql`. Expected: all pass; no changes to production. Inspect generated migration privileges and actual outstanding status values against current schema.
- [ ] **Step 6:** Commit app SQL/docs and backend code separately: `Add atomic share transcription admission`.

### Task 4: Independent share upload scheduling and safe retries

**Files:** Create `SharedTranscription/ShareSubmissionAPI.swift`, `ShareUploadSession.swift`, `ShareSessionOwnership.swift`, `ShareSubmissionCoordinator.swift`, `SnipNoteTests/ShareSubmissionCoordinatorTests.swift`, `ShareUploadSessionTests.swift`; update shared models with wire decoding and typed errors from the spec.

**Interfaces:**
- `ShareSubmissionAPI.register(_ submission: ShareSubmission, credential: ShareAccessSession) async throws -> UploadSessionResponse`; `status(sessionID: UUID, credential: ShareAccessSession) async throws -> UploadSessionResponse`. Move UploadSessionResponse, UploadInstructions and UploadCapabilities into `SharedTranscription/ShareUploadContract.swift` and remove their original declarations; keep legacy usage intact and add the new capability with a false decoding default. No SupabaseManager references. Introduce `ShareSubmissionServing` protocol with the same register/status signatures; the production API conforms and tests inject a fake.
- `ShareUploadTransport` protocol: `tasks() async -> [ShareUploadTask]`, `schedule(request: URLRequest, body: URL, description: String) async throws`, `cancelAll() async`. `ShareUploadTask` contains description:String and suspended:Bool; production adapter resumes existing matching suspended tasks.
- `ShareSubmissionCoordinator.init(store: ShareSubmissionStore, api: any ShareSubmissionServing, credentials: ShareSessionCredentials, transport: any ShareUploadTransport)`; `submit(meetingID: UUID, ownerID: UUID) async throws -> ShareSubmission`; `cancelPreparation(meetingID: UUID, ownerID: UUID) async throws`. State observations are main-actor isolated; delegates persist before notifying UI. `ShareSessionOwnership.tryAcquire(directory: URL) throws -> ShareSessionOwnership?` takes a nonblocking OS lock on session-owner.lock; `release()` closes it; deinit releases. Keep ownership for the live URLSession delegate lifetime and never release solely to show a success screen. App recovery skips sessions still owned by the extension.

- [ ] **Step 1:** Write `offlineNeverReportsScheduled`, `staleOwnerNeverRegisters`, `generationChangesBeforeSchedulePreventTransfer`, `lostResponseRetryUsesSameMeetingID`, `partialSchedulingRetriesOnlyMissingChunks`, `duplicateCallbacksRemainIdempotent`, `registeredCancelDoesNotDeleteSource`, `manifestContainsNoURLOrBearer`, and `signedURLExpiryRetainsRetrySource`. Use a two-chunk fixture (indices 0,1); after crash following schedule(0), retry schedules only 1; no success until both appear resumed. Assert zero registration calls when auth generation changes before admission. If generation changes after remote commit, preserve registered manifest and cancel local scheduling; do not pretend the server commit was undone.
- [ ] **Step 2:** Run both suites; confirm red.
- [ ] **Step 3:** Implement API with injected URLSession and in-memory instructions, exact error-code mapping, and request timeout=30 seconds. Persist registrationAttempted before issuing a registration request; an ambiguous response cannot be treated as an unregistered orphan. Implement source→prepared→registered→scheduled ordering using Task 1 files and Task 3 endpoint. Re-read credential generation before each server registration/scheduling boundary; preserve a single ID on retry and persist ambiguous outcomes for recovery. Use session ID prefix/task descriptions/App Group configuration from the spec. Disable automatic discretionary waits for uploads, preserve current cellular allowance, set waitsForConnectivity and sessionSendsLaunchEvents. Stream multipart files; reconcile actual tasks before scheduling, resume suspended matching tasks, and register only missing tasks. Cancel removes unregistered artifacts only; never delete a possibly accepted submission.
- [ ] **Step 4:** Run both suites and existing BackgroundUploadCoordinator tests. Inspect runtime configuration under tests: sharedContainerIdentifier matches, identifiers differ per meeting, callback drain invokes completion exactly once. All pass.
- [ ] **Step 5:** Commit: `Schedule share uploads without app launch`.

### Task 5: App recovery and safe result import

**Files:** Create `SnipNote/ShareTranscriptionRecovery.swift`, `SnipNoteTests/ShareTranscriptionRecoveryTests.swift`; modify `SnipNote/SnipNoteApp.swift` AppDelegate/activation hooks, `AuthenticationView.swift`, `BackgroundUploadReconciler.swift` only for reuse seams, and `SupabaseManager.swift` only if import requires a focused helper.

**Interfaces:**
- `@MainActor ShareTranscriptionRecovery.activate(context: ModelContext, userID: UUID) async`; `stop()`, `signOut() async`; `handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) -> Bool` returns true only for owned share-session prefix.
- Uses Task 1 store, Task 4 API/transport, existing `SupabaseManager.getMeeting(id:)`, `RenderTranscriptionService.getJobStatus(jobId:)`, and `BackgroundUploadReconciler.applyResult(_:to:userID:jobID:)` for final mapping. Add injected fetch/status/sync closures for tests; do not introduce a second transcription implementation.

- [ ] **Step 1:** Write `completedBeforeFirstLaunchImportsAllOutputs`, `repeatedLaunchCreatesOneMeeting`, `activeAccountCannotImportForeignManifest`, `foregroundResumesMissingChunksOnly`, `callbackCompletionFiresOnceAfterPersistence`, `corruptNeighborDoesNotBlockRecovery`, `cleanupKeepsPlaybackOriginal`, and `ambiguousAdmissionIsLookedUpBeforeCleanup`. In in-memory SwiftData assert count=1 for stable meeting ID, processingState=.completed and all three text outputs preserved; injected save/upsert spy sees no pending overwrite of terminal remote state; client minutes debit spy count=0. At 7 days, registered/uncertain originals remain; confirmed never-registered orphan is removed. Unknown session identifiers fall through to legacy handler.
- [ ] **Step 2:** Run recovery suite; confirm red.
- [ ] **Step 3:** Implement one app session owner per meeting, background delegate handoff and foreground repair. Insert/refetch stable-ID model on main actor, import remote metadata/job before upsert, set cloud backend/source playback fields, and use existing terminal mapping. Reconnect extension session only after extension release/system handoff; foreground recovery must check a cross-process owner lease before connecting. Use Task 4 ShareSessionOwnership; process death releases the lock, and foreground recovery skips a still-owned session. Do not introduce another lease format or global timer. Route AppDelegate share events first, then existing handler; call system completion only after durable delegate work. Recheck active account after every awaited fetch. Stop polling at background, retain task callbacks. Keep legacy pending flag import intact. Cleanup follows spec retention/remote lookup rules.
- [ ] **Step 4:** Run recovery and existing shared-import/background-reconciler suites; all pass. Verify upgrade retains the private SwiftData configuration and old import behavior.
- [ ] **Step 5:** Commit: `Restore shared transcriptions on app return`.

### Task 6: Share-sheet UI and audio loading

**Files:** Create `SnipNoteShare/ShareTranscriptionView.swift`, `SnipNoteShare/Localizable.xcstrings`, `SnipNoteTests/ShareTranscriptionPresentationTests.swift`; modify `SnipNoteShare/ShareViewController.swift`, `Info.plist` and Xcode shared test memberships as needed; create `SnipNoteUITests/ShareTranscriptionUITests.swift` plus an app DEBUG-only preview host.

**Interfaces:**
- `ShareTranscriptionView` takes a main-actor observable `ShareTranscriptionPresentation` containing title, duration, provider, language, state, and `transcribe()`, `retry()`, `cancel()` callbacks. State enum cases: ready, preparing, authorizing, scheduled, error(ShareSubmissionError); derive controls/copy from state.
- Controller loads/copies one NSItemProvider file while the temporary URL is valid, captures Task 2 snapshot/preferences, and owns the presentation/coordinator. Hosting SwiftUI in the existing UIKit controller is allowed; no responder-chain app opening remains.

- [ ] **Step 1:** Write presentation tests: ready enables Transcribe; preparing disables repeat taps and enables Cancel; authorizing disables Cancel once registered; scheduled alone allows success dismissal; expired auth/offline/insufficient-minutes show exact spec English copy and Italian equivalents; no UI action opens the main app. UI tests use deterministic DEBUG preview fixtures for ready/preparing/error/scheduled, verify buttons and long title layout at largest accessibility text. Real extension execution remains a device check, not mocked UI proof.
- [ ] **Step 2:** Run presentation suite and new UI tests; confirm intended red failures.
- [ ] **Step 3:** Implement view/state mapping, accessibility identifiers, visible Retry/Cancel errors, VoiceOver scheduled announcement and 1-second dismissal. Keep temporary-file copy valid across provider callback. Reject multiple/non-audio/invalid-duration input visibly; never rely solely on filename extension. Filter audio via NSExtensionActivationRule. Remove openMainApp and pending flag writing from new extension. Link resource catalogs in correct targets, mirror app theme through captured preferences only if already supported; use system adaptive colors otherwise. Do not use invented percentage progress during local preparation.
- [ ] **Step 4:** Run presentation/UI suites and existing shared audio import launch/router tests. Capture English/Italian light/dark, long-title and largest-text preview screenshots; inspect truncation, focus order and tap targets. All pass with no app launch on successful share.
- [ ] **Step 5:** Commit: `Add share-sheet transcription panel`.

### Task 7: Integration rehearsal and owner release gate

**Files:** Create `docs/verification/2026-10-02-share-and-transcribe.md`; update `SUPABASE_SETUP.md`, backend `README.md`, `DEPLOYMENT.md`, and `deploy/env.example` with actual implemented contracts, provisioning, recovery and rollout details.

**Interfaces:** Uses the completed endpoint, migration, signed extension, existing worker/reconciler and owner-only flags. No new product behavior is added here.

- [ ] **Step 1:** Run the full backend unittest suite and SQL admission/completion regression checks on the disposable database; run app unit/UI tests and build the app plus embedded extension. Record command results and simulator UUID. Investigate new failures; do not broaden scope to unrelated refactors.
- [ ] **Step 2:** Rehearse disable-new-admissions while accepted sessions still finish; verify legacy `/jobs` and `/upload-sessions` compatibility and no exposed privileged RPC. Record cancellation/expiry releasing commitments without debit and completed jobs charging once. Do not deploy as part of plan execution without the rollout decision.
- [ ] **Step 3:** Provide the owner a signed-device checklist and run it when deployment is authorized: Voice Memos/Files, small and 150–400 MB originals, source-app return, long preparation memory/timing, lock/switch, connectivity interruption, URL expiry/repair, force quit/reopen, auth expiry/sign-out, concurrent shares, and English/Italian accessibility. Confirm server job starts/completes without another foreground API call after upload. Verify no two processes connect to one session concurrently. A failure preparing representative originals blocks release and requires a revised design.
- [ ] **Step 4:** Document measured outcomes, unverified checks, preexisting completion-trigger billing limits, exact flag rollback steps, and accepted-session preservation. Confirm wider rollout remains disabled until owner device acceptance. Do not label simulator-only results as background reliability verification.
- [ ] **Step 5:** Commit: `Document share transcription verification`.

## Self-review and handoff

Spec coverage: intent/UI/online gate (4,6); shared files/preparation (1); auth/preferences (2); backend admission/billing (3); transport/retry (4); import/account isolation/cleanup (5); accessibility and real-device release/rollback (6,7). Each Review Focus condition has a named test above. Future notifications and Live Activities intentionally have no implementation task.

This plan is a draft for human review. Recommend subagent-driven execution because the security, transactional admission and cross-process session boundaries benefit from separate task reviews. Review the spec and plan, then choose an execution approach before implementation.
