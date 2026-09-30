-- Only the Edge Function service role can spend quota or register conversations.
-- Dedicated safety budgets do not replace or double-charge purchased minutes.
CREATE TABLE public.ai_proxy_limits (
  scope text PRIMARY KEY CHECK (scope IN ('user', 'global')),
  requests_per_minute integer NOT NULL CHECK (requests_per_minute > 0),
  requests_per_day integer NOT NULL CHECK (requests_per_day > 0),
  text_bytes_per_day bigint NOT NULL CHECK (text_bytes_per_day > 0),
  audio_bytes_per_day bigint NOT NULL CHECK (audio_bytes_per_day > 0),
  concurrent_requests integer NOT NULL CHECK (concurrent_requests > 0)
);
INSERT INTO public.ai_proxy_limits VALUES
  ('user', 20, 200, 16777216, 67108864, 3),
  ('global', 200, 5000, 536870912, 2147483648, 64);

CREATE TABLE public.ai_proxy_usage (
  scope text PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  minute_start timestamptz NOT NULL,
  minute_requests integer NOT NULL DEFAULT 0,
  day_start timestamptz NOT NULL,
  day_requests integer NOT NULL DEFAULT 0,
  text_bytes bigint NOT NULL DEFAULT 0,
  audio_bytes bigint NOT NULL DEFAULT 0,
  CHECK ((scope = 'global' AND user_id IS NULL) OR (user_id IS NOT NULL AND scope = 'user:' || user_id::text))
);

CREATE TABLE public.ai_proxy_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '150 seconds'
);
CREATE INDEX ai_proxy_reservations_expiry ON public.ai_proxy_reservations(expires_at);
CREATE INDEX ai_proxy_reservations_user ON public.ai_proxy_reservations(user_id, expires_at);

CREATE TABLE public.ai_proxy_conversations (
  id text PRIMARY KEY CHECK (id ~ '^conv_[A-Za-z0-9_-]+$'),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_count integer NOT NULL DEFAULT 0 CHECK (request_count BETWEEN 0 AND 30),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ai_proxy_conversations_user ON public.ai_proxy_conversations(user_id);

ALTER TABLE public.ai_proxy_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_proxy_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_proxy_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_proxy_conversations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ai_proxy_limits, public.ai_proxy_usage, public.ai_proxy_reservations,
  public.ai_proxy_conversations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ai_proxy_limits, public.ai_proxy_usage,
  public.ai_proxy_reservations, public.ai_proxy_conversations TO service_role;

CREATE FUNCTION public.reserve_ai_proxy_usage(p_user_id uuid, p_text_bytes bigint, p_audio_bytes bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_minute timestamptz := date_trunc('minute', v_now);
  v_day timestamptz := date_trunc('day', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_scope text;
  v_limits public.ai_proxy_limits%ROWTYPE;
  v_usage public.ai_proxy_usage%ROWTYPE;
  v_id uuid;
BEGIN
  IF p_user_id IS NULL OR p_text_bytes IS NULL OR p_audio_bytes IS NULL
    OR p_text_bytes < 0 OR p_audio_bytes < 0 THEN
    RAISE EXCEPTION 'Invalid quota input';
  END IF;
  -- Consistent lock order: global first, then caller. All Edge instances share it.
  INSERT INTO public.ai_proxy_usage(scope, user_id, minute_start, day_start)
  VALUES ('global', NULL, v_minute, v_day), ('user:' || p_user_id, p_user_id, v_minute, v_day)
  ON CONFLICT DO NOTHING;
  PERFORM scope FROM public.ai_proxy_usage
    WHERE scope IN ('global', 'user:' || p_user_id) ORDER BY scope FOR UPDATE;
  DELETE FROM public.ai_proxy_reservations WHERE expires_at <= v_now;
  FOREACH v_scope IN ARRAY ARRAY['global', 'user:' || p_user_id] LOOP
    SELECT * INTO STRICT v_limits FROM public.ai_proxy_limits
      WHERE scope = CASE WHEN v_scope = 'global' THEN 'global' ELSE 'user' END;
    SELECT * INTO STRICT v_usage FROM public.ai_proxy_usage WHERE scope = v_scope;
    IF v_usage.minute_start <> v_minute THEN v_usage.minute_requests := 0; END IF;
    IF v_usage.day_start <> v_day THEN
      v_usage.day_requests := 0; v_usage.text_bytes := 0; v_usage.audio_bytes := 0;
    END IF;
    IF v_usage.minute_requests >= v_limits.requests_per_minute
      OR v_usage.day_requests >= v_limits.requests_per_day
      OR v_usage.text_bytes + p_text_bytes > v_limits.text_bytes_per_day
      OR v_usage.audio_bytes + p_audio_bytes > v_limits.audio_bytes_per_day
      OR (SELECT count(*) FROM public.ai_proxy_reservations
          WHERE v_scope = 'global' OR user_id = p_user_id) >= v_limits.concurrent_requests THEN
      RETURN NULL;
    END IF;
  END LOOP;
  -- Update both budgets only after all checks pass. Failed upstream calls count too.
  UPDATE public.ai_proxy_usage SET
    minute_requests = CASE WHEN minute_start = v_minute THEN minute_requests ELSE 0 END + 1,
    day_requests = CASE WHEN day_start = v_day THEN day_requests ELSE 0 END + 1,
    text_bytes = CASE WHEN day_start = v_day THEN text_bytes ELSE 0 END + p_text_bytes,
    audio_bytes = CASE WHEN day_start = v_day THEN audio_bytes ELSE 0 END + p_audio_bytes,
    minute_start = v_minute, day_start = v_day
  WHERE scope IN ('global', 'user:' || p_user_id);
  INSERT INTO public.ai_proxy_reservations(user_id) VALUES (p_user_id) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.claim_ai_proxy_conversation(p_user_id uuid, p_conversation_id text)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  -- Ownership and turn admission are one atomic update. Unknown legacy IDs fail closed.
  UPDATE public.ai_proxy_conversations SET request_count = request_count + 1
  WHERE id = p_conversation_id AND user_id = p_user_id AND request_count < 30;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_ai_proxy_usage(uuid, bigint, bigint),
  public.claim_ai_proxy_conversation(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_ai_proxy_usage(uuid, bigint, bigint),
  public.claim_ai_proxy_conversation(uuid, text) TO service_role;

-- Explicit grants also work on projects without automatic Data API exposure.
REVOKE ALL ON public.ai_model_config FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ai_model_config TO service_role;
