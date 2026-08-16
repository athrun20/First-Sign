# Run First Sign on Edge with Formspree quote email (+ optional Vision key).
# 1) copy formspree.env.example.json formspree.env.json
# 2) paste form URLs; optional GOOGLE_VISION_API_KEY
# 3) .\scripts\run_edge_with_quote.ps1
#
# Docs: docs/QUOTE_EMAIL_SETUP.md · docs/VISION_API_SETUP.md

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$envFile = Join-Path $root "formspree.env.json"
$example = Join-Path $root "formspree.env.example.json"

if (-not (Test-Path $envFile)) {
  Write-Host ""
  Write-Host "Missing formspree.env.json" -ForegroundColor Yellow
  Write-Host "Creating from example..."
  if (-not (Test-Path $example)) {
    throw "formspree.env.example.json not found at $example"
  }
  Copy-Item $example $envFile
  Write-Host ""
  Write-Host "Edit formspree.env.json and set FORMSPREE_ENDPOINT to your Formspree form URL," -ForegroundColor Cyan
  Write-Host "then re-run this script. (https://formspree.io → New form → copy endpoint)" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  notepad formspree.env.json"
  Write-Host ""
  exit 1
}

$raw = Get-Content $envFile -Raw
if ($raw -match "YOUR_FORM_ID" -or $raw -match "xxxxxxxx") {
  Write-Host ""
  Write-Host "formspree.env.json still has a placeholder form id." -ForegroundColor Yellow
  Write-Host "Paste your real endpoint from formspree.io, then re-run." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "  notepad formspree.env.json"
  Write-Host ""
  exit 1
}

$hasVision = $false
if ($raw -match '"GOOGLE_VISION_API_KEY"\s*:\s*"([^"]*)"') {
  $key = $Matches[1].Trim()
  if ($key.Length -gt 8 -and $key -notmatch "your_key") {
    $hasVision = $true
  }
}

Write-Host "Starting First Sign on Edge with formspree.env.json ..." -ForegroundColor Green
Write-Host "  Formspree quote email: on" -ForegroundColor DarkGray
if ($hasVision) {
  Write-Host "  Google Cloud Vision:   on (web may CORS-fallback to local)" -ForegroundColor DarkGray
} else {
  Write-Host "  Google Cloud Vision:   off (local pipeline) - see docs/VISION_API_SETUP.md" -ForegroundColor DarkGray
}

flutter run -d edge --dart-define-from-file=formspree.env.json
