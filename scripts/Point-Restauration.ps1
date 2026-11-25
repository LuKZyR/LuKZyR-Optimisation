param([switch]$NonInteractif, [string]$Description = "Avant LuKZyR Optimisation")
# Crée UN point de restauration (appelé une seule fois par l'interface avant d'appliquer).
# v5.6 : code de sortie 0 = point créé, 1 = échec (l'interface demande alors s'il faut continuer).
# v5.14 : 0 = point VRAIMENT créé maintenant (nouveau numéro de séquence) ; 2 = pas de nouveau point, mais un point
# « $Description » de moins de 10 min existe : il est réutilisé, et c'est dit clairement ; 1 = échec.
# La fréquence minimale entre deux points (SystemRestorePointCreationFrequency) est d'abord retenue
# pour « Tout annuler », mise à 0 le temps de créer le point, puis remise AUSSITÔT à sa valeur d'origine
# (supprimée si elle était absente) : Windows garde son délai normal de 24 h entre deux points automatiques.
$ErrorActionPreference = "SilentlyContinue"
if ($NonInteractif) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }
Write-Host "==> Point de restauration"
$cle = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
$nom = "SystemRestorePointCreationFrequency"
# 1. valeur d'origine retenue pour « Tout annuler » AVANT toute écriture (dans tous les cas, même installation d'applis seule)
$sauv = Join-Path $PSScriptRoot "Sauvegarde-Reglages.ps1"
if (Test-Path $sauv) { & $sauv -Sauvegarder -NonInteractif -Elements "restauration" *> $null }
$k = Get-Item $cle
$avait = $k -and (@($k.GetValueNames()) -contains $nom)
$orig = if ($avait) { $k.GetValue($nom) } else { $null }
$ok = $false; $err = ""; $reutilise = $null
function Sequence-Max { $m = 0; foreach ($p in @(Get-ComputerRestorePoint)) { if ([int64]$p.SequenceNumber -gt $m) { $m = [int64]$p.SequenceNumber } }; return $m }
try {
  Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
  if (-not (Test-Path $cle)) { New-Item -Path $cle -Force | Out-Null }
  Set-ItemProperty -Path $cle -Name $nom -Value 0 -Type DWord -ErrorAction Stop
  $seqAvant = Sequence-Max
  Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable avert -WarningAction SilentlyContinue
  # Checkpoint-Computer peut « réussir » sans rien créer (avertissement) : réussite seulement si un point AU NUMÉRO
  # PLUS GRAND qu'avant existe (un ancien point du même nom ne compte plus comme « créé »)
  if ((Sequence-Max) -gt $seqAvant) { $ok = $true }
  elseif ($avert) { $err = "$avert" } else { $err = "aucun nouveau point trouvé" }
} catch { $err = $_.Exception.Message }
if (-not $ok) {
  $rec = @(Get-ComputerRestorePoint | Where-Object { $_.Description -eq $Description -and $_.ConvertToDateTime($_.CreationTime) -gt (Get-Date).AddMinutes(-10) } | Sort-Object SequenceNumber -Descending)
  if ($rec.Count) { $reutilise = $rec[0].ConvertToDateTime($rec[0].CreationTime) }
}
# 2. fréquence remise aussitôt à l'identique
try {
  if ($avait) { Set-ItemProperty -Path $cle -Name $nom -Value ([int]$orig) -Type DWord -ErrorAction Stop }
  else { Remove-ItemProperty -Path $cle -Name $nom -ErrorAction SilentlyContinue }
} catch { Write-Host "ATTENTION : la fréquence des points de restauration n'a pas pu être remise ($($_.Exception.Message)). « Tout annuler » la remettra." -ForegroundColor Yellow }
if ($ok) { Write-Host "Point de restauration « $Description » créé." -ForegroundColor Green }
elseif ($reutilise) {
  Write-Host "Aucun nouveau point créé ($err)." -ForegroundColor Yellow
  Write-Host "Le point « $Description » créé à $($reutilise.ToString('HH:mm')) (il y a $([math]::Max(0, [int]((Get-Date) - $reutilise).TotalMinutes)) min) est RÉUTILISÉ : il protège aussi ces changements." -ForegroundColor Yellow
}
else {
  Write-Host "ÉCHEC : le point de restauration n'a pas pu être créé ($err)." -ForegroundColor Red
  Write-Host "Vérifie que la Protection du système est activée sur $env:SystemDrive et qu'il reste de la place sur le disque." -ForegroundColor Yellow
}
if (-not $NonInteractif) { Read-Host "Appuie sur Entrée pour fermer" }
if ($ok) { exit 0 } elseif ($reutilise) { exit 2 } else { exit 1 }
