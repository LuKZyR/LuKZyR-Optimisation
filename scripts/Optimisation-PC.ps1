param(
  [switch]$NonInteractif, [switch]$SansPointRestauration,
  [switch]$Alimentation, [switch]$ModeJeu, [switch]$PlanifGPU, [switch]$PrioriteJeux, [switch]$Souris,
  [switch]$VBS, [switch]$TRIM, [switch]$NettoyageTemp, [switch]$Hibernation, [switch]$AssistantStockage,
  [switch]$Transparence, [switch]$OptimDistribution, [switch]$Reparation,
  [switch]$JeuxFenetres, [switch]$VRR, [switch]$EdgeArrierePlan, [switch]$DelaiDemarrage, [switch]$AppsArrierePlan,
  [switch]$WinSxS, [switch]$PlanEquilibre,
  [switch]$ModeAlimPerf, [switch]$GpuJeux, [switch]$OptimLecteurs,
  [switch]$CachesShaders
)
# Optimisation Windows 10/11 - générique (s'adapte au PC)
# Sans paramètre : mode console interactif (tout, avec questions pour VBS et DISM/SFC).
# Depuis l'interface : -NonInteractif + un switch par réglage, aucune question posée.
$ErrorActionPreference = "SilentlyContinue"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Relance en administrateur..." -ForegroundColor Yellow
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
function Ok($t) { Write-Host " - $t" -ForegroundColor Green }
# v5.6 : chaque échec réel est compté ; code de sortie 1 s'il y en a eu au moins un
$script:echecs = 0
function Echec($t) { Write-Host " - ÉCHEC : $t" -ForegroundColor Red; $script:echecs++ }
function reg { & reg.exe @args; if ($LASTEXITCODE -ne 0) { Echec "registre ($($args[1]) $($args[3]))" } }
# PC portable = Windows le dit « mobile », ou une vraie batterie (pas un onduleur) dans un boîtier qui n'est pas un PC fixe
# v5.14 : vraie batterie (pas un onduleur), même sur un PC qui ne se dit pas « portable »
function A-Batterie { [bool]@(Get-CimInstance Win32_Battery | Where-Object { "$($_.Name) $($_.DeviceID)" -notmatch 'UPS|APC|Eaton|CyberPower|Back-?UPS|Onduleur|Smart-UPS' }).Count }
function Est-Portable {
  $type = 0; try { $type = [int](Get-CimInstance Win32_ComputerSystem).PCSystemType } catch {}
  if ($type -eq 2) { return $true }
  $bat = @(Get-CimInstance Win32_Battery | Where-Object { "$($_.Name) $($_.DeviceID)" -notmatch 'UPS|APC|Eaton|CyberPower|Back-?UPS|Onduleur|Smart-UPS' })
  if (-not $bat.Count) { return $false }
  $ch = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes)
  if (@($ch | Where-Object { $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 24, 35 }).Count) { return $false }
  return $true
}

$reglages = "Alimentation","ModeJeu","PlanifGPU","PrioriteJeux","Souris","VBS","TRIM","NettoyageTemp","Hibernation","AssistantStockage","Transparence","OptimDistribution","Reparation",
  "JeuxFenetres","VRR","EdgeArrierePlan","DelaiDemarrage","AppsArrierePlan","WinSxS","PlanEquilibre","ModeAlimPerf","GpuJeux","OptimLecteurs","CachesShaders"
# Réglages jamais appliqués « par défaut » en mode console (réservés à un choix explicite)
# v5.16 : CachesShaders aussi (cache : à demander explicitement)
$optionnels = "VBS","Reparation","AppsArrierePlan","WinSxS","PlanEquilibre","ModeAlimPerf","GpuJeux","CachesShaders"
$tout = -not ($reglages | Where-Object { $PSBoundParameters.ContainsKey($_) })
if ($tout -and -not $NonInteractif) {
  # Mode console : tout sauf VBS et réparation, qui sont demandés
  foreach ($n in $reglages) { if ($optionnels -notcontains $n) { Set-Variable $n $true } }
  $VBS = (Read-Host "Désactiver VBS / intégrité de la mémoire ? (gain variable selon le PC, un peu moins de sécurité) (o/n)") -eq "o"
  $Reparation = (Read-Host "Vérifier et réparer les fichiers système (DISM + SFC, ~15 min) ? (o/n)") -eq "o"
}

