# Background Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upload prepared audio chunks while SnipNote is suspended, automatically queue one transcription, and verify the feature in an owner-only TestFlight trial on the existing production backend.

**Architecture:** Persist file-based upload manifests on iOS and use a background URLSession. New authenticated upload-session endpoints and an independent reconciler verify storage objects before transactionally creating a normal pending job. Rehearse locally, then add the new path to the existing production backend behind an owner-only server gate, retaining the legacy flow for ordinary use and rollback.

**Tech Stack:** Swift/SwiftUI, SwiftData, Foundation URLSession, AVFoundation, FastAPI, supabase-py, PostgreSQL, systemd, Swift Testing, Python unittest.

**Spec:** `docs/superpowers/specs/2026-09-30-background-upload-design.md`

## Global Constraints

- Keep small upload chunks and the existing provider/chunk transcription behavior.
- Support 150–400 MB originals through small chunks; do not introduce a 100 MB original-file limit.
- Use a 24-hour upload deadline; preserve verified files for reuse after expiration.
- Keep provider/language/duration fixed for an upload attempt; do not restore xAI single-request work.
- Preparation is not guaranteed while suspended; the UI must distinguish preparation from registered background upload.
- No APNs, Live Activities, pricing changes, or unrelated security-branch features.
- No production migration or deployment during this documentation revision; rehearse locally and review the concrete deployment before the owner-only trial.
- The owner runs Xcode builds manually; provide commands/checklists, do not execute builds here.
- Use the existing production database/storage/API and local SwiftData store; no separate staging infrastructure or environment-switching subsystem.
- Enable new background sessions only for the owner's verified account during the approximately 7–10-day trial; shipped builds keep their existing upload flow.
- Disabling the feature affects new sessions only; existing sessions can refresh credentials and finish without creating a second legacy job.
- Use new upload tables; no new transcription-job enum values or incompatible shared meeting states.

## Review Focus

- A flag can change after the app checks capabilities: bootstrap must enforce the gate, and disabling it must not duplicate or strand an existing session. Task 1/2/6 tests pin this.
- A crash between registration and task creation must leave recoverable intent, not duplicate uploads. Task 5 tests cover each boundary.
- Signed URLs can expire while iOS waits for connectivity: preserve successful files and refresh only unfinished credentials on wake. Task 2/5 tests pin this.
- Two reconcilers can see the same complete upload: one transaction must create one job and all metadata. Task 3 database tests pin this.
- A large original can fill local disk during preparation: stop clearly, retain the source, and avoid loading every chunk into RAM. Task 4 tests and Task 8 device checks pin this.

## File map and contract

App root: `/Users/mattia/Documents/Projects/Xcodestuff/SnipNote/SnipNote`.
Service root: `/Users/mattia/Documents/Projects/Xcodestuff/SnipNote/snipnote-transcription-service`.
All paths below are relative to their indicated root. Implement on isolated `codex/background-upload` branches after the worktree workflow; stage only task files, preserving unrelated local changes. The service's local revert commits remain intact. Do not merge stacked feature branches wholesale.

New app files: `BackgroundUploadSettings.swift` (local opt-out and capability selection), `BackgroundUploadModels.swift` (wire/durable types), `BackgroundUploadStore.swift` (atomic persistence), `BackgroundUploadAPI.swift` (authenticated capability/bootstrap/status), `BackgroundUploadCoordinator.swift` (session/delegates), `BackgroundUploadReconciler.swift` (SwiftData/status application).

New service files: `upload_auth.py` (verified identity), `upload_models.py` (wire validation), `upload_sessions.py` (bootstrap/status/signing), `upload_reconciler.py` (object verification), `upload_worker.py` (independent loop), plus matching `tests/test_*.py` files and a separate deployment unit.

`POST /upload-sessions`: Bearer authentication; body `{meeting_id, transcription_provider, language, duration, files:[{index, expected_bytes, duration, extension, content_type}]}`. Indexes must be consecutive from zero, sizes/durations positive and finite, and extensions/MIME allowed by the bucket. Server generates paths; reject client-supplied URLs/paths and conflicting repeat manifests with 409.

Response: `{session_id, status, job_id?, upload_deadline, files:[{index, verified, upload_url?, method?, headers?, expires_at?}]}`. Never return signed instructions for verified files. `GET /upload-sessions/{id}` returns the same shape without signed credentials; repeat POST refreshes missing-file instructions. Session states: `awaiting_upload`, `queued`, `expired`, `cancelled`. A reserved job UUID is internal until promotion, then appears as `job_id`. Existing `/jobs` endpoints and response types remain unchanged.

