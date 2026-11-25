param([string[]]$Apps = @("Discord","Steam","Epic Games","Brave","Spotify","Ubisoft Connect","Rockstar Games"), [switch]$SansQuestion, [switch]$NonInteractif, [switch]$MajTout)
# Installation des applis via winget (sources officielles) : Discord, Steam, Epic Games, Brave, Spotify, Ubisoft Connect,
# Rockstar Games, EA app, Battle.net, GOG Galaxy, 7-Zip, VLC, OBS Studio (sans paramètre : les 7 premières)
$ErrorActionPreference = "SilentlyContinue"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
if ($NonInteractif) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false; $SansQuestion = $true }
# -Apps "Discord,Epic Games" (passé en une seule chaîne par -File) -> liste
$Apps = @($Apps | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim(" '`"") } | Where-Object { $_ })
Write-Host "`n==> Installation des applications" -ForegroundColor Cyan
if (-not (Get-Command winget)) {
    Write-Host "winget est absent : installe « Programme d'installation d'application » (App Installer) depuis le Microsoft Store, puis relance." -ForegroundColor Red
    if (-not $NonInteractif) { Read-Host "Entrée pour fermer" }
    exit 1
}
winget source update --disable-interactivity 2>&1 | Out-Null
$applis = [ordered]@{
  "Discord"     = "Discord.Discord"
  "Steam"       = "Valve.Steam"
  "Epic Games"  = "EpicGames.EpicGamesLauncher"
  "Brave"       = "Brave.Brave"
  "Spotify"     = "Spotify.Spotify"
  "Ubisoft Connect" = "Ubisoft.Connect"
  "Rockstar Games"  = "RockstarGames.Launcher"
  "EA app"      = "ElectronicArts.EADesktop"
  "Battle.net"  = "Blizzard.BattleNet"
  "GOG Galaxy"  = "GOG.Galaxy"
  "7-Zip"       = "7zip.7zip"
  "VLC"         = "VideoLAN.VLC"
  "OBS Studio"  = "OBSProject.OBSStudio"
}
# Options supplémentaires par appli : le paquet Battle.net exige un dossier d'installation (InstallLocationRequired)
$options = @{
  "Battle.net" = @("--location", "${env:ProgramFiles(x86)}\Battle.net")
}
$echecs = 0
foreach ($nom in $applis.Keys) {
  if ($Apps -notcontains $nom) { continue }
  $id = $applis[$nom]
  $deja = winget list --id $id --exact --source winget --accept-source-agreements --disable-interactivity 2>&1 | Select-String ([regex]::Escape($id))
  if ($deja) { Write-Host " - $nom déjà installé." -ForegroundColor Yellow; continue }
  Write-Host " - Installation de $nom..."
  if ($nom -eq "Spotify") {
    # L'installeur de Spotify refuse de tourner en administrateur : on le relance avec des droits normaux
    $spExe = Join-Path $env:APPDATA "Spotify\Spotify.exe"
    $cmd = Join-Path $env:TEMP "helixflux-spotify.cmd"
    $res = Join-Path $env:TEMP "helixflux-spotify.log"
    Remove-Item $res -Force -ErrorAction SilentlyContinue
    Set-Content -Path $cmd -Encoding ASCII -Value "@echo off`r`nwinget install --id Spotify.Spotify --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity`r`necho CODE=%ERRORLEVEL% > `"$res`"`r`nexit"
    $lua = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue).EnableLUA
    if ($lua -eq 0) {
      # Contrôle de compte (UAC) désactivé : l'Explorateur est lui aussi administrateur -> jeton restreint
      Start-Process runas.exe -ArgumentList "/trustlevel:0x20000 `"$cmd`"" -WindowStyle Hidden
    } else {
      # Cas normal : l'Explorateur tourne avec des droits normaux
      Start-Process explorer.exe -ArgumentList "`"$cmd`""
    }
    $t = 0
    while (-not (Test-Path $spExe) -and -not (Test-Path $res) -and $t -lt 600) { Start-Sleep -Seconds 5; $t += 5 }
    $code = (Get-Content $res -Raw -ErrorAction SilentlyContinue) -replace '(?s)^\D*?(-?\d+).*', '$1'
    Remove-Item $cmd, $res -Force -ErrorAction SilentlyContinue
    if (Test-Path $spExe) { Write-Host "   Spotify installé." -ForegroundColor Green }
    elseif ($code -and $code.Trim() -ne "0") { Write-Host "   Échec pour Spotify (code $($code.Trim())), installe-le depuis spotify.com." -ForegroundColor Red; $echecs++ }
    else { Write-Host "   Spotify pas encore détecté : l'installation continue peut-être en arrière-plan, sinon installe-le depuis spotify.com." -ForegroundColor Yellow }
    continue
  }
  $extra = @($options[$nom] | Where-Object { $_ })
  winget install --id $id --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity @extra 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -match '[A-Za-z]{3}' -and $_ -notmatch '[█▒]' } | ForEach-Object { Write-Host "   $($_.Trim())" }
  if ($LASTEXITCODE -eq 0) { Write-Host "   $nom installé." -ForegroundColor Green } else { Write-Host "   Échec pour $nom (code $LASTEXITCODE), installe-le à la main." -ForegroundColor Red; $echecs++ }
}
if ($SansQuestion) { $r = if ($MajTout) { "o" } else { "n" } } else { $r = Read-Host "`nMettre aussi à jour toutes tes autres applis avec winget ? (o/n)" }
if ($r -eq "o") {
  Write-Host "`n==> Mise à jour des autres applications" -ForegroundColor Cyan
  winget upgrade --all --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -match '[A-Za-z]{3}' -and $_ -notmatch '[█▒]' } | ForEach-Object { Write-Host "   $($_.Trim())" }
}
Write-Host "`nApplications terminées." -ForegroundColor Green
if (-not $NonInteractif -and -not $SansQuestion) { Read-Host "Appuie sur Entrée pour fermer" }
