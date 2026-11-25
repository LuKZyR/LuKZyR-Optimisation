# =====================================================================
#  HELIXFLUX OPTIMISATION v0.1 bêta (version interne 5.3) - Écran de chargement
#  v5.3 : l'écran est en C# compilé (scripts\LkChargement.dll, source dans assets\source-lanceur) :
#  aucun code PowerShell ne tourne sur son fil, et il a plusieurs chemins de fermeture (voir le .cs).
#  Si la DLL manque, on retombe sur l'ancien écran PowerShell, avec les mêmes filets de sécurité.
#  Affiché TOUT DE SUITE au lancement, pendant la détection du matériel.
#  La fenêtre vit dans son propre fil (runspace STA) : son animation ne se fige
#  jamais, même quand le script principal est occupé (compilation, WMI...).
#  Le script principal donne l'étape et le pourcentage via $chg (table partagée).
# =====================================================================
$chg = [hashtable]::Synchronized(@{ Hwnd = [IntPtr]::Zero; Pct = 0.0; Max = 18.0; Etape = ""; Fin = $false; Ferme = $false; Pret = $false; Clair = $false; Version = ""; Logo = ""; Ico = ""; Visible = $false })

# DPI : déclaré avant la 1re fenêtre (sans compilation C#, donc instantané)
function Activer-DpiChargement {
  try {
    $ab = [AppDomain]::CurrentDomain.DefineDynamicAssembly((New-Object Reflection.AssemblyName "LkDpi"), [Reflection.Emit.AssemblyBuilderAccess]::Run)
    $tb = $ab.DefineDynamicModule("LkDpi").DefineType("LkDpiNatif", "Public, Class")
    [void]$tb.DefinePInvokeMethod("SetProcessDPIAware", "user32.dll", [Reflection.MethodAttributes]"Public, Static, PinvokeImpl", [Reflection.CallingConventions]::Standard, [bool], [Type[]]@(), [Runtime.InteropServices.CallingConvention]::Winapi, [Runtime.InteropServices.CharSet]::Auto)
    $ty = $tb.CreateType(); [void]$ty::SetProcessDPIAware()
  } catch {}
}

