# Run FirstSign on Windows desktop with Formspree + optional Vision.
# Windows is the most reliable desktop target for Google Cloud Vision
# (Edge/web can hit CORS and fall back to local).
#
# Docs: docs/VISION_API_SETUP.md · docs/QUOTE_EMAIL_SETUP.md

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$envFile = Join-Path $root "formspree.env.json"
if (-not (Test-Path $envFile)) {
  Write-Host "Missing formspree.env.json - copy formspree.env.example.json first." -ForegroundColor Yellow
  exit 1
}

$raw = Get-Content $envFile -Raw
$hasVision = $false
if ($raw -match '"GOOGLE_VISION_API_KEY"\s*:\s*"([^"]*)"') {
  $key = $Matches[1].Trim()
  if ($key.Length -gt 8 -and $key -notmatch "your_key") {
    $hasVision = $true
  }
}

if (-not $hasVision) {
  Write-Host ""
  Write-Host "GOOGLE_VISION_API_KEY is empty in formspree.env.json." -ForegroundColor Yellow
  Write-Host "Paste your key from Google Cloud Console, then re-run." -ForegroundColor Cyan
  Write-Host "See docs/VISION_API_SETUP.md" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  notepad formspree.env.json"
  Write-Host ""
  exit 1
}

Write-Host "Starting FirstSign on Windows with Formspree + Cloud Vision ..." -ForegroundColor Green
flutter run -d windows --dart-define-from-file=formspree.env.json
