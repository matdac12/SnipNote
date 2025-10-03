-- Create enum for job status
CREATE TYPE transcription_job_status AS ENUM ('pending', 'processing', 'completed', 'failed');

-- Create transcription_jobs table
CREATE TABLE IF NOT EXISTS public.transcription_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    meeting_id UUID NOT NULL,
    audio_url TEXT NOT NULL,
    status transcription_job_status NOT NULL DEFAULT 'pending',
    transcript TEXT,
    duration FLOAT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Create indexes for efficient querying
CREATE INDEX idx_transcription_jobs_user_id ON public.transcription_jobs(user_id);
CREATE INDEX idx_transcription_jobs_status ON public.transcription_jobs(status);
CREATE INDEX idx_transcription_jobs_created_at ON public.transcription_jobs(created_at DESC);
CREATE INDEX idx_transcription_jobs_meeting_id ON public.transcription_jobs(meeting_id);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_transcription_jobs_updated_at
    BEFORE UPDATE ON public.transcription_jobs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE public.transcription_jobs ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only insert jobs for themselves
CREATE POLICY "Users can create their own transcription jobs"
    ON public.transcription_jobs
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- RLS Policy: Users can only read their own jobs
CREATE POLICY "Users can view their own transcription jobs"
    ON public.transcription_jobs
    FOR SELECT
    USING (auth.uid() = user_id);

-- RLS Policy: Users can update their own jobs (for retry scenarios)
CREATE POLICY "Users can update their own transcription jobs"
    ON public.transcription_jobs
    FOR UPDATE
    USING (auth.uid() = user_id);

-- RLS Policy: Service role can do anything (for worker processing)
CREATE POLICY "Service role has full access to transcription jobs"
    ON public.transcription_jobs
    FOR ALL
    USING (auth.role() = 'service_role');

-- Add comment to table
COMMENT ON TABLE public.transcription_jobs IS 'Tracks server-side audio transcription jobs for SnipNote meetings';
COMMENT ON COLUMN public.transcription_jobs.status IS 'Job status: pending (queued), processing (in progress), completed (success), failed (error)';
COMMENT ON COLUMN public.transcription_jobs.audio_url IS 'Supabase Storage URL or public URL to audio file';
COMMENT ON COLUMN public.transcription_jobs.duration IS 'Audio duration in seconds';
