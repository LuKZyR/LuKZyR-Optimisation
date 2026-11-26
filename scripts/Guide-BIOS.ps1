param([switch]$Exporter, [switch]$SansOuvrir)
# =====================================================================
#  LUKZYR OPTIMISATION v0.1 bêta  -  Guide BIOS personnalisé
#  Détecte la carte mère (et CPU, RAM, GPU, UEFI, Secure Boot, TPM)
#  puis écrit un guide adapté à CE PC. Ne modifie jamais le BIOS.
#
#  Utilisation :
#   . .\Guide-BIOS.ps1                -> charge les fonctions (interface, tests)
#     $m = Lire-MaterielBios ; Get-GuideBios $m ; Get-ProfilBios $m
#   .\Guide-BIOS.ps1                  -> affiche le guide dans la console
#   .\Guide-BIOS.ps1 -Exporter        -> écrit Guide-BIOS-<modèle>.txt sur le Bureau et l'ouvre
# =====================================================================

# Valeur vide / bidon -> ""
function Nettoyer-Valeur($v) {
  if ($null -eq $v) { return "" }
  $s = ("$v" -replace '\s+', ' ').Trim()
  if ($s -match '^(To be filled( by O\.?E\.?M\.?)?|Default string|System (Product Name|manufacturer|Version)|O\.?E\.?M\.?|Not Applicable|N/?A|None|Unknown|Base Board.*|Type2 - Board.*|x+|0+|-+|\.+)$') { return "" }
  return $s
}

# v5.17 : typologie CPU / machine virtuelle / type de RAM (guide + interface)
function Est-Virtuel($m) {
  if (-not $m) { return $false }
  $s = @(
    $(if ($m.Cpu) { "$($m.Cpu.Name) $($m.Cpu.Manufacturer)" } else { "" })
    $(if ($m.Board) { "$($m.Board.Manufacturer) $($m.Board.Product)" } else { "" })
    $(if ($m.Bios) { "$($m.Bios.Manufacturer) $($m.Bios.SMBIOSBIOSVersion) $($m.Bios.Version)" } else { "" })
    $(if ($m.Systeme) { "$($m.Systeme.Manufacturer) $($m.Systeme.Model)" } else { "" })
    $(if ($m.Gpus) { @($m.Gpus | ForEach-Object { "$($_.Name) $($_.AdapterCompatibility)" }) -join " " } else { "" })
  ) -join " "
  if ($s -match '(?i)QEMU|TCG CPU|KVM|Bochs|SeaBIOS|OVMF|\bedk2\b|VirtualBox|innotek|VMware|Hyper-V|Virtual Machine|Xen\b|BHYVE|Parallels|Virtual CPU|Standard PC \(Q35|Standard PC \(i440FX|Virtio|Red Hat QXL') { return $true }
  if ($m.Systeme -and "$($m.Systeme.Model)" -match '(?i)Virtual Machine|HVM|Google Compute|Amazon EC2') { return $true }
  return $false
}

function Classer-Cpu($cpu) {
  $r = [pscustomobject]@{ Marque = ""; Famille = ""; Virtuel = $false; Hybride = $false; X3D = $false; RyzenSerie = 0; IntelGen = 0; Arm = $false; Nom = "" }
  if (-not $cpu) { return $r }
  $nom = ("$($cpu.Name)" -replace '\s+', ' ').Trim()
  $fab = "$($cpu.Manufacturer)"
  $cm = "$fab $nom"
  $r.Nom = $nom
  $r.Virtuel = ($cm -match '(?i)QEMU|TCG CPU|KVM|Bochs|Virtual CPU|VirtualBox|VMware|Hyper-V|Xen\b')
  $r.Arm = ($cm -match '(?i)\bARM\b|Snapdragon|Qualcomm|Ampere|Apple M\d|SQ\d') -or ("$env:PROCESSOR_ARCHITECTURE" -eq "ARM64") -or ("$env:PROCESSOR_ARCHITEW6432" -eq "ARM64")
  if ($r.Arm) { $r.Marque = "ARM"; $r.Famille = "ARM" }
  elseif ($cm -match '(?i)GenuineIntel|Intel|Core Ultra|\bi[3579]-|Pentium|Celeron|Xeon|\bAtom\b') { $r.Marque = "Intel" }
  elseif ($cm -match '(?i)AuthenticAMD|\bAMD\b|Ryzen|Threadripper|Athlon|EPYC|Phenom|Sempron') { $r.Marque = "AMD" }
  $r.X3D = $nom -match 'X3D'
  if ($nom -match '(?i)Ryzen\s+(?:Threadripper\s+)?(?:PRO\s+)?(?:[3579]\s+)?(?:PRO\s+)?(\d)(\d{3})') { $r.RyzenSerie = [int]$matches[1] * 1000 }
  elseif ($nom -match '(?i)Threadripper\s+(?:PRO\s+)?(\d)(\d{3})') { $r.RyzenSerie = [int]$matches[1] * 1000 }
  elseif ($nom -match '(?i)Ryzen\s+AI') { $r.RyzenSerie = 200 }
  if ($nom -match 'i[3579]-(\d{2})\d{3}') { $r.IntelGen = [int]$matches[1] }
  elseif ($nom -match 'i[3579]-(\d)\d{3}') { $r.IntelGen = [int]$matches[1] }
  elseif ($nom -match '(?i)Ultra\s+\d+\s+(\d)') { $r.IntelGen = [int]$matches[1] }
  $ultra = $nom -match '(?i)Core(?:\((TM|R)\))?\s*Ultra'
  $r.Hybride = ($r.Marque -eq "Intel" -and ($r.IntelGen -ge 12 -or $ultra))
  if ($r.Marque -eq "AMD" -and $nom -match '(?i)Ryzen|Threadripper|EPYC') {
    if ($nom -match '(?i)Threadripper') { $r.Famille = "Threadripper" }
    elseif ($r.X3D) { $r.Famille = "X3D" }
    elseif ($nom -match '(?i)\bAI\b|\b\d{3,4}G\b|\bHX\b|\bHS\b|\bGE\b') { $r.Famille = "APU" }
    elseif ($nom -match '(?i)EPYC') { $r.Famille = "EPYC" }
    else { $r.Famille = "Ryzen" }
  } elseif ($r.Marque -eq "Intel") {
    $r.Famille = if ($ultra) { "Core Ultra" } elseif ($r.Hybride) { "Intel hybride" } else { "Intel" }
  }
  return $r
}

function Type-Ram($code) {
  try { $n = [int]$code } catch { return "" }
  switch ($n) {
    20 { "DDR" } 21 { "DDR2" } 24 { "DDR3" } 26 { "DDR4" } 27 { "DDR4" }
    28 { "LPDDR" } 29 { "LPDDR2" } 30 { "LPDDR3" } 31 { "LPDDR4" } 32 { "LPDDR4X" }
    34 { "DDR5" } 35 { "LPDDR5" } 36 { "LPDDR5X" }
    default { "" }
  }
}

