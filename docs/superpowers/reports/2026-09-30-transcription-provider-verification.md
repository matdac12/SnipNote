# Transcription provider implementation verification

Approved spec and plan: `../specs/2026-09-30-transcription-provider-design.md`
and `../plans/2026-09-30-transcription-provider.md`.

## Workspaces and baseline

- App: `/private/tmp/snipnote-provider-ios`, branch `feature/transcription-provider`.
  Original main remains `53af2dc`. Proxy auth/quota/ownership changes and their
  tests were already committed at `e321fef`, contrary to the plan's older
  working-tree description; starting from local HEAD preserved them.
- Relevant pre-existing app changes are separate in `5dcd427`: version 2.7/build 1,
  approved spec/plan, and unfinished proxy test draft. The missing-key fixture was
  repaired in the feature commit. Skill metadata, untracked skills and CLI cache
  were excluded. Original ignored configuration was not copied.
- Service: `/private/tmp/snipnote-provider-service`, branch
  `feature/transcription-provider`, based on local main `5176d6b`, not origin/main.
  All four unpushed configuration commits are included: `974e4c1`, `776d63f`,
  `7ee9642`, `5176d6b`.
- Original app status, full tracked diff and relevant SHA-256 hashes were captured
  in `/private/tmp/snipnote-provider-baseline` and compared after implementation:
  unchanged. Original service remained clean and both main tips unchanged.
- No push, merge, production database mutation, function deployment, secret change,
  VPS restart or paid AI call was performed. Supabase MCP was used read-only for
  actual schema/configuration/constraints/policies. The user separately reported
  setting the Supabase `XAI_API_KEY`; it was not read or tested live.

## Completed behavior

Cloud Settings saves OpenAI/xAI selection with English/Italian copy; missing or
unknown stored values use OpenAI. Cloud requests capture the selection once and
carry it through audio preprocessing, chunks and retries. Server bootstrap
captures it before asynchronous upload; both regular/chunked job retry helpers
forward that value. Manual retranscription goes through the same router and
uses the current preference. Existing job retry/resume keeps the stored provider.

The proxy accepts the provider only on `/audio/transcriptions`, preserves its
existing authentication/quotas/limits, and sends xAI requests to a fixed private
`/v1/stt` endpoint. Options precede file, optional language enables formatting,
auto language omits both fields, and unusable xAI responses fail. Provider errors
are sanitized with status preserved and never switch providers. VPS API validates
provider input, persists it on jobs and carries it through internal/parallel
chunk dispatch. An omitted provider defaults to OpenAI; explicit invalid values,
including empty multipart values, are rejected. Model IDs come from
`transcription`/`transcription_xai` rows using existing cache semantics.

Summary, overview, actions, title, text summary and Eve model configuration and
functions have no feature changes. Local transcription, audio processing,
notifications and minutes accounting retain existing implementations.

## Automated results

| Check | Actual result |
| --- | --- |
| Service `python -m unittest discover -s tests -v` | 20 passed, 0 failures; HTTP/DB/download/text-generation boundaries faked |
| Service `python -m compileall -q main.py ai_config.py transcription_provider.py transcribe.py jobs.py supabase_client.py` | Exit 0 |
| Proxy `deno test handler_test.ts transcription_test.ts` | 19 passed, 0 failures, including all 8 unchanged security cases |
| Proxy `deno check index.ts handler.ts` | Passed |
| Proxy `deno fmt --check handler.ts index.ts transcription_test.ts` | Passed |
| Disposable PostgreSQL 17 SQL tests | Passed; red before column existed; defaults/check/NULL/seed validated |
| Local migration preservation/rerun | Existing job backfill, other model rows, RLS and ACL unchanged; edited xAI model preserved on rerun |
| Targeted iOS `xcodebuild test` | 11 passed, 0 failures, 0 skipped |
| Settings UI test | Ran; skipped for absent signed-in account/onboarding prerequisite |
| Full iOS `xcodebuild build test` | Build succeeded; 68 unique tests passed, 0 failed, 2 skipped (75 successful device runs including dynamic launch cases) |
| Both feature diffs `git diff --check` | Passed |