$codeChargement = {
  $ErrorActionPreference = "SilentlyContinue"
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $g0 = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $s = [math]::Max(1.0, $g0.DpiX / 96.0); $g0.Dispose()
  # (pas de fonction "H" : c'est un alias de Get-History, prioritaire sur les fonctions)
  function S($v) { [float]($v * $s) }
  function Hex($h) { [Drawing.ColorTranslator]::FromHtml($h) }
  if ($chg.Clair) { $cFond = Hex "#f6f6fa"; $cBord = Hex "#dcdce8"; $cTexte = Hex "#1a1a24"; $cGris = Hex "#55556e"; $cAcc = Hex "#7c4dff"; $cPiste = Hex "#e3e3ec" }
  else { $cFond = Hex "#0f0f15"; $cBord = Hex "#26263a"; $cTexte = Hex "#f2f2f7"; $cGris = Hex "#8a8aa3"; $cAcc = Hex "#a78bfa"; $cPiste = Hex "#24242e" }
  $cViolet = Hex "#8c52ff"
  $f = New-Object Windows.Forms.Form
  $f.Text = "HelixFlux Optimisation - preparation"; $f.FormBorderStyle = "None"; $f.StartPosition = "CenterScreen"
  $f.ClientSize = New-Object Drawing.Size([int](S 440), [int](S 270)); $f.BackColor = $cFond; $f.ShowInTaskbar = $true
  $f.GetType().GetProperty("DoubleBuffered", [Reflection.BindingFlags]"NonPublic,Instance").SetValue($f, $true, $null)
  try { if ($chg.Ico -and (Test-Path $chg.Ico)) { $f.Icon = New-Object Drawing.Icon($chg.Ico) } } catch {}
  $logo = $null
  try { if ($chg.Logo -and (Test-Path $chg.Logo)) { $logo = [Drawing.Image]::FromFile($chg.Logo) } elseif ($f.Icon) { $logo = (New-Object Drawing.Icon($chg.Ico, 64, 64)).ToBitmap() } } catch {}
  $polT = New-Object Drawing.Font("Segoe UI", (S 24), [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
  $polS = New-Object Drawing.Font("Segoe UI", (S 12.5), [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
  $polE = New-Object Drawing.Font("Segoe UI", (S 12.5), [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
  $polP = New-Object Drawing.Font("Segoe UI", (S 12.5), [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
  $polV = New-Object Drawing.Font("Segoe UI", (S 10.5), [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
  $st = @{ FinT = -1.0; Peint = $false; Aff = 0.0; Ang = 0.0; Sw = [Diagnostics.Stopwatch]::StartNew(); Der = 0.0; PctVu = -1.0; Depuis = 0.0; Fondu = $false }
  function Arrondi($x, $y, $w, $h, $r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath; $d = [math]::Min($r * 2, [math]::Min($w, $h))
    if ($d -lt 1) { $p.AddRectangle((New-Object Drawing.RectangleF($x, $y, $w, $h))); return $p }
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90); $p.CloseFigure(); return $p
  }
  $f.Add_Paint({
    $g = $_.Graphics; $g.SmoothingMode = "AntiAlias"; $g.InterpolationMode = "HighQualityBicubic"; $g.PixelOffsetMode = "HighQuality"
    $W = $f.ClientSize.Width; $Hh = $f.ClientSize.Height; $t = $st.Sw.Elapsed.TotalSeconds
    $pen = New-Object Drawing.Pen($cBord, [float][math]::Max(1, (S 1))); $g.DrawRectangle($pen, 0, 0, $W - 1, $Hh - 1); $pen.Dispose()
    # halo violet qui respire derrière le logo
    $cx = $W / 2; $cy = S 76; $pu = 0.5 + 0.5 * [math]::Sin($t * 2.4)
    for ($i = 5; $i -ge 0; $i--) {
      $r = (S (30 + $i * 7)) * (1 + 0.05 * $pu); $a = [int]([math]::Max(0, (26 - $i * 4)) * (0.55 + 0.45 * $pu))
      $b = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($a, $cViolet)); $g.FillEllipse($b, [float]($cx - $r), [float]($cy - $r), [float](2 * $r), [float](2 * $r)); $b.Dispose()
    }
    if ($logo) { $g.DrawImage($logo, [float]($cx - (S 28)), [float]($cy - (S 28)), [float](S 56), [float](S 56)) }
    $fl = [Windows.Forms.TextFormatFlags]"HorizontalCenter, VerticalCenter, SingleLine, NoPrefix"
    [Windows.Forms.TextRenderer]::DrawText($g, "HELIXFLUX", $polT, (New-Object Drawing.Rectangle(0, [int](S 112), $W, [int](S 34))), $cAcc, $fl)
    [Windows.Forms.TextRenderer]::DrawText($g, "Optimisation  ·  by Lukzyr", $polS, (New-Object Drawing.Rectangle(0, [int](S 144), $W, [int](S 20))), $cGris, $fl)
    # étape en cours : petit cercle qui tourne + texte + pourcentage
    $xb = S 64; $wb = $W - 2 * $xb; $ye = S 188
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(60, $cAcc), [float](S 2)); $g.DrawEllipse($pen, $xb, $ye, (S 13), (S 13)); $pen.Dispose()
    $pen = New-Object Drawing.Pen($cAcc, [float](S 2)); $pen.StartCap = "Round"; $pen.EndCap = "Round"
    $g.DrawArc($pen, $xb, $ye, (S 13), (S 13), [float]$st.Ang, 100); $pen.Dispose()
    $fe = [Windows.Forms.TextFormatFlags]"Left, VerticalCenter, SingleLine, EndEllipsis, NoPrefix"
    [Windows.Forms.TextRenderer]::DrawText($g, [string]$chg.Etape, $polE, (New-Object Drawing.Rectangle([int]($xb + (S 22)), [int]($ye - (S 4)), [int]($wb - (S 70)), [int](S 22))), $cTexte, $fe)
    $fp = [Windows.Forms.TextFormatFlags]"Right, VerticalCenter, SingleLine, NoPrefix"
    [Windows.Forms.TextRenderer]::DrawText($g, ("{0} %" -f [int][math]::Floor($st.Aff)), $polP, (New-Object Drawing.Rectangle([int]($xb + $wb - (S 60)), [int]($ye - (S 4)), [int](S 60), [int](S 22))), $cAcc, $fp)
    # barre de progression arrondie + reflet qui glisse
    $yb = S 216; $hb = S 6
    $p = Arrondi $xb $yb $wb $hb ($hb / 2); $b = New-Object Drawing.SolidBrush($cPiste); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
    $wf = [float]($wb * [math]::Min(100, $st.Aff) / 100)
    if ($wf -ge 1) {
      $p = Arrondi $xb $yb ([math]::Max($wf, $hb)) $hb ($hb / 2)
      $lg = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.PointF($xb, 0)), (New-Object Drawing.PointF(($xb + $wb), 0)), (Hex "#2f9bff"), $cViolet)
      $g.FillPath($lg, $p); $lg.Dispose()
      $xr = $xb + (($t * 0.6) % 1.4 - 0.2) * $wb; $wr = S 60
      $g.SetClip($p)
      $rb = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.PointF(($xr - $wr), 0)), (New-Object Drawing.PointF(($xr + $wr), 0)), [Drawing.Color]::FromArgb(0, 255, 255, 255), [Drawing.Color]::FromArgb(0, 255, 255, 255))
      $bl = New-Object Drawing.Drawing2D.ColorBlend(3); $bl.Colors = @([Drawing.Color]::FromArgb(0, 255, 255, 255), [Drawing.Color]::FromArgb(110, 255, 255, 255), [Drawing.Color]::FromArgb(0, 255, 255, 255)); $bl.Positions = @([float]0, [float]0.5, [float]1)
      $rb.InterpolationColors = $bl; $g.FillRectangle($rb, [float]($xr - $wr), $yb, [float](2 * $wr), $hb); $rb.Dispose(); $g.ResetClip(); $p.Dispose()
    }
    [Windows.Forms.TextRenderer]::DrawText($g, [string]$chg.Version, $polV, (New-Object Drawing.Rectangle(0, [int](S 238), $W, [int](S 20))), $cGris, $fl)
    $st.Peint = $true
  })
  $tm = New-Object Windows.Forms.Timer; $tm.Interval = 30
  $tm.Add_Tick({
    $t = $st.Sw.Elapsed.TotalSeconds; $dt = [math]::Min(0.2, $t - $st.Der); $st.Der = $t
    $st.Ang = ($st.Ang + 330 * $dt) % 360
    # le titre « chargement » n'apparaît qu'une fois l'écran dessiné : le lanceur .exe passe alors la main sans trou
    if ($st.Peint -and $f.Text -ne "HelixFlux Optimisation - chargement") { $f.Text = "HelixFlux Optimisation - chargement" }
    $p0 = [double]$chg.Pct; $p1 = [double]$chg.Max
    if ($p0 -ne $st.PctVu) { $st.PctVu = $p0; $st.Depuis = $t }
    # pendant une étape, on avance doucement vers la fin de l'étape (sans jamais l'atteindre avant qu'elle soit finie)
    $cible = if ($chg.Fin) { 100 } else { $p0 + ($p1 - $p0) * 0.92 * (1 - [math]::Exp(-($t - $st.Depuis) / 3.0)) }
    if ($cible -gt $st.Aff) { $st.Aff += ($cible - $st.Aff) * [math]::Min(1, $dt * 7) }
    if ($chg.Ferme -or $t -gt 600) { $tm.Stop(); $f.Close(); return }
    if ($chg.Fin) { if ($st.FinT -lt 0) { $st.FinT = $t }; if ($t - $st.FinT -gt 4) { $tm.Stop(); $f.Close(); return } }
    if ($chg.Fin -and $st.Aff -gt 99) { $st.Aff = 100; if ($chg.Pret -or ($st.FinT -ge 0 -and $t - $st.FinT -gt 2.5)) { $st.Fondu = $true } }
    if ($st.Fondu) { $o = $f.Opacity - $dt * 4.5; if ($o -le 0.03) { $tm.Stop(); $f.Close(); return }; $f.Opacity = $o }
    $f.Invalidate()
  })
  $f.Add_Shown({ $chg.Visible = $true; $chg.Hwnd = $f.Handle; $tm.Start() })
  [Windows.Forms.Application]::Run($f)
  $tm.Dispose(); if ($logo) { $logo.Dispose() }
}

$script:modeChargement = ""
function Demarrer-Chargement($racine, $version, $beta = $false) {
  try {
    $pr = Get-ItemProperty -Path "HKCU:\Software\Lukzyr" -ErrorAction SilentlyContinue
    $chg.Clair = ("$($pr.Theme)" -eq "clair")
    $en = if ("$($pr.Langue)" -in @("fr", "en")) { "$($pr.Langue)" -eq "en" } else { (Get-UICulture).TwoLetterISOLanguageName -ne "fr" }
    $chg.Etape = if ($en) { "Loading the interface..." } else { "Chargement de l'interface..." }
    $chg.Version = "v$version" + $(if ($beta) { if ($en) { " beta" } else { " bêta" } } else { "" }); $chg.Pct = 10.0; $chg.Max = 20.0   # suite du lanceur .exe (0 -> 10 %)
    $chg.Logo = Join-Path $racine "assets\logo.png"; $chg.Ico = Join-Path $racine "assets\helixflux.ico"
    if ($env:LK_CHARGEMENT_PS) { throw "écran PowerShell demandé (test)" }
    # DLL chargée depuis ses octets : marche même si le zip téléchargé a « bloqué » les fichiers
    $dll = Join-Path $racine "scripts\LkChargement.dll"
    if (-not ("LkChargement" -as [type])) { [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll)) }
    if (-not [LkChargement]::Start([bool]$chg.Clair, [string]$chg.Version, [string]$racine, [string]$chg.Etape, 10, 20)) { throw ([LkChargement]::DerniereErreur) }
    $script:modeChargement = "dll"
  } catch {
    $script:erreurChargement = "$($_.Exception.Message)"
    try {
      Activer-DpiChargement
      $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = "STA"; $rs.ThreadOptions = "ReuseThread"; $rs.Open()
      $rs.SessionStateProxy.SetVariable("chg", $chg)
      $ps = [powershell]::Create(); $ps.Runspace = $rs; [void]$ps.AddScript($codeChargement)
      $script:chgPs = $ps; $script:chgH = $ps.BeginInvoke(); $script:modeChargement = "ps"
    } catch { $script:chgPs = $null; $script:modeChargement = "" }
  }
}
function Texte-Chargement($texte) { if (Get-Command T -ErrorAction SilentlyContinue) { T $texte } else { $texte } }
# Étape suivante : $pct = début, $max = fin de l'étape (la barre avance doucement entre les deux)
function Etape-Chargement($pct, $max, $texte) {
  try {
    $tx = if ($texte) { Texte-Chargement $texte } else { $null }
    if ($script:modeChargement -eq "dll") { [LkChargement]::Step([float]$pct, [float]$max, $tx); return }
    $chg.Pct = [double]$pct; $chg.Max = [double]$max; if ($tx) { $chg.Etape = $tx }
  } catch {}
}
# v5.3 : la fenêtre principale est entièrement affichée (opaque) : l'écran peut s'effacer en fondu
function Pret-Chargement {
  try {
    if ($script:modeChargement -eq "dll") { [LkChargement]::Ready(); return }
    $chg.Pret = $true
  } catch {}
}
# Fin : la barre file à 100 % puis l'écran s'efface en fondu, une fois la fenêtre principale visible
function Fin-Chargement {
  try {
    $tx = Texte-Chargement "Prêt"
    if ($script:modeChargement -eq "dll") { [LkChargement]::Finish($tx); return }
    $chg.Etape = $tx; $chg.Pct = 100.0; $chg.Max = 100.0; $chg.Fin = $true
  } catch {}
}
# Fermeture garantie (fenêtre fermée, ou filet de sécurité 2 s après l'affichage)
function Fermer-Chargement {
  try {
    if ($script:modeChargement -eq "dll") { [LkChargement]::Close(); return }
    $chg.Fin = $true; $chg.Ferme = $true
    # écran PowerShell : on poste aussi WM_CLOSE à sa fenêtre (marche même si son minuteur ne tourne plus)
    if ($chg.Hwnd -ne [IntPtr]::Zero -and ("LkNative" -as [type])) { [void][LkNative]::PostMessage([IntPtr]$chg.Hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
  } catch {}
}
