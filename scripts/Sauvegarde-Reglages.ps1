param([string]$Elements = "", [switch]$Sauvegarder, [switch]$Restaurer, [switch]$NonInteractif)
# LuKZyR Optimisation - « Tout annuler »
# Sauvegarde la valeur D'ORIGINE de chaque réglage que l'appli modifie, dans
# C:\ProgramData\Lukzyr\sauvegarde-reglages.json (la 1re valeur vue est gardée : un 2e passage
# ne l'écrase jamais), puis restaure tout à l'identique (valeurs absentes supprimées).
# Peut être chargé (dot-source) par l'interface ou lancé :
#   -Sauvegarder -Elements "optim:ModeJeu,debloat,..."   /   -Restaurer
$ErrorActionPreference = "SilentlyContinue"
if ($NonInteractif) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }
$script:FichierSauvegarde = Join-Path $env:ProgramData "Lukzyr\sauvegarde-reglages.json"

# --- Catalogue : ce que chaque réglage modifie (registre / services / spécial) ---
$script:CatalogueReglages = @{
  "optim:ModeJeu" = @{ Registre = @("HKCU\Software\Microsoft\GameBar|AutoGameModeEnabled", "HKCU\Software\Microsoft\GameBar|AllowAutoGameMode", "HKCU\System\GameConfigStore|GameDVR_Enabled", "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR|AppCaptureEnabled") }
  "optim:PlanifGPU" = @{ Registre = @("HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers|HwSchMode") }
  "optim:PrioriteJeux" = @{ Registre = @("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile|SystemResponsiveness", "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games|GPU Priority", "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games|Priority", "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games|Scheduling Category", "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games|SFIO Priority") }
  "optim:Souris" = @{ Registre = @("HKCU\Control Panel\Mouse|MouseSpeed", "HKCU\Control Panel\Mouse|MouseThreshold1", "HKCU\Control Panel\Mouse|MouseThreshold2") }
  "optim:VBS" = @{ Registre = @("HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity|Enabled", "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard|EnableVirtualizationBasedSecurity") }
  "optim:AssistantStockage" = @{ Registre = @("HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy|01") }
  "optim:Transparence" = @{ Registre = @("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize|EnableTransparency") }
  "optim:OptimDistribution" = @{ Registre = @("HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization|DODownloadMode", "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config|DODownloadMode") }
  "optim:Alimentation" = @{ Special = @("alimentation") }
  "optim:PlanEquilibre" = @{ Special = @("alimentation") }
  "optim:JeuxFenetres" = @{ Registre = @("HKCU\Software\Microsoft\DirectX\UserGpuPreferences|DirectXUserGlobalSettings") }
  "optim:VRR" = @{ Registre = @("HKCU\Software\Microsoft\DirectX\UserGpuPreferences|DirectXUserGlobalSettings") }
  "optim:EdgeArrierePlan" = @{ Registre = @("HKLM\SOFTWARE\Policies\Microsoft\Edge|StartupBoostEnabled", "HKLM\SOFTWARE\Policies\Microsoft\Edge|BackgroundModeEnabled") }
  "optim:DelaiDemarrage" = @{ Registre = @("HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize|StartupDelayInMSec", "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize|WaitForIdleState") }
  "optim:AppsArrierePlan" = @{ Registre = @("HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy|LetAppsRunInBackground") }
  "optim:Hibernation" = @{ Special = @("hibernation") }
  "optim:TRIM" = @{ Special = @("trim") }
  "debloat" = @{ Registre = @(
      "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SilentInstalledAppsEnabled", "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SystemPaneSuggestionsEnabled",
      "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-338388Enabled", "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-338389Enabled",
      "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-353694Enabled", "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-353696Enabled",
      "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-310093Enabled", "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SoftLandingEnabled",
      "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|RotatingLockScreenOverlayEnabled",
      "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|Start_IrisRecommendations", "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent|DisableWindowsConsumerFeatures",
      "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo|Enabled", "HKCU\Software\Microsoft\Windows\CurrentVersion\Search|BingSearchEnabled",
      "HKCU\Software\Policies\Microsoft\Windows\Explorer|DisableSearchBoxSuggestions", "HKLM\SOFTWARE\Policies\Microsoft\Dsh|AllowNewsAndInterests",
      "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds|EnableFeeds",
      "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|HideFileExt", "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|LaunchTo") }
  "telemetrie" = @{ Registre = @("HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry",
      "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy|TailoredExperiencesWithDiagnosticDataEnabled")
    Services = @("DiagTrack") }
  "copilot" = @{ Registre = @("HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot|TurnOffWindowsCopilot", "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowCopilotButton") }
  "restauration" = @{ Registre = @("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore|SystemRestorePointCreationFrequency") }
}