`GET /upload-capabilities`: Bearer authentication; returns `{background_upload_enabled: bool}` for the verified account. New session creation independently enforces the same server gate; return a structured `background_upload_disabled` error if disabled. Existing session refresh/status remain authorized by ownership when new creation is off. Do not fall back on generic authentication/ownership failures.

All HTTP signing details must be proved using the pinned Storage SDK and small disposable files under the owner's production account after deployment review; do not assume a signed URL accepts a particular verb, body encoding, or headers. No credentials/URLs in logs.

### Task 1: Feature selection and the existing upload fallback

**Files (app):** Create `SnipNote/BackgroundUploadSettings.swift`, `SnipNoteTests/BackgroundUploadSettingsTests.swift`; modify `SnipNote/SettingsView.swift` and English/Italian localization resources for a local opt-out. Do not restructure endpoint configuration or the SwiftData store.

**Interfaces:** `BackgroundUploadSettings` persists `useLegacyUpload: Bool` (default false); `shouldStartBackgroundUpload(serverEnabled: Bool) -> Bool` returns false when the opt-out is set or the server capability is false. Task 5 supplies the authenticated capability lookup; Task 6 applies selection only to new uploads, not recovery.

- [x] Write `serverDisabledUsesLegacyUpload`, `localOptOutUsesLegacyUpload`, and `serverEnabledAndNoOptOutUsesBackgroundUpload` tests. Assert the setting cannot enable background uploads when the server gate is off.
- [ ] Owner runs these Swift Testing tests in Xcode; record the initial failure.
- [x] Implement the setting and a localized opt-out control available when the feature is offered. Keep backend URLs, account tokens, app-group imports and the current SwiftData schema/store unchanged.
- [ ] Owner reruns tests; all pass. Confirm the current upload path remains selectable in the new build.
- [x] Commit `Add background upload opt-out`.

### Task 2: Upload-session persistence and authenticated API

**Files (service):** Create `upload_auth.py`, `upload_models.py`, `upload_sessions.py`, `tests/test_upload_sessions.py`, `tests/test_upload_auth.py`; modify `main.py`, `deploy/env.example` and pinned dependencies only if necessary.
**Files (app schema source):** Generate the migration under `supabase/migrations/` using the installed CLI's documented `migration new` command. Capture its generated filename in this plan when executing; do not invent a timestamp or create a second divergent service migration.

**Interfaces:** `verify_upload_user(authorization: str | None) -> str` returns a verified Supabase UUID; `bootstrap_upload(user_id: str, request: UploadBootstrapRequest) -> UploadSessionResponse`; `get_upload_session(user_id: str, session_id: str) -> UploadSessionResponse`. Supply a repository/storage adapter to tests instead of importing production clients.

- [x] Write unittest cases `test_repeated_bootstrap_returns_same_session`, `test_conflicting_manifest_returns_409`, `test_unverified_or_other_owner_rejected`, `test_disabled_bootstrap_does_not_affect_legacy_jobs`, `test_only_owner_can_start_background_session`, `test_flag_change_after_capability_check_rejects_new_session`, `test_flag_off_allows_existing_session_refresh`, `test_expired_refresh_preserves_verified_files`, and `test_signing_failure_leaves_retryable_session`. Assert a 24-hour deadline, captured provider/language, zero signed URLs for verified files, and no writes on authorization failure.
- [x] Run `python -m unittest discover -s tests -p 'test_upload*.py' -v` in the service environment; record expected failures.
- [x] Verify current Supabase changelog/Auth/Storage docs and CLI help, then implement the capability/session endpoints. Validate JWT remotely through the configured Supabase Auth service or use verified signing keys with issuer/audience/expiry checks; never trust decoded claims alone. Defaults: `BACKGROUND_UPLOAD_ENABLED=false`, `BACKGROUND_UPLOAD_ALLOWED_USERS` empty. Trial configuration contains only the owner's verified UUID; an empty allowlist never enables everyone. Existing session reads/refresh/finishing stay available when new-session creation is disabled.
- [x] Create `public.background_upload_sessions` with UUID ID/owner/meeting/reserved job ID, manifest digest, captured options, text status CHECK, deadline and timestamps; unique owner/meeting and reserved job ID. Create `public.background_upload_files` with session/index composite key, generated path, byte size, duration, MIME, verification timestamps; unique path. Keep statuses internal to these tables. Index unfinished-session scanning by last-check time and ID.
- [x] Enable RLS; revoke client/anon table writes and direct function execution. Use service-role-only access through the new authenticated API. No new policies on existing tables/bucket. Verify permissions with ordinary authenticated and anonymous roles on a disposable/local database; document service ownership checks separately.
- [x] Rerun new tests and existing `python -m unittest discover -s tests -v`; all pass. Commit `Add authenticated upload sessions` with the generated migration.

