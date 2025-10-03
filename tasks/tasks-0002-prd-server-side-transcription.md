## Relevant Files

- `supabase/schema.sql` (or relevant migration scripts) - Define transcription job table, status fields, and indexes.
- `supabase/functions/*` - Potential new edge functions or updates for job creation/status access control.
- `RenderService/src/index.ts` (new) - Entry point for Render web API handling job creation and status queries.
- `RenderWorker/src/worker.ts` (new) - Background worker processing transcription jobs and orchestrating chunk transcription.
- `SnipNote/SupabaseManager.swift` - Client-side Supabase interactions; add job creation/status polling helpers.
- `SnipNote/OpenAIService/OpenAIService.swift` - Reference for existing chunking logic and model usage to port server-side.
- `SnipNote/MeetingsView.swift` & `SnipNote/MeetingDetailView.swift` - UI surfaces to trigger job polling and reflect status changes.
- `SnipNote/CreateMeetingView.swift` - Flow where "Analyze Meeting" triggers server-side job creation.
- `SnipNote/NotificationService.swift` - Configure local notification when status transitions to completed.
- `SnipNoteTests/*` - Extend or add tests covering new client job-hand-off logic.

### Notes

- Unit tests for new server components should live alongside their source (e.g., `RenderService/src/index.test.ts`).
- Prefer existing testing approaches (e.g., XCTest for iOS, Jest/Vitest for Node services).

## Tasks

- [ ] 1.0 Provision Render-based transcription architecture (API service + worker topology, deployment targets, environment configuration plan)
  - [ ] 1.1 Define Render service layout (web service for APIs, background worker for transcription pipeline).
  - [ ] 1.2 Document environment variables (Supabase keys, OpenAI keys, storage endpoints) and secrets management.
  - [ ] 1.3 Determine deployment configuration (instances, region, scaling thresholds) and CI/CD integration plan.
  - [ ] 1.4 Outline network/security model between Render services, Supabase, and client app (HTTPS, JWT validation).

- [ ] 2.0 Build server-side transcription job pipeline (job ingestion endpoint, chunk management, GPT-4o-transcribe integration, Supabase persistence)
  - [ ] 2.1 Implement authenticated `/jobs` endpoint to accept job creation requests with audio metadata.
  - [ ] 2.2 Validate request payloads, confirm user access to meeting/audio path via Supabase lookup.
  - [ ] 2.3 Enqueue job into worker queue or task scheduler (Render cron/worker, Redis, Supabase queue).
  - [ ] 2.4 Implement worker logic to download audio, chunk it, and call `gpt-4o-transcribe` per chunk.
  - [ ] 2.5 Stitch chunk transcripts, summaries, and metadata; persist results to Supabase tables.
  - [ ] 2.6 Handle failure states, retries, and partial progress logging with clear status updates.

- [ ] 3.0 Extend mobile client hand-off flow (audio upload handling, job creation requests, status polling, local notification trigger)
  - [ ] 3.1 Update client upload flow to ensure audio is stored (Supabase bucket) before job creation.
  - [ ] 3.2 Add API call to enqueue transcription job when user taps "Analyze Meeting" or uploads voice memo.
  - [ ] 3.3 Implement status polling using new `/jobs/{id}` endpoint with sensible polling cadence.
  - [ ] 3.4 Update UI state bindings to reflect `pending`, `in_progress`, `completed`, and `failed` statuses.
  - [ ] 3.5 Trigger local notification when job status transitions to `completed` while app is backgrounded.

- [ ] 4.0 Update Supabase data layer (job metadata schema, permissions, minutes/cost reconciliation)
  - [ ] 4.1 Design and migrate Supabase schema for transcription jobs (table, indexes, policy updates).
  - [ ] 4.2 Ensure Supabase Row Level Security policies allow authorized job creation and status reads only.
  - [ ] 4.3 Integrate job completion with minutes/cost tracking tables, maintaining idempotency.
  - [ ] 4.4 Add audit fields/logging hooks for job lifecycle (timestamps, error context).

- [ ] 5.0 Implement observability, reliability, and security safeguards (auth enforcement, logging/metrics, timeout & retry policies, operational playbooks)
  - [ ] 5.1 Enforce authentication/authorization on all Render endpoints and worker operations.
  - [ ] 5.2 Instrument logging for job lifecycle events, latency, and failure analytics; define dashboards/alerts.
  - [ ] 5.3 Configure timeout and retry policies for audio downloads, OpenAI calls, and Supabase writes.
  - [ ] 5.4 Document operational runbooks (retries, manual requeues, failure handling) and address open questions (Render plan, scaling, storage strategy).