if (-not $SansPointRestauration) {
  Etape "Point de restauration (pour pouvoir tout annuler)"
  # v5.6 : même script que l'interface (fréquence sauvegardée puis remise, résultat vérifié)
  & (Join-Path $PSScriptRoot "Point-Restauration.ps1") -NonInteractif -Description "Avant optimisation PC"
  # v5.14 : code 2 = un point récent (moins de 10 min) existait déjà et est réutilisé (dit clairement par le script)
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
    if ($NonInteractif) { Write-Host "Arrêt : pas de point de restauration, rien n'a été modifié." -ForegroundColor Red; exit 1 }
    if ((Read-Host "Continuer SANS point de restauration ? (o/n)") -ne "o") { Write-Host "Arrêt : rien n'a été modifié."; exit 1 }
  }
}

if ($Alimentation) {
  Etape "Plan d'alimentation"
  if (Est-Portable) {
    Write-Host " - PC portable détecté : plan d'alimentation laissé tel quel pour préserver la batterie." -ForegroundColor Yellow
  } else {
    # v5.5 : plan « Performances élevées » (gain faible, 0 à 2 % ; un peu plus de chaleur au repos).
    # Sur Ryzen de bureau, « Utilisation normale » donne quasiment les mêmes performances.
    $hp = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    powercfg -setactive $hp 2>&1 | Out-Null
    if ("$(powercfg /getactivescheme)" -notmatch $hp) {
      # Plan masqué sur certains Windows 11 : on le recrée UNE fois. v5.6 : repéré par son GUID (noté dans
      # ProgramData\Lukzyr\plan-cree.txt), jamais par son nom (traduit selon la langue de Windows) ;
      # « Tout annuler » le supprime.
      $fc = Join-Path $env:ProgramData "Lukzyr\plan-cree.txt"
      $guid = if (Test-Path $fc) { "$(Get-Content $fc -Raw)".Trim() } else { "" }
      if ($guid -and "$(powercfg /list)" -notmatch [regex]::Escape($guid)) { $guid = "" }
      if (-not $guid) {
        $out = powercfg -duplicatescheme $hp
        if ("$out" -match '([0-9a-f]{8}-[0-9a-f\-]{27})') { $guid = $matches[1]; [void](New-Item -ItemType Directory -Force (Split-Path $fc)); Set-Content -Path $fc -Value $guid -Encoding ASCII }
      }
      if ($guid) { powercfg -setactive $guid 2>&1 | Out-Null }
    }
    if ("$(powercfg /getactivescheme)" -match '([0-9a-f]{8}-[0-9a-f\-]{27})' -and ($matches[1] -eq $hp -or $matches[1] -eq $guid)) { Ok "Plan « Performances élevées » activé (gain faible : 0 à 2 %)." }
    else { Echec "le plan « Performances élevées » n'a pas pu être activé." }
  }
}

if ($PlanEquilibre) {
  Etape "Plan d'alimentation « Utilisation normale »"
  if ($Alimentation) { Write-Host " - Ignoré : le plan « Performances élevées » est déjà choisi." -ForegroundColor Yellow }
  else {
    # Recommandé par AMD pour les Ryzen de bureau : la fréquence monte aussi vite, moins de chaleur au repos
    powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "Plan « Utilisation normale » activé (mêmes performances en jeu sur Ryzen, moins de chaleur au repos)." }
    else { Echec "plan « Utilisation normale » non activé (powercfg code $LASTEXITCODE)." }
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
  # v5.14 : « GPU Priority » et « SFIO Priority » ne sont plus écrits : la documentation Microsoft (MMCSS) les donne
  # comme inutilisés. « Tout annuler » remet quand même ceux écrits par une ancienne version (toujours sauvegardés).
  reg add $mm /v SystemResponsiveness /t REG_DWORD /d 10 /f | Out-Null
  reg add "$mm\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f | Out-Null
  reg add "$mm\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d High /f | Out-Null
  Ok "Un peu moins de processeur réservé aux tâches de fond (effet faible, pas de gain d'images/s garanti)."
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
  # v5.6 : texte honnête ; on ne touche PAS à l'hyperviseur (bcdedit) : VBS peut rester actif si l'intégrité
  # de la mémoire est gérée par Sécurité Windows, ou si Hyper-V / WSL2 / Sandbox l'utilisent.
  Ok "Demande de désactivation de VBS / intégrité de la mémoire enregistrée (effectif après redémarrage)."
  Write-Host "   VBS peut rester actif si Hyper-V, WSL2 ou le Bac à sable Windows sont utilisés, ou si Sécurité Windows le réactive." -ForegroundColor Yellow
  Write-Host "   Vérifie après redémarrage : Sécurité Windows > Sécurité de l'appareil > Isolation du noyau. Le gain dépend du PC (souvent faible)."
}

