#Requires -Version 5.1
<#
.SYNOPSIS
  Create a Play Store upload keystore + local android/key.properties for Pillar AI.

.DESCRIPTION
  - Generates android/upload-keystore.jks (gitignored).
  - Writes android/key.properties (gitignored) with paths that match Gradle.
  - Never prints or commits passwords.
  - Safe to re-run only if you first remove the existing keystore yourself.

  Run from anywhere:
    powershell -ExecutionPolicy Bypass -File android\scripts\create_upload_keystore.ps1
#>

$ErrorActionPreference = 'Stop'

$androidDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$keystorePath = Join-Path $androidDir 'upload-keystore.jks'
$keyPropsPath = Join-Path $androidDir 'key.properties'
$alias = 'upload'

function Find-Keytool {
  $cmd = Get-Command keytool -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $javaHome = $env:JAVA_HOME
  if ($javaHome) {
    $candidate = Join-Path $javaHome 'bin\keytool.exe'
    if (Test-Path $candidate) { return $candidate }
  }

  # Common Android Studio JBR locations on Windows
  $studioRoots = @(
    "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
    "${env:ProgramFiles(x86)}\Android\Android Studio\jbr\bin\keytool.exe",
    "$env:LOCALAPPDATA\Programs\Android\Android Studio\jbr\bin\keytool.exe"
  )
  foreach ($p in $studioRoots) {
    if (Test-Path $p) { return $p }
  }

  throw @'
keytool not found. Install a JDK or Android Studio, then either:
  • Add keytool to PATH, or
  • Set JAVA_HOME to a JDK that contains bin\keytool.exe
'@
}

Write-Host ''
Write-Host 'Pillar AI — create Play Store upload keystore' -ForegroundColor Cyan
Write-Host "Android dir: $androidDir"
Write-Host "Keystore:    $keystorePath"
Write-Host "Alias:       $alias"
Write-Host ''

if (Test-Path $keystorePath) {
  throw "Refusing to overwrite existing keystore: $keystorePath`nBack it up, then delete/move it only if you intend to replace it."
}

$keytool = Find-Keytool
Write-Host "Using keytool: $keytool"
Write-Host ''
Write-Host 'You will be prompted for passwords and certificate fields.' -ForegroundColor Yellow
Write-Host 'Store passwords in a password manager — losing them blocks app updates.' -ForegroundColor Yellow
Write-Host ''

# SecureString → plain for keytool only (not logged)
function Read-Secret([string]$prompt) {
  $sec = Read-Host -Prompt $prompt -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

$storePassword = Read-Secret 'Keystore store password'
$keyPassword = Read-Secret 'Key password (often same as store password)'
if ([string]::IsNullOrWhiteSpace($storePassword) -or [string]::IsNullOrWhiteSpace($keyPassword)) {
  throw 'Passwords cannot be empty.'
}

$cn = Read-Host 'Your name / organization (CN) [Pillar AI]'
if ([string]::IsNullOrWhiteSpace($cn)) { $cn = 'Pillar AI' }
$ou = Read-Host 'Organizational unit (OU) [Mobile]'
if ([string]::IsNullOrWhiteSpace($ou)) { $ou = 'Mobile' }
$o = Read-Host 'Organization (O) [Pillar AI]'
if ([string]::IsNullOrWhiteSpace($o)) { $o = 'Pillar AI' }
$l = Read-Host 'City (L) [New York]'
if ([string]::IsNullOrWhiteSpace($l)) { $l = 'New York' }
$st = Read-Host 'State (ST) [NY]'
if ([string]::IsNullOrWhiteSpace($st)) { $st = 'NY' }
$c = Read-Host 'Country code (C) [US]'
if ([string]::IsNullOrWhiteSpace($c)) { $c = 'US' }

$dname = "CN=$cn, OU=$ou, O=$o, L=$l, ST=$st, C=$c"

Write-Host ''
Write-Host 'Generating keystore (validity ~27 years)...' -ForegroundColor Cyan

& $keytool -genkeypair -v `
  -keystore $keystorePath `
  -storetype JKS `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias $alias `
  -storepass $storePassword `
  -keypass $keyPassword `
  -dname $dname

if ($LASTEXITCODE -ne 0) {
  throw "keytool failed with exit code $LASTEXITCODE"
}

# storeFile is relative to android/app/ (see app/build.gradle.kts)
$keyProps = @"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$alias
storeFile=../upload-keystore.jks
"@
Set-Content -Path $keyPropsPath -Value $keyProps -Encoding ascii -NoNewline
# trailing newline
Add-Content -Path $keyPropsPath -Value '' -Encoding ascii

# Clear secrets from shell variables as best-effort
$storePassword = $null
$keyPassword = $null

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host "  Keystore:       $keystorePath  (gitignored)"
Write-Host "  key.properties: $keyPropsPath  (gitignored)"
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Back up upload-keystore.jks + passwords offline (password manager / secure storage).'
Write-Host '  2. From the Flutter project root:'
Write-Host '       flutter build appbundle --release'
Write-Host '  3. Upload build/app/outputs/bundle/release/app-release.aab to Play Console.'
Write-Host '  4. Enroll in Play App Signing if prompted (Google holds the app signing key).'
Write-Host ''
Write-Host 'Verify git will not track secrets:'
Write-Host '  git check-ignore -v android/key.properties android/upload-keystore.jks'
Write-Host ''