### Task 3: Verify chunks and promote atomically

**Files (service):** Create `upload_reconciler.py`, `upload_worker.py`, `deploy/snipnote-upload-reconciler.service`, `tests/test_upload_reconciler.py`; modify `upload_sessions.py`, `DEPLOYMENT.md`, `deploy/env.example`.
**Files (app schema source):** Generate a second migration for the promotion function through the documented CLI workflow.

**Interfaces:** `reconcile_uploads(limit: int = 100) -> ReconcileReport`; `verify_upload_files(session_id: str) -> list[VerifiedUploadFile]`. RPC `promote_background_upload(p_session_id uuid) returns uuid` locks that session and returns the existing/new job UUID. `VerifiedUploadFile` contains index, path, bytes and duration.

- [x] Write tests `test_missing_or_wrong_size_never_queues`, `test_two_promotions_create_one_job`, `test_metadata_failure_rolls_back_promotion`, `test_busy_transcriber_does_not_delay_upload_checks`, `test_expiration_does_not_delete_referenced_audio`, and `test_existing_legacy_job_is_not_overwritten`. Assert completed metadata is present before the pending job is visible; use a real disposable PostgreSQL database for the transaction/concurrency tests.
- [x] Run the new unittest module and database tests; record failures before implementation.
- [x] Implement exact-byte verification outside database transactions; update only successfully checked files. A short service-only SECURITY INVOKER RPC atomically creates existing-format `audio_chunks` or `recordings` metadata, inserts one normal pending job, links the meeting, and marks the session queued. Reject a conflicting existing job rather than overwriting it. Do not extend the job enum or change the legacy worker's selection contract.
- [ ] Run the reconciler in its own process every 20 seconds with bounded fair batches. Renew the same session/deadline on authenticated retry after expiry, preserving valid objects and paths. Cleanup checks session expiry plus active/completed references before deleting abandoned files; never delete queued session objects.
- [x] Verify object-size and promotion behavior against disposable local fixtures now; Task 7 proves the real production signed-upload transport. No paid transcription call is needed for the transport proof. All new/legacy tests pass. Commit `Queue verified background uploads`.

### Task 4: Durable file-based chunk preparation

**Files (app):** Modify `SnipNote/AudioChunker.swift`; create `SnipNote/BackgroundUploadModels.swift`, `SnipNote/BackgroundUploadStore.swift`, `SnipNoteTests/BackgroundUploadPreparationTests.swift`, `SnipNoteTests/BackgroundUploadStoreTests.swift`.

**Interfaces:** `PreparedUploadFile: Codable` has index, relative file path, expectedBytes: Int64, duration: Double, MIME and extension. `AudioChunker.prepareUploadFiles(from: URL, directory: URL) async throws -> [PreparedUploadFile]`. `BackgroundUploadManifest: Codable` has version, account/meeting UUIDs, optional session/job IDs, source relative path, captured settings and per-file states. `BackgroundUploadStore.save(_:) throws`, `load(userID: UUID) throws -> [BackgroundUploadManifest]` use atomic replacement.

- [x] Write tests `preparationPreservesOrderedAudioCoverage`, `smallAudioUsesStableFile`, `atomicSaveRetainsPreviousManifestOnFailure`, `diskFullRetainsSourceAndReportsPreparationFailure`, and `manifestPathsCannotEscapeUploadDirectory`. Assert no segment gaps/overlap are introduced and preserved files outlive the creating view.
- [ ] Owner runs these tests and records initial failures.
- [x] Implement file exports using current segmentation/encoding, but split a prepared file further if necessary to meet the existing 15 MiB target. Do not retain a `[Data]` containing all chunks. Use protected application-support storage accessible after first unlock, check available capacity, retain the original and capture account/options before preparation.
- [ ] Owner reruns tests with deterministic audio fixtures; all pass. Commit `Prepare durable upload chunk files`.

