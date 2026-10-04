# Share and transcribe without opening SnipNote

Date: 2026-10-02
Status: Draft for review; implementation is not authorized by this document.

## Intent and success

From Voice Memos, the user shares one recording to SnipNote, taps Transcribe in a small share panel, receives confirmation, and returns to the source app. Upload and server processing proceed while the user switches apps or locks the phone. Opening SnipNote later restores the meeting and its transcript, overview, and summary without creating another job.

The user explicitly chose **Require connection to start transcription**. No offline inbox is included. A connection is needed for server acceptance; losing connectivity after scheduling transfers causes a network wait, not loss of the recording.

Live Activities and server completion notifications are separate follow-ups. This release makes no promise of a completion alert while the main app is suspended.

## Current implementation and approach

`SnipNoteShare/ShareViewController.swift` copies audio to App Group storage, writes `pending_audio.txt`, and tries to open the main app. `SharedAudioImport.swift` then routes into CreateMeetingView. The existing background coordinator uses file-backed URLSession uploads, but its manifests live in the app's private Application Support directory. `BackgroundUploadReconciler` polls while the app is active. The backend registers sessions only for existing owned meetings; an independent server reconciler promotes verified chunks to jobs. A database completion trigger already debits minutes.

Recommended: retain the current 15 MiB chunk upload protocol, move only extension-safe preparation/transport contracts into focused shared files, and add an authenticated share submission endpoint that creates the meeting and session together. Preserve the ordinary in-app upload flow and SwiftData location.

Alternatives considered: retaining the app-opening handoff does not meet the intended experience; uploading a whole original requires a different ingress and server preparation pipeline and increases retry cost for the user's 150–400 MB recordings. Do not change provider behavior or introduce whole-file server decoding in this feature.

## Global constraints

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

## Share panel and exact behavior

Accept one audio file, initially m4a, mp3, wav, aiff, ogg, or flac that AVFoundation can decode. Activation rules must filter audio; reject non-audio despite a misleading extension, multiple attachments, zero bytes, nonfinite/zero duration, or an unreadable file. m4a/mp3/wav/aiff/ogg/flac names do not imply codec support: inability to decode is a visible preparation error. Preserve the source file. Use its filename without extension as the title, trim whitespace, and fall back to “Voice recording” / “Registrazione vocale”. Title limit: 200 characters.

The panel shows filename/title, duration, captured cloud provider and language, Transcribe, and Cancel. No title editor or settings editor is included. Cancel before submission removes only this share's unregistered temporary artifacts. Reject signed-out/expired sessions and insufficient minutes before accepting, with guidance to open SnipNote manually; never launch it automatically.

States and English copy (Italian equivalents must retain the same meaning):

| State | Copy/action |
|---|---|
| Ready | “Transcribe”, “Cancel” |
| Preparing | “Preparing audio…”; disable repeat submission; Cancel remains available |
| Authorizing | “Starting transcription…” |
| Scheduled | “Added for transcription”; announce, then dismiss after 1 second |
| Offline before acceptance | “Connect to the internet and try again.”; Retry, Cancel |
| Authentication missing/expired | “Open SnipNote to sign in or refresh your session, then share again.” |
| Insufficient minutes | “You don’t have enough minutes for this recording. Open SnipNote to add minutes.” |
| Preparation fails/interrupted | “Couldn’t prepare this recording. Try again or import it in SnipNote.” |
| Other submission failure | “Couldn’t start transcription. Try again.”; preserve the same submission ID for Retry |

The extension must remain visible during local copying, decoding, and chunk preparation. It cannot promise instant dismissal for long recordings. Confirmation is allowed only when the source, chunk files, upload bodies and manifest are durable, the server has registered the meeting/session, and every missing chunk has a resumed system upload task. If the extension dies sooner, no success confirmation occurred; the app can recover durable preparation on next launch. Incomplete original copies are never submitted: mark source copy completion only after an atomic rename; missing/incomplete copies require sharing again. A real-device trial on 150–400 MB recordings is a release gate. If extension preparation cannot reliably handle these inputs, revise the architecture rather than claiming success or silently opening the app.

