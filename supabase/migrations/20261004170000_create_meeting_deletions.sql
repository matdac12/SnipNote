-- Tombstones for deleted meetings (MAT-1658).
--
-- Pull sync used to delete any local meeting that was missing from the server,
-- which would erase a Guest's recordings once they create an Account. Devices now
-- remove a local meeting only when it has a row here. Only the id is stored, so the
-- meeting content itself is still hard-deleted from `meetings` / `transcription_jobs`.
--
-- Tombstones are written by a trigger so every delete path (iOS, web app, workers)
-- produces one. Otherwise a meeting deleted on the web would be pushed back by a
-- phone that still has it.

CREATE TABLE IF NOT EXISTS public.meeting_deletions (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    meeting_id UUID NOT NULL,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, meeting_id)
);

ALTER TABLE public.meeting_deletions ENABLE ROW LEVEL SECURITY;

-- Clients only read tombstones; the trigger below is the only writer.
CREATE POLICY "Users can view their own meeting deletions"
    ON public.meeting_deletions
    FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

CREATE OR REPLACE FUNCTION public.record_meeting_deletion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- When the whole account is deleted its meetings cascade away; skip those,
    -- the user row (and so the tombstone's foreign key target) is already gone.
    IF EXISTS (SELECT 1 FROM auth.users WHERE id = OLD.user_id) THEN
        INSERT INTO public.meeting_deletions (user_id, meeting_id)
        VALUES (OLD.user_id, OLD.id)
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION public.record_meeting_deletion() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER meetings_record_deletion
    AFTER DELETE ON public.meetings
    FOR EACH ROW
    EXECUTE FUNCTION public.record_meeting_deletion();
