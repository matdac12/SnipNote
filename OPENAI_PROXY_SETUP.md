# OpenAI Proxy (Supabase Edge Function)

The iOS app no longer ships an OpenAI API key. Every OpenAI call goes through
`supabase/functions/openai-proxy`, which:

1. Requires a signed-in Supabase user (JWT checked by the gateway and again with `auth.getUser()`).
2. Only allows `POST` to `/audio/transcriptions`, `/responses`, `/conversations`, `/chat/completions`.
3. Adds `Authorization: Bearer $OPENAI_API_KEY` from Supabase secrets and forwards the body unchanged.
4. Returns OpenAI's status code and body as-is, so the app's error handling is unchanged.

```
iOS app ──(Supabase access token)──▶ /functions/v1/openai-proxy/<path> ──(OpenAI key)──▶ api.openai.com/v1/<path>
```

The transcription server (VPS, `api.snipnote.app`) keeps its own key: it reads
`OPENAI_API_KEY` from `/etc/snipnote-transcription/env`.

## Switching models: the `ai_model_config` table

Models are not chosen by the app. Each iOS call sends `X-SnipNote-Task: <task>`,
and the proxy overrides `model`, reasoning effort and verbosity from the matching
row in `public.ai_model_config` (migration `supabase/migrations/20260926_create_ai_model_config.sql`).
The VPS worker reads the same rows for long-meeting summaries (see
`AI_MODEL_CONFIG.md` in the transcription-service repo).

| task | used by | seeded model / effort / verbosity |
|---|---|---|
| `overview` | iOS + VPS | gpt-6-luna / low / low |
| `summary` | iOS + VPS | gpt-6-luna / low / low |
| `actions` | iOS + VPS | gpt-6-luna / low / – |
| `title` | iOS | gpt-6-luna / low / – |
| `text_summary` | iOS (`summarizeText`) | gpt-6-luna / low / – |
| `eve_chat` | iOS | gpt-6-luna / low / medium |
| `actions_report` | iOS (Chat Completions) | gpt-6-luna / low / – |

All rows are seeded with `fallback_model = gpt-6-luna`.

**To switch a model:** open Supabase Dashboard → Table Editor → `ai_model_config`, edit
`model`, `reasoning_effort` or `verbosity`, and save. The change applies within 60 seconds
(cache TTL) for both the app and the VPS. No app release and no redeploy are needed.

Rules the proxy applies:
- NULL `reasoning_effort` / `verbosity` means the value the app sent is kept.
- A non-`none` effort strips `temperature`, `top_p` and `logprobs`, which reasoning models reject.
  On Chat Completions, `max_tokens` is renamed to `max_completion_tokens`.
- If OpenAI answers 400/404, the proxy retries once with `fallback_model`, when it is set and
  differs from `model`. The Edge Function logs show the OpenAI error that triggered it.
- If there's no header or no row, the body is forwarded as sent. The app's built-in defaults
  are also `gpt-6-luna` with effort `low`.
- Transcription (`/audio/transcriptions`) is not affected. It stays `gpt-4o-transcribe` in the app.

Parameter notes (GPT-6 family, checked Sept 2026): `reasoning.effort` accepts
`none|low|medium|high|xhigh|max`, and **`minimal` is rejected**. `text.verbosity`
(`low|medium|high`) is still supported. Check the model page on developers.openai.com
before switching to a new family.

## Deploy

```bash
supabase secrets set OPENAI_API_KEY=sk-...
supabase functions deploy openai-proxy
```

## Smoke test

```bash
# Without a token -> 401
curl -i -X POST https://bndbnqtvicvynzkyygte.supabase.co/functions/v1/openai-proxy/responses

# With a signed-in user's access token -> OpenAI response
curl -X POST https://bndbnqtvicvynzkyygte.supabase.co/functions/v1/openai-proxy/responses \
  -H "Authorization: Bearer <USER_ACCESS_TOKEN>" \
  -H "apikey: <SUPABASE_ANON_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-5-nano","input":"ping"}'
```

Logs: Supabase Dashboard → Edge Functions → openai-proxy → Logs
(one line per call: `<path> user=<id> status=<code> <ms>`).

## iOS side

- `OpenAIService.baseURL` points to the proxy; requests carry the user's Supabase
  access token plus the public `apikey` header.
- `Config.openAIAPIKey`, the Keychain fallback and the "API Key Required" alert are gone.
  Delete `openAIAPIKey` from your local (gitignored) `Config.swift`.
  `openAIResponsesModel` and `openAIPromptID` are still used.
- A missing session throws `OpenAIError.notAuthenticated`.

## Key rotation (after the new build is live)

The old key is embedded in every previously shipped build, so treat it as leaked.
Once most users are on the proxy build:

1. Create a new key in the OpenAI dashboard.
2. `supabase secrets set OPENAI_API_KEY=<new>` and update `/etc/snipnote-transcription/env` on the VPS, then restart `snipnote-api` / `snipnote-worker`.
3. Revoke the old key. Older app versions will lose AI features at this point.

---

## For the Claude Code agent on Mattia's Mac: guide the user through setup

You're helping Mattia set this up on their Mac. **Guide, don't do.** Mattia pastes
the OpenAI key themselves. Never ask them to paste the key into the chat, never
put it in a file in this repo, and never run a command that has the key in it
on their behalf. Go one step at a time and wait for them to confirm each step
before moving on.

Supabase project ref: `bndbnqtvicvynzkyygte`

