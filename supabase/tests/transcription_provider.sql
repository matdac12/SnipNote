-- Run on a disposable database after the additive migration.
BEGIN;
CREATE TEMP TABLE provider_jobs (LIKE public.transcription_jobs INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
DO $$
DECLARE selected text;
BEGIN
  INSERT INTO provider_jobs (user_id, meeting_id, audio_url)
    VALUES (gen_random_uuid(), gen_random_uuid(), 'https://test.invalid/audio')
    RETURNING transcription_provider INTO selected;
  IF selected <> 'openai' THEN RAISE EXCEPTION 'Legacy job did not default to OpenAI'; END IF;
  INSERT INTO provider_jobs (user_id, meeting_id, audio_url, transcription_provider)
    VALUES (gen_random_uuid(), gen_random_uuid(), 'https://test.invalid/audio', 'xai');
  BEGIN
    INSERT INTO provider_jobs (user_id, meeting_id, audio_url, transcription_provider)
      VALUES (gen_random_uuid(), gen_random_uuid(), 'https://test.invalid/audio', 'unknown');
    RAISE EXCEPTION 'Unknown provider accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO provider_jobs (user_id, meeting_id, audio_url, transcription_provider)
      VALUES (gen_random_uuid(), gen_random_uuid(), 'https://test.invalid/audio', NULL);
    RAISE EXCEPTION 'NULL provider accepted';
  EXCEPTION WHEN not_null_violation THEN NULL;
  END;
  IF NOT EXISTS (SELECT FROM public.ai_model_config WHERE task = 'transcription_xai'
    AND model = 'grok-voice-transcribe-2.0' AND reasoning_effort IS NULL
    AND verbosity IS NULL AND fallback_model IS NULL) THEN
    RAISE EXCEPTION 'xAI configuration seed differs';
  END IF;
END $$;
ROLLBACK;
