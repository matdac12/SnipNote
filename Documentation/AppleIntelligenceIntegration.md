# Apple Intelligence Integration

## Current Status
- Apple Intelligence testing is confirmed working in-app via the temporary `Apple` tab.
- The current Apple test prompts are close to production prompts but not exactly identical.
- Production still uses OpenAI prompt definitions in `OpenAIService`.

## Key Decision
- For production, use a **hybrid provider strategy** with **OpenAI fallback**.
- Default behavior should be **Automatic**:
  - If Apple Intelligence is available on the current device, use Apple.
  - Otherwise, use OpenAI.
- This is required because older devices (for example iPhone 13 series) do not support Apple Intelligence, while newer devices (for example iPhone 16 Plus) do.

## Rock-Solid Plan

### 1. Prompt Parity First
- Create a shared prompt source (for example `MeetingAnalysisPrompts.swift`) for:
  - Overview
  - Summary
  - Actions
- Both Apple and OpenAI providers must consume the exact same prompt templates.
- Goal: differences in output should come from model behavior, not prompt drift.

### 2. Provider Architecture
- Introduce `MeetingAnalysisProvider` protocol:
  - `generateOverview(transcript:)`
  - `generateSummary(transcript:)`
  - `extractActions(transcript:)`
- Implement:
  - `OpenAIMeetingAnalysisProvider`
  - `AppleMeetingAnalysisProvider`
- Add `MeetingAnalysisRouter` to select provider and handle fallback.

### 3. Settings & Defaults
- Add Settings section: `AI Analysis Provider`.
- Options:
  - `Automatic (Recommended)`
  - `OpenAI`
  - `Apple Intelligence`
- Default value: `Automatic`.

### 4. Availability & Compatibility Guardrails
- On every analysis call, check Apple model availability (`SystemLanguageModel.availability`).
- If Apple is unavailable in Automatic mode, route to OpenAI.
- Surface a clear unavailability reason for diagnostics:
  - device not eligible
  - Apple Intelligence disabled
  - model not ready
  - unsupported OS/SDK
- Keep OpenAI key and existing config validation unchanged.

### 5. Integrate Real Call Sites
- Replace direct `OpenAIService` analysis calls with router calls in:
  - `CreateMeetingView`
  - `LocalTranscriptionJobManager`
  - Retry/regenerate analysis paths
- Keep transcription backend logic and Eve chat behavior unchanged in v1.

### 6. Reliability & Observability
- Add telemetry for:
  - provider used (Apple/OpenAI)
  - latency
  - fallback occurrences
  - failure reason
  - actions JSON parse failure rate
- Add lightweight debug visibility of provider used per analysis.

### 7. QA Matrix
- Apple available + forced Apple.
- Apple unavailable + Automatic.
- Apple unavailable + forced Apple.
- Apple runtime failure + Automatic fallback.
- Actions schema parity:
  - `[{"action":"...","priority":"HIGH|MED|LOW"}]`
- Locale tests at minimum:
  - English
  - Italian

### 8. Rollout Strategy
- Phase 1: internal/dev-only toggle.
- Phase 2: beta rollout with Automatic default.
- Phase 3: full rollout after quality/fallback metrics are stable.

## Open Questions (To Finalize Before Implementation)
1. In **forced Apple** mode, should we hard-fail or fallback to OpenAI?
2. Should Eve chat stay OpenAI-only in v1? (recommended)
3. Do we want to store provider-used metadata per meeting for audit/debug?
4. Do we want a temporary side-by-side comparison view (Apple vs OpenAI on same transcript) before production rollout?
