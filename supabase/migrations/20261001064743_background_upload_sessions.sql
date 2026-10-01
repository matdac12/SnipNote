-- Additive only. Rehearse against the current legacy schema before approval.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
CREATE TABLE public.background_upload_sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  meeting_id uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
  reserved_job_id uuid NOT NULL UNIQUE,
  manifest_digest text NOT NULL,
  transcription_provider text NOT NULL CHECK (transcription_provider IN ('openai','xai')),
  language text,
  duration double precision NOT NULL CHECK (duration > 0 AND duration < 'Infinity'::float8),
  status text NOT NULL DEFAULT 'awaiting_upload' CHECK (status IN ('awaiting_upload','queued','expired','cancelled')),
  upload_deadline timestamptz NOT NULL,
  last_checked_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, meeting_id)
);
CREATE TABLE public.background_upload_files (
  session_id uuid NOT NULL REFERENCES public.background_upload_sessions(id) ON DELETE CASCADE,
  index integer NOT NULL CHECK (index >= 0),
  path text NOT NULL UNIQUE,
  expected_bytes bigint NOT NULL CHECK (expected_bytes > 0 AND expected_bytes <= 15728640),
  duration double precision NOT NULL CHECK (duration > 0 AND duration < 'Infinity'::float8),
  content_type text NOT NULL,
  verified_at timestamptz,
  PRIMARY KEY (session_id, index)
);
CREATE INDEX background_upload_unfinished_scan ON public.background_upload_sessions(last_checked_at, id)
  WHERE status = 'awaiting_upload';
ALTER TABLE public.background_upload_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.background_upload_files ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.background_upload_sessions, public.background_upload_files FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.background_upload_sessions, public.background_upload_files TO service_role;

-- Registration + all file metadata are one transaction, safe under repeated POSTs.
CREATE FUNCTION public.register_background_upload(p_session jsonb, p_files jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE sid uuid; owner_id uuid := (p_session->>'user_id')::uuid; mid uuid := (p_session->>'meeting_id')::uuid;
BEGIN
  PERFORM id FROM public.meetings WHERE id = mid AND user_id = owner_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'meeting_not_found'; END IF;
  SELECT id INTO sid FROM public.background_upload_sessions WHERE user_id = owner_id AND meeting_id = mid;
  IF sid IS NOT NULL THEN RETURN sid; END IF;
  INSERT INTO public.background_upload_sessions(id,user_id,meeting_id,reserved_job_id,manifest_digest,transcription_provider,language,duration,upload_deadline)
  VALUES ((p_session->>'id')::uuid,owner_id,mid,(p_session->>'reserved_job_id')::uuid,p_session->>'manifest_digest',p_session->>'transcription_provider',p_session->>'language',(p_session->>'duration')::float8,(p_session->>'upload_deadline')::timestamptz)
  RETURNING id INTO sid;
  INSERT INTO public.background_upload_files(session_id,index,path,expected_bytes,duration,content_type)
  SELECT sid,(f->>'index')::integer,f->>'path',(f->>'expected_bytes')::bigint,(f->>'duration')::float8,f->>'content_type FROM jsonb_array_elements(p_files) f;
  IF NOT FOUND THEN RAISE EXCEPTION 'empty_manifest'; END IF;
  RETURN sid;
END $$;
REVOKE ALL ON FUNCTION public.register_background_upload(jsonb,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_background_upload(jsonb,jsonb) TO service_role;
COMMIT;
