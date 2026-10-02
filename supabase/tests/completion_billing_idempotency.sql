BEGIN;
CREATE TEMP TABLE user_minutes (user_id uuid PRIMARY KEY, balance_minutes integer, updated_at timestamptz);
CREATE TEMP TABLE minutes_transactions (user_id uuid, amount integer, reason text, meeting_id uuid);
CREATE TEMP TABLE completion_jobs (id uuid, user_id uuid, meeting_id uuid, status text, duration double precision, completed_at timestamptz);
DO $$
DECLARE definition text;
BEGIN
 SELECT pg_get_functiondef('public.debit_minutes_on_job_completion()'::regprocedure) INTO definition;
 definition := replace(definition, 'public.debit_minutes_on_job_completion()', 'pg_temp.debit_minutes_on_job_completion()');
 definition := replace(definition, 'SECURITY DEFINER', 'SECURITY INVOKER');
 EXECUTE definition;
END $$;
CREATE TRIGGER fixture_debit AFTER UPDATE ON completion_jobs FOR EACH ROW EXECUTE FUNCTION pg_temp.debit_minutes_on_job_completion();
INSERT INTO user_minutes VALUES ('11111111-1111-4111-8111-111111111111',100,now());
INSERT INTO completion_jobs VALUES ('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333','processing',120,null);
UPDATE completion_jobs SET status='completed',completed_at=now();
DO $$ BEGIN
 IF (SELECT balance_minutes FROM user_minutes) <> 98 THEN RAISE EXCEPTION 'First completion must debit two minutes'; END IF;
END $$;
UPDATE completion_jobs SET status='processing';
UPDATE completion_jobs SET status='completed';
DO $$ BEGIN
 IF (SELECT balance_minutes FROM user_minutes) <> 98 OR (SELECT count(*) FROM minutes_transactions) <> 1 THEN RAISE EXCEPTION 'Regression: duplicate debit when restoring completed status'; END IF;
END $$;
ROLLBACK;
