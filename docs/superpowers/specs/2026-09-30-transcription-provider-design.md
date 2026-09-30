# Saved transcription provider selection

## Intent and scope

Let a user choose OpenAI or xAI for cloud audio transcription and save that choice in Settings. The reason for adding xAI is its lower published transcription price. Both short recordings processed through the Supabase proxy and longer recordings processed on the VPS must honor the choice.

The user approved the conversational design and explicitly limited the feature to transcription. This document captures that design for review alongside the implementation plan; writing these documents does not authorize implementation, deployment, or publication.

Global constraints:

- Change only cloud transcription provider selection and its supporting configuration, requests, jobs, tests, and documentation.
- Preserve summary, overview, actions, title, text summary, and Eve model behavior and configuration.
- Preserve Cloud/On-device selection, local Whisper models, existing audio preprocessing, chunking thresholds, transcript merging, progress, notifications, and minutes accounting.
- Default to OpenAI for missing preferences, unknown stored preference values, older clients, and jobs without a provider field.
- Accept only `openai` and `xai` on network requests; reject unknown values rather than defaulting them.
- Save the preference locally under `cloudTranscription.provider`; cross-device preference synchronization is outside this feature.
- Keep provider credentials in backend secrets/environment variables; never place them in the iOS app or `ai_model_config` rows.
- Use existing SwiftUI, SwiftData, Supabase, Deno, FastAPI, OpenAI SDK, and httpx infrastructure; do not add product dependencies or change platform/language version targets.
- Follow repository naming and access conventions; use two-space indentation in new Swift files and existing formatting elsewhere.
- Preserve unrelated working-tree changes; do not push, apply live migrations, publish functions, or restart VPS services as part of implementation without explicit authorization.

## Baseline

The iOS repository is `SnipNote/SnipNote`; the sibling VPS service repository is `SnipNote/snipnote-transcription-service` (`../snipnote-transcription-service` from the app root).

The service branch `origin/claude/ios-api-key-security-8vxoc2` was merged into local `main` by fast-forward at `5176d6b`. Local `main` is four commits ahead of `origin/main`; this merge has not been pushed or deployed. Its `ai_config.py` reads model rows from Supabase with a 60-second cache. Credentials still come from the VPS environment.

The app has an existing Cloud/On-device picker in `SettingsView.swift`. Short cloud transcription follows `TranscriptionRouter` → `OpenAIService` → `openai-proxy`. Longer recordings follow `CreateMeetingView` → `RenderTranscriptionService` → VPS `/jobs` → `jobs.py` → `transcribe.py`.

The app working tree also contains unrelated proxy authentication/quota changes, localization/configuration changes, and tests. The current proxy implementation is in `handler.ts`, with `index.ts` providing dependencies. Preserve that baseline, including its endpoint allowlist, authentication, quotas, body limits, and conversation ownership checks.

An unimplemented test draft, `supabase/functions/openai-proxy/transcription_test.ts`, was added before the user clarified the documentation-only scope. It is not a passing test suite or product implementation. Its fixture incorrectly uses a default argument for the missing-key case; an executor must repair that fixture before treating its failures as evidence.

## Settings and lifecycle

Add a cloud-only picker labeled “Transcription provider”, with options “OpenAI” and “xAI (Grok)”. Its explanatory copy is “Applies to new cloud transcriptions.” Localize through `Localizable.xcstrings`, including the app's existing English and Italian translations. Do not show fixed model versions or prices in the picker: administrators can change model IDs centrally.

Use `CloudTranscriptionProvider` (`String`, `Codable`, `CaseIterable`, `Identifiable`, `Sendable`) and a small `@MainActor` settings store. Provider raw values are exactly `openai` and `xai`. The preference remains saved when switching to On-device mode and back.

For short cloud transcription, capture the preference once at the cloud branch of `TranscriptionRouter`. Pass it explicitly through all processing/chunk/retry functions. For server processing, capture it in `CreateMeetingView.processServerSide(audioURL:)` before asynchronous audio upload, and pass the same value through both job-creation retry helpers. Changing Settings while a transcription or upload is running affects the next new transcription only.

Manual retranscription starts a new operation and uses the current preference. Retry/resume of an existing server job uses that job's stored provider. No meeting-level provider history or local-resume schema change is required.

## Wire contract and shared model configuration

| Boundary | Selection field | Missing value |
| --- | --- | --- |
| iOS → Supabase `/audio/transcriptions` | `X-SnipNote-Transcription-Provider: openai` or `xai` | OpenAI |
| iOS → VPS `/jobs` (regular and chunked) | JSON `transcription_provider` | OpenAI |
| VPS synchronous `/transcribe` | multipart `transcription_provider` | OpenAI |
| Stored `transcription_jobs` row | `transcription_provider text NOT NULL DEFAULT 'openai'` | Existing rows become OpenAI |

