# Google Cloud Vision setup (FirstSign)

When a key is present at build/run time, analysis uses **Google Cloud Vision**
(label + object + color) fused with the local multi-feature pipeline.  
Without a key — or if Vision fails — the app falls back cleanly to **local-only**.

## 1. Create a Google Cloud project + enable Vision

1. Open [Google Cloud Console](https://console.cloud.google.com/).
2. Create or select a project (e.g. `firstsign`).
3. **APIs & Services → Library** → search **Cloud Vision API** → **Enable**.
4. **APIs & Services → Credentials → Create credentials → API key**.
5. Copy the key (starts with `AIza…`).

### Restrict the key (strongly recommended)

In **Credentials → your key → Edit**:

| Platform | Restriction |
|----------|-------------|
| **Android** | Application restriction → Android apps · package `com.pillarai.app` + SHA-1 |
| **Web (Edge/Chrome)** | HTTP referrers · e.g. `http://localhost:*/*` for debug |
| **API restriction** | Restrict key → **Cloud Vision API** only |

Billing must be enabled on the project (Vision has a free monthly quota, then paid).

> **Security note:** Flutter web embeds dart-defines in the client bundle.  
> Always use **API restrictions** (Vision only) and referrer/package limits.  
> Prefer Android / Windows for production Vision; web is fine for dev with a restricted key.

## 2. Add the key to local config

`formspree.env.json` is gitignored and already holds Formspree endpoints.

```json
{
  "FORMSPREE_ENDPOINT": "https://formspree.io/f/xwvgavzj",
  "FORMSPREE_CONFIRM_ENDPOINT": "https://formspree.io/f/mzdnoqnl",
  "FORMSPREE_CONTRACTOR_NOTIFY_ENDPOINT": "https://formspree.io/f/mdaqrbln",
  "QUOTE_TEAM_EMAIL": "sanchezj24@live.com",
  "GOOGLE_VISION_API_KEY": "AIza...your_key..."
}
```

Or one-off:

```powershell
flutter run -d windows --dart-define=GOOGLE_VISION_API_KEY=AIza...
# also accepted: GCV_API_KEY, VISION_API_KEY
```

## 3. Run with Formspree + Vision

```powershell
.\scripts\run_edge_with_quote.ps1
# Android phone (Formspree + Vision):
.\scripts\run_android_with_quote.ps1
# Android release APK / Play AAB:
.\scripts\build_android_release.ps1 -Apk
.\scripts\build_android_release.ps1
# Windows desktop (reliable Vision client):
flutter run -d windows --dart-define-from-file=formspree.env.json
```

Full Android ship path: **[ANDROID_RELEASE.md](ANDROID_RELEASE.md)**.

Hot restart **does not** inject new defines — full restart required after editing the env file.

## 4. How to tell Vision is on

| Signal | Where |
|--------|--------|
| Analyzing copy | Photo review: “Sending to Google Cloud Vision” |
| Report badge | Source line mentions **Google Cloud Vision** |
| Fallback | Source says **Local multi-feature · Vision unavailable** |

Demo Mode and calibration still use local features when forced offline.

## 5. Web (Edge) CORS note

The Vision REST API is called **from the client**. Some browsers block the
request (CORS). If that happens, FirstSign **falls back to local** automatically.

For a reliable Vision pass during development:

- Use **Windows** or **Android** targets, or  
- Accept local fallback on Edge and still validate Formspree / UX there.

## 6. Troubleshooting

| Symptom | Fix |
|--------|-----|
| Still local pipeline | Rebuild with `--dart-define-from-file=formspree.env.json` and a non-empty key |
| HTTP 403 | Enable Cloud Vision API; check key restrictions / billing |
| HTTP 400 | Key malformed; strip quotes; re-copy from Console |
| Quota exceeded | Check Vision quotas in Cloud Console |
| Web only fails | CORS — try Windows/Android; local fallback is expected |

## Privacy

When Vision is configured, photos for that analysis pass may be sent to Google.
See in-app **Privacy & data** (`lib/legal/privacy_copy.dart`). Photos are not
uploaded with Formspree quote email.
