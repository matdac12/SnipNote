# Task: Design (then build) the onboarding download of the Local mode model

**Date:** 2026-10-04 · **Repo:** SnipNote · **Branch:** main

## What to do
Run a design discussion with Mattia for Linear **MAT-1669** (onboarding step that downloads the ~600 MB Parakeet model with visible progress), settle its open questions, then write the decisions into the issue. Only once he agrees on the design, implement it. Start with the discussion, not code.

## Context you need
- ADR 0001 (`docs/adr/0001-local-mode-free-and-accountless.md`) makes **Local mode** free forever, account-less (**Guest**), and the default for new installs. Use the `GLOSSARY.md` terms.
- **MAT-1659** (done in code, left In Progress) makes new installs default to Local mode. But the Parakeet model is only downloaded by a manual button in Settings, and recording is blocked with a "missing model" alert until it is installed. So a fresh install currently cannot make its first recording. MAT-1669 exists to fix that and blocks MAT-1659 from shipping.
- Mattia's direction so far: an extra **onboarding step**. The user starts the download, carries on through the rest of onboarding while it runs, and can see the download status. He called it worth its own discussion, so do not assume answers to the open questions.

## Read first
- `MAT-1669` in Linear (team Matdac6, project SnipNote; load the `mcp__claude_ai_Linear__*` tools with ToolSearch). The open questions are listed in its description. Also read `docs/agents/issue-tracker.md` and `triage-labels.md`.
- `SnipNote/OnboardingView.swift` — the existing 4-screen onboarding and where a new step would go.
- `SnipNote/LocalTranscriptionManager.swift` — model status (`LocalModelStatus`), `download(_:)`, `isSelectedModelInstalled`, and the `downloadInFlight` UserDefaults keys. Find what the download already supports (progress, resume, cancel, survival across app kill). Also read the new `registerInitialModeIfNeeded()` added for MAT-1659.
- `SnipNote/ParakeetTranscriptionService.swift` and `LocalTranscriptionService.swift` — how the download is actually performed (foreground or background session).
- `SnipNote/TranscriptionSettingsView.swift` — the existing manual download UI to reuse or replace.
- `SnipNote/CreateMeetingView.swift` — `validateLocalTranscriptionAvailability()` (search by name, line numbers are moving) is the gate that blocks recording.
- `GLOSSARY.md` and the ADR above.

## Constraints
- **Never build the app.** It does not build here. When done, tell Mattia to build manually; he pastes back errors.
- **Never commit or push** unless Mattia asks (see `CLAUDE.local.md`).
- Local mode must stay free, account-less and never spend Minutes. No analytics events carrying emails, account IDs or content.
- Pricing and Stripe are frozen (MAT-1662): do not touch them.
- Do not reopen decisions in the ADR or the plan.
- **Other work is in the same working tree right now.** Two agents running in the original session are editing for MAT-1660 (analytics: a new analytics service, a Settings toggle, call-site insertions) and MAT-1661 (Apple Intelligence unavailable messaging: `MeetingAnalysis*` and meeting-detail views). Run `git status` first, keep your edits small, and avoid reformatting files you don't need to change. A single combined code review of those three issues is planned before anything is confirmed.
- Use `AskUserQuestion` for decisions that are Mattia's to make; give a recommendation rather than a survey.

## Definition of done
- [ ] Each open question in MAT-1669 has a decision from Mattia, recorded as a comment (or description update) on MAT-1669, and the issue is relabelled `ready-for-agent` if it is ready to build.
- [ ] If implementing: a fresh install can complete onboarding while the model downloads, with an accurate progress indicator.
- [ ] After the download finishes, the first recording is transcribed with Parakeet with no "missing model" alert.
- [ ] A failed or interrupted download shows a clear state and a retry, with nothing stuck.
- [ ] No Minutes involved, no account required.
- [ ] Final message says what changed and tells Mattia to build manually.

## Out of scope
- Analytics, Apple Intelligence messaging, Guest mode, Pro gating, pricing.
- Changing which transcription model is supported; only how it gets onto the device.
- Committing or pushing.

## Suggested skills
- `mattpocock-skills:grilling` — to work through the open questions with Mattia one at a time.
- `swiftui-pro` — when writing or reviewing the onboarding and progress UI.
- `mattpocock-skills:domain-modeling` — only if a decision is big enough to need an ADR.