if ($TRIM) {
  Etape "TRIM des SSD"
  fsutil behavior set DisableDeleteNotify 0 | Out-Null
  if ($LASTEXITCODE -eq 0) { Ok "TRIM activé dans Windows." } else { Echec "TRIM non activé (fsutil code $LASTEXITCODE)." }
  # v5.6 : beaucoup de SSD NVMe ont MediaType = « Unspecified » : on tente le TRIM sur tout volume qui n'est pas un disque dur
  # connu ; Windows refuse simplement les disques qui ne le gèrent pas.
  $ssd = 0
  Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -match 'NTFS|ReFS' } | ForEach-Object {
    $lettre = $_.DriveLetter
    $disk = $_ | Get-Partition | Get-Disk | Get-PhysicalDisk
    if ("$($disk.MediaType)" -eq 'HDD') { return }
    if ("$($disk.BusType)" -match '(?i)USB|SD|MMC|1394|File Backed Virtual') { return }
    try { Optimize-Volume -DriveLetter $lettre -ReTrim -ErrorAction Stop; Ok "TRIM lancé sur $($lettre): ($(if ("$($disk.MediaType)" -eq 'SSD') { 'SSD' } else { "type « $($disk.MediaType) », $($disk.BusType)" }))"; $ssd++ }
    catch { Write-Host " - $($lettre): TRIM non pris en charge par ce disque ($($_.Exception.Message.Trim()))." }
  }
  if (-not $ssd) { Write-Host " - Aucun SSD compatible TRIM trouvé : rien à lancer." }
}

if ($NettoyageTemp) {
  Etape "Nettoyage des fichiers temporaires"
  # v5.6 : jamais de suivi des liens (jonction / lien symbolique dans Temp = on supprime le lien, pas sa cible),
  # et gain mesuré sur les lecteurs réellement concernés (pas toujours C:)
  $dossiers = @($env:TEMP, "$env:SystemRoot\Temp") | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
  $lecteurs = @($dossiers | ForEach-Object { ([IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $_).ProviderPath)).Substring(0, 1) } | Select-Object -Unique)
  $avant = @{}; foreach ($l in $lecteurs) { $avant[$l] = (Get-PSDrive $l).Free }
  function Vider-Dossier($d) {
    foreach ($e in @(Get-ChildItem -LiteralPath $d -Force)) {
      if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        # lien : on enlève le lien lui-même (le dossier pointé n'est pas touché)
        if ($e.PSIsContainer) { try { [IO.Directory]::Delete($e.FullName, $false) } catch {} } else { try { [IO.File]::Delete($e.FullName) } catch {} }
      } elseif ($e.PSIsContainer) { Vider-Dossier $e.FullName; try { [IO.Directory]::Delete($e.FullName, $false) } catch {} }
      else { try { [IO.File]::Delete($e.FullName) } catch {} }
    }
  }
  foreach ($d in $dossiers) { Vider-Dossier $d }
  $gain = 0; foreach ($l in $lecteurs) { $gain += ((Get-PSDrive $l).Free - $avant[$l]) }
  $gain = [math]::Max(0.0, [math]::Round($gain / 1MB))
  Ok "Fichiers temporaires supprimés ($gain Mo libérés ; les fichiers en cours d'utilisation sont ignorés)."
}