function Marque-Disque($n) {
  $s = "$n"
  if ($s -match '(?i)Samsung') { "Samsung" }
  elseif ($s -match '(?i)CT\d|Crucial|Micron') { "Crucial" }
  elseif ($s -match '(?i)\bWD\b|Western Digital|SanDisk|WD[_ ]?(BLACK|BLUE|RED|GREEN|SN\d)') { "WD" }
  elseif ($s -match '(?i)Kingston|SA400|SNV2|KC\d|NV2|NV3') { "Kingston" }
  elseif ($s -match '(?i)Seagate|ST\d|FireCuda|BarraCuda') { "Seagate" }
  elseif ($s -match '(?i)Kioxia|Toshiba|OCZ') { "Kioxia" }
  elseif ($s -match '(?i)SK\s?Hynix|Hynix|Solidigm') { "SK Hynix" }
  elseif ($s -match '(?i)ADATA|XPG') { "ADATA" }
  elseif ($s -match '(?i)Corsair|MP600|MP400') { "Corsair" }
  elseif ($s -match '(?i)Sabrent') { "Sabrent" }
  elseif ($s -match '(?i)\bPNY\b') { "PNY" }
  elseif ($s -match '(?i)Teamgroup|T-Force|\bT-CREATE') { "TeamGroup" }
  elseif ($s -match '(?i)Silicon Power|SPCC') { "Silicon Power" }
  elseif ($s -match '(?i)Lexar') { "Lexar" }
  elseif ($s -match '(?i)Intel SSD|INTEL SSD') { "Intel" }
  else { "" }
}


# ---------------------------------------------------------------------
# 1) Lecture du matériel (Windows). Chaque mesure est protégée : une
#    erreur donne simplement "inconnu".
# ---------------------------------------------------------------------
function Lire-MaterielBios {
  $m = [ordered]@{}
  $m.Board    = try { Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1 } catch { $null }
  $m.Bios     = try { Get-CimInstance Win32_BIOS -ErrorAction Stop | Select-Object -First 1 } catch { $null }
  $m.Cpu      = try { Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 } catch { $null }
  $m.Mems     = try { @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop) } catch { @() }
  $m.Gpus     = try { @(Get-CimInstance Win32_VideoController -ErrorAction Stop) } catch { @() }
  $m.Systeme  = try { Get-CimInstance Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1 } catch { $null }
  # v5.6 : un onduleur (UPS) branché en USB apparaît aussi comme « batterie » : il est ignoré
  $m.Batterie = try { [bool]@(Get-CimInstance Win32_Battery -ErrorAction Stop | Where-Object { "$($_.Name) $($_.DeviceID)" -notmatch 'UPS|APC|Eaton|CyberPower|Back-?UPS|Onduleur|Smart-UPS' }).Count } catch { $false }
  $m.Chassis  = try { @((Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop | Select-Object -First 1).ChassisTypes) } catch { @() }
  # UEFI ou Legacy : Windows fournit la variable d'environnement firmware_type
  $fw = "$env:firmware_type"
  if (-not $fw) { try { if ((bcdedit /enum "{current}" 2>$null) -match 'winload\.efi') { $fw = "UEFI" } elseif ((bcdedit /enum "{current}" 2>$null) -match 'winload\.exe') { $fw = "Legacy" } } catch {} }
  $m.Firmware = $fw
  # Secure Boot : lève une erreur en mode Legacy (ou sans droits admin)
  $m.SecureBoot = try { [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $null }
  # TPM
  $m.Tpm = $null
  try {
    $t = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction Stop | Select-Object -First 1
    if ($t) { $m.Tpm = [pscustomobject]@{ Present = $true; Actif = [bool]$t.IsEnabled_InitialValue; Version = ("$($t.SpecVersion)" -split ',')[0].Trim() } }
    else { $m.Tpm = [pscustomobject]@{ Present = $false; Actif = $false; Version = "" } }
  } catch {
    try { $g = Get-Tpm -ErrorAction Stop; $m.Tpm = [pscustomobject]@{ Present = [bool]$g.TpmPresent; Actif = [bool]$g.TpmReady; Version = "" } } catch {}
  }
  # Resizable BAR : détectable seulement sur NVIDIA (nvidia-smi : BAR1 > 256 Mo = actif)
  $m.ReBar = $null
  try {
    $smi = Get-Command nvidia-smi -ErrorAction Stop
    $q = & $smi.Source -q -d MEMORY 2>$null
    $i = [array]::FindIndex([string[]]$q, [Predicate[string]]{ param($l) $l -match 'BAR1 Memory Usage' })
    if ($i -ge 0 -and "$($q[$i+1])" -match '(\d+)\s*MiB') { $m.ReBar = ([int]$matches[1] -gt 256) }
  } catch {}
  return [pscustomobject]$m
}

# ---------------------------------------------------------------------
# 2) Chipsets connus (déduits du nom de la carte mère)
# ---------------------------------------------------------------------
$script:Chipsets = @{
  # AMD AM4
  "A320" = @("AMD", "AM4", "DDR4", "Entrée de gamme : la RAM peut rester bridée selon la carte ; Resizable BAR rarement proposé.")
  "B350" = @("AMD", "AM4", "DDR4", ""); "X370" = @("AMD", "AM4", "DDR4", "")
  "B450" = @("AMD", "AM4", "DDR4", "Resizable BAR ajouté par mise à jour du BIOS sur beaucoup de cartes (avec un Ryzen 3000/5000).")
  "X470" = @("AMD", "AM4", "DDR4", "Resizable BAR ajouté par mise à jour du BIOS sur beaucoup de cartes (avec un Ryzen 3000/5000).")
  "A520" = @("AMD", "AM4", "DDR4", ""); "B550" = @("AMD", "AM4", "DDR4", ""); "X570" = @("AMD", "AM4", "DDR4", "")
  # AMD AM5
  "A620" = @("AMD", "AM5", "DDR5", "Pas d'overclocking du processeur sur A620 (PBO souvent absent)."); "B650" = @("AMD", "AM5", "DDR5", "")
  "B650E" = @("AMD", "AM5", "DDR5", ""); "X670" = @("AMD", "AM5", "DDR5", ""); "X670E" = @("AMD", "AM5", "DDR5", "")
  "B840" = @("AMD", "AM5", "DDR5", ""); "B850" = @("AMD", "AM5", "DDR5", ""); "X870" = @("AMD", "AM5", "DDR5", ""); "X870E" = @("AMD", "AM5", "DDR5", ""); "A620E" = @("AMD", "AM5", "DDR5", "Pas d'overclocking du processeur sur A620 (PBO souvent absent).")
  "X399" = @("AMD", "TR4", "DDR4", ""); "TRX40" = @("AMD", "sTRX4", "DDR4", ""); "TRX50" = @("AMD", "sTR5", "DDR5", ""); "WRX90" = @("AMD", "sTR5", "DDR5", "")
  # Intel
  "H310" = @("Intel", "LGA1151", "DDR4", "Fréquence RAM limitée par le chipset (XMP souvent bloqué)."); "B360" = @("Intel", "LGA1151", "DDR4", "Fréquence RAM limitée par le chipset (XMP souvent bloqué)."); "B365" = @("Intel", "LGA1151", "DDR4", "Fréquence RAM limitée par le chipset (XMP souvent bloqué)."); "H370" = @("Intel", "LGA1151", "DDR4", "Fréquence RAM limitée par le chipset (XMP souvent bloqué).")
  "Z370" = @("Intel", "LGA1151", "DDR4", ""); "Z390" = @("Intel", "LGA1151", "DDR4", "")
  "H410" = @("Intel", "LGA1200", "DDR4", "Fréquence RAM limitée par le chipset sur les séries 400 H/B."); "B460" = @("Intel", "LGA1200", "DDR4", "Fréquence RAM limitée par le chipset sur les séries 400 H/B."); "H470" = @("Intel", "LGA1200", "DDR4", "Fréquence RAM limitée par le chipset sur les séries 400 H/B."); "Z490" = @("Intel", "LGA1200", "DDR4", "")
  "H510" = @("Intel", "LGA1200", "DDR4", "XMP non garanti sur H510."); "B560" = @("Intel", "LGA1200", "DDR4", ""); "H570" = @("Intel", "LGA1200", "DDR4", ""); "Z590" = @("Intel", "LGA1200", "DDR4", "")
  "H610" = @("Intel", "LGA1700", "DDR4 ou DDR5", "XMP non garanti sur H610."); "B660" = @("Intel", "LGA1700", "DDR4 ou DDR5", ""); "H670" = @("Intel", "LGA1700", "DDR4 ou DDR5", ""); "Z690" = @("Intel", "LGA1700", "DDR4 ou DDR5", "")
  "B760" = @("Intel", "LGA1700", "DDR4 ou DDR5", ""); "H770" = @("Intel", "LGA1700", "DDR4 ou DDR5", ""); "Z790" = @("Intel", "LGA1700", "DDR4 ou DDR5", "")
  "H810" = @("Intel", "LGA1851", "DDR5", ""); "B860" = @("Intel", "LGA1851", "DDR5", ""); "Z890" = @("Intel", "LGA1851", "DDR5", "")
  "W680" = @("Intel", "LGA1700", "DDR4 ou DDR5", ""); "Q670" = @("Intel", "LGA1700", "DDR4 ou DDR5", "")
}

