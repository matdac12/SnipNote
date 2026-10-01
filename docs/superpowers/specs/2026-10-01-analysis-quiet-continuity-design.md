# Analysis experience: quiet continuity

Date: 2026-10-01
Status: Quiet continuity selected by the owner; specification accepted as the basis for implementation planning on 2026-10-01. Implementation awaits plan review.
Scope: SnipNote's in-app analysis presentation.

## Decision and intent

The owner selected **Quiet continuity** after reviewing three animated HTML previews. The approved direction is a calm, spacious analysis surface that remains visually continuous across preparation, upload, queueing, and server processing. It uses SnipNote's existing orange accent, semantic system surfaces, system typography, and restrained motion.

The experience must make the short preparation interval and subsequent freedom to leave unmistakable. Once preparation finishes **and background upload tasks are registered**, the user can switch apps or lock the phone while upload continues. Upload completion is not the permission boundary.

The preview is a visual reference, not a functional specification for its artificial timings, browser controls, phone frame, or sample meeting data. Its light/dark and language controls are review tools, not proposed app controls.

Reference preview: `/Users/mattia/.codex/visualizations/2026/10/01/01a0f6c2-de14-70e3-b15e-a3e6737d5eae/analysis-previews/quiet.html`.

## Existing foundation

- App integration baseline: `12e6323`.
- Transcription service main baseline: `471ae67`.
- Physical-phone trials succeeded, including a recording of approximately 1 hour 26 minutes uploaded after leaving the app.
- Production remains owner-only; the owner will handle app release separately.
- `CreateMeetingView` creates the meeting and navigates before the durable upload manifest necessarily exists.
- `MeetingDetailView` currently presents background-upload snapshots with a compact stack, and other processing paths with `MinimalistProcessingView`.
- `BackgroundUploadManifest.transferRegistered` exposes the existing upload-registration safety signal. The view must consume actual lifecycle state rather than infer readiness from elapsed time or bytes sent.
- A background manifest can remain `.queued` while its associated server job is processing. That manifest phase must not mask the more specific job status.

No service API, database schema, upload transport, retry-budget, account-isolation, or audio-retention change is required by this design.

## Scope boundaries

Include the cloud analysis path initiated from the existing recording/import flows, its meeting-detail presentation, preparation, upload progress, server queue/processing, retry/error presentation, and transition into existing results. Preserve current entry points and navigation.

Existing local processing must retain accurate keep-open guidance. Shared visual treatment may be reused where appropriate, but this design does not change local transcription behavior or falsely extend background-upload guarantees to it. The legacy foreground upload route must likewise retain its own keep-open requirements.

Exclude Live Activities, new background mechanisms, notifications, app release, service rollout, provider changes, new cancellation semantics, result-layout redesign, and the other two visual directions. Do not add the preview's simulated Switch apps button to the app.

## Layout and visual hierarchy

Keep the existing meeting header and native navigation visible. Place one analysis surface beneath the header with consistent horizontal gutters and generous vertical spacing.

Its order is:

1. Small phase label.
2. Prominent stage title.
3. A stable visual region for either measured upload percentage or restrained activity indication.
4. Thin orange progress line in a neutral track.
5. Secondary progress detail, such as transferred and total bytes.
6. Readable guidance panel.
7. Recovery action only when the current state requires it.

Use `AppTheme` colors and corner-radius conventions. Primary headings use `textColor`; supporting text uses `secondaryTextColor` without additional opacity that compromises readability. Use the orange accent for progress. The safe-to-leave panel uses a semantic success treatment with separate light/dark values and explicit words; meaning must remain clear without color. Its confirmation symbol, if used, accompanies equivalent text and is decorative for VoiceOver.

Upload percentage is prominent but subordinate to the title and permission guidance. Use monospaced digits for percentage and byte counts. Font sizing must scale with Dynamic Type. Preserve visual anchors under ordinary text sizes; allow vertical expansion and scrolling at accessibility sizes rather than clipping content or forcing fixed heights.

Do not add waveform animation, stage-step navigation, particles, glowing orbs, or extra nested cards.

## State presentation

