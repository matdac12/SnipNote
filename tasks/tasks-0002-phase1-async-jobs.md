## Relevant Files

- `supabase/migrations/[timestamp]_create_transcription_jobs.sql` - Migration to create transcription_jobs table with status tracking, RLS policies, and indexes.
- `snipnote-transcription-service/main.py` - FastAPI endpoints for job creation (`POST /jobs`), status checks (`GET /jobs/{id}`), and health check.
- `snipnote-transcription-service/transcribe.py` - OpenAI Whisper transcription logic (refactored to work with job processing).
- `snipnote-transcription-service/jobs.py` (new) - Job queue management and async processing logic using Render Background Worker pattern.
- `snipnote-transcription-service/supabase_client.py` (new) - Supabase Python client for job CRUD operations and status updates.
- `SnipNote/RenderTranscriptionService.swift` - Extended API client to support async job creation and status polling.
- `SnipNote/TranscriptionJobModels.swift` (new) - Swift models for job status, job response, and transcription result.
- `SnipNote/CreateMeetingView.swift` - Add server transcription toggle and async job handling flow.
- `SnipNote/MeetingDetailView.swift` - Display job status during async processing (pending, processing, completed).
- `SnipNote/SupabaseManager.swift` - Helper methods for querying transcription job status from Supabase (optional fallback).

### Notes

- Supabase migrations should be tested locally using `supabase migration new` and `supabase db push`.
- Python service will use environment variable `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` for server-side database access.
- iOS will poll job status every 15 seconds while CreateMeetingView is active, less frequently when backgrounded.
- Job processing will be triggered by Render cron job checking for `pending` jobs every minute.

## Tasks

- [x] 1.0 Create Supabase transcription_jobs table and security policies
  - [x] 1.1 Design table schema with columns: id (uuid, pk), user_id (uuid, fk to auth.users), meeting_id (uuid), audio_url (text), status (enum: pending/processing/completed/failed), transcript (text, nullable), duration (float, nullable), error_message (text, nullable), created_at (timestamp), updated_at (timestamp), completed_at (timestamp, nullable)
  - [x] 1.2 Create migration file in `supabase/migrations/` using Supabase CLI or Studio
  - [x] 1.3 Add Row Level Security (RLS) policies: users can only create jobs for their own user_id, users can only read their own jobs
  - [x] 1.4 Add indexes on user_id, status, and created_at for efficient querying
  - [x] 1.5 Test migration locally using `supabase db push` and verify table structure

- [ ] 2.0 Build Python async job creation and status endpoints
  - [ ] 2.1 Create `supabase_client.py` module with Supabase Python client initialization using environment variables (SUPABASE_URL, SUPABASE_SERVICE_KEY)
  - [ ] 2.2 Add helper functions in `supabase_client.py`: create_job(user_id, meeting_id, audio_url), get_job(job_id), update_job_status(job_id, status, transcript=None, error=None)
  - [ ] 2.3 Add `POST /jobs` endpoint in `main.py` that accepts {user_id, meeting_id, audio_url}, creates job record with status='pending', returns job_id
  - [ ] 2.4 Add `GET /jobs/{job_id}` endpoint that queries Supabase and returns job status, transcript (if completed), and timestamps
  - [ ] 2.5 Add basic authentication middleware (validate API key or JWT - can be simple for MVP, full auth in Phase 4)
  - [ ] 2.6 Update `requirements.txt` with `supabase-py` dependency
  - [ ] 2.7 Test endpoints locally using curl/Postman with test job creation and status retrieval

- [ ] 3.0 Implement Render Background Worker for job processing
  - [ ] 3.1 Create `jobs.py` module with `process_pending_jobs()` function that queries Supabase for jobs with status='pending'
  - [ ] 3.2 Implement job processing loop: for each pending job, update status to 'processing', download audio from audio_url, call transcribe_audio(), save transcript to job record
  - [ ] 3.3 Add error handling: wrap transcription in try/except, update job status to 'failed' with error_message if exception occurs
  - [ ] 3.4 Add job completion logic: update status to 'completed', set transcript and duration, set completed_at timestamp
  - [ ] 3.5 Create `worker.py` entry point that calls `process_pending_jobs()` and can be run as cron job or continuous loop
  - [ ] 3.6 Add Render cron job configuration (render.yaml or dashboard) to run worker.py every 1-2 minutes
  - [ ] 3.7 Test worker locally by creating test job in Supabase and running worker.py to verify it processes the job