After server registration, cancellation is no longer offered in the share panel; a failed scheduling attempt is retryable under the same identity. Cancellation in the main app retains existing behavior. An ambiguous network response must never delete a possibly registered submission: query/retry idempotently on next execution.

## Shared data, credentials, and process ownership

Create `SharedTranscription/` source files compiled into app, extension, and app unit tests with explicit Xcode memberships. The directory contains no app singletons, SwiftData, UIKit UIApplication, StoreKit, or OpenAI clients.

Use `ShareTranscriptions/<user UUID>/<meeting UUID>/` inside the existing App Group. The per-share manifest is version 1 and records immutable owner/meeting IDs, title, created time, captured provider/language/duration, original relative path, prepared chunk descriptors, optional server session/job IDs, transfer states, registrationAttempted (persisted before the first registration request), and local state: `preparing`, `prepared`, `registered`, `scheduled`, `retry`, `completed`, `cancelled`. Tokens and signed instructions are held in memory only. Use unique names, atomic replacement, file protection complete-until-first-authentication, exclusion from backup, containment checks, and POSIX per-share advisory locks for cross-process mutation. Unknown/corrupt versions are quarantined individually rather than blocking other shares.

The app publishes a read-only access-token snapshot to shared Keychain access group `$(AppIdentifierPrefix)com.mattianalytics.snipnote.share`, service `com.mattianalytics.snipnote.share`, account `access-session`, accessible after first unlock on this device only. Snapshot fields: user ID, access token, expiration, generation UUID. The app updates it at launch and every auth-state event, including refresh; sign-out invalidates it before starting the sign-out request. The extension never refreshes the Supabase session or stores a refresh token. Missing/expired snapshots require the user to open SnipNote; a server 401 invalidates the extension's attempt without altering a newer snapshot. Recheck generation/owner before registration and scheduling. Provision both targets for the shared access group; existing app login storage is unchanged.

Preferences in App Group defaults contain only provider, optional transcription language, interface language, and current account ID. Publish on launch and preference change. A per-meeting language choice is not currently a saved global preference: use auto-detect unless a persisted preference is introduced deliberately and wired to the app's language selector. Do not confuse interface language with audio language.

Each share gets a stable background session identifier `com.mattianalytics.snipnote.share-upload.<meeting UUID>` and `sharedContainerIdentifier` equal to the App Group. Task description is `<user UUID>/<meeting UUID>/<chunk index>`. The extension owns its session while running; the app reconnects only after extension completion, on matching system events or foreground recovery. Use a separate `session-owner.lock` file and a nonblocking POSIX advisory lock held for the session lifetime; foreground recovery skips a still-owned session. Process death releases the OS lock. Data mutation uses a separate `manifest.lock`. Do not connect two processes to the same background session concurrently. The legacy app upload session remains unchanged. Stream multipart bodies to files rather than allocating all audio in memory.

## Authenticated backend admission

Add `POST /share-transcriptions`, verified by the existing Supabase user verification boundary; never trust a body user ID. Request: `meeting_id`, `title`, plus the existing UploadBootstrapRequest provider/language/duration/files fields. Reject extra fields. Response is the existing UploadSessionResponse. Do not change `/upload-sessions`, `/jobs`, or existing clients' contracts.

A service-role-only transactional RPC `register_share_transcription(p_owner uuid, p_title text, p_session jsonb, p_files jsonb) returns uuid` creates the meeting and upload session/files together. Lock the owner's user_minutes row for admission. Cost is `max(1, ceil(duration / 60))`. Available balance is the stored balance less outstanding cloud commitments: unfinished upload sessions (awaiting_upload and queued with nonterminal job) plus pending/processing cloud jobs not already represented by those sessions. Count each meeting once; exclude cancelled/expired sessions and terminal jobs. Compare under the same lock used by balance updates. This is a computed admission hold, not a new debit or credit ledger. No schema-wide billing rewrite is included.

Create a pending, processing meeting with the captured title, owner, and duration metadata supported by the current schema. Do not expose a job until the existing reconciler verifies every storage object. Registration is idempotent for owner + meeting ID + immutable manifest/title: repeated requests return the same session without creating another meeting/job or consuming another commitment. Conflicting metadata returns 409. An existing foreign meeting returns 404. Recheck share enablement only for new admissions so disabling the feature does not strand accepted transfers.

