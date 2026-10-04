-- Analytics queries for public.analytics_events (MAT-1660).
--
-- Run in the Supabase SQL editor (service role / postgres). Clients cannot read the
-- table. Every query starts from the same `ev` CTE; to try a query on the sample
-- data at the bottom, replace the `ev` definition with the `ev` from the SAMPLE DATA
-- section (nothing is written, it is a VALUES list).
--
-- Notes that apply to all queries:
--   * An "install" is a random per-install UUID. Reinstalling, or turning analytics
--     off and on again, creates a new install, so counts are slight overestimates.
--   * Weeks start on Monday, days are UTC calendar days.
--   * Cohorts only include installs old enough to have a complete window, so the
--     newest week does not read as a false drop.
--   * `app_opened` is sent at launch and on foreground (at most once per 30 minutes),
--     so "active on day N" means "opened the app on day N".

-- ---------------------------------------------------------------------------
-- 1. New installs per week (week of the first event seen for an install)
-- ---------------------------------------------------------------------------
WITH ev AS (SELECT install_id, event, properties, occurred_at FROM public.analytics_events),
first_seen AS (
    SELECT install_id, min(occurred_at) AS first_at
    FROM ev
    GROUP BY install_id
)
SELECT date_trunc('week', first_at AT TIME ZONE 'UTC')::date AS week,
       count(*) AS new_installs
FROM first_seen
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------------
-- 2. Activation: first Local recording within 24h of the install's first app_opened
--    Cohort = week of the first app_opened.
-- ---------------------------------------------------------------------------
WITH ev AS (SELECT install_id, event, properties, occurred_at FROM public.analytics_events),
first_open AS (
    SELECT install_id, min(occurred_at) AS t0
    FROM ev
    WHERE event = 'app_opened'
    GROUP BY install_id
),
cohort AS (
    SELECT f.install_id,
           f.t0,
           EXISTS (
               SELECT 1
               FROM ev r
               WHERE r.install_id = f.install_id
                 AND r.event = 'local_recording_started'
                 AND r.occurred_at >= f.t0
                 AND r.occurred_at <  f.t0 + interval '24 hours'
           ) AS activated
    FROM first_open f
    WHERE f.t0 <= now() - interval '24 hours'
)
SELECT date_trunc('week', t0 AT TIME ZONE 'UTC')::date AS week,
       count(*) AS installs,
       count(*) FILTER (WHERE activated) AS activated,
       round(100.0 * count(*) FILTER (WHERE activated) / count(*), 1) AS activation_pct
FROM cohort
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------------
-- 3. Day-7 retention: opened the app on the 7th UTC calendar day after the install's
--    first app_opened day. Cohort = week of the first app_opened; only installs whose
--    day 7 is already over.
-- ---------------------------------------------------------------------------
WITH ev AS (SELECT install_id, event, properties, occurred_at FROM public.analytics_events),
first_open AS (
    SELECT install_id, (min(occurred_at) AT TIME ZONE 'UTC')::date AS d0
    FROM ev
    WHERE event = 'app_opened'
    GROUP BY install_id
),
cohort AS (
    SELECT f.install_id,
           f.d0,
           EXISTS (
               SELECT 1
               FROM ev o
               WHERE o.install_id = f.install_id
                 AND o.event = 'app_opened'
                 AND (o.occurred_at AT TIME ZONE 'UTC')::date = f.d0 + 7
           ) AS retained
    FROM first_open f
    WHERE f.d0 + 7 < (now() AT TIME ZONE 'UTC')::date
)
SELECT date_trunc('week', d0::timestamp)::date AS week,
       count(*) AS installs,
       count(*) FILTER (WHERE retained) AS retained_d7,
       round(100.0 * count(*) FILTER (WHERE retained) / count(*), 1) AS d7_retention_pct
FROM cohort
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------------
-- 4a. analysis_unavailable rate per week: unavailable events per completed Local
--     transcript. Assumes analysis_unavailable is sent once per affected meeting.
-- ---------------------------------------------------------------------------
WITH ev AS (SELECT install_id, event, properties, occurred_at FROM public.analytics_events)
SELECT date_trunc('week', occurred_at AT TIME ZONE 'UTC')::date AS week,
       count(*) FILTER (WHERE event = 'local_transcript_completed') AS local_transcripts,
       count(*) FILTER (WHERE event = 'analysis_unavailable') AS analysis_unavailable,
       round(
           100.0 * count(*) FILTER (WHERE event = 'analysis_unavailable')
           / nullif(count(*) FILTER (WHERE event = 'local_transcript_completed'), 0),
           1
       ) AS unavailable_pct