# --- Registre bas niveau (types exacts : DWord, String, Binary, MultiString...) ---
function Ouvrir-Cle($chemin, [bool]$ecriture, [bool]$creer) {
  $racine, $sous = $chemin -split '\\', 2
  $base = switch ($racine) { "HKCU" { [Microsoft.Win32.Registry]::CurrentUser } "HKLM" { [Microsoft.Win32.Registry]::LocalMachine } default { $null } }
  if (-not $base) { return $null }
  if ($creer) { return $base.CreateSubKey($sous) }
  return $base.OpenSubKey($sous, $ecriture)
}
function Lire-ValeurReg($id) {
  $chemin, $nom = $id -split '\|', 2
  $k = Ouvrir-Cle $chemin $false $false
  if (-not $k) { return [ordered]@{ Existe = $false } }
  try {
    if (@($k.GetValueNames()) -notcontains $nom) { return [ordered]@{ Existe = $false } }
    $type = $k.GetValueKind($nom).ToString()
    $v = $k.GetValue($nom, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    if ($v -is [byte[]]) { $v = [Convert]::ToBase64String($v); $type = "Binary" }
    elseif ($v -is [string[]]) { $v = @($v) }
    return [ordered]@{ Existe = $true; Type = $type; Valeur = $v }
  } finally { $k.Close() }
}
function Ecrire-ValeurReg($id, $etat) {
  $chemin, $nom = $id -split '\|', 2
  if (-not $etat.Existe) {
    $k = Ouvrir-Cle $chemin $true $false
    if ($k) { try { if (@($k.GetValueNames()) -contains $nom) { $k.DeleteValue($nom, $false) } } finally { $k.Close() } }
    return
  }
  $k = Ouvrir-Cle $chemin $true $true
  try {
    $kind = [Microsoft.Win32.RegistryValueKind]$etat.Type
    # (pas de « switch » ici : il déroulerait les tableaux d'octets)
    if ($etat.Type -eq "DWord") { $k.SetValue($nom, [int]$etat.Valeur, $kind) }
    elseif ($etat.Type -eq "QWord") { $k.SetValue($nom, [long]$etat.Valeur, $kind) }
    elseif ($etat.Type -eq "Binary") { [byte[]]$octets = [Convert]::FromBase64String([string]$etat.Valeur); $k.SetValue($nom, $octets, $kind) }
    elseif ($etat.Type -eq "MultiString") { [string[]]$lignes = @($etat.Valeur); $k.SetValue($nom, $lignes, $kind) }
    else { $k.SetValue($nom, [string]$etat.Valeur, $kind) }
  } finally { $k.Close() }
}

# --- Fichier de sauvegarde ---
function Lire-Sauvegarde {
  $s = $null
  if (Test-Path $script:FichierSauvegarde) { try { $s = Get-Content $script:FichierSauvegarde -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $s = $null } }
  $d = [ordered]@{ Version = 1; Creee = (Get-Date -Format s); Registre = [ordered]@{}; Services = [ordered]@{}; Speciaux = [ordered]@{}; Dns = [ordered]@{} }
  if ($s) {
    if ($s.Creee) { $d.Creee = $s.Creee }
    foreach ($sec in "Registre", "Services", "Speciaux", "Dns") {
      if ($s.$sec) { foreach ($p in $s.$sec.PSObject.Properties) { $d[$sec][$p.Name] = $p.Value } }
    }
  }
  return $d
}
function Ecrire-Sauvegarde($d) {
  [void](New-Item -ItemType Directory -Force (Split-Path $script:FichierSauvegarde))
  [IO.File]::WriteAllText($script:FichierSauvegarde, ($d | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
}
function Sauvegarde-Vide { $d = Lire-Sauvegarde; return -not ($d.Registre.Count + $d.Services.Count + $d.Speciaux.Count + $d.Dns.Count) }

# Retient l'état actuel d'une liste de valeurs de registre (uniquement si pas déjà retenu)
function Retenir-Registre([string[]]$ids, $d = $null) {
  $ecrire = -not $d; if (-not $d) { $d = Lire-Sauvegarde }
  $n = 0
  foreach ($id in $ids) { if (-not $d.Registre.Contains($id)) { $d.Registre[$id] = Lire-ValeurReg $id; $n++ } }
  if ($ecrire) { Ecrire-Sauvegarde $d }
  return $n
}
function Lire-Special($nom) {
  switch ($nom) {
    "alimentation" { if ("$(powercfg /getactivescheme)" -match '([0-9a-f]{8}-[0-9a-f\-]{27})') { return $matches[1] } }
    "hibernation"  {
      # v5.6 : valeur absente = on regarde si le fichier d'hibernation existe (sinon l'annulation pourrait la couper à tort)
      $pw = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
      if ($pw -and @($pw.PSObject.Properties.Name) -contains "HibernateEnabled") { return [int]([bool]$pw.HibernateEnabled) }
      return [int](Test-Path -LiteralPath "$env:SystemDrive\hiberfil.sys")
    }
    "trim"         { if ("$(fsutil behavior query DisableDeleteNotify)" -match 'NTFS DisableDeleteNotify\s*=\s*(\d)') { return [int]$matches[1] } }
  }
  return $null
}
# Sauvegarde les originaux des éléments demandés (clés du catalogue)
function Sauvegarder-Elements([string[]]$elements) {
  $d = Lire-Sauvegarde; $n = 0
  foreach ($e in @($elements + "restauration")) {
    $c = $script:CatalogueReglages[$e]; if (-not $c) { continue }
    if ($c.Registre) { $n += Retenir-Registre $c.Registre $d }
    foreach ($s in @($c.Services)) { if ($s -and -not $d.Services.Contains($s)) { $sv = Get-Service $s; if ($sv) { $d.Services[$s] = "$($sv.StartType)"; $n++ } } }
    foreach ($sp in @($c.Speciaux + $c.Special)) { if ($sp -and -not $d.Speciaux.Contains($sp)) { $v = Lire-Special $sp; if ($null -ne $v) { $d.Speciaux[$sp] = $v; $n++ } } }
  }
  Ecrire-Sauvegarde $d
  return $n
}
# DNS : retient les serveurs configurés à la main (vide = automatique/DHCP) de chaque carte
function Retenir-Dns($cartes) {
  $d = Lire-Sauvegarde
  foreach ($a in $cartes) {
    $g = "$($a.InterfaceGuid)"; if ($d.Dns.Contains($g)) { continue }
    $v4 = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$g" -Name NameServer).NameServer
    $v6 = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$g" -Name NameServer).NameServer
    $d.Dns[$g] = [ordered]@{ Nom = "$($a.Name)"; IPv4 = "$v4"; IPv6 = "$v6" }
  }
  Ecrire-Sauvegarde $d
}

# v5.6 : DNS d'UNE famille (ipv4 / ipv6) d'une carte : liste vide = automatique (DHCP / FAI). L'autre famille n'est pas touchée.
function Regler-DnsFamille($index, $famille, [string[]]$serveurs) {
  $serveurs = @($serveurs | Where-Object { $_ })
  if (-not $serveurs.Count) { netsh interface $famille set dnsservers name=$index source=dhcp 2>&1 | Out-Null; return ($LASTEXITCODE -eq 0) }
  netsh interface $famille set dnsservers name=$index source=static address=$($serveurs[0]) register=primary validate=no 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { return $false }
  for ($i = 1; $i -lt $serveurs.Count; $i++) { netsh interface $famille add dnsservers name=$index address=$($serveurs[$i]) index=$($i + 1) validate=no 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { return $false } }
  return $true
}

# Résumé lisible de ce qui sera restauré (pour la confirmation)
function Resume-Sauvegarde {
  $d = Lire-Sauvegarde; $l = New-Object System.Collections.ArrayList
  foreach ($k in $d.Registre.Keys) {
    $e = $d.Registre[$k]; $chemin, $nom = $k -split '\|', 2
    $txt = if ($e.Existe) { "= " + $(if ($e.Valeur -is [array]) { $e.Valeur -join ';' } else { "$($e.Valeur)" }) } else { "(supprimée, absente à l'origine)" }
    [void]$l.Add("Registre : $(Split-Path $chemin -Leaf)\$nom $txt")
  }
  foreach ($k in $d.Services.Keys) { [void]$l.Add("Service $k : démarrage $($d.Services[$k])") }
  foreach ($k in $d.Speciaux.Keys) {
    $v = $d.Speciaux[$k]
    [void]$l.Add($(switch ($k) { "alimentation" { "Plan d'alimentation d'origine ($v)" } "hibernation" { "Hibernation : $(if ($v) { 'activée' } else { 'désactivée' })" } "trim" { "TRIM (DisableDeleteNotify = $v)" } default { "$k = $v" } }))
  }
  foreach ($k in $d.Dns.Keys) { $e = $d.Dns[$k]; [void]$l.Add("DNS de « $($e.Nom) » : $(if ("$($e.IPv4)$($e.IPv6)".Trim()) { "$($e.IPv4) $($e.IPv6)".Trim() } else { 'automatique (FAI)' })") }
  return $l
}

# Restaure tout, puis vide la sauvegarde (un nouveau passage repart de l'état restauré)
function Restaurer-Tout {
  $d = Lire-Sauvegarde; $ok = 0; $ko = 0
  foreach ($k in $d.Registre.Keys) {
    try { Ecrire-ValeurReg $k $d.Registre[$k]; $ok++ } catch { $ko++; Write-Host " - Échec registre $k : $($_.Exception.Message)" -ForegroundColor Red }
  }
  foreach ($s in $d.Services.Keys) {
    try { Set-Service $s -StartupType $d.Services[$s] -ErrorAction Stop; if ($d.Services[$s] -ne "Disabled") { Start-Service $s }; $ok++ } catch { $ko++; Write-Host " - Échec service $s" -ForegroundColor Red }
  }
  foreach ($k in $d.Speciaux.Keys) {
    $v = $d.Speciaux[$k]
    switch ($k) {
      "alimentation" {
        powercfg -setactive $v 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $ok++ } else { $ko++; Write-Host " - Échec : plan d'alimentation $v introuvable." -ForegroundColor Red }
        # v5.6 : supprime le plan « Performances élevées » que l'appli avait dû recréer (repéré par son GUID, jamais par son nom)
        $fc = Join-Path (Split-Path $script:FichierSauvegarde) "plan-cree.txt"
        if (Test-Path $fc) {
          $g = "$(Get-Content $fc -Raw)".Trim()
          if ($g -match '^[0-9a-fA-F\-]{36}$' -and $g -ne "$v" -and "$(powercfg /getactivescheme)" -notmatch [regex]::Escape($g)) { powercfg -delete $g 2>&1 | Out-Null }
          Remove-Item $fc -Force
        }
      }
      "hibernation"  {
        if ([int]$v) { powercfg -h on 2>&1 | Out-Null } else { powercfg -h off 2>&1 | Out-Null }
        if ($LASTEXITCODE -eq 0) { $ok++ } else { $ko++; Write-Host " - Échec : hibernation non remise (powercfg code $LASTEXITCODE)." -ForegroundColor Red }
      }
      "trim"         {
        fsutil behavior set DisableDeleteNotify ([int]$v) | Out-Null
        if ($LASTEXITCODE -eq 0) { $ok++ } else { $ko++; Write-Host " - Échec : TRIM non remis (fsutil code $LASTEXITCODE)." -ForegroundColor Red }
      }
    }
  }
  foreach ($g in $d.Dns.Keys) {
    $e = $d.Dns[$g]; $a = Get-NetAdapter | Where-Object { "$($_.InterfaceGuid)" -eq $g }
    if (-not $a) { $ko++; continue }
    # v5.6 : IPv4 et IPv6 remis SÉPARÉMENT (une famille vide = automatique pour cette famille seulement)
    $r4 = Regler-DnsFamille $a.ifIndex "ipv4" @("$($e.IPv4)" -split '[,\s]+' | Where-Object { $_ })
    $r6 = Regler-DnsFamille $a.ifIndex "ipv6" @("$($e.IPv6)" -split '[,\s]+' | Where-Object { $_ })
    if ($r4 -and $r6) { $ok++ } else { $ko++; Write-Host " - Échec DNS sur « $($e.Nom) » (IPv4 : $(if ($r4) { 'OK' } else { 'échec' }), IPv6 : $(if ($r6) { 'OK' } else { 'échec' }))." -ForegroundColor Red }
  }
  if ($d.Dns.Count) { Clear-DnsClientCache }
  if (-not $ko) { Remove-Item $script:FichierSauvegarde -Force }
  else { Write-Host " - $ko élément(s) non restauré(s) : la sauvegarde est conservée." -ForegroundColor Yellow }
  return @{ Ok = $ok; Ko = $ko }
}

# --- Exécution directe ---
if ($MyInvocation.InvocationName -ne '.') {
  if ($Sauvegarder) {
    Write-Host "==> Sauvegarde des réglages d'origine (pour « Tout annuler »)"
    $n = Sauvegarder-Elements @($Elements -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not (Test-Path $script:FichierSauvegarde)) { Write-Host " - ÉCHEC : impossible d'écrire $script:FichierSauvegarde." -ForegroundColor Red; exit 1 }
    Write-Host " - $n nouvelle(s) valeur(s) d'origine retenue(s) dans $script:FichierSauvegarde (les originaux déjà retenus ne sont jamais écrasés)."
  }
  if ($Restaurer) {
    Write-Host "==> Restauration des réglages d'origine"
    if (Sauvegarde-Vide) { Write-Host " - Rien à restaurer (aucune sauvegarde)." }
    else { $r = Restaurer-Tout; Write-Host " - $($r.Ok) réglage(s) restauré(s), $($r.Ko) échec(s). Redémarre le PC pour tout appliquer."; if ($r.Ko) { exit 1 } }
  }
}
