# Repository Guidelines

## Project Structure & Module Organization
- `SnipNote/`: SwiftUI app sources. Views (e.g., `CreateMeetingView.swift`, `MeetingsView.swift`), services/managers (`OpenAIService.swift`, `SupabaseManager.swift`, `StoreManager.swift`), audio utilities (`AudioRecorder.swift`, `AudioChunker.swift`), theme/config (`Theme.swift`, `Config.swift`), and assets (`Assets.xcassets`).
- `SnipNoteTests/`: Unit tests using Swift Testing (`@Test`, `#expect`).
- `SnipNoteUITests/`: UI tests using XCTest (`XCUIApplication`, `XCTAttachment`).
- `SnipNote.xcodeproj/`: Xcode project and schemes.

## Build, Test, and Development Commands
- Open in Xcode: `open SnipNote.xcodeproj`
- Build (Simulator): `xcodebuild -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 15' build`
- Run unit + UI tests: `xcodebuild test -scheme SnipNote -destination 'platform=iOS Simulator,name=iPhone 15'`
- List schemes/targets: `xcodebuild -list -project SnipNote.xcodeproj`
Adjust the destination to a simulator available on your machine.

## Coding Style & Naming Conventions
- Swift 5.x, SwiftUI. Use 2‑space indentation, `PascalCase` for types/files, `camelCase` for vars/functions, `UPPER_SNAKE_CASE` for constants.
- Views end with `View` (e.g., `SettingsView`); service singletons end with `Service`/`Manager` (e.g., `OpenAIService.shared`). One primary type per file.
- Keep business logic in services/observable models; keep views declarative and side‑effect free where possible.
- Prefer `private`/`fileprivate` access where appropriate; avoid force unwraps.

## Testing Guidelines
- Unit tests: place in `SnipNoteTests` using Swift Testing. Example:
  ```swift
  @Test func generatesTitle() async throws { /* … */ }
  ```
- UI tests: place in `SnipNoteUITests` using XCTest; name methods `test…()` and use `XCUIApplication().launch()`.
- Aim to cover services (OpenAI, audio, auth) with deterministic tests; keep UI assertions resilient.

## Commit & Pull Request Guidelines
- Commits: concise, imperative subject (≤ 50 chars), optional scope. Examples: `Add audio chunking retries`, `Fix paywall layout on iPad`.
- PRs: include purpose, summary of changes, linked issues, and screenshots/video for UI changes. Note any schema/config changes (e.g., Supabase, StoreKit).
- Ensure `xcodebuild … build test` passes locally before requesting review.

## Security & Configuration Tips
- Do not commit secrets. `OpenAIService` prefers Keychain; `Config.swift` should only hold placeholders or read from secure config (consider `.xcconfig` for local overrides).
- See `SUPABASE_SETUP.md` for backend setup. If touching auth/usage tracking, update that doc accordingly.
- Review `Info.plist` and entitlements when adding capabilities (microphone, networking).

## 2025-08-03 – Eve Vector Store Integration
- Eve chat now relies on the OpenAI Responses API with `file_search`; transcripts are provided via a per-user vector store instead of inline prompt variables.
- Introduced `UserAIContext` + `MeetingFileState` models to persist a user’s vector store id and per-meeting file metadata (file id, expiry, attachment flag).
- App ensures a single vector store per Supabase user, created with a 14-day `last_active_at` expiry; files are uploaded as text, attached, and detached as the user tweaks Eve’s context.
- `EveView` runs all SwiftData mutations on the main actor to avoid Swift 6 `Sendable` issues and synchronizes attachments whenever meetings are selected/deselected or conversations reset.
- `OpenAIService` gained helpers to create vector stores, upload transcripts (`user_data` purpose, 7-day file expiry), and manage file attach/detach lifecycle.
- Default behavior keeps all meetings attached; context filtering simply detaches files so we can reattach without re-uploading when the user broadens the scope again.
