# Transcription provider production deployment

The user explicitly authorized production migration, Edge Function deployment,
VPS credential configuration/restarts, and then merging both feature branches
into local main. This authorization supersedes the implementation-only limits
recorded in the earlier verification report. No GitHub push or iOS publication
was performed.

## Deployed revisions

- iOS feature merged by fast-forward into local main at `dc389e9` (plus this
  deployment record). Service feature merged into local main at `7cc8460`.
- VPS `/opt/snipnote-transcription` fast-forwarded from `5176d6b` to
  `7cc8460d8904154f2a34303abd28bde6cd92bdbf` using a verified Git bundle over SSH.
  No tracked VPS edits existed; its untracked `.venv` was retained.
- Supabase project: `bndbnqtvicvynzkyygte`.
- Only the reviewed `add_transcription_provider` migration was applied.
  **Remote migration version: `20260930113230`**. Its source is local file
  `supabase/migrations/20260930105323_add_transcription_provider.sql`.
  MCP assigns its own timestamp, as for the earlier model/security migrations;
  do not infer that this migration is unapplied from differing filenames, or
  blindly replay local migration history.
- `openai-proxy` deployed as **version 5**, status ACTIVE,
  **verify_jwt=true**. All four deployed source files exactly match the reviewed
  worktree. Initial MCP deployment returned an internal error; CLI deployment
  of the same sources succeeded. The prior version 4 source/metadata is saved
  at `/private/tmp/snipnote-provider-proxy-v4-backup.json` for rollback preparation.
- Both VPS units restarted at **2026-09-30 11:36:58 UTC**:
  `snipnote-api.service` and `snipnote-worker.service`.

## Credentials

The existing `XAI_API_KEY` was read from
`/root/Documents/OMNI/whatsapp-omni/.env` and copied **entirely on the VPS** into
`/etc/snipnote-transcription/env`. The WhatsApp source was unchanged. No key was
printed, returned to the Mac, added to code, or placed in database configuration.
The target is root-owned, mode 600. A protected pre-change environment backup is
`/etc/snipnote-transcription/env.before-provider-20260930` (also mode 600).

Both live service processes were checked through `/proc` and have a nonempty
`XAI_API_KEY` inherited from systemd. Supabase secret metadata separately confirms
the `XAI_API_KEY` name exists; secret values/digests were withheld. Credential
validity against a paid transcription endpoint was not tested.

## Verified results

- Local pre-deployment tests: service **20/20**, proxy **19/19**, Deno type checks
  passed. Earlier full iOS simulator build/test remains **68 passed, 2 skipped**.
- Tests rerun in the **VPS's existing virtual environment: 20 passed, 0 failures**.
  Python syntax validation passed before restarting.
- Both units are active/running, with **NRestarts=0** after deployment. Filtered
  post-restart journal inspection found **zero exception/configuration-failure
  entries**. Raw logs were withheld to avoid printing meeting content.
- VPS real Supabase configuration lookup resolves `transcription` to
  `gpt-transcribe`, and `transcription_xai` to `grok-voice-transcribe-2.0`.
- Localhost and public `https://api.snipnote.app` health return **200/healthy**.
  Live OpenAPI schemas advertise OpenAI/xAI with default OpenAI on job request
  and status models.
- Explicit unknown/empty provider values on both `/jobs` and multipart
  `/transcribe` return **422** through localhost and the public endpoint. These
  requests created no jobs and made no transcription calls.
- A read of an existing completed job through the public status endpoint returns
  **200** and `transcription_provider=openai`. Transcript/content was withheld.
- Live proxy unauthenticated xAI transcription returns **401**. CORS preflight
  returns **200** and allows `x-snipnote-transcription-provider`.
- Production schema now has `transcription_provider text NOT NULL DEFAULT
  'openai'` with the named OpenAI/xAI check constraint. All **189 existing jobs**
  received OpenAI. The xAI seed has NULL effort/verbosity/fallback.
- Before/after snapshots confirm every other model row (including timestamps),
  job/config table policies, privileges and RLS flags are **unchanged**.
- Security advisors were reviewed: notices concern existing tables/functions/auth
  settings, not objects introduced by this additive column/config-row migration.
  No unrelated security configuration was changed during this deployment.
- Before restart there were no pending jobs. Four existing processing rows have
  not updated since August; these pre-existing stale rows were left untouched.
  Job status counts stayed at 175 completed / 10 failed / 4 processing.

## Local merge preservation

The app checkout contained version settings and untracked plan/spec/test files
that overlap the feature. Originals were backed up under
`/private/tmp/snipnote-provider-before-main-merge`. The already-preserved project
version change was stashed before the fast-forward and is now included in main;
its content matches the pre-merge file exactly. That backup stash is retained
with message `Preserved pre-existing version settings before provider merge`.
Do not pop it blindly: its version change is already committed.

Unrelated `skills-lock.json`, `supabase/.temp/cli-latest` and untracked Supabase
skill folders remain in the original app checkout. Tracked file bytes were
compared after the merge and remain unchanged. The service checkout remains
clean. Both feature worktrees are retained. Remote GitHub branches were not pushed.

## Remaining release verification

Backend deployment is complete. The new iOS code is on local main but has not been
published. Before releasing it, run the approved staging/manual matrix from
`OPENAI_PROXY_SETUP.md`: short proxy and long regular/chunked recordings for both
providers with English/Italian/auto language, preference changes during delayed
upload/retry, transcript quality with current preprocessing, unchanged text
outputs, progress/notifications/minutes, and signed-in Settings persistence across
relaunch and Local/Cloud toggles. Paid transcription calls were not performed in
this deployment session.

For rollback, retain the additive column/config row. Stop new xAI submissions and
drain or explicitly fail queued xAI jobs before using a worker without provider
support. Review source/environment backups before reverting; do not accidentally
reuse the current key's removal as a production smoke test.
