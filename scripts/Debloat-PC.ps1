param([switch]$NonInteractif, [switch]$SansPointRestauration, [switch]$Debloat, [switch]$Telemetrie, [switch]$Copilot, [switch]$OneDrive, [switch]$Edge, [switch]$SansEdge)
# Débloatage SÛR de Windows 10/11 - ne touche pas au Store, Xbox, Defender, Windows Update, pilotes
# Sans paramètre : mode console (tout le débloat, questions pour Copilot / OneDrive / Edge).
# Depuis l'interface : -NonInteractif + -Debloat / -Telemetrie / -Copilot / -OneDrive (/ -Edge), aucune question.
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
function Etape($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
# v5.6 : chaque échec est compté ; code de sortie 1 s'il y en a eu au moins un
$script:echecs = 0
function Echec($t) { Write-Host " - ÉCHEC : $t" -ForegroundColor Red; $script:echecs++ }
function reg { & reg.exe @args; if ($LASTEXITCODE -ne 0) { Echec "registre ($($args[1]) $($args[3]))" } }
# v5.11 : écriture DWORD par .NET (plus reg.exe). Windows 11 24H2+ protège certaines valeurs (pilote UCPD :
#   widgets, flux d'actualités, recherche...) : même en administrateur, l'écriture est refusée à tout programme
#   non-Microsoft. Ce n'est pas une panne : ligne neutre « ignoré (protégé par Windows) », jamais compté comme échec.
#   Aucune prise de possession ni modification des droits des clés système.
$script:proteges = 0
function Est-Protege($ex) { for ($e = $ex; $e; $e = $e.InnerException) { if ($e -is [System.UnauthorizedAccessException] -or $e -is [System.Security.SecurityException]) { return $true } }; return $false }
function Reg-Dword($chemin, $nom, [int]$valeur) {
  # renvoie "ok", "deja", "protege" ou "echec"
  $racine, $sous = $chemin -split '\\', 2
  # vue 64 bits explicite (même si PowerShell 32 bits) : mêmes clés que reg.exe 64 bits
  $ruche = switch ($racine) { "HKLM" { [Microsoft.Win32.RegistryHive]::LocalMachine } "HKCU" { [Microsoft.Win32.RegistryHive]::CurrentUser } default { $null } }
  $base = $null; if ($null -ne $ruche) { try { $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($ruche, [Microsoft.Win32.RegistryView]::Registry64) } catch { $base = $null } }
  if (-not $base) { Echec "registre ($chemin $nom) : racine inconnue"; return "echec" }
  try {
    $k = $base.OpenSubKey($sous, $false)
    if ($k) { try { if (@($k.GetValueNames()) -contains $nom -and "$($k.GetValueKind($nom))" -eq "DWord" -and [int]$k.GetValue($nom) -eq $valeur) { return "deja" } } finally { $k.Close() } }
  } catch {}
  try {
    $k = $base.CreateSubKey($sous)   # crée aussi les clés parentes manquantes (ex. « Windows Feeds »)
    if (-not $k) { Echec "registre ($chemin $nom) : clé impossible à créer"; return "echec" }
    try { $k.SetValue($nom, $valeur, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $k.Close() }
    return "ok"
  } catch {
    if (Est-Protege $_.Exception) { $script:proteges++; Write-Host " - ignoré (protégé par Windows) : $chemin\$nom" -ForegroundColor DarkGray; return "protege" }
    Echec "registre ($chemin $nom) : $($_.Exception.Message)"; return "echec"
  }
}
if (-not $NonInteractif) {
  $Debloat = $true; $Telemetrie = $true
  $Copilot  = (Read-Host "Supprimer aussi Copilot ? (o/n)") -eq "o"
  $OneDrive = (Read-Host "Désinstaller OneDrive ? (tes fichiers déjà synchronisés restent sur le PC) (o/n)") -eq "o"
  if (-not $SansEdge) { $Edge = (Read-Host "Désinstaller Microsoft Edge ? (garde un autre navigateur, ex. Brave) (o/n)") -eq "o" }
}

if (-not $SansPointRestauration) {
  # v5.6 : même script que l'interface (fréquence sauvegardée puis remise, résultat vérifié)
  & (Join-Path $PSScriptRoot "Point-Restauration.ps1") -NonInteractif -Description "Avant debloat"
  if ($LASTEXITCODE -ne 0) {
    if ($NonInteractif) { Write-Host "Arrêt : pas de point de restauration, rien n'a été modifié." -ForegroundColor Red; exit 1 }
    if ((Read-Host "Continuer SANS point de restauration ? (o/n)") -ne "o") { Write-Host "Arrêt : rien n'a été modifié."; exit 1 }
  }
}

if ($Debloat) {
Etape "Suppression des applis inutiles (tous les comptes du PC ; réinstallables depuis le Microsoft Store)"
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
# v5.6 : listes lues UNE fois ; résultat vérifié pour chaque paquet ; retrait pour tous les comptes (-AllUsers)
# et de l'image Windows (paquets « provisionnés » : ne reviennent pas pour les nouveaux comptes)
$installes = @(Get-AppxPackage -AllUsers | Where-Object { -not $_.NonRemovable -and -not $_.IsFramework })
$provisionnes = @(Get-AppxProvisionedPackage -Online)
$nb = 0
foreach ($a in $applis) {
  foreach ($p in @($installes | Where-Object { $_.Name -like $a })) {
    try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; Write-Host " - Supprimé (tous les comptes) : $($p.Name)" -ForegroundColor Green; $nb++ }
    catch {
      try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; Write-Host " - Supprimé (compte actuel seulement) : $($p.Name)" -ForegroundColor Yellow; $nb++ }
      catch { Echec "$($p.Name) n'a pas pu être supprimé ($($_.Exception.Message))" }
    }
  }
  foreach ($pp in @($provisionnes | Where-Object { $_.DisplayName -like $a })) {
    try { [void](Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop); Write-Host " - Retiré de l'image Windows : $($pp.DisplayName)" -ForegroundColor Green }
    catch { Echec "$($pp.DisplayName) n'a pas pu être retiré de l'image Windows ($($_.Exception.Message))" }
  }
}
if (-not $nb) { Write-Host " - Aucune appli inutile installée (déjà propre)." }

Etape "Moins de pub et de suivi"
# Pubs et suggestions dans le menu Démarrer / écran de verrouillage
$cdm = "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
foreach ($v in "SilentInstalledAppsEnabled","SystemPaneSuggestionsEnabled","SubscribedContent-338388Enabled","SubscribedContent-338389Enabled","SubscribedContent-353694Enabled","SubscribedContent-353696Enabled","SubscribedContent-310093Enabled","SoftLandingEnabled","RotatingLockScreenOverlayEnabled") {
  [void](Reg-Dword $cdm $v 0)
}
[void](Reg-Dword "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Start_IrisRecommendations 0)
[void](Reg-Dword "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" DisableWindowsConsumerFeatures 1)
# Identifiant publicitaire
[void](Reg-Dword "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" Enabled 0)
# Recherche Bing dans le menu Démarrer
[void](Reg-Dword "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" BingSearchEnabled 0)
[void](Reg-Dword "HKCU\Software\Policies\Microsoft\Windows\Explorer" DisableSearchBoxSuggestions 1)
# Widgets (météo/actus dans la barre des tâches)
# v5.11 : stratégie machine d'abord ; si Windows la protège, réglage équivalent du compte (bouton Widgets masqué,
#         flux d'actualités de la barre des tâches coupé). Si tout est protégé : rien n'est forcé, on explique.
$w = Reg-Dword "HKLM\SOFTWARE\Policies\Microsoft\Dsh" AllowNewsAndInterests 0
if ($w -eq "protege" -or $w -eq "echec") { $w = Reg-Dword "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarDa 0 }
$fl = Reg-Dword "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" EnableFeeds 0
if ($fl -eq "protege" -or $fl -eq "echec") { $fl = Reg-Dword "HKCU\Software\Microsoft\Windows\CurrentVersion\Feeds" ShellFeedsTaskbarViewMode 2 }
if ($w -eq "ok" -or $w -eq "deja") { Write-Host " - Pubs, suggestions, Bing et widgets réduits." -ForegroundColor Green }
else {
  Write-Host " - Pubs, suggestions et Bing réduits." -ForegroundColor Green
  if ($w -eq "protege") { Write-Host " - Widgets : réglage protégé par Windows sur ce PC (rien n'a été forcé). Pour les masquer : clic droit sur la barre des tâches > Paramètres de la barre des tâches > Widgets : Désactivé." }
}

Etape "Explorateur plus pratique"
[void](Reg-Dword "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" HideFileExt 0)
[void](Reg-Dword "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" LaunchTo 1)
Write-Host " - Extensions de fichiers visibles, l'Explorateur s'ouvre sur « Ce PC »." -ForegroundColor Green
}

if ($Telemetrie) {
  Etape "Télémétrie"
  # Données de diagnostic au minimum + service « Expériences des utilisateurs connectés et télémétrie » arrêté
  [void](Reg-Dword "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" AllowTelemetry 1)
  [void](Reg-Dword "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy" TailoredExperiencesWithDiagnosticDataEnabled 0)
  Stop-Service DiagTrack -Force
  try { Set-Service DiagTrack -StartupType Disabled -ErrorAction Stop; Write-Host " - Télémétrie réduite au minimum (service DiagTrack désactivé)." -ForegroundColor Green }
  catch { if (Get-Service DiagTrack) { Echec "service DiagTrack non désactivé ($($_.Exception.Message))" } else { Write-Host " - Service DiagTrack absent sur ce PC." } }
}

if ($Copilot) {
  Etape "Copilot"
  # v5.3 : Windows 11 23H2/24H2 : l'appli « Microsoft.Copilot » ; les composants système (NonRemovable) sont laissés tels quels
  $p = @(Get-AppxPackage -AllUsers -Name "*Copilot*" -ErrorAction SilentlyContinue | Where-Object { -not $_.NonRemovable -and -not $_.IsFramework })
  if ($p.Count) {
    foreach ($x in $p) {
      try { Remove-AppxPackage -Package $x.PackageFullName -AllUsers -ErrorAction Stop; Write-Host " - Appli supprimée : $($x.Name)" -ForegroundColor Green }
      catch { try { Remove-AppxPackage -Package $x.PackageFullName -ErrorAction Stop; Write-Host " - Appli supprimée (utilisateur actuel) : $($x.Name)" -ForegroundColor Green } catch { Echec "$($x.Name) : suppression impossible ($($_.Exception.Message))" } }
    }
  } else { Write-Host " - Appli Copilot absente." }
  # ne revient pas pour les nouveaux comptes
  try { Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -like "*Copilot*" } | ForEach-Object { try { [void](Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop); Write-Host " - Copilot retiré de l'image Windows (nouveaux comptes)." } catch {} } } catch {}
  [void](Reg-Dword "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot" TurnOffWindowsCopilot 1)
  [void](Reg-Dword "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ShowCopilotButton 0)
  Write-Host " - Copilot désactivé." -ForegroundColor Green
}

if ($OneDrive) {
  Etape "OneDrive"
  taskkill /f /im OneDrive.exe 2>&1 | Out-Null
  $fait = $false
  $wg = Get-Command winget.exe -CommandType Application | Select-Object -First 1 -ExpandProperty Source
  if (-not $wg -and (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe")) { $wg = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" }
  if ($wg) {
    & $wg uninstall --id Microsoft.OneDrive --source winget --silent --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
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
  else { Echec "OneDrive est encore présent : désinstalle-le depuis Paramètres > Applications." }
}

if ($Edge -and -not $SansEdge) {
  # (le script refuse lui-même s'il n'y a aucun autre navigateur)
  & (Join-Path (Split-Path -Parent $PSCommandPath) "Desinstaller-Edge.ps1") -NonInteractif:$NonInteractif
  if ($LASTEXITCODE -ne 0) { $script:echecs++ }
}

if ($script:proteges) { Write-Host "`n$($script:proteges) réglage(s) ignoré(s) car protégé(s) par Windows (normal sur Windows 11 récent, ce n'est pas une erreur)." }
if ($script:echecs) { Write-Host "`nNettoyage terminé avec $($script:echecs) échec(s) (détails ci-dessus)." -ForegroundColor Red }
else { Write-Host "`nNettoyage terminé." -ForegroundColor Green }
Write-Host "Rien de critique n'a été touché : Store, Xbox, Defender, Windows Update, pilotes et Photos sont intacts."
if (-not $NonInteractif) {
  Write-Host "Pour annuler : tape 'rstrui' dans Démarrer et choisis 'Avant debloat'."
  Read-Host "Appuie sur Entrée pour fermer"
}
if ($script:echecs) { exit 1 } else { exit 0 }
