param([switch]$NonInteractif)
# Désinstallation de Microsoft Edge (garde WebView2, nécessaire à beaucoup d'applis)
$ErrorActionPreference = "SilentlyContinue"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
if ($NonInteractif) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }
Write-Host "`n==> Désinstallation de Microsoft Edge" -ForegroundColor Cyan
$edgeExe = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edgeExe)) { $edgeExe = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
Get-Process msedge | Stop-Process -Force
$setups = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe", "$env:ProgramFiles\Microsoft\Edge\Application\*\Installer\setup.exe"
if (-not $setups) { Write-Host " - Edge ne semble pas installé." -ForegroundColor Yellow }
foreach ($s in $setups) {
  Write-Host " - Lancement du désinstalleur officiel : $($s.FullName)"
  $p = Start-Process $s.FullName "--uninstall --system-level --verbose-logging --force-uninstall" -Wait -PassThru -WindowStyle Hidden
  Write-Host "   code de retour : $($p.ExitCode)"
}
Start-Sleep 3
if (Test-Path $edgeExe) {
  Write-Host " - Windows a bloqué la désinstallation automatique." -ForegroundColor Red
  Write-Host "   En Europe tu peux le faire à la main : Paramètres > Applications > Microsoft Edge > Désinstaller." -ForegroundColor Yellow
  Start-Process "ms-settings:appsfeatures"
} elseif ($setups) {
  # Empêche Windows Update de le réinstaller
  reg add "HKLM\SOFTWARE\Microsoft\EdgeUpdate" /v DoNotUpdateToEdgeWithChromium /t REG_DWORD /d 1 /f | Out-Null
  Remove-Item "$env:PUBLIC\Desktop\Microsoft Edge.lnk", "$env:USERPROFILE\Desktop\Microsoft Edge.lnk" -Force
  $wv2 = Test-Path "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application"
  Write-Host " - Edge désinstallé. WebView2 : $(if ($wv2) { 'conservé' } else { 'non présent sur ce PC' })." -ForegroundColor Green
}
if (-not $NonInteractif) { Read-Host "Appuie sur Entrée pour continuer" }
