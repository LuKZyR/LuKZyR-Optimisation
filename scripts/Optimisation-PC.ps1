param(
  [switch]$NonInteractif, [switch]$SansPointRestauration,
  [switch]$Alimentation, [switch]$ModeJeu, [switch]$PlanifGPU, [switch]$PrioriteJeux, [switch]$Souris,
  [switch]$VBS, [switch]$TRIM, [switch]$NettoyageTemp, [switch]$Hibernation, [switch]$AssistantStockage,
  [switch]$Transparence, [switch]$OptimDistribution, [switch]$Reparation,
  [switch]$JeuxFenetres, [switch]$VRR, [switch]$EdgeArrierePlan, [switch]$DelaiDemarrage, [switch]$AppsArrierePlan,
  [switch]$WinSxS, [switch]$PlanEquilibre
)
# Optimisation Windows 10/11 - générique (s'adapte au PC)
# Sans paramètre : mode console interactif (tout, avec questions pour VBS et DISM/SFC).
# Depuis l'interface : -NonInteractif + un switch par réglage, aucune question posée.
$ErrorActionPreference = "SilentlyContinue"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Relance en administrateur..." -ForegroundColor Yellow
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
if ($NonInteractif) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }
function Etape($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Ok($t) { Write-Host " - $t" -ForegroundColor Green }

$reglages = "Alimentation","ModeJeu","PlanifGPU","PrioriteJeux","Souris","VBS","TRIM","NettoyageTemp","Hibernation","AssistantStockage","Transparence","OptimDistribution","Reparation",
  "JeuxFenetres","VRR","EdgeArrierePlan","DelaiDemarrage","AppsArrierePlan","WinSxS","PlanEquilibre"
# Réglages jamais appliqués « par défaut » en mode console (réservés à un choix explicite)
$optionnels = "VBS","Reparation","AppsArrierePlan","WinSxS","PlanEquilibre"
$tout = -not ($reglages | Where-Object { $PSBoundParameters.ContainsKey($_) })
if ($tout -and -not $NonInteractif) {
  # Mode console : tout sauf VBS et réparation, qui sont demandés
  foreach ($n in $reglages) { if ($optionnels -notcontains $n) { Set-Variable $n $true } }
  $VBS = (Read-Host "Désactiver VBS / intégrité de la mémoire ? (+FPS, un peu moins de sécurité) (o/n)") -eq "o"
  $Reparation = (Read-Host "Vérifier et réparer les fichiers système (DISM + SFC, ~15 min) ? (o/n)") -eq "o"
}

if (-not $SansPointRestauration) {
  Etape "Point de restauration (pour pouvoir tout annuler)"
  Enable-ComputerRestore -Drive "$env:SystemDrive\"
  reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency /t REG_DWORD /d 0 /f | Out-Null
  Checkpoint-Computer -Description "Avant optimisation PC" -RestorePointType MODIFY_SETTINGS
  Ok "Point de restauration créé."
}

if ($Alimentation) {
  Etape "Plan d'alimentation"
  if (Get-CimInstance Win32_Battery) {
    Write-Host " - PC portable détecté : plan d'alimentation laissé tel quel pour préserver la batterie." -ForegroundColor Yellow
  } else {
    # v5.5 : plan « Performances élevées » (gain faible, 0 à 2 % ; un peu plus de chaleur au repos).
    # Sur Ryzen de bureau, « Utilisation normale » donne quasiment les mêmes performances.
    $hp = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    powercfg -setactive $hp 2>&1 | Out-Null
    if ("$(powercfg /getactivescheme)" -notmatch $hp) {
      # Plan masqué sur certains Windows 11 : on le recrée une seule fois (pas de doublon s'il existe déjà)
      $existant = powercfg /list | Select-String "Performances élevées|High performance"
      $guid = $null
      if ($existant -and ("$existant" -match '([0-9a-f]{8}-[0-9a-f\-]{27})')) { $guid = $matches[1] }
      if (-not $guid) { $out = powercfg -duplicatescheme $hp; if ("$out" -match '([0-9a-f]{8}-[0-9a-f\-]{27})') { $guid = $matches[1] } }
      if ($guid) { powercfg -setactive $guid | Out-Null }
    }
    Ok "Plan « Performances élevées » activé (gain faible : 0 à 2 %)."
  }
}

if ($PlanEquilibre) {
  Etape "Plan d'alimentation « Utilisation normale »"
  if ($Alimentation) { Write-Host " - Ignoré : le plan « Performances élevées » est déjà choisi." -ForegroundColor Yellow }
  else {
    # Recommandé par AMD pour les Ryzen de bureau : la fréquence monte aussi vite, moins de chaleur au repos
    powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e
    Ok "Plan « Utilisation normale » activé (mêmes performances en jeu sur Ryzen, moins de chaleur au repos)."
  }
}

if ($ModeJeu) {
  Etape "Mode Jeu"
  reg add "HKCU\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f | Out-Null
  reg add "HKCU\Software\Microsoft\GameBar" /v AllowAutoGameMode /t REG_DWORD /d 1 /f | Out-Null
  reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f | Out-Null
  reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" /v AppCaptureEnabled /t REG_DWORD /d 0 /f | Out-Null
  Ok "Mode Jeu activé, enregistrement en arrière-plan coupé (la Game Bar reste disponible)."
}

if ($PlanifGPU) {
  Etape "Planification GPU à accélération matérielle (HAGS)"
  reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /t REG_DWORD /d 2 /f | Out-Null
  Ok "HAGS activé (effectif après redémarrage, si la carte graphique le gère)."
}

if ($PrioriteJeux) {
  Etape "Priorité aux jeux"
  $mm = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
  reg add $mm /v SystemResponsiveness /t REG_DWORD /d 10 /f | Out-Null
  reg add "$mm\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f | Out-Null
  reg add "$mm\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f | Out-Null
  reg add "$mm\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d High /f | Out-Null
  reg add "$mm\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d High /f | Out-Null
  Ok "Priorité CPU/GPU donnée aux jeux."
}

if ($Souris) {
  Etape "Souris sans accélération"
  reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d 0 /f | Out-Null
  reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d 0 /f | Out-Null
  reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d 0 /f | Out-Null
  Ok "Accélération de la souris désactivée (effectif à la prochaine session)."
}

if ($VBS) {
  Etape "Intégrité de la mémoire / VBS"
  reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f | Out-Null
  reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f | Out-Null
  Ok "VBS / intégrité de la mémoire désactivés (effectif après redémarrage)."
}

if ($TRIM) {
  Etape "TRIM des SSD"
  fsutil behavior set DisableDeleteNotify 0 | Out-Null
  $ssd = 0
  Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
    $disk = $_ | Get-Partition | Get-Disk | Get-PhysicalDisk
    if ($disk.MediaType -eq 'SSD') { Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim; Ok "TRIM lancé sur $($_.DriveLetter):"; $ssd++ }
  }
  if (-not $ssd) { Write-Host " - Aucun SSD détecté : TRIM activé dans Windows, rien à lancer." }
}