### Task 5: Background session and crash recovery

**Files (app):** Create `SnipNote/BackgroundUploadAPI.swift`, `SnipNote/BackgroundUploadCoordinator.swift`, `SnipNoteTests/BackgroundUploadCoordinatorTests.swift`; modify `SnipNote/SnipNoteApp.swift`.

**Interfaces:** `BackgroundUploadAPI.capabilities() async throws -> UploadCapabilities` with `backgroundUploadEnabled: Bool`; `bootstrap(_ manifest: BackgroundUploadManifest) async throws -> UploadSessionResponse`; `status(sessionID: UUID) async throws -> UploadSessionResponse`. Coordinator `start(meetingID: UUID, source: URL, options: UploadOptions) async throws`, `recover(userID: UUID) async`, `handleBackgroundEvents(identifier: String, completion: @escaping () -> Void)`. `UploadOptions` holds provider, language and duration. Inject transport/API/store seams for tests; use URLSession upload tasks from files in production.

- [x] Write tests `crashAfterBootstrapReschedulesMissingTasks`, `existingTasksAreReattachedWithoutDuplicateUpload`, `expiredURLRetriesOnlyUnverifiedChunk`, `duplicateCallbackCannotRegressState`, `accountMismatchNeverAppliesResult`, and `completionHandlerWaitsForDurableDelegateUpdates`. Assert task descriptions identify manifest/file and successful chunks never restart.
- [ ] Owner runs tests and records the initial failures.
- [x] Implement a stable background session identifier, persisted intent before scheduling, account-scoped task enumeration recovery, delegate updates and app-delegate reconnection. Use returned HTTP instructions exactly, `uploadTask(with:fromFile:)`, current cellular/network preferences and `waitsForConnectivity`. Persist failure and retry state; use at most three immediate retry attempts with 1/2/4-second backoff when execution is available, then expose recoverable retry. Refresh credentials on authenticated wake, not on an assumed permanent runtime.
- [ ] Never interpret force quit as proof the server failed. Ask session status before replacing transfers, and retain files until remote verification. Owner reruns tests; all pass. Commit `Run uploads through background URLSession`.

### Task 6: Integrate progress and result reconciliation

**Files (app):** Create `SnipNote/BackgroundUploadReconciler.swift`, `SnipNoteTests/BackgroundUploadRoutingTests.swift`; modify `SnipNote/CreateMeetingView.swift`, `SnipNote/MeetingDetailView.swift`, `SnipNote/MeetingSyncService.swift`, `SnipNote/RenderTranscriptionService.swift`, `SnipNote/SnipNoteApp.swift` and existing localization resources.

**Interfaces:** `BackgroundUploadReconciler.reconcile(context: ModelContext, userID: UUID) async`; all SwiftData changes execute on the main actor. Coordinator exposes observable snapshots with preparing/uploading/retry state and byte progress; a queued session hands off its ordinary job ID to the existing polling/result path.

- [x] Write tests `flagOffKeepsLegacyBootstrap`, `flagOnStartsCoordinator`, `unavailableCapabilitiesUseLegacyForNewUpload`, `disabledBootstrapBeforeSessionCreationUsesLegacy`, `flagOffOrOptOutDoesNotDuplicateExistingSession`, `networkFailureDoesNotStartLocalFallback`, `reopeningRestoresJobAndResultWithoutDetailView`, and `queuedPromotionUsesLegacyMeetingStates`. Assert provider/language stay captured, a successful remote result is applied once, and cancelled/deleted/account-mismatched transcriptions are not recreated by late callbacks.
- [ ] Owner runs tests and records initial failures.
- [x] For a new cloud upload, check capability and local opt-out before preparation; use the existing path when capabilities are unavailable/off or the user opts out. A structured disabled-bootstrap response permits legacy fallback only when no session exists. An ambiguous bootstrap/network failure must reconcile the idempotent session before choosing another route. Preserve local transcription. Persist/sync meeting ownership before server bootstrap and retry incomplete metadata sync without signing for nonexistent/foreign meetings. Show preparation until all file tasks are registered, then upload byte progress and clear permission to leave the app. Localize user-facing English/Italian messages.
- [ ] Reconcile at launch/foreground/session events. Gate fallback on a confirmed remote failure with no active upload, not a polling timeout. Release source/chunk files only when safe for recovery and existing playback. Owner reruns relevant cloud-routing, meeting-state and new tests; all pass. Commit `Integrate recoverable background upload flow`.