Admission failures: 401 `unauthenticated`, 402 `insufficient_minutes`, 403 `share_transcription_disabled`, 409 `manifest_conflict`, 422 invalid media/manifest, 503 transient service failure. Add `share_transcription_enabled` to `/upload-capabilities` without removing `background_upload_enabled`; default false. `SHARE_TRANSCRIPTION_ENABLED=true` and the existing background-upload allowlist are both required for new share submissions.

Retain the existing completion debit; the app must not issue a second client debit for shared cloud jobs. A simultaneous legacy client outside this admission path can still bypass computed holds; do not represent this feature as a universal billing reservation system. Cancellation/expiry releases computed admission capacity; successful completion reduces stored balance and removes that job from outstanding capacity. Failed jobs release capacity without a debit. Existing completion-trigger failure behavior is unchanged and is a preexisting billing limitation.

## Recovery and finding results

Foreground launch and auth activation enumerate manifests belonging to the active account. Insert missing SwiftData meetings with the stable ID before reconciliation; import the server meeting/job state before any local save/upsert can overwrite a terminal result. Link the durable original for playback. Use existing status/result mapping to restore transcript, overview, and summary. A second launch, duplicate callback, or retry produces one local meeting and one remote job.

Route share-session background events through a focused recovery coordinator, drain delegate events and durable writes before calling iOS's completion handler exactly once, and never instantiate foreground-only SwiftUI/StoreKit for that work. Refresh signed instructions only when authenticated execution is available. iOS may delay transfers; a signed URL can expire during a long network wait. Retain source and chunks for foreground repair and describe it as retry needed, not transcription complete.

Switching accounts or signing out prevents new admissions and prevents results applying to another user's models. Locally registered transfers may already reach storage/server; signing out does not promise cancellation of accepted server work. At the next available execution, cancel local transfers for inactive owners; retain their protected recovery state until that owner signs back in. Files must not disappear because a different account is active.

Force quitting can interrupt uploads until SnipNote is reopened. Once the server has verified the full upload, transcription is independent of the app. Do not promise uninterrupted progress after force quit. Preserve existing legacy `pending_audio.txt` and file/deep-link import routing for old artifacts; the new extension never writes that flag.

Remove verified transfer bodies/chunks only after durable completion. Keep audio required for playback. Remove an orphan local `preparing`/`prepared` directory after 7 days only if registrationAttempted is false or an authenticated server lookup confirms it was never registered; otherwise retain it for repair. Do cleanup only during app execution, never by assuming a background timer runs.

## Verification and release

Deterministic tests cover hostile paths, same filenames, partial writes, stale auth, generation changes, wrong-owner requests, balance concurrency, idempotent retries, scheduling interruption, callback replay, account switching, source retention, failed jobs, corrupt manifests, and completed-result restoration without a detail view.

Physical iPhone acceptance covers Voice Memos and Files; small audio and representative 150–400 MB originals; dismissal returning to the source app; lock/switch during upload; connectivity loss after scheduling; signed URL expiry; force quit and recovery; cancellation during preparation; app/extension process ownership; and English/Italian accessibility. The server must queue and finish without a foreground app request after all chunks arrive. Record memory/preparation timings and evidence, not just a build result.

Enable only for the existing owner trial after backend migration/rehearsal and signed extension provisioning are verified. Deploy additive backend support before the app; production migration/deployment requires a separate execution decision. Roll back new admissions with the flag while keeping accepted upload sessions, server reconciliation, source files, and recovery working. Wider rollout follows device acceptance.

## Sources

- [Apple: extension uploads, shared containers, and background event handoff](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html)
- [Apple: shared-container session configuration](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/sharedcontaineridentifier)
- [Apple: Keychain sharing across targets](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
- [Supabase: session lifetimes and refresh behavior](https://supabase.com/docs/guides/auth/sessions)

These sources establish platform boundaries; the admission protocol, limits, and UI above are project design decisions.
