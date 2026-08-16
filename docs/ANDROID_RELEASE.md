# First Sign Android — Formspree + Vision (debug & release)

Compile-time secrets live in gitignored **`formspree.env.json`** (same file as desktop/web).

| Key | Purpose |
|-----|---------|
| `FORMSPREE_ENDPOINT` | Team quote form |
| `FORMSPREE_CONFIRM_ENDPOINT` | Homeowner confirmation form |
| `QUOTE_TEAM_EMAIL` | Metadata / reply context |
| `GOOGLE_VISION_API_KEY` | Cloud Vision (optional; local fallback if empty/fail) |

Hot reload / hot restart **does not** inject new defines — full `run` or `build` required after edits.

---

## 1. Dev run on a phone

1. USB debugging on · accept RSA prompt  
2. `flutter devices` shows an Android device  
3. From project root:

```powershell
.\scripts\run_android_with_quote.ps1
```

Equivalent:

```powershell
flutter run -d android --dart-define-from-file=formspree.env.json
```

### How to verify on device

| Feature | Check |
|---------|--------|
| **Formspree** | Request a quote → “Request sent” · Formspree Submissions |
| **Vision** | Analyze photos → “Sending to Google Cloud Vision” · report source mentions Cloud Vision |
| **Local fallback** | No key / network fail → local multi-feature still works |

---

## 2. Release APK (sideload / internal test)

Preferred (reads gitignored `formspree.env.json` — do **not** hard-code the Vision key):

```powershell
.\scripts\build_android_release.ps1 -Apk
# → build\app\outputs\flutter-apk\app-release.apk
```

Equivalent one-liner:

```powershell
flutter build apk --release --dart-define-from-file=formspree.env.json
```

Or pass defines explicitly (replace the Vision key; never commit it):

```powershell
flutter build apk --release --dart-define=GOOGLE_VISION_API_KEY=YOUR_KEY --dart-define=FORMSPREE_ENDPOINT=https://formspree.io/f/xwvgavzj
```

Install:

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
# or: flutter install
```

Smaller per-ABI APKs:

```powershell
.\scripts\build_android_release.ps1 -Apk -Split
```

---

## 3. Play Store App Bundle (AAB)

### Signing (once)

```powershell
cd android
powershell -ExecutionPolicy Bypass -File .\scripts\create_upload_keystore.ps1
cd ..
```

Details: [`android/PLAY_STORE_SIGNING.md`](../android/PLAY_STORE_SIGNING.md).  
Never commit `key.properties` or `*.jks`.

### Build

```powershell
.\scripts\build_android_release.ps1
# → build\app\outputs\bundle\release\app-release.aab
```

Upload the AAB in Play Console (Internal testing recommended first).

---

## 4. Vision key security on Android

Release APKs embed dart-defines in the binary. Restrict the key in Google Cloud:

1. **API restrictions** → Cloud Vision API only  
2. **Application restrictions** → Android apps  
   - Package: `com.pillarai.app`  
   - SHA-1 from your upload/debug keystore  

```powershell
# Debug SHA-1 (typical for sideload/debug installs)
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android

# Upload keystore SHA-1 (Play release)
keytool -list -v -keystore android\upload-keystore.jks -alias upload
```

---

## 5. Troubleshooting

| Symptom | Fix |
|--------|-----|
| No Android device | Plug in phone / start emulator · `flutter devices` |
| Quote still “save lead only” | Rebuild with `--dart-define-from-file=formspree.env.json` |
| Always local analysis | Confirm `GOOGLE_VISION_API_KEY` non-empty; enable Vision API + billing |
| HTTP 403 Vision | Key restrictions / package SHA-1 / API not enabled |
| Unsigned / debug AAB | Create `key.properties` + keystore before release build |

---

## 6. Related docs

- [`QUOTE_EMAIL_SETUP.md`](QUOTE_EMAIL_SETUP.md)  
- [`VISION_API_SETUP.md`](VISION_API_SETUP.md)  
- [`android/PLAY_STORE_SIGNING.md`](../android/PLAY_STORE_SIGNING.md)  
