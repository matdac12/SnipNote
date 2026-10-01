# Quiet Continuity Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give SnipNote one calm analysis surface with an unmistakable preparation-to-safe-background-upload handoff.

**Architecture:** A pure value-based resolver derives presentation from the existing meeting, upload manifest, and server status. A dedicated SwiftUI view renders it without owning transport or SwiftData mutations. Narrow initiation, legacy-routing, and status-persistence hooks keep that presentation truthful across navigation and reopening.

**Tech Stack:** Existing Swift 5.0 project, SwiftUI, SwiftData, Swift Testing, XCTest UI tests; no new dependencies or platform upgrades.

**Spec:** `docs/superpowers/specs/2026-10-01-analysis-quiet-continuity-design.md` (read in full before executing).

## Global Constraints

- “Once preparation finishes **and background upload tasks are registered**, the user can switch apps or lock the phone while upload continues.”
- “Upload completion is not the permission boundary.”
- “No overall preparation-to-results percentage is introduced.”
- “Visual timers never control functional transitions.”
- “Returning must not replay initiation or the permission milestone, restart work, or reset progress.”
- “The legacy foreground upload route must likewise retain its own keep-open requirements.”
- “No service API, database schema, upload transport, retry-budget, account-isolation, or audio-retention change is required by this design.”
- “All actions retain descriptive labels and at least 44-point touch targets.”
- “Do not add waveform animation, stage-step navigation, particles, glowing orbs, or extra nested cards.”
- Preserve native navigation, existing results, English/Italian app-language selection, local processing capabilities, and deployment/build settings.
- No Live Activities, new notifications, publishing, deployment, merging, or release changes.
- Execution chosen by owner: **native**, one implementer in the executing session. Preserve the owner's **no-subagents** constraint, including final review: do a separate author review, label that limitation, and do not describe it as independent review.

## Review Focus

1. Cloud does not necessarily mean background: short imports and recorded cloud audio can use foreground processing; permission must remain keep-open (Tasks 1, 3).
2. A 100% byte count can precede server confirmation, and a malformed/empty file list must not authorize leaving (Task 1).
3. Reopening or a failed status poll must not regress confirmed server work to uploading; an old job's cached state must never leak into another job (Tasks 1, 3).
4. A queued manifest can mask a running or failed server job; remote completion can precede local result application (Tasks 1, 3).
5. Rapid permission changes, repeated polling, and navigation reentry must not repeat VoiceOver announcements or imply that retry recovery runs unattended (Tasks 1, 2, 4).

---

## Execution setup and repository evidence

This is one app presentation feature, not separate app/service projects. Service repo is read-only reference: `/Users/mattia/Documents/Projects/Xcodestuff/SnipNote/snipnote-transcription-service`, baseline `471ae67`. App baseline `12e6323`; recheck HEAD and relevant changes before execution. Do not reset newer work.

Use `using-git-worktrees` at execution time, reusing a suitable managed worktree or creating an isolated branch such as `codex/analysis-quiet-continuity`. Read AGENTS.md. Inspect `git status --short` first: planning-time unrelated changes include `.DS_Store`, `skills-lock.json`, Supabase temporary/skill files, and an app marketing-version change to 2.9. The catalog may also have unrelated concurrent edits. Preserve all of these; never stage unrelated hunks with this feature. Reinspect the catalog before adding keys and retain existing translations. Spec and plan may still be untracked: copy their exact contents into the isolated checkout before using them; include only those documents in a documentation commit if needed. Keep the durable preview available at the path in the spec.

Run `executing-plans`' workspace/ledger helpers, read both documents, keep SNIPNOTE_RUN_LIVE_TESTS unset (no real minute debit), record the shared-interface preflight, and resume from ledger/commits after compaction. Each task below ends with its specified test command; retain RED/GREEN output and deviations as rulings. Commits are local only.

Verified planning-time evidence: `xcodebuild -list -project SnipNote.xcodeproj` resolved packages and lists scheme `SnipNote`; synchronized source/test folders automatically include new files. `xcrun simctl list devices available` includes iPhone 16 / iOS 18.5 and iPad mini (A17 Pro) / iOS 18.5. Those discovery commands needed sandbox escalation for Xcode caches/CoreSimulator. A sandbox failure is not a product test failure; use authorized escalation rather than changing the project.

For every task command below, run from the implementing checkout:

```bash
xcodebuild test -project SnipNote.xcodeproj -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:SnipNoteTests CODE_SIGNING_ALLOWED=NO
```

Call this **UNIT** below; substitute the exact full command, adding the named `-only-testing:SnipNoteTests/<Suite>` filter instead of the broad test-target filter for RED/GREEN. If this simulator is unavailable in the later session, choose an installed supported simulator, record its exact destination, and use it consistently. Never raise deployment targets to satisfy skill defaults.

## File map and locked interfaces

| File | Responsibility |
| --- | --- |
| Create `SnipNote/AnalysisPresentation.swift` | Equatable semantic presentation value; nested phase/guidance enums and progress fields |
| Create `SnipNote/AnalysisPresentationInput.swift` | Plain input value and main-actor Meeting adapter; no managed model stored |
| Create `SnipNote/AnalysisPresentationResolver.swift` | Pure precedence, progress sanitization, known server-stage normalization |
| Create `SnipNote/AnalysisAnnouncementTracker.swift` | Pure, view-lifetime transition/announcement deduplication |
| Create `SnipNote/AnalysisStatusView.swift` | Accessible themed rendering and narrowly scoped motion |
| Modify `SnipNote/Theme.swift`, `SnipNote/LocalizationManager.swift`, `SnipNote/Localizable.xcstrings` | Semantic success colors and complete localized surface copy |
| Modify `SnipNote/CreateMeetingView.swift`, `SnipNote/BackgroundUploadRouting.swift` | Truthful initial preparing state and notification of legacy selection |
| Modify `SnipNote/MeetingDetailView.swift`, `SnipNote/BackgroundUploadReconciler.swift` | Integration, retained status, nonterminal presentation metadata, stable view identity |
| Create `SnipNote/AnalysisPreviewFixtures.swift`, `SnipNote/AnalysisPreviewHostView.swift` | DEBUG-only deterministic screen fixtures; no service calls |
| Modify `SnipNote/SnipNoteApp.swift` | DEBUG launch hook for isolated UI fixtures |
| Create `SnipNoteTests/AnalysisPresentationTests.swift`, `AnalysisAnnouncementTests.swift`, `AnalysisLocalizationTests.swift` | Meaningful state, announcement, copy regressions |
| Modify `SnipNoteTests/BackgroundUploadRoutingTests.swift` | Legacy callback timing and safe restoration regressions |
| Create `SnipNoteUITests/AnalysisExperienceUITests.swift` | Screen-level safety and transition regressions without login |

Use 2-space indentation, one primary type per file, private implementation details, and no force unwraps. Do not restructure the large existing views outside their analysis presentation.

## Task 1: Resolve truthful analysis states

**Files:** Create the first three production files and `SnipNoteTests/AnalysisPresentationTests.swift`.

**Interfaces:**
- `AnalysisPresentationInput.init(meetingID: UUID, jobID: String? = nil, backend: TranscriptionBackend? = .cloud, processingState: ProcessingState = .transcribing, processingPhase: MeetingProcessingPhase = .preparing, upload: BackgroundUploadManifest? = nil, serverStatus: JobStatus? = nil, serverStage: String? = nil, canRetry: Bool = false, canRetryAnalysis: Bool = false)`.
- `@MainActor AnalysisPresentationInput.init(meeting: Meeting, upload: BackgroundUploadManifest?, serverStatus: JobStatus?, serverStage: String?)` copies fields only; when the supplied serverStage is nil/empty, use meeting.currentStageDescription as persisted presentation evidence only for an accepted job. Never classify arbitrary local stage text as server state.
- `AnalysisPresentation.Phase`: `preparing`, `uploading`, `confirmingUpload`, `queued`, `transcribing`, `analyzing`, `processing`, `pausedUpload`, `failed`, `foreground`, `results`.
- `AnalysisPresentation.Guidance`: `keepOpen`, `safeUpload`, `safeServer`, `needsAttention`, `none`.
- `AnalysisPresentation` stores `meetingID: UUID`, `jobID: String?`, `phase: Phase`, `guidance: Guidance`, `uploadFraction: Double?`, `sentBytes: Int64?`, `totalBytes: Int64?`, `canRetryUpload: Bool`; `canLeave: Bool` is true only for safeUpload/safeServer. Equatable conformance for the value and nested enums.
- `AnalysisPresentationResolver.resolve(_ input: AnalysisPresentationInput, previous: AnalysisPresentation? = nil) -> AnalysisPresentation`.
- `AnalysisPresentationResolver.serverPhase(status: JobStatus, stage: String?) -> AnalysisPresentation.Phase` is shared with Task 3.

