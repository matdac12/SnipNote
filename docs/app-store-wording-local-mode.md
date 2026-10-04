# App Store wording: Local mode and Apple Intelligence (MAT-1661)

Local mode (free forever, see `docs/adr/0001-local-mode-free-and-accountless.md`) transcribes on the device for everyone. Summaries in Local mode run on Apple Intelligence, so they only exist on devices, settings and languages that support it. Marketing must say so plainly and never promise summaries to everyone.

## One-line claim

**Free transcription; free summaries on Apple Intelligence devices.**

Do not use "free AI summaries" or "free meeting notes" without the Apple Intelligence qualifier.

## Suggested App Store description snippet

> Record a meeting and SnipNote transcribes it on your iPhone, free forever, with no account and no limits. On iPhones with Apple Intelligence, SnipNote also writes a summary of every meeting for free, right on your device. On other iPhones, or if Apple Intelligence is turned off or doesn't support your language, you still get the full transcript, and summaries need Apple Intelligence. Need more? Cloud mode adds server-side processing, cross-device sync and the web app, paid with Minutes.

## Where this applies

- App Store subtitle / promotional text: use the one-line claim.
- App Store description: use the snippet above (keep the "summaries need Apple Intelligence" sentence).
- Screenshots: any screenshot showing a summary should come from an Apple Intelligence device; do not imply summaries on every device.
- Website and onboarding: same qualifier.

## In-app copy used (transcript-only state)

Shown on the meeting detail screen instead of the Overview and Summary sections, as a neutral notice (no error alert, no red state). The meeting is marked completed and the transcript is shown below it. In the meetings list the row reads "Transcript only" when it has no other preview.

| Reason | Title | Message |
| --- | --- | --- |
| Device not eligible | Summaries need Apple Intelligence | This device doesn't support Apple Intelligence, so SnipNote can't write a summary here. Your transcript is saved and free. |
| Apple Intelligence off in Settings | Summaries need Apple Intelligence | Apple Intelligence is turned off. Turn it on in Settings > Apple Intelligence & Siri to get summaries. Your transcript is saved. |
| Unsupported language | Summaries need Apple Intelligence | Apple Intelligence doesn't support this meeting's language yet, so SnipNote can't write a summary. Your transcript is saved. |
| Model still downloading | Apple Intelligence is getting ready | Apple Intelligence is still getting ready on this device and may be downloading. Your transcript is saved. Try again in a little while. |
| iOS older than 26 | Summaries need Apple Intelligence | Apple Intelligence requires iOS 26 or later. Update iOS to get summaries. Your transcript is saved. |
| Other / unknown | Summaries need Apple Intelligence | Summaries aren't available on this device right now. Your transcript is saved. |

A "Try again" button appears for every reason except "device not eligible" and "unsupported language" (nothing the user can change). It re-runs the analysis on the saved transcript.

Notification on completion (instead of "...transcript and AI summary"): "'<meeting name>' is ready with its transcript".

## Behavior guarantees

- Cloud analysis is never used as a fallback when Apple Intelligence is unavailable.
- Local mode never spends Minutes. A transcript-only meeting settles the debit flag without a debit.
- Strings are currently English literals in code; localize them when the rest of the analysis copy is localized.
