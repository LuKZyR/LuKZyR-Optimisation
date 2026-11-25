param([string]$Fichier = "", [switch]$NonInteractif)
# LuKZyR Optimisation v5.14 - Réparer les réglages laissés par d'autres « optimiseurs »
# Peut être chargé (dot-source) par l'interface pour la DÉTECTION (lecture seule), ou lancé pour RÉPARER :
#   -NonInteractif -Fichier "C:\ProgramData\Lukzyr\a-reparer.json"   ({ "Reparer": [...], "Taches": [...] })
# Chaque valeur d'origine est sauvegardée AVANT modification (« Tout annuler » la remet).
# Règles : ne touche JAMAIS à Defender, Windows Update, l'Optimisation de la distribution (DoSvc), le Store, Xbox ni
# aux pilotes : leur état est seulement LU et affiché. Les tâches planifiées de Microsoft, des navigateurs et des
# antivirus ne sont jamais proposées ni désactivées.
$ErrorActionPreference = "SilentlyContinue"
if ($NonInteractif) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }
# Sauvegarde-Reglages.ps1 a aussi un paramètre -NonInteractif : on garde les nôtres
$garde = @{ Fichier = $Fichier; NonInteractif = $NonInteractif }
. (Join-Path $PSScriptRoot "Sauvegarde-Reglages.ps1")
$Fichier = $garde.Fichier; $NonInteractif = $garde.NonInteractif

$script:CleMM = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile|NetworkThrottlingIndex"
$script:ClePrio = "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl|Win32PrioritySeparation"
$script:CleSpectre = @("HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management|FeatureSettingsOverride", "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management|FeatureSettingsOverrideMask")
$script:ClePagefile = "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management|PagingFiles"
$script:BcdConnus = @("useplatformclock", "useplatformtick", "disabledynamictick", "tscsyncpolicy")
# Services utiles à Windows souvent coupés par des « optimiseurs » : démarrage Windows par défaut
$script:ServicesDefaut = [ordered]@{ SysMain = "Automatic"; WSearch = "AutomaticDelayedStart"; Spooler = "Automatic"; bthserv = "Manual"; Audiosrv = "Automatic"; AudioEndpointBuilder = "Automatic"; Themes = "Automatic" }
# Tâches jamais proposées : navigateurs (leurs mises à jour), sécurité, Microsoft / Windows / Office, LuKZyR
$script:RegexTachesExclues = '(?i)google|chrome|chromium|msedge|\bedge\b|brave|firefox|mozilla|opera|vivaldi|yandex|waterfox|librewolf|thorium|tor ?browser|microsoft|windows|onedrive|office|teams|lukzyr|' +
  'defender|avast|avg|avira|norton|symantec|mcafee|kaspersky|eset|bitdefender|malwarebytes|sophos|trend ?micro|f-secure|panda|comodo|webroot|g ?data|emsisoft|crowdstrike|sentinel|zonealarm|360 ?total|adaware'

function Lire-Bcd {
  $r = @{}
  foreach ($l in @(& bcdedit.exe /enum "{current}" 2>$null)) { if ("$l" -match '^\s*(useplatformclock|useplatformtick|disabledynamictick|tscsyncpolicy)\s+(\S+)') { $r[$matches[1].ToLower()] = $matches[2] } }
  return $r
}
function Taille-Pagefile {
  # $null = géré par Windows ou taille libre ; sinon taille maxi totale en Mo (0 = aucun fichier d'échange)
  $pf = Lire-ValeurReg $script:ClePagefile
  $lignes = @(@($pf.Valeur) | Where-Object { "$_".Trim() })
  if (-not $pf.Existe -or -not $lignes.Count) { return 0 }
  $total = 0
  foreach ($l in $lignes) {
    $t = @("$l".Trim() -split '\s+')
    if ($t[0] -like '`?:*') { return $null }
    if ($t.Count -ge 3 -and [int64]$t[2] -gt 0) { $total += [int64]$t[2] } else { return $null }
  }
  return $total
}

