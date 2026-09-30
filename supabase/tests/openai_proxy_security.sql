-- Run inside a transaction after the two proxy migrations; roll back the fixtures.
DO $$
DECLARE
  user_a uuid;
  user_b uuid;
  reservation uuid;
  i integer;
BEGIN
  SELECT id INTO STRICT user_a FROM auth.users ORDER BY id LIMIT 1;
  SELECT id INTO STRICT user_b FROM auth.users WHERE id <> user_a ORDER BY id LIMIT 1;
  IF has_function_privilege('anon', 'public.reserve_ai_proxy_usage(uuid,bigint,bigint)', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.claim_ai_proxy_conversation(uuid,text)', 'EXECUTE')
    OR has_table_privilege('authenticated', 'public.ai_proxy_conversations', 'INSERT')
    OR has_table_privilege('anon', 'public.ai_proxy_usage', 'SELECT') THEN
    RAISE EXCEPTION 'Client privileges expose proxy control';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.reserve_ai_proxy_usage(uuid,bigint,bigint)', 'EXECUTE')
    OR NOT has_table_privilege('service_role', 'public.ai_model_config', 'SELECT') THEN
    RAISE EXCEPTION 'Service role cannot operate proxy';
  END IF;

  FOR i IN 1..3 LOOP
    reservation := public.reserve_ai_proxy_usage(user_a, 100, 0);
    IF reservation IS NULL THEN RAISE EXCEPTION 'Allowed concurrent call rejected'; END IF;
  END LOOP;
  IF public.reserve_ai_proxy_usage(user_a, 100, 0) IS NOT NULL THEN
    RAISE EXCEPTION 'Concurrency cap bypassed';
  END IF;
  IF (SELECT day_requests FROM public.ai_proxy_usage WHERE user_id = user_a) <> 3 THEN
    RAISE EXCEPTION 'Rejected request consumed quota';
  END IF;
  DELETE FROM public.ai_proxy_reservations;
  UPDATE public.ai_proxy_usage SET minute_requests = 20 WHERE user_id = user_a;
  IF public.reserve_ai_proxy_usage(user_a, 100, 0) IS NOT NULL THEN RAISE EXCEPTION 'Minute cap bypassed'; END IF;
  UPDATE public.ai_proxy_usage SET minute_requests = 0, day_requests = 200 WHERE user_id = user_a;
  IF public.reserve_ai_proxy_usage(user_a, 100, 0) IS NOT NULL THEN RAISE EXCEPTION 'Daily cap bypassed'; END IF;
  UPDATE public.ai_proxy_usage SET day_requests = 0, text_bytes = 16777216 WHERE user_id = user_a;
  IF public.reserve_ai_proxy_usage(user_a, 1, 0) IS NOT NULL THEN RAISE EXCEPTION 'Text budget bypassed'; END IF;
  UPDATE public.ai_proxy_usage SET text_bytes = 0, audio_bytes = 67108864 WHERE user_id = user_a;
  IF public.reserve_ai_proxy_usage(user_a, 0, 1) IS NOT NULL THEN RAISE EXCEPTION 'Audio budget bypassed'; END IF;
  UPDATE public.ai_proxy_usage SET minute_start = now() - interval '2 days', day_start = now() - interval '2 days' WHERE user_id = user_a;
  reservation := public.reserve_ai_proxy_usage(user_a, 10, 0);
  IF reservation IS NULL OR (SELECT day_requests FROM public.ai_proxy_usage WHERE user_id = user_a) <> 1 THEN
    RAISE EXCEPTION 'Quota windows did not reset';
  END IF;
  DELETE FROM public.ai_proxy_reservations;
  UPDATE public.ai_proxy_usage SET day_requests = 5000 WHERE scope = 'global';
  IF public.reserve_ai_proxy_usage(user_b, 1, 0) IS NOT NULL THEN RAISE EXCEPTION 'Global cap bypassed'; END IF;

  INSERT INTO public.ai_proxy_conversations(id, user_id) VALUES ('conv_review_fixture', user_a);
  IF public.claim_ai_proxy_conversation(user_b, 'conv_review_fixture') THEN RAISE EXCEPTION 'Cross-user conversation accepted'; END IF;
  IF public.claim_ai_proxy_conversation(user_a, 'conv_unknown') THEN RAISE EXCEPTION 'Unregistered conversation accepted'; END IF;
  FOR i IN 1..30 LOOP
    IF NOT public.claim_ai_proxy_conversation(user_a, 'conv_review_fixture') THEN RAISE EXCEPTION 'Owner turn rejected'; END IF;
  END LOOP;
  IF public.claim_ai_proxy_conversation(user_a, 'conv_review_fixture') THEN RAISE EXCEPTION 'Unbounded conversation history'; END IF;
END;
$$;
