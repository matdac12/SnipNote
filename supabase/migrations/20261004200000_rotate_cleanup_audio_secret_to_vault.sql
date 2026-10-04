-- MAT-1670 follow-up: the cleanup-audio-storage shared secret was a literal in the repo
-- (trigger body and Edge Function fallback). Move it to Vault with a random value.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'cleanup_internal_secret') THEN
    PERFORM vault.create_secret(
      replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
      'cleanup_internal_secret',
      'Shared secret between cleanup_audio_on_job_completion() and the cleanup-audio-storage Edge Function'
    );
  END IF;
END $$;

-- The Edge Function reads the secret through this (service role only).
CREATE OR REPLACE FUNCTION public.get_cleanup_internal_secret()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cleanup_internal_secret' LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.get_cleanup_internal_secret() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cleanup_internal_secret() TO service_role;

-- Same behaviour as before, but the secret comes from Vault. If it is missing we skip cleanup
-- with a warning rather than fail the job update.
CREATE OR REPLACE FUNCTION public.cleanup_audio_on_job_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  request_id bigint;
  supabase_url text := 'https://bndbnqtvicvynzkyygte.supabase.co';
  internal_secret text;
BEGIN
  -- Only act when status changes to 'completed'
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN

    internal_secret := public.get_cleanup_internal_secret();
    IF internal_secret IS NULL THEN
      RAISE WARNING 'cleanup_internal_secret missing in Vault; skipping audio cleanup for meeting %', NEW.meeting_id;
      RETURN NEW;
    END IF;

    -- Call the Edge Function via pg_net
    SELECT net.http_post(
      url := supabase_url || '/functions/v1/cleanup-audio-storage',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-internal-secret', internal_secret
      ),
      body := jsonb_build_object(
        'meeting_id', NEW.meeting_id::text,
        'user_id', NEW.user_id::text
      )
    ) INTO request_id;

    RAISE LOG 'Triggered cleanup for meeting % (request_id: %)', NEW.meeting_id, request_id;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.cleanup_audio_on_job_completion() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_audio_on_job_completion() TO service_role;