# --- Détection (lecture seule) : Id + valeur actuelle. Les textes sont faits par l'interface (traduits). ---
function Detecter-Problemes {
  $p = New-Object System.Collections.ArrayList
  $bcd = Lire-Bcd
  foreach ($n in $script:BcdConnus) { if ($bcd.ContainsKey($n)) { [void]$p.Add([pscustomobject]@{ Id = "bcd:$n"; Valeur = "$($bcd[$n])" }) } }
  $pf = Taille-Pagefile
  if ($null -ne $pf -and $pf -lt 1024) { [void]$p.Add([pscustomobject]@{ Id = "pagefile"; Valeur = "$pf" }) }
  foreach ($s in $script:ServicesDefaut.Keys) {
    $sv = Get-Service $s -ErrorAction SilentlyContinue
    if ($sv -and "$($sv.StartType)" -eq "Disabled") { [void]$p.Add([pscustomobject]@{ Id = "svc:$s"; Valeur = "Disabled" }) }
  }
  try { $m = Get-MMAgent -ErrorAction Stop; if ($m -and -not $m.MemoryCompression) { [void]$p.Add([pscustomobject]@{ Id = "mmagent"; Valeur = "0" }) } } catch {}
  $t = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue
  if ($t -and "$($t.State)" -eq "Disabled") { [void]$p.Add([pscustomobject]@{ Id = "tachedefrag"; Valeur = "Disabled" }) }
  $v = Lire-ValeurReg $script:CleMM
  # (DWORD lu comme entier signé : 0xFFFFFFFF = -1 ; 4294967295 = masque 32 bits)
  if ($v.Existe) { $nti = [int64]$v.Valeur -band 4294967295; if ($nti -ne 10) { [void]$p.Add([pscustomobject]@{ Id = "reg:nti"; Valeur = ("0x{0:X}" -f $nti) }) } }
  $v = Lire-ValeurReg $script:ClePrio
  if ($v.Existe -and [int64]$v.Valeur -notin @(2, 38)) { [void]$p.Add([pscustomobject]@{ Id = "reg:prio"; Valeur = ("{0} (0x{0:X})" -f [int64]$v.Valeur) }) }
  $v = Lire-ValeurReg $script:CleSpectre[0]
  if ($v.Existe -and [int64]$v.Valeur -in @(1, 3)) { [void]$p.Add([pscustomobject]@{ Id = "reg:spectre"; Valeur = "$($v.Valeur)" }) }
  return @($p)
}
# État de Defender / Windows Update / Optimisation de la distribution : LU seulement, jamais modifié
function Lire-EtatsProteges {
  $l = New-Object System.Collections.ArrayList
  foreach ($s in "wuauserv", "DoSvc") {
    $sv = Get-Service $s -ErrorAction SilentlyContinue
    if ($sv) { [void]$l.Add([pscustomobject]@{ Id = $s; Demarrage = "$($sv.StartType)"; Statut = "$($sv.Status)"; Ok = ("$($sv.StartType)" -ne "Disabled"); Antivirus = "" }) }
  }
  $av = @(); try { $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { "$($_.displayName)" } | Where-Object { $_ }) } catch {}
  $autres = @($av | Where-Object { $_ -notmatch '(?i)defender' })
  $wd = Get-Service WinDefend -ErrorAction SilentlyContinue
  $wdOk = $wd -and "$($wd.Status)" -eq "Running"
  [void]$l.Add([pscustomobject]@{ Id = "WinDefend"; Demarrage = "$($wd.StartType)"; Statut = "$($wd.Status)"; Ok = ($wdOk -or $autres.Count -gt 0); Antivirus = ($autres -join ", ") })
  return @($l)
}
# Tâches planifiées d'AUTRES éditeurs, actives (hors Microsoft, navigateurs, sécurité)
function Lister-TachesTierces {
  $l = New-Object System.Collections.ArrayList
  foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    if ("$($t.TaskPath)" -like '\Microsoft\*' -or "$($t.State)" -eq "Disabled") { continue }
    $exe = ""; foreach ($a in @($t.Actions)) { if ($a.Execute) { $exe = [Environment]::ExpandEnvironmentVariables("$($a.Execute)".Trim('"')); break } }
    $editeur = ""; if ($exe -and (Test-Path -LiteralPath $exe)) { try { $editeur = "$((Get-Item -LiteralPath $exe).VersionInfo.CompanyName)".Trim() } catch {} }
    if ("$($t.TaskName) $($t.TaskPath) $($t.Author) $exe $editeur" -match $script:RegexTachesExclues) { continue }
    $quand = @(foreach ($d in @($t.Triggers)) {
      switch -Regex ("$($d.CimClass.CimClassName)") { 'Logon' { "logon" } 'Boot' { "boot" } 'Daily|Weekly|Monthly' { "schedule" } 'Idle' { "idle" } 'Time' { "time" } 'Event' { "event" } default { "other" } }
    }) | Select-Object -Unique
    [void]$l.Add([pscustomobject]@{ Plein = "$($t.TaskPath)$($t.TaskName)"; Nom = "$($t.TaskName)"; Editeur = $editeur; Exe = $exe; Quand = @($quand) })
  }
  return @($l | Sort-Object Nom)
}

