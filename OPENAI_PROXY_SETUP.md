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

The transcription server (VPS, `api.snipnote.app`) is unaffected: it reads
`OPENAI_API_KEY` from `/etc/snipnote-transcription/env`.

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
