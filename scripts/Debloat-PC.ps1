param([switch]$NonInteractif, [switch]$SansPointRestauration, [switch]$Debloat, [switch]$Telemetrie, [switch]$Copilot, [switch]$OneDrive, [switch]$Edge, [switch]$SansEdge)
# Débloatage SÛR de Windows 10/11 - ne touche pas au Store, Xbox, Defender, Windows Update, pilotes
# Sans paramètre : mode console (tout le débloat, questions pour Copilot / OneDrive / Edge).
# Depuis l'interface : -NonInteractif + -Debloat / -Telemetrie / -Copilot / -OneDrive (/ -Edge), aucune question.
$ErrorActionPreference = "SilentlyContinue"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
if ($NonInteractif) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }
function Etape($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
if (-not $NonInteractif) {
  $Debloat = $true; $Telemetrie = $true
  $Copilot  = (Read-Host "Supprimer aussi Copilot ? (o/n)") -eq "o"
  $OneDrive = (Read-Host "Désinstaller OneDrive ? (tes fichiers déjà synchronisés restent sur le PC) (o/n)") -eq "o"
  if (-not $SansEdge) { $Edge = (Read-Host "Désinstaller Microsoft Edge ? (garde un autre navigateur, ex. Brave) (o/n)") -eq "o" }
}

if (-not $SansPointRestauration) {
  Etape "Point de restauration"
  Enable-ComputerRestore -Drive "$env:SystemDrive\"
  reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency /t REG_DWORD /d 0 /f | Out-Null
  Checkpoint-Computer -Description "Avant debloat" -RestorePointType MODIFY_SETTINGS
  Write-Host "Point de restauration créé." -ForegroundColor Green
}

if ($Debloat) {
Etape "Suppression des applis inutiles (réinstallables depuis le Microsoft Store)"
$applis = @(
  # Microsoft
  "Microsoft.BingNews","Microsoft.BingWeather","Microsoft.BingSearch","Microsoft.BingFinance","Microsoft.BingSports",
  "Microsoft.BingTravel","Microsoft.BingFoodAndDrink","Microsoft.BingHealthAndFitness","Microsoft.News",
  "Microsoft.GetHelp","Microsoft.Getstarted","Microsoft.MicrosoftOfficeHub","Microsoft.Office.OneNote","Microsoft.Office.Sway",
  "Microsoft.MicrosoftSolitaireCollection","Microsoft.People","Microsoft.PowerAutomateDesktop","Microsoft.Todos",
  "Microsoft.WindowsFeedbackHub","Microsoft.WindowsMaps","Microsoft.ZuneVideo","Microsoft.549981C3F5F10",
  "Microsoft.Windows.DevHome","Microsoft.OutlookForWindows","Microsoft.WindowsCommunicationsApps","Microsoft.MixedReality.Portal",
  "Microsoft.SkypeApp","Microsoft.Microsoft3DViewer","Microsoft.Print3D","Microsoft.Messaging","Microsoft.OneConnect",
  "Microsoft.Wallet","Microsoft.Whiteboard","Microsoft.MicrosoftJournal","Microsoft.YourPhone","MicrosoftWindows.CrossDevice",
  "MicrosoftCorporationII.MicrosoftFamily","MicrosoftCorporationII.QuickAssist","Clipchamp.Clipchamp","MSTeams","MicrosoftTeams",
  # Applis tierces preinstallees
  "*LinkedIn*","*WhatsApp*","*AdobeExpress*","*AdobeCreativeCloudExpress*","*PhotoshopExpress*","*Messenger*","*Facebook*",
  "*Instagram*","*TikTok*","*BytedancePte*","*Twitter*","*Disney*","*Netflix*","*AmazonVideo*","*PrimeVideo*",
  "*Hulu*","*Pandora*","*Shazam*","*Flipboard*","*TuneIn*","*Plex*","*ESPN*","*Picsart*","*Duolingo*","*king.com*",
  "*CandyCrush*","*BubbleWitch*","*FarmVille*","*HiddenCity*","*MarchofEmpires*","*RoyalRevolt*","*Asphalt*","*Sling*",
  "*McAfee*","*Norton*","*ExpressVPN*","*Booking*","*Xing*"
)
$nb = 0
foreach ($a in $applis) {
  $p = Get-AppxPackage -AllUsers -Name $a
  if ($p) { $p | Remove-AppxPackage -AllUsers; Write-Host " - Supprimé : $($p[0].Name)" -ForegroundColor Green; $nb++ }
  Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $a | Remove-AppxProvisionedPackage -Online | Out-Null
}
if (-not $nb) { Write-Host " - Aucune appli inutile trouvée (déjà propre)." }

Etape "Moins de pub et de suivi"
# Pubs et suggestions dans le menu Démarrer / écran de verrouillage
$cdm = "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
foreach ($v in "SilentInstalledAppsEnabled","SystemPaneSuggestionsEnabled","SubscribedContent-338388Enabled","SubscribedContent-338389Enabled","SubscribedContent-353694Enabled","SubscribedContent-353696Enabled","SubscribedContent-310093Enabled","SoftLandingEnabled","RotatingLockScreenOverlayEnabled") {
  reg add $cdm /v $v /t REG_DWORD /d 0 /f | Out-Null
}
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f | Out-Null
# Identifiant publicitaire
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f | Out-Null
# Recherche Bing dans le menu Démarrer
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f | Out-Null
reg add "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f | Out-Null
# Widgets (météo/actus dans la barre des tâches)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /t REG_DWORD /d 0 /f | Out-Null
Write-Host " - Pubs, suggestions, Bing et widgets réduits." -ForegroundColor Green

Etape "Explorateur plus pratique"
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f | Out-Null
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f | Out-Null
Write-Host " - Extensions de fichiers visibles, l'Explorateur s'ouvre sur « Ce PC »." -ForegroundColor Green
}

if ($Telemetrie) {
  Etape "Télémétrie"
  # Données de diagnostic au minimum + service « Expériences des utilisateurs connectés et télémétrie » arrêté
  reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 1 /f | Out-Null
  reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f | Out-Null
  Stop-Service DiagTrack -Force; Set-Service DiagTrack -StartupType Disabled
  Write-Host " - Télémétrie réduite au minimum (service DiagTrack désactivé)." -ForegroundColor Green
}

if ($Copilot) {
  Etape "Copilot"
  # v5.3 : Windows 11 23H2/24H2 : l'appli « Microsoft.Copilot » ; les composants système (NonRemovable) sont laissés tels quels
  $p = @(Get-AppxPackage -AllUsers -Name "*Copilot*" -ErrorAction SilentlyContinue | Where-Object { -not $_.NonRemovable -and -not $_.IsFramework })
  if ($p.Count) {
    foreach ($x in $p) {
      try { Remove-AppxPackage -Package $x.PackageFullName -AllUsers -ErrorAction Stop; Write-Host " - Appli supprimée : $($x.Name)" -ForegroundColor Green }
      catch { try { Remove-AppxPackage -Package $x.PackageFullName -ErrorAction Stop; Write-Host " - Appli supprimée (utilisateur actuel) : $($x.Name)" -ForegroundColor Green } catch { Write-Host " - $($x.Name) : suppression impossible ($($_.Exception.Message))" -ForegroundColor Yellow } }
    }
  } else { Write-Host " - Appli Copilot absente." }
  # ne revient pas pour les nouveaux comptes
  try { Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -like "*Copilot*" } | ForEach-Object { try { [void](Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop); Write-Host " - Copilot retiré de l'image Windows (nouveaux comptes)." } catch {} } } catch {}
  reg add "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f | Out-Null
  reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f | Out-Null
  Write-Host " - Copilot désactivé." -ForegroundColor Green
}

