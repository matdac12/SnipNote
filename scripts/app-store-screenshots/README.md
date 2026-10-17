# App Store screenshots

Everything that made the SnipNote 3.0 App Store images (October 2026). One command regenerates them:

```sh
scripts/app-store-screenshots/run-all.sh              # English, into ../snipnote-marketing/App Store <version>
scripts/app-store-screenshots/run-all.sh /tmp/shots it # Italian UI, into /tmp/shots
```

It overwrites files in the output folder, so pass a new folder to keep an older set. It takes about ten minutes and needs Xcode, the `iPhone 17 Pro Max` and `iPad Pro 13-inch (M5)` simulators, and Google Chrome.

## What it produces

| Folder | Size | App Store Connect slot |
| --- | --- | --- |
| `iPhone 6.3 inch/Framed` | 1206×2622 | iPhone with Dynamic Island (medium display) |
| `iPad 13 inch/Framed` | 2064×2752 | iPad 13" display |
| `*/Raw` | same | plain screenshots, spares |
| `Header and Search Results` | 3840×1646 and 3840×2560 PNG | product page header, search results |

Upload the framed sets in their numbered order; the first three also appear in search results.

## How it works

1. **Screenshot mode** (`SnipNote/ScreenshotSeed.swift`, debug builds only). Launching with `--screenshot-seed` skips onboarding, stays a Guest in Local mode, turns analytics off, reports the Parakeet model as installed, shows a 480-minute balance, skips StoreKit, and never syncs. The meetings live in an in-memory store, so nothing touches Supabase. Small `#if DEBUG` guards in `SnipNoteApp`, `StoreManager`, `MinutesManager`, `LocalTranscriptionManager`, `AccountGate` and `MeetingSyncService` hook it in. Edit the sample meetings in `ScreenshotSeed.samples`.
2. **Capture** (`SnipNoteUITests/AppStoreScreenshotsUITests.swift`, run by `shoot.sh`). The UI test taps through Home, Transcriptions, a meeting, search, Settings, Transcription, Dictation keyboard and a live recording, and writes each screen as PNG plus an element-tree `.txt` (handy when a tap misses). Without `TEST_RUNNER_SNIPNOTE_SHOTS_DIR` the test skips, so normal test runs are unaffected.
3. **Frames** (`frame.py`): headline over each screenshot, rendered with headless Chrome. Captions for English and Italian are in `SHOTS`.
4. **Header and search results** (`hero.py`): built from the iPhone screenshots.

## Rules learned the hard way

- **Sizes App Store Connect accepted:** iPhone 1206×2622 (it rejected 1320×2868), iPad 2064×2752. Header 3840×1646 and search results 3840×2560 as **PNG**: the header slot rejected `.jpg` although the spec page lists it. No alpha channel.
- **Safe areas** from Apple's templates (keep key content inside, the rest may be cropped): header ~1646×660 centered, search results ~2165×1027 centered, universal 16:9 (5244×2950) ~1403×957 centered at (2622, 1141). Templates: https://developer.apple.com/app-store/asset-best-practices/
- **No prices, URLs or awards** in any image, and no "free summaries" without the Apple Intelligence condition (`docs/app-store-wording-local-mode.md`).
- **The simulator can't draw emoji** (they show as "?" boxes), so UI must use SF Symbols where it would appear in screenshots.
- **A stale Supabase session in the simulator keychain** showed a real email in Settings; `shoot.sh` runs `simctl keychain reset` first.
- **Run with `-parallel-testing-enabled NO`**, or Xcode tests on a clone of the simulator without the status-bar override.
- **On iPad the tabs are top buttons**, not a tab bar; the test finds them by their symbol identifier.
- **Not automated:** the keyboard inside another app (needs the real model and live dictation), and sample meetings in Italian (the seed is English only).
