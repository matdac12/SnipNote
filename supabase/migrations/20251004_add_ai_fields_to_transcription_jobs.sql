-- Add AI-generated content fields to transcription_jobs table
ALTER TABLE public.transcription_jobs
    ADD COLUMN overview TEXT,
    ADD COLUMN summary TEXT,
    ADD COLUMN actions JSONB;

-- Add comments for new columns
COMMENT ON COLUMN public.transcription_jobs.overview IS 'AI-generated 1-sentence meeting overview (short summary)';
COMMENT ON COLUMN public.transcription_jobs.summary IS 'AI-generated full meeting summary';
COMMENT ON COLUMN public.transcription_jobs.actions IS 'AI-extracted action items as JSON array';
