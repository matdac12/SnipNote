# Task: Lock down database functions that anon can call (MAT-1670)

**Date:** 2026-10-04 · **Repo:** SnipNote · **Branch:** main

## What to do
Work Linear **MAT-1670**. The Supabase security advisor shows many `SECURITY DEFINER` functions in `public` that `anon` and `authenticated` can execute through `/rest/v1/rpc/...`. The anon key ships in the app, so anyone can call them. The worst case seen so far is `credit_minutes_admin(p_user_id, p_amount, ...)`, which has no `auth.uid()` or service-role check in its body, so it appears to credit Minutes to any user. Confirm which functions are truly exploitable, find their legitimate callers, then prepare a migration that revokes `EXECUTE` where only the service role should call, and adds an ownership or purchase check where signed-in users must keep calling. Investigate read-only first. **Do not apply anything to prod until Mattia approves your plan.**

## Context you need
- Pro is defined as an Account holder with a positive Minutes balance (`GLOSSARY.md`), and Pro gates sync and the web app. A forgeable balance therefore means free Pro.
- No exploit has been attempted. Do not attempt one against prod. Prove exploitability from the function source and the grants (`has_function_privilege`), not by calling the functions.
- The Supabase project is `bndbnqtvicvynzkyygte`. The Supabase MCP tools are connected. Use `execute_sql` with SELECTs only until approval; `get_advisors` (type `security`) lists the flagged functions.
- The legitimate callers can be in four places. Check them all before revoking anything:
  - the iOS app (`SnipNote/MinutesManager.swift`, `SupabaseManager.swift`, `StoreManager.swift`, `UsageTracker.swift`; grep for `.rpc(`),
  - the deployed Edge Functions (use the MCP `list_edge_functions` and `get_edge_function`, for example `validate-storekit-transaction` and the OpenAI proxy),
  - the transcription worker in `../snipnote-transcription-service` (it uses the service role),
  - the web app in `../snipnote-website`.
- Database triggers call some of the flagged functions (for example `debit_minutes_on_job_completion`, `handle_new_user_signup`, `cleanup_audio_on_job_completion`). Trigger functions fire as the table owner, so revoking `EXECUTE` from `anon` and `authenticated` should not break them, but verify that rather than assume it.
- **Overlap with MAT-1664 (Guest mode), which another agent is working on in a worktree.** That task changes when the Trial grant is claimed, and the iOS app may call `grant_free_tier_minutes` or similar through RPC. Record exactly which RPCs the app calls so Mattia can reconcile the two before anything is revoked.

## Read first
- Linear MAT-1670 (load the `mcp__claude_ai_Linear__*` tools with ToolSearch), and `docs/agents/issue-tracker.md` for conventions.
- `GLOSSARY.md` and `docs/adr/0001-local-mode-free-and-accountless.md` for the Pro, Minutes and Trial grant vocabulary.
- `supabase/migrations/` for the existing style, especially `20261002102926_prevent_repeat_completion_debit.sql` and `20261004170000_create_meeting_deletions.sql` (trigger plus revoke pattern).
- `CLAUDE.md` (Sept 16 and Sept 26 notes) for how credits, duplicate transactions and `minutes_transactions` are meant to work.

## Constraints
- **Never build the app.** It doesn't build here. Tell Mattia to build manually when you finish.
- **Never commit or push** unless Mattia asks (`CLAUDE.local.md`).
- Pricing and Stripe are frozen (MAT-1662). This task is database permissions only.
- Do not change function behaviour beyond adding permission or ownership checks. Do not rename functions or change signatures: shipped app versions call them.
- Prod writes (applying the migration) need Mattia's explicit go-ahead after he has seen the plan. Approvals for earlier migrations do not carry over.
- Write the SQL as a file in `supabase/migrations/` (new timestamp), apply it with the MCP `apply_migration` only after approval, and keep the file and the applied SQL identical.
- Other work is going on in this repo and in a worktree. Run `git status` first and keep edits to your migration and, if truly needed, small call-site changes.

## Definition of done
- [ ] A table of every flagged function: who can execute it today, whether it checks the caller, who legitimately calls it, and the proposed fix (revoke, add a check, or leave).
- [ ] Plan shown to Mattia and approved.
- [ ] Migration file written and applied. `credit_minutes_admin` is no longer executable by `anon` or `authenticated`, and signed-in users cannot credit themselves Minutes without a verified purchase.
- [ ] Verified with `has_function_privilege` for `anon` and `authenticated` on each changed function, and `get_advisors` re-run to show the findings gone.
- [ ] A short manual regression list for Mattia: buy a pack or subscription (sandbox), check the credit lands once, transcribe and check the debit, sign up and check the Trial grant, and run a server transcription so the worker still works.
- [ ] MAT-1670 updated with a comment and moved to Done once Mattia confirms.

## Out of scope
- Leaked-password protection, the Postgres version upgrade, and the mutable `search_path` warnings. Mention them in your report only; do not fix them here unless Mattia asks.
- Guest mode, Pro gating and pricing.
- Committing or pushing.

## Suggested skills
- `mattpocock-skills:diagnosing-bugs` — only if a revoke breaks a real flow and you need to trace it.
- `security-review` — to review your migration before asking for approval.