- [ ] **Step 1: Write resolver tests with real manifest values.** In the test suite define `upload(phase: BackgroundUploadPhase = .uploading, sent: Int64 = 0, total: Int64 = 100, registered: Bool = true) -> BackgroundUploadManifest`: one `PreparedUploadFile`, state `.scheduled` when registered, `.pending` otherwise, chosen sent bytes. Set manifest meetingID to the tested ID. No transport/network mocks are needed here.

```swift
@Test func safeAtZeroBytesOnlyAfterRegistration() {
  let id = UUID()
  var ready = upload(sent: 0); ready.meetingID = id
  let safe = AnalysisPresentationResolver.resolve(.init(meetingID: id, upload: ready))
  #expect(safe.phase == .uploading && safe.canLeave)
  #expect(safe.uploadFraction == 0)
  ready.files[0].state = .pending
  let waiting = AnalysisPresentationResolver.resolve(.init(meetingID: id, upload: ready))
  #expect(waiting.phase == .preparing && !waiting.canLeave)
}
```

Add named tests with these assertions: `noSnapshotStartsPreparing` → preparing/keepOpen/no fraction; `allBytesSentMeansConfirmation` → confirmingUpload/safeUpload/fraction 1, not results; `emptyOrZeroTotalFilesNeverAuthorizeLeaving` → keepOpen/no fraction even if the existing allSatisfy property returns true; `retryOverridesStaleSafeState` → pausedUpload/needsAttention/canRetryUpload, no safe message; `localAndForegroundCloudNeverInheritSafety` → foreground/keepOpen without manifest and no accepted server job; `foreignManifestIsIgnored` → mismatched meeting IDs do not confer permission; `cancelledManifestDoesNotConferSafety` → needsAttention; `terminalMeetingWins` → completed model/results regardless of stale manifest, failed model/failed without safe guidance.

Add `queuedManifestUsesRunningJob` → queued snapshot plus processing/transcription stage yields transcribing/safeServer; `serverFailureWinsQueuedManifest` → failed/no safety; `remoteCompleteWaitsForAppliedResults` → completed remote status with transcribing model yields processing/safeServer, not results; `statusGapPreservesSameJobOnly` → nil status retains previous server phase only for the same meeting/job and no contradictory retry/terminal evidence; `freshReturnUsesPersistedPhase` → jobID plus persisted generatingSummary yields analyzing/safeServer without prior view state; `stalledBytesDoNotAdvance` → identical byte samples produce identical fraction; `malformedProgressIsBounded` → negative sent clamps to 0, excess sent clamps to total, nonpositive total gives no fraction.

- [ ] **Step 2: Run UNIT filtered to `AnalysisPresentationTests`.** Expected RED: missing presentation types, not a simulator/cache error.
- [ ] **Step 3: Implement the interfaces above.** Resolver precedence: terminal model; explicit local route; matching active manifest recovery/cancellation; manifest preparing/unregistered; registered upload/confirmation; accepted server job (queued snapshot or existing jobID); foreground fallback. Server failure overrides queued presentation. A jobID is created after legacy upload acceptance, so pending with a jobID means queued, not upload. Use previous only to bridge missing server metadata for the same identity; fresh input wins, and previous safety never overrides recovery or an absent transfer guarantee.

Normalize known service strings from `../snipnote-transcription-service/jobs.py` and `transcribe.py`: prefixes `Transcribing`, `Merging transcripts`, `Combining transcripts`, or `Transcription complete` → transcribing; `Generating summary`, `Summary generated`, `Generating overview`, or `AI content generated` → analyzing; other processing-stage strings → processing. Ignore case and trim whitespace. Unknown/nil stage must show generic processing, never raw English server text or invented percentage/ETA. Add parameterized tests for these exact strings and an unknown string. Persisted generatingOverview/generatingSummary can restore analyzing when live status is absent.

- [ ] **Step 4: Run UNIT filtered to `AnalysisPresentationTests`.** Expected GREEN, no skipped resolver tests.
- [ ] **Step 5: Commit the four task files.** `git commit -m "Add analysis presentation resolver"`. End-of-task contract: UNIT filtered to `AnalysisPresentationTests`.

