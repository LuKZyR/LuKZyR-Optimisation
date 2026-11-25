param([switch]$NonInteractif)
# Désinstallation de Microsoft Edge (garde WebView2, nécessaire à beaucoup d'applis)
# v5.6 : refuse de désinstaller s'il n'y a aucun autre navigateur ; code 1 si Edge est toujours là.
$ErrorActionPreference = "SilentlyContinue"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # v5.6 : relance en administrateur AVEC les mêmes paramètres, attend la fin et renvoie son code ; UAC refusé = code 1
    $relance = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    foreach ($p in $PSBoundParameters.GetEnumerator()) {
      if ($p.Value -is [switch]) { if ($p.Value.IsPresent) { $relance += "-$($p.Key)" } }
      else { $relance += "-$($p.Key)"; $relance += "`"$(@($p.Value) -join ',')`"" }
    }
    try { $pr = Start-Process powershell -ArgumentList ($relance -join ' ') -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $pr.ExitCode }
    catch { Write-Host "Droits administrateur refusés : rien n'a été modifié." -ForegroundColor Red; exit 1 }
}
if ($NonInteractif) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }
Write-Host "`n==> Désinstallation de Microsoft Edge" -ForegroundColor Cyan
$edges = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")
function Edge-Present { [bool](@($edges | Where-Object { $_ -and (Test-Path $_) }).Count) }
if (-not (Edge-Present)) {
  Write-Host " - Edge n'est pas installé : rien à faire." -ForegroundColor Yellow
  if (-not $NonInteractif) { Read-Host "Appuie sur Entrée pour continuer" }
  exit 0
}
# Un autre navigateur doit VRAIMENT être installé (sinon le PC se retrouve sans navigateur)
$autres = [ordered]@{
  "Brave"   = @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe")
  "Chrome"  = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
  "Firefox" = @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe", "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe")
  "Opera"   = @("$env:LOCALAPPDATA\Programs\Opera\opera.exe", "$env:LOCALAPPDATA\Programs\Opera GX\opera.exe", "$env:ProgramFiles\Opera\opera.exe")
  "Vivaldi" = @("$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe", "$env:ProgramFiles\Vivaldi\Application\vivaldi.exe")
}
$trouve = @($autres.Keys | Where-Object { @($autres[$_] | Where-Object { $_ -and (Test-Path $_) }).Count })
if (-not $trouve.Count) {
  Write-Host " - ARRÊT : aucun autre navigateur trouvé (Brave, Chrome, Firefox, Opera, Vivaldi). Edge n'a PAS été désinstallé." -ForegroundColor Red
  Write-Host "   Installe d'abord un autre navigateur (page Applications > Brave), puis recommence." -ForegroundColor Yellow
  if (-not $NonInteractif) { Read-Host "Appuie sur Entrée pour continuer" }
  exit 1
}
Write-Host " - Autre navigateur présent : $($trouve -join ', ')."
Get-Process msedge | Stop-Process -Force
$setups = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe", "$env:ProgramFiles\Microsoft\Edge\Application\*\Installer\setup.exe"
foreach ($s in $setups) {
  Write-Host " - Lancement du désinstalleur officiel : $($s.FullName)"
  $p = Start-Process $s.FullName "--uninstall --system-level --verbose-logging --force-uninstall" -Wait -PassThru -WindowStyle Hidden
  Write-Host "   code de retour : $($p.ExitCode)"
}
Start-Sleep 3
if (Edge-Present) {
  Write-Host " - ÉCHEC : Edge est toujours installé (Windows a bloqué la désinstallation automatique)." -ForegroundColor Red
  Write-Host "   En Europe tu peux le faire à la main : Paramètres > Applications > Microsoft Edge > Désinstaller." -ForegroundColor Yellow
  if (-not $NonInteractif) { Start-Process "ms-settings:appsfeatures"; Read-Host "Appuie sur Entrée pour continuer" }
  exit 1
}
# Remarque : aucune clé de registre n'empêche de façon fiable Windows Update de réinstaller Edge
# (DoNotUpdateToEdgeWithChromium ne servait qu'à la migration de l'ancien Edge) : on n'en écrit donc aucune.
Remove-Item "$env:PUBLIC\Desktop\Microsoft Edge.lnk", "$env:USERPROFILE\Desktop\Microsoft Edge.lnk" -Force
$wv2 = Test-Path "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application"
Write-Host " - Edge désinstallé. WebView2 : $(if ($wv2) { 'conservé' } else { 'non présent sur ce PC' })." -ForegroundColor Green
Write-Host "   Une grosse mise à jour de Windows peut le réinstaller : relance simplement cette option si besoin."
if (-not $NonInteractif) { Read-Host "Appuie sur Entrée pour continuer" }
exit 0