# v5.16 : caches de shaders (DirectX / NVIDIA / AMD / Intel) et caches d'icônes / miniatures
# de l'Explorateur. On ne supprime QUE le contenu des dossiers listés (jamais le dossier
# lui-même). Fichiers verrouillés = ignorés, sans tuer l'Explorateur. Non annulable (c'est un cache).
if ($CachesShaders) {
  Etape "Nettoyage des caches shaders et miniatures"
  $local = $env:LOCALAPPDATA
  $racines = @(
    (Join-Path $local "D3DSCache"),
    (Join-Path $local "NVIDIA\DXCache"),
    (Join-Path $local "NVIDIA\GLCache"),
    (Join-Path $local "NVIDIA Corporation\NV_Cache"),
    (Join-Path $local "AMD\DxCache"),
    (Join-Path $local "AMD\DxcCache"),
    (Join-Path $local "AMD\VkCache"),
    (Join-Path $local "AMD\GLCache"),
    (Join-Path $local "Intel\ShaderCache"),
    (Join-Path $local "Intel\DXCache"),
    (Join-Path $local "Intel\GLCache"),
    (Join-Path $local "Intel\VkCache")
  )
  function Sous-Racine($chemin, $racine) {
    try {
      $c = [IO.Path]::GetFullPath($chemin)
      $r = [IO.Path]::GetFullPath($racine).TrimEnd('\')
      return $c.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or $c.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
  }
  # Vide le CONTENU de $d (fichiers et sous-dossiers). $d lui-même n'est jamais supprimé.
  # Les jonctions / liens ne sont pas suivis (ni supprimés).
  function Vider-ContenuCache($d) {
    $gain = [int64]0; $ok = 0; $saut = 0
    foreach ($e in @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)) {
      if (-not (Sous-Racine $e.FullName $d)) { $saut++; continue }
      if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { $saut++; continue }
      if ($e.PSIsContainer) {
        $r = Vider-ContenuCache $e.FullName
        $gain += $r.Gain; $ok += $r.Ok; $saut += $r.Saut
        try { [IO.Directory]::Delete($e.FullName, $false) } catch {}
      } else {
        $taille = [int64]0; try { $taille = [int64]$e.Length } catch {}
        try { [IO.File]::Delete($e.FullName); $gain += $taille; $ok++ } catch { $saut++ }
      }
    }
    return @{ Gain = $gain; Ok = $ok; Saut = $saut }
  }
  $total = [int64]0; $nf = 0; $ns = 0; $vus = 0
  foreach ($d in $racines) {
    if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
    $vus++
    $r = Vider-ContenuCache $d
    $total += $r.Gain; $nf += $r.Ok; $ns += $r.Saut
  }
  $expl = Join-Path $local "Microsoft\Windows\Explorer"
  if ($expl -and (Test-Path -LiteralPath $expl)) {
    $vus++
    foreach ($e in @(Get-ChildItem -LiteralPath $expl -Force -ErrorAction SilentlyContinue -File | Where-Object { $_.Name -match '^(thumbcache|iconcache)_.*\.db$' })) {
      if (-not (Sous-Racine $e.FullName $expl)) { $ns++; continue }
      $taille = [int64]0; try { $taille = [int64]$e.Length } catch {}
      try { [IO.File]::Delete($e.FullName); $total += $taille; $nf++ } catch { $ns++ }
    }
  }
  $mo = [math]::Max(0.0, [math]::Round($total / 1MB))
  if ($nf -eq 0 -and $ns -eq 0) { Write-Host " - Aucun cache trouvé : rien à nettoyer." }
  elseif ($nf -eq 0) { Ok "Aucun fichier libéré ($ns fichier(s) en cours d'utilisation laissés en place)." }
  else { Ok "Caches shaders et miniatures nettoyés ($mo Mo libérés, $nf fichier(s) ; les fichiers en cours d'utilisation sont ignorés)." }
}

if ($Hibernation -and (A-Batterie)) {
  # v5.14 : jamais sur un PC avec batterie (portable, tablette), même sans le profil « PC portable »
  Etape "Hibernation"
  Write-Host " - Batterie détectée : hibernation laissée active (elle protège ton travail quand la batterie est vide)." -ForegroundColor Yellow
}
elseif ($Hibernation) {
  Etape "Hibernation"
  $avait = Test-Path "$env:SystemDrive\hiberfil.sys"
  powercfg -h off 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Echec "hibernation non désactivée (powercfg code $LASTEXITCODE)." }
  elseif ($avait) { Ok "Hibernation et démarrage rapide désactivés (fichier hiberfil.sys supprimé)." }
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
  if ($LASTEXITCODE -eq 0) { Ok "Anciennes versions des composants supprimées (les mises à jour restent désinstallables)." }
  else { Echec "nettoyage des composants (DISM code $LASTEXITCODE)." }
}

