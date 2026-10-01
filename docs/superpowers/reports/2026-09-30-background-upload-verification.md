# Background upload implementation verification

Implemented inline on 2026-10-01 in `codex/background-upload` in both repositories.
No subagents. No production migration, deployment, configuration change, account
activation, push or merge performed. Main checkouts and unrelated local changes preserved.

## Evidence

- Backend: 49/49 tests pass, including six real PostgreSQL tests on an empty
  disposable PostgreSQL 17 database; pinned SDK HTTP characterization and legacy
  API/provider/worker fixtures make no paid requests.
- Local rehearsal: only the two generated upload migrations applied; four legacy
  table column contracts unchanged, six public tables afterward. RLS enabled on
  both new tables; anonymous/authenticated roles denied table/RPC access. Concurrent
  promotion creates one pending job; registration/metadata errors roll back.
- iPhone 17: 33/33 new upload and relevant selected cloud/meeting tests pass. The user
  authorized simulator commands after reporting Task 1 success. No physical-device
  suspension/large-file behavior claimed.
- Full unit suite: 107 passed, one skipped, one failed.
  `ExportTests.testDOCXDocumentEscapesAndKeepsContent` fails; the
  same test fails on unchanged main. This remains a pre-existing merge/release blocker.
- SQL migrations generated with installed CLI 2.24.3 (`migration new --help` read):
  `20261001064743_background_upload_sessions.sql` and
  `20261001065143_promote_background_upload.sql`. Neither applied to production.
- Read-only production preflight: API/worker healthy; VPS revision
  `7cc8460d8904154f2a34303abd28bde6cd92bdbf`; about 12 GB free. Latest observed
  Supabase migration `20260930113230`. Database backup/restore availability remains
  unconfirmed (OS package backups do not prove it).
- Docs checked: Supabase changelog, Auth get_user and signed-upload docs; inspected
  pinned storage3 source. Signed HTTP instructions are multipart PUT with a streamed
  durable body. Production transport proof is pending approval.

## Commands

Run from the app worktree:

```bash
cd /Users/mattia/.codex/worktrees/background-upload/SnipNote
xcodebuild test -project SnipNote.xcodeproj -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnipNoteTests/BackgroundUploadSettingsTests -only-testing:SnipNoteTests/BackgroundUploadPreparationTests -only-testing:SnipNoteTests/BackgroundUploadStoreTests -only-testing:SnipNoteTests/BackgroundUploadCoordinatorTests -only-testing:SnipNoteTests/BackgroundUploadRoutingTests -only-testing:SnipNoteTests/MeetingTranscriptionBackendTests -only-testing:SnipNoteTests/CloudTranscriptionRequestTests
# Full suite (known existing DOCX failure):
xcodebuild test -project SnipNote.xcodeproj -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnipNoteTests
# A single Swift Testing function selection includes parentheses:
xcodebuild test -project SnipNote.xcodeproj -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 17' '-only-testing:SnipNoteTests/BackgroundUploadCoordinatorTests/crashAfterBootstrapReschedulesMissingTasks()'
```

Backend (service worktree):

```bash
cd /private/tmp/snipnote-background-upload-service
python3.12 -m venv .venv-test
.venv-test/bin/pip install -r requirements-test.txt
# Provide a new, empty disposable LOCAL database; never production.
UPLOAD_TEST_DATABASE_URL='<loopback disposable DSN>' .venv-test/bin/python deploy/rehearse_uploads.py /Users/mattia/.codex/worktrees/background-upload/SnipNote
UPLOAD_TEST_DATABASE_URL='<same local DSN>' .venv-test/bin/python -m unittest discover -s tests -p 'test_upload*.py' -v
UPLOAD_TEST_DATABASE_URL='<same local DSN>' .venv-test/bin/python -m unittest discover -s tests -v
```

## Production approval point

