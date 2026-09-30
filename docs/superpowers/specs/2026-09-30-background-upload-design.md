# Background upload for cloud transcriptions

Date: 2026-09-30
Status: Approved in principle; TestFlight isolation clarified during planning

## Goal and agreed scope

Allow a user to start a cloud transcription, leave SnipNote or lock the iPhone after upload preparation, and have the upload and server transcription continue. The user's typical originals are 150–400 MB and longer than an hour. Keep small upload chunks and the existing provider/chunk transcription behavior. Do not restore the reverted xAI single-request work. Live Activities are a separate follow-up.

Success means a prepared upload survives app suspension, successful chunks are not uploaded again after a failure, and the server starts the job without requiring the app to remain awake. Reopening the app restores accurate progress and eventually the result without creating duplicate jobs.

## Approach and alternatives

Use file-based background URLSession uploads for the existing small chunks. This allows iOS to manage transfers and limits retry cost to a failed chunk. A whole-original upload simplifies preparation but increases retry cost for these large recordings. Supabase resumable uploads introduce a separate transport protocol and are deferred; do not assume an ordinary Swift Task or a short UIKit background task can keep an upload running indefinitely.

## User experience

The transcription appears immediately. Its first stage is **Preparing audio**, followed by **Uploading**, **Queued**, and the existing processing/result stages. Preparation exports stable chunk files and registers them for background transfer. The app shows when that registration is complete and the user can leave the app.

Preparation itself is not guaranteed to continue while suspended. Retain the original so interrupted preparation can resume or restart on reopening. Once transfers are registered, locking the phone and switching apps are supported. Force quitting can cancel transfers; reopening reconciles them and retries missing chunks. If all files already reached storage, server processing continues independently.

Preserve existing network preferences; do not introduce a Wi-Fi-only restriction. Describe network waits and recoverable upload failures separately from a server transcription failure. Show byte progress for upload, not an invented transcription percentage.

## iOS responsibilities

- A focused upload coordinator owns a background URLSession with a stable identifier and delegates; views initiate work and observe state.
- Prepare chunks as files in an application-support upload directory, using the current time segmentation and encoding behavior. Avoid accumulating every chunk in memory. Small recordings also use a stable file-based transfer.
- Persist an atomic manifest containing environment ID, account ID, transcription ID, upload session ID, optional server job ID, captured provider/language/duration, file paths, chunk ordering, expected byte sizes, and transfer state. Never store account access tokens in that manifest.
- Complete manifest persistence and server bootstrap before scheduling transfers. Recover safely if the process stops between these steps. Keep files protected in a way that permits background reads after the first device unlock.
- AppDelegate reconnects the session on background-transfer events and calls the supplied system completion handler only after delegate events and durable state updates finish.
- Reconcile persisted manifests with actual URLSession tasks at launch and after delegate events. Refresh expired signed upload URLs when execution and authentication are available. Retry only missing/failed files with bounded backoff; keep successfully uploaded files recorded.
- Account changes cannot apply a previous user's progress or results to the active account. Cancel inappropriate transfers and preserve or discard recovery state according to explicit ownership checks.
- Retain original/chunk files until remote storage verification succeeds. Clear confirmed uploads and completed manifests without deleting audio still needed for recovery or existing playback.
- Restore remote job status/results through app-level reconciliation, including when the detail view was never reopened. Decode new/unknown job states safely. A polling/network error must not trigger duplicate local transcription while a valid remote job is awaiting upload or queued.

## Server and storage responsibilities

Introduce an authenticated background-upload bootstrap API alongside the existing job API. Its request is a manifest of ordered files with expected sizes and durations plus the selected provider/language. The server verifies the authenticated user owns the transcription, generates storage paths itself, and returns an upload session ID and per-file signed upload instructions. Existing clients continue using the existing API.

Bootstrap is idempotent for the same owner/transcription and manifest. Repeated calls return the same upload session and refresh signed instructions for unfinished uploads. Conflicting manifests are rejected rather than silently changing a running job. URLs are short-lived credentials and must not be logged; file extensions and content types must match the recordings bucket's actual policy.

Upload sessions start in **awaiting_upload** in separate upload tables; do not extend the existing transcription-job status enum. A server reconciliation loop checks every expected object and its exact byte size, then atomically persists recordings/chunk metadata, creates one ordinary **pending** transcription job, links it to the meeting and marks the session **queued**. Metadata writes and promotion must tolerate retries and process restarts. Existing worker chunk processing then runs unchanged. The app may signal completion to accelerate this check, but server promotion never depends on that signal.

Run upload reconciliation independently of long transcription jobs. Bound work per pass fairly so older incomplete uploads cannot starve newer complete uploads. Use a 24-hour upload deadline, return it to the app, and expose an explicit recoverable expiration state. After expiration the app can bootstrap a fresh attempt on reopening; preserve verified files for reuse and never delete objects referenced by active/completed jobs. Cleanup of abandoned partial files must verify ownership and references before deleting them.

Do not introduce a 100 MB original-file limit. Validate each prepared file against storage/server limits and support the user's 150–400 MB originals through small chunks. Keep provider selection and current chunk stitching behavior. Do not include APNs, Live Activities, pricing changes, or unrelated security-branch features in this change.

## Compatibility and rollout

TestFlight alone does not isolate infrastructure. First test against a separate staging Supabase environment and staging API/reconciler/worker, using test accounts and audio. Explicit build configuration selects staging credentials and endpoints; the App Store Release configuration remains production with background upload disabled. Never route a production client to staging automatically based solely on its receipt. Namespaced local recovery data must not cross environments.

Implement the minimum authentication and ownership validation required for the new endpoint. Verify current Supabase signing/upload behavior before relying on it. Rehearse additive migrations and rollback on staging. For eventual production rollout, add only new upload tables/functions, keep existing tables/statuses/contracts compatible, and deploy the API/reconciler disabled by default. Enable selected test accounts only after legacy-client smoke tests. Disabling bootstrap must still allow existing sessions to finish. Roll back code/flags without destructive database rollback. No production migration or deployment is part of the planning phase.

Existing pushed background-upload backend code is reference material: it assumes a whole-file transfer, has a 300 MiB default, and is stacked on the rejected xAI change. Extract/adapt only relevant code; do not merge that branch wholesale. Keep shared meeting state values recognizable to old builds; new preparation/upload stages belong to the new session API and local manifest.

## Verification and acceptance

Deterministic tests cover manifest persistence/recovery, repeated bootstrap, ownership rejection, conflicting manifests, expired credentials, missing/wrong-sized objects, metadata retry, single atomic promotion, and independence from busy workers. Verify late callbacks, account switching, and duplicate delegate events cannot corrupt local state or duplicate jobs.

On a physical iPhone, test small audio and representative 150–400 MB originals: lock during upload, switch apps, interrupt/reconnect the network, reopen after force quit, and wait through another long server job. Confirm only failed chunks retry, upload progress recovers, server processing begins while the app remains suspended, and the final transcript appears on return. Observe disk and memory usage during preparation.

The repository requests that the owner run Xcode builds manually. Provide the owner a focused device checklist and report automated backend/unit checks separately. Do not claim background behavior verified solely from a simulator or a build.