FROM ev
WHERE event IN ('local_transcript_completed', 'analysis_unavailable')
GROUP BY 1
ORDER BY 1;

-- 4b. Same, split by reason (device / setting / language), all time.
WITH ev AS (SELECT install_id, event, properties, occurred_at FROM public.analytics_events)
SELECT properties ->> 'reason' AS reason,
       count(*) AS events,
       count(DISTINCT install_id) AS installs
FROM ev
WHERE event = 'analysis_unavailable'
GROUP BY 1
ORDER BY events DESC;

-- ---------------------------------------------------------------------------
-- 5. Funnel: cloud_trial_prompt_shown -> cloud_trial_claimed -> paywall_viewed
--    -> purchase_completed. Installs are counted at a step only if they did the
--    previous step first (each step's time must be >= the previous step's first time).
--    To limit the window, add e.g. WHERE occurred_at >= now() - interval '30 days'
--    to the `ev` CTE.
-- ---------------------------------------------------------------------------
WITH ev AS (SELECT install_id, event, properties, occurred_at FROM public.analytics_events),
s1 AS (
    SELECT install_id, min(occurred_at) AS t
    FROM ev
    WHERE event = 'cloud_trial_prompt_shown'
    GROUP BY install_id
),
s2 AS (
    SELECT s1.install_id, min(e.occurred_at) AS t
    FROM s1
    JOIN ev e ON e.install_id = s1.install_id
             AND e.event = 'cloud_trial_claimed'
             AND e.occurred_at >= s1.t
    GROUP BY s1.install_id
),
s3 AS (
    SELECT s2.install_id, min(e.occurred_at) AS t
    FROM s2
    JOIN ev e ON e.install_id = s2.install_id
             AND e.event = 'paywall_viewed'
             AND e.occurred_at >= s2.t
    GROUP BY s2.install_id
),
s4 AS (
    SELECT s3.install_id, min(e.occurred_at) AS t
    FROM s3
    JOIN ev e ON e.install_id = s3.install_id
             AND e.event = 'purchase_completed'
             AND e.occurred_at >= s3.t
    GROUP BY s3.install_id
),
counts AS (
    SELECT 1 AS step, 'cloud_trial_prompt_shown' AS event, count(*) AS installs FROM s1
    UNION ALL SELECT 2, 'cloud_trial_claimed', count(*) FROM s2
    UNION ALL SELECT 3, 'paywall_viewed', count(*) FROM s3
    UNION ALL SELECT 4, 'purchase_completed', count(*) FROM s4
)
SELECT step,
       event,
       installs,
       round(100.0 * installs / nullif(first_value(installs) OVER (ORDER BY step), 0), 1) AS pct_of_step_1,
       round(100.0 * installs / nullif(lag(installs) OVER (ORDER BY step), 0), 1) AS pct_of_previous_step
FROM counts
ORDER BY step;