- [ ] 4.0 Extend iOS API client for async job handling
  - [ ] 4.1 Create `TranscriptionJobModels.swift` with enums and structs: JobStatus enum (pending, processing, completed, failed), CreateJobRequest, CreateJobResponse, JobStatusResponse
  - [ ] 4.2 Add `createJob(userId: UUID, meetingId: UUID, audioURL: String)` method to RenderTranscriptionService that calls POST /jobs and returns job_id
  - [ ] 4.3 Add `getJobStatus(jobId: String)` method that calls GET /jobs/{id} and returns JobStatusResponse
  - [ ] 4.4 Add `pollJobStatus(jobId: String, interval: TimeInterval, completion: @escaping (JobStatusResponse) -> Void)` helper that uses Timer to poll status every 15 seconds
  - [ ] 4.5 Add cancellation support for polling (store Timer reference and invalidate when view disappears)
  - [ ] 4.6 Handle all job states in UI: show loading for pending/processing, show transcript for completed, show error for failed

- [ ] 5.0 Integrate async transcription into CreateMeetingView with toggle
  - [ ] 5.1 Add @State variable `useServerTranscription: Bool = true` and Toggle UI in settings/options section
  - [ ] 5.2 Refactor existing transcription logic into separate functions: `processOnDevice()` and `processServerSide()`
  - [ ] 5.3 Implement `processServerSide()`: upload audio to Supabase Storage, get audio URL, create transcription job via RenderTranscriptionService
  - [ ] 5.4 Add job polling in `processServerSide()`: start polling job status, update meeting.isProcessing = true, navigate to MeetingDetailView
  - [ ] 5.5 Add completion handler: when job status = completed, update meeting with transcript and summary, set isProcessing = false, send notification
  - [ ] 5.6 Keep existing on-device transcription flow intact for when toggle is OFF
  - [ ] 5.7 Test toggle switching between on-device and server transcription modes

- [ ] 6.0 Add job status monitoring UI in MeetingDetailView
  - [ ] 6.1 Add @State variables for job tracking: `jobId: String?`, `jobStatus: JobStatus?`, `jobErrorMessage: String?`
  - [ ] 6.2 Add visual indicator for job status: ProgressView with status text for pending/processing states
  - [ ] 6.3 Display job progress in header or dedicated section: "Transcribing on server... (Processing)" with animated indicator
  - [ ] 6.4 Handle completed state: hide progress indicator, show transcript and summary once available
  - [ ] 6.5 Handle failed state: show error message with retry button that recreates job
  - [ ] 6.6 Add background polling: continue polling job status while view is visible, pause when view disappears
  - [ ] 6.7 Add pull-to-refresh gesture to manually check job status

- [ ] 7.0 Test end-to-end async transcription flow
  - [ ] 7.1 Test job creation: create meeting with server transcription enabled, verify job record created in Supabase with status='pending'
  - [ ] 7.2 Test worker processing: verify Render cron/worker picks up pending job, processes it, and updates status to 'completed'
  - [ ] 7.3 Test iOS polling: verify app polls job status every 15 seconds and UI updates when status changes
  - [ ] 7.4 Test background scenarios: lock phone during processing, verify polling continues via background fetch, notification sent when complete
  - [ ] 7.5 Test error handling: create job with invalid audio URL, verify status updates to 'failed' with error message, verify UI shows error
  - [ ] 7.6 Test toggle functionality: verify on-device transcription still works when toggle is OFF
  - [ ] 7.7 Verify cost tracking: check user_usage table updates correctly for server-processed transcriptions (minutes and cost calculation)
