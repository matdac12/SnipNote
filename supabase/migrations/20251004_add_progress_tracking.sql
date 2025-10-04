-- Add progress tracking columns to transcription_jobs table
-- This enables real-time progress updates during long transcription jobs

ALTER TABLE public.transcription_jobs
ADD COLUMN progress_percentage INTEGER DEFAULT 0,
ADD COLUMN current_stage TEXT;

-- Add comments for documentation
COMMENT ON COLUMN transcription_jobs.progress_percentage IS 'Progress from 0-100 representing job completion percentage';
COMMENT ON COLUMN transcription_jobs.current_stage IS 'Human-readable stage description (e.g., "Transcribing chunk 2/5...")';

-- Add index for efficient progress queries
CREATE INDEX idx_transcription_jobs_progress ON transcription_jobs(progress_percentage) WHERE status = 'processing';