if ($NettoyageTemp) {
  Etape "Nettoyage des fichiers temporaires"
  $avant = (Get-PSDrive C).Free
  Remove-Item "$env:TEMP\*" -Recurse -Force
  Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force
  $gain = [math]::Round(((Get-PSDrive C).Free - $avant) / 1MB)
  Ok "Fichiers temporaires supprimés ($gain Mo libérés ; les fichiers en cours d'utilisation sont ignorés)."
}

if ($Hibernation) {
  Etape "Hibernation"
  $avait = Test-Path "$env:SystemDrive\hiberfil.sys"
  powercfg -h off
  if ($avait) { Ok "Hibernation et démarrage rapide désactivés (fichier hiberfil.sys supprimé)." }
  else { Ok "Hibernation et démarrage rapide désactivés (déjà inactifs, rien à supprimer)." }
}

if ($AssistantStockage) {
  Etape "Assistant de stockage"
  reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" /v 01 /t REG_DWORD /d 1 /f | Out-Null
  Ok "Assistant de stockage activé."
}

if ($Transparence) {
  Etape "Effets de transparence"
  reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f | Out-Null
  Ok "Transparence désactivée."
}

if ($OptimDistribution) {
  Etape "Optimisation de la distribution (partage des mises à jour)"
  # Mode 0 = téléchargement HTTP direct depuis Microsoft, sans partage entre PC.
  # Le service DoSvc n'est PAS désactivé (Windows Update et le Store en ont besoin) ; pas de mode 100.
  $cles = @("HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization", "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config")
  $deja = $true
  foreach ($k in $cles) {
    $v = (Get-ItemProperty -Path "Registry::$k" -Name DODownloadMode -ErrorAction SilentlyContinue).DODownloadMode
    if ($v -ne 0) { $deja = $false; reg add $k /v DODownloadMode /t REG_DWORD /d 0 /f | Out-Null }
  }
  if ($deja) { Ok "Partage des mises à jour déjà désactivé (rien à changer)." }
  else { Ok "Windows ne partage plus tes mises à jour avec d'autres PC (téléchargement direct depuis Microsoft, Windows Update intact)." }
}

