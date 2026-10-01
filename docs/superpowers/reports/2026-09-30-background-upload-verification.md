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
- iPhone 17: new upload and relevant selected cloud/meeting suites pass. The user
  authorized simulator commands after reporting Task 1 success. No physical-device
  suspension/large-file behavior claimed.
- Full unit suite: `ExportTests.testDOCXDocumentEscapesAndKeepsContent` fails; the
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
xcodebuild test -project SnipNote.xcodeproj -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnipNoteTests/BackgroundUploadSettingsTests -only-testing:SnipNoteTests/BackgroundUploadPreparationTests -only-testing:SnipNoteTests/BackgroundUploadStoreTests -only-testing:SnipNoteTests/BackgroundUploadCoordinatorTests -only-testing:SnipNoteTests/BackgroundUploadRoutingTests
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

Whole-change self-review pending; independent review remains required before production.
Rulings and final review findings will be recorded here before handoff.