## Task 2: Build the quiet, localized, accessible surface

**Files:** Create `AnalysisStatusView.swift`, `AnalysisAnnouncementTracker.swift`, announcement/localization tests; modify Theme, LocalizationManager, and catalog.

**Interfaces:**
- Consumes Task 1's `AnalysisPresentation`.
- `AnalysisStatusView.init(presentation: AnalysisPresentation, retryUpload: (() -> Void)? = nil)`; ThemeManager and LocalizationManager are environment objects. No transport or model mutations in the view.
- `AnalysisAnnouncementTracker.mutating func update(_ presentation: AnalysisPresentation) -> AnalysisPresentation?`: return a presentation only for meaningful phase/guidance changes after seeding; initial update returns nil; bytes alone return nil. Seed a changed meeting or a different nonnil job identity without announcing historic permission. A nil→assigned jobID for the same live meeting is ordinary handoff, not reentry: announce the new stage once without repeating unchanged safe guidance.
- `AppTheme.successColor: Color`, `AppTheme.successBackgroundColor: Color`. Light foreground RGB `(0.137, 0.424, 0.286)`, background `(0.918, 0.957, 0.929)`; dark foreground `(0.722, 0.882, 0.776)`, background `(0.125, 0.227, 0.169)`. These match the approved preview; measure composed text contrast in verification, adjust only if needed and record it.

- [ ] **Step 1: Write failing announcement and catalog tests.** `firstRenderDoesNotAnnounce`, `handoffAnnouncesOnce`, `bytesAndRepeatedPollsDoNotAnnounce`, `reentrySeedsWithoutAnnouncement`, `retryThenReregisterAnnouncesNewSafety`, `differentJobSeedsWithoutOldPermission`, `jobAssignedDuringLiveFlowAnnouncesQueueOnly` (same meeting, nil→jobID, safeUpload→safeServer: one queue-stage announcement, no repeated permission sentence).

```swift
@Test func handoffAnnouncesOnce() {
  let id = UUID()
  var tracker = AnalysisAnnouncementTracker()
  let preparing = AnalysisPresentationResolver.resolve(.init(meetingID: id))
  #expect(tracker.update(preparing) == nil)
  var manifest = upload(sent: 0); manifest.meetingID = id
  let safe = AnalysisPresentationResolver.resolve(.init(meetingID: id, upload: manifest))
  #expect(tracker.update(safe)?.guidance == .safeUpload)
  #expect(tracker.update(safe) == nil)
}
```

Here the test's private upload helper has Task 1's same manifest contract; keep shared test helpers in a single test-support file only if actually reused. Catalog tests load built en/it bundles with `Bundle.main.path(forResource:ofType:)` and `Bundle(path:)`, using `#require` to fail rather than skip missing bundles. Assert preparation and safe-upload title/detail equal the spec strings exactly in both languages. Assert every key used by the new view resolves to translated text rather than its key. Do not mutate shared app-language UserDefaults in parallel tests.

- [ ] **Step 2: Run UNIT with both `-only-testing:SnipNoteTests/AnalysisAnnouncementTests` and `-only-testing:SnipNoteTests/AnalysisLocalizationTests` filters.** Expected RED: missing tracker/copy.
- [ ] **Step 3: Implement the tracker and localized rendering.** Add catalog keys under `analysis.*`: `phase.preparing/uploading/server`, `title.preparing/uploading/confirming/queued/transcribing/analyzing/processing/paused/failed`, `guidance.keep_open.title/detail`, `guidance.safe.title`, `guidance.upload.detail`, `guidance.queue.detail`, `guidance.server.detail`, `guidance.attention.title/detail`, `action.retry`, and `progress.accessibility`.

Use the spec's EN/IT copy verbatim. Supplemental exact copy: processing title “Processing your meeting” / “Elaborazione della riunione”; failure “Analysis needs attention” / “L’analisi richiede attenzione”; attention title “Open SnipNote to continue” / “Apri SnipNote per continuare”; attention detail “Check your connection and try again.” / “Controlla la connessione e riprova.” Progress accessibility format “Audio upload: %d%%” / “Caricamento audio: %d%%”. Phase labels “Preparing / Uploading / On the server” and “Preparazione / Caricamento / Sul server”. Format percentage and byte counts with the selected app locale, not an English string interpolation. Recovery details/actions specific to terminal failure remain owned by the existing error UI in Task 3; do not claim audio retention generically.

