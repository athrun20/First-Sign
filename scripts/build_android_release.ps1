# Build First Sign Android release with Formspree + Vision dart-defines.
#
# Usage (from project root):
#   .\scripts\build_android_release.ps1              # AAB (Play Store)
#   .\scripts\build_android_release.ps1 -Apk         # universal release APK
#   .\scripts\build_android_release.ps1 -Apk -Split  # per-ABI APKs
#
# Requires formspree.env.json. For Play upload signing, also need
# android/key.properties + upload-keystore.jks (see android/PLAY_STORE_SIGNING.md).
#
# Docs: docs/ANDROID_RELEASE.md

param(
  [switch]$Apk,
  [switch]$Split
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_formspree_env.ps1"
$root = Get-FirstSignRoot
Set-Location $root

$envFile = Assert-FormspreeEnvFile

Write-Host ""
Write-Host "First Sign Android release build" -ForegroundColor Green
Write-FormspreeEnvStatus -EnvFile $envFile

$keyProps = Join-Path $root "android\key.properties"
$keystore = Join-Path $root "android\upload-keystore.jks"
if (-not (Test-Path $keyProps) -or -not (Test-Path $keystore)) {
  Write-Host ""
  Write-Host "Note: upload signing files missing - build may use debug signing." -ForegroundColor Yellow
  Write-Host "For Play Store: android/PLAY_STORE_SIGNING.md" -ForegroundColor Cyan
  Write-Host "  cd android; powershell -ExecutionPolicy Bypass -File .\scripts\create_upload_keystore.ps1" -ForegroundColor DarkGray
  Write-Host ""
} else {
  Write-Host "  Upload signing:        key.properties present" -ForegroundColor DarkGray
}

if ($Apk) {
  Write-Host ""
  Write-Host "Building release APK..." -ForegroundColor Cyan
  if ($Split) {
    flutter build apk --release --split-per-abi --dart-define-from-file=formspree.env.json
    Write-Host ""
    Write-Host "APKs:" -ForegroundColor Green
    Get-ChildItem -Path "build\app\outputs\flutter-apk\*-release.apk" -ErrorAction SilentlyContinue |
      ForEach-Object { Write-Host ("  " + $_.FullName) }
  } else {
    flutter build apk --release --dart-define-from-file=formspree.env.json
    $apkPath = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
    Write-Host ""
    if (Test-Path $apkPath) {
      Write-Host "APK ready:" -ForegroundColor Green
      Write-Host ("  " + $apkPath)
      Write-Host ""
      Write-Host "Install on a phone:" -ForegroundColor Cyan
      Write-Host ("  adb install -r `"" + $apkPath + "`"")
    } else {
      Write-Host "Build finished - check build\app\outputs\flutter-apk\" -ForegroundColor Yellow
    }
  }
} else {
  Write-Host ""
  Write-Host "Building release App Bundle (AAB) for Play Console..." -ForegroundColor Cyan
  flutter build appbundle --release --dart-define-from-file=formspree.env.json
  $aabPath = Join-Path $root "build\app\outputs\bundle\release\app-release.aab"
  Write-Host ""
  if (Test-Path $aabPath) {
    Write-Host "AAB ready:" -ForegroundColor Green
    Write-Host ("  " + $aabPath)
    Write-Host ""
    Write-Host "Upload this file in Play Console (Production or Internal testing)." -ForegroundColor Cyan
  } else {
    Write-Host "Build finished - check build\app\outputs\bundle\release\" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "Important: dart-defines are compile-time. Rebuild after editing formspree.env.json." -ForegroundColor DarkGray
Write-Host "Restrict GOOGLE_VISION_API_KEY in Cloud Console (Vision API only + Android package)." -ForegroundColor DarkGray
Write-Host ""
