# FirstSign

AI-assisted **home exterior screening** for homeowners — guided photos, findings story, digital twin, surface-evidence detail, shareable PDF, Formspree quote email, and on-device contractor lead tools.

> Photo screening · not a licensed inspection. Confirm findings on-site before major repairs.

## Features

- **Guided capture** with Smart Capture Assistant tips and quality checks  
- **On-device multi-feature analysis** (optional Google Cloud Vision when a key is provided)  
- **Story report** — condition → priority → recommendations → impact  
- **Digital twin** + **surface evidence** finding detail (exterior photo clues — not wall-penetrating imaging)  
- **Fix this finding** — retake the best guided shot for a finding, re-run screening, see score/severity change  
- **Share / download PDF** (branding logo supported)  
- **Demo Mode** — sample home walkthrough without a camera  
- **Report history**, resume incomplete capture, score history  
- **Local contractor tools** — leads, notes, branding  
- **Hardened storage** — photo blobs in Hive (IndexedDB on web), not base64 in SharedPreferences  

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) stable (this project targets Dart `^3.12`)  
- Chrome/Edge for web, or Windows/macOS/Android/iOS toolchains as needed  

## Run

```bash
flutter pub get
flutter run -d edge          # or chrome
flutter run -d windows
flutter run -d android       # physical phone or emulator
```

### Android phone (dev install)

1. **Install Android Studio** (includes SDK + platform-tools).  
   First launch: install Android SDK, Android SDK Platform (API 34+), and accept licenses.
2. Point Flutter at the SDK if needed:
   ```bash
   flutter config --android-sdk %LOCALAPPDATA%\Android\Sdk
   flutter doctor --android-licenses
   flutter doctor
   ```
3. On the phone: **Settings → About phone → tap Build number 7×** → enable **Developer options → USB debugging**.  
   Plug in USB (or use wireless debugging). Accept the RSA prompt on the phone.
4. Confirm the device:
   ```bash
   flutter devices
   # expect something like: SM-… • R58… • android-arm64
   ```
5. Run with Formspree + Vision (requires `formspree.env.json`):
   ```powershell
   flutter pub get
   .\scripts\run_android_with_quote.ps1
   # or: flutter run -d android --dart-define-from-file=formspree.env.json
   ```
6. Release APK / Play AAB (same env file):
   ```powershell
   .\scripts\build_android_release.ps1 -Apk    # sideload APK
   .\scripts\build_android_release.ps1         # Play Store AAB
   ```

Full Android release guide: **[`docs/ANDROID_RELEASE.md`](docs/ANDROID_RELEASE.md)**.  
**App id:** `com.pillarai.app` · **Permissions:** camera, internet, legacy storage (≤ API 32).

### Play Store release signing (Android)

Upload keystore setup (secrets stay local — never commit `key.properties` or `*.jks`):

```powershell
# Windows — from project root
cd android
powershell -ExecutionPolicy Bypass -File .\scripts\create_upload_keystore.ps1
cd ..
.\scripts\build_android_release.ps1
# → build/app/outputs/bundle/release/app-release.aab
```

Full steps, manual `keytool`, and safety checklist: [`android/PLAY_STORE_SIGNING.md`](android/PLAY_STORE_SIGNING.md). Template: [`android/key.properties.example`](android/key.properties.example).

### Optional: Google Cloud Vision (primary when configured)

Full setup: **[`docs/VISION_API_SETUP.md`](docs/VISION_API_SETUP.md)**.

```powershell
# 1) Enable Cloud Vision API + create an API key in Google Cloud Console
# 2) Paste into formspree.env.json:
#    "GOOGLE_VISION_API_KEY": "AIza..."
# 3) Run (Windows is most reliable for Vision; Edge may CORS-fallback):
.\scripts\run_windows_with_vision.ps1
# or same file on Edge / Android:
.\scripts\run_edge_with_quote.ps1
```

Also accepted: `--dart-define=GOOGLE_VISION_API_KEY=...` / `GCV_API_KEY` / `VISION_API_KEY`.

When a key is present, analysis uses **Google Cloud Vision** (label + object + color cues) fused with local image features.  
Without a key — or if the Vision request fails — the app falls back cleanly to the **local multi-feature** pipeline (demo/offline still work).

### Optional: Formspree quote email

**Request a quote** posts contact + report summary to Formspree (default team inbox: `sanchezj24@live.com`). Full setup: **[`docs/QUOTE_EMAIL_SETUP.md`](docs/QUOTE_EMAIL_SETUP.md)**.

```powershell
# 1) Create a form at https://formspree.io (notification → your team email)
# 2) Local config (gitignored):
copy formspree.env.example.json formspree.env.json
# 3) Paste FORMSPREE_ENDPOINT, then:
.\scripts\run_edge_with_quote.ps1
```

Without Formspree, the app still **saves a local contractor lead** and you can share a PDF.

Fields sent (team): full name, phone, email, property address, report score, top findings, planning range (plus preferred contact time and notes).  
Leads are **also** saved on-device for contractor tools even if email delivery fails.

## Demo Mode

On the home screen, tap **Try sample home (demo)**.  
FirstSign paints sample elevations, runs the calibrated screening engine, saves a report, and opens the full UI (twin, surface evidence, PDF).

## Tests & quality

```bash
flutter analyze
flutter test
flutter test test/photo_calibration_test.dart   # pixel-pipeline calibration
flutter build web --release
```

### Real-photo calibration

Painted fixtures exercise the full decode → features → scoring path.  
To calibrate on **real house photos**, see `assets/calibration/README.md`.

CI runs analyze, test, and web build (see `.github/workflows/ci.yml`).

## Privacy (local-first)

- Photos and reports stay **on this device** by default  
- Profile fields autofill quotes; shared only when you submit a quote  
- **Request a quote** emails contact details + a report summary via **Formspree** to the configured inbox, attempts a short **homeowner confirmation** email, and also saves a **local** contractor lead on this device  
- Shared PDFs leave the device when you export them  
- Optional Vision API (only if you pass a key) may send images to Google for that analysis  
- Screening tool only — not a licensed inspection  

In the app: **Profile → Privacy & data**, or open route `/privacy`. Canonical strings live in `lib/legal/privacy_copy.dart`.

## Project layout

```
lib/
  main.dart                 # App shell + routes
  legal/privacy_copy.dart   # Privacy strings
  models/                   # Analysis, capture, leads, saved reports
  screens/                  # Home, capture, report, demo, contractor, …
  services/                 # Analysis, stores, PDF, blob storage
  widgets/                  # Twin, surface evidence sheet, capture assistant
  theme/
```

Package name: **`pillar_ai`**  
Android / iOS application id: **`com.pillarai.app`**

## Storage notes

| Data | Storage |
|------|---------|
| Photo / logo bytes | Hive blob box (`pillar_blobs_v2`) → IndexedDB on web |
| Report / lead / draft metadata | SharedPreferences (small JSON) |
| Soft blob budget | ~28 MB web · ~120 MB desktop |

If storage is full, the app prompts you to delete older reports.

## License

Private / unpublished (`publish_to: none`). All rights reserved unless otherwise noted.