Use system typography: stage title `.title2` semibold; phase `.caption` medium; guidance title `.subheadline` semibold and detail `.footnote`; byte count `.caption` with monospaced digits. Use `@ScaledMetric` for a base 56-point upload percentage. Horizontal insets 24 points, title/progress separation 24–32, guidance padding 16, guidance radius theme.cornerRadius, line height 4. Maximum content width 480 points on iPad; use minimum visual-space reservation, not fixed total heights. Check Dynamic Type wrapping before tightening spacing.

Use one indeterminate line treatment only; no simultaneously breathing hero. For Reduce Motion show a static activity mark and localized stage with no repeating animation. Stage/guidance opacity changes and upload fill use `.easeOut(duration: 0.25)` scoped to their actual values; never animate the whole view on byte updates. Retain numeric measurement without spring overshoot. Use `.monospacedDigit()`, SF Symbols only, and text rather than color as the safety cue.

Expose identifiers `analysis.stage`, `analysis.guidance.title`, `analysis.guidance.detail`, `analysis.upload.progress`, `analysis.retry`. Progress uses accessible value, decorative graphics are hidden, action hits are at least 44 points. Call tracker in onChange, seed on first appearance, and post only meaningful returned messages (stage text for phase changes; add safe-to-leave text only on a false→true canLeave transition) through the native accessibility announcement API compatible with this project's target. View disappearance/reentry seeds without replay; language changes refresh text but do not announce safety again. No focus-stealing layout notification.

- [ ] **Step 4: Run UNIT filtered to both task suites, then build the app.** Expected GREEN and `BUILD SUCCEEDED`. Command: `xcodebuild build -project SnipNote.xcodeproj -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' CODE_SIGNING_ALLOWED=NO`.
- [ ] **Step 5: Commit only Task 2 files.** `git commit -m "Add quiet analysis status surface"`. End-of-task contract: UNIT (all unit tests).

## Task 3: Wire truthful initiation, handoff, and server continuity

**Files:** Modify CreateMeetingView, BackgroundUploadRouting, MeetingDetailView, BackgroundUploadReconciler, and BackgroundUploadRoutingTests; extend AnalysisPresentationTests as needed.

**Interfaces:**
- Consumes Task 1 resolver/adapter and Task 2 `AnalysisStatusView`.
- Add trailing `onLegacySelected: () -> Void = {}` to `BackgroundUploadRouting.init(...)`. Invoke immediately before every actual legacy selection, including capability failure, flag/opt-out, and explicit disabled rejection without an existing session. Do not notify legacy on ambiguous/authentication failures or recovery of an existing background session.
- Add `initialPhase: MeetingProcessingPhase = .queued` to private `createProcessingMeeting(sourceAudioDuration:transcriptionBackend:initialPhase:)` in CreateMeetingView; only the `processServerSide(audioURL:)` call passes `.preparing`.
- Existing `BackgroundUploadReconciler.applyResult(_:to:userID:jobID:) -> Bool` continues returning true only for terminal application; nonterminal calls can update existing presentation metadata.

- [ ] **Step 1: Write failing routing and reconciliation regression tests.** `legacyCallbackPrecedesForegroundWork` checks callback fires once before start() returns legacy; parameterize server-off, opt-out, unavailable capabilities, disabled rejection. `ambiguousFailureDoesNotReportLegacy` checks existing exception is propagated and callback count 0; `existingSessionNeverReportsLegacy` checks recovery count 1, legacy count 0. Retain existing routing assertions unchanged.

`nonterminalMetadataRestoresProcessing` constructs a processing JobStatusResponse with exact matching IDs and “Generating summary...”, calls applyResult, expects false, meeting.processingPhase == .generatingSummary, and resolver fresh input phase analyzing/safeServer. `pendingMetadataRestoresQueue` expects .queued; `foreignProgressDoesNotMutateMeeting` expects unchanged phase/progress for foreign IDs. `progressDoesNotOverwriteResults` checks completed/edited model remains unchanged. Use existing test response construction conventions, no live services. Add a persistence test that saves the model, refetches it, and resolves without previous view state, expecting analyzing/safeServer. Add `newServerEntryIsPreparingBeforeManifest` using an in-memory Meeting set to the same initial phase as processServerSide, expecting preparing/keepOpen.

