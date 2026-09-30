# OpenAI proxy setup

The app sends its Supabase user access token to `openai-proxy`. Only the Edge
Function reads `OPENAI_API_KEY`. The public Supabase anon key stays in the app;
it is not an OpenAI key or a service-role key.

## Secrets and deployment

Save `OPENAI_API_KEY` under Supabase Dashboard → Edge Functions → Secrets.
Use the OpenAI project containing Eve's stored prompt. Never put the key in chat,
`Config.swift`, or the repository. `OPENAI_EVE_PROMPT_ID` optionally overrides
the public prompt ID pinned in `index.ts`.

Deployment order:

1. Save the secret.
2. Apply `supabase/migrations/20260926_create_ai_model_config.sql`, then
   `supabase/migrations/20260930094838_secure_openai_proxy.sql`.
3. Deploy `openai-proxy` with JWT verification enabled.
4. Align and deploy the VPS worker separately.
5. Build, smoke-test while signed in, and release the app.

Both migrations and the function were deployed to `bndbnqtvicvynzkyygte` on
September 30, 2026. Check migration history before applying again. Avoid a
blanket `db push`: older local migrations may not match the remote history.

```bash
supabase functions deploy openai-proxy --project-ref bndbnqtvicvynzkyygte --use-api
```

For a fresh checkout, copy `Documentation/Config.swift.example` to
`SnipNote/Config.swift` and set only the public Eve prompt ID. No API key is needed.
The app deletes the OpenAI Keychain item left by older installations.

The VPS at `api.snipnote.app` reads its own `OPENAI_API_KEY` from
`/etc/snipnote-transcription/env`. Supabase secrets do not update the VPS.

## Models

Edit `public.ai_model_config` in the Table Editor. It seeds `overview`, `summary`,
`actions`, `title`, `text_summary`, `eve_chat`, `actions_report`, and `transcription`.
Text defaults to `gpt-6-luna` / low reasoning; transcription defaults to
`gpt-transcribe`, with `gpt-4o-transcribe` as fallback. Changes apply within 60 seconds.

Only POST `/responses`, `/conversations`, and `/audio/transcriptions` are allowed.
The table configures models and parameters, not arbitrary upstream URLs. Missing
task headers use `text_summary` or `transcription`; unknown or mismatched tasks
are rejected. Missing rows use built-in defaults; an unavailable config table
fails closed. Fallbacks reuse reasoning/verbosity, so choose compatible models.

## Safety controls

`ai_proxy_limits` is service-only. Dashboard edits apply on the next call:

| Budget | Per user | Entire project |
| --- | ---: | ---: |
| Requests per minute | 20 | 200 |
| Requests per UTC day | 200 | 5,000 |
| Text bytes per day | 16 MiB | 512 MiB |
| Audio bytes per day | 64 MiB | 2 GiB |
| Concurrent calls | 3 | 64 |

Text requests are limited to 512 KiB, audio files to 12 MiB, and output to 4,096
tokens. Quota reservations are atomic across instances; denied calls never reach
OpenAI. Accepted attempts, including failures, count. Calls time out after 120
seconds and abandoned leases expire after 150 seconds. Daily budgets reset at
UTC midnight. These budgets are separate from purchased minutes; audio limits
measure bytes rather than duration. Slow/malformed uploads can consume Edge
resources before quota admission.

Eve conversation IDs must be registered to the caller. File/vector-store IDs,
previous response IDs, item references, tools, and arbitrary templates are rejected.
Each conversation allows 30 admitted turns. Legacy, unknown, or exhausted IDs
are replaced once by the app. Local messages remain, but the prior remote chat
context is not carried into the replacement; current meeting context is sent again.

The control tables have RLS, no client policies, and revoked client privileges.
“RLS enabled, no policy” advisor notices are deliberate. The invoker quota and
ownership RPCs are executable only by service role.

## Verification and rotation

```bash
deno test supabase/functions/openai-proxy/handler_test.ts supabase/functions/openai-proxy/transcription_test.ts
deno check --config supabase/functions/openai-proxy/deno.json supabase/functions/openai-proxy/index.ts
```

Run `supabase/tests/openai_proxy_security.sql` in a transaction on an isolated
test database after the migrations, then roll back. It requires two test users.
Do not run its fixture changes outside a transaction.