if ($OneDrive) {
  Etape "OneDrive"
  taskkill /f /im OneDrive.exe 2>&1 | Out-Null
  $fait = $false
  if (Get-Command winget) {
    winget uninstall --id Microsoft.OneDrive --source winget --silent --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $fait = $true }
  }
  if (-not $fait) {
    foreach ($s in "$env:SystemRoot\System32\OneDriveSetup.exe","$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
      if (Test-Path $s) { Start-Process $s "/uninstall" -Wait; $fait = $true; break }
    }
  }
  $reste = (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")
  if ($fait -and -not $reste) { Write-Host " - OneDrive désinstallé (tes fichiers restent dans ton dossier utilisateur)." -ForegroundColor Green }
  elseif (-not $fait) { Write-Host " - OneDrive n'est pas installé." }
  else { Write-Host " - OneDrive est encore présent : désinstalle-le depuis Paramètres > Applications." -ForegroundColor Yellow }
}

if ($Edge -and -not $SansEdge) { & (Join-Path (Split-Path -Parent $PSCommandPath) "Desinstaller-Edge.ps1") -NonInteractif:$NonInteractif }

Write-Host "`nNettoyage terminé." -ForegroundColor Green
Write-Host "Rien de critique n'a été touché : Store, Xbox, Defender, Windows Update, pilotes et Photos sont intacts."
if (-not $NonInteractif) {
  Write-Host "Pour annuler : tape 'rstrui' dans Démarrer et choisis 'Avant debloat'."
  Read-Host "Appuie sur Entrée pour fermer"
}
