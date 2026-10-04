# Anonymous usage analytics: App Privacy label and privacy policy wording (draft)

Draft for MAT-1660. Nothing here is published yet. The website repo is not touched; copy the policy text over when approved.

What the app actually sends, so the wording below stays honest:

- Event name from a fixed list (app opened, Local recording started, Local transcript completed, analysis unavailable, Cloud trial prompt shown, Cloud trial claimed, paywall viewed, purchase completed).
- A random install ID generated on the device. It is not an Account ID, not derived from one, not the advertising ID and not the vendor ID. It is deleted when the user turns analytics off, and replaced by a new one if they turn it on again. Deleting the app also loses it.
- App version (for example "2.9"), a coarse OS bucket (for example "ios17"), and the time of the event (set by the server).
- A few enum or bucket properties: audio length bucket ("5 to 15 minutes"), why analysis was unavailable (device / setting / language), which screen opened a paywall, and which pack or subscription was bought.
- Never sent: email, Account ID, meeting names, transcripts, audio, audio-derived content, exact durations, device model, IP address stored with the event, or any Apple identifier.
- Events are sent with the public API key and no user token, so a Guest and a signed-in user look the same to the server.
- On by default, off with Settings > Share Anonymous Usage Data. When off, nothing is sent.

## App Store Connect: App Privacy answers

Add to the existing answers (Account email, purchases and so on stay as they are).

| Question | Answer |
| --- | --- |
| Data type | **Usage Data > Product Interaction** (which features are used, paywall views, purchases) |
| Collected | Yes |
| Linked to the user's identity | **No** (no Account, email or Apple ID is attached; the install ID is random and never joined to an Account) |
| Used to track the user | **No** (not shared with data brokers or other companies, not combined with third-party data, no advertising) |
| Purposes | **Analytics** only |

Decision for Mattia, the install ID: Apple's "Identifiers > Device ID" category is defined around device-level IDs such as the advertising ID. Ours is a random per-install value, so strictly it is not a device ID. The conservative choice is to also declare **Identifiers > Device ID**, collected, not linked to identity, not used for tracking, purpose Analytics. Declaring more than needed carries no penalty, declaring less than a reviewer expects can. Recommended: declare it.

Not needed: Diagnostics (no crash or performance data is sent), Location, Contacts, User Content (audio and transcripts are not part of analytics), Identifiers > User ID (the install ID is not a user ID).

## Privacy policy text (English)

> **Anonymous usage data**
>
> SnipNote collects anonymous usage data to understand which features are used and to fix problems, for example when you open the app, start a Local recording, or open a purchase screen. This data is tied to a random ID created on your device when you first use the app. It is not linked to your name, email, Account or Apple ID, and we cannot tell who you are from it.
>
> We record the type of event, your app version, your iOS version (for example "iOS 17"), and a few general details such as a length range for a recording ("5 to 15 minutes"). We never include your email, recordings, transcripts, meeting names or any content you create.
>
> We use this data only to improve SnipNote. We do not use it for advertising, we do not sell it, and we do not share it with other companies or combine it with data from other apps or websites to track you.
>
> You can turn this off at any time in Settings > Share Anonymous Usage Data. When it is off, SnipNote sends no usage data and deletes the random ID. This setting does not affect Cloud mode, which needs your Account to process your recordings when you choose it.
>
> We keep anonymous usage events for up to 400 days.

(The 400 days matches the default in `public.purge_analytics_events`, which the migration schedules nightly with `pg_cron`. If you change the retention, change both.)

## Privacy policy text (Italian)

> **Dati d'uso anonimi**
>
> SnipNote raccoglie dati d'uso anonimi per capire quali funzioni vengono usate e per correggere problemi, ad esempio quando apri l'app, avvii una registrazione in modalità Locale o apri una schermata di acquisto. Questi dati sono associati a un ID casuale creato sul tuo dispositivo al primo utilizzo. Non sono collegati al tuo nome, alla tua email, al tuo Account o al tuo Apple ID, e non permettono di sapere chi sei.
>
> Registriamo il tipo di evento, la versione dell'app, la versione di iOS (ad esempio "iOS 17") e alcuni dettagli generici come un intervallo di durata della registrazione ("da 5 a 15 minuti"). Non includiamo mai la tua email, le registrazioni, le trascrizioni, i nomi delle riunioni o altri contenuti che crei.
>
> Usiamo questi dati solo per migliorare SnipNote. Non li usiamo per la pubblicità, non li vendiamo e non li condividiamo con altre aziende né li combiniamo con dati di altre app o siti per tracciarti.
>
> Puoi disattivarli in qualsiasi momento in Impostazioni > Condividi dati d'uso anonimi. Quando sono disattivati, SnipNote non invia dati d'uso ed elimina l'ID casuale. Questa impostazione non riguarda la modalità Cloud, che richiede il tuo Account per elaborare le registrazioni quando la scegli.
>
> Conserviamo gli eventi d'uso anonimi per un massimo di 400 giorni.

## Notes

- Apple and Supabase infrastructure logs may briefly contain request IP addresses as part of normal hosting. The analytics table does not store them. If the policy already describes hosting logs, no extra sentence is needed.
- Marketing line that stays true: "No account, no tracking, no ads." Do not say "no data collected", because anonymous usage events are collected.
- Update this wording if events ever gain properties beyond enums and buckets, or if the install ID is ever joined to an Account.