- [ ] **Step 2: Run UNIT filtered to `BackgroundUploadRoutingTests` and `AnalysisPresentationTests`.** Expected RED on missing callback or nonterminal metadata assertions.
- [ ] **Step 3: Integrate initiation and legacy selection.** Create server-route meetings with `.preparing` before `onMeetingCreated` navigates. In the legacy callback change that existing meeting's phase to `.transcribing`, preserve state/source/job identity, and save using existing error handling. Never grant permission from the callback. Existing recorded-cloud/short-import foreground entry points retain their paths and minimalist layout (this feature does not reroute them to background upload); mark their phase `.transcribing` where needed so they do not show a persistent preparing label. Preserve all routing thresholds, minute checks, notification scheduling, and lifecycle task ownership. The concrete insertion sites are processServerSide around line 1601, its routing constructor around 1634, createProcessingMeeting around 2207, and recorded-cloud creation/navigation around 1958–2012 (line numbers are planning-time anchors; match method names in the current checkout). Add a narrow existing busy guard to initiation if duplicate taps can currently create duplicate meetings; verify two rapid taps in Task 4/manual real-entry validation.
- [ ] **Step 4: Integrate retained server metadata.** In the reconciler, after existing identity/active-meeting guards, apply pending/processing results to existing `processingPhase` and normalized stage; use Task 1 serverPhase to map transcribing→`.transcribing`, analyzing→`.generatingSummary`, generic processing→`.transcribing` with normalized generic currentStageDescription. In applyQueued, set phase .queued only when first associating this job; repeated reconciliation must not erase a persisted transcribing/analyzing phase. Add `repeatedQueuedPromotionPreservesProcessingPhase` to Step 1, asserting generatingSummary survives a second applyQueued call with the same jobID. No new persisted columns; do not change `processingState` raw-value semantics. Save nonterminal metadata too: move context.save outside the terminal-only condition while preserving markResultApplied/sync/finish exclusively for terminal results. Preserve all account, cancellation, deletion, and already-applied guards.
- [ ] **Step 5: Integrate MeetingDetailView.** Render AnalysisStatusView once for background/accepted server analysis, using the adapter and a view-scoped last presentation keyed to meeting/job; retain existing local/foreground rendering and actions. Initial server preparation uses the new surface even without snapshot. Wire retry to the existing coordinator recover action. Show existing terminal error details/retry controls in the same content area below the new status title; avoid duplicate retry actions or claiming background continuation. Terminal local/foreground failures preserve their existing UI.

Remove synthetic `.pending`/“Uploading to server...” initialization for an already known jobID in updatePollingTask. Seed from persisted metadata, retain last confirmed status across poll errors, and clear cached state only for identity changes. Do not change polling intervals or add a poller. Do not use `.id(phase)` on the whole analysis view. Remove/narrow `.id(refreshTrigger)` on the ScrollView so metadata refreshes no longer destroy processing view identity; existing SwiftData/onChange updates must still refresh results. Add a 0.25-second opacity transition when processing yields to results, disabled under Reduce Motion; do not delay result application.
- [ ] **Step 6: Run UNIT including existing background-upload/coordinator/store/preparation/settings/routing and meeting-state suites.** Expected GREEN without live network prerequisites for these targeted suites; investigate genuine regressions before continuing. Also build with Task 2's build command.
- [ ] **Step 7: Commit only Task 3 files.** `git commit -m "Connect analysis stages to upload lifecycle"`. End-of-task contract: UNIT.

## Task 4: Prove the actual screen with deterministic UI fixtures

**Files:** Create DEBUG fixtures/host and AnalysisExperienceUITests; modify SnipNoteApp, ThemeManager/LocalizationManager DEBUG injection, and a DEBUG-only MeetingDetailView initializer. Tests use the actual detail screen and new component, not an HTML replica.

