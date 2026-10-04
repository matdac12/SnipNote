-- Anonymous product analytics (MAT-1660).
--
-- Guests (Local mode, no Account, no Supabase session) must be countable without
-- SnipNote knowing who they are, so events go to our own table instead of a
-- third-party vendor. Nothing here references auth.users: the only identifier is a
-- random per-install UUID generated on the device. It is never an account ID or
-- derived from one, and the app drops it when the user turns analytics off.
--
-- Write path: the `track_analytics_event` RPC, callable with the anon key and no
-- session. Read path: none for clients. RLS is on with no policies and table
-- privileges are revoked, so only the service role / SQL editor can read events
-- (see docs/analytics-queries.sql).
--
-- Why an RPC and not an Edge Function: the function needs no secrets and no
-- third-party call, and an Edge Function would accept the same public anon key
-- anyway. Safety comes from validation inside the function (event allowlist,
-- strict property shape, size bounds) plus per-install and global rate limits, all
-- enforced in one place next to the data, without a cold start per event.

CREATE TABLE IF NOT EXISTS public.analytics_events (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    install_id  uuid        NOT NULL,
    event       text        NOT NULL,
    app_version text,
    platform    text,
    properties  jsonb       NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    -- Belt and braces: the RPC validates these too, this protects against any
    -- other writer (service role scripts, future functions).
    CONSTRAINT analytics_events_event_len CHECK (char_length(event) BETWEEN 1 AND 64),
    CONSTRAINT analytics_events_version_len CHECK (app_version IS NULL OR char_length(app_version) <= 16),
    CONSTRAINT analytics_events_platform_len CHECK (platform IS NULL OR char_length(platform) <= 16),
    CONSTRAINT analytics_events_properties_object CHECK (jsonb_typeof(properties) = 'object'),
    CONSTRAINT analytics_events_properties_size CHECK (octet_length(properties::text) <= 512)
);

-- Rate limiting looks up one install's recent rows; funnels and retention scan by
-- event and time.
CREATE INDEX IF NOT EXISTS analytics_events_install_time_idx
    ON public.analytics_events (install_id, occurred_at);
CREATE INDEX IF NOT EXISTS analytics_events_event_time_idx
    ON public.analytics_events (event, occurred_at);
CREATE INDEX IF NOT EXISTS analytics_events_time_idx
    ON public.analytics_events (occurred_at);

-- No policies = no client access (anon or authenticated), for reads and writes.
ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

-- Supabase's default privileges grant new tables to anon/authenticated; take that away.
REVOKE ALL ON public.analytics_events FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.track_analytics_event(
    p_install_id  uuid,
    p_event       text,
    p_app_version text  DEFAULT NULL,
    p_platform    text  DEFAULT NULL,
    p_properties  jsonb DEFAULT '{}'::jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    -- Keep in sync with AnalyticsEvent in the iOS app. Adding an event means a new
    -- migration that re-creates this function.
    v_allowed_events constant text[] := ARRAY[
        'app_opened',
        'local_recording_started',
        'local_transcript_completed',
        'analysis_unavailable',
        'cloud_trial_prompt_shown',
        'cloud_trial_claimed',
        'paywall_viewed',
        'purchase_completed'
    ];
    -- Per-install ceilings. A normal install sends a handful of events per session.
    v_max_per_minute constant int := 10;
    v_max_per_hour   constant int := 120;
    -- Global ceiling, so a client rotating install IDs cannot flood the table.
    v_max_global_per_minute constant int := 600;

    v_props jsonb := COALESCE(p_properties, '{}'::jsonb);
    v_key   text;
    v_value jsonb;
BEGIN
    IF p_install_id IS NULL THEN
        RAISE EXCEPTION 'install id required' USING ERRCODE = '22023';
    END IF;

    IF p_event IS NULL OR NOT (p_event = ANY (v_allowed_events)) THEN
        RAISE EXCEPTION 'unknown event' USING ERRCODE = '22023';
    END IF;

    IF p_app_version IS NOT NULL
       AND (char_length(p_app_version) > 16 OR p_app_version !~ '^[0-9]+(\.[0-9]+){0,3}$') THEN
        RAISE EXCEPTION 'invalid app version' USING ERRCODE = '22023';
    END IF;

    IF p_platform IS NOT NULL AND p_platform !~ '^(ios|ipados)[0-9]{1,2}$' THEN
        RAISE EXCEPTION 'invalid platform' USING ERRCODE = '22023';
    END IF;

    -- Properties: a small flat object of short enum-like values. The value pattern
    -- has no spaces or "@", so free text (transcripts, names, emails) cannot fit.
    IF jsonb_typeof(v_props) <> 'object' THEN
        RAISE EXCEPTION 'properties must be an object' USING ERRCODE = '22023';
    END IF;
    IF octet_length(v_props::text) > 512 THEN
        RAISE EXCEPTION 'properties too large' USING ERRCODE = '22023';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(v_props)) > 8 THEN
        RAISE EXCEPTION 'too many properties' USING ERRCODE = '22023';
    END IF;
    FOR v_key, v_value IN SELECT key, value FROM jsonb_each(v_props) LOOP
        IF v_key !~ '^[a-z][a-z_]{0,31}$' THEN
            RAISE EXCEPTION 'invalid property key' USING ERRCODE = '22023';
        END IF;
        IF jsonb_typeof(v_value) NOT IN ('string', 'number', 'boolean') THEN
            RAISE EXCEPTION 'invalid property value' USING ERRCODE = '22023';
        END IF;
        IF jsonb_typeof(v_value) = 'string' AND (v_value #>> '{}') !~ '^[A-Za-z0-9_.:-]{1,40}$' THEN
            RAISE EXCEPTION 'invalid property value' USING ERRCODE = '22023';
        END IF;
    END LOOP;

    -- Rate limits. Over the limit is not an error: drop silently, the client never retries.
    IF (SELECT count(*) FROM public.analytics_events
         WHERE install_id = p_install_id AND occurred_at > now() - interval '1 minute') >= v_max_per_minute
       OR (SELECT count(*) FROM public.analytics_events
            WHERE install_id = p_install_id AND occurred_at > now() - interval '1 hour') >= v_max_per_hour
       OR (SELECT count(*) FROM public.analytics_events
            WHERE occurred_at > now() - interval '1 minute') >= v_max_global_per_minute THEN
        RETURN false;
    END IF;

    INSERT INTO public.analytics_events (install_id, event, app_version, platform, properties)
    VALUES (p_install_id, p_event, p_app_version, p_platform, v_props);

    RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.track_analytics_event(uuid, text, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.track_analytics_event(uuid, text, text, text, jsonb) TO anon, authenticated;

-- Retention helper, scheduled nightly below. Can also be run by hand from the SQL editor,
-- e.g. SELECT public.purge_analytics_events('400 days');
CREATE OR REPLACE FUNCTION public.purge_analytics_events(p_older_than interval DEFAULT '400 days')
RETURNS bigint
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
    WITH deleted AS (
        DELETE FROM public.analytics_events
        WHERE occurred_at < now() - p_older_than
        RETURNING 1
    )
    SELECT count(*) FROM deleted;
$$;

REVOKE ALL ON FUNCTION public.purge_analytics_events(interval) FROM PUBLIC, anon, authenticated;

-- Nightly purge, so the table cannot grow without bound even if someone spams the public
-- RPC up to its global rate limit. cron.schedule with an existing job name replaces it.
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
    'purge-analytics-events',
    '17 3 * * *',
    $$SELECT public.purge_analytics_events('400 days')$$
);
