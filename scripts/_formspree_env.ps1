# Shared helpers for Formspree + Vision dart-define scripts.
# Dot-source from other scripts: . "$PSScriptRoot\_formspree_env.ps1"

function Get-FirstSignRoot {
  return (Split-Path -Parent $PSScriptRoot)
}

function Get-FormspreeEnvPath {
  return (Join-Path (Get-FirstSignRoot) "formspree.env.json")
}

function Assert-FormspreeEnvFile {
  $envFile = Get-FormspreeEnvPath
  $example = Join-Path (Get-FirstSignRoot) "formspree.env.example.json"
  if (-not (Test-Path $envFile)) {
    Write-Host ""
    Write-Host "Missing formspree.env.json" -ForegroundColor Yellow
    if (Test-Path $example) {
      Write-Host "Copy the example and fill in Formspree + Vision values:" -ForegroundColor Cyan
      Write-Host "  copy formspree.env.example.json formspree.env.json"
    }
    Write-Host ""
    exit 1
  }
  $raw = Get-Content $envFile -Raw
  if ($raw -match "YOUR_FORM_ID" -or $raw -match "xxxxxxxx") {
    Write-Host ""
    Write-Host "formspree.env.json still has a placeholder form id." -ForegroundColor Yellow
    Write-Host "Paste real Formspree endpoints, then re-run." -ForegroundColor Cyan
    Write-Host ""
    exit 1
  }
  return $envFile
}

function Get-FormspreeEnvStatus {
  param([string]$EnvFile)
  $raw = Get-Content $EnvFile -Raw
  $hasVision = $false
  if ($raw -match '"GOOGLE_VISION_API_KEY"\s*:\s*"([^"]*)"') {
    $key = $Matches[1].Trim()
    if ($key.Length -gt 8 -and $key -notmatch "your_key") {
      $hasVision = $true
    }
  }
  $hasConfirm = $false
  if ($raw -match '"FORMSPREE_CONFIRM_ENDPOINT"\s*:\s*"([^"]*)"') {
    $c = $Matches[1].Trim()
    if ($c.Length -gt 10 -and $c -notmatch "YOUR_FORM") {
      $hasConfirm = $true
    }
  }
  $hasInvitee = $false
  if ($raw -match '"FORMSPREE_CONTRACTOR_NOTIFY_ENDPOINT"\s*:\s*"([^"]*)"') {
    $n = $Matches[1].Trim()
    if ($n.Length -gt 10 -and $n -notmatch "YOUR_FORM") {
      $hasInvitee = $true
    }
  }
  return @{
    HasVision  = $hasVision
    HasConfirm = $hasConfirm
    HasInvitee = $hasInvitee
  }
}

function Write-FormspreeEnvStatus {
  param([string]$EnvFile)
  $st = Get-FormspreeEnvStatus -EnvFile $EnvFile
  Write-Host "  Formspree quote email: on" -ForegroundColor DarkGray
  if ($st.HasConfirm) {
    Write-Host "  Homeowner confirm:     on (dedicated form)" -ForegroundColor DarkGray
  } else {
    Write-Host "  Homeowner confirm:     primary form fallback" -ForegroundColor DarkGray
  }
  if ($st.HasInvitee) {
    Write-Host "  Invitee lead notify:   on (dedicated form)" -ForegroundColor DarkGray
  } else {
    Write-Host "  Invitee lead notify:   primary form fallback" -ForegroundColor DarkGray
  }
  if ($st.HasVision) {
    Write-Host "  Google Cloud Vision:   on" -ForegroundColor DarkGray
  } else {
    Write-Host "  Google Cloud Vision:   off (local pipeline)" -ForegroundColor DarkGray
  }
}
