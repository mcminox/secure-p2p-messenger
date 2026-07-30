# Устанавливает в "Доверенные корневые центры сертификации (локальный компьютер)"
# тестовый сертификат пакета msix (тот же, которым подписывается MSIX по умолчанию).
# Без этого App Installer выдаёт 0x800B010A и блокирует кнопку «Установить».
#
# Запуск: PowerShell от имени администратора:
#   cd secure_p2p_messenger
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\tools\trust_msix_test_cert.ps1

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$cacheRoot = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev"
if (-not (Test-Path $cacheRoot)) {
  throw "Не найден кэш pub: $cacheRoot. Выполните в каталоге проекта: flutter pub get"
}

$candidates = Get-ChildItem -Path $cacheRoot -Directory -Filter "msix-*" -ErrorAction SilentlyContinue |
  ForEach-Object {
    $f = Join-Path $_.FullName "assets\test_certificate.pfx"
    if (Test-Path $f) {
      [PSCustomObject]@{ Path = $f; Time = $_.LastWriteTimeUtc }
    }
  } | Sort-Object Time -Descending

$pfx = ($candidates | Select-Object -First 1).Path

if (-not $pfx) {
  throw "Не найден assets\test_certificate.pfx в пакете msix. Выполните: flutter pub get"
}

$secure = ConvertTo-SecureString -String "1234" -AsPlainText -Force
Import-PfxCertificate -FilePath $pfx -Password $secure -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
Write-Host "Готово. Закройте окно установщика MSIX и снова откройте .msix (или выполните установку заново)." -ForegroundColor Green