### Task 7: Local rehearsal and owner-only production deployment

**Files:** Service `DEPLOYMENT.md`, `deploy/env.example`, `deploy/snipnote-upload-reconciler.service`; app `docs/superpowers/reports/2026-09-30-background-upload-verification.md`.

- [x] Rehearse migrations, authorization and concurrent promotion on a disposable local database with synthetic fixtures. Record before/after schema and legacy API/worker smoke tests. Verify new objects add no required field/status changes to existing tables, no destructive DDL, and no unexpected access grants. Use bounded lock/statement timeouts so a blocked migration aborts rather than holding traffic indefinitely.
- [ ] Complete backend tests and owner-run relevant Swift checks, then request an independent whole-change code review through the review skill before production deployment. Resolve substantive findings and repeat affected checks.
- [x] Read-only preflight the existing Supabase project and `ssh omni` deployment: current schema/revision, backup availability, service health and available disk. Prepare the exact additive migration diff, deployment revisions and flag configuration for review. Keep the existing database, bucket, accounts, API URL and transcription worker; no new cloud project, cloned functions or transcription concurrency settings.
- [ ] After the owner approves that concrete deployment, apply the reviewed migrations and deploy the compatible API plus lightweight independent upload reconciler on the existing VPS. Start with `BACKGROUND_UPLOAD_ENABLED=false`; confirm the legacy app/job flow still works before enabling anything.
- [ ] Set `BACKGROUND_UPLOAD_ALLOWED_USERS` to only the owner's verified UUID and enable the feature. Prove signed-upload HTTP instructions using tiny disposable owner-scoped files, including wrong-size verification and interrupted retries. Remove transport test artifacts; do not submit transport-only probes for paid transcription. Confirm the independent reconciler operates during a long ordinary job. Record revisions, migration IDs and results without secrets.
- [ ] Rehearse switching the feature off: a new upload uses the legacy path, an existing session still refreshes/finishes, and completed transcripts remain accessible. Keep the previous API revision available. Document that full code rollback removing session support pauses unfinished uploads; preserve files/manifests and restore compatible support for recovery instead of spawning duplicate legacy jobs. Leave additive tables in place. Commit `Document owner-only upload rollout`.

### Task 8: Owner TestFlight trial and App Store release decision

**Files:** App verification report from Task 7, plus a focused owner checklist; service `DEPLOYMENT.md` rollout section.

- [ ] Give the owner ordinary TestFlight archive instructions and single-test selections. Owner builds and archives; verify app/share extension versions match, endpoints remain production, and the owner's account receives the new capability while a non-owner fixture is denied. Do not create a staging scheme or change the SwiftData schema/store.
- [ ] Owner tests actual small audio and 150/400 MB originals on a physical iPhone: preparation, lock, switch apps, network drop/reconnect, expired signing credentials, force quit/reopen, low disk and account switch. Record expected-versus-observed results, failed-chunk retries, peak preparation memory/disk, server queueing while suspended and transcript arrival on reopen.
- [ ] Run an approximately 7–10-day owner-only trial while continuing ordinary app use on the same account and data. Exercise the local opt-out to keep the existing flow usable. Smoke-test the shipped App Store build against the upgraded compatible backend, including ordinary promoted records; verify replacing TestFlight with the shipped app preserves existing local data. Restore TestFlight and confirm unfinished-session recovery when needed. No additional tester recruitment or load-testing infrastructure is required.
- [ ] Consolidate automated checks, independent review and device evidence. If trial defects required changes, rerun affected tests and review the fixes before the App Store release decision; do not repeat unchanged checks solely because the trial ended.
- [ ] After the trial, present device evidence and remaining defects for the App Store release decision. The compatible backend/migrations are already deployed; widening the server allowlist or shipping the new app is a separate activation decision, not another infrastructure migration. Keep the feature switch and local opt-out available after release.
- [ ] Commit the acceptance evidence and report remaining device/resource blockers honestly. No success claim without observed physical-device behavior.

## Execution and review handoff