Unauthenticated function requests must return 401. In the signed-in app, test a
short cloud recording, summary/title/actions, Eve, and an actions report. Inspect
Edge Function logs for endpoint/task/status. A 503 can indicate a missing secret,
unavailable control tables, or upstream failure. Logs omit transcript bodies and keys.

The live minutes debit test is opt-in (`SNIPNOTE_RUN_LIVE_TESTS=1`); it needs a
dedicated signed-in test account and debits real backend minutes.

Treat the key embedded in older releases as exposed. After the proxy app is live
and the VPS has a valid replacement key, revoke the old key in OpenAI. Older builds
will lose AI features. Removing a local literal does not revoke a key or remove it
from already-shipped binaries.

## Saved cloud transcription provider rollout

Settings saves `openai` or `xai` locally under `cloudTranscription.provider`.
Only new cloud transcriptions use the choice. On-device Whisper, purchased
minutes, and text generation (including Eve) keep their existing behavior.
Short recordings still POST `/audio/transcriptions`, with
`X-SnipNote-Task: transcription` and `X-SnipNote-Transcription-Provider: openai|xai`.
The proxy's private xAI destination is fixed at `https://api.x.ai/v1/stt`.
Missing provider headers default to OpenAI; unknown values and provider headers
on text endpoints return 400. Authentication, quotas and upload limits apply to
both providers.

OpenAI uses `ai_model_config.task = transcription`; xAI uses `transcription_xai`,
seeded with `grok-voice-transcribe-2.0` and NULL effort, verbosity and fallback.
Model edits are cached for 60 seconds. Keep credentials out of this table.
Fallback models are always within the selected provider, only for 400/404;
xAI failures never switch to OpenAI. Missing xAI credentials return an actionable
503. Empty or malformed xAI transcript responses return sanitized 502 errors.
Explicit language enables xAI formatting; auto language omits language/format.

Deployment is a separate, authorized operation. Perform these steps in order:

1. Check remote migration history and schema, then apply **only**
   `supabase/migrations/20260930105323_add_transcription_provider.sql` through
   the reviewed migration workflow. It adds the job column/default/check and
   inserts the xAI row without replacing administrator changes. Do not blindly
   apply historical migrations or run blanket `supabase db push`.
2. Configure `XAI_API_KEY` in Supabase Edge Function secrets and independently
   in `/etc/snipnote-transcription/env` on the VPS (root-owned, mode 600).
   Keep `OPENAI_API_KEY` for OpenAI transcription and unchanged text generation.
   Supabase secrets do not populate the VPS environment. Never print keys.
3. Deploy the reviewed `openai-proxy` with JWT verification enabled and the
   service API **and worker** changes; restart both VPS units in the deployment
   window. The service release must include local main's configuration commits
   through `5176d6b`, plus the provider feature commits. Nothing was pushed by
   the implementation task.
4. Run the authorized staging smoke matrix below, then release the iOS app last.
   Legacy clients and jobs remain OpenAI throughout rollout.

For rollback, stop new xAI submissions and coordinate app/backend rollback.
Retain the additive column and config row. Drain or explicitly fail queued xAI
jobs before rolling back to workers that do not understand providers; never let
an old worker process a queued xAI job as OpenAI. Keep the xAI credential until
those jobs are handled. Users can select OpenAI for new operations.

### Manual staging matrix (prepared, not executed)

Use a dedicated account and separately authorized paid API calls.

| Provider | Route | Language cases | Expected |
| --- | --- | --- | --- |
| OpenAI | Short proxy recording | English, Italian, auto | Usable transcript; existing progress/minutes behavior |
| xAI | Short proxy recording | English, Italian, auto | Usable transcript; existing progress/minutes behavior |
| OpenAI | Long regular and chunked VPS jobs | English, Italian, auto | Stored provider retained through all chunks/retries |
| xAI | Long regular and chunked VPS jobs | English, Italian, auto | Stored provider retained through all chunks/retries |

For each route, change Settings during delayed upload and after a transient
failure. The active operation must keep its initial provider; the next new
operation (including manual retranscription) must use the new preference.
Check summaries/actions/title/Eve, completion notifications, minutes debit and
transcript quality with existing audio preprocessing. In staging, test missing
xAI credentials, 401/403, 429 and 5xx; errors must preserve status information,
release quota reservations, omit secrets/content and never contact OpenAI as an
xAI fallback. Do not remove a production key to simulate these failures.
