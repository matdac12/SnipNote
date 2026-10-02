# Supabase Setup Instructions

## OpenAI proxy and model configuration

OpenAI credentials are stored only in Edge Function secrets as `OPENAI_API_KEY`.
Never put an OpenAI key in `Config.swift` or the app Keychain. The public Supabase
anon key below authenticates the project and is safe to ship; it is not a service key.

See `../OPENAI_PROXY_SETUP.md` for deployment order, model configuration, server
quotas, conversation ownership, verification, and key rotation. Apply the model
configuration migration and the proxy security migration before deploying `openai-proxy`.
The proxy safety budgets are separate from purchased transcription minutes.

## Cloud transcription provider addition

Apply only `../supabase/migrations/20260930105323_add_transcription_provider.sql`
when adding provider support to the existing schema. Check linked migration
history first; do not replay all historical migrations. This adds
`transcription_jobs.transcription_provider text NOT NULL DEFAULT 'openai'` with
an OpenAI/xAI check and seeds the `ai_model_config` task row `transcription_xai` without
replacing existing configuration. RLS and client privileges are unchanged.

Set `XAI_API_KEY` in Edge Function secrets and independently on the VPS;
credentials never belong in `ai_model_config` or iOS. Deploy database addition,
credentials, proxy and VPS API/worker, then the app. Selection affects only
transcription; legacy requests/jobs default to OpenAI. See the provider rollout
and staging matrix in [OPENAI_PROXY_SETUP.md](../OPENAI_PROXY_SETUP.md).
Keep the additive schema during rollback and drain queued xAI jobs before using
workers without provider support. Run `supabase/tests/transcription_provider.sql`
only against a disposable/local database after the addition.

## Add Supabase Package Dependency

1. Open SnipNote.xcodeproj in Xcode
2. Select the project in the navigator
3. Select the SnipNote target
4. Go to the "Package Dependencies" tab
5. Click the "+" button
6. Enter the package URL: https://github.com/supabase/supabase-swift
7. Click "Add Package"
8. Select "Supabase" from the package products
9. Click "Add Package"

## Supabase Project Details

- Project URL: https://bndbnqtvicvynzkyygte.supabase.co
- Anon Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJuZGJucXR2aWN2eW56a3l5Z3RlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI0MTgyNDUsImV4cCI6MjA2Nzk5NDI0NX0.KJR2WxJBeTY4diMjXISBsFwFiYsniX1r0xjDIF0sgY8

## Enable Email Authentication in Supabase Dashboard

1. Go to https://supabase.com/dashboard/project/bndbnqtvicvynzkyygte/auth/providers
2. Enable "Email" provider if not already enabled
3. Configure email settings as needed

## Background upload sessions (not deployed)

The two 20261001 upload migrations add service-only tables and registration/promotion
RPCs. Clients authenticate to the existing transcription API with a Supabase access
token; the API validates it remotely and checks meeting ownership. No client table
permissions or existing RLS/bucket policies change. The server gate defaults off and
an empty allowlist enables nobody. See the background upload verification report
for local rehearsal evidence and the production approval checkpoint.

## Cancelling cloud transcription on meeting deletion

The app marks the user's pending/processing transcription jobs as `failed` with
`Cancelled by user` before deleting meeting metadata. The server checks job state
before transcription requests and only updates jobs still pending/processing,
preventing a stale worker from requeuing or completing cancelled work. A request
already in flight can finish. This uses the existing job UPDATE ownership policy
and requires no schema migration. Rebuild the iOS app to enable deletion-triggered
cancellation.