Simulator: iPhone 17 Pro, iOS 26.5, UUID
`A565668D-42A4-4D9B-957F-27C64E326274`, Xcode 26.6.
Targeted tests ran the real cloud router and audio preprocessing/chunk loop on
65-second PCM audio above 1.5 MB, changing Settings after the first request;
a second case exercised an actual transient HTTP 500 retry. Every request kept
xAI. No chunk/retry loop was mocked away.

Full suite skips: opt-in paid minutes-debit test (not authorized), signed-in
Settings persistence UI case (no test account). Existing test/compiler warnings
and pre-existing share-extension build 3 versus app build 1 mismatch remain;
these did not fail the build. Simulator emitted shutdown/LLDB diagnostics after
a successful run; xcresult records zero failures. No production StoreKit/release
archive validation was performed.

Database verification used an isolated standalone PostgreSQL cluster on
localhost:55439 with baseline job/config migrations and minimal auth role stubs,
not Docker or linked Supabase. The installed CLI (2.24.3) lacks local advisors;
explicit policy/privilege catalog comparisons verified no new client access.
Logs/results are in `/private/tmp/snipnote-provider-*.log` and
`/private/tmp/snipnote-provider-derived/Logs/Test/`.

## Review and fix

A fresh read-only reviewer checked both branches and independently reran the
19-test service suite, proxy tests and whitespace checks. It found one Important
issue: FastAPI treated an explicitly empty `/transcribe` provider field as the
OpenAI default. Regression reproduced 200 instead of 422; raw-form validation
fixed it; the complete service suite now passes 20 tests. The correction is
committed separately as `11f046c`. No other concrete feature defects were found.

## Rulings made

1. Worktrees use `/private/tmp` to leave original ignore files untouched. Cost:
   preserve these temporary paths until handoff.
2. Builds use a local ignored copy of `Config.swift.example` with a placeholder
   public Eve prompt ID; original ignored config was not copied. Cost: live Eve
   verification requires the normal local public prompt configuration.
3. UI test skips only an absent signed-in/onboarding prerequisite; no auth bypass
   was added. Cost: signed-in UI persistence remains manual verification.
4. Live quality/model/credential checks remain separately authorized staging work.
   Cost: deployed availability/quality is unverified.
5. Signed-in UI and view upload-delay integration remain pending, as allowed by
   the plan's seam limitation. Cost: manual simulator/staging coverage remains.
6. Full iOS/database results rely on executor evidence, not an independent second
   run by the reviewer. Cost: those checks have one verifier.
7. Existing OpenAI blank-response/SDK error behavior is unchanged by this feature.
   Cost: preserved baseline behavior remains.
8. Existing VPS authentication design is outside this provider feature. Cost:
   unchanged baseline security architecture remains.
9. Local-resume history and exact model pinning remain explicitly excluded. Cost:
   the existing 60-second model cache can observe edits during a job.

No minor findings were deferred.

## Remaining rollout/manual work

See [OPENAI_PROXY_SETUP.md](../../../OPENAI_PROXY_SETUP.md#saved-cloud-transcription-provider-rollout)
and the service `DEPLOYMENT.md` provider release section.

1. Inspect production migration history and apply only
   `20260930105323_add_transcription_provider.sql`; do not blanket-push history.
2. Configure the VPS `XAI_API_KEY` in `/etc/snipnote-transcription/env` before
   provider-capable API/worker deployment. Supabase secret is already set per
   user report; do not print keys or assume its presence verifies the provider.
3. Deploy the reviewed proxy with JWT verification and the service API/worker
   including local main's four configuration commits; restart both VPS units.
4. Run the documented paid staging matrix: both providers, short proxy and long
   regular/chunked jobs, English/Italian/auto, preference changes during delayed
   upload/retry, missing-key/status failures, progress/notifications/minutes and
   unchanged text behavior. Verify signed-in Settings persistence across relaunch
   and Local/Cloud toggles. These tests were prepared, not executed.
5. Release iOS last. For rollback, keep the additive schema and drain or explicitly
   fail queued xAI jobs before deploying workers that ignore provider.
