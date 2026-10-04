-- MAT-1670: stop anon/authenticated from forging Minutes or subscriptions.
-- Permissions only; no function bodies or signatures change.

-- 1. Service-role-only functions (Stripe webhook, triggers, legacy writers).
--    Triggers fire as the table owner and do not need caller EXECUTE.
DO $$
DECLARE
  fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.credit_minutes_admin(uuid,integer,text,text,jsonb)',
    'public.update_subscription_status(uuid,text,text,text,boolean,timestamp with time zone,timestamp with time zone,text)',
    'public.check_and_update_expired_subscriptions()',
    'public.get_or_create_monthly_usage(uuid)',
    'public.increment_meeting_count(uuid,integer)',
    'public.increment_note_count(uuid,integer)',
    'public.cleanup_audio_on_job_completion()',
    'public.debit_minutes_on_job_completion()',
    'public.handle_new_user_signup()',
    'public.handle_subscription_change()',
    'public.initialize_user_usage()',
    'public.trigger_transcription_worker()',
    'public.update_user_minutes_email()',
    'public.update_updated_at_column()',
    'public.update_updated_at()'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;

-- 2. Signed-in-only functions: these rely on auth.uid(), so anon has no use for them.
DO $$
DECLARE
  fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.get_user_minutes_balance(uuid)',
    'public.grant_free_tier_minutes()',
    'public.credit_minutes(integer,text,text,jsonb)',
    'public.debit_minutes(integer,uuid)',
    'public.get_my_usage()',
    'public.increment_meeting_usage(boolean,integer)',
    'public.increment_note_usage(boolean,integer)',
    'public.increment_ai_usage(integer,integer,integer)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', fn);
  END LOOP;
END $$;

-- 3. Minutes and subscription tables: clients may read their own rows only.
--    All writes go through RPCs, Edge Functions, or the service role.
REVOKE ALL ON public.user_minutes, public.minutes_transactions, public.subscriptions FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.user_minutes, public.minutes_transactions, public.subscriptions FROM authenticated;

DROP POLICY IF EXISTS "Users can insert own minutes" ON public.user_minutes;
DROP POLICY IF EXISTS "Users can update own minutes" ON public.user_minutes;
DROP POLICY IF EXISTS "Users can insert own transactions" ON public.minutes_transactions;
