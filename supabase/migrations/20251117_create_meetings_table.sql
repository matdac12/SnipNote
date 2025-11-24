-- Create meetings table to store meeting metadata (title, location, notes, etc.)
-- This syncs with the iOS SwiftData Meeting model

CREATE TABLE IF NOT EXISTS public.meetings (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Core meeting metadata
    name TEXT NOT NULL,
    location TEXT,
    meeting_notes TEXT,  -- Pre-meeting notes

    -- Timestamps
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    date_created TIMESTAMPTZ NOT NULL DEFAULT now(),
    date_modified TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Recording status
    has_recording BOOLEAN NOT NULL DEFAULT FALSE,

    -- Processing state
    processing_state TEXT NOT NULL DEFAULT 'pending',  -- pending, transcribing, generating_summary, failed, completed
    processing_error TEXT,
    is_processing BOOLEAN NOT NULL DEFAULT FALSE,

    -- Chunk tracking (for progress display)
    last_processed_chunk INTEGER DEFAULT 0,
    total_chunks INTEGER DEFAULT 0,

    -- Server-side transcription reference
    transcription_job_id UUID,

    -- Indexes for common queries
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own meetings
CREATE POLICY "Users can view their own meetings"
    ON public.meetings
    FOR SELECT
    USING (auth.uid() = user_id);

-- Policy: Users can insert their own meetings
CREATE POLICY "Users can insert their own meetings"
    ON public.meetings
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Policy: Users can update their own meetings
CREATE POLICY "Users can update their own meetings"
    ON public.meetings
    FOR UPDATE
    USING (auth.uid() = user_id);

-- Policy: Users can delete their own meetings
CREATE POLICY "Users can delete their own meetings"
    ON public.meetings
    FOR DELETE
    USING (auth.uid() = user_id);

-- Indexes for performance
CREATE INDEX idx_meetings_user_id ON public.meetings(user_id);
CREATE INDEX idx_meetings_date_created ON public.meetings(date_created DESC);
CREATE INDEX idx_meetings_transcription_job_id ON public.meetings(transcription_job_id);

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_meetings_updated_at
    BEFORE UPDATE ON public.meetings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Add comment
COMMENT ON TABLE public.meetings IS 'Stores meeting metadata synced from iOS SwiftData. Links to recordings and transcription_jobs tables.';
