param([switch]$NonInteractif, [string]$Description = "Avant HelixFlux Optimisation")
# Crée UN point de restauration (appelé une seule fois par l'interface avant d'appliquer)
$ErrorActionPreference = "SilentlyContinue"
if ($NonInteractif) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }
Write-Host "==> Point de restauration"
Enable-ComputerRestore -Drive "$env:SystemDrive\"
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency /t REG_DWORD /d 0 /f | Out-Null
$avant = @(Get-ComputerRestorePoint).Count
Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction SilentlyContinue -ErrorVariable errPR
$apres = @(Get-ComputerRestorePoint).Count
if ($apres -gt $avant) { Write-Host "Point de restauration « $Description » créé." }
else { Write-Host "ATTENTION : le point de restauration n'a pas pu être créé. $errPR" }
if (-not $NonInteractif) { Read-Host "Appuie sur Entrée pour fermer" }