function Trouver-Chipset($modele) {
  $s = "$modele".ToUpper()
  foreach ($mt in [regex]::Matches($s, '(?<![A-Z0-9])(TRX\d{2}|WRX\d{2}|[ABHXZ]\d{3}E?)')) {
    $c = $mt.Groups[1].Value
    if ($script:Chipsets.ContainsKey($c)) { return $c }
    $c2 = $c.TrimEnd('E'); if ($script:Chipsets.ContainsKey($c2)) { return $c2 }
  }
  return ""
}

function Date-Bios($d) {
  if ($null -eq $d) { return $null }
  if ($d -is [datetime]) { return $d }
  $s = "$d"
  if ($s -match '^(\d{4})(\d{2})(\d{2})') { try { return [datetime]::new([int]$matches[1], [int]$matches[2], [int]$matches[3]) } catch { return $null } }
  try { return [datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
}

# ---------------------------------------------------------------------
# 3) Profil normalisé (utilisé par le guide ET par l'interface)
# ---------------------------------------------------------------------
function Get-ProfilBios($m) {
  if (-not $m) { $m = Lire-MaterielBios }
  $p = [ordered]@{}
  $fabCM = Nettoyer-Valeur $m.Board.Manufacturer
  $fabPC = Nettoyer-Valeur $m.Systeme.Manufacturer
  $p.Modele = Nettoyer-Valeur $m.Board.Product
  $p.ModelePC = Nettoyer-Valeur $m.Systeme.Model
  $brut = "$fabCM $fabPC"
  $p.Fabricant = if ($fabCM -match 'Micro-?Star|^MSI') { "MSI" }
    elseif ($fabCM -match 'ASUSTeK|^ASUS') { "ASUS" }
    elseif ($fabCM -match 'Gigabyte|AORUS') { "Gigabyte" }
    elseif ($fabCM -match 'ASRock') { "ASRock" }
    elseif ($fabCM -match 'BIOSTAR') { "Biostar" }
    elseif ($fabCM -match 'NZXT') { "NZXT" }
    elseif ($brut -match 'Dell|Alienware') { "Dell" }
    elseif ($brut -match 'Hewlett|^HP|\sHP') { "HP" }
    elseif ($brut -match 'Lenovo') { "Lenovo" }
    elseif ($brut -match 'Acer') { "Acer" }
    elseif ($brut -match 'Toshiba|Dynabook') { "Dynabook" }
    elseif ($brut -match 'Microsoft') { "Microsoft" }
    elseif ($brut -match 'Samsung') { "Samsung" }
    elseif ($brut -match 'Huawei|Honor') { "Huawei" }
    elseif ($brut -match 'Fujitsu') { "Fujitsu" }
    elseif ($brut -match 'Medion') { "Medion" }
    elseif ($fabPC -match 'Micro-?Star|^MSI') { "MSI" }
    elseif ($fabPC -match 'ASUS') { "ASUS" }
    elseif ($fabPC -match 'Gigabyte') { "Gigabyte" }
    else { "" }
  $p.FabricantBrut = if ($fabCM) { $fabCM } else { $fabPC }
  $type = 0; try { $type = [int]$m.Systeme.PCSystemType } catch {}
  # portable = Windows le dit « mobile », ou une batterie dans un boîtier qui n'est pas un PC fixe (tour, mini-tour, tout-en-un...)
  $fixe = [bool]@($m.Chassis | Where-Object { $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 24, 35 }).Count
  $p.Portable = ($type -eq 2) -or ([bool]$m.Batterie -and -not $fixe)
  $p.Oem = $p.Fabricant -in @("Dell","HP","Lenovo","Acer","Dynabook","Microsoft","Samsung","Huawei","Fujitsu","Medion")
  # Profil de guide : carte mère de bureau d'une marque connue, sinon PC de marque / portable, sinon inconnu
  $p.Profil = if ($p.Portable -or $p.Oem) { "OEM" } elseif ($p.Fabricant -in @("MSI","ASUS","Gigabyte","ASRock","Biostar","NZXT")) { $p.Fabricant } else { "Inconnu" }
  # Nom affiché
  $nomCM = (@($(if ($p.Fabricant) { $p.Fabricant } else { $p.FabricantBrut }), $p.Modele) | Where-Object { $_ }) -join " "
  if ($p.Profil -eq "OEM" -and $p.ModelePC) { $nomCM = (@($(if ($p.Fabricant) { $p.Fabricant } else { $p.FabricantBrut }), $p.ModelePC) | Where-Object { $_ }) -join " " }
  $p.Nom = if ($nomCM) { $nomCM } else { "carte mère non identifiée" }
  # BIOS
  $p.BiosVersion = Nettoyer-Valeur $m.Bios.SMBIOSBIOSVersion
  $p.BiosDate = Date-Bios $m.Bios.ReleaseDate
  # Processeur
  $p.Virtuel = Est-Virtuel $m
  $cls = Classer-Cpu $m.Cpu
  $p.CpuNom = if ($cls.Nom) { $cls.Nom } else { Nettoyer-Valeur $m.Cpu.Name }
  $p.CpuMarque = $cls.Marque
  $p.CpuFamille = $cls.Famille
  $p.RyzenSerie = $cls.RyzenSerie
  $p.X3D = $cls.X3D
  $p.IntelGen = $cls.IntelGen
  $p.IntelHybride = $cls.Hybride
  $p.Arm = $cls.Arm
  # Chipset
  $p.Chipset = Trouver-Chipset $p.Modele
  $p.Plateforme = ""; $p.ChipsetNote = ""
  if ($p.Chipset) { $info = $script:Chipsets[$p.Chipset]; $p.Plateforme = $info[1]; $p.ChipsetNote = $info[3]; if (-not $p.CpuMarque) { $p.CpuMarque = $info[0] } }
  # Mémoire
  $mems = @($m.Mems | Where-Object { $_ })
  $p.RamGo = [math]::Round((($mems | Measure-Object -Property Capacity -Sum).Sum) / 1GB)
  $p.RamBarrettes = $mems.Count
  $t = 0; foreach ($x in $mems) { try { if ([int]$x.SMBIOSMemoryType) { $t = [int]$x.SMBIOSMemoryType; break } } catch {} }
  $p.RamType = Type-Ram $t
  if (-not $p.RamType -and $p.Chipset -and $script:Chipsets[$p.Chipset][2] -notmatch 'ou') { $p.RamType = $script:Chipsets[$p.Chipset][2] }
  $nSoudes = @($mems | Where-Object {
    $ff = 0; try { $ff = [int]$_.FormFactor } catch {}
    ($ff -eq 13) -or ("$($_.BankLabel) $($_.DeviceLocator)" -match '(?i)solder|onboard|system board')
  }).Count
  $p.RamSoudee = ($nSoudes -gt 0) -or ($p.RamType -match 'LPDDR')
  $vMax = 0; $vConf = 0
  foreach ($x in $mems) {
    try { $a = [int]$x.Speed; if ($a -gt $vMax) { $vMax = $a } } catch {}
    try { $b = [int]$x.ConfiguredClockSpeed; if ($b -gt $vConf) { $vConf = $b } } catch {}
  }
  $p.RamVitesseMax = $vMax; $p.RamVitesse = $vConf
  $p.RamRef = (@($mems | ForEach-Object { Nettoyer-Valeur $_.PartNumber } | Where-Object { $_ } | Select-Object -Unique) -join ", ")
  # XMP/EXPO : "Off" = vitesse actuelle nettement sous la vitesse annoncée ; "Probable" = vitesse de base JEDEC
  $p.Xmp = "Inconnu"
  if ($vConf -gt 0) {
    if ($vMax -gt 0 -and $vConf -lt ($vMax - 100)) { $p.Xmp = "Off" }
    elseif (($p.RamType -eq "DDR4" -and $vConf -le 2666) -or ($p.RamType -eq "DDR5" -and $vConf -le 4800)) { $p.Xmp = "Base" }
    else { $p.Xmp = "OK" }
  }
  # Carte graphique
  $tousG = @($m.Gpus | Where-Object { $_ })
  $gp = @($tousG | Where-Object { "$($_.Name)" -notmatch '(?i)Microsoft Basic|Basic Display|Virtual Display|Remote Display|Parsec|Meta Quest|Indirect Display' })
  if (-not $gp.Count) { $gp = @($tousG) }
  $p.GpuNom = (@($gp | ForEach-Object {
    $n = Nettoyer-Valeur $_.Name
    $id = "$($_.PNPDeviceID)"
    if ($id -match 'VEN_10DE' -and $n -match '(?i)Standard VGA|Basic Display|Microsoft Basic') { "NVIDIA GeForce (pilote non installé)" }
    elseif ($id -match 'VEN_1002' -and $n -match '(?i)Standard VGA|Basic Display|Microsoft Basic') { "AMD Radeon (pilote non installé)" }
    elseif ($id -match 'VEN_8086' -and $n -match '(?i)Standard VGA|Basic Display|Microsoft Basic') { "Intel Graphics (pilote non installé)" }
    elseif ($n -match '(?i)QEMU|Bochs|Virtio|Red Hat|Standard VGA|Microsoft Basic|Basic Display|Hyper-V Video|VMware SVGA') { "Carte d'affichage de base" }
    else { $n }
  } | Where-Object { $_ }) -join " + ")
  $marques = @()
  foreach ($g in $tousG) {
    $n = "$($g.Name) $($g.AdapterCompatibility) $($g.PNPDeviceID)"
    if ($n -match '(?i)NVIDIA|GeForce|RTX|GTX|Quadro|TITAN|Tesla|VEN_10DE') { $marques += "NVIDIA" }
    elseif ($n -match '(?i)Radeon|FirePro|Instinct|VEN_1002') { $marques += "AMD" }
    elseif ($n -match '(?i)Arc\b|VEN_8086.*DEV_56|Intel\(R\) Arc') { $marques += "Intel Arc" }
    elseif ($n -match '(?i)Intel|UHD|Iris|Xe Graphics|VEN_8086') { $marques += "Intel" }
  }
  $p.GpuMarques = @($marques | Select-Object -Unique)
  $p.GpuBasique = (-not $p.GpuMarques.Count) -and [bool]$p.GpuNom
  $p.GpuDediee = $p.GpuNom -match 'RTX|GTX|RX\s?\d|Arc\s?[AB]\d|Radeon\s+(Pro|VII)'
  $p.GpuReBarOk = $p.GpuNom -match 'RTX\s?[3-9]\d|RX\s?[6-9]\d{3}|Arc'
  # Firmware / sécurité
  $fw = "$($m.Firmware)"
  $p.Uefi = if ($fw -match 'UEFI') { $true } elseif ($fw -match 'Legacy|BIOS') { $false } else { $null }
  $p.SecureBoot = $m.SecureBoot
  $p.TpmPresent = if ($m.Tpm) { [bool]$m.Tpm.Present } else { $null }
  $p.TpmActif = if ($m.Tpm) { [bool]$m.Tpm.Actif } else { $null }
  $p.TpmVersion = if ($m.Tpm) { "$($m.Tpm.Version)" } else { "" }
  $p.ReBar = $m.ReBar
  # Page support officielle (recherche du modèle exact sur le site du fabricant)
  $p.UrlSupport = Url-Support $p
  return [pscustomobject]$p
}

function Url-Support($p) {
  $enc = { param($s) [uri]::EscapeDataString("$s") }
  $mod = if ($p.Profil -eq "OEM" -and $p.ModelePC) { $p.ModelePC } else { $p.Modele }
  $mod = ($mod -replace '\(.*?\)', '' -replace '\s+', ' ').Trim()   # "MODELE (REF-1234)" -> "MODELE"
  switch ($p.Fabricant) {
    "MSI"      { if ($mod) { return "https://www.msi.com/search/$(& $enc $mod)" } else { return "https://www.msi.com/support" } }
    "ASUS"     { if ($mod) { return "https://www.asus.com/fr/searchresult?searchType=support&searchKey=$(& $enc $mod)" } else { return "https://www.asus.com/fr/support/" } }
    "Gigabyte" { if ($mod) { return "https://www.gigabyte.com/Search?kw=$(& $enc $mod)" } else { return "https://www.gigabyte.com/Support" } }
    "ASRock"   { if ($mod) { return "https://www.asrock.com/search/index.asp?Keyword=$(& $enc $mod)" } else { return "https://www.asrock.com/support/index.asp" } }
    "Dell"     { return "https://www.dell.com/support/home/fr-fr" }
    "HP"       { return "https://support.hp.com/fr-fr/drivers" }
    "Lenovo"   { return "https://pcsupport.lenovo.com/fr/fr" }
    "Acer"     { return "https://www.acer.com/fr-fr/support" }
    "NZXT"     { return "https://nzxt.com/fr-FR/support" }
    "Biostar"  { if ($mod) { return "https://www.biostar.com.tw/app/en/mb/introduction.php?S_name=$(& $enc $mod)" } else { return "https://www.biostar.com.tw/app/en/support/" } }
    "Dynabook" { return "https://support.dynabook.com/" }
    "Microsoft"{ return "https://www.microsoft.com/surface/support" }
    "Samsung"  { return "https://www.samsung.com/support/" }
    "Huawei"   { return "https://consumer.huawei.com/support/" }
    "Fujitsu"  { return "https://www.fujitsu.com/support/" }
    "Medion"   { return "https://www.medion.com/support" }
  }
  $q = (@($p.FabricantBrut, $mod, "BIOS support") | Where-Object { $_ }) -join " "
  return "https://www.google.com/search?q=$(& $enc $q)"
}

# ---------------------------------------------------------------------
# 4) Profils fabricants (infos connues ; les noms de menus peuvent
#    varier selon la carte et la version du BIOS)
# ---------------------------------------------------------------------
function Infos-Fabricant($p) {
  $amd = $p.CpuMarque -eq "AMD"; $am5 = $p.Plateforme -eq "AM5" -or $p.RamType -eq "DDR5" -and $amd
  $nomProfilRam = if ($amd -and $am5) { "EXPO" }
    elseif ($amd) { switch ($p.Profil) { "MSI" { "A-XMP" } "ASUS" { "D.O.C.P." } default { "XMP" } } }
    elseif ($p.CpuMarque) { "XMP" } else { "XMP / EXPO" }
  $f = @{ Touche = ""; Interface = ""; Avance = ""; Ram = @(); ReBar = @(); Flash = ""; Tpm = ""; Pbo = "" }
  switch ($p.Profil) {
    "MSI" {
      $f.Touche = "Suppr (Del) en boucle dès l'allumage"
      $f.Interface = "Click BIOS 5 (sur la plupart des cartes MSI récentes), mode EZ au départ"
      $f.Avance = "F7 bascule entre le mode EZ et le mode avancé"
      $f.Ram = @(
        "Mode EZ : bouton $(if ($amd -and $am5) { 'EXPO' } elseif ($amd) { 'A-XMP' } else { 'XMP' }) en haut à gauche > Profil 1.",
        "Ou en mode avancé (F7) : OC > Extreme Memory Profile (XMP) / A-XMP$(if ($am5) { ' / EXPO' }) > Profil 1.",
        "Si le PC ne démarre plus avec le profil : OC > « Memory Try It! » propose des réglages plus sages (ex. 3466 au lieu de 3600).")
      $f.ReBar = @("Mode avancé (F7) : Settings > Advanced > PCI Subsystem Settings",
        "« Above 4G memory/Crypto Currency mining » : Enabled",
        "« Re-Size BAR Support » : Enabled (ou Auto)")
      $f.Flash = "M-FLASH (bouton dans le BIOS) avec le fichier BIOS sur une clé USB en FAT32"
      $f.Tpm = if ($amd) { "Settings > Security > Trusted Computing > AMD fTPM switch (généralement)" } else { "Settings > Security > Trusted Computing > Intel Platform Trust Technology (PTT) (généralement)" }
      $f.Pbo = "OC > Advanced CPU Configuration > AMD Overclocking (accepter l'avertissement) > Precision Boost Overdrive"
    }
    "ASUS" {
      $f.Touche = "Suppr ou F2 dès l'allumage"
      $f.Interface = "UEFI BIOS Utility, mode EZ au départ"
      $f.Avance = "F7 passe en Advanced Mode"
      $f.Ram = @(
        "Mode EZ : « AI Overclock Tuner » / D.O.C.P. / XMP / EXPO > Profil 1, ou",
        "Advanced Mode (F7) : Ai Tweaker > Ai Overclock Tuner > $(if ($amd -and $am5) { 'EXPO' } elseif ($amd) { 'D.O.C.P. (ou XMP sur les cartes récentes)' } else { 'XMP I (ou XMP II)' }).")
      $f.ReBar = @("Advanced > PCI Subsystem Settings > « Above 4G Decoding » : Enabled",
        "Puis « Re-Size BAR Support » : Enabled (ou Auto)",
        "Si l'option est grisée : Boot > CSM (Compatibility Support Module) > Disabled d'abord.")
      $f.Flash = "Tool > ASUS EZ Flash 3 (ou EZ Flash selon la carte), fichier sur une clé USB en FAT32"
      $f.Tpm = if ($amd) { "Advanced > AMD fTPM configuration (généralement)" } else { "Advanced > PCH-FW Configuration > PTT (généralement)" }
      $f.Pbo = "Ai Tweaker > Precision Boost Overdrive (ou Advanced > AMD Overclocking)"
    }
    "Gigabyte" {
      $f.Touche = "Suppr dès l'allumage"
      $f.Interface = "BIOS AORUS / Gigabyte, mode Easy au départ"
      $f.Avance = "F2 bascule entre Easy Mode et Advanced Mode"
      $f.Ram = @("Advanced Mode : Tweaker > « Extreme Memory Profile (X.M.P.) » > Profile1$(if ($amd -and $am5) { ' (EXPO sur AM5)' }).",
        "En Easy Mode, le même réglage est souvent proposé directement (X.M.P. / EXPO).")
      $f.ReBar = @("Settings > IO Ports > « Above 4G Decoding » : Enabled",
        "« Re-Size BAR Support » : Auto/Enabled",
        "CSM doit être désactivé (Boot > CSM Support : Disabled).")
      $f.Flash = "Q-Flash (touche F8 dans le BIOS), fichier sur une clé USB en FAT32"
      $f.Tpm = if ($amd) { "Settings > Miscellaneous > AMD CPU fTPM (généralement)" } else { "Settings > Miscellaneous > Intel Platform Trust Technology (PTT) (généralement)" }
      $f.Pbo = "Tweaker > Advanced CPU Settings > Precision Boost Overdrive (généralement)"
    }
    "ASRock" {
      $f.Touche = "F2 ou Suppr dès l'allumage"
      $f.Interface = "UEFI ASRock, mode Easy au départ sur les cartes récentes"
      $f.Avance = "F6 bascule entre Easy Mode et Advanced Mode"
      $f.Ram = @("Advanced Mode : OC Tweaker > DRAM Configuration > « Load XMP Setting »$(if ($amd -and $am5) { ' / « Load EXPO Setting »' }) > Profil 1.")
      $f.ReBar = @("Advanced > Chipset Configuration > « Above 4G Decoding » : Enabled",
        "« Re-Size BAR Support » : Enabled",
        "CSM doit être désactivé (Boot > CSM : Disabled).")
      $f.Flash = "Tool > Instant Flash, fichier sur une clé USB en FAT32"
      $f.Tpm = if ($amd) { "Advanced > CPU Configuration > AMD fTPM switch (généralement)" } else { "Security > Intel Platform Trust Technology (généralement)" }
      $f.Pbo = "OC Tweaker > CPU Configuration / AMD Overclocking > Precision Boost Overdrive (généralement)"
    }
    "Biostar" {
      $f.Touche = "Suppr dès l'allumage (F9 ou F12 généralement pour le menu de démarrage)"
      $f.Interface = "UEFI Biostar"
      $f.Avance = "généralement un onglet « Advanced » ou un mode avancé"
      $f.Ram = @("Le profil $nomProfilRam se trouve généralement dans le menu d'overclocking (souvent nommé « O.N.E. ») > Memory.")
      $f.ReBar = @("Généralement : Advanced > PCI Subsystem > Above 4G Decoding + Re-Size BAR Support (si proposé).")
      $f.Flash = "outil de mise à jour intégré au BIOS (généralement « BIO-Flasher »), fichier sur une clé USB"
      $f.Tpm = "généralement dans Advanced ou Security (fTPM / PTT)"
      $f.Pbo = "généralement dans le menu d'overclocking (O.N.E.)"
    }
    "NZXT" {
      $f.Touche = "Suppr ou F2 dès l'allumage"
      $f.Interface = "UEFI NZXT"
      $f.Avance = "généralement F6/F7 ou un bouton « Advanced Mode »"
      $f.Ram = @("Le profil $nomProfilRam se trouve généralement dans le menu OC / DRAM Configuration.")
      $f.ReBar = @("Généralement : Advanced > PCI / Chipset Configuration > Above 4G Decoding + Re-Size BAR Support.")
      $f.Flash = "outil de mise à jour intégré au BIOS (voir la page support NZXT)"
      $f.Tpm = "généralement dans Advanced ou Security (fTPM / PTT)"
      $f.Pbo = "généralement dans le menu OC"
    }
    "OEM" {
      $touches = @{ "Dell" = "F2 (F12 = menu de démarrage)"; "HP" = "Échap puis F10 (ou F10 directement)"; "Lenovo" = "F1 (ThinkPad/ThinkCentre) ou F2 (IdeaPad/Legion) ; sur certains portables, bouton Novo"
        "Acer" = "F2"; "Dynabook" = "F2"; "Microsoft" = "maintenir Volume + puis appuyer sur le bouton d'alimentation (Surface)"; "Samsung" = "F2"; "Huawei" = "F2"; "Fujitsu" = "F2"; "Medion" = "F2 ou Suppr"
        "ASUS" = "F2 (portables ASUS)"; "MSI" = "Suppr (portables MSI)"; "Gigabyte" = "F2 (portables Gigabyte/AORUS)" }
      $f.Touche = if ($touches.ContainsKey($p.Fabricant)) { $touches[$p.Fabricant] } else { "généralement F2, Suppr, F10 ou Échap (le nom s'affiche souvent au démarrage)" }
      $f.Interface = "BIOS du constructeur (simplifié)"
      $f.Avance = "selon le constructeur ; beaucoup d'options sont masquées"
      $f.Ram = @("Sur les PC de marque et les portables, XMP/EXPO est rarement proposé : la RAM tourne à la vitesse prévue par le constructeur.",
        "Si une option « Memory Profile », « XMP » ou « EXPO » existe, active-la ; sinon, ne cherche pas plus loin.")
      $f.ReBar = @("Resizable BAR dépend du constructeur : il est soit déjà actif, soit absent. Mets le BIOS à jour pour en profiter s'il existe.")
      $f.Flash = switch ($p.Fabricant) { "Dell" { "Dell SupportAssist / Dell Command Update, ou le fichier .exe de la page support" } "HP" { "HP Support Assistant, ou le fichier de la page support" }
        "Lenovo" { "Lenovo Vantage, ou le fichier de la page support" } default { "l'outil du constructeur ou le fichier de la page support (souvent un .exe à lancer sous Windows)" } }
      $f.Tpm = "Security > TPM / Intel PTT / AMD fTPM (généralement déjà actif sur les PC de marque)"
      $f.Pbo = ""
    }
    default {
      $f.Touche = "généralement Suppr ou F2 (le nom de la touche s'affiche souvent au démarrage)"
      $f.Interface = "UEFI du fabricant"
      $f.Avance = "généralement F7, F6 ou F2 pour le mode avancé"
      $f.Ram = @("Cherche « XMP », « EXPO », « D.O.C.P. » ou « Memory Profile » (souvent dans un menu OC / Tweaker / Overclocking) > Profil 1.")
      $f.ReBar = @("Cherche « Above 4G Decoding » puis « Re-Size BAR » (souvent dans Advanced > PCI / Chipset).")
      $f.Flash = "l'outil de mise à jour intégré au BIOS (souvent nommé « Flash »), fichier sur une clé USB en FAT32"
      $f.Tpm = "généralement dans Advanced ou Security (AMD fTPM / Intel PTT)"
      $f.Pbo = "généralement dans le menu d'overclocking"
    }
  }
  $f.NomProfilRam = $nomProfilRam
  return $f
}

# ---------------------------------------------------------------------
# 5) Génération du guide (texte). Conventions pour l'affichage :
#    "=== TITRE ===" = section ; "/!\ " = avertissement ; "  - " = étape
# ---------------------------------------------------------------------
function Get-GuideBios($m) {
  if (-not $m) { $m = Lire-MaterielBios }
  $p = Get-ProfilBios $m
  $f = Infos-Fabricant $p
  $amd = ($p.CpuMarque -eq "AMD" -and -not $p.Virtuel); $intel = ($p.CpuMarque -eq "Intel" -and -not $p.Virtuel)
  $L = New-Object System.Collections.Generic.List[string]
  function A([string]$t = "") { $L.Add($t) }
  function OuiNon($v, $oui = "oui", $non = "non") { if ($null -eq $v) { "inconnu" } elseif ($v) { $oui } else { $non } }

  A "GUIDE BIOS PERSONNALISÉ - $($p.Nom)"
  A "Généré par LuKZyR Optimisation v0.1 bêta le $((Get-Date).ToString('dd/MM/yyyy'))."
  A "Ce guide n'applique rien : c'est toi qui choisis dans le BIOS. Les noms de menus"
  A "peuvent varier un peu selon la version du BIOS."
  A ""
  A "=== TON PC ==="
  $fabAff = if ($p.Fabricant) { $p.Fabricant } else { $p.FabricantBrut }
  A "Carte mère      : $(if ($p.Modele) { "$fabAff $($p.Modele)".Trim() } else { 'non communiquée par le BIOS' })"
  if ($p.Profil -eq "OEM" -and $p.ModelePC) { A "Modèle du PC    : $fabAff $($p.ModelePC)" }
  A "Chipset         : $(if ($p.Chipset) { "$($p.Chipset) ($($p.CpuMarque) $($p.Plateforme))" } else { 'non déduit du nom de la carte' })"
  $dateTxt = if ($p.BiosDate) { $p.BiosDate.ToString('dd/MM/yyyy') } else { "date inconnue" }
  A "BIOS            : $(if ($p.BiosVersion) { "version $($p.BiosVersion)" } else { 'version inconnue' })$(if ($p.BiosDate) { " du $dateTxt" })"
  if ($p.Virtuel) { A "Type            : PC virtuel (les réglages d'une carte mère physique ne s'appliquent généralement pas)" }
  A "Processeur      : $(if ($p.CpuNom) { $p.CpuNom } else { 'non détecté' })$(if ($p.CpuFamille) { " ($($p.CpuFamille))" })"
  if ($p.Arm) { A "Architecture    : ARM64 (mode compatible : certaines optimisations x86 ne s'appliquent pas)" }
  $ramTxt = if ($p.RamGo) { "$($p.RamGo) Go $($p.RamType) ($($p.RamBarrettes) module(s))".Replace("  ", " ") + $(if ($p.RamSoudee) { ", mémoire soudée" } else { "" }) } else { "non détectée" }
  A "Mémoire         : $ramTxt"
  if ($p.RamVitesse) { A "Vitesse RAM     : $($p.RamVitesse) MHz actuellement$(if ($p.RamVitesseMax -gt $p.RamVitesse) { " (barrettes annoncées $($p.RamVitesseMax) MHz)" })" }
  A "Carte graphique : $(if ($p.GpuNom) { $p.GpuNom } else { 'non détectée' })"
  A "Démarrage       : $(if ($p.Uefi -eq $true) { 'UEFI' } elseif ($p.Uefi -eq $false) { 'Legacy (ancien mode BIOS/CSM)' } else { 'inconnu' })"
  A "Secure Boot     : $(if ($p.Uefi -eq $false) { 'non disponible (démarrage Legacy)' } else { OuiNon $p.SecureBoot 'activé' 'désactivé' })"
  A "TPM             : $(if ($null -eq $p.TpmPresent) { 'inconnu' } elseif ($p.TpmPresent) { "présent$(if ($p.TpmVersion) { " (version $($p.TpmVersion))" })$(if ($p.TpmActif -eq $false) { ', désactivé' })" } else { 'absent ou désactivé dans le BIOS' })"
  if ($null -ne $p.ReBar) { A "Resizable BAR   : $(OuiNon $p.ReBar 'actif' 'inactif')" }
  if ($p.Profil -eq "Inconnu") { A ""; A "/!\ Fabricant de la carte mère non reconnu : le guide ci-dessous est générique." }
  A ""
  if ($p.Virtuel) {
    A "=== RÉGLAGES CARTE MÈRE ==="
    A "  - Sans objet sur une machine virtuelle : XMP / EXPO, Resizable BAR et PBO concernent une carte mère physique."
    A "  - Tu peux quand même vérifier le firmware du guest (UEFI, Secure Boot, TPM) dans les options de l'hyperviseur."
    return ($L -join "`r`n")
  }

  A "=== 1. ENTRER DANS LE BIOS ==="
  A "  - Touche : $($f.Touche)."
  if ($p.Uefi -eq $true) { A "  - Plus simple : bouton « Redémarrer dans le BIOS » de LuKZyR Optimisation (ou Paramètres > Récupération > Démarrage avancé > Paramètres du microprogramme UEFI)." }
  A "  - Interface : $($f.Interface)$(if ($p.Uefi -eq $false -and $p.Profil -eq 'Inconnu') { ' (ou BIOS classique)' })."
  A "  - Mode avancé : $($f.Avance)."
  A "  - Pour sauvegarder et quitter : F10 puis « Yes / Oui » (sur la plupart des BIOS)."
  A ""

  A "=== 2. METTRE À JOUR LE BIOS (recommandé avant le reste) ==="
  if ($p.BiosDate) {
    $age = ((Get-Date) - $p.BiosDate).TotalDays / 365.25
    if ($age -ge 2) { A "/!\ Ton BIOS date du $dateTxt (plus de $([math]::Floor($age)) ans) : une mise à jour apporte souvent stabilité RAM, Resizable BAR et correctifs de sécurité." }
    else { A "  - Ton BIOS date du $dateTxt : il est assez récent, la mise à jour est facultative." }
  }
  if ($p.Modele -or $p.ModelePC) {
    A "  - Ouvre la page support officielle de ta carte (bouton « Page support de ma carte mère ») :"
    A "    $($p.UrlSupport)"
    if ($p.Profil -eq "OEM") { A "    (entre le modèle exact$(if ($p.ModelePC) { " « $($p.ModelePC) »" }) ou le numéro de série / Service Tag collé sous le PC)" }
    else { A "    (si la recherche ne trouve rien, tape le modèle exact sur le site du fabricant)" }
  } else {
    A "/!\ Le modèle de ta carte mère n'est pas communiqué par le BIOS : lis-le sur la carte elle-même, sur sa boîte, ou avec CPU-Z (onglet « Mainboard »), puis cherche « <modèle> BIOS » sur le site du fabricant."
  }
  $modExact = if ($p.Profil -eq "OEM" -and $p.ModelePC) { $p.ModelePC } else { $p.Modele }
  A "  - Vérifie que le modèle EXACT correspond$(if ($modExact) { " ($modExact)" }) : un BIOS d'un autre modèle peut rendre la carte inutilisable."
  A "  - Outil de mise à jour : $($f.Flash)."
  A "  - Ne coupe jamais le courant pendant la mise à jour. LuKZyR Optimisation ne flashe jamais le BIOS tout seul."
  A "  - Après une mise à jour, les réglages reviennent par défaut : refais les étapes suivantes."
  A ""

  if ($p.Profil -eq "OEM") { A "=== 3. RAM : PROFIL $($f.NomProfilRam.ToUpper()) ===" } else { A "=== 3. RAM : ACTIVER LE PROFIL $($f.NomProfilRam.ToUpper()) (le plus gros gain) ===" }
  switch ($p.Xmp) {
    "Off"  { A "/!\ Ta RAM tourne à $($p.RamVitesse) MHz alors que tes barrettes sont annoncées à $($p.RamVitesseMax) MHz : le profil $($f.NomProfilRam) semble DÉSACTIVÉ. Active-le." }
    "Base" { A "/!\ Ta RAM tourne à $($p.RamVitesse) MHz, la vitesse de base $($p.RamType). Si tes barrettes sont vendues plus rapides (voir l'étiquette ou la boîte$(if ($p.RamRef) { " : référence $($p.RamRef)" })), le profil $($f.NomProfilRam) est probablement désactivé." }
    "OK"   { A "  - Ta RAM tourne à $($p.RamVitesse) MHz : le profil semble déjà actif. Rien à faire ici (pour info, voici où il se trouve)." }
    default { A "  - Vitesse de la RAM non communiquée : vérifie dans le BIOS que le profil est activé." }
  }
  foreach ($e in $f.Ram) { A "  - $e" }
  if ($amd -and $p.RyzenSerie -in 3000, 5000 -and $p.RamType -eq "DDR4") { A "  - Ryzen $($p.RyzenSerie) + DDR4 : le meilleur compromis est généralement 3600 MHz (CL16-18), avec l'Infinity Fabric (FCLK) à 1800 en 1:1. Au-delà, le gain est faible." }
  if ($amd -and ($p.Plateforme -eq "AM5" -or $p.RyzenSerie -ge 7000) -and $p.RamType -ne "DDR4") { A "  - Ryzen 7000/9000 + DDR5 : le point idéal est généralement 6000 MHz (EXPO). Le premier démarrage après activation peut être long (entraînement mémoire), c'est normal." }
  if ($intel -and $p.RamType -eq "DDR5") { A "  - Intel + DDR5 : active simplement le profil XMP de tes barrettes ; le premier démarrage peut être plus long (entraînement mémoire)." }
  if ($p.ChipsetNote -and $p.ChipsetNote -match 'RAM|XMP') { A "/!\ $($p.ChipsetNote)" }
  if ($p.Profil -ne "OEM") { A "  - Si le PC ne démarre plus : attends 2-3 redémarrages automatiques, sinon fais un Clear CMOS (voir le manuel) et choisis une vitesse un cran en dessous." }
  A ""

  A "=== 4. RESIZABLE BAR / SMART ACCESS MEMORY ==="
  $gpuTxt = if ($p.GpuMarques -contains "Intel Arc") { "Intel Arc : Resizable BAR est INDISPENSABLE pour de bonnes performances." }
    elseif ($p.GpuReBarOk) { "Ta carte graphique le gère : gain de quelques % dans certains jeux." }
    elseif ($p.GpuDediee) { "Ta carte graphique est peut-être trop ancienne pour en profiter (RTX 30 / RX 6000 / Arc ou plus récent requis)." }
    else { "Utile surtout avec une carte graphique dédiée récente (RTX 30 / RX 6000 / Arc ou plus)." }
  A "  - $gpuTxt"
  if ($p.ReBar -eq $true) { A "  - Resizable BAR est déjà actif. Rien à faire." }
  elseif ($p.Uefi -eq $false) { A "/!\ Windows démarre en mode Legacy : Resizable BAR exige le mode UEFI (CSM désactivé). Ne désactive PAS le CSM sans avoir converti le disque en GPT (outil MBR2GPT), sinon Windows ne démarrera plus." }
  if ($p.ReBar -ne $true) { foreach ($e in $f.ReBar) { A "  - $e" } }
  if ($p.ChipsetNote -and $p.ChipsetNote -match 'Resizable') { A "  - $($p.ChipsetNote)" }
  if ($p.GpuMarques -contains "AMD" -and $amd) { A "  - Vérification : AMD Software (Adrenalin) > Performances > Réglage > Smart Access Memory." }
  elseif ($p.GpuMarques -contains "NVIDIA") { A "  - Vérification : Panneau de configuration NVIDIA > Informations système > Resizable BAR = Oui." }
  A ""

  A "=== 5. SÉCURITÉ : SECURE BOOT ET TPM (Windows 11, anti-triche) ==="
  if ($p.TpmPresent -eq $true -and $p.TpmActif -ne $false) { A "  - TPM présent et actif : rien à faire." }
  else { A "  - Active le TPM : $(if ($amd) { 'AMD fTPM' } elseif ($intel) { 'Intel PTT' } else { 'fTPM / PTT' }) - $($f.Tpm)." }
  if ($p.SecureBoot -eq $true) { A "  - Secure Boot activé : rien à faire." }
  elseif ($p.Uefi -eq $false) { A "/!\ Secure Boot exige le mode UEFI : à ne pas activer tant que Windows démarre en Legacy." }
  else { A "  - Secure Boot $(if ($p.SecureBoot -eq $false) { 'désactivé' } else { 'non vérifié' }) : il se trouve généralement dans Boot > Secure Boot (ou Security). Certains anti-triches (ex. Valorant sous Windows 11) l'exigent." }
  A ""

  if ($p.Profil -ne "OEM" -and $f.Pbo -and ($amd -or $intel)) {
    A "=== 6. POUR ALLER PLUS LOIN (facultatif, utilisateurs avancés) ==="
    if ($amd) {
      if ($p.Chipset -eq "A620" -or $p.Chipset -eq "A320") { A "  - Le chipset $($p.Chipset) ne permet généralement pas l'overclocking du processeur : passe cette étape." }
      else {
        A "  - PBO + Curve Optimizer : $($f.Pbo)."
        A "    Precision Boost Overdrive : Advanced ; Curve Optimizer : All Cores > Negative > commence à 5, monte par paliers de 5 (15 max)."
        A "/!\ Une valeur trop forte peut rendre le PC instable (écrans bleus, redémarrages, erreurs en jeu), même si tout semble aller au début."
        A "    Si le moindre souci apparaît : remets Curve Optimizer sur Disabled (ou « Load Optimized Defaults »). Rien n'est obligatoire."
        if ($p.X3D) { A "/!\ Processeur X3D : options limitées (Curve Optimizer seulement selon le BIOS). Ne monte jamais la tension." }
        A "  - Teste la stabilité (OCCT ou Cinebench 30 min + tes jeux). Plantage = réduis la valeur ou désactive."
      }
    } elseif ($intel) {
      A "  - Laisse les réglages processeur par défaut (« Intel Default Settings » si proposé) : c'est le plus stable."
      if ($p.IntelGen -in 13, 14) { A "/!\ Intel Core 13e/14e génération : mets impérativement le BIOS à jour (microcode 0x12B ou plus récent) pour éviter l'usure du processeur." }
    }
    A "  - Courbe des ventilateurs : un peu plus agressive au-dessus de 70 °C si tu actives ces options."
    A ""
  }

  A "=== EN CAS DE PROBLÈME ==="
  if ($p.Profil -eq "OEM") { A "  - Le PC ne démarre plus après un réglage : rentre dans le BIOS et choisis « Load Defaults / Restore Settings », ou contacte le support du constructeur (ne démonte pas un portable sous garantie)." }
  else { A "  - Le PC ne démarre plus après un réglage : Clear CMOS (cavalier ou bouton, voir le manuel), ou retire la pile 1 minute PC débranché." }
  A "  - Dans le doute, « Load Optimized Defaults » (souvent F6 ou F9) remet le BIOS d'usine."
  return ($L -join "`r`n")
}

# Nom de fichier sûr
function Nom-Fichier($s) {
  $n = ("$s" -replace '\(.*?\)', '' -replace '[^A-Za-z0-9_\-\.]+', '-' -replace '-{2,}', '-').Trim('-', '.')
  if (-not $n) { $n = "PC" }; return $n
}

function Export-GuideBios($m, [switch]$Ouvrir) {
  if (-not $m) { $m = Lire-MaterielBios }
  $p = Get-ProfilBios $m
  $texte = Get-GuideBios $m
  $bureau = [Environment]::GetFolderPath("Desktop"); if (-not $bureau) { $bureau = $env:TEMP }
  $mod = if ($p.Modele) { $p.Modele } elseif ($p.ModelePC) { $p.ModelePC } else { "PC" }
  $chemin = Join-Path $bureau "Guide-BIOS-$(Nom-Fichier $mod).txt"
  [IO.File]::WriteAllText($chemin, $texte, (New-Object Text.UTF8Encoding $true))
  if ($Ouvrir) { Start-Process notepad.exe "`"$chemin`"" }
  return $chemin
}

# Lancé directement (pas en dot-source)
if ($MyInvocation.InvocationName -ne '.') {
  try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch {}
  $mat = Lire-MaterielBios
  if ($Exporter) {
    $c = Export-GuideBios $mat -Ouvrir:(-not $SansOuvrir)
    Write-Host "Guide BIOS enregistré : $c" -ForegroundColor Green
  } else { Get-GuideBios $mat }
}
