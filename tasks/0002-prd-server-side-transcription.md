# PRD: Render Server-Side Transcription Service

## Introduction/Overview

SnipNote currently performs meeting transcription work on-device, forcing users to keep the app in the foreground to avoid iOS background execution limits. The goal is to offload transcription sessions to a Render-hosted backend so users can upload or hand off audio, lock their phones, and receive results without managing foreground tasks. This PRD defines the server-side workflow, mobile hand-off, and status tracking required to maintain current UX while improving reliability and scalability.

## Goals

1. Allow users to safely background or lock their devices while transcription continues server-side.
2. Improve reliability for long-form (>2 hour) recordings by centralizing processing and chunk management.
3. Maintain existing client UX and Supabase integrations while transparently delegating processing to Render.
4. Ensure authentication, storage, and status updates align with existing SnipNote security practices.

## User Stories

### US-1: Voice Memo Uploads
**As a** SnipNote user who imports voice memos
**I want** my uploaded audio to be processed server-side after I submit it
**So that** I can close the app and return later to a completed transcript.

### US-2: In-App Recording Hand-Off
**As a** user recording a meeting inside SnipNote
**I want** the app to hand the recording to a backend transcription job when I tap "Analyze Meeting"
**So that** I can leave the app while transcription finalizes.

### US-3: Progress Awareness
**As a** user waiting on transcription results
**I want** the app to show me when processing is pending, in progress, or complete
**So that** I know when to expect meeting summaries without refreshing manually.

## Functional Requirements

### FR-1: Job Creation & Audio Upload (Priority: Critical)
1.1. The mobile app MUST upload finalized audio files (voice memo imports or in-app recordings) to Supabase storage or another existing secure bucket before invoking server-side transcription.
1.2. The mobile app MUST create a transcription job record (e.g., in Supabase) with metadata: user identifier, meeting reference, audio file location, duration, file size, and chunking flag.
1.3. The Render service MUST expose an authenticated endpoint (e.g., `/jobs`) that the mobile app calls to enqueue processing, returning a job identifier used for polling.

### FR-2: Long-Form Audio Handling (Priority: Critical)
2.1. The Render service MUST support processing audio sessions exceeding two hours by reusing/expanding the existing chunking strategy.
2.2. The service MUST stream or download audio in manageable chunks to respect Render memory/time limits.
2.3. The service MUST ensure chunk boundaries and stitching logic preserve transcript accuracy (timestamps, speaker tags if present).

### FR-3: Transcription Processing Pipeline (Priority: Critical)
3.1. The Render worker MUST call OpenAI's `gpt-4o-transcribe` model for each chunk according to current cost tracking conventions.
3.2. The pipeline MUST capture and consolidate chunk outputs into a final transcript, summaries, and metadata currently stored in Supabase.
3.3. The worker MUST update job status transitions (`pending → in_progress → completed` or `failed`) and persist partial progress for observability.
3.4. On failure, the worker MUST record error context and mark the job as `failed` without losing existing meeting data.

### FR-4: Status Polling API (Priority: High)
4.1. The Render service MUST expose an authenticated status endpoint (e.g., `/jobs/{id}`) returning job state, percent complete (if available), and timestamps.
4.2. The mobile app MUST poll the status endpoint on a cadence configurable in the client (default suggestion: every 15–30 seconds while view is visible, less frequently when backgrounded via background fetch).
4.3. When status transitions to `completed`, the mobile app MUST set a local notification flag so iOS presents a notification without requiring push infrastructure.
4.4. The status endpoint MUST return failure reasons where applicable so the mobile app can surface actionable messaging.

### FR-5: Result Persistence (Priority: High)
5.1. Upon completion, the worker MUST write transcripts, summaries, and associated metadata back to the existing Supabase tables.
5.2. The worker MUST update any usage/minutes tracking tables currently used for billing.
5.3. The worker MUST ensure idempotency—rerunning the same job MUST NOT duplicate minutes or transcripts.

### FR-6: Authentication & Authorization (Priority: High)
6.1. All Render endpoints MUST require the same auth scheme used today (e.g., Supabase JWT or service key validation) to ensure only legitimate clients enqueue jobs or read statuses.
6.2. The system MUST validate that the requesting user owns the referenced meeting/audio before enqueueing a job.
6.3. All network traffic MUST use HTTPS; shared secrets MUST be stored in Render environment variables.

### FR-7: Observability & Operations (Priority: Medium)
7.1. The service MUST log job lifecycle events, errors, and latency metrics to aid debugging.
7.2. The service SHOULD expose lightweight health checks suitable for Render monitoring.
7.3. Operational dashboards or alerts SHOULD highlight failed jobs and long-running sessions beyond a configurable SLA (e.g., >3 hours).

### FR-8: Timeouts & Retries (Priority: Medium)
8.1. The worker MUST implement configurable timeouts for downloading audio, calling OpenAI, and writing to Supabase to avoid indefinite runs.
8.2. The worker MUST retry transient failures (network, 5xx) with exponential backoff while respecting overall job deadlines.
8.3. Jobs exceeding the maximum runtime MUST mark as failed with a clear timeout reason for the client.

## Non-Goals (Out of Scope)

- Adding push notification infrastructure; local notifications triggered from client polling are sufficient.
- Redesigning mobile UX beyond status indicators already present.
- Changing pricing or subscription gating for transcription features.
- Implementing Render billing upgrades (decision deferred).

## Design Considerations

- Majority of audio originates from iOS Voice Notes imports; flow should prioritize efficient uploads and resumable storage writes.
- The same pipeline must support immediate hand-off from in-app recordings after "Analyze Meeting" without additional user prompts.
- Maintain parity with existing Supabase schema for transcripts, minutes tracking, and cost allocation to avoid downstream changes.
- Consider background fetch cadence and battery impact when defining polling intervals and local notification triggers.

## Technical Considerations

- Render environment is selected but not yet provisioned; the PRD assumes creation of at least one background worker (cron or queue-based) and an API web service.
- Evaluate whether Supabase storage bandwidth is sufficient for large files; if not, document any requirements for alternative storage (e.g., S3) while keeping API identical to the client.
- Ensure chunking implementation aligns with prior on-device logic to keep transcription accuracy and formatting consistent.
- Securely manage OpenAI API keys within Render environment variables and rotate as needed.
- Confirm server-side OpenAI usage is compatible with existing cost tracking assumptions to prevent billing discrepancies.

## Success Metrics

- Formal quantitative metrics are deferred. Track operationally via the ratio of jobs finished while the app is backgrounded versus foreground, and monitor failure/timeout counts for regressions.

## Open Questions

1. Notification flow: Should the client also surface in-app banners or timeline events when polling detects completion?
2. Render plan: Do we need a dedicated Render Pro account for concurrency, bandwidth, or worker limits?
3. Storage strategy: Is Supabase storage adequate for peak load, or should we plan for alternative blob storage?
4. Scaling: Do we require a job queue (e.g., Redis, Supabase queues) to prevent overload during simultaneous long recordings?
5. Cost monitoring: Should we add additional instrumentation to reconcile server-side usage with existing cost dashboards?
6. Background polling limits: What iOS background modes will be leveraged to ensure timely status checks without draining battery?
