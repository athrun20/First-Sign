# Run First Sign on a connected Android device with Formspree + Vision.
# Requires formspree.env.json (see formspree.env.example.json and docs/).
#
# Phone setup:
#   USB debugging on · accept RSA prompt · flutter devices shows the phone
#
# Docs: docs/ANDROID_RELEASE.md · docs/QUOTE_EMAIL_SETUP.md · docs/VISION_API_SETUP.md

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_formspree_env.ps1"
$root = Get-FirstSignRoot
Set-Location $root

$envFile = Assert-FormspreeEnvFile

Write-Host "Checking for Android devices..." -ForegroundColor Cyan
$devicesOut = flutter devices 2>&1 | Out-String
if ($devicesOut -notmatch "android|Android") {
  Write-Host ""
  Write-Host "No Android device detected." -ForegroundColor Yellow
  Write-Host "1) Plug in the phone (USB debugging on) or start an emulator" -ForegroundColor Cyan
  Write-Host "2) flutter devices   # confirm a device appears" -ForegroundColor Cyan
  Write-Host "3) Re-run: .\scripts\run_android_with_quote.ps1" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "To build an installable APK without a device:" -ForegroundColor DarkGray
  Write-Host "  .\scripts\build_android_release.ps1 -Apk" -ForegroundColor DarkGray
  Write-Host ""
  exit 1
}

Write-Host "Starting First Sign on Android with formspree.env.json ..." -ForegroundColor Green
Write-FormspreeEnvStatus -EnvFile $envFile

flutter run -d android --dart-define-from-file=formspree.env.json
