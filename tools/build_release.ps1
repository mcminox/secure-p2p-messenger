# Полная сборка: APK + Windows exe + MSIX.
# 1) Android SDK: рекомендуется короткий путь C:\asdk (избегает ошибок NDK при длинных путях).
# 2) Windows: VS 2022 Build Tools + компонент ATL; сборка из VsDevCmd (см. ниже).

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$WorkspaceRoot = Split-Path $Root -Parent
$BundledFlutter = Join-Path $WorkspaceRoot "tools\flutter"
if (-not $env:FlutterRoot -and (Test-Path (Join-Path $BundledFlutter "bin\flutter.bat"))) {
  $env:FlutterRoot = $BundledFlutter
  $env:Path = "$(Join-Path $BundledFlutter 'bin');$env:Path"
}

$FlutterBat = if ($env:FlutterRoot) { Join-Path $env:FlutterRoot "bin\flutter.bat" } else { "flutter" }
$DartBat = if ($env:FlutterRoot) { Join-Path $env:FlutterRoot "bin\dart.bat" } else { "dart" }

if (-not $env:ANDROID_HOME -and (Test-Path "C:\asdk")) {
  $env:ANDROID_HOME = "C:\asdk"
}
if (-not $env:JAVA_HOME) {
  $c = @(
    "C:\Program Files\Eclipse Adoptium\jdk-21.0.3.9-hotspot",
    (Get-ChildItem "$env:LOCALAPPDATA\Programs\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1).FullName
  ) | Where-Object { $_ -and (Test-Path "$_\bin\java.exe") }
  if ($c) { $env:JAVA_HOME = $c[0] }
}

New-Item -ItemType Directory -Force -Path "$Root\dist" | Out-Null

& $FlutterBat pub get

Write-Host "=== APK (release) ===" -ForegroundColor Cyan
& $FlutterBat build apk --release
Copy-Item -Force "$Root\build\app\outputs\flutter-apk\app-release.apk" "$Root\dist\SecureP2P-Messenger-release.apk"

$VsDevCandidates = @(
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat"
)
$VsDevCmd = $VsDevCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $VsDevCmd) {
  Write-Warning "VsDevCmd не найден. Установите VS Build Tools с C++ и ATL."
  exit 1
}

Write-Host "=== Windows exe + MSIX (через VsDevCmd) ===" -ForegroundColor Cyan
$cmd = @"
call "$VsDevCmd" -arch=amd64 -host_arch=amd64 && cd /d "$Root" && "$FlutterBat" build windows --release && "$DartBat" run msix:create
"@
cmd /c $cmd

Copy-Item -Force "$Root\build\windows\x64\runner\Release\secure_p2p_messenger.msix" "$Root\dist\SecureP2P-Messenger.msix"

Write-Host "Готово:" -ForegroundColor Green
Write-Host "  $Root\dist\SecureP2P-Messenger-release.apk"
Write-Host "  $Root\dist\SecureP2P-Messenger.msix"
Write-Host "  EXE: $Root\build\windows\x64\runner\Release\secure_p2p_messenger.exe"
Write-Host ""
Write-Host "Если MSIX не ставится (0x800B010A / издатель неизвестен): PowerShell от админа — .\tools\trust_msix_test_cert.ps1" -ForegroundColor Yellow
