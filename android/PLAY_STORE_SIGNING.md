# Play Store upload signing (FirstSign)

Safe local setup for a **Play Console upload key**. Secrets stay on your machine only.

| Item | Location | In git? |
|------|----------|---------|
| Template | `android/key.properties.example` | Yes |
| Real passwords | `android/key.properties` | **No** (gitignored) |
| Upload keystore | `android/upload-keystore.jks` | **No** (gitignored) |
| Gradle wiring | `android/app/build.gradle.kts` | Yes (reads `key.properties` when present) |

**App id:** `com.pillarai.app`  
**Recommended alias:** `upload`

---

## 1. Prerequisites

- JDK with `keytool` (Android Studio’s JBR is fine)
- Flutter project root: `flutter_application_1`
- PowerShell (Windows) or bash (macOS/Linux)

Confirm `keytool` exists:

```powershell
keytool -help
```

If not found, open Android Studio → set `JAVA_HOME` to the bundled JBR, or add that `bin` folder to `PATH`.

---

## 2. Generate the upload keystore (recommended)

### Windows (PowerShell)

From the **Flutter project root**:

```powershell
cd android
powershell -ExecutionPolicy Bypass -File .\scripts\create_upload_keystore.ps1
```

### macOS / Linux

```bash
cd android
chmod +x scripts/create_upload_keystore.sh
./scripts/create_upload_keystore.sh
```

The script:

1. Creates `android/upload-keystore.jks` (alias `upload`, RSA 2048, ~10 000 days)
2. Writes `android/key.properties` with the correct `storeFile=../upload-keystore.jks`
3. Never commits or logs passwords

**Back up** the `.jks` file and both passwords offline. Losing them can block updates.

---

## 3. Manual keytool (optional)

From the **`android/`** folder:

### Windows (cmd)

```bat
keytool -genkeypair -v ^
  -keystore upload-keystore.jks ^
  -storetype JKS ^
  -keyalg RSA -keysize 2048 -validity 10000 ^
  -alias upload
```

### PowerShell / bash

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Then create `android/key.properties` from the example:

```powershell
# Windows
copy key.properties.example key.properties
# Edit key.properties — set storePassword, keyPassword (and keep keyAlias/storeFile)
notepad key.properties
```

```bash
# macOS / Linux
cp key.properties.example key.properties
# Edit storePassword and keyPassword only
```

`key.properties` must look like this (paths relative to **`android/app/`**):

```properties
storePassword=***your-store-password***
keyPassword=***your-key-password***
keyAlias=upload
storeFile=../upload-keystore.jks
```

Do **not** put real passwords in `key.properties.example` or any committed file.

---

## 4. Confirm secrets are ignored

```bash
git check-ignore -v android/key.properties android/upload-keystore.jks
```

You should see ignore rules (root `.gitignore` and/or `android/.gitignore`).  
`git status` must **not** list either file as new/modified for commit.

---

## 5. Gradle release signing (already configured)

`android/app/build.gradle.kts` already:

- Loads `android/key.properties` when it exists
- Creates a `release` signing config from `keyAlias`, `keyPassword`, `storeFile`, `storePassword`
- Uses that config for the `release` build type
- Falls back to the **debug** keystore if `key.properties` is missing (local sideload only — **not** for Play)

No change required for a normal setup.

---

## 6. Build a signed Play upload

From the **Flutter project root**:

```bash
flutter pub get
flutter build appbundle --release
```

Output:

```text
build/app/outputs/bundle/release/app-release.aab
```

Optional APK (not required for Play if you use App Bundles):

```bash
flutter build apk --release
```

---

## 7. Play Console checklist

1. Create the app (or open existing) → **Production** / testing track → **Create new release**
2. Upload `app-release.aab`
3. Accept **Play App Signing** (recommended): Google holds the app signing key; you keep the **upload** key (`upload-keystore.jks`)
4. Complete store listing, content rating, privacy policy, data safety, etc.
5. Ship to internal testing first, then promote

---

## 8. Safety rules

| Do | Don’t |
|----|--------|
| Keep `key.properties` + `*.jks` gitignored | Commit passwords or keystores |
| Back up keystore + passwords offline | Rely only on one laptop disk |
| Use alias `upload` (matches example) | Re-generate a new keystore after Play enrollment without a key reset process |
| Build with `--release` after `key.properties` exists | Upload a debug-signed AAB to production |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Release still debug-signed | Ensure `android/key.properties` exists and `storeFile` points at a real `.jks` under `android/` |
| `keytool` not found | Install JDK / Android Studio; set `JAVA_HOME` |
| `storeFile` not found | Path is relative to `android/app/` → use `../upload-keystore.jks` |
| Wrong package | Confirm `applicationId` is `com.pillarai.app` in `app/build.gradle.kts` |