# --- v5.5 : nouveaux réglages (tous enregistrés avant modification, annulables avec « Tout annuler ») ---
function Regler-DirectX($nom, $val) {
  # DirectXUserGlobalSettings est une liste « clé=valeur; » : on ne touche qu'à notre clé, les autres sont conservées
  $k = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
  if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
  $cur = (Get-ItemProperty -Path $k -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue).DirectXUserGlobalSettings
  $paires = [ordered]@{}
  foreach ($p in ("$cur" -split ';')) { if ($p -match '^\s*([^=]+?)\s*=(.*)$') { $paires[$matches[1]] = $matches[2].Trim() } }
  $deja = ("$($paires[$nom])" -eq "$val")
  if (-not $deja) {
    $paires[$nom] = "$val"
    $txt = (($paires.Keys | ForEach-Object { "$_=$($paires[$_])" }) -join ';') + ';'
    Set-ItemProperty -Path $k -Name DirectXUserGlobalSettings -Value $txt -Type String
  }
  return $deja
}

if ($JeuxFenetres) {
  Etape "Optimisations pour les jeux en fenêtre"
  if (Regler-DirectX "SwapEffectUpgradeEnable" 1) { Ok "Déjà activées (rien à changer)." }
  else { Ok "Activées : latence plus faible et HDR auto dans les jeux en fenêtre / plein écran fenêtré." }
}

if ($VRR) {
  Etape "Optimisations pour la fréquence variable (VRR)"
  if (Regler-DirectX "VRROptimizeEnable" 1) { Ok "Déjà activées (rien à changer)." }
  else { Ok "Activées : FreeSync / G-Sync aussi pour les jeux qui ne le gèrent pas d'eux-mêmes (si l'écran le permet)." }
}

if ($EdgeArrierePlan) {
  Etape "Microsoft Edge en arrière-plan"
  $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { $_ -and (Test-Path $_) }
  if (-not $edge) { Write-Host " - Edge n'est pas installé : rien à faire." -ForegroundColor Yellow }
  else {
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_DWORD /d 0 /f | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v BackgroundModeEnabled /t REG_DWORD /d 0 /f | Out-Null
    Ok "Edge ne se précharge plus au démarrage et ne reste plus ouvert une fois fermé (Edge fonctionne normalement)."
  }
}

if ($DelaiDemarrage) {
  Etape "Délai des applis au démarrage"
  $k = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
  reg add $k /v StartupDelayInMSec /t REG_DWORD /d 0 /f | Out-Null
  reg add $k /v WaitForIdleState /t REG_DWORD /d 0 /f | Out-Null
  Ok "Les applis de démarrage se lancent sans attendre (bureau prêt un peu plus tôt)."
}

if ($AppsArrierePlan) {
  Etape "Applis du Store en arrière-plan"
  # 2 = refusé pour toutes les applis du Store (les programmes classiques ne sont pas concernés)
  reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /t REG_DWORD /d 2 /f | Out-Null
  Ok "Applis du Store bloquées en arrière-plan (certaines notifications, comme Courrier ou Teams version Store, peuvent arriver en retard)."
}

if ($WinSxS) {
  Etape "Nettoyage des composants Windows (WinSxS, peut prendre 10 min)"
  # Jamais /ResetBase : les mises à jour installées restent désinstallables
  DISM /Online /Cleanup-Image /StartComponentCleanup 2>&1 | ForEach-Object { "$_" -replace "`0","" } | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*\[[=\s\d\.%]*\]\s*$' } | ForEach-Object { Write-Host "   $_" }
  Ok "Anciennes versions des composants supprimées (les mises à jour restent désinstallables)."
}

if ($Reparation) {
  Etape "Réparation des fichiers système (DISM + SFC, peut prendre 15 min)"
  DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | ForEach-Object { "$_" -replace "`0","" } | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*\[[=\s\d\.%]*\]\s*$' } | ForEach-Object { Write-Host "   $_" }
  sfc /scannow 2>&1 | ForEach-Object { "$_" -replace "`0","" } | Where-Object { $_ -match '\S' -and $_ -notmatch '\d+\s*%' } | ForEach-Object { Write-Host "   $_" }
  Ok "Réparation terminée."
}

Etape "Vérifications"
$mem = Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1
$ram = $mem.ConfiguredClockSpeed; if (-not $ram) { $ram = $mem.Speed }
if ($ram) { Write-Host " - Vitesse RAM actuelle : $ram MHz (max annoncée : $($mem.Speed) MHz)" } else { Write-Host " - Vitesse RAM : non communiquée par ce PC." }
if (($mem.SMBIOSMemoryType -eq 26 -and $ram -and $ram -le 2666) -or ($mem.SMBIOSMemoryType -eq 34 -and $ram -and $ram -le 4800)) {
  Write-Host "   -> RAM à sa vitesse de base : active XMP/EXPO/DOCP dans le BIOS si ta RAM le permet." -ForegroundColor Yellow
}
Write-Host "`nOptimisation terminée. Redémarre le PC pour tout appliquer." -ForegroundColor Green
if (-not $NonInteractif) {
  Write-Host "Pour annuler : tape 'rstrui' dans Démarrer et choisis le point « Avant ... »."
  Read-Host "Appuie sur Entrée pour fermer"
}