| State | Title and indicator | Guidance and behavior |
| --- | --- | --- |
| Initiating, before upload snapshot | Preparing your audio; indeterminate activity | Keep SnipNote open for now. Show immediately after initiation, including while routing/registration is unresolved. Do not briefly claim that upload has begun. |
| Preparing files / finishing registration | Preparing your audio; indeterminate activity | Keep SnipNote open for now. Preserve this guidance until the actual background registration condition is satisfied. |
| Registered background upload | Uploading your audio; measured upload percentage and byte progress | You can leave now. Switch apps or lock your phone. Uploading continues. |
| All bytes sent, awaiting server confirmation | Finishing upload; completed upload line with a restrained activity cue | Retain safe-to-leave guidance where the registered transfer remains valid. Do not equate 100% upload with successful server acceptance or completed analysis. |
| Server queued | Waiting to transcribe; indeterminate activity | You can leave now. Your audio is uploaded. Processing will continue. |
| Server working | Use a normalized localized stage title, such as Transcribing your meeting or Finding the key points; indeterminate activity unless trustworthy measured progress exists | You can leave now. Your meeting is being processed on the server. |
| Completed | Brief confirmation if currently visible, then existing meeting results | Do not hold the user on a completion screen or delay results for animation. |
| Recoverable upload interruption | Upload paused; quiet static presentation with preserved progress detail when meaningful | Explain the interruption and expose the existing retry action. Do not continue showing a generic safe-to-leave promise if recovery requires foreground attention. |
| Terminal failure | Specific localized failure title, retained-audio explanation only when supported, existing recovery actions | Keep errors and actions in the same visual area. Follow existing retry/resume capabilities. |

A server job that is pending must not be labeled as an active upload merely because the older job-status presentation maps pending to uploading. Once upload acceptance is established, pending means server queueing.

No overall preparation-to-results percentage is introduced. Upload progress is explicitly scoped to bytes transferred. Preparation has no invented percentage or duration estimate. Do not smooth values by advancing them beyond measured progress. Network stalls must preserve the last measured value rather than simulate advancement.

For server processing, use backend status/stage only where it is meaningful and supported. Normalize user-facing labels into English/Italian instead of displaying arbitrary raw server strings. Do not imply finer-grained stages that are not observable. Do not introduce a server estimate without independently justified data.

## Presentation state and data flow

Introduce a small, testable presentation resolver for the analysis surface. It derives a semantic state, progress details, guidance, and permitted actions from existing meeting state, background-upload snapshot, route, and server-job state. Keep transport and SwiftData mutations out of the visual component.

State precedence must recognize terminal meeting results/failure, upload recovery, preparation/registration, active upload or confirmation, and associated server queue/processing as appropriate. An upload manifest's `.queued` phase means upload handoff occurred; it must not override a known running server job. During a status-refresh gap, retain the last confirmed truthful stage and safety information instead of resetting the screen to uploading.

The initial preparation presentation must exist before a snapshot is available. If routing selects local transcription or legacy foreground upload, transition to that route's accurate stage and keep-open guidance without presenting background-upload permission.

Keep the analysis component's identity stable across stage updates. Returning to the meeting restores current state from the existing sources of truth. Returning must not replay initiation or the permission milestone, restart work, or reset progress. Visual timers never control functional transitions.

## Motion

- Tap feedback remains immediate and native. Prevent duplicate initiation through existing busy-state semantics; add no artificial waiting period.
- Retain normal app navigation. Do not require a cross-screen button morph or change navigation architecture.
- Stage titles and guidance crossfade in place over approximately 200–300 ms. A very small entrance displacement is acceptable on initial initiation only.
- Measured upload fill retargets smoothly with ease-out, approximately 200–300 ms. Avoid spring overshoot and bouncing numeric transitions. The displayed value remains the measured value.
- Animate one restrained indeterminate treatment at a time. Avoid animating both a large hero motif and the progress line continuously.
- The safe-to-leave transition is a single clearly visible change in panel text and semantic appearance when registration is confirmed. Do not use celebration or repeat the transition on ordinary status polling.
- Short states can pass naturally. Do not delay preparation, transfer, or results to complete choreography.
- Completion fades softly into existing results. Interrupted transitions retarget to the newest state.
- Returning to an existing job shows its current presentation without a staged entrance sequence.

## English and Italian copy

Use the existing app-language resolution and string catalog consistently, including dynamic stage titles. Parameterized progress text uses locale-aware formatting.

