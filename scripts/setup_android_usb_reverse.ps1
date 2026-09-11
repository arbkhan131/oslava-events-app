$ErrorActionPreference = 'Stop'

$adbCandidates = @(
  "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
  "$env:ANDROID_HOME\platform-tools\adb.exe",
  "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
  "adb.exe"
) | Where-Object { $_ -and (Get-Command $_ -ErrorAction SilentlyContinue) }

if (-not $adbCandidates) {
  throw 'adb.exe was not found. Install Android platform-tools or add adb to PATH.'
}

$adb = $adbCandidates[0]
& $adb devices
& $adb reverse tcp:55321 tcp:55321
& $adb reverse --list

Write-Output 'Android USB reverse is configured: phone 127.0.0.1:55321 -> PC 127.0.0.1:55321'
