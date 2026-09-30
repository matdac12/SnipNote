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
deno test supabase/functions/openai-proxy/handler_test.ts
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