| Purpose | English | Italian |
| --- | --- | --- |
| Preparation title | Preparing your audio | Preparazione dell’audio |
| Preparation guidance title | Keep SnipNote open for now | Tieni SnipNote aperta per ora |
| Preparation guidance detail | This is brief. We’ll let you know when you can leave. | Ci vorrà poco. Ti avviseremo quando potrai uscire. |
| Upload title | Uploading your audio | Caricamento dell’audio |
| Permission title | You can leave now | Ora puoi uscire dall’app |
| Upload permission detail | Switch apps or lock your phone. Uploading continues. | Puoi cambiare app o bloccare il telefono. Il caricamento continua. |
| Confirmation title | Finishing upload | Completamento del caricamento |
| Queue title | Waiting to transcribe | In attesa di trascrizione |
| Queue guidance detail | Your audio is uploaded. Processing will continue. | L’audio è caricato. L’elaborazione continuerà. |
| Transcription title | Transcribing your meeting | Trascrizione della riunione |
| Analysis title | Finding the key points | Individuazione dei punti chiave |
| Server guidance detail | Your meeting is being processed on the server. | La riunione viene elaborata sul server. |
| Paused upload | Upload paused | Caricamento in pausa |
| Retry action | Retry upload | Riprova caricamento |

Preparation copy sets an expectation of brevity, not a fixed deadline. If preparation takes unusually long, preserve accurate keep-open guidance; do not promise a countdown or switch to a safe state on a timer. Avoid wording that instructs force-quitting the app: permission specifically concerns switching apps or locking the phone.

## Accessibility

- Honor Reduce Motion: stop decorative loops, displacement, and animated numerical rolling; use static activity cues and direct updates or brief opacity changes.
- Support large Dynamic Type, small phones, landscape, and iPad without truncating permission guidance or recovery controls.
- VoiceOver order follows the visual hierarchy. Group status and progress coherently; expose a progress value and meaningful stage.
- Announce stage changes and the newly safe-to-leave milestone once. Do not announce every byte update, polling result, or animation frame; do not unexpectedly steal focus.
- All actions retain descriptive labels and at least 44-point touch targets.
- Maintain readable text contrast in both appearances. Orange progress and success treatment must not be the sole indicators of state. Verify increased-contrast and differentiate-without-color settings.

## Anticipated app touchpoints

- `SnipNote/CreateMeetingView.swift`: truthful immediate initiation presentation and existing route integration.
- `SnipNote/MeetingDetailView.swift`: one continuous surface, correct upload/server precedence, recovery and results transitions.
- Dedicated analysis presentation state/resolver and SwiftUI view files: declarative rendering and deterministic state derivation.
- `SnipNote/Theme.swift`: semantic success treatment if no suitable shared token exists.
- `SnipNote/Localizable.xcstrings`: complete English/Italian copy.
- Existing minimalist components: reuse or adapt only within this scope; avoid changing unrelated processing paths without checking their guidance and motion.
- `SnipNoteTests` and focused UI validation: safety-state and presentation mapping checks.

The coordinator's registration guarantee remains authoritative. This spec does not authorize changing its functional boundary to match visual timing. No transcription-service change is anticipated.

## Acceptance and verification

1. Immediately after initiation, the detail presentation shows preparation rather than a misleading upload fallback.
2. While preparation or registration is unfinished, guidance asks the user to keep the app open.
3. Once background upload tasks are confirmed registered, safe-to-leave guidance appears even at zero or low upload progress.
4. Upload progress reflects bytes only, remains stable during stalls, and does not claim analysis completion at 100%.
5. A known running server job is shown as processing despite an upload manifest remaining queued.
6. Returning during upload, queueing, or processing restores the current stage without resetting work or replaying the permission transition.
7. Retry/failure states retain existing recoverability and do not promise background continuation when foreground recovery is required.
8. Local and legacy foreground routes never inherit the background-upload safety promise.
9. English and Italian guidance remains fully readable under large Dynamic Type, light/dark appearance, and small-screen layouts.
10. Reduce Motion stops decorative motion; VoiceOver announces the handoff once and exposes usable progress and recovery actions.
11. Existing completed results appear promptly without changing their content or interactions.

Verify the presentation resolver with deterministic state-mapping tests, particularly registration false/true, queued manifest with running job, status gaps, retry, and local/legacy routes. Build and run relevant app tests on an available simulator. Inspect the full sequence, rapid phase changes, long preparation, stalled upload, interruption/retry, and return-to-app behavior. Review motion at slow speed and normal speed; verify both appearances, accessibility settings, English/Italian, phone/landscape/iPad layouts. Repeat a physical-device background-upload check to confirm the visual work has not regressed the accepted behavior.

## Review boundary

This document records the selected direction and proposed behavior. Writing it does not begin app implementation. After the owner reviews the written specification, agree on the implementation step separately. Live Activities and release remain separate future work.