Recommended execution: **Native** in this session, task by task, followed by an independent whole-change review. These tasks share a tight API/manifest contract across two repositories; keeping implementation context together reduces interface drift. The owner supplies Xcode/device evidence at the indicated checks.

Implementation started 2026-10-01 inline on isolated codex/background-upload branches. Simulator checks now run here by user authorization; physical-device checks remain pending; no subagents, production changes, merge or activation authorized. Production deployment review concerns the concrete migration/deployment result; it does not stop already-authorized reversible code work. Implementation changes are recorded below; production actions remain pending approval.

## Execution record

- Task 1: setting/tests/localized opt-out implemented; owner Swift RED/GREEN pending.
- Task 2 migration generated: `20261001064743_background_upload_sessions.sql`. Backend RED: missing new modules; GREEN: 13 upload tests, 33 full-suite tests. Permission rehearsal follows in Task 3.
- Task 3 migration generated: `20261001065143_promote_background_upload.sql`. Local PostgreSQL rehearsal verifies concurrent single promotion, metadata rollback, legacy conflicts, and denied client roles.
- Task 4: durable manifests/protected exports and fixtures implemented; Swift checks owner-pending.
- Task 5: background URLSession/crash recovery implemented. User authorized subsequent Xcode checks on iPhone 17; Tasks 1/4/5 selected tests passed (14). Backend 44/44. Device behavior unverified.
- Task 6: integrated routing, localized byte progress, app-level recovery and durable result-sync retry; 26 selected Swift tests passed. Full unit suite has pre-existing DOCX export failure reproduced on main.
- Task 7: local rehearsal/backend checks and read-only VPS/Supabase preflight done; concrete deployment prepared in service DEPLOYMENT.md and app report. Production migration/deploy/activation pending owner approval. Database backups unconfirmed; independent review pending (no delegation authorized).
- Task 8: archive commands, single-suite selections and focused physical-device/trial checklist delivered in the verification report; archive, production transport, 7–10-day trial and App Store decision pending.

- Final self-review fix pass: late status/cancellation races, suspended task recovery, bounded cross-file retries, Auth routing, reconciliation reentrancy and interrupted source-copy recovery observed RED→GREEN. Final iPhone 17 selections: 33/33. Full unit suite: 107 passed, one skipped, one pre-existing DOCX failure. Backend: 49/49 including six real PostgreSQL tests.
- Current code: app `55b7598`; service `754fc29`. Final evidence, exact commands, exhaustive rulings and pending production/device checks are in `docs/superpowers/reports/2026-09-30-background-upload-verification.md`. Checked steps indicate implemented/observed work only; mixed owner/production steps remain open.

- Approved trial rollout 2026-10-01: owner authorized production steps and confirmed backup readiness. Both reviewed migrations applied, history aligned to source IDs; API/reconciler deployed and only verified owner account enabled. Production signed multipart/retry/wrong-size/expiry-renewal/feature-off proofs passed and fixtures cleaned without paid jobs. Transport regression fixed at service `f328b6d`, backend 50/50. See report's approved-rollout section for precise evidence and backup limitations. Main remains unmerged/unpushed.
- Task 8 first check now uses direct Xcode installation, per owner request; physical iPhones currently unavailable, so device connection/run and suspension/results evidence remain pending. Independent review, shipped-app end-to-end smoke, long-job coexistence, TestFlight/trial and wider release decisions remain pending.

- Physical-phone checkpoint 2026-10-01: connected iPhone 16 paired, signed physical build succeeded, original-bundle app installed and launched without debugger. Owner account/data confirmation and actual preparation/lock/reopen/transcript observations remain pending; exact install commands and evidence in report.

- First physical-phone trial: owner confirmed existing login/meetings and Home Screen before upload bytes reached total. Server verified 7,870,403 bytes and queued the ordinary job at 08:36:17 UTC while owner remained outside. Upload/promotion observed; unchanged xAI transcription failed after five retries at 08:42:21 UTC (invalid response text). Successful transcript application and owner reopen status remain unverified; no provider change or duplicate job initiated. Details in verification report.

- Owner reopened and saw invalid-text failure. Follow-up root cause: a redundant 369 ms tail already covered by prior overlap; authorized diagnostic xAI call returned HTTP 200 with empty text. Service boundary regression RED→GREEN, full backend 52/52. Minimal chunk-loop fix prepared; production worker change and same-job retry pending approval (original rollout preserved worker). Successful transcript arrival remains unverified.
