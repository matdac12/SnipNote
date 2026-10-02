-- Completion timestamps survive stale client status writes. Restoring an already
-- completed job must not create another debit or subtract minutes again.
CREATE OR REPLACE FUNCTION public.debit_minutes_on_job_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  minutes_to_debit INTEGER;
BEGIN
  IF NEW.status = 'completed'
     AND (OLD.status IS NULL OR OLD.status != 'completed')
     AND OLD.completed_at IS NULL THEN
    minutes_to_debit := GREATEST(1, CEIL(COALESCE(NEW.duration, 0) / 60.0));

    INSERT INTO minutes_transactions (user_id, amount, reason, meeting_id)
    VALUES (NEW.user_id, -minutes_to_debit, 'server_transcription', NEW.meeting_id);

    INSERT INTO user_minutes (user_id, balance_minutes, updated_at)
    VALUES (NEW.user_id, -minutes_to_debit, NOW())
    ON CONFLICT (user_id)
    DO UPDATE SET
      balance_minutes = user_minutes.balance_minutes - minutes_to_debit,
      updated_at = NOW();

    RAISE NOTICE 'Debited % minutes for job % (user: %, meeting: %)',
      minutes_to_debit, NEW.id, NEW.user_id, NEW.meeting_id;
  END IF;
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Failed to debit minutes for job %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$function$;
