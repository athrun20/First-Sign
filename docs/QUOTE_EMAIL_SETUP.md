# First Sign quote email (Formspree) setup

When configured, **Request a quote** emails a screening summary to your team and can send a best-effort homeowner confirmation.

## 1. Create the contractor form (required)

1. Sign up / log in at [formspree.io](https://formspree.io).
2. **New form** → name it e.g. `First Sign quotes`.
3. Set the form **notification email** to your team inbox (default in app: `sanchezj24@live.com`).
4. Copy the endpoint, e.g. `https://formspree.io/f/xpwzgkqr`.
5. Under form settings, allow JSON submissions (default for modern Formspree).

## 2. Optional: homeowner confirmation form

1. Create a **second** form (keeps the contractor inbox clean).
2. Optionally enable **Autoresponse** (Formspree plan feature) so Formspree emails the submission `email` field.
3. Copy that endpoint for `FORMSPREE_CONFIRM_ENDPOINT`.
4. If omitted, the app reuses the primary form for a second “confirmation” POST (works, but adds an extra row in the same inbox).

## 2b. Optional: invitee (matched contractor) notify form

When a homeowner submits a quote, First Sign:

1. Emails the **team** form (unchanged).  
2. Saves a **local lead** (unchanged).  
3. Best-effort homeowner confirmation (unchanged).  
4. **NEW:** runs `matchContractors()` against the on-device invite network and POSTs one Formspree submission **per matching contractor** with a valid email.

Each invitee payload includes homeowner contact, score, condition, top findings, planning range, lead id, and a screening disclaimer. Delivery uses Formspree `_cc` + `email` (enable **CC** and/or **Autoresponse** on the form so the invitee receives mail).

1. Create a form e.g. `First Sign invitee leads` (recommended so team submissions stay separate).  
2. Copy the endpoint into `FORMSPREE_CONTRACTOR_NOTIFY_ENDPOINT` (First Sign: `https://formspree.io/f/mdaqrbln`).  
3. If omitted, invitee posts **reuse** `FORMSPREE_ENDPOINT` (extra rows in the team form — fine for early testing).  
4. Failures here **never** fail the homeowner quote.

Matching rules (same as `matchContractors`): active only, trade overlap with top findings, service area empty (national) or city/ZIP overlap with property address. No match → no extra email.

Add invitees in-app: **Pro tools → Invite network**.

## 3. Configure the app (local file — recommended)

```powershell
# From project root
copy formspree.env.example.json formspree.env.json
# Edit formspree.env.json — paste your real form URL(s)
```

`formspree.env.json` is gitignored. Never commit real form IDs if you treat them as private.

### Run (Edge)

```powershell
.\scripts\run_edge_with_quote.ps1
```

Or:

```powershell
flutter run -d edge --dart-define-from-file=formspree.env.json
```

### Run (Android)

```powershell
.\scripts\run_android_with_quote.ps1
# or:
flutter run -d android --dart-define-from-file=formspree.env.json
```

### Release AAB / APK (Formspree + Vision)

```powershell
.\scripts\build_android_release.ps1         # Play Store AAB
.\scripts\build_android_release.ps1 -Apk    # sideload APK
# or:
flutter build appbundle --release --dart-define-from-file=formspree.env.json
```

See **[ANDROID_RELEASE.md](ANDROID_RELEASE.md)** for signing, install, and Vision key restrictions.

### One-off flags (no file)

```powershell
flutter run -d edge `
  --dart-define=FORMSPREE_ENDPOINT=https://formspree.io/f/YOUR_FORM_ID `
  --dart-define=QUOTE_TEAM_EMAIL=sanchezj24@live.com
```

You can also pass a bare form id: `--dart-define=FORMSPREE_ENDPOINT=YOUR_FORM_ID`  
(the app expands it to `https://formspree.io/f/...`).

Optional Vision key in the same file: `"GOOGLE_VISION_API_KEY": "AIza..."` — see **[VISION_API_SETUP.md](VISION_API_SETUP.md)**.

## 4. What gets emailed

**Team form** receives:

- Name, phone, email, property address  
- Score, condition, planning range, top findings  
- Preferred contact window, notes, lead id  
- Subject: `First Sign quote request · score N · address`

**Homeowner confirmation** (if confirm endpoint posts successfully):

- Score, condition, planning range, top findings  
- Screening reminder  

**Matched invitee form** (best-effort, one POST per match with email):

- Homeowner name, phone, email, property address  
- Score, condition label, top findings, planning range  
- Lead id + short First Sign screening note  
- `_cc` / `email` set to the invitee’s email  

Photos are **not** uploaded with the quote email.

## 5. Verify

1. Run with `formspree.env.json` filled in.  
2. Complete a demo or real report → **Request a quote**.  
3. Submit — UI should say **Request sent** (not only “saved”).  
4. Check the Formspree form **Submissions** page and your team inbox.  
5. Confirm the homeowner address received a copy if you enabled autoresponse / `_cc`.  
6. Add a matching invitee under **Pro tools → Invite network** (trade + city/ZIP).  
7. Submit another quote — debug console should log `QuoteSubmit: invitee match` / `invitee notified`.  
8. Check Formspree **Submissions** on the invitee form (or primary if reusing it).

## 6. Without Formspree

The app still works: quote flow **saves a local contractor lead** and offers PDF share. Email is optional but required for automatic team notification.

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| Button still says “Save lead on this device” | Rebuild with `--dart-define-from-file=formspree.env.json` (hot restart does not inject new defines) |
| HTTP 403 / 422 | Activate the form, complete Formspree email verification, check form is not disabled |
| No email | Check spam; confirm Formspree notification email; open Submissions in dashboard |
| CORS on web | Formspree allows browser POSTs; ensure endpoint is `https://formspree.io/f/...` |