Review the two named migrations and service feature-branch diff against `6764cb4`.
Confirm backup/restore availability and independent review before approving migration
or deployment. Deploy the API/reconciler disabled, smoke-test the shipped app, then
request separate owner-only activation approval. Exact service commands, flag values,
transport proof and rollback procedure are in service `DEPLOYMENT.md`. No blanket
migration push, project clone, bucket policy changes or concurrency tuning.

## Owner archive and physical-device checklist

After separately approved backend rollout/owner activation:

```bash
cd /Users/mattia/.codex/worktrees/background-upload/SnipNote
open SnipNote.xcodeproj
# Select SnipNote / Any iOS Device, verify signing and app/share extension build numbers.
xcodebuild -project SnipNote.xcodeproj -scheme SnipNote -configuration Release -destination 'generic/platform=iOS' -archivePath /private/tmp/SnipNote-background-upload.xcarchive archive
# Xcode Organizer: Distribute App → App Store Connect → Upload → ordinary TestFlight.
```

Use the same account, database, bucket and production API. Confirm the owner's
capability is true, a non-owner fixture is denied, and local opt-out uses legacy.
For small audio and representative 150 MB / 400 MB originals, record observed
results (all currently pending):

| Scenario | Required observation |
| --- | --- |
| Preparation | Original retained, no gaps/overlap, bounded memory, disk checked; UI says keep open |
| Lock / switch apps | Only after registration, transfers finish and server queues while app is suspended |
| Network drop / reconnect | Byte progress recovers; successful chunks stay successful; only unfinished chunks retry |
| Expired credentials | Reopen refreshes same session, verified objects reused, no second legacy job |
| Force quit / reopen | Query server first; reattach/recreate missing tasks; transcript arrives without detail view |
| Low disk | Clear recoverable preparation error, original retained, no upload/job duplication |
| Account switch / sign out | Old transfers canceled; old progress/results do not affect current user |
| Long ordinary server job | Independent upload checks continue and enqueue one normal pending job |
| Delete / cancel | Late callbacks do not recreate transcription or apply results |
| Flag off / local opt-out | New uploads use legacy; existing background session still refreshes and finishes |
| Result sync interrupted | Saved transcript applied once; metadata sync retries without overwriting user edits |

Log session/job IDs, failed-file indexes, peak preparation memory/disk and transcript
arrival times; omit signed URLs/tokens. Continue ordinary use for about 7–10 days.
Replace TestFlight with shipped App Store build and verify existing local data and
promoted records remain usable; restore TestFlight and check unfinished-session
recovery. Wider allowlist/app release/merge await owner acceptance evidence.

## Review and rulings

Whole-change author self-review completed against both branch diffs, the spec,
plan interfaces and review focus. No independent reviewer was delegated, per the
user's instruction; independent review remains pending before production/merge.
One substantive fix pass covered late status overwriting successful callbacks,
cancellation resurrection, suspended task resumption, cross-file retry-budget
bypass, authentication fallback, concurrent reconciliation and interrupted source
copy. Each regression was observed failing, then passing. Settings now fetches
capability when opened; no deferred minor findings were recorded.

Rulings, in execution order:

1. Initially defer Swift/device execution to the owner because Xcode was explicitly
   prohibited; implement in order without claiming verification. Cost if wrong:
   owner finds compile/device defects. Later simulator authorization superseded
   this restriction; physical-device evidence remains pending.
2. Perform author self-review without delegation, as expressly instructed. Cost
   if wrong: author blind spots; independent review remains a production/merge gate.
3. Execute unchanged disposable copies of native skill scripts because installed
   executable bits were missing. Cost if wrong: tooling drift; installed skills
   were preserved.
4. Use multipart PUT from the pinned storage3 implementation, with streamed
   durable iOS request bodies. Cost if wrong: production transport proof requires
   adapting framing before activation.
