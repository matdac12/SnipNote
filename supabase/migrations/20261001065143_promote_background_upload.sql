BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
CREATE FUNCTION public.promote_background_upload(p_session_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE s public.background_upload_sessions%ROWTYPE; m public.meetings%ROWTYPE; n integer;
BEGIN
  SELECT * INTO s FROM public.background_upload_sessions WHERE id=p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;
  IF s.status='queued' THEN RETURN s.reserved_job_id; END IF;
  IF s.status <> 'awaiting_upload' OR s.upload_deadline <= now() THEN RAISE EXCEPTION 'session_not_active'; END IF;
  SELECT * INTO m FROM public.meetings WHERE id=s.meeting_id AND user_id=s.user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'meeting_not_found'; END IF;
  IF m.transcription_job_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.transcription_jobs WHERE meeting_id=s.meeting_id) THEN
    RAISE EXCEPTION 'existing_job_conflict';
  END IF;
  SELECT count(*) INTO n FROM public.background_upload_files WHERE session_id=s.id;
  IF n=0 OR EXISTS (SELECT 1 FROM public.background_upload_files WHERE session_id=s.id AND verified_at IS NULL) THEN
    RAISE EXCEPTION 'files_not_verified';
  END IF;
  -- Even one file uses the supported chunk worker; no public URL credentials stored.
  INSERT INTO public.audio_chunks(meeting_id,user_id,chunk_index,total_chunks,file_path,file_size,duration_seconds)
  SELECT s.meeting_id,s.user_id,index,n,path,expected_bytes::integer,duration
    FROM public.background_upload_files WHERE session_id=s.id ORDER BY index;
  INSERT INTO public.transcription_jobs(id,user_id,meeting_id,status,is_chunked,total_chunks,chunks_processed,duration,language,transcription_provider)
  VALUES (s.reserved_job_id,s.user_id,s.meeting_id,'pending',true,n,0,s.duration,s.language,s.transcription_provider);
  UPDATE public.meetings SET transcription_job_id=s.reserved_job_id,has_recording=true,
    is_processing=true,processing_state='transcribing',total_chunks=n,
    upload_status='completed',upload_progress=100,uploaded_chunks=n WHERE id=s.meeting_id;
  UPDATE public.background_upload_sessions SET status='queued',updated_at=now() WHERE id=s.id;
  RETURN s.reserved_job_id;
END $$;
REVOKE ALL ON FUNCTION public.promote_background_upload(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.promote_background_upload(uuid) TO service_role;
COMMIT;