Add a database check constraint limiting the job column to the two values. Keep existing job RLS and client privileges unchanged. Return the field in VPS job status responses with a default of `openai` for legacy dictionaries; iOS need not display or require it.

Keep the existing `ai_model_config.task = 'transcription'` row for OpenAI. Add `task = 'transcription_xai'`, seeded with `model = 'grok-voice-transcribe-2.0'` and NULL `reasoning_effort`, `verbosity`, and `fallback_model`. Insert without overwriting any administrator-edited rows. Do not update other task rows.

Provider selection is captured per operation/job. Model IDs retain the existing eventual-consistency semantics of backend configuration caches; this feature does not pin an exact model revision for an entire job.

## Provider requests

OpenAI continues to use its existing SDK/endpoint, transcription row, and configured same-provider fallback behavior. The app continues posting to the same proxy URL with `X-SnipNote-Task: transcription`; the proxy chooses the provider-specific configuration internally. No client-controlled upstream URL, API key, or effective model ID is accepted.

xAI uses `POST https://api.x.ai/v1/stt`, bearer authentication with `XAI_API_KEY`, and multipart form data. Put model and language/options before the file: xAI may ignore options after the file. For container audio, preserve the filename and MIME type and omit raw-audio format/sample-rate fields. Do not send OpenAI's `response_format` field.

When language is explicitly supplied, send that language and `format=true`. Without a language, omit both fields, allowing xAI language detection; its language parameter controls text formatting rather than the same language-hint behavior as OpenAI. Read the JSON `text` string into the existing transcript contract. A malformed response or a whitespace-only transcript must fail rather than complete a meeting with unusable text. Timestamps, multichannel support, diarization, keyterms, streaming, and provider-specific preprocessing changes are outside this feature.

The proxy gets `XAI_API_KEY` from Supabase Edge Function secrets. The VPS gets it from its existing environment file. Those deployments need the same credential configured separately, as with OpenAI today. Moving VPS key access into Supabase Vault or a new credential broker would be a separate design.

## Failures and compatibility

Missing xAI credentials produce an actionable configuration failure without contacting OpenAI. Unknown provider values fail validation (proxy HTTP 400; FastAPI HTTP 422). Legacy callers remain on OpenAI. A provider header on a non-transcription proxy endpoint is rejected with HTTP 400 so this feature cannot change text-model routing.

Keep existing transient retry policies, forwarding sanitized status information needed to distinguish 401/403 from 429/5xx. Never switch from xAI to OpenAI automatically. If an administrator configures `fallback_model` for xAI, it means another xAI model and is retried only for HTTP 400/404, matching the existing same-provider fallback policy. Rewind/rebuild audio before any retry.

The new proxy path must retain authentication, usage reservation/release, body-size limits, allowed multipart fields, and sanitized error responses. Do not log credential values or upstream response bodies. Keep the externally allowed path `/audio/transcriptions`; `/stt` is only an internal upstream destination.

## Verification and rollout

Deterministic tests cover preference persistence, missing/invalid preferences, OpenAI legacy requests, xAI model lookup/request ordering, authentication/quota preservation, provider isolation on failures, queued job persistence, regular and parallel chunks, and preference changes during upload/retry. Use HTTP/DB boundary fakes; automated tests must not call paid AI APIs or mutate production Supabase.

Run Deno tests/type checking, the service's unittest suite, relevant database tests against a disposable/local database, and iOS build/unit/UI checks on an available simulator. Disclose infrastructure limitations rather than claiming those checks passed.

Prepare documentation for deploying the database addition first, configuring xAI secrets, deploying the proxy and VPS API/worker, and releasing the app last. Verify one short and one long transcription per provider with English and Italian audio before rollout. This smoke test checks transcription quality with the existing audio preprocessing; it does not promise quality parity from price alone.

Rollback the app/backend release together if needed. Retain the additive job column and configuration row; do not drop them while queued xAI jobs exist. Existing users default to OpenAI and can select it again. These are release instructions, not authorization to perform a live rollout.

## References

- [xAI speech-to-text guide](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text): endpoint, versioned model IDs, multipart ordering, language formatting, response fields.
- [xAI transcription pricing](https://docs.x.ai/developers/models/speech-to-text): published REST rate of $0.10/hour at research time; recheck before publishing any price claims.
- [Supabase function secrets](https://supabase.com/docs/guides/functions/secrets): backend credential configuration.
- `../snipnote-transcription-service/AI_MODEL_CONFIG.md` and `OPENAI_PROXY_SETUP.md`: existing shared model configuration and deployment instructions.