### Step 0: Merge this branch first
This branch was written against a copy of the code on origin that may be
older than Mattia's local code. Merge it into the local code and resolve
conflicts. They should be limited to `OpenAIService.swift`,
`CreateMeetingView.swift` and `SupabaseManager.swift`. The rule when
resolving: **no code path may call `api.openai.com` directly or read an
OpenAI key.** Every OpenAI request must use `baseURL` (the proxy) and
`proxyAccessToken()`. Afterwards, run
`grep -rn "api.openai.com\|openAIAPIKey\|apiKey" SnipNote/` and make sure no
key usage is left (comments are fine).

### Step 1: Get the key ready
Ask Mattia to open https://platform.openai.com/api-keys and either copy their
current key or create a new one (for example "snipnote-supabase-proxy").
Creating a new one is better. The old key has shipped inside the app, so it
will be revoked later (see Key rotation).

### Step 2: Add the secret. Option A: Dashboard (easiest, no install)
Walk them through this:
1. Go to https://supabase.com/dashboard/project/bndbnqtvicvynzkyygte
2. In the left sidebar, open **Edge Functions**, then the **Secrets** tab. If
   the UI has moved, look in **Project Settings → Edge Functions**.
3. Click **Add new secret**. Set Name to `OPENAI_API_KEY` (exactly that) and
   Value to the key they copied (`sk-...`). Save.
4. The key should now appear in the list, showing only a digest and not the
   value.

### Step 2: Add the secret. Option B: CLI
Mattia runs these themselves in Terminal:
```bash
brew install supabase/tap/supabase        # if `supabase --version` fails
supabase login                            # opens the browser
cd <path to SnipNote repo>
supabase link --project-ref bndbnqtvicvynzkyygte
supabase secrets set OPENAI_API_KEY=sk-... # Mattia types or pastes the key here
supabase secrets list                      # OPENAI_API_KEY should be listed
```
Tip: prefix the `secrets set` line with a space so it isn't saved in shell
history (this works in zsh only if `HIST_IGNORE_SPACE` is set). Or clear the
history line afterwards.

### Step 2b: Create the `ai_model_config` table
Use the SQL Editor, not `supabase db push`. The remote migration history may not match
this repo, and `db push` would try to apply every older migration.
1. Supabase Dashboard → **SQL Editor** → **New query**.
2. Paste the whole contents of `supabase/migrations/20260926_create_ai_model_config.sql`
   and click **Run**. Running it twice is safe: `IF NOT EXISTS` / `ON CONFLICT DO NOTHING`.
3. Table Editor → `ai_model_config` should show 7 rows, all `gpt-6-luna` / `low`.
4. Show Mattia how to edit a row. This is how models get switched from now on.

### Step 3: Deploy the function
Dashboard deploys aren't practical for multi-file functions, so use the CLI.
It needs `login` and `link` from Option B:
```bash
supabase functions deploy openai-proxy
```
`supabase/config.toml` already sets `verify_jwt = true` for it. Check that
`openai-proxy` appears under Edge Functions in the dashboard.

### Step 4: Verify
- Run the unauthenticated curl from the **Smoke test** section. It must return
  `401`. You can run this one yourself, since it contains no secrets.
- Mattia builds the app in Xcode. You don't build; Mattia will report any errors.
  Mattia deletes `openAIAPIKey` from the local `Config.swift` before building.
- In the app, Mattia tries a short recording (5 minutes or less), then checks the
  summary, title, actions, an Eve chat and the actions report.
- Dashboard → Edge Functions → openai-proxy → Logs should show lines like
  `/responses task=summary model=gpt-6-luna user=... status=200`.
- Optional: temporarily set one row's `model` to a bogus value such as `gpt-nope`, wait
  60 seconds and generate that feature. The logs should show the rejection and a retry
  with `gpt-6-luna`, and the app should still work. Then set the row back.

### Step 5: Hand off to the VPS
The VPS worker must be updated too (`jobs.py` reads the same table). Tell Mattia
to open the Claude Code session on the VPS and point it at `AI_MODEL_CONFIG.md`
in the `snipnote-transcription-service` repo (branch
`claude/ios-api-key-security-8vxoc2`). That file has the deploy and verify steps.
Deploy order: table (Step 2b), then function (Step 3), then VPS, then app build.

### Troubleshooting
| Symptom | Cause / fix |
|---|---|
| 500 `Server misconfigured` | `OPENAI_API_KEY` secret is missing or misspelled. Redo Step 2, then redeploy. |
| 401 `Invalid token` / `Invalid JWT` | User isn't signed in, or the app isn't sending the session token. Sign out and back in. |
| 403 `Endpoint not allowed` | The app called a path that isn't in `ALLOWED_PATHS` in `index.ts`. Add it there if that's intended. |
| 401 from OpenAI (`invalid_api_key`) | The secret value is wrong. Set it again. The new value is used on the next request, no redeploy needed. |
| 404 on the function URL | Function isn't deployed. Run Step 3. |
| Logs show `rejected (400) ... retrying with gpt-6-luna` | The configured model or parameter was refused (e.g. typo, or `minimal` effort on a GPT-6 model). Fix the row. |
| Logs show `model=as-sent` | No `X-SnipNote-Task` header, or no row for that task, so the app's defaults were used. Check the task name matches a row. |
| `Failed to load ai_model_config` | The table is missing (run Step 2b). The proxy keeps working with the app's defaults. |
