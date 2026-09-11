$ErrorActionPreference = 'Stop'

$supabaseUrl = if ($env:SUPABASE_URL) {
  $env:SUPABASE_URL
} else {
  'https://vrpxpidnbhnuismbzroe.supabase.co'
}

if (-not $env:SUPABASE_ANON_KEY) {
  throw 'Set SUPABASE_ANON_KEY to the staging public anon/publishable key before building.'
}

$artifact = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-release.apk'
if (Test-Path $artifact) {
  Remove-Item -LiteralPath $artifact -Force
}

flutter build apk --release `
  --dart-define=OSLAVA_ENV=staging `
  --dart-define=SUPABASE_URL="$supabaseUrl" `
  --dart-define=SUPABASE_ANON_KEY="$env:SUPABASE_ANON_KEY"

if ($LASTEXITCODE -ne 0) {
  throw "flutter build apk failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $artifact)) {
  throw "Expected APK was not created at $artifact"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $artifact).Length
Write-Output "Built staging APK at $artifact"
Write-Output "Size bytes: $size"
Write-Output "SHA256: $hash"