-- ===========================================================================
-- SAMPLE DATA, for checking the queries by hand.
-- Replace the `ev` CTE at the top of a query with this one. Nothing is written.
--
-- Installs (UUID suffix = letter; g and h are not hex so they are ...0010 and ...0011):
--   a  opens Mon 08-03, records 2h later (activated), opens day 7 (08-10), transcript + analysis unavailable (device)
--   b  opens Tue 08-04, records 08-06 (>24h, not activated), opens 08-12 (day 8, not day 7), transcript, no unavailable
--   c  opens Wed 08-05 22:00, never records, opens 08-12 (day 7), not activated
--   d  opens Tue 08-11, records 1h later (activated), transcript, never returns
--   e  opens Wed 08-12, full funnel: prompt -> claimed -> paywall -> purchase
--   f  opens 08-12, prompt shown, then paywall without claiming (stops at step 1)
--   g  opens 08-12, paywall + purchase only (no prompt, not in funnel), opens 08-19 (day 7)
--   h  opens 08-13, prompt -> claimed, never sees paywall (stops at step 2)
--
-- Expected results:
--   1. installs/week:  2026-08-03 -> 3 (a,b,c);  2026-08-10 -> 5 (d,e,f,g,h)
--   2. activation:     2026-08-03 -> 3 installs, 1 activated, 33.3%
--                      2026-08-10 -> 5 installs, 1 activated, 20.0%
--   3. day-7:          2026-08-03 -> 3 installs, 2 retained (a,c), 66.7%
--                      2026-08-10 -> 5 installs, 1 retained (g), 20.0%
--   4a. unavailable:   2026-08-03 -> 2 transcripts (a,b), 1 unavailable, 50.0%
--                      2026-08-10 -> 1 transcript (d), 0 unavailable, 0.0%
--   4b. by reason:     device -> 1 event, 1 install
--   5. funnel:         prompt_shown 3 (e,f,h) 100.0 / -
--                      claimed      2 (e,h)   66.7 / 66.7
--                      paywall      1 (e)     33.3 / 50.0   (f has no claim; g has no prompt)
--                      purchase     1 (e)     33.3 / 100.0
-- ===========================================================================
-- WITH ev AS (
--     SELECT install_id::uuid, event, properties::jsonb, occurred_at::timestamptz
--     FROM (VALUES
--         ('00000000-0000-0000-0000-00000000000a', 'app_opened',                '{}',                         '2026-08-03T10:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000a', 'local_recording_started',   '{}',                         '2026-08-03T12:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000a', 'local_transcript_completed','{"length_bucket":"5_15m"}',  '2026-08-03T12:10:00Z'),
--         ('00000000-0000-0000-0000-00000000000a', 'analysis_unavailable',      '{"reason":"device"}',        '2026-08-03T12:11:00Z'),
--         ('00000000-0000-0000-0000-00000000000a', 'app_opened',                '{}',                         '2026-08-10T09:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000b', 'app_opened',                '{}',                         '2026-08-04T10:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000b', 'local_recording_started',   '{}',                         '2026-08-06T10:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000b', 'local_transcript_completed','{"length_bucket":"1_5m"}',   '2026-08-06T10:05:00Z'),
--         ('00000000-0000-0000-0000-00000000000b', 'app_opened',                '{}',                         '2026-08-12T10:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000c', 'app_opened',                '{}',                         '2026-08-05T22:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000c', 'app_opened',                '{}',                         '2026-08-12T08:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000d', 'app_opened',                '{}',                         '2026-08-11T09:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000d', 'local_recording_started',   '{}',                         '2026-08-11T10:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000d', 'local_transcript_completed','{"length_bucket":"under_1m"}','2026-08-11T10:03:00Z'),
--         ('00000000-0000-0000-0000-00000000000e', 'app_opened',                '{}',                         '2026-08-12T09:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000e', 'cloud_trial_prompt_shown',  '{}',                         '2026-08-12T10:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000e', 'cloud_trial_claimed',       '{}',                         '2026-08-12T10:05:00Z'),
--         ('00000000-0000-0000-0000-00000000000e', 'paywall_viewed',            '{"paywall":"subscription","source":"home"}', '2026-08-13T10:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000e', 'purchase_completed',        '{"kind":"minutes_pack","product_id":"com.snipnote.packs.minutes100"}', '2026-08-13T10:02:00Z'),
--         ('00000000-0000-0000-0000-00000000000f', 'app_opened',                '{}',                         '2026-08-12T09:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000f', 'cloud_trial_prompt_shown',  '{}',                         '2026-08-12T10:00:00Z'),
--         ('00000000-0000-0000-0000-00000000000f', 'paywall_viewed',            '{"paywall":"subscription","source":"settings"}', '2026-08-12T10:10:00Z'),
--         ('00000000-0000-0000-0000-000000000010', 'app_opened',                '{}',                         '2026-08-12T09:30:00Z'),
--         ('00000000-0000-0000-0000-000000000010', 'paywall_viewed',            '{"paywall":"minutes_pack","source":"create_meeting"}', '2026-08-12T10:00:00Z'),
--         ('00000000-0000-0000-0000-000000000010', 'purchase_completed',        '{"kind":"minutes_pack","product_id":"com.snipnote.packs.minutes500"}', '2026-08-12T10:05:00Z'),
--         ('00000000-0000-0000-0000-000000000010', 'app_opened',                '{}',                         '2026-08-19T09:00:00Z'),
--         ('00000000-0000-0000-0000-000000000011', 'app_opened',                '{}',                         '2026-08-13T09:00:00Z'),
--         ('00000000-0000-0000-0000-000000000011', 'cloud_trial_prompt_shown',  '{}',                         '2026-08-13T10:00:00Z'),
--         ('00000000-0000-0000-0000-000000000011', 'cloud_trial_claimed',       '{}',                         '2026-08-13T10:05:00Z')
--     ) AS t(install_id, event, properties, occurred_at)
-- )
