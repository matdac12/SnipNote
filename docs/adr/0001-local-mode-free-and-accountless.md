---
status: accepted
---

# Local mode is free forever and needs no account

Local mode (on-device Parakeet transcription and Apple Intelligence analysis) is never limited, capped or paywalled, and works as a Guest with no Account. An Account (email and password) is created only when the user first enters Cloud mode, because only Cloud mode needs an identity for Minutes, purchases and server jobs. Only Cloud mode and clearly extra features may be paid.

We chose this over keeping a login wall so that "free" can be marketed honestly, with no email asked before the first recording. Cloud was the only product for months and earned almost nothing, so the free product is the growth bet.

## Considered Options

- **Anonymous Supabase user at Cloud entry, email only at purchase:** less friction, but a reinstall loses the Minutes balance and allows repeated Trial grants. Rejected in favour of requiring email at Cloud entry.
- **Free tier with caps on Local mode:** rejected, it breaks the promise the marketing relies on.

## Consequences

- A Guest writes nothing to Supabase, so usage is measured with anonymous events (own events table), not accounts. Signed-in users' Local meetings currently still sync their text to Supabase; whether that stays free is a separate decision.
- Cross-device sync, the web app and speaker labels are Pro extras, not part of the free-forever promise. Existing Accounts keep sync and web access for a grace period before gating starts.
- Turning a Guest into an Account must not delete the Guest's local meetings: the current pull-sync deletes local meetings missing from the server, so local meetings must be pushed first or the deletion rule changed.
- On devices without Apple Intelligence, Local mode gives a transcript only; summaries need Apple Intelligence. Marketing must say so.
- Supersedes the earlier assumption that every user signs in at launch.