5. Retain expired/abandoned objects because retry reuses them and no retention
   interval was specified. Cost if wrong: storage accumulates until a reviewed
   cleanup policy exists. Queued objects are never deleted by the new reconciler.
6. Promote even one prepared file through ordinary audio_chunks and the unchanged
   chunk worker. Cost if wrong: existing single-file playback needs device proof;
   the app retains its durable original for playback.
7. Leave the unrelated DOCX failure outside feature scope after reproducing it on
   unchanged main. Cost if wrong: the full suite remains red; resolve it before
   merge/release.

The native execution ledger remains in this plan's ignored workspace while owner
acceptance is pending. Completion markers do not claim unfinished deployment,
transport or device contracts have passed. Code and observed evidence are committed.

## Commits and final evidence

App base: `efa1a11719e554db0e7a1898515c2157a176a0a4`.
Service base: `6764cb4` (whole-file xAI revert retained).

The authoritative app commits are: `99dbf12`, `5d1d84a`, `0245757`, `6d0a9b9`,
`488e28e`, `de1294a`, `9826ecd`, `5693864`, `55b7598` (final race fixes),
followed by this verification record. Service commits are `e9f827b`, `364ed6b`,
`0b28724`, `754fc29` (current service HEAD).

Final logs (local, not committed):
- `/private/tmp/upload-final-backend.log`: 49 tests, OK.
- `/private/tmp/upload-final-rehearsal.log`: fresh disposable schema rehearsal.
- `/private/tmp/upload-final-swift.log` and `upload-final-swift-summary.json`: 33/33.
- `/private/tmp/upload-final-full-swift.log` and `upload-final-full-summary.json`:
  107 passed, one failed, one skipped.
- `/private/tmp/upload-xcode-baseline-export.log`: same DOCX failure on main.
- `/private/tmp/upload-review-red.log`, `upload-review-routing-red.log`,
  `upload-review-retry-red.log`, `upload-source-copy-red.log`: review regressions.

Branches/worktrees remain for follow-up. No push, merge, production action or
owner-only activation has occurred. Tasks 7/8 are intentionally incomplete at
those authorization and physical-device checkpoints.


## Approved owner trial rollout — 2026-10-01

The owner approved trial preparation, production migrations/deployment and owner-only
activation in this conversation, then identified their login and confirmed backup
readiness. This section supersedes the earlier approval-pending status; nothing was
pushed or merged to main.

- Auth verified `mattia.dacampo@gmail.com`, UUID
  `e6658fad-05e2-4d25-9779-857bc72bbc81`, confirmed/non-anonymous. This is the only
  allowed account. New-upload capability true for owner, false for a non-owner UUID
  fixture. Actual non-owner authenticated device testing remains pending.
- The two exact additive SQL files were applied via Supabase MCP. Its generated
  history versions were aligned to the already generated repository versions
  `20261001064743` / `20261001065143`; both named entries confirmed afterward.
  New tables have RLS and no anon/authenticated table or RPC privileges;
  service-role-only access confirmed. New RPCs remain SECURITY INVOKER with fixed
  search paths. Advisors report only the expected no-policy INFO for these new
  service-only tables; unrelated existing warnings left untouched.
- Service deployed by transferring a Git bundle and checking out a detached reviewed
  revision on the existing VPS. Current running API code:
  `f328b6df996f96b4846e0ff2e6d93724458f6578`.
  API, ordinary worker and independent reconciler active. Ordinary worker PID
  `3103443` and start time `2026-09-30 12:04:28 UTC` unchanged throughout.
- Private rollback copy of environment and prior revision retained at
  `/root/snipnote-rollbacks/background-upload-2026-10-01/` on omni. Prior revision
  `7cc8460d8904154f2a34303abd28bde6cd92bdbf` remains available. API restarts caused
  brief 502 responses while initializing, then recovered to healthy.