# --- v5.14 ---
if ($ModeAlimPerf) {
  Etape "Mode d'alimentation « Meilleures performances » (Windows 11)"
  try {
    . (Join-Path $PSScriptRoot "Sauvegarde-Reglages.ps1") -NonInteractif:$NonInteractif
    $plan = if ("$(powercfg /getactivescheme)" -match '([0-9a-f]{8}-[0-9a-f\-]{27})') { $matches[1] } else { "" }
    if ($Alimentation -or $plan -eq "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -or $plan -eq "e9a42b02-d5df-448d-aa00-03f14749eb61") {
      Write-Host " - Ignoré : ce mode n'agit qu'avec le plan « Utilisation normale » (un plan Performances élevées est actif)." -ForegroundColor Yellow
    } else {
      $avant = Mode-Alim
      if ($avant -eq $script:ModesAlim.perf) { Ok "Déjà en « Meilleures performances » (rien à changer)." }
      else { [void](Mode-Alim $script:ModesAlim.perf); if ((Mode-Alim) -eq $script:ModesAlim.perf) { Ok "Mode « Meilleures performances » activé sur secteur (gain faible ; la batterie garde son propre mode)." } else { Echec "mode d'alimentation non changé." } }
    }
  } catch {
    $ex = $_.Exception; $types = ""; while ($ex) { $types += " " + $ex.GetType().Name; $ex = $ex.InnerException }
    if ($types -match 'EntryPointNotFound|DllNotFound') { Write-Host " - Non disponible sur cette version de Windows (Windows 11 seulement) : rien n'a été changé." -ForegroundColor Yellow }
    else { Echec "mode d'alimentation : $($_.Exception.Message)" }
  }
}

if ($GpuJeux) {
  Etape "Carte graphique puissante pour les jeux"
  # Même réglage que Paramètres > Affichage > Graphiques > « Hautes performances », jeu par jeu. Une préférence déjà
  # choisie (par toi ou par Windows) n'est JAMAIS remplacée. Valeurs d'origine sauvegardées avant (« Tout annuler »).
  . (Join-Path $PSScriptRoot "Sauvegarde-Reglages.ps1") -NonInteractif:$NonInteractif
  $gpuPci = @(Get-CimInstance Win32_VideoController | Where-Object { "$($_.PNPDeviceID)" -like 'PCI\*' })
  if ($gpuPci.Count -lt 2) { Write-Host " - Une seule carte graphique : rien à régler." -ForegroundColor Yellow }
  else {
    $k = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    $exist = @((Get-Item -Path $k).GetValueNames())
    $n = 0; $deja = 0
    foreach ($exe in @(Lister-ExeJeux)) {
      if ($exist -contains $exe) { $deja++; continue }
      try { Set-ItemProperty -Path $k -Name $exe -Value "GpuPreference=2;" -Type String -ErrorAction Stop; $n++ } catch { Echec "préférence graphique de $exe" }
    }
    if ($n -or $deja) { Ok "$n jeu(x) réglé(s) sur la carte graphique puissante$(if ($deja) { ", $deja déjà réglé(s) (laissés tels quels)" })." }
    else { Write-Host " - Aucun jeu Steam ou Epic trouvé : rien à régler." }
  }
}