**Interfaces:**
- `#if DEBUG ThemeManager.init(previewTheme: AppTheme)` and `LocalizationManager.init(previewLanguageCode: String)` initialize only instance state, never standard UserDefaults. Change existing `LocalizationManager.localizedString(_ key: String) -> String` to resolve its instance languageCode via AppLocalization.bundle(for:), while leaving static localizedAppString and normal initialization/setLanguage semantics intact. AnalysisStatusView must use the environment instance, including locale-aware progress formatting.
- `#if DEBUG AnalysisPreviewFixtures.input(stage: String, meetingID: UUID, jobID: String?) -> AnalysisPresentationInput`; supported stages `preparing`, `upload-zero`, `upload-half`, `confirming`, `queued`, `processing`, `retry`, `failed`, `complete`, `legacy`, `local`.
- `#if DEBUG AnalysisPreviewHostView: View`: in-memory Meeting, deterministic input, explicit fixture buttons `fixture.next`, `fixture.back`, `fixture.return`; state advances only on test controls, no timer.
- `#if DEBUG MeetingDetailView.init(meeting: Meeting, analysisPreview: AnalysisPresentationInput)` sets an optional DEBUG-only input override. All view-owned network/reconcile/poll/refresh tasks and production retry actions are suppressed for this override; preview controls update it without transport. Normal initializer behavior remains unchanged.
- Launch argument `--analysis-preview`; stage via launch environment `SNIPNOTE_ANALYSIS_STAGE`, locale via `SNIPNOTE_ANALYSIS_LANGUAGE`, appearance via `SNIPNOTE_ANALYSIS_APPEARANCE`. DEBUG only. Guard the normal app root's launch/account/reconciliation effects so the fixture root bypasses authentication and services. Do not mutate production stores or settings; attach preview theme/locale at the fixture root. Use the DEBUG injection initializers specified above. Test that constructing Italian/dark preview managers leaves standard appLanguage/selectedTheme untouched and the instance resolves the expected Italian guidance; add that regression in SnipNoteTests/AnalysisLocalizationTests.swift. Apply preferredColorScheme from the fixture appearance and use environment theme colors for the detail background; do not call shared-manager themed modifiers in the fixture branch.

- [ ] **Step 1: Write failing XCTest UI assertions.** `testPreparationRequiresOpenAndZeroByteUploadAllowsLeave`: launch fixture preparing, assert keep-open title, tap fixture.next, assert “You can leave now”, progress value 0%, and no result UI. `testReturnKeepsUploadProgress`: launch upload-half, fixture.back and fixture.return, assert 50% and safe guidance still present. `testQueuedThenProcessingDoesNotBecomeUpload`: queue → next, stage is localized processing/transcribing, no upload label/percentage. `testRetryRemovesPermissionAndExposesAction`: retry fixture shows no safe title and a retry button at least 44-point frame height. `testItalianSafetyCopy`: Italian preparing→next asserts exact spec permission title/detail. `testLegacyAndLocalNeverSayCanLeave`: launch each fixture and assert keep-open/no safe title. `testCompletionShowsExistingResults`: complete fixture uses model.markCompleted and real overview/summary/transcript sections, no stale status or artificial completion delay. Give each screenshot a descriptive XCTAttachment name.
- [ ] **Step 2: Run `xcodebuild test -project SnipNote.xcodeproj -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:SnipNoteUITests/AnalysisExperienceUITests CODE_SIGNING_ALLOWED=NO`.** Expected RED: no fixture/status assertions satisfied. Tests must not skip for missing login.
- [ ] **Step 3: Implement the fixture interfaces and launch branch.** Retain production navigation/header/layout. Test controls are visibly outside the analysis surface and absent from normal app launch. Provide `#Preview` cases using the same input fixtures for rapid transitions, both themes, accessibility text sizes, and Reduce Motion. No network, original audio writes, account changes, or real upload session registration. A fixture back/return validates presentation reentry only; it is not evidence of physical background transfer.
- [ ] **Step 4: Run the Task 4 UI command.** Expected GREEN, zero login-related skips. Build Release for simulator with `-configuration Release` and verify fixture launch branch is compiled out (code inspection plus Release build); expected `BUILD SUCCEEDED`.
- [ ] **Step 5: Commit only Task 4 files.** `git commit -m "Test analysis handoff and return experience"`. End-of-task contract: Task 4 UI command.

## Task 5: Verify polish and accepted background behavior

**Files:** Create `docs/verification/2026-10-01-analysis-quiet-continuity.md`; change product files only if verification exposes a real defect, then add the focused regression before fixing it. Visual-only defects use a reproducible UI/preview assertion or documented visual check rather than a test that simply mirrors a style constant.