# --- Réparation (seulement les Id connus ci-dessus) ---
function Reparer-Element($id, $d) {
  switch -Wildcard ($id) {
    "bcd:*" {
      $n = $id.Substring(4); if ($script:BcdConnus -notcontains $n) { Write-Host " - Ignoré (inconnu) : $id"; return $false }
      $bcd = Lire-Bcd; if (-not $bcd.ContainsKey($n)) { Write-Host " - $n : déjà à la valeur de Windows."; return $true }
      # copie complète de la configuration de démarrage, une seule fois (bcdedit /import pour revenir en arrière à la main)
      $copie = Join-Path $env:ProgramData "Lukzyr\bcd-avant-reparation.bak"
      if (-not (Test-Path -LiteralPath $copie)) { & bcdedit.exe /export "$copie" 2>&1 | Out-Null }
      [void](Retenir-Special "bcd:$n" $bcd[$n] $d); Ecrire-Sauvegarde $d
      & bcdedit.exe /deletevalue "{current}" $n 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) { Write-Host " - Démarrage : « $n » remis à la valeur de Windows (effectif après redémarrage)." -ForegroundColor Green; return $true }
      Write-Host " - ÉCHEC : bcdedit /deletevalue $n (code $LASTEXITCODE)." -ForegroundColor Red; return $false
    }
    "pagefile" {
      [void](Retenir-Registre @($script:ClePagefile) $d); Ecrire-Sauvegarde $d
      $ok = $false
      try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop; Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop; $ok = $true } catch {}
      if (-not $ok) { try { Ecrire-ValeurReg $script:ClePagefile ([ordered]@{ Existe = $true; Type = "MultiString"; Valeur = @("?:\pagefile.sys") }); $ok = $true } catch {} }
      if ($ok) { Write-Host " - Fichier d'échange rendu à Windows (taille automatique, effectif après redémarrage)." -ForegroundColor Green } else { Write-Host " - ÉCHEC : fichier d'échange non modifié." -ForegroundColor Red }
      return $ok
    }
    "svc:*" {
      $s = $id.Substring(4); if (-not $script:ServicesDefaut.Contains($s)) { Write-Host " - Ignoré (service non prévu) : $s"; return $false }
      [void](Retenir-Service $s $d); Ecrire-Sauvegarde $d
      $mode = $script:ServicesDefaut[$s]
      if ($mode -eq "AutomaticDelayedStart") { & sc.exe config $s start= delayed-auto 2>&1 | Out-Null; $ok = ($LASTEXITCODE -eq 0) }
      else { try { Set-Service $s -StartupType $mode -ErrorAction Stop; $ok = $true } catch { $ok = $false } }
      if ($ok -and $mode -ne "Manual") { Start-Service $s -ErrorAction SilentlyContinue }
      if ($ok) { Write-Host " - Service $s remis au démarrage par défaut de Windows." -ForegroundColor Green } else { Write-Host " - ÉCHEC : service $s non modifié." -ForegroundColor Red }
      return $ok
    }
    "mmagent" {
      [void](Retenir-Special "mmagent" 0 $d); Ecrire-Sauvegarde $d
      try { Enable-MMAgent -MemoryCompression -ErrorAction Stop; Write-Host " - Compression de la mémoire réactivée (effectif après redémarrage)." -ForegroundColor Green; return $true }
      catch { Write-Host " - ÉCHEC : compression de la mémoire ($($_.Exception.Message))." -ForegroundColor Red; return $false }
    }
    "tachedefrag" {
      [void](Retenir-Special "tachedefrag" "Disabled" $d); Ecrire-Sauvegarde $d
      try { [void](Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction Stop); Write-Host " - Optimisation hebdomadaire des lecteurs réactivée." -ForegroundColor Green; return $true }
      catch { Write-Host " - ÉCHEC : tâche « Optimiser les lecteurs »." -ForegroundColor Red; return $false }
    }
    "reg:nti" {
      [void](Retenir-Registre @($script:CleMM) $d); Ecrire-Sauvegarde $d
      try { Ecrire-ValeurReg $script:CleMM ([ordered]@{ Existe = $true; Type = "DWord"; Valeur = 10 }); Write-Host " - NetworkThrottlingIndex remis à 10 (valeur de Windows)." -ForegroundColor Green; return $true }
      catch { Write-Host " - ÉCHEC : NetworkThrottlingIndex." -ForegroundColor Red; return $false }
    }
    "reg:prio" {
      [void](Retenir-Registre @($script:ClePrio) $d); Ecrire-Sauvegarde $d
      try { Ecrire-ValeurReg $script:ClePrio ([ordered]@{ Existe = $true; Type = "DWord"; Valeur = 2 }); Write-Host " - Priorité des processus remise à la valeur de Windows (2)." -ForegroundColor Green; return $true }
      catch { Write-Host " - ÉCHEC : Win32PrioritySeparation." -ForegroundColor Red; return $false }
    }
    "reg:spectre" {
      [void](Retenir-Registre $script:CleSpectre $d); Ecrire-Sauvegarde $d
      try { foreach ($c in $script:CleSpectre) { Ecrire-ValeurReg $c ([ordered]@{ Existe = $false }) }; Write-Host " - Protections du processeur (Spectre / Meltdown) rendues à Windows (effectif après redémarrage)." -ForegroundColor Green; return $true }
      catch { Write-Host " - ÉCHEC : protections du processeur." -ForegroundColor Red; return $false }
    }
    default { Write-Host " - Ignoré (inconnu) : $id"; return $false }
  }
}
function Desactiver-Tache($plein, $d) {
  if ("$plein" -like '\Microsoft\*' -or "$plein" -notlike '\*') { Write-Host " - Ignoré (tâche protégée) : $plein"; return $false }
  $i = $plein.LastIndexOf('\'); $chemin = $plein.Substring(0, $i + 1); $nom = $plein.Substring($i + 1)
  $t = Get-ScheduledTask -TaskPath $chemin -TaskName $nom -ErrorAction SilentlyContinue
  if (-not $t) { Write-Host " - Tâche introuvable (déjà supprimée ?) : $plein"; return $true }
  $exe = ""; foreach ($a in @($t.Actions)) { if ($a.Execute) { $exe = "$($a.Execute)"; break } }
  if ("$($t.TaskName) $($t.TaskPath) $($t.Author) $exe" -match $script:RegexTachesExclues) { Write-Host " - Ignoré (navigateur, sécurité ou Microsoft) : $plein"; return $false }
  if ("$($t.State)" -eq "Disabled") { Write-Host " - Déjà désactivée : $plein"; return $true }
  [void](Retenir-Special "tache:$plein" "$($t.State)" $d); Ecrire-Sauvegarde $d
  try { [void](Disable-ScheduledTask -InputObject $t -ErrorAction Stop); Write-Host " - Tâche désactivée : $plein" -ForegroundColor Green; return $true }
  catch { Write-Host " - ÉCHEC : tâche $plein ($($_.Exception.Message))." -ForegroundColor Red; return $false }
}

# --- Exécution directe ---
if ($MyInvocation.InvocationName -ne '.') {
  Write-Host "==> Réparation des réglages"
  if (-not $Fichier -or -not (Test-Path -LiteralPath $Fichier)) { Write-Host " - Rien à réparer (liste absente)."; exit 0 }
  $j = $null; try { $j = Get-Content -LiteralPath $Fichier -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
  if (-not $j) { Write-Host " - ÉCHEC : liste illisible ($Fichier)." -ForegroundColor Red; exit 1 }
  $d = Lire-Sauvegarde; $ko = 0
  foreach ($id in @($j.Reparer | Where-Object { $_ })) { Write-Host "==> $id"; if (-not (Reparer-Element "$id" $d)) { $ko++ } }
  foreach ($t in @($j.Taches | Where-Object { $_ })) { if (-not (Desactiver-Tache "$t" $d)) { $ko++ } }
  Ecrire-Sauvegarde $d
  Remove-Item -LiteralPath $Fichier -Force -ErrorAction SilentlyContinue
  Write-Host " - Defender, Windows Update et l'Optimisation de la distribution n'ont pas été touchés. Tout est annulable avec « Tout annuler »."
  if ($ko) { exit 1 } else { exit 0 }
}