if ($OptimLecteurs) {
  Etape "Optimiser les lecteurs"
  # Tâche Windows hebdomadaire (TRIM des SSD, défragmentation des disques durs) : réactivée si un autre outil l'a coupée
  $t = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue
  if (-not $t) { Write-Host " - Tâche « Optimiser les lecteurs » introuvable sur ce Windows." -ForegroundColor Yellow }
  elseif ("$($t.State)" -eq "Disabled") {
    try { [void](Enable-ScheduledTask -InputObject $t -ErrorAction Stop); Ok "Optimisation hebdomadaire des lecteurs réactivée (elle avait été coupée)." } catch { Echec "tâche « Optimiser les lecteurs » non réactivée." }
  } else { Ok "Optimisation hebdomadaire des lecteurs déjà active." }
  # Retrim tout de suite des SSD (sans effet sur les données ; les disques durs sont laissés à la tâche hebdomadaire)
  if (-not $TRIM) {
    $r = 0
    Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -match 'NTFS|ReFS' } | ForEach-Object {
      $lettre = $_.DriveLetter
      $disk = $_ | Get-Partition | Get-Disk | Get-PhysicalDisk
      if ("$($disk.MediaType)" -eq 'HDD') { return }
      if ("$($disk.BusType)" -match '(?i)USB|SD|MMC|1394|File Backed Virtual') { return }
      try { Optimize-Volume -DriveLetter $lettre -ReTrim -ErrorAction Stop; Ok "Retrim lancé sur $($lettre):"; $r++ } catch {}
    }
    if (-not $r) { Write-Host " - Aucun SSD à retrimer." }
  } else { Write-Host " - Retrim déjà lancé par « TRIM des SSD »." }
}

if ($Reparation) {
  Etape "Réparation des fichiers système (DISM + SFC, peut prendre 15 min)"
  DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | ForEach-Object { "$_" -replace "`0","" } | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*\[[=\s\d\.%]*\]\s*$' } | ForEach-Object { Write-Host "   $_" }
  $codeDism = $LASTEXITCODE
  sfc /scannow 2>&1 | ForEach-Object { "$_" -replace "`0","" } | Where-Object { $_ -match '\S' -and $_ -notmatch '\d+\s*%' } | ForEach-Object { Write-Host "   $_" }
  $codeSfc = $LASTEXITCODE
  if ($codeDism -ne 0) { Echec "DISM /RestoreHealth (code $codeDism)." }
  if ($codeSfc -ne 0) { Echec "SFC (code $codeSfc) : voir C:\Windows\Logs\CBS\CBS.log." }
  if (-not $codeDism -and -not $codeSfc) { Ok "Réparation terminée." }
}

Etape "Vérifications"
$mem = Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1
# v5.6 : vitesse ACTUELLE = ConfiguredClockSpeed seulement ; Speed = vitesse max annoncée (jamais présentée comme actuelle)
$ram = $mem.ConfiguredClockSpeed
if ($ram) { Write-Host " - Vitesse RAM actuelle : $ram MHz$(if ($mem.Speed) { " (max annoncée : $($mem.Speed) MHz)" })" }
elseif ($mem.Speed) { Write-Host " - Vitesse RAM actuelle : non communiquée par ce PC (max annoncée : $($mem.Speed) MHz)." }
else { Write-Host " - Vitesse RAM : non communiquée par ce PC." }
if (($mem.SMBIOSMemoryType -eq 26 -and $ram -and $ram -le 2666) -or ($mem.SMBIOSMemoryType -eq 34 -and $ram -and $ram -le 4800)) {
  Write-Host "   -> RAM à sa vitesse de base : active XMP/EXPO/DOCP dans le BIOS si ta RAM le permet." -ForegroundColor Yellow
}
if ($script:echecs) { Write-Host "`nOptimisation terminée avec $($script:echecs) échec(s) (détails ci-dessus). Redémarre le PC pour appliquer le reste." -ForegroundColor Red }
else { Write-Host "`nOptimisation terminée. Redémarre le PC pour tout appliquer." -ForegroundColor Green }
if (-not $NonInteractif) {
  Write-Host "Pour annuler : tape 'rstrui' dans Démarrer et choisis le point « Avant ... »."
  Read-Host "Appuie sur Entrée pour fermer"
}
if ($script:echecs) { exit 1 } else { exit 0 }