**Interfaces:** Consumes integrated app, Task 4 fixtures, all previous test suites; produces an evidence report with command results, screenshots, unresolved checks, and review rulings.

- [ ] **Step 1: Run full build and tests.** `xcodebuild build test -project SnipNote.xcodeproj -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' CODE_SIGNING_ALLOWED=NO`. Expected `BUILD SUCCEEDED` and `TEST SUCCEEDED`; list any existing credential/device-dependent skips/failures separately from feature results, never silently call the full suite green.
- [ ] **Step 2: Walk fixture states on small phone, iPhone 16 portrait/landscape, and iPad mini portrait/landscape.** Use installed sizes; previews can cover smaller widths unsupported by installed devices. At largest accessibility text size, all permission copy and controls remain readable and scrollable. Repeat English/Italian and light/dark; attach screenshots for preparation, safe upload, queue, processing, retry, results. Verify safe panel text contrast ≥4.5:1, percentage readable in both themes, and action targets ≥44 points.
- [ ] **Step 3: Inspect motion and accessibility.** At normal and slowed animation speed inspect preparing→upload-zero, upload progress, queue→processing, immediate completion, retry→reregister, and back/return. Under Reduce Motion no decorative loop/displacement/rolling numbers remain. With VoiceOver verify one handoff announcement, no byte-update announcements, correct traversal and progress value, and no focus theft. Increased Contrast/Differentiate Without Color preserve text and symbols; permission never relies on tint alone. Temporarily slow presentation animation durations for inspection in DEBUG fixtures only, then restore the production 0.25-second values before commit; do not slow network or preparation work. Use the existing tracker tests for rapid update deduplication; observation still required for native announcement delivery.
- [ ] **Step 4: Exercise real initiation and background transfer on the owner's physical phone when available.** Check imported server-route audio plus recorded/short-import foreground routes. Double-tap initiation must create one meeting; local/legacy must stay keep-open. For background: observe preparation, wait for actual registration/safe message, switch apps or lock during upload, return during transfer and after server processing. Check a poor connection/stall and retry; verify source retention and current-stage restoration. Simulator/fixture results do not replace this check. If the agent cannot operate the physical phone, complete all other work and give the owner this exact trial checklist; label physical verification pending and keep release/merge outside this task.
- [ ] **Step 5: Write the evidence report and perform the whole-branch review.** Use verification-before-completion and requesting-code-review guidance. Owner forbids subagents: perform a distinct self-review against spec, plan, diff, and Review Focus, recording “Final review: self-review (owner requested no subagents)” in the execution ledger. Fix important findings with reproducing RED/GREEN tests and rerun affected checks; defer isolated minors explicitly. Do not claim independent review or certify unobserved physical/accessibility checks.
- [ ] **Step 6: Commit the evidence report and any verified fixes separately.** `git commit -m "Record analysis experience verification"`. End-of-task contract: full command in Step 1. Leave a reviewable isolated branch with screenshots/evidence; use finishing-a-development-branch within the owner's no-merge/no-release scope.

## Plan self-review and handoff

- Spec coverage: resolver/state safety → Task 1; layout, copy, motion, announcement semantics → Task 2; navigation/initiation/server persistence/error/result integration → Task 3; real-screen deterministic regressions → Task 4; all-device/accessibility/physical acceptance and final review → Task 5.
- Shared interfaces: Task 1 owns input/value/resolver names; Tasks 2–4 consume them unchanged. Task 2 owns status view/theme/announcement contracts; Task 3 integrates them. Task 3 owns legacy callback and existing-phase persistence; Task 4 overrides presentation only, never lifecycle. Task 5 consumes these deliverables without adding features.
- Review Focus: all five conditions have explicitly named regression assertions; actual native announcement delivery and physical transfer remain observation requirements, not mocked claims.
- Plan includes no implementation bodies, no new service or schema requirements, and no scope expansion to other visual directions. UI constants and supplemental copy are explicit implementation decisions subordinate to the spec.
- Planning verification: scheme/package and simulator discovery succeeded; product code was not changed and app build/tests were not run for this plan.
- Owner reviews this plan before execution. The execution method is already selected: native, using executing-plans. The next session's explicit instruction to execute this plan supplies that approval; do not reopen visual-direction selection or request redundant method confirmation.