- Backup evidence is owner-confirmed, not independently verified: Management API
  returned `walg_enabled=true`, `pitr_enabled=false`, no listed backups/physical
  restore data. Fresh protected CLI dump failed because the database password was
  unavailable; the empty output is not a backup. No backup settings/password changed.
- Disabled production smoke: real owner Auth, missing-Auth 401, owner capability
  false, structured disabled bootstrap 403 without session writes, unchanged legacy
  missing-job route 404. Shipped-app end-to-end smoke remains owner-pending.
- Real production transport proof: tiny owner-scoped synthetic audio, exact iOS
  multipart PUT framing, exact stored bytes, missing/wrong-size verification,
  idempotent refresh, verified files omitted from signed credentials, replacement
  upload of a wrong-size object, same-session expiry renewal, independent reconciler
  rejection of an incomplete fixture, and feature-off refresh all passed. Owner
  activation restored afterward. The deliberately absent third file prevented any
  paid promotion. Fixture meetings/sessions/files removed; zero remain. A transient
  Auth session was used only for the proof and signed out with `scope=local`, leaving
  existing device sessions alone. Tokens/signed URLs were not printed or committed.
- Transport exposed a real SDK gap: storage3 0.8.2 rejects signing an existing object
  unless `x-upsert=true` is supplied at signing time. Regression test observed
  Duplicate failure, then passed after a narrow pinned-adapter fix. Service commit
  `f328b6d`; final backend 50/50 including six local PostgreSQL tests. Log
  `/private/tmp/upload-upsert-green.log`. No app code change required.
- Final sanitized production logs retained privately on omni:
  `disabled-smoke.log` and `transport-proof-final.log` under the rollback directory.
  The latter proves recovery and rollback behavior. Production object credential
  expiry over the full two-hour interval, a long paid job during reconciliation,
  actual device suspension and transcript arrival remain unverified.

Additional rulings:

1. Proceed with the explicitly approved owner trial using the completed author
   review, respecting the continued no-subagents instruction. Independent review
   remains pending before merge/wider release. Cost if wrong: undiscovered defects
   affect the owner trial.
2. Keep the pinned dependencies and use the SDK's narrow request adapter to send
   the documented signing-time upsert header, only for unverified session files.
   Cost if wrong: a future SDK upgrade needs adapter/wire-test review. Production
   replacement proof passed; verified files never receive replacement credentials.
3. Align MCP-generated migration history IDs to repository-generated IDs without
   altering SQL contents, keeping one migration source/history. Cost if wrong:
   incorrect bookkeeping could cause future migration replay; both entries verified.

### Immediate physical-phone handoff

Xcode's device inventory found the owner's iPhone 13/16 unavailable; only an iPad
was available. No app installed onto another device.

```bash
cd /Users/mattia/.codex/worktrees/background-upload/SnipNote
open SnipNote.xcodeproj
```

Connect/unlock/trust the intended iPhone, enable Developer Mode if prompted, choose
SnipNote and the physical phone destination, retain existing bundle ID/signing/data,
and Run. Then stop debugging and launch from Home Screen for suspension tests.
Use server transcription and leave the local legacy-upload opt-out off. Test small
recording first, then larger audio; wait for permission to leave before locking.
Verify server verification/ordinary queueing and transcript on reopen. Network drop
and force-quit/reopen are separate recovery tests. Do not uninstall/reset the app.
Direct Xcode installation is the first test; TestFlight and the 7–10-day trial follow.


## Physical-phone installation — 2026-10-01

Owner connected iPhone 16 di Matti (iPhone 16 Plus). Pairing completed through
`devicectl manage pair`; no app deletion or bundle/signing change. Build from app
revision `9f747dd` succeeded with existing automatic signing using Xcode 26.6:

```bash
cd /Users/mattia/.codex/worktrees/background-upload/SnipNote
xcodebuild -project SnipNote.xcodeproj -scheme SnipNote -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/SnipNote-background-upload-device build
xcrun devicectl device install app --device F14158B7-FEC9-5476-9FE3-E246488F6ABF /private/tmp/SnipNote-background-upload-device/Build/Products/Debug-iphoneos/SnipNote.app --timeout 60
xcrun devicectl device process launch --device F14158B7-FEC9-5476-9FE3-E246488F6ABF com.mattianalytics.snipnote --timeout 30
```

Install and launch confirmed successful with original bundle identity
`com.mattianalytics.snipnote`, without attaching a debugger. Local build log:
`/private/tmp/upload-device-build.log`; install/launch JSON:
`/private/tmp/upload-phone-install.json`, `/private/tmp/upload-phone-launch.json`.

Owner must now confirm account/data continuity and perform the small-audio
server upload, preparation/permission-to-leave, lock and reopen test. These observed
installation results do not yet prove background transfer, server promotion or
transcript application on the physical phone. TestFlight/archive/trial remain pending.


## First physical-phone upload — 2026-10-01

Owner confirmed the installed app remained logged in and showed existing real
meetings. For a 477-second recording, the owner reported reaching Home Screen
while the upload byte counter was below its total and staying outside SnipNote.
Server observations:

- Session `69828665-7894-48d2-8dce-8c7723b61c21`, meeting
  `e614c373-5be4-415a-b844-51af8f42daef`, created 08:36:10 UTC.
- One file, 7,870,403 bytes, verified at 08:36:17.216 UTC.
- Ordinary job `17bef8f9-4fef-4bb6-b575-752c0bace00a` queued at
  08:36:17.311 UTC; processing observed while owner remained outside the app.
- The unchanged xAI worker then retried five times and marked this job failed
  at 08:42:21 UTC. Its sanitized error was “xAI transcription returned invalid
  text (HTTP 502)”; this is the worker's validation error for absent/empty text,
  not evidence of an actual HTTP 502 response from xAI.
- Read-only media inspection found decodable AAC, 48 kHz stereo, 477.163 seconds
  and non-silent mean volume (-23.8 dB). Temporary inspection audio was deleted;
  no recording/transcript content or credentials were logged.

This demonstrates transfer completion and ordinary queue promotion after the
owner reported leaving before upload completion. Exact OS suspension timing,
background delegate completion and successful transcript application remain
unverified. Owner was asked to reopen and report the displayed meeting status;
that observation is pending. No automatic provider switch, duplicate upload or
additional paid diagnostic transcription was initiated. Network interruption,
force-quit recovery, large originals and the longer owner trial remain pending.


### Transcription follow-up and owner reopen observation

Owner reopened and observed the expected invalid-text/max-retries error. Worker
logs showed five internal chunks successfully transcribed (1,091 / 1,159 /
1,079 / 1,269 / 1,097 characters), followed by a sixth 0.00 MB chunk failing.
These partial transcripts were in memory and were not saved when the job failed.
Boundary reproduction decoded 477,119 ms; step 95,350 ms; fifth chunk ended at
477,119 ms, while the redundant sixth covered 476,750–477,119 ms (369 ms,
3,501 encoded bytes). The fifth chunk already contained that entire fragment.

Owner explicitly authorized paid diagnostic requests. One call using the same
provider configuration and fragment returned HTTP 200, application/json, valid
object with duration/language/text fields and empty string text. Only response
structure/length was printed. This confirms empty tail text rather than a
special-character rejection. No failed-job state change was made.

A minimal service fix stops splitting once the preceding overlap reaches the
recording end. Real WAV/MP3 regression failed before the fix (two chunks versus
one), then passed; another case verifies audio beyond overlap stays covered.
Backend suite 52/52 including six local PostgreSQL tests passed. Strict invalid
response validation, provider routing and concurrency remain unchanged. Worker
fix deployment/retry of the existing owner job need approval because the original
background-upload rollout explicitly preserved the existing worker. Successful
transcript application remains pending that retry; no additional app build needed.
