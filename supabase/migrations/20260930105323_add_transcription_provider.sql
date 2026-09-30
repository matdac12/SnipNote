-- Additive: legacy jobs remain OpenAI; existing policies and grants are unchanged.
ALTER TABLE public.transcription_jobs
  ADD COLUMN IF NOT EXISTS transcription_provider text NOT NULL DEFAULT 'openai';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_constraint
    WHERE conrelid = 'public.transcription_jobs'::regclass
      AND conname = 'transcription_jobs_transcription_provider_check'
  ) THEN
    ALTER TABLE public.transcription_jobs
      ADD CONSTRAINT transcription_jobs_transcription_provider_check
      CHECK (transcription_provider IN ('openai', 'xai'));
  END IF;
END $$;

INSERT INTO public.ai_model_config (task, model, reasoning_effort, verbosity, fallback_model)
VALUES ('transcription_xai', 'grok-voice-transcribe-2.0', NULL, NULL, NULL)
ON CONFLICT (task) DO NOTHING;
