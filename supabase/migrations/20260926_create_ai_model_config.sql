-- Central model configuration for every AI task.
-- Read by the openai-proxy Edge Function (iOS calls) and the VPS transcription
-- worker (server-side summaries). Edit rows in the Table Editor to switch models;
-- changes apply within ~60 seconds, no app release or redeploy needed.
--
-- NULL reasoning_effort / verbosity = leave whatever the caller sent.
-- fallback_model = retried once if OpenAI rejects the request with 400/404
-- (e.g. typo in model name, unsupported parameter). NULL disables the retry.

CREATE TABLE IF NOT EXISTS public.ai_model_config (
    task              text PRIMARY KEY,
    model             text NOT NULL,
    reasoning_effort  text,
    verbosity         text,
    fallback_model    text,
    notes             text,
    updated_at        timestamptz NOT NULL DEFAULT now()
);

-- Service role only (Edge Function + VPS). No policies = no client access.
ALTER TABLE public.ai_model_config ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.touch_ai_model_config_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ai_model_config_updated_at ON public.ai_model_config;
CREATE TRIGGER ai_model_config_updated_at
BEFORE UPDATE ON public.ai_model_config
FOR EACH ROW EXECUTE FUNCTION public.touch_ai_model_config_updated_at();

INSERT INTO public.ai_model_config (task, model, reasoning_effort, verbosity, fallback_model, notes) VALUES
    ('overview',       'gpt-6-luna', 'low', 'low',    'gpt-6-luna', 'One-sentence meeting overview (iOS + VPS)'),
    ('summary',        'gpt-6-luna', 'low', 'low',    'gpt-6-luna', 'Full meeting summary (iOS + VPS)'),
    ('actions',        'gpt-6-luna', 'low', NULL,     'gpt-6-luna', 'Action item extraction, JSON output (iOS + VPS)'),
    ('title',          'gpt-6-luna', 'low', NULL,     'gpt-6-luna', 'Meeting title (iOS)'),
    ('text_summary',   'gpt-6-luna', 'low', NULL,     'gpt-6-luna', 'Generic transcript summary, summarizeText (iOS)'),
    ('eve_chat',       'gpt-6-luna', 'low', 'medium', 'gpt-6-luna', 'Eve chat with stored prompt (iOS)'),
    ('actions_report', 'gpt-6-luna', 'low', NULL,     'gpt-6-luna', 'Actions report, Chat Completions API (iOS)')
ON CONFLICT (task) DO NOTHING;
