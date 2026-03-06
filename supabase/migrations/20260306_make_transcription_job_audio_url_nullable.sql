-- Local-model transcription completes on device and does not require a stored audio asset.
ALTER TABLE public.transcription_jobs
ALTER COLUMN audio_url DROP NOT NULL;

COMMENT ON COLUMN public.transcription_jobs.audio_url IS
'Supabase Storage URL or public URL to audio file when a transcription job depends on remote audio; null for local-only jobs.';
