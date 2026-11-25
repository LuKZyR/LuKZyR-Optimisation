param([switch]$TestAuto)
# =====================================================================
#  LUKZYR OPTIMISATION v0.1 bêta (version interne 5.11)  -  Tableau de bord
#  Détecte le matériel, propose les pilotes officiels, nettoie et optimise
#  -TestAuto : (tests uniquement) active tout et applique sans confirmation
# =====================================================================
$VersionApp = "0.1"          # version publique (comparée au version.json des mises à jour)
$VersionBeta = $true         # v0.1 bêta = version interne 5.11
$VersionInterne = "5.11"   # comparé comme [version] : 5.11 > 5.10 > 5.9
# Mise à jour automatique : adresse d'un fichier version.json (voir LISEZ-MOI).
# Vide = pas de serveur. Peut aussi être réglée dans C:\ProgramData\Lukzyr\config.json : { "urlMiseAJour": "https://..." }
# v5.7 : le dépôt officiel (avant : adresse vide => « Aucun serveur de mise à jour configuré », rien n'était vérifié)
$UrlMiseAJourDefaut = "https://raw.githubusercontent.com/LuKZyR/LuKZyR-Optimisation/main/version.json"
# 2e source si version.json est absent ou illisible : les releases GitHub du dépôt (pré-versions comprises)
$UrlReleasesDefaut  = "https://api.github.com/repos/LuKZyR/LuKZyR-Optimisation/releases?per_page=5"
# v5.6 : un plantage au démarrage n'est plus invisible : journal ProgramData\Lukzyr\plantage-demarrage.txt + message
$script:fichierPlantage = Join-Path $env:ProgramData "Lukzyr\plantage-demarrage.txt"
function Noter-Plantage($texte) {
  try { [void](New-Item -ItemType Directory -Force (Split-Path $script:fichierPlantage)); [IO.File]::AppendAllText($script:fichierPlantage, "[$(Get-Date -Format s)] $texte`r`n", [Text.Encoding]::UTF8) } catch {}
}
# v5.9 : $details = texte exact de l'erreur (erreurs du compilateur C#, exception) : écrit en entier dans le journal
#        et affiché (raccourci) dans le message, pour savoir enfin POURQUOI ça plante
function Plantage-Demarrage($texte, $details) {
  $infos = ""
  try { $infos = "PowerShell $($PSVersionTable.PSVersion) | CLR $($PSVersionTable.CLRVersion) | " + $(if ([Environment]::Is64BitProcess) { "64 bits" } else { "32 bits" }) + " | Windows $([Environment]::OSVersion.Version) | LuKZyR Optimisation v0.1 bêta (build $VersionInterne)" } catch {}
  $journal = $texte
  if ($details) { $journal += "`r`n--- Détail de l'erreur ---`r`n" + (($details -split "`r?`n") -join "`r`n") }
  if ($infos) { $journal += "`r`n--- Système ---`r`n" + $infos }
  Noter-Plantage $journal
  try { Fermer-Chargement } catch {}
  if (-not $env:LK_TEST) {
    $court = ""
    if ($details) { $court = [string]$details; if ($court.Length -gt 1200) { $court = $court.Substring(0, 1200) + " [...]" }; $court = "`n`nErreur :`n" + $court }
    try { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show(("LuKZyR Optimisation n'a pas pu démarrer :`n`n" + $texte + $court + "`n`nDétails complets : " + $script:fichierPlantage), "LuKZyR Optimisation", "OK", "Error") } catch {}
  }
  exit 3   # 3 = déjà signalé à l'utilisateur (le lanceur n'affiche pas un 2e message)
}
# (pas de « trap » global : il interromprait des fonctions qui continuent normalement après une petite erreur ;
#  les plantages non prévus sont signalés par le lanceur, qui lit la sortie d'erreur de PowerShell)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# v5.10 : une erreur dans l'interface (dessin d'un contrôle...) ne doit plus afficher la boîte « exception non gérée »
#         de WinForms : mode « capturer » réglé AVANT la 1re fenêtre ; le gestionnaire (LkSafe) est branché après la compilation
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch {}
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # v5.6 : UAC refusé = message clair (avant : rien ne se passait)
    $extra = if ($TestAuto) { " -TestAuto" } else { "" }
    try { $pr = Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"$extra" -Verb RunAs -PassThru -ErrorAction Stop }
    catch { [void][Windows.Forms.MessageBox]::Show("LuKZyR Optimisation a besoin des droits administrateur pour modifier les réglages de Windows.`n`nLa demande a été refusée : rien n'a été modifié. Relance l'appli et clique sur « Oui ».", "LuKZyR Optimisation", "OK", "Warning"); exit 1 }
    # on attend la fin de l'appli : si elle s'arrête sur une erreur sans l'avoir signalée (code autre que 0 / 3), on le dit
    try { $pr.WaitForExit(); $codeFin = $pr.ExitCode } catch { $codeFin = 0 }
    if ($codeFin -ne 0 -and $codeFin -ne 3) { [void][Windows.Forms.MessageBox]::Show("LuKZyR Optimisation s'est arrêté de façon inattendue (code $codeFin).`n`nLance plutôt « LuKZyR Optimisation.exe » : il affiche le détail de l'erreur. Les journaux sont dans C:\ProgramData\Lukzyr.", "LuKZyR Optimisation", "OK", "Error") }
    exit $codeFin
}
# v5.2 : écran de chargement affiché TOUT DE SUITE (avant la compilation de l'interface et la détection du matériel)
. (Join-Path (Split-Path -Parent $PSCommandPath) "Chargement.ps1")
Demarrer-Chargement (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) $VersionApp $VersionBeta
# v5.9 : -IgnoreWarnings : Windows PowerShell 5.1 traite les AVERTISSEMENTS du compilateur C# comme des erreurs
#        (en v5.7/5.8, l'avertissement CS1690 sur LkHero.Fill bloquait toute l'interface au démarrage).
#        Les vraies erreurs sont gardées (-ErrorVariable / catch) et écrites dans plantage-demarrage.txt.
$erreursCompil = @(); $exceptionCompil = $null
try { Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -IgnoreWarnings -ErrorAction SilentlyContinue -ErrorVariable erreursCompil -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Drawing.Text; using System.Windows.Forms;
using System.Runtime.InteropServices; using System.Collections.Concurrent; using System.Collections.Generic; using System.Diagnostics; using System.Text;

// v5.10 : filet de sécurité. Une erreur de dessin (ou toute erreur non gérée de l'interface) est écrite dans
// C:\ProgramData\Lukzyr\erreurs-interface.txt et l'appli continue (avant : boîte « exception non gérée » de WinForms).
public static class LkSafe {
  public static string Journal = null; public static int Erreurs = 0, Dessins = 0; public static string Derniere = "";
  static readonly object verrou = new object(); static Dictionary<string, int> vus = new Dictionary<string, int>(); static bool installe;
  public static void Noter(string quoi, Exception ex) {
    try {
      lock (verrou) {
        Erreurs++; Derniere = quoi + " : " + (ex == null ? "?" : ex.GetType().Name + " " + ex.Message);
        string cle = quoi + "|" + (ex == null ? "" : ex.GetType().FullName + "|" + ex.Message); int n; vus.TryGetValue(cle, out n); vus[cle] = n + 1;
        if (n >= 3 || Erreurs > 300 || string.IsNullOrEmpty(Journal)) return;   // la même erreur 3 fois maximum (pas d'avalanche à 60 images/s)
        System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Journal));
        System.IO.File.AppendAllText(Journal, "[" + DateTime.Now.ToString("s") + "] " + quoi + "\r\n" + (ex == null ? "" : ex.ToString()) + "\r\n\r\n", Encoding.UTF8);
      }
    } catch { }
  }
  // appelé par chaque OnPaint / OnPaintBackground des contrôles Lk* : on note, on efface proprement, on continue
  public static void Paint(Control c, Exception ex, PaintEventArgs e) {
    Dessins++; Noter("Dessin " + (c == null ? "?" : c.GetType().Name), ex);
    try { if (c != null && e != null) e.Graphics.Clear(LkCard.BackOf(c)); } catch { }
    try { LkFade f = c as LkFade; if (f != null && f.IsHandleCreated && !f.IsDisposed) f.BeginInvoke((MethodInvoker)delegate { try { f.Stop(); } catch { } }); } catch { }
  }
  public static void Installer(string journal) {
    Journal = journal; if (installe) return; installe = true;
    Application.ThreadException += delegate(object s, System.Threading.ThreadExceptionEventArgs a) { Noter("Erreur non gérée de l'interface (l'appli continue)", a.Exception); };
    AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs a) { Noter("Erreur non gérée" + (a.IsTerminating ? " (arrêt)" : ""), a.ExceptionObject as Exception); };
  }
}

public static class LkNative {
  [DllImport("user32.dll")] public static extern bool ReleaseCapture();
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  // v5.3 : fenêtre de l'Explorateur (CabinetWClass) dont le titre est le dossier ; marche même si l'appli est en administrateur
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  public static bool FenetreExplorateur(string chemin) {
    string c = chemin.TrimEnd('\\'); string nom = System.IO.Path.GetFileName(c); bool ok = false;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      StringBuilder k = new StringBuilder(64); GetClassNameW(h, k, 64); if (k.ToString() != "CabinetWClass") return true;
      StringBuilder t = new StringBuilder(512); GetWindowTextW(h, t, 512); string s = t.ToString().TrimEnd('\\');
      if (s.Equals(nom, StringComparison.OrdinalIgnoreCase) || s.Equals(c, StringComparison.OrdinalIgnoreCase) || s.StartsWith(nom + " ", StringComparison.OrdinalIgnoreCase) || s.StartsWith(nom + " -", StringComparison.OrdinalIgnoreCase)) { ok = true; return false; }
      return true; }, IntPtr.Zero);
    return ok;
  }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string id);
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
  [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
  [StructLayout(LayoutKind.Sequential)] class MEMSTAT { public uint dwLength = 64; public uint dwMemoryLoad; public ulong a, b, c, d, e, f, g; }
  [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx([In, Out] MEMSTAT m);
  static long pi, pk, pu;
  public static int CpuLoad() {
    long i, k, u; if (!GetSystemTimes(out i, out k, out u)) return -1;
    long di = i - pi, dt = (k - pk) + (u - pu); pi = i; pk = k; pu = u;
    if (dt <= 0) return 0; return (int)Math.Max(0, Math.Min(100, 100 - di * 100 / dt));
  }
  [DllImport("user32.dll")] static extern bool SystemParametersInfo(int a, int b, ref int v, int c);
  // Réglage Windows « Afficher les animations dans Windows » (SPI_GETCLIENTAREAANIMATION)
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumDisplaySettingsW")] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  // v5.5 : fréquence actuelle de l'écran principal et maximum proposé à la même résolution
  public static int[] Frequences() {
    try {
      DEVMODE d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
      if (!EnumDisplaySettings(null, -1, ref d)) return new int[] { 0, 0 };
      int cur = d.dmDisplayFrequency, max = cur;
      for (int i = 0; i < 2000; i++) {
        DEVMODE m = new DEVMODE(); m.dmSize = d.dmSize;
        if (!EnumDisplaySettings(null, i, ref m)) break;
        if (m.dmPelsWidth == d.dmPelsWidth && m.dmPelsHeight == d.dmPelsHeight && m.dmDisplayFrequency > max) max = m.dmDisplayFrequency;
      }
      return new int[] { cur, max };
    } catch { return new int[] { 0, 0 }; }
  }
  public static bool SystemAnimations() { int v = 1; try { if (SystemParametersInfo(0x1042, 0, ref v, 0)) return v != 0; } catch { } return true; }
  public static int RamLoad() { MEMSTAT m = new MEMSTAT(); return GlobalMemoryStatusEx(m) ? (int)m.dwMemoryLoad : -1; }
  // Gèle / dégèle le dessin d'un conteneur (WM_SETREDRAW) : échange de pages en une seule image
  public static void Redraw(Control c, bool on) { SendMessage(c.Handle, 0x0B, (IntPtr)(on ? 1 : 0), IntPtr.Zero); if (on) c.Refresh(); }
  public static void Drag(Form f) { ReleaseCapture(); SendMessage(f.Handle, 0xA1, (IntPtr)2, IntPtr.Zero); }
  // v5.10 : rectangle utilisable par LinearGradientBrush (largeur et hauteur >= 1, jamais NaN / infini)
  public static float Fini(float v) { return float.IsNaN(v) || float.IsInfinity(v) ? 0f : Math.Max(-100000f, Math.Min(100000f, v)); }
  public static RectangleF R1(RectangleF r) { return new RectangleF(Fini(r.X), Fini(r.Y), Math.Max(1f, Fini(r.Width)), Math.Max(1f, Fini(r.Height))); }
  public static GraphicsPath Round(RectangleF r, float rad) {
    r = new RectangleF(Fini(r.X), Fini(r.Y), Math.Max(0f, Fini(r.Width)), Math.Max(0f, Fini(r.Height))); rad = Math.Max(0f, Fini(rad));
    GraphicsPath p = new GraphicsPath(); float d = Math.Min(rad * 2, Math.Min(r.Width, r.Height));
    if (d < 1) { p.AddRectangle(r); return p; }
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
    p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
  }
}

// Moteur d'animation : UN seul minuteur WinForms (15 ms) pour toute l'appli, qui ne tourne
// que pendant une animation. Tout est calculé en C# (rien par image côté PowerShell).
// LkAnim.On = false -> chaque animation saute directement à son état final.
public static class LkAnim {
  public static bool On = true;
  public static bool Closing = false;
  public static float Lent = 1f;             // tests uniquement : ralenti (ex. 6 = six fois plus lent)
  public static int Erreurs = 0; public static string DerniereErreur = "";
  // v5.5 : UN seul minuteur (~60 images/s) pour toute l'appli ; il s'arrête dès que plus rien n'anime.
  // Les « boucles » (pulsations pendant une exécution) sont mises en pause quand la fenêtre est
  // réduite ou inactive, et ne tournent jamais au repos.
  static Timer t; static List<Func<bool>> jobs = new List<Func<bool>>(); static List<Func<bool>> boucles = new List<Func<bool>>();
  public static bool Reduit = false;          // option « Animations réduites » : courtes, sans glissement ni boucle
  static bool pause;
  public static bool Pause { get { return pause; } set { pause = value; if (!pause && boucles.Count > 0) Demarrer(); } }
  public static bool Boucles { get { return On && !Reduit && !Closing; } }
  public static long Images = 0;              // images calculées (mesures de consommation)
  public static bool Actif { get { return t != null && t.Enabled; } }
  public static int NbJobs { get { return jobs.Count; } }
  public static int NbBoucles { get { return boucles.Count; } }
  static void Demarrer() { if (t == null) { t = new Timer(); t.Interval = 16; t.Tick += Tick; } if (!t.Enabled) t.Start(); }
  public static void Add(Func<bool> step) { jobs.Add(step); Demarrer(); }
  public static void AddLoop(Func<bool> step) { boucles.Add(step); if (!pause) Demarrer(); }
  static void Run(List<Func<bool>> l) {
    for (int i = l.Count - 1; i >= 0; i--) {
      if (i >= l.Count) continue;
      bool keep; try { keep = l[i](); } catch (Exception ex) { keep = false; Erreurs++; DerniereErreur = ex.ToString(); }
      if (!keep && i < l.Count) l.RemoveAt(i);
    }
  }
  static void Tick(object s, EventArgs e) {
    Images++;
    Run(jobs);
    if (!pause) Run(boucles);
    if (jobs.Count == 0 && (boucles.Count == 0 || pause)) t.Stop();
  }
  // Apparition échelonnée : les éléments visibles d'une page montent de dy pixels, l'un après l'autre
  static int stTok;
  public static void Stagger(Control parent, int dy, int ms, int pas, int max) {
    int my = ++stTok;
    if (!On || Reduit || parent == null || ms <= 0) return;
    int vis = parent.Parent != null ? parent.Parent.ClientSize.Height : parent.Height;
    List<Control> l = new List<Control>();
    foreach (Control c in parent.Controls) { if (!c.Visible) continue; int y = c.Top + (parent.Parent is ScrollableControl || parent.Top < 0 ? parent.Top : 0); if (y < vis && y + c.Height > 0) l.Add(c); }
    l.Sort((a, b) => a.Top != b.Top ? a.Top.CompareTo(b.Top) : a.Left.CompareTo(b.Left));
    if (l.Count > max) l.RemoveRange(max, l.Count - max);
    if (l.Count == 0) return;
    int n = l.Count; int[] cible = new int[n]; int[] pose = new int[n]; bool[] fini = new bool[n];
    for (int k = 0; k < n; k++) { cible[k] = l[k].Top; pose[k] = cible[k] + dy; l[k].Top = pose[k]; }
    int dur = Math.Max(1, (int)(ms * Lent)); Stopwatch sw = Stopwatch.StartNew();
    Add(() => {
      bool reste = false; long el = sw.ElapsedMilliseconds;
      for (int k = 0; k < n; k++) {
        if (fini[k]) continue;
        Control c = l[k];
        if (c.IsDisposed || c.Top != pose[k]) { fini[k] = true; continue; }   // déplacé ailleurs entre-temps : on n'y touche plus
        float p = my != stTok ? 1f : Math.Max(0f, Math.Min(1f, (float)(el - k * pas) / dur));
        int y = cible[k] + (int)Math.Round(dy * (1f - Ease(p)));
        if (y != c.Top) { c.Top = y; pose[k] = y; }
        if (p >= 1f) fini[k] = true; else reste = true;
      }
      return reste;
    });
  }
  public static float Ease(float p) { float q = 1f - p; return 1f - q * q * q; }
  public static float Ease5(float p) { float q = 1f - p; return 1f - q * q * q * q * q; }
  // v5.3 : variante avec courbe au choix (glissement des pages plus doux à l'arrivée)
  public static void TweenQ(int ms, Action<float> apply, Action done) {
    if (!On || ms <= 0) { apply(1f); if (done != null) done(); return; }
    if (Reduit) ms = Math.Min(ms, 120);
    ms = Math.Max(1, (int)(ms * Lent)); Stopwatch sw = Stopwatch.StartNew(); apply(0f);
    Add(() => { float p = Math.Min(1f, (float)sw.ElapsedMilliseconds / ms); apply(Ease5(p)); if (p >= 1f) { if (done != null) done(); return false; } return true; });
  }
  public static Color Mix(Color a, Color b, float p) {
    if (float.IsNaN(p) || p <= 0f) return a; if (p >= 1f) return b;   // v5.10 : NaN -> a (avant : exception dans Color.FromArgb)
    return Color.FromArgb(C255(a.A + (b.A - a.A) * p), C255(a.R + (b.R - a.R) * p), C255(a.G + (b.G - a.G) * p), C255(a.B + (b.B - a.B) * p));
  }
  public static int C255(float v) { return float.IsNaN(v) ? 0 : (int)Math.Max(0f, Math.Min(255f, v)); }
  // Interpolation de 0 à 1 (adoucie) sur ms millisecondes ; apply(p) est appelée à chaque image
  public static void Tween(int ms, Action<float> apply, Action done) {
    if (!On || ms <= 0) { apply(1f); if (done != null) done(); return; }
    if (Reduit) ms = Math.Min(ms, 120);
    ms = Math.Max(1, (int)(ms * Lent));
    Stopwatch sw = Stopwatch.StartNew();
    apply(0f);
    Add(() => {
      float p = Math.Min(1f, (float)sw.ElapsedMilliseconds / ms);
      apply(Ease(p));
      if (p >= 1f) { if (done != null) done(); return false; }
      return true;
    });
  }
  // Fenêtre : apparition / disparition en fondu
  public static void FadeIn(Form f, int ms) { if (!On) { f.Opacity = 1; return; } Tween(ms, p => { try { f.Opacity = Math.Max(0.01, p); } catch { } }, () => { try { f.Opacity = 1; } catch { } }); }
  public static void FadeClose(Form f, int ms) {
    Closing = true;
    if (!On) { f.Close(); return; }
    double o0 = f.Opacity;
    Tween(ms, p => { try { f.Opacity = o0 * (1 - p); } catch { } }, () => f.Close());
  }
  // Changement de page : glissement court + titre en fondu
  static int slideTok;
  public static void SlideIn(Control c, int dx, int ms) {
    int my = ++slideTok;
    if (!On || Reduit) { c.Left = 0; return; }
    TweenQ(ms, p => { if (my == slideTok) c.Left = (int)Math.Round(dx * (1f - p)); }, () => { if (my == slideTok) c.Left = 0; });
  }
  public static void FadeFore(Control c, Color from, Color to, int ms) {
    Tween(ms, p => { c.ForeColor = Mix(from, to, p); }, null);
  }
  // Indicateur de sélection qui glisse verticalement
  static int moveTok;
  public static void MoveY(Control c, int y, int ms) {
    int my = ++moveTok; int y0 = c.Top;
    Tween(ms, p => { if (my == moveTok) c.Top = (int)Math.Round(y0 + (y - y0) * p); }, null);
  }
  // Soulignement des onglets : glisse et change de largeur
  static int tabTok;
  public static void MoveXW(Control c, int x, int w, int ms) {
    int my = ++tabTok; int x0 = c.Left, w0 = c.Width;
    Tween(ms, p => { if (my == tabTok) c.SetBounds((int)Math.Round(x0 + (x - x0) * p), c.Top, (int)Math.Round(w0 + (w - w0) * p), c.Height); }, null);
  }
  // v5.1 : le soulignement est posé TOUT DE SUITE sous le bon onglet (même si l'interface est occupée),
  // puis s'élargit depuis le centre ; s'il n'y a pas d'animation, il est déjà à sa place finale.
  public static void PlaceXW(Control c, int x, int w, int ms) {
    int my = ++tabTok;
    if (!On || ms <= 0) { c.SetBounds(x, c.Top, w, c.Height); c.Update(); return; }
    int w0 = Math.Max(4, (int)(w * 0.55f));
    c.SetBounds(x + (w - w0) / 2, c.Top, w0, c.Height); c.Update();
    Tween(ms, p => { if (my == tabTok) { int ww = (int)Math.Round(w0 + (w - w0) * p); c.SetBounds(x + (w - ww) / 2, c.Top, ww, c.Height); } }, () => { if (my == tabTok) c.SetBounds(x, c.Top, w, c.Height); });
  }
  // Nombre qui défile jusqu'à sa valeur (1er affichage des statistiques)
  public static void CountTo(Label l, int to, string suffix, int ms) {
    if (!On || Reduit) { l.Text = to.ToString() + suffix; return; }
    Tween(ms, p => { l.Text = ((int)Math.Round(to * p)).ToString() + suffix; }, null);
  }
}

// Petite barre violette arrondie qui marque la page active dans la barre latérale
public class LkIndicator : Control {
  public Color Fill = Color.FromArgb(167, 139, 250); public Color Fill2 = Color.Empty;
  public LkIndicator() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(Parent != null ? Parent.BackColor : BackColor); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    if (Width < 2 || Height < 1) return;
    using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, Width - 1, Height - 1), (Math.Min(Width, Height) - 1) / 2f))
    using (Brush b = Fill2.IsEmpty ? (Brush)new SolidBrush(Fill) : new LinearGradientBrush(LkNative.R1(new RectangleF(-1, 0, Width + 2, Height)), Fill2, Fill, 0f)) e.Graphics.FillPath(b, p);
  }
}

// Panneau double tampon (pages sans défilement) : pas de scintillement pendant les glissements
public class LkPanel : Panel {
  public LkPanel() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true); }
}

// Carte à coins arrondis (fond = couleur du parent, remplissage = Fill) ; survol et sélection en fondu
public class LkCard : Panel {
  public Color Fill = Color.FromArgb(23, 23, 31); public int Radius = 12; bool hover; public Color HoverFill = Color.Empty;
  Color shown = Color.Empty; int tok; float hp; public Color Glow = Color.FromArgb(167, 139, 250);
  // v5.7 : bordure fine (définit la carte sans l'alourdir) ; au survol elle glisse vers HoverBorder
  public Color Border = Color.Empty, HoverBorder = Color.Empty;
  public static Color BordDefaut = Color.Empty, BordSurvolDefaut = Color.Empty; public bool BordAuto = true;   // bordure du thème (changée en un coup)
  // v5.7 : rendu « composé » (WS_EX_COMPOSITED) : la carte et ses textes sont peints ensemble, d'un seul bloc,
  // plus de texte qui « clignote » au survol ou pendant un défilement. Coupé automatiquement si la carte
  // contient une zone de texte (curseur clignotant) ou si l'option Paramètres > Rendu lissé est désactivée.
  public static bool Compose = true; public static bool Instant = false;
  public bool Composited = true;
  public LkCard() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  bool DansCompose() { for (Control p = Parent; p != null; p = p.Parent) { LkCard k = p as LkCard; if (k != null && k.Composited && Compose) return true; if (p is LkHero && Compose) return true; } return false; }
  protected override CreateParams CreateParams { get { CreateParams cp = base.CreateParams; if (Compose && Composited && !DansCompose()) cp.ExStyle |= 0x02000000; return cp; } }
  protected override void OnControlAdded(ControlEventArgs e) {
    base.OnControlAdded(e);
    if (Composited && (e.Control is TextBoxBase || e.Control is WebBrowserBase)) { Composited = false; if (IsHandleCreated) UpdateStyles(); }
  }
  Color Target { get { return hover && !HoverFill.IsEmpty ? HoverFill : Fill; } }
  public Color CurrentFill { get { return shown.IsEmpty ? Target : shown; } }
  public static Color BackOf(Control c) {
    if (c.Parent == null) return c.BackColor; LkCard k = c.Parent as LkCard; if (k != null) return k.CurrentFill;
    LkHero h = c.Parent as LkHero; if (h != null) { Color hf = h.Fill; if (!hf.IsEmpty) return hf; }   // v5.9 : copie locale (évite l'avertissement CS1690)
    return c.Parent.BackColor; }
  public void SetHover(bool h) { if (HoverFill.IsEmpty || hover == h) return; Color from = CurrentFill; hover = h; Retarget(from); }
  public void SetFill(Color c) { Color from = CurrentFill; Fill = c; Retarget(from); }
  void Retarget(Color from) {
    Color to = Target; int my = ++tok;
    float h0 = hp, h1 = hover ? 1f : 0f;
    if (Instant || !IsHandleCreated || !Visible) { shown = to; hp = h1; Sync(); return; }
    LkAnim.Tween(160, p => { if (my != tok) return; shown = LkAnim.Mix(from, to, p); hp = h0 + (h1 - h0) * p; Sync(); }, null);
  }
  void Sync() { Color c0 = CurrentFill; foreach (Control c in Controls) { if (c is Label) c.BackColor = c0; else c.Invalidate(); } Invalidate(); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, Width - 0.5f, Height - 0.5f), Radius))
    using (SolidBrush b = new SolidBrush(CurrentFill)) e.Graphics.FillPath(b, p);
    Color b0 = !Border.IsEmpty ? Border : (BordAuto ? BordDefaut : Color.Empty);
    Color b1 = !HoverBorder.IsEmpty ? HoverBorder : (BordAuto && !HoverFill.IsEmpty ? BordSurvolDefaut : Color.Empty);
    if (!b0.IsEmpty) {
      Color bc = b1.IsEmpty ? b0 : LkAnim.Mix(b0, b1, hp);
      using (GraphicsPath p = LkNative.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Math.Max(1, Radius - 0.5f)))
      using (Pen pn = new Pen(bc, 1f)) e.Graphics.DrawPath(pn, p);
    }
    base.OnPaint(e);
  }
}

// Interrupteur style iOS
public class LkToggle : Control {
  bool on; float pos; int tok; public Color OnColor = Color.FromArgb(140, 82, 255); public Color OffColor = Color.FromArgb(51, 51, 74);
  public event EventHandler CheckedChanged;
  public LkToggle() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true); Cursor = Cursors.Hand; }
  public bool Checked { get { return on; } set { if (on == value) return; on = value; Glisse(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); } }
  // Le bouton rond glisse et la couleur passe progressivement du gris au violet
  void Glisse() {
    float from = pos, to = on ? 1f : 0f; int my = ++tok;
    if (!IsHandleCreated || !Visible) { pos = to; Invalidate(); return; }
    LkAnim.Tween(170, p => { if (my != tok) return; pos = from + (to - from) * p; Invalidate(); }, null);
  }
  protected override void OnClick(EventArgs e) { Checked = !Checked; base.OnClick(e); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    float h = Height - 1, w = Width - 1;
    using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, w, h), h / 2)) using (SolidBrush b = new SolidBrush(LkAnim.Mix(OffColor, OnColor, pos))) g.FillPath(b, p);
    float m = h * 0.125f, k = h - 2 * m; float x = m + (w - 2 * m - k) * pos;
    using (SolidBrush b = new SolidBrush(Color.White)) g.FillEllipse(b, x, m, k, k);
  }
}

// Petite barre de progression arrondie (0-100, -1 = vide)
public class LkBar : Control {
  int v; float shown; int tok; bool busy; float phase; public Color Track = Color.FromArgb(35, 35, 45); public Color Fill = Color.FromArgb(140, 82, 255);
  public Color Fill2 = Color.Empty;   // v5.5 : si défini, dégradé Fill2 -> Fill (couleurs du logo)
  public LkBar() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  // La barre glisse de l'ancienne valeur vers la nouvelle
  public int Value { get { return v; } set {
    int n = Math.Max(0, Math.Min(100, value)); if (n == v) return; v = n;
    float from = shown, to = n; int my = ++tok;
    if (!IsHandleCreated || !Visible) { shown = to; Invalidate(); return; }
    // v5.5 : petits écarts (jauges du tableau de bord) = mise à jour directe, sans animation
    if (Math.Abs(to - from) < 4f) { ++tok; shown = to; Invalidate(); return; }
    LkAnim.Tween(450, p => { if (my != tok) return; shown = from + (to - from) * p; Invalidate(); }, null);
  } }
  // Mode « en cours » : un reflet lumineux balaie la barre en boucle
  public bool Busy { get { return busy; } set {
    if (busy == value) return; busy = value; Invalidate();
    Lancer();
  } }
  // v5.5 : la boucle ne tourne que si la barre est réellement affichée (page cachée ou barre retirée = arrêt)
  bool boucle; Stopwatch swB = Stopwatch.StartNew();
  void Lancer() {
    if (boucle || !busy || !LkAnim.Boucles || IsDisposed || Parent == null || !Visible) return; boucle = true;
    LkAnim.AddLoop(() => { if (!busy || IsDisposed || Parent == null || !Visible) { boucle = false; Invalidate(); return false; } phase = (swB.ElapsedMilliseconds % 1400) / 1400f; Invalidate(); return true; });
  }
  protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); Lancer(); }
  protected override void OnParentChanged(EventArgs e) { base.OnParentChanged(e); Lancer(); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; float r = Height / 2f;
    using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, Width - 1, Height - 1), r)) using (SolidBrush b = new SolidBrush(Track)) g.FillPath(b, p);
    float w = (Width - 1) * shown / 100f;
    if (w >= 1) { if (w < Height) w = Height; using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, w, Height - 1), r)) using (Brush b = Fill2.IsEmpty ? (Brush)new SolidBrush(Fill) : new LinearGradientBrush(LkNative.R1(new RectangleF(-1, 0, Width + 2, Height)), Fill2, Fill, 0f)) g.FillPath(b, p); }
    if (busy && LkAnim.On) {
      float sw = (Width - 1) * 0.22f, x = -sw + (Width - 1 + sw) * phase;
      using (GraphicsPath clip = LkNative.Round(new RectangleF(0, 0, Width - 1, Height - 1), r)) {
        g.SetClip(clip);
        using (LinearGradientBrush lb = new LinearGradientBrush(LkNative.R1(new RectangleF(x - 1, 0, sw + 2, Height)), Color.FromArgb(0, 200, 180, 255), Color.FromArgb(0, 200, 180, 255), 0f)) {
          ColorBlend cb = new ColorBlend(3); cb.Colors = new Color[] { Color.FromArgb(0, 200, 180, 255), Color.FromArgb(230, 200, 180, 255), Color.FromArgb(0, 200, 180, 255) }; cb.Positions = new float[] { 0f, 0.5f, 1f };
          lb.InterpolationColors = cb; g.FillRectangle(lb, x, 0, sw, Height);
        }
        g.ResetClip();
      }
    }
  }
}

// Bouton arrondi
public class LkButton : Control {
  public Color Fill = Color.FromArgb(140, 82, 255), HoverFill = Color.FromArgb(124, 66, 240), DisabledFill = Color.FromArgb(60, 50, 90); public int Radius = 10;
  public Color Fill2 = Color.Empty;   // v5.7 : si défini, dégradé Fill2 (gauche) -> Fill (droite)
  public string Icon = null;
  float h; int tok; bool pressed; bool busy; float pulse; int dots;
  public LkButton() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); Cursor = Cursors.Hand; ForeColor = Color.White; }
  // Survol : la couleur glisse en douceur
  void Survol(float to) { float from = h; int my = ++tok; LkAnim.Tween(130, p => { if (my != tok) return; h = from + (to - from) * p; Invalidate(); }, null); }
  protected override void OnMouseEnter(EventArgs e) { Survol(1f); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { pressed = false; Survol(0f); base.OnMouseLeave(e); }
  // Appui : le bouton s'enfonce légèrement
  protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left && Enabled) { pressed = true; Invalidate(); } base.OnMouseDown(e); }
  protected override void OnMouseUp(MouseEventArgs e) { if (pressed) { pressed = false; Invalidate(); } base.OnMouseUp(e); }
  // Pendant l'exécution : couleur qui pulse et points de suspension animés
  public bool Busy { get { return busy; } set {
    if (busy == value) return; busy = value; Invalidate();
    Lancer();
  } }
  bool boucle; Stopwatch swB = Stopwatch.StartNew();
  void Lancer() {
    if (boucle || !busy || !LkAnim.Boucles || IsDisposed || Parent == null || !Visible) return; boucle = true;
    LkAnim.AddLoop(() => {
      if (!busy || IsDisposed || Parent == null || !Visible) { boucle = false; pulse = 0f; Invalidate(); return false; }
      long ms = swB.ElapsedMilliseconds; pulse = (float)(0.5 - 0.5 * Math.Cos(ms * 2 * Math.PI / 1300.0)); dots = (int)(ms / 400 % 4); Invalidate(); return true; });
  }
  protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); Lancer(); }
  protected override void OnParentChanged(EventArgs e) { base.OnParentChanged(e); Lancer(); }
  protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
  protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
  public void PerformClick() { if (Enabled) OnClick(EventArgs.Empty); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    Color c; string txt = Text;
    if (busy) {
      c = LkAnim.On ? LkAnim.Mix(Fill, Color.FromArgb(178, 140, 255), pulse * 0.55f) : Fill;
      if (LkAnim.On) txt = Text.TrimEnd('.', ' ') + new string('.', dots).PadRight(3);
    } else c = !Enabled ? DisabledFill : LkAnim.Mix(Fill, HoverFill, h);
    RectangleF rc = new RectangleF(0, 0, Width - 1, Height - 1);
    if (pressed) { float d = Math.Max(1f, Height * 0.04f); rc.Inflate(-d, -d); c = LkAnim.Mix(c, Color.Black, 0.12f); }
    using (GraphicsPath p = LkNative.Round(rc, Radius)) {
      if (!Fill2.IsEmpty && Enabled && rc.Width > 2) {
        Color c2 = LkAnim.Mix(Fill2, Color.Black, h * 0.12f + (pressed ? 0.12f : 0f));
        using (LinearGradientBrush b = new LinearGradientBrush(LkNative.R1(new RectangleF(rc.X - 1, rc.Y, rc.Width + 2, rc.Height)), c2, c, 0f)) g.FillPath(b, p);
      } else using (SolidBrush b = new SolidBrush(c)) g.FillPath(b, p);
    }
    Color fc = (Enabled || busy) ? ForeColor : Color.FromArgb(190, 190, 210);
    if (Icon != null && !busy) {
      TextFormatFlags tf = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding;
      float isz = Font.Size * 1.15f, gap = Font.Size * 0.5f; int tw = TextRenderer.MeasureText(g, txt, Font, Size.Empty, tf).Width;
      float x0 = rc.X + (rc.Width - (isz + gap + tw)) / 2f;
      LkIcons.Draw(g, Icon, new RectangleF(x0, rc.Y + (rc.Height - isz) / 2f, isz, isz), fc, 2.2f);
      TextRenderer.DrawText(g, txt, Font, new Rectangle((int)(x0 + isz + gap), (int)rc.Y, tw + 4, (int)rc.Height), fc, tf);
    } else TextRenderer.DrawText(g, txt, Font, Rectangle.Round(rc), fc, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix);
  }
}

// Zone défilante sans barre Windows : molette + fine barre violette dessinée
public class LkScroll : Panel, IMessageFilter {
  public Panel Content = new LkPanel(); int off; public int Bar = 8; public Color Thumb = Color.FromArgb(60, 60, 80);
  // v5.7 : molette = défilement doux (le contenu glisse vers sa cible), pas de saut de 60 px
  public int Step = 60; int target; bool glisse; bool drag; int dragY0, dragOff0;
  public LkScroll() {
    SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    Controls.Add(Content); Application.AddMessageFilter(this);
  }
  public void Recalc() {
    int h = 0; foreach (Control c in Content.Controls) h = Math.Max(h, c.Bottom);
    Content.BackColor = BackColor; Content.Width = Width - Bar - 4; Content.Height = Math.Max(h + 4, Height); ScrollTo(off);
  }
  int Borne(int y) { return Math.Max(0, Math.Min(y, Content.Height - Height)); }
  public int Offset { get { return off; } }
  void Barre() { Invalidate(new Rectangle(Math.Max(0, Width - Bar - 2), 0, Bar + 2, Height)); }
  public void ScrollTo(int y) { off = target = Borne(y); if (Content.Top != -off) Content.Top = -off; Barre(); }
  public void ScrollSmooth(int y) {
    target = Borne(y);
    if (!LkAnim.On || LkAnim.Reduit || !Visible) { ScrollTo(target); return; }
    if (glisse) return; glisse = true;
    Stopwatch sw = Stopwatch.StartNew(); long last = 0;
    LkAnim.Add(() => {
      if (IsDisposed || !Visible) { glisse = false; return false; }
      long now = sw.ElapsedMilliseconds; double dt = Math.Max(1, now - last); last = now;
      int d = target - off;
      if (Math.Abs(d) <= 1) { off = target; Content.Top = -off; Barre(); glisse = false; return false; }
      int pas = (int)Math.Round(d * (1.0 - Math.Exp(-dt / 55.0))); if (pas == 0) pas = Math.Sign(d);
      off += pas; Content.Top = -off; Barre(); return true;
    });
  }
  Rectangle Pouce() {
    if (Content.Height <= Height) return Rectangle.Empty;
    float th = Math.Max(30f, (float)Height * Height / Content.Height); float ty = (Height - th) * off / (float)(Content.Height - Height);
    return new Rectangle(Width - Bar - 2, (int)ty, Bar + 2, (int)th);
  }
  protected override void OnMouseDown(MouseEventArgs e) {
    base.OnMouseDown(e);
    if (e.Button != MouseButtons.Left || Content.Height <= Height || e.X < Width - Bar - 4) return;
    Rectangle p = Pouce();
    if (!p.Contains(e.Location)) { ScrollSmooth(off + (e.Y < p.Top ? -Height : Height) * 9 / 10); return; }
    drag = true; dragY0 = e.Y; dragOff0 = off; Capture = true;
  }
  protected override void OnMouseMove(MouseEventArgs e) {
    base.OnMouseMove(e);
    if (!drag) return;
    Rectangle p = Pouce(); float course = Height - p.Height; if (course < 1) return;
    ScrollTo(dragOff0 + (int)((e.Y - dragY0) * (Content.Height - Height) / course));
  }
  protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); drag = false; Capture = false; }
  public bool PreFilterMessage(ref Message m) {
    if (m.Msg != 0x020A || !Visible || Content.Height <= Height) return false;
    Control p = this; while (p != null) { if (!p.Visible) return false; p = p.Parent; }
    if (!RectangleToScreen(ClientRectangle).Contains(Cursor.Position)) return false;
    int delta = (short)((long)m.WParam >> 16); ScrollSmooth((glisse ? target : off) - delta * Step / 120); return true;
  }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    e.Graphics.Clear(BackColor);
    if (Content.Height <= Height) return;
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    float th = Math.Max(30f, (float)Height * Height / Content.Height); float ty = (Height - th) * off / (float)(Content.Height - Height);
    using (GraphicsPath p = LkNative.Round(new RectangleF(Width - Bar + 2, ty, Bar - 4, th), (Bar - 4) / 2f)) using (SolidBrush b = new SolidBrush(Thumb)) e.Graphics.FillPath(b, p);
  }
  protected override void OnResize(EventArgs e) { base.OnResize(e); Recalc(); }
  protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); if (Visible) Recalc(); }
  protected override void Dispose(bool d) { Application.RemoveMessageFilter(this); base.Dispose(d); }
}

// Badge / pastille teintée : fond = couleur d'accent en transparence sur le fond du parent, texte = accent.
// Light = thème clair (accent plus foncé pour rester lisible). Sert aussi de carré d'icône (Segoe MDL2).
public class LkBadge : Control {
  public static bool Light = false;
  public Color Accent = Color.FromArgb(52, 211, 153), AccentLight = Color.Empty; public int Radius = 6; public int Alpha = 34;
  public string Icon = null; public float IconSize = 0;
  public LkBadge() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  public Color Ink { get { return (Light && !AccentLight.IsEmpty) ? AccentLight : Accent; } }
  protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    Color k = Ink;
    using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, Width - 1, Height - 1), Radius)) using (SolidBrush b = new SolidBrush(Color.FromArgb(Light ? Alpha + 6 : Alpha, k))) g.FillPath(b, p);
    if (Icon != null) {
      float sz = IconSize > 0 ? IconSize : Height * 0.5f;
      if (string.IsNullOrEmpty(Text)) { LkIcons.Draw(g, Icon, new RectangleF((Width - sz) / 2f, (Height - sz) / 2f, sz, sz), k, 2f); return; }
      float pad = Height * 0.3f;
      LkIcons.Draw(g, Icon, new RectangleF(pad, (Height - sz) / 2f, sz, sz), k, 2.4f);
      TextRenderer.DrawText(g, Text, Font, new Rectangle((int)(pad + sz + Height * 0.18f), 0, Width, Height), k, LkCard.BackOf(this), TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
      return;
    }
    TextRenderer.DrawText(g, Text, Font, new Rectangle(0, 0, Width, Height), k, LkCard.BackOf(this), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
  }
}

// v5.2 : jeu d'icônes vectoriel (grille 24, trait 2, bouts ronds, style Lucide/Fluent), net à toutes les échelles.
// Une icône = une liste de formes : l (ligne) p/P (polyligne ouverte/fermée) c (cercle) e (ellipse) a (arc)
// b (courbe de Bézier) r (rectangle arrondi) f (point plein) g (roue dentée).
public static class LkIcons {
  static readonly Dictionary<string, string> defs = new Dictionary<string, string> {
    {"sun", "c 12 12 4; l 12 2 12 4; l 12 20 12 22; l 4.93 4.93 6.34 6.34; l 17.66 17.66 19.07 19.07; l 2 12 4 12; l 20 12 22 12; l 6.34 17.66 4.93 19.07; l 19.07 4.93 17.66 6.34"},
    {"moon", "a 12 12 9 0 270; a 16.5 7.5 6.364 225 -180"},
    {"settings", "g 12 12 9.6 7.4 8; c 12 12 3"},
    {"x", "l 18 6 6 18; l 6 6 18 18"},
    {"minus", "l 5 12 19 12"},
    {"home", "p 3 11 12 3.5 21 11; p 5.5 9 5.5 20.5 10 20.5 10 14.5 14 14.5 14 20.5 18.5 20.5 18.5 9"},
    {"list", "l 8.5 6 21 6; l 8.5 12 21 12; l 8.5 18 21 18; f 4 6 1.3; f 4 12 1.3; f 4 18 1.3"},
    {"sliders", "l 3 7 13 7; l 19 7 21 7; c 16 7 2.6; l 3 17 5 17; l 11 17 21 17; c 8 17 2.6"},
    {"search", "c 11 11 7; l 21 21 16 16"},
    {"chevron", "p 9 18 15 12 9 6"},
    {"check", "p 20 6 9 17 4 12"},
    {"check-circle", "c 12 12 10; p 8 12.3 11 15.2 16.2 9.3"},
    {"x-circle", "c 12 12 10; l 15 9 9 15; l 9 9 15 15"},
    {"alert", "P 12 3.2 21.6 20 2.4 20; l 12 9.5 12 13.5; f 12 16.8 1.2"},
    {"info", "c 12 12 10; l 12 11 12 16.5; f 12 7.8 1.2"},
    {"heart", "l 12 21 5 14; b 5 14 3.5 12.55 2 10.8 2 8.5; a 7.5 8.5 5.5 180 90; b 7.5 3 9.26 3 10.5 3.5 12 5; b 12 5 13.5 3.5 14.74 3 16.5 3; a 16.5 8.5 5.5 270 90; b 22 8.5 22 10.79 20.49 12.54 19 14; l 19 14 12 21; p 3.5 12 8.5 12 10 9.5 13 15 14.5 12 20.5 12"},
    {"zap", "P 13 2 3 14 12 14 11 22 21 10 12 10"},
    {"trash", "l 3 6 21 6; p 19 6 19 20 17 22 7 22 5 20 5 6; p 8 6 8 4 10 2 14 2 16 4 16 6; l 10 11 10 17; l 14 11 14 17"},
    {"sparkles", "P 10 3 11.8 8.2 17 10 11.8 11.8 10 17 8.2 11.8 3 10 8.2 8.2; l 19 3 19 7; l 17 5 21 5; l 18 16 18 20; l 16 18 20 18"},
    {"grid", "r 3 3 7.5 7.5 1.8; r 13.5 3 7.5 7.5 1.8; r 13.5 13.5 7.5 7.5 1.8; r 3 13.5 7.5 7.5 1.8"},
    {"monitor", "r 2 3 20 14 2.2; l 8 21 16 21; l 12 17 12 21"},
    {"cpu", "r 4 4 16 16 2.2; r 9 9 6 6 1; l 9 1.5 9 4; l 15 1.5 15 4; l 9 20 9 22.5; l 15 20 15 22.5; l 20 9 22.5 9; l 20 15 22.5 15; l 1.5 9 4 9; l 1.5 15 4 15"},
    {"undo", "a 12 12 9 180 -315; l 5.64 5.64 3 8; p 3 3 3 8 8 8"},
    {"history", "a 12 12 9 180 -315; l 5.64 5.64 3 8; p 3 3 3 8 8 8; p 12 7 12 12 15.5 14"},
    {"refresh", "a 12 12 9 0 315; l 18.36 5.64 21 8; p 21 3 21 8 16 8"},
    {"power", "l 12 2 12 11; a 12 12.5 9 -55 290"},
    {"globe", "c 12 12 10; l 2 12 22 12; e 12 12 4.2 10"},
    {"play", "c 12 12 10; P 10 8.2 15.8 12 10 15.8"},
    {"download", "l 12 3 12 15; p 7 10 12 15 17 10; p 3 15 3 19 5 21 19 21 21 19 21 15"},
    {"plug", "l 9 2 9 7; l 15 2 15 7; P 6 7 18 7 18 11 14.5 15.5 9.5 15.5 6 11; l 12 15.5 12 22"},
    {"shield", "b 12 22 12 22 20 18 20 12; l 20 12 20 5; l 20 5 12 2; l 12 2 4 5; l 4 5 4 12; b 4 12 4 18 12 22 12 22"},
    {"shield-check", "b 12 22 12 22 20 18 20 12; l 20 12 20 5; l 20 5 12 2; l 12 2 4 5; l 4 5 4 12; b 4 12 4 18 12 22 12 22; p 8.8 12 11 14.2 15.4 9.8"},
    {"lock", "r 4 11 16 10.5 2.2; a 12 7 5 180 180; l 7 7 7 11; l 17 7 17 11"},
    {"gauge", "a 12 14 9 150 240; l 12 14 16 9.5; f 12 14 1.4"},
    {"drive", "r 2 13 20 8 2; p 2 13 5.5 4.5 18.5 4.5 22 13; f 6.5 17 1.1; l 10 17 17 17"},
    {"memory", "r 2 6 20 12 1.8; l 6 10 6 14; l 10 10 10 14; l 14 10 14 14; l 18 10 18 14; l 6 18 6 21; l 12 18 12 21; l 18 18 18 21"},
    {"spinner", "a 12 12 9 -90 270"},
    {"gamepad", "r 2 7 20 11 4; l 6 12.5 10 12.5; l 8 10.5 8 14.5; f 15.5 11.5 1.1; f 18 13.8 1.1"},
    {"file-text", "p 14 2 6 2 4 4 4 20 6 22 18 22 20 20 20 8 14 2; p 14 2 14 8 20 8; l 8 13 16 13; l 8 17 16 17"},
    {"pie", "a 12 12 10 -90 270; p 12 2 12 12 22 12"},
    {"activity", "p 2 12 6 12 9 4 15 20 18 12 22 12"},
    {"thermo", "l 12 4 12 14; a 12 17.5 3.5 -60 300; a 12 4 2 180 180; l 10 4 10 14; l 14 4 14 14"}
  };
  public static bool Has(string n) { return n != null && (n == "theme" || defs.ContainsKey(n)); }
  // Accepte un nom d'icône ou un ancien glyphe Segoe MDL2 (compatibilité)
  public static string Resolve(string t) {
    if (string.IsNullOrEmpty(t)) return null;
    if (t.Length == 1) { switch ((int)t[0]) { case 0xE706: return "theme"; case 0xE713: return "settings"; case 0xEA99: return "trash"; case 0xE7A7: return "undo"; case 0xE777: return "history"; case 0xE772: return "plug"; case 0xE72C: return "power"; case 0xE774: return "globe"; case 0xE768: return "play"; case 0xE895: return "refresh"; case 0xE946: return "info"; case 0xE7BA: return "alert"; case 0xE73E: return "check-circle"; case 0xE783: return "x-circle"; case 0xE95E: return "heart"; case 0xE930: return "check-circle"; case 0xE945: return "zap"; case 0xE74D: return "sparkles"; case 0xE71D: return "grid"; case 0xE770: return "monitor"; case 0xE950: return "cpu"; case 0xE76C: return "chevron"; case 0xE721: return "search"; case 0xE896: return "download"; case 0x2715: return "x"; case 0x2013: return "minus"; case 0x21B6: return "undo"; } return (int)t[0] < 0x2000 ? t : null; }   // nom d'1 lettre (ex. « x » = fermer) : c'est un nom, pas un glyphe
    return t;
  }
  static PointF[] Gear(float cx, float cy, float ro, float ri, int n, float k, float ox, float oy) {
    List<PointF> l = new List<PointF>(); float st = 360f / n;
    for (int i = 0; i < n; i++) {
      float a = i * st;
      float[,] q = { { a - st * 0.30f, ri }, { a - st * 0.17f, ro }, { a + st * 0.17f, ro }, { a + st * 0.30f, ri } };
      for (int j = 0; j < 4; j++) { double t = (q[j, 0] - 90) * Math.PI / 180; l.Add(new PointF(ox + (float)(cx + q[j, 1] * Math.Cos(t)) * k, oy + (float)(cy + q[j, 1] * Math.Sin(t)) * k)); }
    }
    return l.ToArray();
  }
  // v5.7 : chaque icône est analysée une seule fois puis gardée en mémoire
  static readonly Dictionary<string, List<KeyValuePair<string, float[]>>> cache = new Dictionary<string, List<KeyValuePair<string, float[]>>>();
  static List<KeyValuePair<string, float[]>> Parts(string name, string d) {
    List<KeyValuePair<string, float[]>> l;
    if (cache.TryGetValue(name, out l)) return l;
    l = new List<KeyValuePair<string, float[]>>();
    foreach (string part in d.Split(';')) {
      string[] a = part.Trim().Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
      if (a.Length == 0) continue;
      float[] v = new float[a.Length - 1];
      for (int i = 1; i < a.Length; i++) v[i - 1] = float.Parse(a[i], System.Globalization.CultureInfo.InvariantCulture);
      l.Add(new KeyValuePair<string, float[]>(a[0], v));
    }
    cache[name] = l; return l;
  }
  public static void Draw(Graphics g, string name, RectangleF box, Color col, float stroke) {
    if (name == "theme") name = LkBadge.Light ? "moon" : "sun";
    string d; if (name == null || !defs.TryGetValue(name, out d) || box.Width < 2) return;
    float k = Math.Min(box.Width, box.Height) / 24f;
    float ox = box.X + (box.Width - 24 * k) / 2f, oy = box.Y + (box.Height - 24 * k) / 2f;
    GraphicsState gs = g.Save();
    g.SmoothingMode = SmoothingMode.AntiAlias; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
    try {
      using (Pen pen = new Pen(col, Math.Max(1.25f, stroke * k))) using (SolidBrush br = new SolidBrush(col)) {
        pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; pen.LineJoin = LineJoin.Round;
        foreach (KeyValuePair<string, float[]> kv in Parts(name, d)) {
          float[] v = kv.Value; string op = kv.Key;
          switch (op) {
            case "l": g.DrawLine(pen, ox + v[0] * k, oy + v[1] * k, ox + v[2] * k, oy + v[3] * k); break;
            case "p": case "P": {
              PointF[] pts = new PointF[v.Length / 2];
              for (int i = 0; i < pts.Length; i++) pts[i] = new PointF(ox + v[2 * i] * k, oy + v[2 * i + 1] * k);
              if (op == "P") g.DrawPolygon(pen, pts); else g.DrawLines(pen, pts); break; }
            case "c": g.DrawEllipse(pen, ox + (v[0] - v[2]) * k, oy + (v[1] - v[2]) * k, 2 * v[2] * k, 2 * v[2] * k); break;
            case "e": g.DrawEllipse(pen, ox + (v[0] - v[2]) * k, oy + (v[1] - v[3]) * k, 2 * v[2] * k, 2 * v[3] * k); break;
            case "f": g.FillEllipse(br, ox + (v[0] - v[2]) * k, oy + (v[1] - v[2]) * k, 2 * v[2] * k, 2 * v[2] * k); break;
            case "a": g.DrawArc(pen, ox + (v[0] - v[2]) * k, oy + (v[1] - v[2]) * k, 2 * v[2] * k, 2 * v[2] * k, v[3], v[4]); break;
            case "b": g.DrawBezier(pen, ox + v[0] * k, oy + v[1] * k, ox + v[2] * k, oy + v[3] * k, ox + v[4] * k, oy + v[5] * k, ox + v[6] * k, oy + v[7] * k); break;
            case "r": using (GraphicsPath p = LkNative.Round(new RectangleF(ox + v[0] * k, oy + v[1] * k, v[2] * k, v[3] * k), v[4] * k)) g.DrawPath(pen, p); break;
            case "g": g.DrawPolygon(pen, Gear(v[0], v[1], v[2], v[3], (int)v[4], k, ox, oy)); break;
          }
        }
      }
    } catch { } finally { g.Restore(gs); }
  }
}
// Icône (remplace les glyphes Segoe MDL2) : couleur = ForeColor, pastille colorée optionnelle (Chip)
public class LkIcon : Control {
  public static bool Chips = false;   // v5.4 (épuré) : pas de pastille colorée derrière les icônes
  public Color Chip = Color.Empty; public int ChipAlpha = 34; public float Radius = 9; public float IconSize = 0; public float Stroke = 1.6f;
  public LkIcon() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true); }
  protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { PeindreFondLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreFondLk(PaintEventArgs e) {
    LkCard k = Parent as LkCard;
    if (k != null) e.Graphics.Clear(k.CurrentFill); else if (BackColor.A == 255) e.Graphics.Clear(BackColor); else base.OnPaintBackground(e);
  }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    if (!Chip.IsEmpty && Chips) {
      float cs = Math.Min(Width, Height) - 1;
      using (GraphicsPath p = LkNative.Round(new RectangleF((Width - 1 - cs) / 2f, (Height - 1 - cs) / 2f, cs, cs), Radius))
      using (SolidBrush b = new SolidBrush(Color.FromArgb(Math.Min(255, LkBadge.Light ? ChipAlpha + 8 : ChipAlpha), Chip))) g.FillPath(b, p);
    }
    float sz = IconSize > 0 ? IconSize : Math.Min(Width, Height) * 0.6f;
    LkIcons.Draw(g, LkIcons.Resolve(Text), new RectangleF((Width - sz) / 2f, (Height - sz) / 2f, sz, sz), Enabled ? ForeColor : Color.Gray, Stroke);
  }
}


// Bandeau d'alerte : conteneur arrondi teinté + bordure (enfants : labels transparents)
public class LkTint : Panel {
  // v5.4 (épuré) : plus d'encadré coloré ; une simple ligne icône + texte
  public Color Accent = Color.FromArgb(245, 158, 11); public int Radius = 12;
  public void Apparaitre() { }
  public LkTint() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
}

// Grand bandeau violet du Tableau de bord (dégradé + halo), identique en thème clair et sombre
public class LkHero : Panel {
  // v5.4 (épuré) : zone à plat, sans dégradé ; seule la fine barre de progression d'OPTIMISER est dessinée
  public int Radius = 18;
  public float Prog = -1f; public Rectangle ProgRect = Rectangle.Empty; float progShown; int ptok;
  public void SetProg(float v) {
    float from = progShown < 0 ? 0 : progShown; Prog = v; int my = ++ptok;
    if (v < 0) { progShown = -1; Invalidate(); return; }
    if (!LkAnim.On || !IsHandleCreated) { progShown = v; Invalidate(); return; }
    LkAnim.Tween(400, p => { if (my != ptok) return; progShown = from + (v - from) * p; Invalidate(Rectangle.Inflate(ProgRect, 2, 2)); }, null);
  }
  public LkHero() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  // v5.7 : fond de carte + bordure + halo (Fill vide = ancien rendu à plat)
  public Color Fill = Color.Empty, Border = Color.Empty, Glow = Color.FromArgb(140, 82, 255), Glow2 = Color.FromArgb(18, 224, 255); public Rectangle GlowRect = Rectangle.Empty; public int GlowAlpha = 46;
  protected override CreateParams CreateParams { get { CreateParams cp = base.CreateParams; if (LkCard.Compose) cp.ExStyle |= 0x02000000; return cp; } }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    if (!Fill.IsEmpty) {
      using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, Width - 0.5f, Height - 0.5f), Radius)) {
        using (SolidBrush b = new SolidBrush(Fill)) g.FillPath(b, p);
        if (!GlowRect.IsEmpty) {
          g.SetClip(p);
          using (GraphicsPath el = new GraphicsPath()) {
            el.AddEllipse(GlowRect);
            using (PathGradientBrush pb = new PathGradientBrush(el)) {
              pb.CenterColor = Color.FromArgb(GlowAlpha, Glow); pb.SurroundColors = new Color[] { Color.FromArgb(0, Glow2) };
              g.FillPath(pb, el);
            }
          }
          g.ResetClip();
        }
      }
      if (!Border.IsEmpty) using (GraphicsPath p = LkNative.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Radius - 0.5f)) using (Pen pn = new Pen(Border, 1f)) g.DrawPath(pn, p);
    }
    if (Prog >= 0 && progShown >= 0 && ProgRect.Width > 0) {
      RectangleF pr = ProgRect; float rr = pr.Height / 2f;
      Color tr = LkBadge.Light ? Color.FromArgb(228, 228, 234) : Color.FromArgb(36, 36, 44);
      using (GraphicsPath t = LkNative.Round(pr, rr)) using (SolidBrush b = new SolidBrush(tr)) g.FillPath(b, t);
      float w = pr.Width * Math.Max(0f, Math.Min(100f, progShown)) / 100f;
      if (w >= 1) { if (w < pr.Height) w = pr.Height; using (GraphicsPath t = LkNative.Round(new RectangleF(pr.X, pr.Y, w, pr.Height), rr)) using (LinearGradientBrush b = new LinearGradientBrush(LkNative.R1(new RectangleF(pr.X - 1, pr.Y, pr.Width + 2, pr.Height)), Color.FromArgb(18, 224, 255), Color.FromArgb(140, 82, 255), 0f)) g.FillPath(b, t); }
    }
  }
}

// Pastille de profil dans le bandeau (titre + sous-titre), sélection en blanc plein
// v5.8 : élément de navigation de la barre latérale (icône + texte, survol en fondu, actif = fond teinté + barre cyan -> violet)
public class LkNav : Control {
  public Color HoverFill = Color.FromArgb(23, 23, 28), ActiveFill = Color.FromArgb(28, 23, 48), ActiveFore = Color.White;
  public Color Accent = Color.FromArgb(18, 224, 255), Accent2 = Color.FromArgb(140, 82, 255);
  public string Icon = null; public int Radius = 10; public float IconSize = 18f; public Font ActiveFont;
  bool active; float h; int tok;
  public LkNav() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); Cursor = Cursors.Hand; }
  public bool Active { get { return active; } set { if (active == value) return; active = value; Invalidate(); } }
  void Survol(float to) { float from = h; int my = ++tok; LkAnim.Tween(120, p => { if (my != tok) return; h = from + (to - from) * p; Invalidate(); }, null); }
  protected override void OnMouseEnter(EventArgs e) { Survol(1f); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { Survol(0f); base.OnMouseLeave(e); }
  protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    Color fond = LkCard.BackOf(this);
    RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
    if (active) {
      using (GraphicsPath p = LkNative.Round(r, Radius))
      using (LinearGradientBrush b = new LinearGradientBrush(LkNative.R1(new RectangleF(0, 0, Width + 1, Height)), ActiveFill, LkAnim.Mix(ActiveFill, fond, 0.55f), 0f)) g.FillPath(b, p);
      float bw = Math.Max(3f, Height * 0.08f), bh = Height * 0.5f, by = (Height - bh) / 2f;
      using (GraphicsPath p = LkNative.Round(new RectangleF(0, by, bw, bh), bw / 2f))
      using (LinearGradientBrush b = new LinearGradientBrush(LkNative.R1(new RectangleF(0, by - 1, bw, bh + 2)), Accent, Accent2, 90f)) g.FillPath(b, p);
    } else if (h > 0.01f) using (GraphicsPath p = LkNative.Round(r, Radius)) using (SolidBrush b = new SolidBrush(LkAnim.Mix(fond, HoverFill, h))) g.FillPath(b, p);
    Color fc = active ? ActiveFore : LkAnim.Mix(ForeColor, ActiveFore, h * 0.75f);
    float x0 = Height * 0.36f;
    if (!string.IsNullOrEmpty(Icon)) { LkIcons.Draw(g, Icon, new RectangleF(x0, (Height - IconSize) / 2f, IconSize, IconSize), active ? LkAnim.Mix(Accent, Accent2, 0.35f) : fc, 2f); x0 += IconSize + Height * 0.32f; }
    Font f = active && ActiveFont != null ? ActiveFont : Font;
    TextRenderer.DrawText(g, Text, f, new Rectangle((int)x0, 0, Math.Max(10, Width - (int)x0 - 6), Height), fc, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
  }
}

public class LkPill : Control {
  // v5.4 (épuré) : contour fin, rempli d'une teinte légère quand il est choisi
  public string Sub = ""; public bool Selected; public int Radius = 12; public Font SubFont; float h; int tok;
  public string Icon = null; public bool SubRight = false;   // v5.8 : ligne large (icône, nom à gauche, nombre de réglages à droite)
  public LkPill() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true); BackColor = Color.Transparent; Cursor = Cursors.Hand; }
  void Survol(float to) { float from = h; int my = ++tok; LkAnim.Tween(130, p => { if (my != tok) return; h = from + (to - from) * p; Invalidate(); }, null); }
  protected override void OnMouseEnter(EventArgs e) { Survol(1f); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { Survol(0f); base.OnMouseLeave(e); }
  protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    bool L = LkBadge.Light;
    Color acc = L ? Color.FromArgb(124, 77, 255) : Color.FromArgb(167, 139, 250);
    Color ligne = L ? Color.FromArgb(220, 220, 228) : Color.FromArgb(44, 44, 54);
    Color ligneH = L ? Color.FromArgb(190, 190, 202) : Color.FromArgb(70, 70, 84);
    RectangleF r = new RectangleF(0.75f, 0.75f, Width - 2f, Height - 2f);
    using (GraphicsPath p = LkNative.Round(r, Radius)) {
      if (Selected) {
        using (SolidBrush b = new SolidBrush(Color.FromArgb(L ? 20 : 26, acc))) g.FillPath(b, p);
        using (Pen pn = new Pen(acc, 1.5f)) g.DrawPath(pn, p);
      } else using (Pen pn = new Pen(LkAnim.Mix(ligne, ligneH, h), 1f)) g.DrawPath(pn, p);
    }
    int pad = (int)(Height * 0.28f);
    Color c1 = Selected ? acc : (L ? Color.FromArgb(24, 24, 31) : Color.FromArgb(237, 237, 242));
    Color c2 = L ? Color.FromArgb(95, 95, 110) : Color.FromArgb(139, 139, 154);
    if (SubRight) {
      float isz = Height * 0.40f, x0 = Height * 0.30f;
      if (!string.IsNullOrEmpty(Icon)) { LkIcons.Draw(g, Icon, new RectangleF(x0, (Height - isz) / 2f, isz, isz), acc, 2.2f); x0 += isz + Height * 0.26f; }
      TextFormatFlags tl = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis;
      TextFormatFlags tr = TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix;
      int ws = SubFont != null ? TextRenderer.MeasureText(g, Sub, SubFont, Size.Empty, tr).Width : 0;
      TextRenderer.DrawText(g, Text, Font, new Rectangle((int)x0, 0, Math.Max(10, Width - (int)x0 - ws - pad * 2), Height), c1, tl);
      if (SubFont != null) TextRenderer.DrawText(g, Sub, SubFont, new Rectangle(0, 0, Width - pad, Height), c2, tr);
      return;
    }
    using (SolidBrush b1 = new SolidBrush(c1)) g.DrawString(Text, Font, b1, pad, Height * 0.14f);
    if (SubFont != null) using (SolidBrush b2 = new SolidBrush(c2)) g.DrawString(Sub, SubFont, b2, pad, Height * 0.54f);
  }
}

// Gros bouton rond « OPTIMISER » : halo qui respire en continu, pulsation plus forte pendant l'exécution
public class LkOrb : Control {
  public string Sub = ""; public Font SubFont; bool busy; float phase; float h; int tok; bool loop; Stopwatch sw = Stopwatch.StartNew(); int dots;
  float ripple; float prog = -1f, progShown = -1f; int ptok;
  // v5.8 : mode anneau de score (Score >= 0) : piste + arc dégradé cyan -> violet, grand nombre au centre.
  // Pendant OPTIMISER, l'arc montre la progression à la place du score.
  public float Score = -1f; float scoreShown = 0f; int stok; public Font SmallFont;
  public void SetScore(float v) {
    v = Math.Max(0f, Math.Min(1f, v)); float from = Score < 0f ? 0f : scoreShown; Score = v; int my = ++stok;
    LkAnim.Tween(700, p => { if (my != stok) return; scoreShown = from + (v - from) * (1f - (1f - p) * (1f - p)); Invalidate(); }, () => { if (my == stok) { scoreShown = v; Invalidate(); } });
  }
  void PaintScore(Graphics g, bool L) {
    float cx = Width / 2f, cy = Height / 2f, R = Math.Min(Width, Height) / 2f - 2f, w = Math.Max(4f, R * 0.15f), rr = R - w / 2f;
    if (R < 8f || rr - w < 2f) return;   // v5.10 : trop petit pour l'anneau (rectangles négatifs -> exception GDI+)
    float ph = LkAnim.On && busy ? phase : 0f;
    Color piste = L ? Color.FromArgb(228, 228, 236) : Color.FromArgb(40, 40, 50);
    piste = LkAnim.Mix(piste, L ? Color.FromArgb(210, 200, 250) : Color.FromArgb(62, 50, 110), ph * 0.6f);
    RectangleF rc = new RectangleF(cx - rr, cy - rr, rr * 2, rr * 2);
    using (Pen tr = new Pen(piste, w)) g.DrawEllipse(tr, rc);
    float frac = progShown >= 0f ? progShown : scoreShown;
    if (frac > 0.003f) using (LinearGradientBrush gb = new LinearGradientBrush(LkNative.R1(new RectangleF(cx - R, cy - R, R * 2, R * 2)), Color.FromArgb(18, 224, 255), Color.FromArgb(140, 82, 255), 135f))
      using (Pen pn = new Pen(gb, w)) { pn.StartCap = LineCap.Round; pn.EndCap = LineCap.Round; g.DrawArc(pn, rc, -90f, 360f * Math.Min(1f, frac)); }
    string t = Text; if (busy && LkAnim.On) t = Text.TrimEnd('.', ' ') + new string('.', dots).PadRight(3);
    StringFormat sf = new StringFormat(); sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
    float ri = rr - w;
    Font ft = (SmallFont != null && Text.TrimEnd('.', ' ').Length > 3) ? SmallFont : Font;
    using (SolidBrush b = new SolidBrush(ForeColor)) g.DrawString(t, ft, b, new RectangleF(cx - ri - 4, cy - ri * 0.62f, ri * 2 + 8, ri * 0.95f), sf);
    if (SubFont != null) using (SolidBrush b = new SolidBrush(L ? Color.FromArgb(95, 95, 110) : Color.FromArgb(139, 139, 154))) g.DrawString(Sub, SubFont, b, new RectangleF(cx - ri, cy + ri * 0.30f, ri * 2, ri * 0.45f), sf);
  }
  // v5.3 : anneau de progression autour du bouton (v < 0 : caché)
  public void SetProgress(float v) {
    if (v < 0f) { ++ptok; prog = progShown = -1f; Invalidate(); return; }
    v = Math.Min(1f, v); float from = progShown < 0f ? 0f : progShown; prog = v; int my = ++ptok;
    LkAnim.Tween(420, p => { if (my != ptok) return; progShown = from + (v - from) * p; Invalidate(); }, null);
  }
  public LkOrb() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true); BackColor = Color.Transparent; Cursor = Cursors.Hand; }
  public bool Busy { get { return busy; } set { busy = value; Invalidate(); Boucle(); } }
  // Une seule boucle d'animation, seulement quand le bouton est visible
  public void Boucle() {
    if (loop || !busy || !LkAnim.Boucles || !Visible || IsDisposed) return; loop = true;   // v5.5 : rien au repos
    LkAnim.AddLoop(() => {
      if (IsDisposed || !Visible || !busy || !LkAnim.Boucles) { loop = false; phase = 0f; Invalidate(); return false; }
      long ms = sw.ElapsedMilliseconds; double per = busy ? 1100.0 : 2400.0;
      phase = (float)(0.5 - 0.5 * Math.Cos(ms * 2 * Math.PI / per)); ripple = (float)((ms % 2800) / 2800.0); dots = (int)(ms / 400 % 4); Invalidate(); return true;
    });
  }
  protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); if (Visible) Boucle(); }
  void Survol(float to) { float from = h; int my = ++tok; LkAnim.Tween(150, p => { if (my != tok) return; h = from + (to - from) * p; Invalidate(); }, null); }
  protected override void OnMouseEnter(EventArgs e) { Survol(1f); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { Survol(0f); base.OnMouseLeave(e); }
  protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
  public void PerformClick() { if (Enabled) OnClick(EventArgs.Empty); }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    // v5.4 (épuré) : disque plein violet, anneau fin qui respire très doucement, anneau de progression
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
    bool L = LkBadge.Light;
    if (Score >= 0f) { PaintScore(g, L); return; }
    Color acc = Color.FromArgb(140, 82, 255);
    float cx = Width / 2f, cy = Height / 2f, R = Math.Min(Width, Height) / 2f - 2;
    if (R < 4f) return;   // v5.10 : trop petit pour être dessiné
    float ph = LkAnim.On ? phase : 0f;
    float rp = R * 0.94f, w = Math.Max(2f, R * 0.035f);
    Color piste = L ? Color.FromArgb(226, 222, 245) : Color.FromArgb(40, 34, 64);
    using (Pen tr = new Pen(LkAnim.Mix(piste, Color.FromArgb(L ? 205 : 62, L ? 196 : 50, L ? 245 : 110), busy ? ph : ph * 0.5f), w)) g.DrawEllipse(tr, cx - rp, cy - rp, rp * 2, rp * 2);
    if (progShown >= 0f && progShown > 0.002f) using (LinearGradientBrush gb = new LinearGradientBrush(LkNative.R1(new RectangleF(cx - rp - 2, cy - rp - 2, rp * 2 + 4, rp * 2 + 4)), Color.FromArgb(18, 224, 255), Color.FromArgb(167, 139, 250), 45f)) using (Pen pn = new Pen(gb, w * 1.6f)) { pn.StartCap = LineCap.Round; pn.EndCap = LineCap.Round; g.DrawArc(pn, cx - rp, cy - rp, rp * 2, rp * 2, -90f, 360f * progShown); }
    float ri = R * (0.78f + 0.015f * h);
    Color fill = busy ? LkAnim.Mix(acc, Color.FromArgb(160, 112, 255), ph * 0.6f) : LkAnim.Mix(acc, Color.FromArgb(122, 64, 238), h);
    Color fill2 = LkAnim.Mix(Color.FromArgb(76, 110, 255), Color.FromArgb(60, 92, 240), busy ? 0f : h);
    using (LinearGradientBrush b = new LinearGradientBrush(LkNative.R1(new RectangleF(cx - ri - 1, cy - ri - 1, ri * 2 + 2, ri * 2 + 2)), fill2, fill, 45f)) g.FillEllipse(b, cx - ri, cy - ri, ri * 2, ri * 2);
    string t = Text; if (busy && LkAnim.On) t = Text.TrimEnd('.', ' ') + new string('.', dots).PadRight(3);
    StringFormat sf = new StringFormat(); sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
    using (SolidBrush b = new SolidBrush(Color.White)) g.DrawString(t, Font, b, new RectangleF(cx - ri, cy - ri * 0.55f, ri * 2, ri * 0.7f), sf);
    if (SubFont != null) using (SolidBrush b = new SolidBrush(Color.FromArgb(215, 255, 255, 255))) g.DrawString(Sub, SubFont, b, new RectangleF(cx - ri * 0.92f, cy + ri * 0.12f, ri * 1.84f, ri * 0.5f), sf);
  }
}

// v5.7 : titre de section : petite barre cyan -> violet, texte, filet fin jusqu'au bord (un seul contrôle)
public class LkSection : Control {
  public Color Line = Color.FromArgb(37, 37, 45); public Color A1 = Color.FromArgb(18, 224, 255), A2 = Color.FromArgb(140, 82, 255);
  public LkSection() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    float bh = Height * 0.62f, bw = Math.Max(3f, Height * 0.16f), by = (Height - bh) / 2f;
    using (GraphicsPath p = LkNative.Round(new RectangleF(0, by, bw, bh), bw / 2f))
    using (LinearGradientBrush b = new LinearGradientBrush(LkNative.R1(new RectangleF(0, by - 1, bw, bh + 2)), A1, A2, 90f)) g.FillPath(b, p);
    int x = (int)(bw + Height * 0.45f);
    TextFormatFlags tf = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding;
    int tw = TextRenderer.MeasureText(g, Text, Font, Size.Empty, tf).Width;
    TextRenderer.DrawText(g, Text, Font, new Rectangle(x, 0, Width - x, Height), ForeColor, LkCard.BackOf(this), tf);
    int lx = x + tw + (int)(Height * 0.6f);
    if (lx < Width - 4) using (Pen pn = new Pen(Line, 1f)) { g.SmoothingMode = SmoothingMode.None; g.DrawLine(pn, lx, Height / 2, Width - 2, Height / 2); }
  }
}

// v5.7 : mini-courbe d'historique (moniteur en direct) : 40 dernières valeurs, trait en dégradé + remplissage léger
public class LkSpark : Control {
  int[] v = new int[40]; int n = 0; public Color A1 = Color.FromArgb(18, 224, 255), A2 = Color.FromArgb(140, 82, 255);
  public LkSpark() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  public void Push(int x) { if (x < 0) return; x = Math.Max(0, Math.Min(100, x)); if (n < v.Length) v[n++] = x; else { Array.Copy(v, 1, v, 0, v.Length - 1); v[v.Length - 1] = x; } Invalidate(); }
  public void Clear() { n = 0; Invalidate(); }
  protected override void OnPaintBackground(PaintEventArgs e) { try { e.Graphics.Clear(LkCard.BackOf(this)); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    if (n < 2 || Width < 4 || Height < 4) return;
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    float dx = (Width - 2f) / (v.Length - 1), h = Height - 3f; PointF[] pts = new PointF[n];
    for (int i = 0; i < n; i++) pts[i] = new PointF(1 + (v.Length - n + i) * dx, 1.5f + h * (1f - v[i] / 100f));
    using (GraphicsPath f = new GraphicsPath()) {
      f.AddLines(pts); f.AddLine(pts[n - 1].X, pts[n - 1].Y, pts[n - 1].X, Height); f.AddLine(pts[n - 1].X, Height, pts[0].X, Height); f.CloseFigure();
      using (LinearGradientBrush b = new LinearGradientBrush(LkNative.R1(new RectangleF(0, 0, Width, Height + 1)), Color.FromArgb(46, A2), Color.FromArgb(0, A2), 90f)) g.FillPath(b, f);
    }
    using (LinearGradientBrush lb = new LinearGradientBrush(LkNative.R1(new RectangleF(-1, 0, Width + 2, Height)), A1, A2, 0f)) using (Pen p = new Pen(lb, Math.Max(1.5f, Height / 22f))) { p.LineJoin = LineJoin.Round; g.DrawLines(p, pts); }
  }
}

// v5.7 : transition de page « instantané » : au lieu de déplacer des dizaines de fenêtres (cartes, textes,
// interrupteurs) à chaque image, la page est photographiée UNE fois (une image par bloc) et un seul contrôle
// anime les images ; la vraie page est dessous, déjà prête. Un clic passe au travers (HTTRANSPARENT).
public class LkFade : Control {
  class It { public Bitmap B; public Rectangle R; public int K; }
  List<It> items = new List<It>(); Color bg; int dy, dur, pas, kmax; Stopwatch sw; int tok;
  static Dictionary<Control, LkFade> parents = new Dictionary<Control, LkFade>();
  public static int Erreurs = 0;
  public LkFade() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.Opaque, true); Visible = false; TabStop = false; }
  public static LkFade Get(Control parent) {
    LkFade f; if (parents.TryGetValue(parent, out f) && !f.IsDisposed) return f;
    f = new LkFade(); parent.Controls.Add(f); parents[parent] = f; return f;
  }
  public static void StopAll() { foreach (LkFade f in parents.Values) if (!f.IsDisposed) f.Stop(); }
  protected override void WndProc(ref Message m) { if (m.Msg == 0x84) { m.Result = (IntPtr)(-1); return; } base.WndProc(ref m); }
  static bool Natif(Control c) { foreach (Control x in c.Controls) { if (x is TextBoxBase || x is WebBrowserBase || x is ListControl || Natif(x)) return true; } return false; }
  public void Stop() {
    ++tok; if (Visible) Visible = false;
    foreach (It i in items) { try { i.B.Dispose(); } catch { } }
    items.Clear(); sw = null;
  }
  public bool Prepare(Control page, Color fond, int decalage) {
    Stop();
    if (!LkAnim.On || LkAnim.Reduit || page == null || page.Parent != Parent || page.Width < 8 || page.Height < 8) return false;
    try {
      Control content = page; int oy = 0;
      LkScroll sc = page as LkScroll; if (sc != null) { content = sc.Content; oy = sc.Content.Top; }
      if (Natif(content)) return false;
      List<Control> l = new List<Control>();
      foreach (Control c in content.Controls) {
        if (!c.Visible || c.Width <= 0 || c.Height <= 0 || c is LkFade) continue;
        int y = c.Top + oy; if (y >= page.Height || y + c.Height <= 0) continue; l.Add(c);
      }
      if (l.Count == 0 || l.Count > 90) return false;
      List<Control> ordre = new List<Control>(l);
      ordre.Sort((a, b) => a.Top != b.Top ? a.Top.CompareTo(b.Top) : a.Left.CompareTo(b.Left));
      // dessin du bas vers le haut de la pile (index élevé = dessous)
      l.Sort((a, b) => content.Controls.GetChildIndex(b).CompareTo(content.Controls.GetChildIndex(a)));
      kmax = 0;
      foreach (Control c in l) {
        Bitmap bm = new Bitmap(c.Width, c.Height, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
        c.DrawToBitmap(bm, new Rectangle(0, 0, c.Width, c.Height));
        int k = Math.Min(ordre.IndexOf(c), 11); if (k > kmax) kmax = k;
        items.Add(new It { B = bm, R = new Rectangle(c.Left, c.Top + oy, c.Width, c.Height), K = k });
      }
    } catch (Exception) { Erreurs++; Stop(); return false; }
    // v5.10 : durée par défaut AVANT d'être visible. Redraw(main, true) -> Refresh() peint le fondu tout de suite,
    // avant Play() : avec dur = 0, (0 - 0) / 0 = NaN -> y = int.MinValue -> OverflowException dans DrawImage (plantage 5.8/5.9).
    dur = 230; pas = 26; sw = null;
    bg = fond; dy = decalage; Bounds = page.Bounds; BringToFront(); Visible = true; return true;
  }
  public void Play(int ms, int pasMs) {
    if (items.Count == 0) { Stop(); return; }
    dur = Math.Max(1, (int)(ms * LkAnim.Lent)); pas = Math.Max(0, (int)(pasMs * LkAnim.Lent)); sw = Stopwatch.StartNew(); int my = ++tok;
    LkAnim.Add(() => {
      if (my != tok || IsDisposed) return false;
      if (sw.ElapsedMilliseconds >= dur + kmax * pas + 16) { Stop(); return false; }
      Invalidate(); return true;
    });
  }
  protected override void OnPaint(PaintEventArgs e) { try { PeindreLk(e); } catch (Exception ex) { LkSafe.Paint(this, ex, e); } }   // v5.10
  void PeindreLk(PaintEventArgs e) {
    Graphics g = e.Graphics; g.Clear(bg);
    g.InterpolationMode = InterpolationMode.NearestNeighbor; g.PixelOffsetMode = PixelOffsetMode.Half; g.CompositingQuality = CompositingQuality.HighSpeed;
    long el = sw == null ? 0 : sw.ElapsedMilliseconds;
    int d = Math.Max(1, dur), lim = Math.Max(Width, Height) + 4096;
    foreach (It i in items.ToArray()) {
      // v5.10 : image absente / libérée / vide : ignorée ; toutes les valeurs bornées (jamais NaN ni hors limites)
      if (i == null || i.B == null || i.R.Width <= 0 || i.R.Height <= 0) continue;
      int bw, bh; try { bw = i.B.Width; bh = i.B.Height; } catch { continue; }   // Bitmap libéré -> ArgumentException
      if (bw <= 0 || bh <= 0) continue;
      float p = (float)(el - (long)i.K * pas) / d; if (float.IsNaN(p)) p = 1f; p = Math.Max(0f, Math.Min(1f, p));
      float q = LkAnim.Ease(p); if (float.IsNaN(q)) q = 1f; q = Math.Max(0f, Math.Min(1f, q));
      int y = i.R.Y + (int)Math.Round(Math.Max(-1000f, Math.Min(1000f, dy * (1f - q))));
      if (i.R.X > lim || i.R.X < -lim || y > lim || y < -lim) continue;
      int w = Math.Min(i.R.Width, bw), h = Math.Min(i.R.Height, bh);
      g.DrawImage(i.B, new Rectangle(i.R.X, y, w, h), 0, 0, w, h, GraphicsUnit.Pixel);
      if (q < 0.999f) using (SolidBrush b = new SolidBrush(Color.FromArgb(LkAnim.C255(255f * (1f - q)), bg))) g.FillRectangle(b, i.R.X, y, w, h);
    }
  }
}

// v5.7 : moniteur en direct, lu sur un fil d'arrière-plan (jamais sur celui de l'interface) et seulement
// quand le Tableau de bord est affiché : charge 3D du GPU et mémoire vidéo (compteurs Windows « GPU Engine »
// et « GPU Adapter Memory », Windows 10 1709+), température des zones thermiques si Windows la donne.
public static class LkMonitor {
  public static volatile bool Wanted = false;
  static volatile int gpu = -1, temp = -1; static long vram = -1; static System.Threading.Thread th;
  public static int Gpu { get { return gpu; } }
  public static int Temp { get { return temp; } }
  public static long Vram { get { return System.Threading.Interlocked.Read(ref vram); } }
  public static string Erreur = "";
  static Dictionary<string, CounterSample> prev = new Dictionary<string, CounterSample>();
  public static void Start() {
    if (th != null) return;
    th = new System.Threading.Thread(Boucle); th.IsBackground = true; th.Priority = System.Threading.ThreadPriority.BelowNormal; th.Name = "LkMonitor"; th.Start();
  }
  static void Boucle() {
    bool gOk = true, vOk = true, tOk = true; int n = 0;
    while (true) {
      try {
        if (Wanted) {
          if (gOk) gOk = LireGpu();
          if (vOk) vOk = LireVram();
          if (tOk && n % 3 == 0) tOk = LireTemp();
          n++;
        } else prev.Clear();
      } catch (Exception ex) { Erreur = ex.Message; }
      System.Threading.Thread.Sleep(Wanted ? 2000 : 700);
    }
  }
  static string Luid(string n) { int i = n.IndexOf("luid_", StringComparison.OrdinalIgnoreCase); if (i < 0) return ""; int j = n.IndexOf("_phys", i, StringComparison.OrdinalIgnoreCase); return j > i ? n.Substring(i, j - i) : n.Substring(i); }
  static bool LireGpu() {
    try {
      if (!PerformanceCounterCategory.Exists("GPU Engine")) return false;
      InstanceDataCollectionCollection all = new PerformanceCounterCategory("GPU Engine").ReadCategory();
      InstanceDataCollection col = all["Utilization Percentage"]; if (col == null) return false;
      Dictionary<string, CounterSample> cur = new Dictionary<string, CounterSample>(); Dictionary<string, float> parLuid = new Dictionary<string, float>();
      foreach (InstanceData d in col.Values) {
        string nm = d.InstanceName; if (nm.IndexOf("engtype_3D", StringComparison.OrdinalIgnoreCase) < 0) continue;
        CounterSample s = d.Sample; cur[nm] = s; string l = Luid(nm); if (!parLuid.ContainsKey(l)) parLuid[l] = 0f;
        CounterSample p; if (prev.TryGetValue(nm, out p)) { try { parLuid[l] += CounterSample.Calculate(p, s); } catch { } }
      }
      bool premier = prev.Count == 0; prev = cur;
      if (premier) return true;
      float mx = 0f; foreach (float x in parLuid.Values) if (x > mx) mx = x;
      gpu = (int)Math.Round(Math.Max(0f, Math.Min(100f, mx)));
      return true;
    } catch (Exception ex) { Erreur = "GPU : " + ex.Message; gpu = -1; return false; }
  }
  static bool LireVram() {
    try {
      if (!PerformanceCounterCategory.Exists("GPU Adapter Memory")) return false;
      InstanceDataCollection col = new PerformanceCounterCategory("GPU Adapter Memory").ReadCategory()["Dedicated Usage"]; if (col == null) return false;
      long mx = 0; foreach (InstanceData d in col.Values) if (d.RawValue > mx) mx = d.RawValue;
      System.Threading.Interlocked.Exchange(ref vram, mx); return true;
    } catch (Exception ex) { Erreur = "VRAM : " + ex.Message; return false; }
  }
  static bool LireTemp() {
    try {
      if (!PerformanceCounterCategory.Exists("Thermal Zone Information")) return false;
      InstanceDataCollectionCollection all = new PerformanceCounterCategory("Thermal Zone Information").ReadCategory();
      InstanceDataCollection hp = all["High Precision Temperature"], tp = all["Temperature"];
      double mx = -1;
      if (hp != null) foreach (InstanceData d in hp.Values) { double c = d.RawValue / 10.0 - 273.15; if (Plausible(c) && c > mx) mx = c; }
      if (mx < 0 && tp != null) foreach (InstanceData d in tp.Values) { double c = d.RawValue - 273.15; if (Plausible(c) && c > mx) mx = c; }
      temp = mx < 0 ? -1 : (int)Math.Round(mx); return mx >= 0;
    } catch { return false; }
  }
  static bool Plausible(double c) { return c >= 15 && c <= 115 && Math.Abs(c - 27.8) > 0.15; }
}

// v5.7 : taille d'un dossier (lecture seule), rapide, sans suivre les jonctions, avec un temps maximum
public static class LkDisk {
  public static long Size(string path, int maxMs, out bool complet) {
    complet = true; long total = 0; Stopwatch sw = Stopwatch.StartNew();
    Stack<string> pile = new Stack<string>(); pile.Push(path);
    while (pile.Count > 0) {
      if (sw.ElapsedMilliseconds > maxMs) { complet = false; break; }
      string d = pile.Pop();
      try {
        System.IO.DirectoryInfo di = new System.IO.DirectoryInfo(d);
        foreach (System.IO.FileSystemInfo fi in di.EnumerateFileSystemInfos()) {
          try {
            if ((fi.Attributes & System.IO.FileAttributes.ReparsePoint) != 0) continue;
            if ((fi.Attributes & System.IO.FileAttributes.Directory) != 0) pile.Push(fi.FullName);
            else total += ((System.IO.FileInfo)fi).Length;
          } catch { }
        }
      } catch { }
    }
    return total;
  }
  // sous-dossiers directs les plus gros : "chemin|octets|complet" (triés)
  public static string[] Top(string path, int n, int maxMs) {
    List<KeyValuePair<string, long>> l = new List<KeyValuePair<string, long>>(); Stopwatch sw = Stopwatch.StartNew(); bool tout = true;
    try {
      foreach (string d in System.IO.Directory.GetDirectories(path)) {
        try { if ((new System.IO.DirectoryInfo(d).Attributes & System.IO.FileAttributes.ReparsePoint) != 0) continue; } catch { continue; }
        int reste = maxMs - (int)sw.ElapsedMilliseconds; if (reste < 50) { tout = false; break; }
        bool c; long s = Size(d, Math.Min(reste, maxMs / 3), out c); if (!c) tout = false;
        l.Add(new KeyValuePair<string, long>(d, s));
      }
    } catch { }
    l.Sort((a, b) => b.Value.CompareTo(a.Value));
    List<string> r = new List<string>();
    for (int i = 0; i < l.Count && i < n; i++) r.Add(l[i].Key + "|" + l[i].Value + "|" + (tout ? "1" : "0"));
    return r.ToArray();
  }
}

// Lance un processus caché et récupère sa sortie ligne par ligne (sans bloquer l'interface)
public class LkProc {
  public ConcurrentQueue<string> Lines = new ConcurrentQueue<string>(); Process p; public DateTime ExitSeen = DateTime.MinValue;
  public void Start(string file, string args) {
    ProcessStartInfo si = new ProcessStartInfo(file, args);
    si.UseShellExecute = false; si.CreateNoWindow = true; si.RedirectStandardOutput = true; si.RedirectStandardError = true; si.RedirectStandardInput = true;
    si.StandardOutputEncoding = Encoding.UTF8; si.StandardErrorEncoding = Encoding.UTF8;
    p = new Process(); p.StartInfo = si;
    p.OutputDataReceived += (s, e) => { if (e.Data != null) Add(e.Data, ""); };
    p.ErrorDataReceived += (s, e) => { if (e.Data != null) Add(e.Data, "[erreur] "); };
    p.Start(); try { p.StandardInput.Close(); } catch { }
    p.BeginOutputReadLine(); p.BeginErrorReadLine();
  }
  void Add(string s, string pre) {
    foreach (string part in s.Replace("\0", "").Split('\r')) {
      string t = part.TrimEnd(); if (t.Trim().Length == 0) continue;
      if (System.Text.RegularExpressions.Regex.IsMatch(t, @"^[\s\-\\|/]+$")) continue;
      if (t.IndexOf('\u2588') >= 0 || t.IndexOf('\u2592') >= 0) continue;
      Lines.Enqueue(pre + t);
    }
  }
  // Terminé = processus sorti depuis plus d'1,5 s (laisse le temps de vider la sortie, sans jamais bloquer)
  public bool Done { get { if (p == null) return true; if (!p.HasExited) return false; if (ExitSeen == DateTime.MinValue) ExitSeen = DateTime.Now; return (DateTime.Now - ExitSeen).TotalSeconds > 1.5; } }
  public int ExitCode { get { try { return p.ExitCode; } catch { return -1; } } }
  // v5.6 : arrête le script ET tout ce qu'il a lancé (winget, DISM, installeurs...) quand on ferme l'appli
  public void KillTree() {
    try {
      if (p == null || p.HasExited) return;
      ProcessStartInfo k = new ProcessStartInfo(System.IO.Path.Combine(Environment.SystemDirectory, "taskkill.exe"), "/PID " + p.Id + " /T /F");
      k.UseShellExecute = false; k.CreateNoWindow = true;
      using (Process t = Process.Start(k)) { if (t != null) t.WaitForExit(8000); }
      if (!p.HasExited) p.Kill();
    } catch { }
  }
}
"@ } catch { $exceptionCompil = $_ }
if (-not ("LkProc" -as [type]) -or -not ("LkAnim" -as [type])) {
  $lignes = New-Object System.Collections.Generic.List[string]
  foreach ($e in @($erreursCompil) + @($exceptionCompil)) {
    if ($null -eq $e) { continue }
    $m = if ($e -is [System.Management.Automation.ErrorRecord]) { $e.Exception.Message } elseif ($e -is [Exception]) { $e.Message } else { [string]$e }
    if ($m -and -not $lignes.Contains($m.Trim())) { $lignes.Add($m.Trim()) }
  }
  if ($lignes.Count -eq 0) { $lignes.Add("(aucun message du compilateur : types LkProc / LkAnim introuvables après Add-Type)") }
  Plantage-Demarrage "Les composants de l'interface n'ont pas pu être compilés." ($lignes -join "`r`n")
}
# v5.10 : erreurs de dessin et erreurs non gérées de l'interface -> journal, l'appli continue
try { [LkSafe]::Installer((Join-Path $env:ProgramData "Lukzyr\erreurs-interface.txt")) } catch {}
$dir    = Split-Path -Parent $PSCommandPath
$racine = Split-Path -Parent $dir
$ErrorActionPreference = "SilentlyContinue"

# Animations : réglage enregistré dans HKCU\Software\Lukzyr (Animations = 1/0).
# Par défaut, on suit le réglage Windows « Afficher les animations dans Windows ».
$cleConfig = "HKCU:\Software\Lukzyr"
$prefAnim = (Get-ItemProperty -Path $cleConfig -Name Animations -ErrorAction SilentlyContinue).Animations
# v5.5 : si Windows a désactivé les « effets d'animation », l'appli n'anime rien (quel que soit le réglage de l'appli)
$script:animWindows = [LkNative]::SystemAnimations()
$script:animAppli = if ($null -ne $prefAnim) { [bool][int]$prefAnim } else { $true }
[LkAnim]::On = $script:animAppli -and $script:animWindows
[LkAnim]::Reduit = [bool][int]("0" + (Get-ItemProperty -Path $cleConfig -Name AnimationsReduites -ErrorAction SilentlyContinue).AnimationsReduites)
function Enregistrer-Pref($nom, $valeur) {
  try {
    if (-not (Test-Path $cleConfig)) { [void](New-Item -Path $cleConfig -Force) }
    if ($valeur -is [int] -or $valeur -is [bool]) { Set-ItemProperty -Path $cleConfig -Name $nom -Value ([int]$valeur) -Type DWord -Force }
    else { Set-ItemProperty -Path $cleConfig -Name $nom -Value "$valeur" -Type String -Force }
  } catch {}
}
# Thème (Theme = "clair"/"sombre") et langue (Langue = "fr"/"en", par défaut celle de Windows)
$prefs = Get-ItemProperty -Path $cleConfig -ErrorAction SilentlyContinue
$script:themeClair = ("$($prefs.Theme)" -eq "clair")
$script:langue = if ("$($prefs.Langue)" -in @("fr","en")) { "$($prefs.Langue)" } elseif ((Get-UICulture).TwoLetterISOLanguageName -eq "fr") { "fr" } else { "en" }
. (Join-Path $dir "Traductions.ps1")
$uGo = if ($script:langue -eq "en") { "GB" } else { "Go" }
function T($t) { if ($script:langue -eq "en" -and $null -ne $t) { if ($ENexact -and $ENexact.ContainsKey([string]$t)) { return $ENexact[[string]$t] }; if ($EN.ContainsKey([string]$t)) { return $EN[[string]$t] } }; return $t }
# « v0.1 bêta » / « v0.1 beta »
function Version-Affichee { "v$VersionApp" + $(if ($VersionBeta) { " " + (T "bêta") } else { "" }) }
function Boite($msg, $boutons = "OK", $icone = "Information") { [Windows.Forms.MessageBox]::Show($msg, "LuKZyR Optimisation", $boutons, $icone) }
# Fonctions « Tout annuler » (sauvegarde des réglages d'origine)
. (Join-Path $dir "Sauvegarde-Reglages.ps1")
function Enregistrer-Animations([bool]$on) {
  try {
    if (-not (Test-Path $cleConfig)) { [void](New-Item -Path $cleConfig -Force) }
    Set-ItemProperty -Path $cleConfig -Name Animations -Value ([int]$on) -Type DWord -Force
  } catch {}
}

# DPI : rendu net en 125/150 % ; toutes les dimensions passent par S()
[void][LkNative]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()
$gDpi = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $sc = $gDpi.DpiX / 96.0; $gDpi.Dispose()
if ($sc -lt 1) { $sc = 1.0 }
# v5.1 : à 125/150 % sur un petit écran, la fenêtre (1000 x 660) pourrait dépasser : on réduit l'échelle juste assez
$scDpi = $sc
try {
  $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $scMax = [math]::Min($wa.Width / 1010.0, $wa.Height / 670.0)
  if ($sc -gt $scMax) { $sc = [math]::Max(0.8, [math]::Floor($scMax * 20) / 20) }
} catch {}
function S($v) { [int][math]::Round($v * $sc) }
function Pt($x,$y) { New-Object Drawing.Point((S $x),(S $y)) }
function Sz($w,$h) { New-Object Drawing.Size((S $w),(S $h)) }
# v5.7 : polices gardées en cache (une seule police par taille / style au lieu d'une par contrôle)
$script:polices = @{}
function Police($px, $style = "Regular", $famille = "Segoe UI") {
  $k = "$px|$style|$famille"; $p = $script:polices[$k]
  if (-not $p) { $p = New-Object Drawing.Font($famille, [float]($px * $sc), [Drawing.FontStyle]$style, [Drawing.GraphicsUnit]::Pixel); $script:polices[$k] = $p }
  return $p }
# v5.7 : gel du dessin d'un conteneur pendant qu'on le remplit (une seule image à la fin)
function Geler($c, [bool]$gel) { try { if ($c -and $c.IsHandleCreated) { [LkNative]::Redraw($c, -not $gel) } } catch {} }
# v5.7 : vider une page en libérant vraiment les contrôles (avant : Controls.Clear() seul = handles jamais rendus)
function Vider($pg) { $l = @($pg.Controls); $pg.Controls.Clear(); foreach ($c in $l) { try { $c.Dispose() } catch {} } }

# ===================== DÉTECTION DU MATÉRIEL =====================
# v5.2 : chaque lecture est protégée (si l'une échoue, l'appli s'ouvre quand même) et affichée sur l'écran de chargement
$script:erreursDetection = @()
function Lire-Wmi($quoi, [scriptblock]$code) {
  if ($env:LK_SIMU_RAPIDE) { return $null }   # tests : simule un PC très rapide (détection instantanée)
  try { $ErrorActionPreference = "Stop"; & $code } catch { $script:erreursDetection += "$(T $quoi) : $($_.Exception.Message)"; $null }
}
Etape-Chargement 20 30 "Détection du processeur..."
$cpu   = Lire-Wmi "processeur" { Get-CimInstance Win32_Processor | Select-Object -First 1 }
Etape-Chargement 30 40 "Carte graphique..."
$tousGpu = @(Lire-Wmi "carte graphique" { Get-CimInstance Win32_VideoController } | Where-Object { $_ })
$gpus  = @($tousGpu | Where-Object { $_.Name -notmatch "Microsoft|Basic|Virtual|Remote|Parsec|Meta" })
if (-not $gpus.Count) {
  # Pas de pilote graphique installé : on identifie la marque par l'identifiant matériel
  foreach ($g in $tousGpu) {
    $nomG = if ($g.PNPDeviceID -match "VEN_1002") { "AMD Radeon (pilote non installé)" }
            elseif ($g.PNPDeviceID -match "VEN_10DE") { "NVIDIA GeForce (pilote non installé)" }
            elseif ($g.PNPDeviceID -match "VEN_8086") { "Intel Graphics (pilote non installé)" } else { $null }
    if ($nomG) { $gpus += [pscustomobject]@{ Name = $nomG; AdapterCompatibility = "" } }
  }
}
# v5.3 : mémoire vidéo réelle (Win32_VideoController.AdapterRAM plafonne à 4 Go) : registre du pilote, qwMemorySize
function Vram-Go($g) {
  try {
    foreach ($k in @(Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
      $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
      if ("$($p.DriverDesc)" -ne "$($g.Name)") { continue }
      $o = $p."HardwareInformation.qwMemorySize"
      if (-not $o) { $o = $p."HardwareInformation.MemorySize"; if ($o -is [byte[]]) { $o = [BitConverter]::ToUInt32($o, 0) } }
      if ($o) { return [math]::Round([double]$o / 1GB) }
    }
  } catch {}
  if ($g.AdapterRAM -gt 0) { return [math]::Round([double]$g.AdapterRAM / 1GB) }
  return 0
}
foreach ($g in $gpus) { try { $g | Add-Member -NotePropertyName VramGo -NotePropertyValue (Vram-Go $g) -Force } catch {} }
# carte dédiée (plus de mémoire vidéo) en premier
$gpus = @($gpus | Sort-Object { -[double]$_.VramGo })
Etape-Chargement 40 47 "Carte mère..."
$board = Lire-Wmi "carte mère" { Get-CimInstance Win32_BaseBoard }
$bios  = Lire-Wmi "BIOS" { Get-CimInstance Win32_BIOS }
Etape-Chargement 47 54 "Mémoire..."
$mems  = @(Lire-Wmi "mémoire" { Get-CimInstance Win32_PhysicalMemory } | Where-Object { $_ })
$os    = Lire-Wmi "Windows" { Get-CimInstance Win32_OperatingSystem }
Etape-Chargement 54 62 "Disques..."
$disks = @(Lire-Wmi "disques" { Get-PhysicalDisk } | Where-Object { $_ })
$osVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
# v5.6 : un onduleur (UPS) apparaît aussi comme « batterie » : PC portable = Windows le dit « mobile »,
# ou vraie batterie dans un boîtier qui n'est pas un PC fixe
$portable = [bool](Lire-Wmi "batterie" {
  $type = 0; try { $type = [int](Get-CimInstance Win32_ComputerSystem).PCSystemType } catch {}
  if ($type -eq 2) { return $true }
  $bat = @(Get-CimInstance Win32_Battery | Where-Object { "$($_.Name) $($_.DeviceID)" -notmatch 'UPS|APC|Eaton|CyberPower|Back-?UPS|Onduleur|Smart-UPS' })
  $fixe = [bool]@(@((Get-CimInstance Win32_SystemEnclosure).ChassisTypes) | Where-Object { $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 24, 35 }).Count
  [bool]$bat.Count -and -not $fixe
})

$cpuNom = ("$($cpu.Name)" -replace '\s+',' ').Trim()
$cpuMarque = if ($cpu.Manufacturer -match "AMD") { "AMD" } elseif ($cpu.Manufacturer -match "Intel") { "Intel" } else { "$($cpu.Manufacturer)" }
$ramGo = [math]::Round((($mems | Measure-Object Capacity -Sum).Sum)/1GB)
if (-not $ramGo) { $ramGo = [math]::Round($os.TotalVisibleMemorySize/1MB) }
$ramType = switch (($mems | Select-Object -First 1).SMBIOSMemoryType) { 26 {"DDR4"} 34 {"DDR5"} 24 {"DDR3"} default {""} }
$ramMhz = ($mems | Select-Object -First 1).ConfiguredClockSpeed
if (-not $ramMhz) { $ramMhz = ($mems | Select-Object -First 1).Speed }
$cmMarque = ("$($board.Manufacturer)" -replace 'Micro-Star International Co\., Ltd\.?','MSI' -replace 'ASUSTeK COMPUTER INC\.?','ASUS' -replace 'Gigabyte Technology Co\., Ltd\.?','Gigabyte').Trim()
$cmModele = "$($board.Product)".Trim()

function Gpu-Marque($g) {
  if ($g.Name -match "NVIDIA|GeForce|RTX|GTX|Quadro") { "NVIDIA" }
  elseif ($g.Name -match "AMD|Radeon") { "AMD" }
  elseif ($g.Name -match "Intel|Arc|UHD|Iris") { "Intel" }
  else { "$($g.AdapterCompatibility)" }
}
function Disque-Marque($d) {
  $n = "$($d.FriendlyName)"
  if ($n -match "Samsung") {"Samsung"} elseif ($n -match "CT\d|Crucial|Micron") {"Crucial"} elseif ($n -match "WD|Western|SanDisk") {"WD"}
  elseif ($n -match "Kingston|SA400|SNV|KC\d") {"Kingston"} elseif ($n -match "Seagate|ST\d") {"Seagate"} else {""}
}

# ===================== GUIDE BIOS PERSONNALISÉ =====================
Etape-Chargement 62 70 "Carte mère et BIOS..."
# Détection carte mère / BIOS / UEFI / Secure Boot / TPM + texte du guide (scripts\Guide-BIOS.ps1)
$profilBios = $null; $texteBios = ""; $matBios = $null
try {
  . (Join-Path $dir "Guide-BIOS.ps1")
  $matBios = if ($env:LK_SIMU_RAPIDE) { @{} } else { Lire-MaterielBios }
  $profilBios = Get-ProfilBios $matBios
  $texteBios = Get-GuideBios $matBios
} catch { $texteBios = "Le guide personnalisé n'a pas pu être généré ($($_.Exception.Message)).`r`nUtilise le guide générique : guides\Guide-BIOS.txt" }

# ===================== PILOTES OFFICIELS =====================
$pilotes = @()
$enc = [uri]::EscapeDataString
if ($cpuMarque -eq "AMD") {
  $pilotes += @{ Nom = "Pilotes chipset AMD"; Desc = "Ouvre la page officielle AMD (chipset Ryzen)."; Url = "https://www.amd.com/fr/support/download/drivers.html" }
} elseif ($cpuMarque -eq "Intel") {
  $pilotes += @{ Nom = "Intel Driver & Support Assistant"; Desc = "Chipset, Wi-Fi, iGPU. Installé automatiquement depuis Intel (winget)."; Winget = "Intel.IntelDriverAndSupportAssistant"; Url = "https://www.intel.com/content/www/fr/fr/support/detect.html" }
}
foreach ($g in $gpus) {
  switch (Gpu-Marque $g) {
    "NVIDIA" { $pilotes += @{ Nom = "Pilote NVIDIA (NVIDIA App)"; Desc = ((T "Pour {0}. Ouvre la page officielle NVIDIA.") -f $g.Name); Url = "https://www.nvidia.com/fr-fr/software/nvidia-app/" } }
    "AMD"    { $pilotes += @{ Nom = "Pilote AMD Adrenalin"; Desc = ((T "Pour {0}. Ouvre la page officielle AMD.") -f $g.Name); Url = "https://www.amd.com/fr/support/download/drivers.html" } }
    "Intel"  { if (-not ($pilotes | Where-Object { $_.Winget -eq "Intel.IntelDriverAndSupportAssistant" })) {
                 $pilotes += @{ Nom = "Pilote graphique Intel"; Desc = ((T "Pour {0}. Installé automatiquement depuis Intel (winget).") -f $g.Name); Winget = "Intel.IntelDriverAndSupportAssistant"; Url = "https://www.intel.com/content/www/fr/fr/support/detect.html" } } }
  }
}
$q = $enc.Invoke("$cmModele")
switch -Regex ($cmMarque) {
  "MSI"      { $pilotes += @{ Nom = "Carte mère MSI $cmModele"; Desc = "BIOS, LAN, audio : page support officielle MSI."; Url = "https://www.msi.com/search/$q" } }
  "ASUS"     { $pilotes += @{ Nom = "Carte mère ASUS $cmModele"; Desc = "BIOS, LAN, audio : page support officielle ASUS."; Url = "https://www.asus.com/fr/searchresult?searchType=support&searchKey=$q" } }
  "Gigabyte" { $pilotes += @{ Nom = "Carte mère Gigabyte $cmModele"; Desc = "BIOS, LAN, audio : page support officielle Gigabyte."; Url = "https://www.gigabyte.com/fr/Search?kw=$q" } }
  "ASRock"   { $pilotes += @{ Nom = "Carte mère ASRock $cmModele"; Desc = "BIOS, LAN, audio : page support officielle ASRock."; Url = "https://www.asrock.com/support/index.fr.asp" } }
  default    { if ("$cmMarque$cmModele") { $pilotes += @{ Nom = "Carte mère / PC $cmMarque $cmModele".Trim(); Desc = "Recherche la page support du fabricant."; Url = "https://www.google.com/search?q=" + $enc.Invoke("$cmMarque $cmModele drivers support officiel") } } }
}
$vus = @{}
foreach ($d in $disks) {
  $m = Disque-Marque $d
  if (-not $m -or $vus[$m]) { continue }; $vus[$m] = $true
  switch ($m) {
    "Samsung"  { $pilotes += @{ Nom = "Samsung Magician"; Desc = "Firmware et santé des SSD Samsung (page officielle)."; Url = "https://semiconductor.samsung.com/consumer-storage/support/tools/" } }
    "Crucial"  { $pilotes += @{ Nom = "Crucial Storage Executive"; Desc = "Firmware des SSD Crucial (page officielle)."; Url = "https://www.crucial.com/support/storage-executive" } }
    "WD"       { $pilotes += @{ Nom = "WD Dashboard"; Desc = "Firmware des SSD WD / SanDisk (page officielle)."; Url = "https://support-en.wd.com/app/products/downloads/softwaredownloads" } }
    "Kingston" { $pilotes += @{ Nom = "Kingston SSD Manager"; Desc = "Firmware des SSD Kingston. Installé automatiquement (winget)."; Winget = "Kingston.SSDManager"; Url = "https://www.kingston.com/fr/support/technical/ssdmanager" } }
    "Seagate"  { $pilotes += @{ Nom = "Seagate SeaTools"; Desc = "Diagnostic des disques Seagate (page officielle)."; Url = "https://www.seagate.com/fr/fr/support/downloads/seatools/" } }
  }
}
$volC = Get-Volume -DriveLetter ($env:SystemDrive.Substring(0,1))

# Noms courts pour les cartes de statistiques
$cpuCourt = (($cpuNom -replace '\((R|TM)\)','' -replace '\bCPU\b|\bProcessor\b|\d+-Core|\bAMD\b|\bIntel\b','' -replace '@.*$','') -split '\s+' | Where-Object { $_ }) -join ' '
$gpuNom = if ($gpus.Count) { "$($gpus[0].Name)" } else { "" }
$gpuCourt = if ($gpuNom) { ($gpuNom -replace '\((R|TM)\)','' -replace '\bAMD\b|\bRadeon\b|\bNVIDIA\b|\bGeForce\b|\bGraphics\b|\(pilote non installé\)','' -replace '\s+',' ').Trim() } else { "Non détecté" }
if (-not $gpuCourt) { $gpuCourt = $gpuNom }

# ===================== THÈME =====================
function Hex($h) { [Drawing.ColorTranslator]::FromHtml($h) }
# Deux palettes (sombre / claire) : mêmes rôles, l'accent violet ne change pas.
# Chaque couleur claire est différente de toutes les autres : le changement de thème en direct
# remplace une couleur par son équivalent dans toute la fenêtre.
$palettes = @{
  sombre = [ordered]@{ Titre = "#0e0e13"; Fond = "#121217"; Carte = "#18181e"; CarteSurvol = "#1e1e25"; Blanc = "#ededf2"; Gris = "#8b8b9a"; Gris2 = "#6c6c7a"; Gris3 = "#565663"
    AccentClair = "#a78bfa"; NavActif = "#1c1730"; NavSurvol = "#17171c"; Piste = "#25252d"; Piste2 = "#1f1f26"; Pouce = "#2d2d36"; Texte2 = "#c6c6d2"; BoutonTitre = "#202027"; Off = "#35353f"; Orange = "#f0a03c"; Vert = "#a594f9"; Rouge = "#f0716f"; Bord = "#24242c"; BordSurvol = "#3b3557"; Vif = "#3fe3ff" }
  clair  = [ordered]@{ Titre = "#efeff4"; Fond = "#f7f7fa"; Carte = "#fdfdfe"; CarteSurvol = "#f1f1f5"; Blanc = "#18181f"; Gris = "#5f5f6e"; Gris2 = "#74748a"; Gris3 = "#9a9aab"
    AccentClair = "#7c4dff"; NavActif = "#ece6ff"; NavSurvol = "#ececf1"; Piste = "#e4e4ea"; Piste2 = "#eaeaef"; Pouce = "#cdcdd8"; Texte2 = "#33333f"; BoutonTitre = "#e6e6ec"; Off = "#c9c9d4"; Orange = "#b45309"; Vert = "#6d4ce0"; Rouge = "#b91c1c"; Bord = "#e3e3eb"; BordSurvol = "#cdc2f6"; Vif = "#0e7490" }
}
function Charger-Palette($clair) {
  $pl = $palettes[$(if ($clair) { "clair" } else { "sombre" })]
  $script:cTitre = Hex $pl.Titre; $script:cSide = Hex $pl.Titre; $script:cFond = Hex $pl.Fond; $script:cCarte = Hex $pl.Carte; $script:cCarteSurvol = Hex $pl.CarteSurvol
  $script:cBlanc = Hex $pl.Blanc; $script:cGris = Hex $pl.Gris; $script:cGris2 = Hex $pl.Gris2; $script:cGris3 = Hex $pl.Gris3
  $script:cVif = Hex $pl.Vif; $script:cAccentClair = Hex $pl.AccentClair; $script:cNavActif = Hex $pl.NavActif; $script:cNavSurvol = Hex $pl.NavSurvol
  $script:cPiste = Hex $pl.Piste; $script:cPiste2 = Hex $pl.Piste2; $script:cPouce = Hex $pl.Pouce; $script:cTexte2 = Hex $pl.Texte2; $script:cBoutonTitre = Hex $pl.BoutonTitre; $script:cOff = Hex $pl.Off
  $script:cTexteActif = if ($clair) { Hex "#4b22c9" } else { [Drawing.Color]::White }
  $script:cOrange = Hex $pl.Orange; $script:cVert = Hex $pl.Vert; $script:cRouge = Hex $pl.Rouge
  $script:cBord = Hex $pl.Bord; $script:cBordSurvol = Hex $pl.BordSurvol
}
Charger-Palette $script:themeClair
[LkBadge]::Light = $script:themeClair
[LkCard]::BordDefaut = $cBord; [LkCard]::BordSurvolDefaut = $cBordSurvol
# v5.7 : rendu lissé (WS_EX_COMPOSITED) désactivable dans Paramètres (pris en compte au prochain démarrage)
[LkCard]::Compose = -not ("$((Get-ItemProperty -Path $cleConfig -Name RenduLisse -ErrorAction SilentlyContinue).RenduLisse)" -eq "0")
$cAccent  = Hex "#8c52ff"
$cAccent2 = Hex "#5468ff"   # v5.7 : départ du dégradé des boutons principaux (bleu du logo, texte blanc lisible)
$cCyan    = Hex "#12e0ff"

# ===================== FENÊTRE =====================
Etape-Chargement 70 80 "Préparation de l'interface..."
# v5.8 : barre latérale à gauche (232 px), la zone des pages garde ses 1000 px
$largeurNav = 232
$f = New-Object Windows.Forms.Form
$f.Text = "LuKZyR Optimisation"
$f.ClientSize = Sz (1000 + $largeurNav) 660
$f.StartPosition = "CenterScreen"
$f.FormBorderStyle = "None"
$f.BackColor = $cFond
$f.ForeColor = $cBlanc
$f.Font = Police 13
$f.AutoScaleMode = "None"
function DoubleTampon($c) { try { $c.GetType().GetProperty("DoubleBuffered", [Reflection.BindingFlags]"NonPublic,Instance").SetValue($c, $true, $null) } catch {} }
DoubleTampon $f
$f.KeyPreview = $true
# Bulles d'aide (survol d'un réglage)
$tip = New-Object Windows.Forms.ToolTip; $tip.InitialDelay = 450; $tip.ReshowDelay = 150; $tip.AutoPopDelay = 20000; $tip.ShowAlways = $true
# Logo : UN seul jeu de fichiers à remplacer (assets\lukzyr.ico pour la fenêtre et l'exe, assets\logo.png pour l'en-tête)
$ico = Join-Path $racine "assets\lukzyr.ico"
$logoPng = Join-Path $racine "assets\logo.png"
if (Test-Path $ico) { try { $f.Icon = New-Object Drawing.Icon($ico) } catch {} }
$f.Add_Shown({ try { $v = 2; [void][LkNative]::DwmSetWindowAttribute($f.Handle, 33, [ref]$v, 4) } catch {} })

function Lbl($parent, $texte, $x, $y, $w, $h, $font, $couleur, $fond) {
  $l = New-Object Windows.Forms.Label; $l.Text = (T $texte); $l.Location = Pt $x $y; $l.Size = Sz $w $h; $l.Font = $font
  $l.ForeColor = $couleur; $l.BackColor = $fond; $l.AutoEllipsis = $true; $l.UseMnemonic = $false
  $parent.Controls.Add($l); return $l
}
function Largeur($texte, $font) { [Windows.Forms.TextRenderer]::MeasureText([string]$texte, $font).Width }
# v5.2 : icône vectorielle (s'emploie comme Lbl ; $texte = nom d'icône ou ancien glyphe ; -Puce = pastille colorée derrière)
function Icone($parent, $texte, $x, $y, $w, $h, $taille, $couleur, $fond, $Puce = $null) {
  $i = New-Object LkIcon; $i.Text = "$texte"; $i.Location = Pt $x $y; $i.Size = Sz $w $h; $i.IconSize = [float]($taille * $sc)
  $i.ForeColor = $couleur; $i.BackColor = $fond; $i.Radius = S 9
  if ($Puce) { $i.Chip = $Puce }
  $parent.Controls.Add($i); return $i
}

# --- v5.8 : barre latérale (logo, recherche, navigation à icônes, « Tout annuler », Paramètres) ---
$nav = New-Object LkPanel; $nav.Location = Pt 0 0; $nav.Size = Sz $largeurNav 660; $nav.BackColor = $cSide
$f.Controls.Add($nav)
$traitNav = New-Object Windows.Forms.Panel; $traitNav.Location = Pt ($largeurNav - 1) 0; $traitNav.Size = Sz 1 660; $traitNav.BackColor = $cPiste2
$nav.Controls.Add($traitNav)
# --- Barre du haut (au-dessus des pages) : fil d'Ariane, thème, réduire, fermer ---
$titreBar = New-Object Windows.Forms.Panel
$titreBar.Location = Pt $largeurNav 0; $titreBar.Size = Sz 1000 56; $titreBar.BackColor = $cFond
DoubleTampon $titreBar
$f.Controls.Add($titreBar)
# v5.5 : logo réduit une seule fois en haute qualité à la taille exacte (net en petite taille)
function Logo-Net($taille) {
  try {
    $src = if (Test-Path $logoPng) { [Drawing.Image]::FromFile($logoPng) } elseif (Test-Path $ico) { (New-Object Drawing.Icon($ico, 256, 256)).ToBitmap() } else { return $null }
    $n = S $taille; $bm = New-Object Drawing.Bitmap $n, $n; $gr = [Drawing.Graphics]::FromImage($bm)
    $gr.InterpolationMode = "HighQualityBicubic"; $gr.PixelOffsetMode = "HighQuality"; $gr.SmoothingMode = "AntiAlias"
    $gr.DrawImage($src, 0, 0, $n, $n); $gr.Dispose(); $src.Dispose(); return $bm
  } catch { return $null }
}
$logoImg = New-Object Windows.Forms.PictureBox; $logoImg.Location = Pt 20 18; $logoImg.Size = Sz 34 34; $logoImg.SizeMode = "CenterImage"; $logoImg.BackColor = $cSide
$logoImg.Image = Logo-Net 34
$nav.Controls.Add($logoImg)
$logo = Lbl $nav "LuKZyR" 62 15 150 24 (Police 17 "Bold") $cBlanc $cSide; $logo.TextAlign = "MiddleLeft"
$credit = Lbl $nav ("Optimisation · " + (Version-Affichee)) 63 39 160 16 (Police 10.5 "Bold") $cGris2 $cSide; $credit.TextAlign = "MiddleLeft"
$tip.SetToolTip($credit, (T "Version bêta : merci de signaler les bugs (Journal > Exporter le journal)."))
$bBeta = $null
$lFil = Lbl $titreBar "" 32 0 640 56 (Police 12 "Bold") $cGris2 $cFond; $lFil.TextAlign = "MiddleLeft"
foreach ($c in $nav, $titreBar, $lFil, $logo, $credit, $logoImg) { $c.Add_MouseDown({ if ($_.Button -eq "Left") { [LkNative]::Drag($f) } }) }
function BoutonTitre($txt, $x, $survol, $taille = 16) {
  $b = Icone $titreBar $txt $x 0 44 56 $taille $cGris $cFond
  $b.Cursor = "Hand"; $b.Tag = $survol
  $b.Add_MouseEnter({ $this.BackColor = $this.Tag; $this.ForeColor = $cBlanc }); $b.Add_MouseLeave({ $this.BackColor = $cFond; $this.ForeColor = $cGris })
  return $b
}
$bFermer = BoutonTitre "x" 956 (Hex "#c4283c") 15
$bMini   = BoutonTitre "minus" 912 $cBoutonTitre 15
$bTheme  = BoutonTitre "theme" 868 $cBoutonTitre 17
foreach ($bt in $bFermer, $bMini, $bTheme) { $bt.BringToFront() }
$tip.SetToolTip($bFermer, (T "Fermer")); $tip.SetToolTip($bMini, (T "Réduire")); $tip.SetToolTip($bTheme, (T "Thème clair / sombre"))
$bFermer.Add_Click({ $f.Close() })
$bMini.Add_Click({ $f.WindowState = "Minimized" })

# Sections (onglets) et leurs sous-pages (pastilles en haut de la zone)
$groupes = [ordered]@{
  accueil     = @{ Nom = "Tableau de bord"; Pages = @("accueil") }
  performance = @{ Nom = "Performance"; Pages = @("perf", "session") }
  nettoyage   = @{ Nom = "Nettoyage"; Pages = @("nettoyage") }
  applis      = @{ Nom = "Applications"; Pages = @("applis") }
  systeme     = @{ Nom = "Système"; Pages = @("demarrage", "reseau", "espace", "sysoutils") }
  materiel    = @{ Nom = "Matériel"; Pages = @("infos", "pilotes", "sante", "bios") }
  journal     = @{ Nom = "Journal"; Pages = @("journal") }
  parametres  = @{ Nom = "Paramètres"; Pages = @("parametres") }
}
$groupeDe = @{}; $derniere = @{}
foreach ($g in $groupes.Keys) { foreach ($pg in $groupes[$g].Pages) { $groupeDe[$pg] = $g }; $derniere[$g] = $groupes[$g].Pages[0] }
$nomsSousPages = @{ perf = "Réglages"; session = "Session de jeu"; espace = "Espace disque"; infos = "Mon PC"; demarrage = "Démarrage"; reseau = "Réseau"; sysoutils = "Réparation et sécurité"; pilotes = "Pilotes"; sante = "Santé"; bios = "BIOS" }

# v5.8 : navigation de la barre latérale (une entrée par section + raccourci « Session de jeu »)
$fNav = Police 13.5 "Bold"; $fNavActif = Police 13.5 "Bold"
$onglets = [ordered]@{}
function Element-Nav($cle, $icone, $texte, $y) {
  $n = New-Object LkNav; $n.Text = (T $texte); $n.Icon = $icone; $n.Font = $fNav; $n.ActiveFont = $fNavActif; $n.IconSize = [float](19 * $sc); $n.Radius = S 10
  $n.Location = Pt 12 $y; $n.Size = Sz 208 40; $n.ForeColor = $cGris; $n.ActiveFore = $cBlanc; $n.HoverFill = $cNavSurvol; $n.ActiveFill = $cNavActif; $n.Tag = $cle
  $n.Add_Click({ if ($this.Tag -eq "session") { Afficher "session" } else { Afficher-Groupe $this.Tag } })
  $nav.Controls.Add($n); $script:onglets[$cle] = $n
}
$defNav = @(
  @("accueil", "home", "Accueil"), @("performance", "zap", "Performance"), @("session", "gamepad", "Session de jeu"),
  @("nettoyage", "sparkles", "Nettoyage"), @("applis", "grid", "Applications"), @("systeme", "sliders", "Système"),
  @("materiel", "cpu", "Matériel"), @("journal", "list", "Journal")
)
$yNav = 124
foreach ($d in $defNav) { Element-Nav $d[0] $d[1] $d[2] $yNav; $yNav += 42 }
# Encadré « Tout est annulable »
$boiteAnn = New-Object LkCard; $boiteAnn.Fill = $cCarte; $boiteAnn.Radius = S 12; $boiteAnn.Location = Pt 12 474; $boiteAnn.Size = Sz 208 112
[void](Lbl $boiteAnn "Tout est annulable" 14 11 180 20 (Police 12.5 "Bold") $cBlanc $cCarte)
[void](Lbl $boiteAnn "Point de restauration + sauvegarde avant chaque changement." 14 32 184 34 (Police 11) $cGris $cCarte)
$bAnnNav = New-Object LkButton; $bAnnNav.Text = (T "Tout annuler"); $bAnnNav.Icon = "undo"; $bAnnNav.Font = Police 12 "Bold"; $bAnnNav.Radius = S 9
$bAnnNav.Location = Pt 12 70; $bAnnNav.Size = Sz 184 32; $bAnnNav.Fill = $cCarteSurvol; $bAnnNav.HoverFill = $cNavActif; $bAnnNav.ForeColor = $cBlanc
$bAnnNav.Add_Click({ Tout-Annuler })
$boiteAnn.Controls.Add($bAnnNav); $nav.Controls.Add($boiteAnn)
$tip.SetToolTip($bAnnNav, (T "Remet les réglages modifiés par LuKZyR à leur valeur d'origine."))
Element-Nav "parametres" "settings" "Paramètres" 598
$souligne = New-Object LkIndicator; $souligne.Visible = $false   # v5.8 : plus de soulignement d'onglet

# --- Zone principale ---
$main = New-Object LkPanel
$main.Location = Pt $largeurNav 56; $main.Size = Sz 1000 604; $main.BackColor = $cFond
$f.Controls.Add($main)
$h1  = Lbl $main "" 32 18 600 32 (Police 22 "Bold") $cBlanc $cFond
$sub = Lbl $main "" 33 52 650 20 (Police 13) $cGris $cFond

# Zone des pages de section (le Tableau de bord a son propre panneau plein écran)
$zone = New-Object LkPanel
$zone.Location = Pt 32 84; $zone.Size = Sz 936 456; $zone.BackColor = $cFond
$main.Controls.Add($zone)
# Pastilles des sous-pages (Système, Matériel)
$barresPastilles = @{}; $pastilles = @{}
foreach ($g in $groupes.Keys) {
  if ($groupes[$g].Pages.Count -lt 2) { continue }
  $bp = New-Object LkPanel; $bp.Location = Pt 0 0; $bp.Size = Sz 936 34; $bp.BackColor = $cFond; $bp.Visible = $false
  $xc = 0
  foreach ($pg in $groupes[$g].Pages) {
    $b = New-Object LkButton; $b.Font = Police 12.5 "Bold"; $b.Radius = S 16; $b.Text = (T $nomsSousPages[$pg]); $b.Tag = $pg
    $w = [math]::Ceiling((Largeur $b.Text $b.Font) / $sc) + 34
    $b.Location = Pt $xc 0; $b.Size = Sz $w 32; $b.Fill = $cFond; $b.HoverFill = $cCarteSurvol; $b.ForeColor = $cGris
    $b.Add_Click({ Afficher $this.Tag })
    $bp.Controls.Add($b); $pastilles[$pg] = $b; $xc += $w + 8
  }
  $zone.Controls.Add($bp); $barresPastilles[$g] = $bp
}

$pages = [ordered]@{}
$toggles = New-Object System.Collections.ArrayList
function NouvellePage($nom, $titre, $sousTitre, [switch]$Defile, $Construire = $null) {
  $multi = $groupes[$groupeDe[$nom]].Pages.Count -gt 1
  if ($Defile) { $p = New-Object LkScroll; $p.Bar = S 8; $p.Thumb = $cPouce; $p.Step = S 72 } else { $p = New-Object LkPanel }
  if ($multi) { $p.Location = Pt 0 44; $p.Size = Sz 936 412 } else { $p.Location = Pt 0 0; $p.Size = $zone.ClientSize }
  $p.BackColor = $cFond; $p.Visible = $false
  $zone.Controls.Add($p)
  $script:pages[$nom] = @{ Panel = $p; Titre = $titre; Sous = $sousTitre; Construire = $Construire; Construite = $false; Haut = $p.Top }
  if ($Defile) { $p.Content.BackColor = $cFond; return $p.Content } else { return $p }
}
function Afficher-Groupe($g) { Afficher $derniere[$g] }
# v5.1 : l'onglet actif (gras + soulignement) est mis à jour TOUT DE SUITE et la barre redessinée
# immédiatement, avant de construire la page : il ne dépend plus de la fin d'une animation.
function Maj-Onglets($g, [bool]$anime) {
  # v5.8 : entrée active de la barre latérale + fil d'Ariane (« Système › Espace disque »)
  $cle = if ($script:pageActive -eq "session") { "session" } else { $g }
  foreach ($k in $onglets.Keys) { $onglets[$k].Active = ($k -eq $cle) }
  $pa = $script:pageActive
  $lFil.Text = if ($g -eq "accueil") { "" } else { (T $groupes[$g].Nom) + $(if ($groupes[$g].Pages.Count -gt 1 -and $nomsSousPages[$pa]) { "  ›  " + (T $nomsSousPages[$pa]) } else { "" }) }
  $nav.Update()
}
function Afficher($nom, [switch]$Forcer) {
  if ($tip) { $tip.Active = $false; $tip.Active = $true }   # v5.1 : pas de bulle d'aide oubliée d'une autre page
  $ancienne = $script:pageActive
  if ($ancienne -eq $nom -and -not $Forcer) { return }
  if (-not $pages.Contains($nom)) { return }
  $script:pageActive = $nom
  $g = $groupeDe[$nom]; $derniere[$g] = $nom; $script:groupeActif = $g
  $info = $pages[$nom]; $nouv = $info.Panel
  Maj-Onglets $g ([bool]$ancienne -and [LkAnim]::On)
  $accueil = ($nom -eq "accueil")
  # Pages lues sur le système : construites au 1er affichage (la lecture longue se fait en arrière-plan)
  if ($info.Construire -and -not $info.Construite) { $info.Construite = $true; try { & $info.Construire } catch { Log "Erreur page $nom : $($_.Exception.Message)" } }
  if ($nom -eq "session") { try { Maj-Session } catch { Log "Session de jeu : $($_.Exception.Message)" } }
  if ($nom -eq "perf" -and -not $script:verifsLancees) { $script:verifsLancees = $true; try { Lancer-Verifs } catch { Log "Vérifications : $($_.Exception.Message)" } }
  $anime = [LkAnim]::On -and $ancienne -and $ancienne -ne $nom -and $f.Visible
  [LkFade]::StopAll(); $script:fondu = $null
  $gel = $f.Visible -and $main.IsHandleCreated
  if ($gel) { [LkNative]::Redraw($main, $false) }
  try {
    $main.SuspendLayout()
    foreach ($c in $h1, $sub, $zone, $barreBas) { if ($c) { $c.Visible = -not $accueil } }
    if ($script:listeRech) { $script:listeRech.Visible = $false }
    if ($accueil) { $nouv.Left = 0; $nouv.Visible = $true; $nouv.BringToFront() }
    else {
      $pages["accueil"].Panel.Visible = $false
      foreach ($k in $barresPastilles.Keys) { $barresPastilles[$k].Visible = ($k -eq $g) }
      if ($barresPastilles.ContainsKey($g)) {
        foreach ($pg in $groupes[$g].Pages) {
          $b = $pastilles[$pg]
          if ($pg -eq $nom) { $b.Fill = $cAccent; $b.Fill2 = $cAccent2; $b.HoverFill = Hex "#7a40ee"; $b.ForeColor = [Drawing.Color]::White } else { $b.Fill = $cFond; $b.Fill2 = [Drawing.Color]::Empty; $b.HoverFill = $cCarteSurvol; $b.ForeColor = $cGris }
          $b.Invalidate()
        }
      }
      $nouv.Left = 0; $nouv.Visible = $true; $nouv.BringToFront()
      foreach ($k in @($pages.Keys)) { if ($k -ne $nom -and $k -ne "accueil") { $pages[$k].Panel.Visible = $false; $pages[$k].Panel.Left = 0 } }
      $h1.Text = (T $info.Titre); $sub.Text = (T $info.Sous)
    }
    $banniere.Visible = $script:banniereOn -and -not $accueil
    $main.ResumeLayout()
    # v5.7 : la page est « photographiée » pendant que le dessin est gelé : la 1re image affichée est déjà celle de l'animation
    if ($anime) { try { $fd = [LkFade]::Get($nouv.Parent); if ($fd.Prepare($nouv, $cFond, (S 10))) { $script:fondu = $fd } } catch {} }
  } finally {
    if ($gel) { [LkNative]::Redraw($main, $true) }
  }
  # Le titre reste lisible pendant le fondu (il part du gris, jamais de la couleur du fond)
  $h1.ForeColor = $cBlanc; $sub.ForeColor = $cGris
  if ($anime) {
    if ($script:fondu) { $script:fondu.Play(230, 26) }
    if (-not $accueil) { [LkAnim]::FadeFore($h1, $cGris, $cBlanc, 200) }
  }
  $script:pageVueA = Get-Date
  try { Maj-Moniteur } catch {}
}

# Badges : SÛR (gris) / NON RÉVERSIBLE (gris, cadenas) / AVANCÉ (orange) / DÉFINITIF (rouge)
# v5.6 : « NON RÉVERSIBLE » = sans risque pour Windows, mais « Tout annuler » ne peut pas le défaire
# (applis supprimées ou installées, fichiers effacés, réparation) : plus de fausse promesse de réversibilité.
$badges = @{
  s = @{ Texte = "SÛR"; Clair = "#9a9aae"; Fonce = "#6b6b80"; Icone = "shield-check" }
  n = @{ Texte = "NON RÉVERSIBLE"; Clair = "#9a9aae"; Fonce = "#6b6b80"; Icone = "lock" }
  a = @{ Texte = "AVANCÉ"; Clair = "#f5a524"; Fonce = "#c2410c"; Icone = "alert" }
  d = @{ Texte = "DÉFINITIF"; Clair = "#f87171"; Fonce = "#dc2626"; Icone = "lock" }
  hi = @{ Texte = "IMPACT ÉLEVÉ"; Clair = "#f5a524"; Fonce = "#c2410c"; Icone = "zap" }
  mo = @{ Texte = "IMPACT MOYEN"; Clair = "#a78bfa"; Fonce = "#6d28d9"; Icone = "gauge" }
  lo = @{ Texte = "IMPACT FAIBLE"; Clair = "#9a9aae"; Fonce = "#6b6b80"; Icone = "check" }
}
$fBadge = Police 9.5 "Bold"
$aidesBadge = @{
  s = "SÛR : réversible avec « Tout annuler »."
  n = "NON RÉVERSIBLE : sans risque pour Windows, mais « Tout annuler » ne peut pas le défaire (applis supprimées ou installées, fichiers effacés)."
  a = "AVANCÉ : réversible, mais change un comportement important de Windows. Lis bien la description."
  d = "DÉFINITIF : ne peut pas être annulé par « Tout annuler » (seulement par un point de restauration)."
  hi = "Impact estimé ÉLEVÉ : appli connue pour ralentir l'ouverture de session (launcher, synchro, logiciel RGB...). La désactiver ne la désinstalle pas."
  mo = "Impact estimé MOYEN : programme assez lourd lancé avec Windows."
  lo = "Impact estimé FAIBLE : petit programme, peu de différence au démarrage."
}
function Badge($parent, $type, $x, $y) {
  $bd = New-Object LkBadge; $bd.Text = (T $badges[$type].Texte); $bd.Font = $fBadge; $bd.Radius = S 5
  $bd.Accent = Hex $badges[$type].Clair; $bd.AccentLight = Hex $badges[$type].Fonce
  $bd.Icon = $badges[$type].Icone; $bd.IconSize = [float](11 * $sc)
  $bd.Location = New-Object Drawing.Point($x, $y); $bd.Size = New-Object Drawing.Size(((Largeur $bd.Text $fBadge) + (S 26)), (S 18))
  $parent.Controls.Add($bd); return $bd
}

# Ligne de réglage : carte arrondie + titre + badge + description + interrupteur (toute la carte est cliquable)
# -X / -W : position et largeur (grille 2 colonnes) ; -Badge s|a|d
$script:silencieux = $false
function Ligne($page, $y, $titre, $desc, $actif = $true, $couleur = $null, $cle = $null, [switch]$Hors, $X = 0, $W = 920, $Badge = $null) {
  $h = if ($Badge) { 76 } else { 62 }
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.HoverFill = $cCarteSurvol; $c.Radius = S 12
  $c.Location = Pt $X $y; $c.Size = Sz $W $h; $c.Cursor = "Hand"
  $fT = Police 14 "Bold"
  $wBadge = if ($Badge) { [math]::Ceiling(((Largeur (T $badges[$Badge].Texte) $fBadge) + (S 26)) / $sc) + 6 } else { 0 }
  $wMax = $W - 18 - 72 - $wBadge
  foreach ($tp in 13, 12) { if (([math]::Ceiling((Largeur (T $titre) $fT) / $sc) + 4) -gt $wMax) { $fT = Police $tp "Bold" } }
  $wT = [math]::Min($wMax, [math]::Ceiling((Largeur (T $titre) $fT) / $sc) + 4)
  $t = Lbl $c $titre 18 11 $wT 22 $fT $(if ($couleur) { $couleur } else { $cBlanc }) $cCarte
  $els = @($c, $t)
  if ($Badge) { $bd = Badge $c $Badge (S (18 + $wT + 6)) (S 13); $els += $bd }
  $d = Lbl $c $desc 18 34 ($W - 96) $(if ($Badge) { 34 } else { 18 }) (Police 12) $cGris $cCarte
  $els += $d
  $sw = New-Object LkToggle; $sw.Size = Sz 44 24; $sw.Location = Pt ($W - 62) ([int](($h - 24) / 2)); $sw.OffColor = $cOff
  if ($couleur) { $sw.OnColor = $couleur }
  $sw.Checked = $actif; $sw.Tag = @{ Titre = $titre; Cle = $cle; Badge = $Badge; Desc = $desc }
  $sw.Add_CheckedChanged({ Confirmer-Risque $this; MajCompteur })
  $c.Controls.Add($sw)
  foreach ($el in $els) {
    $el.Cursor = "Hand"
    $el.Add_Click({ $card = if ($this -is [LkCard]) { $this } else { $this.Parent }; $s = $card.Controls | Where-Object { $_ -is [LkToggle] }; if ($s.Enabled) { $s.Checked = -not $s.Checked } })
    $el.Add_MouseEnter({ $card = if ($this -is [LkCard]) { $this } else { $this.Parent }; $card.SetHover($true) })
    $el.Add_MouseLeave({ $card = if ($this -is [LkCard]) { $this } else { $this.Parent }; if (-not $card.ClientRectangle.Contains($card.PointToClient([Windows.Forms.Cursor]::Position))) { $card.SetHover($false) } })
  }
  # Bulle d'aide : description complète + ce que veut dire le badge
  $aide = (T $titre) + "`n" + (T $desc)
  if ($Badge) { $aide += "`n`n" + (T $aidesBadge[$Badge]) }
  foreach ($el in @($els) + @($sw)) { $tip.SetToolTip($el, $aide) }
  $c.Tag = @{ Toggle = $sw; Titre = $titre }
  $page.Controls.Add($c); if (-not $Hors) { [void]$script:toggles.Add($sw) }
  return $sw
}
# Activer une option AVANCÉ / DÉFINITIF à la main demande une confirmation (pas pendant le choix d'un profil)
function Confirmer-Risque($sw) {
  if ($script:silencieux -or -not $sw.Checked -or $sw.Tag.Badge -notin @("a", "d") -or $TestAuto -or $env:LK_TEST) { return }
  $msg = if ($sw.Tag.Badge -eq "d") { (T "Option DÉFINITIVE : « {0} » ne pourra pas être annulé par « Tout annuler ».") -f (T $sw.Tag.Titre) } else { (T "Option AVANCÉE : « {0} ». Lis bien sa description avant de l'activer.") -f (T $sw.Tag.Titre) }
  if ((Boite ($msg + "`n`n" + (T "L'activer quand même ?")) "YesNo" "Warning") -ne "Yes") { $script:silencieux = $true; try { $sw.Checked = $false } finally { $script:silencieux = $false } }
}
# Grille 2 colonnes : titres de section + cartes d'option
function Grille($page) { @{ Page = $page; Y = 0; Col = 0; H = 0 } }
function G-Fin($g) { if ($g.Col -eq 1) { $g.Y += $g.H + 8; $g.Col = 0 } }
function G-Section($g, $texte) { G-Fin $g; if ($g.Y -gt 0) { $g.Y += 12 }; Section $g.Page $g.Y $texte; $g.Y += 32 }
function G-Option($g, $titre, $desc, $badge, $actif, $cle, $couleur = $null) {
  $x = if ($g.Col) { 464 } else { 0 }
  $sw = Ligne $g.Page $g.Y $titre $desc $actif $couleur $cle -X $x -W 456 -Badge $badge
  $g.H = 76
  if ($g.Col) { $g.Col = 0; $g.Y += 84 } else { $g.Col = 1 }
  return $sw
}
function Section($page, $y, $texte) {
  $s = New-Object LkSection; $s.Text = (T $texte); $s.Font = Police 10.5 "Bold"; $s.ForeColor = $cGris; $s.BackColor = $cFond; $s.Line = $cPiste2
  $s.Location = Pt 2 ($y + 4); $s.Size = Sz 918 20; $page.Controls.Add($s); $script:derniereSection = $s
}
# Carte-action : icône + titre + description (+ contrôle à droite), cliquable
function Survol-Carte($el) {
  $el.Add_MouseEnter({ $cd = $this; while ($cd -and -not ($cd -is [LkCard])) { $cd = $cd.Parent }; if ($cd) { $cd.SetHover($true) } })
  $el.Add_MouseLeave({ $cd = $this; while ($cd -and -not ($cd -is [LkCard])) { $cd = $cd.Parent }; if ($cd -and -not $cd.ClientRectangle.Contains($cd.PointToClient([Windows.Forms.Cursor]::Position))) { $cd.SetHover($false) } })
}
function LigneOption($page, $y, $glyphe, $titre, $desc, $couleurIcone = $null, $X = 0, $W = 920, $Badge = $null) {
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.HoverFill = $cCarteSurvol; $c.Radius = S 12
  $c.Location = Pt $X $y; $c.Size = Sz $W 62; $c.Cursor = "Hand"
  $colI = if ($couleurIcone) { $couleurIcone } else { $cAccentClair }
  $ic = Icone $c $(if ($glyphe -is [string]) { $glyphe } else { [string][char]$glyphe }) 13 14 34 34 19 $colI $cCarte -Puce $colI
  $fT = Police 14 "Bold"; $wT = [math]::Min(($W - 260), [math]::Ceiling((Largeur (T $titre) $fT) / $sc) + 4)
  $t = Lbl $c $titre 56 11 $wT 22 $fT $cBlanc $cCarte
  $d = Lbl $c $desc 56 33 ($W - 250) 18 (Police 12) $cGris $cCarte
  $els = @($c, $ic, $t, $d)
  if ($Badge) { $els += (Badge $c $Badge (S (56 + $wT + 6)) (S 13)) }
  foreach ($el in $els) { $el.Cursor = "Hand"; Survol-Carte $el }
  $page.Controls.Add($c)
  return @{ Carte = $c; Icone = $ic; Titre = $t; Desc = $d; Elements = $els }
}
# v5.3 : ouverture de dossier fiable (Paramètres > À propos, Journal)
# Crée le dossier s'il manque, lance explorer.exe (chemin entre guillemets), vérifie qu'une fenêtre
# s'est bien ouverte ; sinon 2e essai par le Shell Windows ; sinon message avec le chemin (copié).
function Fenetre-DossierOuverte($chemin) {
  try {
    try { if ([LkNative]::FenetreExplorateur([IO.Path]::GetFullPath($chemin))) { return $true } } catch {}
    $cible = ([IO.Path]::GetFullPath($chemin)).TrimEnd('\').ToLower()
    foreach ($w in @((New-Object -ComObject Shell.Application).Windows())) {
      try { $p = "$($w.Document.Folder.Self.Path)".TrimEnd('\').ToLower(); if ($p -eq $cible) { return $true } } catch {}
    }
  } catch {}
  return $false
}
function Ouvrir-Dossier($chemin) {
  try {
    if (-not (Test-Path -LiteralPath $chemin)) { [void](New-Item -ItemType Directory -Path $chemin -Force -ErrorAction Stop) }
    Log ((T "Ouverture du dossier") + " : $chemin")
    [void][Diagnostics.Process]::Start((Join-Path $env:WINDIR "explorer.exe"), "`"$chemin`"")
  } catch {
    [void](Boite ((T "Impossible d'ouvrir le dossier") + " :`n$chemin`n`n$($_.Exception.Message)") "OK" "Error"); return
  }
  # vérification sans bloquer l'interface : la fenêtre doit exister 3 à 6 s plus tard
  $script:dossierAVerifier = $chemin; $script:essaiDossier = 1
  if (-not $script:tDossier) {
    $script:tDossier = New-Object Windows.Forms.Timer; $script:tDossier.Interval = 3000
    $script:tDossier.Add_Tick({
      $ch = $script:dossierAVerifier
      if (Fenetre-DossierOuverte $ch) { $script:tDossier.Stop(); Log ((T "Dossier ouvert") + " : $ch"); return }
      # PC lent : on laisse encore 3 s à l'Explorateur avant un 2e essai (sinon deux fenêtres)
      if ($script:essaiDossier -eq 1) { $script:essaiDossier = 2; return }
      if ($script:essaiDossier -eq 2) {
        $script:essaiDossier = 3; Log "Explorateur : pas de fenêtre, 2e essai par le Shell Windows."
        try { (New-Object -ComObject Shell.Application).Open($ch) } catch {}
        return
      }
      $script:tDossier.Stop()
      try { [Windows.Forms.Clipboard]::SetText($ch) } catch {}
      Log "Explorateur : le dossier ne s'est pas ouvert ($ch)."
      if (-not $env:LK_TEST) { [void](Boite ((T "L'Explorateur Windows n'a pas ouvert le dossier. Son chemin a été copié : colle-le dans la barre d'adresse de l'Explorateur.") + "`n`n$ch") "OK" "Warning") }
    })
  }
  $script:tDossier.Stop(); $script:tDossier.Start()
}
function Bouton($parent, $texte, $x, $y, $w, $h, [switch]$Principal, $Couleur = $null) {
  $b = New-Object LkButton; $b.Text = (T $texte); $b.Font = Police 12 "Bold"; $b.Radius = S 10; $b.Location = Pt $x $y; $b.Size = Sz $w $h
  if ($Couleur) { $b.Fill = $Couleur; $b.HoverFill = [LkAnim]::Mix($Couleur, [Drawing.Color]::Black, 0.12) }
  elseif ($Principal) { $b.Fill = $cAccent; $b.Fill2 = $cAccent2; $b.HoverFill = Hex "#7a40ee" } else { $b.Fill = $cCarteSurvol; $b.HoverFill = $cNavActif; $b.ForeColor = $cBlanc }
  $parent.Controls.Add($b); $b.BringToFront(); return $b   # v5.3 : jamais caché sous un texte de la carte
}

# ===================== MATÉRIEL > MON PC =====================
$pInfos = NouvellePage "infos" "Matériel" "Composants détectés sur ce PC." -Defile
$osNom = ("$($os.Caption)" -replace '^Microsoft\s+','').Trim()
$infos = @(
  @("PROCESSEUR", $cpuNom),
  @("CARTE GRAPHIQUE", $(if ($gpus.Count) { ($gpus | ForEach-Object { "$($_.Name)" + $(if ($_.VramGo -gt 0) { " · $($_.VramGo) $uGo" } else { "" }) }) -join "`n" } else { T "Non détectée" })),
  @("CARTE MÈRE", ((("$cmMarque $cmModele".Trim() | ForEach-Object { if ($_) { $_ } else { T "Non communiquée" } }) + "`nBIOS $($bios.SMBIOSBIOSVersion)"))),
  @("MÉMOIRE", ("$ramGo $uGo $ramType".Trim() + $(if ($ramMhz) { "`n$ramMhz MHz" } else { "" }))),
  @("STOCKAGE", $(($disks | ForEach-Object { "$($_.FriendlyName) · $([math]::Round($_.Size/1GB)) $uGo $(if ("$($_.MediaType)" -match 'SSD|HDD') { $_.MediaType })".Trim() }) -join "`n")),
  @("SYSTÈME", ("$osNom $osVer".Trim() + "`n$($env:SystemDrive) $([math]::Round($volC.SizeRemaining/1GB)) $(T 'Go libres sur') $([math]::Round($volC.Size/1GB)) $uGo" + $(if ($portable) { "`n" + (T "PC portable") } else { "" })))
)
$iconesInfos = @("cpu", "monitor", "plug", "memory", "drive", "shield-check")
for ($i = 0; $i -lt $infos.Count; $i++) {
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.Radius = S 12
  $c.Location = Pt (($i % 2) * 464) ([math]::Floor($i / 2) * 122); $c.Size = Sz 456 114
  [void](Lbl $c $infos[$i][0] 18 14 400 16 (Police 10.5 "Bold") $cAccentClair $cCarte)
  [void](Lbl $c $infos[$i][1] 18 36 380 70 (Police 13 "Bold") $cBlanc $cCarte)
  [void](Icone $c $iconesInfos[$i] 402 14 36 36 19 $cAccentClair $cCarte -Puce $cAccent)
  $pInfos.Controls.Add($c)
}
# v5.7 : rapport système (lecture seule, fichier sur le Bureau)
$yInfos = [math]::Ceiling($infos.Count / 2) * 122 + 12
Section $pInfos $yInfos "RAPPORT"; $yInfos += 32
$oRap = LigneOption $pInfos $yInfos "file-text" "Rapport système" "Matériel, pilotes, Windows et réglages appliqués dans un fichier HTML + texte sur le Bureau. Rien n'est envoyé."
$bRap = Bouton $oRap.Carte "Exporter" 756 13 148 36 -Principal; $bRap.Icon = "download"
$bRap.Add_Click({ Exporter-Rapport })
foreach ($el in $oRap.Elements) { $el.Add_Click({ Exporter-Rapport }) }

# ===================== MATÉRIEL > PILOTES =====================
$pP = NouvellePage "pilotes" "Pilotes" "Pilotes officiels des fabricants de tes composants." -Defile
$y = 0
# v5.7 : version et âge du pilote graphique INSTALLÉ (lecture seule) + lien vers la page officielle
function Info-PiloteGpu($g) {
  $r = @{ Version = "$($g.DriverVersion)"; Date = $null; Age = -1; Logiciel = "" }
  try { $d = $g.DriverDate; if ($d -is [datetime]) { $r.Date = $d } elseif ("$d" -match '^(\d{8})') { $r.Date = [datetime]::ParseExact($matches[1], "yyyyMMdd", $null) } } catch {}
  if ($r.Date) { $r.Age = [int]((Get-Date) - $r.Date).TotalDays }
  try {
    foreach ($k in @(Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
      $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
      if ("$($p.DriverDesc)" -ne "$($g.Name)") { continue }
      if ($p.RadeonSoftwareVersion) { $r.Logiciel = "AMD Software Adrenalin $($p.RadeonSoftwareVersion)" }
      break
    }
  } catch {}
  return $r
}
$script:infosPilotes = @()
foreach ($g in $gpus) {
  if (-not $g.DriverVersion) { continue }
  $ip = Info-PiloteGpu $g; $ip.Nom = "$($g.Name)"; $script:infosPilotes += $ip
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.Radius = S 12; $c.Location = Pt 0 $y; $c.Size = Sz 920 84
  [void](Icone $c "monitor" 13 22 40 40 20 $cAccentClair $cCarte -Puce $cAccent)
  [void](Lbl $c ((T "Pilote graphique installé") + " · $($g.Name)") 66 10 660 22 (Police 14 "Bold") $cBlanc $cCarte)
  $l2 = (T "Version") + " $($ip.Version)" + $(if ($ip.Date) { " · " + ((T "du {0}") -f $ip.Date.ToString("dd/MM/yyyy")) + " (" + ((T "il y a {0} jours") -f $ip.Age) + ")" } else { "" }) + $(if ($ip.Logiciel) { " · $($ip.Logiciel)" } else { "" })
  $lb2 = Lbl $c $l2 66 33 660 18 (Police 12) $cGris $cCarte; $lb2.AutoEllipsis = $true
  if ($ip.Age -gt 180) { $txt3 = "Pilote de plus de 6 mois : une version plus récente existe sûrement. Vérifie sur le site officiel."; $col3 = $cOrange }
  elseif ($ip.Age -ge 0) { $txt3 = "Pilote récent : rien à faire."; $col3 = $cVert } else { $txt3 = "Date du pilote inconnue."; $col3 = $cGris }
  [void](Lbl $c $txt3 66 54 660 18 (Police 12 "Bold") $col3 $cCarte)
  $url = switch (Gpu-Marque $g) { "NVIDIA" { "https://www.nvidia.com/fr-fr/drivers/" } "AMD" { "https://www.amd.com/fr/support/download/drivers.html" } "Intel" { "https://www.intel.com/content/www/fr/fr/support/detect.html" } default { $null } }
  if ($url) {
    $bS = Bouton $c "Site officiel" 740 22 164 40; $bS.Icon = "globe"; $bS.Tag = $url
    $bS.Add_Click({ try { Start-Process $this.Tag; Log ((T "Ouverture") + " : $($this.Tag)") } catch {} })
  }
  $pP.Controls.Add($c); $y += 92
}
if ($y) { $y += 4; Section $pP $y "PAGES OFFICIELLES DES FABRICANTS"; $y += 32 }
foreach ($pi in $pilotes) {
  $sw = Ligne $pP $y $pi.Nom $pi.Desc $false $null "pilote" -Badge "n"
  $sw.Tag.Pilote = $pi; $y += 86
}
if (-not $pilotes.Count) { [void](Lbl $pP "Aucun pilote spécifique détecté sur ce PC." 2 0 600 20 (Police 13) $cGris $cFond) }

# ===================== RAPPORT SYSTÈME (v5.7, lecture seule) =====================
# Fichier HTML (lisible, à envoyer pour avoir de l'aide) + même contenu en texte, sur le Bureau.
# Ne contient ni mot de passe, ni clé de licence, ni fichier personnel.
function Encoder-Html($s) { [Net.WebUtility]::HtmlEncode("$s") }
function Exporter-Rapport {
  try {
    $S = [ordered]@{}
    $S["LuKZyR Optimisation"] = @(@((T "Version"), "$(Version-Affichee) (build $VersionInterne)"), @((T "Date du rapport"), (Get-Date -Format "dd/MM/yyyy HH:mm")), @((T "Nom du PC"), $env:COMPUTERNAME))
    $S[(T "Processeur")] = @(@((T "Modèle"), $cpuNom), @((T "Cœurs / threads"), "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"), @((T "Fréquence de base"), "$($cpu.MaxClockSpeed) MHz"))
    $lg = @()
    foreach ($g in $gpus) {
      $ip = $script:infosPilotes | Where-Object { $_.Nom -eq "$($g.Name)" } | Select-Object -First 1
      $lg += , @("$($g.Name)", ($(if ($g.VramGo) { "$($g.VramGo) $uGo · " } else { "" }) + (T "pilote") + " $($g.DriverVersion)" + $(if ($ip.Date) { " (" + $ip.Date.ToString("dd/MM/yyyy") + ")" } else { "" }) + $(if ($ip.Logiciel) { " · $($ip.Logiciel)" } else { "" })))
    }
    if (-not $lg.Count) { $lg += , @((T "Carte graphique"), (T "Non détectée")) }
    $S[(T "Carte graphique")] = $lg
    $S[(T "Carte mère et BIOS")] = @(@((T "Modèle"), "$cmMarque $cmModele".Trim()), @("BIOS", "$($bios.SMBIOSBIOSVersion)" + $(if ($bios.ReleaseDate) { " (" + ([datetime]$bios.ReleaseDate).ToString("dd/MM/yyyy") + ")" } else { "" })))
    $lm = @(, @((T "Total"), ("$ramGo $uGo $ramType".Trim() + $(if ($ramMhz) { " · $ramMhz MHz" } else { "" }))))
    foreach ($m in $mems) { $lm += , @("$($m.DeviceLocator)", ("$([math]::Round([double]$m.Capacity / 1GB)) $uGo · $("$($m.Manufacturer)".Trim()) $("$($m.PartNumber)".Trim()) · $($m.ConfiguredClockSpeed) MHz")) }
    $S[(T "Mémoire")] = $lm
    $ld = @()
    foreach ($d in $disks) { $ld += , @("$($d.FriendlyName)", ("$([math]::Round($d.Size / 1GB)) $uGo · $($d.MediaType) · $($d.BusType) · " + (T "état") + " : $($d.HealthStatus)")) }
    foreach ($v in @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq "Fixed" -and $_.IsReady })) { $ld += , @("$($v.Name)", ((Taille-Txt $v.AvailableFreeSpace) + " " + (T "libres sur") + " " + (Taille-Txt $v.TotalSize) + " · $($v.DriveFormat)")) }
    $S[(T "Stockage")] = $ld
    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    $boot = $null; try { $boot = [datetime]$os.LastBootUpTime } catch {}
    $S["Windows"] = @(@((T "Édition"), "$osNom $osVer".Trim()), @("Build", "$($cv.CurrentBuild).$($cv.UBR)"), @((T "Démarré le"), $(if ($boot) { $boot.ToString("dd/MM/yyyy HH:mm") } else { "-" })), @((T "Type"), $(if ($portable) { T "PC portable" } else { T "PC fixe" })))
    $fr = $null; try { $fr = [LkNative]::Frequences() } catch {}
    $ecr = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $planTxt = "$(& powercfg.exe /getactivescheme 2>$null)"; if ($planTxt -match '\((.+)\)\s*$') { $planTxt = $matches[1] }
    $S[(T "Écran et alimentation")] = @(@((T "Écran principal"), ("$($ecr.Width) x $($ecr.Height)" + $(if ($fr -and $fr[0] -gt 1) { " · $($fr[0]) Hz (" + (T "max") + " $($fr[1]) Hz)" } else { "" }))), @((T "Plan d'alimentation"), $planTxt))
    $tc = if ($script:tempsLhm.Cpu) { "$($script:tempsLhm.Cpu) °C" } elseif ([LkMonitor]::Temp -gt 0) { "$([LkMonitor]::Temp) °C" } else { T "non lue (ouvre LibreHardwareMonitor pour l'avoir)" }
    $S[(T "Températures")] = @(@("CPU", $tc), @("GPU", $(if ($script:tempsLhm.Gpu) { "$($script:tempsLhm.Gpu) °C" } else { "-" })))
    $lr = @(); $res = @(); try { $res = @(Resume-Sauvegarde) } catch {}
    $der = "$((Get-ItemProperty -Path $cleConfig -Name DerniereOptimisation -ErrorAction Ignore).DerniereOptimisation)"
    $lr += , @((T "Dernière optimisation"), $(if ($der) { $der } else { T "jamais" }))
    $lr += , @((T "Réglages annulables"), "$($res.Count)")
    foreach ($x in ($res | Select-Object -First 60)) { $lr += , @("•", "$x") }
    $S[(T "Réglages appliqués par LuKZyR")] = $lr
    $ldm = @()
    if ($script:demarrage) { foreach ($el in $script:demarrage) { $ldm += , @("$($el.Nom)", ($(if ($el.Actif) { T "actif" } else { T "désactivé" }) + " · " + (T "impact") + " " + (T "$($el.Impact)"))) } }
    else { $ldm += , @("-", (T "Ouvre Système > Démarrage une fois pour l'ajouter au rapport.")) }
    $S[(T "Applis au démarrage")] = $ldm
    $S[(T "Session de jeu")] = @(, @((T "État"), $(if (Session-Active) { T "en cours" } else { T "aucune" })))

    $nom = "LuKZyR-rapport-" + (Get-Date -Format "yyyyMMdd-HHmm")
    $dos = if ($env:LK_TEST -or $TestAuto) { $dossierJournal } else { [Environment]::GetFolderPath("Desktop") }
    if (-not (Test-Path -LiteralPath $dos)) { [void](New-Item -ItemType Directory -Path $dos -Force) }
    $fHtml = Join-Path $dos "$nom.html"; $fTxt = Join-Path $dos "$nom.txt"
    $sbT = New-Object Text.StringBuilder
    [void]$sbT.Append("LuKZyR Optimisation - " + (T "Rapport système") + "`r`n" + ("=" * 60) + "`r`n")
    $sbH = New-Object Text.StringBuilder
    [void]$sbH.Append('<!DOCTYPE html><html lang="' + $script:langue + '"><head><meta charset="utf-8"><title>' + (Encoder-Html ((T "Rapport système") + " - $env:COMPUTERNAME")) + '</title><style>')
    [void]$sbH.Append('body{margin:0;background:#0f0f14;color:#e8e8f0;font:14px "Segoe UI",Arial,sans-serif}header{padding:28px 40px;background:linear-gradient(90deg,#12e0ff22,#7c3aed33);border-bottom:1px solid #24242c}h1{margin:0;font-size:24px}h1 span{background:linear-gradient(90deg,#12e0ff,#8b5cf6);-webkit-background-clip:text;color:transparent}header p{margin:6px 0 0;color:#9a9aae}main{max-width:980px;margin:0 auto;padding:24px 40px 48px}section{background:#18181f;border:1px solid #24242c;border-radius:12px;margin:0 0 16px;padding:16px 20px}h2{margin:0 0 10px;font-size:13px;letter-spacing:.06em;text-transform:uppercase;color:#a78bfa}table{width:100%;border-collapse:collapse}td{padding:5px 0;border-top:1px solid #22222a;vertical-align:top}tr:first-child td{border-top:0}td:first-child{width:34%;color:#9a9aae;padding-right:16px}footer{color:#6b6b80;font-size:12px;text-align:center;padding-bottom:24px}')
    [void]$sbH.Append('</style></head><body><header><h1><span>LuKZyR</span> ' + (Encoder-Html (T "Rapport système")) + '</h1><p>' + (Encoder-Html "$env:COMPUTERNAME · $(Get-Date -Format 'dd/MM/yyyy HH:mm') · $(Version-Affichee) (build $VersionInterne)") + '</p></header><main>')
    foreach ($k in $S.Keys) {
      [void]$sbT.Append("`r`n[$k]`r`n"); [void]$sbH.Append('<section><h2>' + (Encoder-Html $k) + '</h2><table>')
      foreach ($ln in $S[$k]) { [void]$sbT.Append(("  {0,-28} {1}" -f $ln[0], $ln[1]) + "`r`n"); [void]$sbH.Append('<tr><td>' + (Encoder-Html $ln[0]) + '</td><td>' + (Encoder-Html $ln[1]) + '</td></tr>') }
      [void]$sbH.Append('</table></section>')
    }
    $pied = T "Rapport en lecture seule : aucun mot de passe, aucune clé de licence, aucun fichier personnel."
    [void]$sbT.Append("`r`n$pied`r`n"); [void]$sbH.Append('</main><footer>' + (Encoder-Html $pied) + '</footer></body></html>')
    $u8 = New-Object Text.UTF8Encoding $true
    [IO.File]::WriteAllText($fHtml, $sbH.ToString(), $u8); [IO.File]::WriteAllText($fTxt, $sbT.ToString(), $u8)
    Log ((T "Rapport système exporté") + " : $fHtml (+ .txt)")
    if (-not $env:LK_TEST -and -not $TestAuto) { try { Start-Process $fHtml } catch { Ouvrir-Dossier $dos } }
  } catch {
    Log ((T "Rapport système impossible") + " : $($_.Exception.Message)")
    if (-not $env:LK_TEST) { [void](Boite ((T "Rapport système impossible") + " :`n$($_.Exception.Message)") "OK" "Error") }
  }
}

# ===================== NETTOYAGE & CONFIDENTIALITÉ =====================
$pN = NouvellePage "nettoyage" "Nettoyage et confidentialité" "Windows plus léger, moins de pubs et de suivi. Store, Xbox, Defender et Windows Update restent intacts." -Defile
$gN = Grille $pN
G-Section $gN "WINDOWS PLUS LÉGER"
$swDebloat  = G-Option $gN "Débloat Windows" "Applis inutiles retirées pour tous les comptes du PC (réinstallables via le Store), pubs, Bing, widgets." "n" $true "debloat"
$swCopilot  = G-Option $gN "Supprimer Copilot" "Retire l'appli Copilot (réinstallable via le Store) et masque son bouton." "n" $false "copilot"
$swOneDrive = G-Option $gN "Désinstaller OneDrive" "Tes fichiers déjà synchronisés restent sur le PC." "d" $false "onedrive"
$swEdge     = G-Option $gN "Désinstaller Microsoft Edge" "Garde WebView2. Fait après l'installation de Brave." "d" $false "edge" $cOrange
G-Section $gN "CONFIDENTIALITÉ"
$swTelem    = G-Option $gN "Réduire la télémétrie" "Données de diagnostic au minimum, service DiagTrack arrêté." "s" $true "telemetrie"

# ===================== APPLICATIONS =====================
$pAp = NouvellePage "applis" "Applications" "Installées depuis leurs sources officielles (winget). Décochées = rien ne se passe." -Defile
$gA = Grille $pAp
G-Section $gA "JEUX"
$swSteam    = G-Option $gA "Steam" "La plus grande boutique de jeux PC." "n" $true "app:Steam"
$swEpic     = G-Option $gA "Epic Games Launcher" "Jeux gratuits chaque semaine et Fortnite." "n" $true "app:Epic Games"
$swUbisoft  = G-Option $gA "Ubisoft Connect" "Launcher des jeux Ubisoft (Assassin's Creed, Rainbow Six...)." "n" $true "app:Ubisoft Connect"
$swRockstar = G-Option $gA "Rockstar Games Launcher" "Launcher de GTA V, Red Dead Redemption 2..." "n" $true "app:Rockstar Games"
$swEA       = G-Option $gA "EA app" "Launcher des jeux EA (EA SPORTS FC, Battlefield, Les Sims...)." "n" $false "app:EA app"
$swBnet     = G-Option $gA "Battle.net" "Launcher Blizzard (Call of Duty, Diablo, Overwatch...)." "n" $false "app:Battle.net"
$swGog      = G-Option $gA "GOG Galaxy" "Jeux sans DRM et bibliothèque de tous tes launchers." "n" $false "app:GOG Galaxy"
G-Section $gA "COMMUNICATION ET MUSIQUE"
$swDiscord  = G-Option $gA "Discord" "Discussion vocale et texte pour jouer entre amis." "n" $true "app:Discord"
$swSpotify  = G-Option $gA "Spotify" "Musique et podcasts en streaming." "n" $true "app:Spotify"
G-Section $gA "NAVIGATEURS"
$swBrave    = G-Option $gA "Brave" "Navigateur rapide avec bloqueur de pubs intégré." "n" $true "app:Brave"
G-Section $gA "CRÉATION ET UTILITAIRES"
$swObs      = G-Option $gA "OBS Studio" "Enregistrement et streaming de tes parties." "n" $false "app:OBS Studio"
$sw7zip     = G-Option $gA "7-Zip" "Ouvre et crée les archives .zip, .7z, .rar." "n" $false "app:7-Zip"
$swVlc      = G-Option $gA "VLC" "Lit toutes les vidéos et musiques." "n" $false "app:VLC"
G-Section $gA "ENTRETIEN"
$swMaj      = G-Option $gA "Mettre à jour les autres applis" "Met à jour tout ce que winget sait gérer." "n" $false "majtout"
G-Fin $gA
[void](Lbl $pAp "Une appli installée ne s'enlève pas avec « Tout annuler » : désinstalle-la depuis Paramètres Windows > Applications." 4 $gA.Y 900 20 (Police 11.5) $cGris $cFond)

# ===================== PERFORMANCE =====================
Etape-Chargement 80 88 $null
$pO = NouvellePage "perf" "Performance" "Jeu, processeur, mémoire et affichage. Tout est annulable avec « Tout annuler »." -Defile
# Clé, titre, description, actif par défaut, badge, page / section
$optims = @(
  @("ModeJeu",           "Mode Jeu", "Windows donne la priorité au jeu, enregistrement en arrière-plan coupé.", $true, "s", "perf", "JEU"),
  @("PrioriteJeux",      "Priorité aux jeux", "Plus de temps CPU et GPU pour le jeu au premier plan.", $true, "s", "perf", "JEU"),
  @("PlanifGPU",         "Planification GPU accélérée", "Moins de latence en jeu (après redémarrage).", $true, "s", "perf", "JEU"),
  @("Souris",            "Souris sans accélération", "Visée plus précise, mouvement 1:1.", $true, "s", "perf", "JEU"),
  @("JeuxFenetres",      "Optimisations des jeux en fenêtre", "Moins de latence en plein écran fenêtré, HDR auto possible.", $true, "s", "perf", "JEU"),
  @("VRR",               "Optimisations VRR (FreeSync / G-Sync)", "Fréquence variable aussi pour les jeux qui ne la gèrent pas.", $true, "s", "perf", "JEU"),
  @("PlanEquilibre",     "Plan d'alimentation Utilisation normale", "Conseillé pour Ryzen : mêmes performances en jeu, moins de chaleur.", $false, "s", "perf", "PROCESSEUR ET ALIMENTATION"),
  @("Alimentation",      "Plan d'alimentation Performances élevées", "Gain faible (0 à 2 %), un peu plus de chaleur. Ignoré sur PC portable.", $true, "s", "perf", "PROCESSEUR ET ALIMENTATION"),
  @("Hibernation",       "Désactiver l'hibernation", "Libère plusieurs Go sur C: et coupe le démarrage rapide.", $true, "s", "perf", "PROCESSEUR ET ALIMENTATION"),
  @("VBS",               "Désactiver VBS / intégrité de la mémoire", "Gain variable (souvent faible), un peu moins de sécurité. Peut rester actif avec Hyper-V ou WSL2.", $false, "a", "perf", "MÉMOIRE ET SÉCURITÉ"),
  @("Transparence",      "Désactiver la transparence", "Effets visuels plus légers.", $true, "s", "perf", "AFFICHAGE"),
  @("DelaiDemarrage",    "Applis de démarrage sans délai", "Windows lance tes applis de démarrage sans attendre 10 secondes.", $true, "s", "perf", "DÉMARRAGE ET ARRIÈRE-PLAN"),
  @("EdgeArrierePlan",   "Edge sans préchargement", "Edge ne démarre plus avec Windows et ne reste plus ouvert une fois fermé.", $true, "s", "perf", "DÉMARRAGE ET ARRIÈRE-PLAN"),
  @("AppsArrierePlan",   "Bloquer les applis du Store en arrière-plan", "Un peu moins de mémoire utilisée. Certaines notifications peuvent arriver en retard.", $false, "a", "perf", "DÉMARRAGE ET ARRIÈRE-PLAN"),
  @("OptimDistribution", "Désactiver l'Optimisation de la distribution", "Windows ne partage plus tes mises à jour avec d'autres PC (moins de bande passante).", $true, "s", "nettoyage", "CONFIDENTIALITÉ"),
  @("NettoyageTemp",     "Nettoyage des fichiers temporaires", "Vide les dossiers Temp de Windows et de l'utilisateur (fichiers effacés).", $true, "n", "nettoyage", "FICHIERS"),
  @("AssistantStockage", "Assistant de stockage", "Nettoyage automatique des fichiers inutiles.", $true, "s", "nettoyage", "FICHIERS"),
  @("WinSxS",            "Nettoyage des composants Windows", "Supprime les anciennes versions des composants (5 à 15 min). Mises à jour toujours désinstallables.", $false, "n", "nettoyage", "FICHIERS"),
  @("TRIM",              "TRIM des SSD", "Garde les SSD rapides.", $true, "s", "sysoutils", "STOCKAGE"),
  @("Reparation",        "Réparation DISM + SFC", "Vérifie et répare les fichiers Windows (environ 15 min).", $false, "n", "sysoutils", "RÉPARATION")
)
$gO = Grille $pO
$grilles = @{ perf = $gO; nettoyage = $gN }
function Placer-Optims($pageCle, $grille) {
  $sect = $null
  foreach ($o in @($optims | Where-Object { $_[5] -eq $pageCle })) {
    if ($o[6] -ne $sect) { $sect = $o[6]; if ($pageCle -ne "nettoyage" -or $sect -ne "CONFIDENTIALITÉ") { G-Section $grille $sect } }
    [void](G-Option $grille $o[1] $o[2] $o[4] $o[3] "optim:$($o[0])")
  }
  G-Fin $grille
}
Placer-Optims "perf" $gO
Placer-Optims "nettoyage" $gN
# v5.5 : un seul plan d'alimentation à la fois ; Edge absent => réglage grisé
$swOpt = @{}; foreach ($sw in $toggles) { if ("$($sw.Tag.Cle)" -like "optim:*") { $swOpt[$sw.Tag.Cle] = $sw } }
$swOpt["optim:Alimentation"].Add_CheckedChanged({ if ($this.Checked) { $swOpt["optim:PlanEquilibre"].Checked = $false } })
$swOpt["optim:PlanEquilibre"].Add_CheckedChanged({ if ($this.Checked) { $swOpt["optim:Alimentation"].Checked = $false } })
$script:edgePresent = [bool](@("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { $_ -and (Test-Path $_) })
if (-not $script:edgePresent) {
  $sE = $swOpt["optim:EdgeArrierePlan"]; $sE.Checked = $false; $sE.Enabled = $false
  foreach ($c in $sE.Parent.Controls) { if ($c -is [Windows.Forms.Label] -and $c.Text -eq (T $sE.Tag.Desc)) { $c.Text = (T "Edge n'est pas installé : rien à régler.") } }
}
# v5.5 : VÉRIFICATIONS (lecture seule, rien n'est modifié) + raccourcis vers le bon réglage
G-Fin $gO; $gO.Y += 12; Section $pO $gO.Y "VÉRIFICATIONS (RIEN N'EST MODIFIÉ)"; $gO.Y += 32
$script:verifs = [ordered]@{}
function Ligne-Verif($cle, $glyphe, $titre, $desc, $bouton, $action) {
  $o = LigneOption $pO $gO.Y $glyphe $titre $desc
  $b = Bouton $o.Carte $bouton 756 13 148 36
  $b.Tag = $action; $b.Add_Click({ try { & $this.Tag } catch { Log "$($_.Exception.Message)" } })
  foreach ($el in $o.Elements) { $el.Tag = $action; $el.Add_Click({ try { & $this.Tag } catch {} }) }
  $o.Bouton = $b; $script:verifs[$cle] = $o; $gO.Y += 70
}
function Ouvrir-Reglage($uri) { try { Start-Process $uri; Log ((T "Ouverture") + " : $uri") } catch { Log "$uri : $($_.Exception.Message)" } }
Ligne-Verif "ecran" 0xE770 "Fréquence de l'écran" "Lecture..." "Ouvrir" { Ouvrir-Reglage "ms-settings:display-advanced" }
Ligne-Verif "rebar" 0xE950 "Resizable BAR / Smart Access Memory" "Lecture..." "Guide BIOS" { Afficher "bios" }
Ligne-Verif "antilag" 0xE945 "Radeon Anti-Lag" "Lecture..." "Explications" {
  $exe = Join-Path $env:ProgramFiles "AMD\CNext\CNext\RadeonSoftware.exe"
  if (Test-Path $exe) { Ouvrir-Reglage $exe } else { Ouvrir-Reglage "https://www.amd.com/en/resources/support-articles/faqs/DH3-033.html" }
}
Ligne-Verif "ndd" 0xE7BA "Ne pas déranger en jeu" "Notifications coupées automatiquement quand un jeu est en plein écran." "Ouvrir" { Ouvrir-Reglage "ms-settings:notifications" }
Ligne-Verif "index" 0xE721 "Indexation de la recherche" "Exclure tes dossiers de jeux de l'indexation évite des lectures disque inutiles." "Ouvrir" { Ouvrir-Reglage "ms-settings:cortana-windowssearch" }
Ligne-Verif "anim" 0xE74D "Effets d'animation de Windows" "Lecture..." "Ouvrir" { Ouvrir-Reglage "ms-settings:easeofaccess-visualeffects" }
# Outil Windows (pas un réglage) : Nettoyage de disque
$oCleanmgr = LigneOption $pN $gN.Y 0xEA99 "Nettoyage de disque Windows" "Ouvre l'outil Windows pour vider la corbeille, les anciennes mises à jour, etc."
foreach ($el in $oCleanmgr.Elements) { $el.Add_Click({ Start-Process cleanmgr }) }

# ===================== PERFORMANCE > SESSION DE JEU (v5.7) =====================
# Ferme des applis d'arrière-plan pendant qu'on joue, puis les relance. Rien n'est désinstallé, aucun
# service ni réglage Windows n'est touché. L'état est noté dans un fichier : si le PC redémarre ou si
# l'appli est fermée pendant la session, la fin de session est proposée au prochain lancement.
$fichierSession = Join-Path $env:ProgramData "Lukzyr\session-jeu.json"
$candidatsSession = @(
  @{ Cle = "onedrive"; Nom = "OneDrive"; Desc = "Synchro des fichiers (reprend où elle en était)."; Proc = @("OneDrive"); Def = $true; Relancer = $true },
  @{ Cle = "teams"; Nom = "Microsoft Teams"; Desc = "Messagerie Microsoft."; Proc = @("ms-teams", "Teams"); Def = $true; Relancer = $true },
  @{ Cle = "widgets"; Nom = "Widgets Windows"; Desc = "Météo et actus (Windows le relance tout seul si besoin)."; Proc = @("Widgets", "WidgetService"); Def = $true; Relancer = $false },
  @{ Cle = "phonelink"; Nom = "Lien avec le téléphone"; Desc = "Synchro avec ton téléphone."; Proc = @("PhoneExperienceHost"); Def = $true; Relancer = $false },
  @{ Cle = "adobe"; Nom = "Adobe Creative Cloud"; Desc = "Mises à jour et synchro Adobe."; Proc = @("Creative Cloud", "CCXProcess", "AdobeIPCBroker", "CoreSync"); Def = $true; Relancer = $true; Principal = "Creative Cloud" },
  @{ Cle = "spotify"; Nom = "Spotify"; Desc = "Laisse décoché si tu écoutes de la musique en jouant."; Proc = @("Spotify"); Def = $false; Relancer = $true },
  @{ Cle = "discord"; Nom = "Discord"; Desc = "Laisse décoché si tu es en vocal."; Proc = @("Discord"); Def = $false; Relancer = $true },
  @{ Cle = "epic"; Nom = "Epic Games Launcher"; Desc = "Ne coche pas si ton jeu passe par Epic."; Proc = @("EpicGamesLauncher"); Def = $false; Relancer = $true },
  @{ Cle = "ea"; Nom = "EA app"; Desc = "Ne coche pas si ton jeu passe par EA."; Proc = @("EADesktop"); Def = $false; Relancer = $true },
  @{ Cle = "ubisoft"; Nom = "Ubisoft Connect"; Desc = "Ne coche pas si ton jeu passe par Ubisoft."; Proc = @("upc", "UbisoftConnect"); Def = $false; Relancer = $true; Principal = "upc" },
  @{ Cle = "battlenet"; Nom = "Battle.net"; Desc = "Ne coche pas si ton jeu passe par Battle.net."; Proc = @("Battle.net"); Def = $false; Relancer = $true },
  @{ Cle = "rgb"; Nom = "Logiciels RGB (iCUE, G HUB, Razer)"; Desc = "Les lumières peuvent rester figées pendant la session."; Proc = @("iCUE", "lghub", "lghub_agent", "RazerAppEngine", "Razer Synapse 3"); Def = $false; Relancer = $true }
)
$sessionUi = [Diagnostics.Process]::GetCurrentProcess().SessionId
$planHaut = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
function Plan-Actif { $o = "$(& powercfg.exe /getactivescheme 2>$null)"; if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $matches[1].ToLower() }; return $null }
function Session-Active { Test-Path -LiteralPath $fichierSession }
function Lire-Session { try { Get-Content -LiteralPath $fichierSession -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } }
function Procs-Candidat($cd) { @(Get-Process -Name $cd.Proc -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID -and $_.SessionId -eq $sessionUi }) }

$pSe = NouvellePage "session" "Session de jeu" "Ferme les applis inutiles pendant que tu joues, puis les relance. Rien n'est désinstallé ni modifié dans Windows." -Defile
$cSe = New-Object LkCard; $cSe.Fill = $cCarte; $cSe.Radius = S 12; $cSe.Location = Pt 0 0; $cSe.Size = Sz 920 92
[void](Icone $cSe "gamepad" 16 22 48 48 26 $cAccentClair $cCarte -Puce $cAccent)
$lSeT = Lbl $cSe "Aucune session en cours" 80 18 590 24 (Police 15 "Bold") $cBlanc $cCarte
$lSeD = Lbl $cSe "Coche les applis à fermer, puis Démarrer. À la fin, tout est relancé." 80 46 590 36 (Police 12) $cGris $cCarte
$bSe = Bouton $cSe "Démarrer la session" 690 24 214 44 -Principal; $bSe.Icon = "play"
$pSe.Controls.Add($cSe)
$ySe = 104
$swSePlan = Ligne $pSe $ySe "Plan Performances élevées pendant la session" $(if ($portable) { "Désactivé sur PC portable (autonomie)." } else { "Ton plan d'alimentation actuel est remis à la fin de la session." }) (-not $portable) $null "session-plan" -Hors
if ($portable) { $swSePlan.Checked = $false; $swSePlan.Enabled = $false }
$ySe += 70
Section $pSe $ySe "APPLIS À FERMER (RELANCÉES À LA FIN)"; $ySe += 32
$choixSe = "$($prefs.SessionApps)"
$swSession = [ordered]@{}
foreach ($cd in $candidatsSession) {
  $on = if ($choixSe) { @($choixSe -split ',') -contains $cd.Cle } else { [bool]$cd.Def }
  $sw = Ligne $pSe $ySe $cd.Nom $cd.Desc $on $null "session" -Hors
  $sw.Tag.Session = $cd; $swSession[$cd.Cle] = $sw
  $sw.Add_CheckedChanged({ if (-not $script:silencieux) { Enregistrer-Pref "SessionApps" ((@($swSession.Keys | Where-Object { $swSession[$_].Checked }) + "-") -join ",") } })
  $ySe += 70
}
[void](Lbl $pSe "Jamais fermés : Windows, l'antivirus, les pilotes, ton jeu et tout ce qui n'est pas coché. Une appli fermée perd ce qui n'était pas enregistré : enregistre avant de démarrer." 4 $ySe 900 36 (Police 11.5) $cGris $cFond)

function Maj-Session {
  $actif = Session-Active
  if ($actif) {
    $e = Lire-Session; $deb = $null; try { $deb = [datetime]"$($e.Debut)" } catch {}
    $lSeT.Text = (T "Session de jeu en cours") + $(if ($deb) { " · " + ((T "depuis {0}") -f $deb.ToString("HH:mm")) } else { "" })
    $det = @()
    if (@($e.Apps).Count) { $det += (T "Fermées") + " : " + (@($e.Apps) -join ", ") } else { $det += T "Aucune appli fermée." }
    if ($e.Plan) { $det += T "Plan Performances élevées actif." }
    $lSeD.Text = ($det -join "  ·  ")
    $bSe.Text = T "Terminer la session"; $bSe.Icon = "check"; $bSe.Fill = $cOrange; $bSe.Fill2 = [Drawing.Color]::Empty; $bSe.HoverFill = [LkAnim]::Mix($cOrange, [Drawing.Color]::Black, 0.12)
    $rapides["session"].Text = T "Session en cours"
  } else {
    $lSeT.Text = T "Aucune session en cours"
    $lSeD.Text = T "Coche les applis à fermer, puis Démarrer. À la fin, tout est relancé."
    $bSe.Text = T "Démarrer la session"; $bSe.Icon = "play"; $bSe.Fill = $cAccent; $bSe.Fill2 = $cAccent2; $bSe.HoverFill = Hex "#7a40ee"
    $rapides["session"].Text = T "Ferme les applis en jeu"
  }
  $bSe.Invalidate()
  foreach ($sw in $swSession.Values) {
    $cd = $sw.Tag.Session; $ouv = (Procs-Candidat $cd).Count -gt 0
    foreach ($el in $sw.Parent.Controls) { if ($el -is [Windows.Forms.Label] -and $el.Top -gt (S 28)) { $el.Text = (T $cd.Desc) + "  ·  " + $(if ($ouv) { T "ouverte" } else { T "pas lancée" }) } }
    $sw.Enabled = -not $actif
  }
  $swSePlan.Enabled = (-not $actif) -and -not $portable
}
function Demarrer-Session {
  if ($script:enCours) { [void](Boite (T "Attends la fin de l'opération en cours.")); return }
  if (Session-Active) { Terminer-Session; return }
  $procs = @(); $relancer = @(); $noms = @()
  foreach ($sw in $swSession.Values) {
    if (-not $sw.Checked) { continue }
    $cd = $sw.Tag.Session; $l = Procs-Candidat $cd
    if (-not $l.Count) { continue }
    $noms += (T $cd.Nom); $procs += $l
    if ($cd.Relancer) {
      $princ = if ($cd.Principal) { $cd.Principal } else { $null }
      foreach ($p in $l) {
        if ($princ -and $p.ProcessName -ne $princ) { continue }
        $ch = $null; try { $ch = $p.Path } catch {}
        if ($ch -and (Test-Path -LiteralPath $ch) -and $relancer -notcontains $ch) { $relancer += $ch }
        break
      }
    }
  }
  $ancienPlan = $null
  if ($swSePlan.Checked -and -not $portable) {
    $actuel = Plan-Actif
    if ($actuel -and $actuel -ne $planHaut -and "$(& powercfg.exe /list 2>$null)" -match $planHaut) { $ancienPlan = $actuel }
  }
  if (-not $procs.Count -and -not $ancienPlan) { [void](Boite (T "Aucune des applis cochées n'est ouverte et le plan d'alimentation est déjà le bon : rien à faire.")); Maj-Session; return }
  # l'état est écrit AVANT de toucher à quoi que ce soit (reprise possible même après un plantage)
  try {
    $dosS = Split-Path $fichierSession; if (-not (Test-Path -LiteralPath $dosS)) { [void](New-Item -ItemType Directory -Path $dosS -Force) }
    $etat = [ordered]@{ Debut = (Get-Date -Format s); Plan = $ancienPlan; Relancer = @($relancer); Apps = @($noms) }
    [IO.File]::WriteAllText($fichierSession, ($etat | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
  } catch { [void](Boite ((T "Session de jeu impossible") + " : $($_.Exception.Message)") "OK" "Error"); return }
  if ($ancienPlan) { & powercfg.exe /setactive $planHaut 2>$null | Out-Null }
  $ids = @($procs | ForEach-Object { $_.Id })
  Log ((T "Session de jeu démarrée") + " : " + $(if ($noms.Count) { $noms -join ", " } else { T "aucune appli fermée" }) + $(if ($ancienPlan) { " · " + (T "plan Performances élevées") } else { "" }))
  # fermeture propre (fenêtre) puis forcée après 1,5 s, en arrière-plan
  En-Fond "session-jeu" {
    foreach ($i in $ids) { try { $p = [Diagnostics.Process]::GetProcessById($i); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() } } catch {} }
    Start-Sleep -Milliseconds 1500
    $n = 0
    foreach ($i in $ids) { try { $p = [Diagnostics.Process]::GetProcessById($i); if (-not $p.HasExited) { $p.Kill(); $n++ } } catch {} }
    $n
  } @{ ids = $ids } { param($r) Maj-Session }
  Maj-Session
}
function Terminer-Session {
  $e = Lire-Session
  if ($e -and "$($e.Plan)" -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { & powercfg.exe /setactive "$($e.Plan)" 2>$null | Out-Null }
  $n = 0
  foreach ($ch in @($e.Relancer)) {
    if (-not $ch -or -not (Test-Path -LiteralPath "$ch")) { continue }
    if (@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension("$ch")) -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionUi }).Count) { continue }
    # relancée par l'Explorateur : avec les droits normaux de l'utilisateur (pas en administrateur)
    try { [void][Diagnostics.Process]::Start((Join-Path $env:WINDIR "explorer.exe"), "`"$ch`""); $n++ } catch {}
  }
  Remove-Item -LiteralPath $fichierSession -Force -ErrorAction SilentlyContinue
  Log ((T "Session de jeu terminée : {0} appli(s) relancée(s)") -f $n + $(if ($e.Plan) { ", " + (T "plan d'alimentation remis") } else { "" }) + ".")
  Maj-Session
}
$bSe.Add_Click({ Demarrer-Session })

# Profils en un clic (Tableau de bord) : règlent les interrupteurs, modifiables ensuite
$profils = [ordered]@{
  gaming    = @{ Nom = "Gaming max"; On = @("debloat","telemetrie","copilot","optim:Alimentation","optim:ModeJeu","optim:PlanifGPU","optim:PrioriteJeux","optim:Souris","optim:VBS","optim:TRIM","optim:NettoyageTemp","optim:Hibernation","optim:AssistantStockage","optim:JeuxFenetres","optim:VRR","optim:DelaiDemarrage","optim:EdgeArrierePlan","optim:Transparence","optim:OptimDistribution") }
  equilibre = @{ Nom = "Équilibré"; On = @("debloat","telemetrie","optim:ModeJeu","optim:PlanifGPU","optim:PrioriteJeux","optim:Souris","optim:TRIM","optim:NettoyageTemp","optim:AssistantStockage","optim:OptimDistribution","optim:JeuxFenetres","optim:VRR","optim:DelaiDemarrage","optim:EdgeArrierePlan","optim:PlanEquilibre") }
  portable  = @{ Nom = "PC portable"; On = @("debloat","telemetrie","optim:ModeJeu","optim:PlanifGPU","optim:TRIM","optim:NettoyageTemp","optim:AssistantStockage","optim:Transparence","optim:OptimDistribution","optim:JeuxFenetres","optim:EdgeArrierePlan","optim:PlanEquilibre") }
}
$cles = @("debloat","telemetrie","copilot") + @($optims | ForEach-Object { "optim:$($_[0])" })
$script:profilChoisi = $null
function Choisir-Profil($k) {
  if ($script:enCours) { return }
  $script:profilChoisi = $k
  $on = $profils[$k].On
  $script:silencieux = $true
  try { foreach ($sw in $toggles) { if ($cles -contains $sw.Tag.Cle) { $sw.Checked = ($on -contains $sw.Tag.Cle) } } } finally { $script:silencieux = $false }
  foreach ($kk in $pillules.Keys) { $pillules[$kk].Selected = ($kk -eq $k); $pillules[$kk].Invalidate() }
  Log "Profil « $(T $profils[$k].Nom) » sélectionné (modifiable avant d'appliquer)."
}

# ===================== LECTURES EN ARRIÈRE-PLAN (v5.1) =====================
# Les lectures lentes du système (applis au démarrage, tâches planifiées, santé des disques)
# tournent dans un runspace séparé : la fenêtre ne gèle plus. Le résultat revient sur le fil
# de l'interface via un minuteur (aucun contrôle n'est touché depuis l'arrière-plan).
$script:fonds = New-Object System.Collections.ArrayList
$tFond = New-Object Windows.Forms.Timer; $tFond.Interval = 120
$tFond.Add_Tick({
  foreach ($j in @($script:fonds)) {
    if (-not $j.H.IsCompleted) { continue }
    [void]$script:fonds.Remove($j)
    $res = $null
    try { $res = $j.PS.EndInvoke($j.H); if ($res.Count -eq 1) { $res = $res[0] } elseif ($res.Count -eq 0) { $res = $null } } catch { Log ((T "Lecture en arrière-plan impossible") + " ($($j.Nom)) : $($_.Exception.InnerException.Message)$($_.Exception.Message)") }
    try { $j.PS.Runspace.Close(); $j.PS.Dispose() } catch {}
    try { & $j.Fin $res } catch { Log ((T "Erreur d'affichage") + " ($($j.Nom)) : $($_.Exception.Message)") }
  }
  if (-not $script:fonds.Count) { $tFond.Stop() }
})
function En-Fond($nom, $code, $vars, $fin) {
  try {
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = "STA"; $rs.Open()
    foreach ($k in $vars.Keys) { $rs.SessionStateProxy.SetVariable($k, $vars[$k]) }
    $pw = [powershell]::Create(); $pw.Runspace = $rs; [void]$pw.AddScript($code)
    [void]$script:fonds.Add(@{ Nom = $nom; PS = $pw; H = $pw.BeginInvoke(); Fin = $fin }); $tFond.Start()
  } catch {
    Log ((T "Lecture en arrière-plan impossible") + " ($nom) : $($_.Exception.Message)")
    try { & $fin $null } catch {}
  }
}
# Petit message « lecture en cours » au début d'une page
# v5.5 : contenu des VÉRIFICATIONS (page Performance), lu au 1er affichage de la page
function Verif-Texte($cle, $texte, $couleur = $null) {
  $o = $script:verifs[$cle]; if (-not $o) { return }
  $o.Desc.Text = (T $texte); $o.Desc.ForeColor = if ($couleur) { $couleur } else { $cGris }
}
function Lancer-Verifs {
  $fr = [LkNative]::Frequences()
  if ($fr[0] -le 1) { Verif-Texte "ecran" "Fréquence impossible à lire sur ce PC." }
  elseif ($fr[1] -gt $fr[0]) { Verif-Texte "ecran" ((T "Réglée à {0} Hz alors que l'écran accepte {1} Hz : à changer.") -f $fr[0], $fr[1]) $cOrange }
  else { Verif-Texte "ecran" ((T "Réglée à {0} Hz, le maximum proposé (rien à faire).") -f $fr[0]) $cVert }
  if ([LkNative]::SystemAnimations()) { Verif-Texte "anim" "Activés. Les couper rend Windows plus vif sur un PC lent." }
  else { Verif-Texte "anim" "Coupés (l'appli n'anime rien non plus)." }
  $exeAmd = Test-Path (Join-Path $env:ProgramFiles "AMD\CNext\CNext\RadeonSoftware.exe")
  if ($exeAmd) { $script:verifs["antilag"].Bouton.Text = (T "Ouvrir Adrenalin") }
  En-Fond "gpu-rebar" {
    $vc = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { "$($_.PNPDeviceID)" -match 'VEN_(1002|10DE|8086)' })
    $vc = @($vc | Sort-Object { if ("$($_.PNPDeviceID)" -match 'VEN_8086') { 1 } else { 0 } })
    if (-not $vc.Count) { return @{ Gpu = ""; Amd = $false; Max = -1 } }
    $g = $vc[0]; $max = -1
    try {
      $pe = Get-CimInstance Win32_PnPEntity -Filter ("DeviceID='" + ("$($g.PNPDeviceID)" -replace '\\', '\\') + "'") -ErrorAction Stop
      foreach ($m in @(Get-CimAssociatedInstance -InputObject $pe -ResultClassName Win32_DeviceMemoryAddress -ErrorAction Stop)) {
        $t = [int64]$m.EndingAddress - [int64]$m.StartingAddress + 1; if ($t -gt $max) { $max = $t }
      }
    } catch { $max = -1 }
    return @{ Gpu = "$($g.Name)"; Amd = ("$($g.PNPDeviceID)" -match 'VEN_1002'); Integre = ("$($g.PNPDeviceID)" -match 'VEN_8086'); Max = $max }
  } @{} {
    param($r)
    if (-not $r -or -not $r.Gpu) {
      Verif-Texte "rebar" "Pas de carte graphique AMD ou NVIDIA détectée : sans objet."
      Verif-Texte "antilag" "Carte graphique AMD non détectée : sans objet."
      return
    }
    if ($r.Integre) { Verif-Texte "rebar" "Seule une puce graphique intégrée est détectée : sans objet." }
    elseif ($r.Max -ge 1GB) { Verif-Texte "rebar" ((T "Activé : la carte voit toute sa mémoire ({0} Go).") -f [math]::Round($r.Max / 1GB)) $cVert }
    elseif ($r.Max -gt 0 -and $r.Max -le 256MB) { Verif-Texte "rebar" "Probablement désactivé : active Above 4G Decoding et Re-Size BAR dans le BIOS." $cOrange }
    else { Verif-Texte "rebar" "Impossible à vérifier sur ce PC (Adrenalin l'indique dans Système)." }
    if ($r.Amd) { Verif-Texte "antilag" "Moins de latence souris : Adrenalin > Jeux > Graphismes > Radeon Anti-Lag." }
    else { Verif-Texte "antilag" "Carte graphique AMD non détectée : sans objet." }
    Log ((T "Vérifications : carte graphique") + " $($r.Gpu), BAR max $(if ($r.Max -gt 0) { [math]::Round($r.Max / 1MB) } else { '?' }) Mo.")
  }
}
function Chargement($pg, $texte) {
  Vider $pg
  $l = Lbl $pg $texte 4 6 700 22 (Police 13 "Bold") $cGris $cFond
  $pb = New-Object LkBar; $pb.Location = Pt 4 36; $pb.Size = Sz 300 4; $pb.Track = $cPiste; $pb.Fill = $cAccent; $pg.Controls.Add($pb); $pb.Busy = $true
  return $l
}

# ===================== SYSTÈME > DÉMARRAGE =====================
# Applis lancées avec Windows : clés Run (HKCU / HKLM / 32 bits) et dossiers Démarrage.
# Activer / désactiver se fait comme le Gestionnaire des tâches (StartupApproved : 02 = actif, 03 = désactivé),
# donc réversible à tout moment. Les logiciels de sécurité ne sont jamais modifiables.
$appr = "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"
$sourcesDemarrage = @(
  @{ Type = "Run"; Cle = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"; App = "HKCU\$appr\Run"; Ou = "Utilisateur" },
  @{ Type = "Run"; Cle = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; App = "HKLM\$appr\Run"; Ou = "Tous les utilisateurs" },
  @{ Type = "Run"; Cle = "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; App = "HKLM\$appr\Run32"; Ou = "Tous les utilisateurs (32 bits)" },
  @{ Type = "Dossier"; Cle = [Environment]::GetFolderPath("Startup"); App = "HKCU\$appr\StartupFolder"; Ou = "Dossier Démarrage" },
  @{ Type = "Dossier"; Cle = [Environment]::GetFolderPath("CommonStartup"); App = "HKLM\$appr\StartupFolder"; Ou = "Dossier Démarrage (tous)" }
)
$regexSecurite = 'SecurityHealth|Windows Defender|MsMpEng|MSASCui|WindowsDefender|avast|\bavg|kaspersky|bitdefender|norton|mcafee|\beset\b|egui|malwarebytes|sophos|trend ?micro|avira|webroot|panda|f-secure|comodo'
$regexLourd = 'steam|discord|epic|onedrive|teams|spotify|adobe|creative ?cloud|origin|eadesktop|ea app|battle\.net|ubisoft|riot|skype|dropbox|googledrive|icloud|nvidia|razer|corsair|g ?hub|lghub|armoury|opera|msedge|chrome|brave'
function Exe-Depuis {
  param($cmd)
  $c = [Environment]::ExpandEnvironmentVariables("$cmd").Trim()
  if ($c -match '^"([^"]+)"') { return $matches[1] }
  if ($c -match '^(.+?\.exe)\b') { return $matches[1] }
  return ($c -split ' ')[0]
}
function Lire-Demarrage {
  $liste = @()
  foreach ($src in $sourcesDemarrage) {
    $elems = @()
    if ($src.Type -eq "Run") {
      $k = Ouvrir-Cle $src.Cle $false $false
      if ($k) { try { foreach ($n in $k.GetValueNames()) { if ($n) { $elems += @{ Nom = $n; Cmd = "$($k.GetValue($n))" } } } } finally { $k.Close() } }
    } elseif ($src.Cle -and (Test-Path $src.Cle)) {
      foreach ($fi in Get-ChildItem $src.Cle -File | Where-Object { $_.Name -ne "desktop.ini" }) {
        $cible = $fi.FullName
        if ($fi.Extension -eq ".lnk") { try { $cible = (New-Object -ComObject WScript.Shell).CreateShortcut($fi.FullName).TargetPath } catch {} }
        $elems += @{ Nom = $fi.Name; Cmd = $cible }
      }
    }
    foreach ($e in $elems) {
      $exe = Exe-Depuis $e.Cmd
      $editeur = ""; $taille = 0
      if ($exe -and (Test-Path $exe)) { $vi = (Get-Item $exe).VersionInfo; $editeur = "$($vi.CompanyName)".Trim(); $taille = (Get-Item $exe).Length }
      $etat = Lire-ValeurReg "$($src.App)|$($e.Nom)"
      $actif = $true
      if ($etat.Existe -and $etat.Type -eq "Binary") { $b = [Convert]::FromBase64String($etat.Valeur); if ($b.Length -and ($b[0] -band 1)) { $actif = $false } }
      $txt = "$($e.Nom) $($e.Cmd) $editeur"
      $impact = if ($txt -match $regexLourd) { "élevé" } elseif ($taille -gt 20MB) { "moyen" } else { "faible" }
      $liste += [pscustomobject]@{ Nom = $e.Nom; Cmd = $e.Cmd; Editeur = $editeur; Ou = $src.Ou; App = $src.App; Actif = $actif; Impact = $impact; Protege = ($txt -match $regexSecurite) }
    }
  }
  return $liste
}
function Basculer-Demarrage($el, [bool]$actif) {
  $id = "$($el.App)|$($el.Nom)"
  [void](Retenir-Registre @($id))   # original gardé pour « Tout annuler »
  $b = New-Object byte[] 12
  if ($actif) { $b[0] = 2 } else { $b[0] = 3; [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($b, 4) }
  Ecrire-ValeurReg $id ([pscustomobject]@{ Existe = $true; Type = "Binary"; Valeur = [Convert]::ToBase64String($b) })
  Log "Démarrage : « $($el.Nom) » $(if ($actif) { 'activé' } else { 'désactivé' })."
}
# Code exécuté en arrière-plan : liste des applis au démarrage + tâches planifiées tierces
$codeDemarrage = @"
. "`$cheminSauvegarde"
function Exe-Depuis {
$(${function:Exe-Depuis})
}
function Lire-Demarrage {
$(${function:Lire-Demarrage})
}
`$liste = @(Lire-Demarrage)
`$taches = @()
if (`$avecTaches) { try { `$taches = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { `$_.TaskPath -notlike "\Microsoft\*" -and `$_.State -ne "Disabled" -and @(`$_.Triggers | Where-Object { `$_.CimClass.CimClassName -match "Logon|Boot" }).Count } | ForEach-Object { "`$(`$_.TaskName)  (`$(`$_.TaskPath.Trim('\')))" }) } catch {} }
@{ Liste = `$liste; Taches = `$taches }
"@
function Vars-Demarrage([bool]$taches) { @{ cheminSauvegarde = (Join-Path $dir "Sauvegarde-Reglages.ps1"); sourcesDemarrage = $sourcesDemarrage; regexSecurite = $regexSecurite; regexLourd = $regexLourd; avecTaches = $taches } }
function Construire-Demarrage {
  if ($script:lectureDem) { return }
  $script:lectureDem = $true
  [void](Chargement $pDem (T "Lecture des applis lancées avec Windows..."))
  En-Fond "demarrage" $codeDemarrage (Vars-Demarrage $true) { param($r) $script:lectureDem = $false; Remplir-Demarrage $r }
}
function Remplir-Demarrage($r) {
  $pg = $pDem; Geler $pages["demarrage"].Panel $true
  try { Remplir-Demarrage2 $r } finally { Geler $pages["demarrage"].Panel $false }
}
function Remplir-Demarrage2($r) {
  $pg = $pDem; Vider $pg
  if (-not $r) { [void](Lbl $pg "La liste des applis au démarrage n'a pas pu être lue (voir le Journal)." 2 0 800 20 (Police 13) $cOrange $cFond); $pages["demarrage"].Construite = $false; return }
  # v5.7 : triées par impact (élevé d'abord), badge d'impact, résumé en haut
  $rang = @{ "élevé" = 0; "moyen" = 1; "faible" = 2 }
  $script:demarrage = @($r.Liste | Sort-Object @{ e = { if ($_.Protege) { 3 } elseif ($rang.ContainsKey("$($_.Impact)")) { $rang["$($_.Impact)"] } else { 2 } } }, @{ e = { -not $_.Actif } }, @{ e = { "$($_.Nom)" } })
  $y = 0
  if (-not $script:demarrage.Count) { [void](Lbl $pg "Aucune appli au démarrage trouvée." 2 0 600 20 (Police 13) $cGris $cFond); $y = 30 }
  else {
    $nAct = @($script:demarrage | Where-Object { $_.Actif }).Count
    $nHaut = @($script:demarrage | Where-Object { $_.Actif -and -not $_.Protege -and "$($_.Impact)" -eq "élevé" }).Count
    $cR = New-Object LkCard; $cR.Fill = $cCarte; $cR.Radius = S 12; $cR.Location = Pt 0 0; $cR.Size = Sz 920 56
    [void](Icone $cR $(if ($nHaut) { "zap" } else { "check-circle" }) 14 12 32 32 18 $(if ($nHaut) { $cOrange } else { $cVert }) $cCarte)
    [void](Lbl $cR ((T "{0} applis au démarrage, {1} actives.") -f $script:demarrage.Count, $nAct) 56 8 840 20 (Police 13.5 "Bold") $cBlanc $cCarte)
    $txtR = if ($nHaut) { (T "{0} à fort impact encore active(s) : désactive celles dont tu n'as pas besoin dès l'allumage.") -f $nHaut } else { T "Aucune appli à fort impact active : ton démarrage est propre." }
    [void](Lbl $cR $txtR 56 29 840 18 (Police 12) $cGris $cCarte)
    $pg.Controls.Add($cR); $y = 68
  }
  foreach ($el in $script:demarrage) {
    $bImp = switch ("$($el.Impact)") { "élevé" { "hi" } "moyen" { "mo" } default { "lo" } }
    $desc = "$(if ($el.Editeur) { $el.Editeur } else { T 'Éditeur inconnu' }) · $(T $el.Ou)"
    if ($el.Protege) {
      # v5.6 : état RÉEL affiché (avant : toujours « actif »), mais jamais modifiable
      $sw = Ligne $pg $y $el.Nom ("$desc · " + (T "Logiciel de sécurité : non modifiable")) $el.Actif $cVert "demarrage" -Hors
      $sw.Enabled = $false
    } else {
      $sw = Ligne $pg $y $el.Nom $desc $el.Actif $null "demarrage" -Hors -Badge $bImp
      $sw.Tag.Element = $el
      $sw.Add_CheckedChanged({ Basculer-Demarrage $this.Tag.Element $this.Checked })
    }
    $y += 84
  }
  # Tâches planifiées lancées à l'ouverture de session / au démarrage (information seulement)
  $taches = @($r.Taches)
  Section $pg $y "TÂCHES PLANIFIÉES AU DÉMARRAGE (INFORMATION)"; $y += 28
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.Radius = S 12; $c.Location = Pt 0 $y
  $txt = if ($taches.Count) { ($taches | Select-Object -First 12) -join "`n" } else { T "Aucune tâche planifiée tierce au démarrage." }
  $n = [math]::Max(1, [math]::Min(12, $taches.Count))
  $c.Size = Sz 920 (24 + 19 * $n)
  [void](Lbl $c $txt 18 12 890 (19 * $n) (Police 12) $cGris $cCarte)
  $pg.Controls.Add($c)
  $pages["demarrage"].Panel.Recalc()
  Log ((T "Démarrage : {0} appli(s) trouvée(s).") -f $script:demarrage.Count)
}
$pDem = NouvellePage "demarrage" "Démarrage" "Appliqué tout de suite, comme le Gestionnaire des tâches. Annulable avec « Tout annuler »." -Defile -Construire { Construire-Demarrage }

# ===================== SYSTÈME > ESPACE DISQUE (v5.7, lecture seule) =====================
# Mesure ce qui prend de la place (dossiers perso, temporaires, corbeille, jeux Steam, fichiers système,
# AppData). Lecture en arrière-plan, chaque mesure a un temps maximum. RIEN n'est supprimé ni déplacé.
$codeEspace = {
  $l = New-Object System.Collections.ArrayList
  $rapide = [bool]("LkDisk" -as [type])
  function Mesure($p, $ms) {
    if ($rapide) { $ok = $false; $s = [LkDisk]::Size($p, $ms, [ref]$ok); return @([int64]$s, [bool]$ok) }
    $s = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    return @([int64]$s, $true)
  }
  function Ajout($cat, $nom, $ch, $ms, [switch]$Fichier) {
    if (-not $ch -or -not (Test-Path -LiteralPath $ch)) { return }
    if ($Fichier) { try { $s = (Get-Item -LiteralPath $ch -Force -ErrorAction Stop).Length; [void]$l.Add(@{ Cat = $cat; Nom = $nom; Chemin = $ch; Taille = [int64]$s; Complet = $true; Fichier = $true }) } catch {}; return }
    $m = Mesure $ch $ms
    [void]$l.Add(@{ Cat = $cat; Nom = $nom; Chemin = $ch; Taille = $m[0]; Complet = $m[1]; Fichier = $false })
  }
  $tel = $null; try { $tel = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -ErrorAction Stop)."{374DE290-123F-4565-9164-39C4925E467B}" } catch {}
  if (-not $tel) { $tel = Join-Path $env:USERPROFILE "Downloads" }
  Ajout "perso" "Téléchargements" $tel 8000
  Ajout "perso" "Bureau" ([Environment]::GetFolderPath("Desktop")) 6000
  Ajout "perso" "Documents" ([Environment]::GetFolderPath("MyDocuments")) 8000
  Ajout "perso" "Vidéos" ([Environment]::GetFolderPath("MyVideos")) 6000
  Ajout "perso" "Images" ([Environment]::GetFolderPath("MyPictures")) 6000
  Ajout "perso" "Musique" ([Environment]::GetFolderPath("MyMusic")) 4000
  Ajout "temp" "Fichiers temporaires (utilisateur)" $env:TEMP 6000
  Ajout "temp" "Fichiers temporaires (Windows)" (Join-Path $env:WINDIR "Temp") 6000
  Ajout "temp" "Corbeille" (Join-Path $env:SystemDrive '$Recycle.Bin') 6000
  # Steam : bibliothèques lues dans libraryfolders.vdf, plus gros jeux de chaque bibliothèque
  $steam = $null; try { $steam = "$((Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath)" -replace '/', '\' } catch {}
  $biblis = @()
  if ($steam -and (Test-Path -LiteralPath $steam)) {
    $biblis += $steam
    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path -LiteralPath $vdf) { foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) { $biblis += ($m.Groups[1].Value -replace '\\\\', '\') } }
  }
  $vus = @{}
  foreach ($b in $biblis) {
    $com = Join-Path $b "steamapps\common"; $k = $com.ToLower().TrimEnd('\')
    if ($vus[$k] -or -not (Test-Path -LiteralPath $com)) { continue }; $vus[$k] = $true
    if ($rapide) {
      foreach ($ln in [LkDisk]::Top($com, 8, 20000)) { $pp = "$ln".Split('|'); if ($pp.Count -ge 3) { [void]$l.Add(@{ Cat = "steam"; Nom = [IO.Path]::GetFileName($pp[0]); Chemin = $pp[0]; Taille = [int64]$pp[1]; Complet = ($pp[2] -eq "1"); Fichier = $false }) } }
    } else { foreach ($d in @(Get-ChildItem -LiteralPath $com -Directory -ErrorAction SilentlyContinue | Select-Object -First 30)) { Ajout "steam" $d.Name $d.FullName 3000 } }
  }
  foreach ($fs in "hiberfil.sys", "pagefile.sys", "swapfile.sys") { Ajout "systeme" $fs (Join-Path ($env:SystemDrive + "\") $fs) 0 -Fichier }
  if ($rapide) {
    foreach ($ln in [LkDisk]::Top($env:LOCALAPPDATA, 6, 15000)) { $pp = "$ln".Split('|'); if ($pp.Count -ge 3) { [void]$l.Add(@{ Cat = "appdata"; Nom = "AppData\Local\" + [IO.Path]::GetFileName($pp[0]); Chemin = $pp[0]; Taille = [int64]$pp[1]; Complet = ($pp[2] -eq "1"); Fichier = $false }) } }
  }
  ,$l.ToArray()
}
function Taille-Txt([double]$o) {
  if ($o -ge 1GB) { return ("{0:N1} " -f ($o / 1GB)) + $uGo }
  if ($o -ge 1MB) { return ("{0:N0} " -f ($o / 1MB)) + (T "Mo") }
  return ("{0:N0} " -f ($o / 1KB)) + (T "Ko")
}
function Construire-Espace {
  if ($script:lectureEsp) { return }
  $script:lectureEsp = $true
  [void](Chargement $pEsp (T "Mesure de l'espace utilisé (jusqu'à une minute sur un gros disque)..."))
  En-Fond "espace" $codeEspace @{} { param($r) $script:lectureEsp = $false; Geler $pages["espace"].Panel $true; try { Remplir-Espace $r } finally { Geler $pages["espace"].Panel $false } }
}
function Remplir-Espace($r) {
  $pg = $pEsp; Vider $pg
  $liste = @($r | Where-Object { $_ -and $_.Taille -ge 0 })
  # résumé des disques
  $y = 0
  $dsk = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq "Fixed" -and $_.IsReady })
  $cD = New-Object LkCard; $cD.Fill = $cCarte; $cD.Radius = S 12; $cD.Location = Pt 0 0; $cD.Size = Sz 920 (24 + 30 * [math]::Max(1, $dsk.Count))
  $yd = 12
  foreach ($d in $dsk) {
    $pc = [int](100 - 100 * $d.AvailableFreeSpace / [math]::Max(1, $d.TotalSize))
    [void](Icone $cD "drive" 14 $yd 22 22 16 $cAccentClair $cCarte)
    [void](Lbl $cD ("$($d.Name.TrimEnd('\')) " + $(if ($d.VolumeLabel) { $d.VolumeLabel } else { "" })) 44 ($yd + 2) 220 18 (Police 12.5 "Bold") $cBlanc $cCarte)
    $bD = New-Object LkBar; $bD.Location = Pt 270 ($yd + 9); $bD.Size = Sz 400 5; $bD.Fill = $(if ($pc -ge 90) { $cOrange } else { $cAccent }); $bD.Fill2 = $(if ($pc -ge 90) { [Drawing.Color]::Empty } else { $cCyan }); $bD.Track = $cPiste; $bD.Value = $pc; $cD.Controls.Add($bD)
    $lT = Lbl $cD ((Taille-Txt $d.AvailableFreeSpace) + " " + (T "libres sur") + " " + (Taille-Txt $d.TotalSize)) 690 ($yd + 2) 212 18 (Police 12) $cGris $cCarte; $lT.TextAlign = "TopRight"
    $yd += 30
  }
  $pg.Controls.Add($cD); $y = $cD.Height / $sc + 12
  $bRe = Bouton $pg "Mesurer à nouveau" 0 $y 200 36; $bRe.Icon = "refresh"
  $bRe.Add_Click({ $pages["espace"].Construite = $true; Construire-Espace })
  [void](Lbl $pg "Clique sur une ligne pour ouvrir le dossier. Pour faire de la place : Nettoyage > fichiers temporaires, ou désinstalle les jeux que tu n'utilises plus." 216 ($y + 1) 700 34 (Police 11.5) $cGris $cFond)
  $y += 52
  if (-not $liste.Count) { [void](Lbl $pg "Mesure impossible (voir le Journal)." 2 $y 600 20 (Police 13) $cOrange $cFond); $pages["espace"].Panel.Recalc(); return }
  $max = [double](($liste | Measure-Object Taille -Maximum).Maximum); if ($max -le 0) { $max = 1 }
  $cats = [ordered]@{ perso = "DOSSIERS PERSONNELS"; steam = "JEUX STEAM (PLUS GROS)"; temp = "TEMPORAIRES ET CORBEILLE"; appdata = "APPDATA (PLUS GROS DOSSIERS)"; systeme = "FICHIERS SYSTÈME (GÉRÉS PAR WINDOWS, NE PAS SUPPRIMER)" }
  $total = 0
  foreach ($k in $cats.Keys) {
    $els = @($liste | Where-Object { $_.Cat -eq $k -and $_.Taille -gt 0 } | Sort-Object { -$_.Taille })
    if (-not $els.Count) { continue }
    Section $pg $y $cats[$k]; $y += 32
    foreach ($el in $els) {
      $c = New-Object LkCard; $c.Fill = $cCarte; $c.HoverFill = $cCarteSurvol; $c.Radius = S 12; $c.Location = Pt 0 $y; $c.Size = Sz 920 56; $c.Cursor = "Hand"
      $t1 = Lbl $c (T $el.Nom) 18 9 560 20 (Police 13.5 "Bold") $cBlanc $cCarte; $t1.AutoEllipsis = $true
      $t2 = Lbl $c $el.Chemin 18 31 560 18 (Police 11.5) $cGris $cCarte; $t2.AutoEllipsis = $true
      $t3 = Lbl $c ((Taille-Txt $el.Taille) + $(if (-not $el.Complet) { " +" } else { "" })) 620 8 282 22 (Police 14 "Bold") $cBlanc $cCarte; $t3.TextAlign = "TopRight"
      $bb = New-Object LkBar; $bb.Location = Pt 642 38; $bb.Size = Sz 260 5; $bb.Fill = $cAccent; $bb.Fill2 = $cCyan; $bb.Track = $cPiste; $bb.Value = [int][math]::Max(1, 100 * $el.Taille / $max); $c.Controls.Add($bb)
      $aide = $el.Chemin + $(if (-not $el.Complet) { "`n" + (T "Mesure arrêtée avant la fin (dossier énorme ou protégé) : la taille réelle est plus grande.") } else { "" })
      foreach ($x in $c, $t1, $t2, $t3, $bb) {
        $x.Cursor = "Hand"; $x.Tag = $el; $tip.SetToolTip($x, $aide); Survol-Carte $x
        $x.Add_Click({ $e = $this.Tag; if ($e.Fichier) { try { [void][Diagnostics.Process]::Start((Join-Path $env:WINDIR "explorer.exe"), "/select,`"$($e.Chemin)`"") } catch {} } else { Ouvrir-Dossier $e.Chemin } })
      }
      $pg.Controls.Add($c); $y += 64; $total++
    }
    $y += 8
  }
  $pages["espace"].Panel.Recalc()
  Log ((T "Espace disque : {0} élément(s) mesuré(s).") -f $total)
}
$pEsp = NouvellePage "espace" "Espace disque" "Ce qui prend de la place sur tes disques. Lecture seule : rien n'est supprimé ni déplacé." -Defile -Construire { Construire-Espace }

# ===================== SYSTÈME > RÉSEAU =====================
$dnsChoix = [ordered]@{
  auto       = @{ Nom = "Automatique (FAI)"; Srv = @() }
  cloudflare = @{ Nom = "Cloudflare"; Srv = @("1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001") }
  google     = @{ Nom = "Google"; Srv = @("8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844") }
  quad9      = @{ Nom = "Quad9"; Srv = @("9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9") }
}
# Cartes réseau connectées : physiques d'abord ; sinon (cartes virtuelles de VM, certains pilotes)
# les cartes matérielles connectées, en écartant VPN, Hyper-V, VirtualBox, VMware, Bluetooth...
function Cartes-Actives {
  $exclues = 'Hyper-V|VirtualBox|VMware Virtual|TAP-|Wintun|WireGuard|Tailscale|ZeroTier|OpenVPN|Loopback|Bluetooth|Teredo|Npcap|vEthernet'
  $l = @(Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" })
  if (-not $l.Count) { $l = @(Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.HardwareInterface -and "$($_.InterfaceDescription) $($_.Name)" -notmatch $exclues }) }
  return $l
}
function Texte-DnsActuel {
  $l = @()
  foreach ($a in Cartes-Actives) {
    $srv = @(Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex | ForEach-Object { $_.ServerAddresses }) | Where-Object { $_ -and $_ -notmatch '^fec0:' }
    $manuel = "$((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)" -Name NameServer).NameServer)".Trim()
    $l += "$($a.Name) : $(if ($srv) { ($srv | Select-Object -First 4) -join ', ' } else { '-' })  ($(if ($manuel) { T 'manuel' } else { T 'automatique' }))"
  }
  if (-not $l.Count) { return (T "Aucune carte réseau physique connectée.") }
  return ($l -join "`n")
}
$pR = NouvellePage "reseau" "Réseau" "Choisis ton DNS et vide le cache DNS."
$cDns = New-Object LkCard; $cDns.Fill = $cCarte; $cDns.Radius = S 12; $cDns.Location = Pt 0 0; $cDns.Size = Sz 936 96
[void](Lbl $cDns "DNS ACTUEL" 18 12 300 16 (Police 10.5 "Bold") $cAccentClair $cCarte)
$lDns = Lbl $cDns "" 18 34 900 56 (Police 13 "Bold") $cBlanc $cCarte
$pR.Controls.Add($cDns)
$script:dnsSel = "cloudflare"; $boutonsDns = @{}; $xd = 0
foreach ($k in $dnsChoix.Keys) {
  $b = New-Object LkButton; $b.Font = Police 13 "Bold"; $b.Radius = S 10; $b.Location = Pt $xd 110; $b.Size = Sz 172 42
  $b.Text = (T $dnsChoix[$k].Nom); $b.Tag = $k; $b.Add_Click({ Choisir-Dns $this.Tag })
  $pR.Controls.Add($b); $boutonsDns[$k] = $b; $xd += 184
}
$lDnsDet = Lbl $pR "" 2 162 900 20 (Police 12) $cGris $cFond
function Choisir-Dns($k) {
  $script:dnsSel = $k
  foreach ($kk in $boutonsDns.Keys) {
    $b = $boutonsDns[$kk]
    if ($kk -eq $k) { $b.Fill = $cAccent; $b.Fill2 = $cAccent2; $b.HoverFill = Hex "#7a40ee"; $b.ForeColor = [Drawing.Color]::White } else { $b.Fill = $cCarte; $b.Fill2 = [Drawing.Color]::Empty; $b.HoverFill = $cCarteSurvol; $b.ForeColor = $cBlanc }
    $b.Invalidate()
  }
  $lDnsDet.Text = if ($dnsChoix[$k].Srv.Count) { (T "Serveurs") + " : " + ($dnsChoix[$k].Srv -join "  ·  ") } else { T "Les serveurs DNS donnés par ta box / ton fournisseur d'accès (réglage d'origine de Windows)." }
}
$bDnsAppl = New-Object LkButton; $bDnsAppl.Text = (T "Appliquer ce DNS"); $bDnsAppl.Font = Police 13 "Bold"; $bDnsAppl.Radius = S 10
$bDnsAppl.Location = Pt 0 196; $bDnsAppl.Size = Sz 220 42; $bDnsAppl.Fill = $cAccent; $bDnsAppl.Fill2 = $cAccent2; $bDnsAppl.HoverFill = Hex "#7a40ee"
$bDnsCache = New-Object LkButton; $bDnsCache.Text = (T "Vider le cache DNS"); $bDnsCache.Font = Police 13 "Bold"; $bDnsCache.Radius = S 10
$bDnsCache.Location = Pt 232 196; $bDnsCache.Size = Sz 220 42; $bDnsCache.Fill = $cCarte; $bDnsCache.HoverFill = $cCarteSurvol; $bDnsCache.ForeColor = $cBlanc
$pR.Controls.Add($bDnsAppl); $pR.Controls.Add($bDnsCache)
[void](Lbl $pR "Les DNS d'origine sont sauvegardés : « Tout annuler » (Système) les remet. IPv4 et IPv6, cartes réseau physiques connectées." 2 252 900 40 (Police 12) $cGris $cFond)
function Appliquer-Dns($k) {
  $cartes = Cartes-Actives
  if (-not $cartes.Count) { [void](Boite (T "Aucune carte réseau physique connectée.")); return $false }
  Retenir-Dns $cartes
  $srv = $dnsChoix[$k].Srv; $ok = 0
  foreach ($a in $cartes) {
    try {
      if ($srv.Count) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $srv -ErrorAction Stop }
      else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop }
      $ok++
    } catch { Log "DNS : échec sur $($a.Name) : $($_.Exception.Message)" }
  }
  Clear-DnsClientCache
  Log "DNS « $(T $dnsChoix[$k].Nom) » appliqué sur $ok carte(s) réseau."
  Maj-DnsActuel
  return ($ok -gt 0)
}
$bDnsAppl.Add_Click({ [void](Appliquer-Dns $script:dnsSel) })
$bDnsCache.Add_Click({ Clear-DnsClientCache; & ipconfig.exe /flushdns | Out-Null; Log "Cache DNS vidé."; [void](Boite (T "Cache DNS vidé.")) })
# v5.1 : la 1re lecture des cartes réseau peut prendre 30 s (module NetTCPIP) : elle se fait en arrière-plan
$codeDns = [scriptblock]::Create("function Cartes-Actives {`n" + ${function:Cartes-Actives}.ToString() + "`n}`n" + {
  $l = @()
  foreach ($a in Cartes-Actives) {
    $srv = @(Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex | ForEach-Object { $_.ServerAddresses }) | Where-Object { $_ -and $_ -notmatch '^fec0:' }
    $manuel = "$((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)" -Name NameServer -ErrorAction SilentlyContinue).NameServer)".Trim()
    $l += [pscustomobject]@{ Nom = "$($a.Name)"; Srv = (@($srv | Select-Object -First 4) -join ', '); Manuel = [bool]$manuel }
  }
  , $l
}.ToString())
function Maj-DnsActuel {
  if ($script:lectureDns) { return }
  $script:lectureDns = $true; $lDns.Text = (T "Lecture des cartes réseau...")
  En-Fond "dns" $codeDns @{} { param($r)
    $script:lectureDns = $false
    $l = @(foreach ($a in @($r)) { if ($a) { "$($a.Nom) : $(if ($a.Srv) { $a.Srv } else { '-' })  ($(if ($a.Manuel) { T 'manuel' } else { T 'automatique' }))" } })
    $lDns.Text = if ($l.Count) { $l -join "`n" } elseif ($null -eq $r) { T "Lecture en arrière-plan impossible" } else { T "Aucune carte réseau physique connectée." }
  }
}
$pages["reseau"].Construire = { Maj-DnsActuel; Choisir-Dns $script:dnsSel }

# ===================== MATÉRIEL > SANTÉ =====================
function Carte-Sante($pg, $y, $titre, $details, $etat, $couleur, $icone = "") {
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.Radius = S 12; $c.Location = Pt 0 $y; $c.Size = Sz 920 62
  $xT = 18
  if ($icone) { [void](Icone $c $icone 14 13 36 36 19 $couleur $cCarte -Puce $couleur); $xT = 62 }
  [void](Lbl $c $titre $xT 11 470 22 (Police 14 "Bold") $cBlanc $cCarte)
  [void](Lbl $c $details $xT 33 (678 - $xT) 18 (Police 12) $cGris $cCarte)
  $e = Lbl $c $etat 692 11 212 22 (Police 13 "Bold") $couleur $cCarte; $e.TextAlign = "TopRight"
  $pg.Controls.Add($c)
}
# Lecture de la santé en arrière-plan (disques, SMART, volumes, température, mémoire)
$codeSante = {
  $d = @{ Disques = @(); Volumes = @(); Temp = $null; MemTot = 0; MemLib = 0 }
  foreach ($k in @(Get-PhysicalDisk)) {
    $rc = $null; try { $rc = $k | Get-StorageReliabilityCounter -ErrorAction Stop } catch {}
    $d.Disques += [pscustomobject]@{ Nom = "$($k.FriendlyName)"; Media = "$($k.MediaType)"; Taille = $k.Size; Sante = "$($k.HealthStatus)"
      Smart = [bool]$rc; Temp = $rc.Temperature; Usure = $rc.Wear; Heures = $rc.PowerOnHours; Erreurs = $rc.ReadErrorsTotal }
  }
  foreach ($v in @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" -and $_.Size -gt 0 } | Sort-Object DriveLetter)) {
    $d.Volumes += [pscustomobject]@{ Lettre = "$($v.DriveLetter)"; Label = "$($v.FileSystemLabel)"; Libre = $v.SizeRemaining; Taille = $v.Size; FS = "$($v.FileSystem)" }
  }
  # v5.3 : température processeur / carte graphique, par ordre de préférence (lecture seule, aucun pilote installé)
  $d.TempSource = ""; $d.TempGpu = $null; $d.TempGpuSource = ""
  function Plausible($c, [switch]$Acpi) { if ($null -eq $c) { return $false }; $c = [double]$c; if ($c -lt 15 -or $c -gt 115) { return $false }; if ($Acpi -and [math]::Abs($c - 27.8) -lt 0.15) { return $false }; return $true }
  # 1. LibreHardwareMonitor / OpenHardwareMonitor ouverts (WMI : OHM, LHM <= 0.9.4)
  foreach ($ns in "root/LibreHardwareMonitor", "root/OpenHardwareMonitor") {
    if ($d.Temp -and $d.TempGpu) { break }
    try {
      $cap = @(Get-CimInstance -Namespace $ns -ClassName Sensor -Filter "SensorType='Temperature'" -ErrorAction Stop)
      $nomNs = if ($ns -match "Libre") { "LibreHardwareMonitor" } else { "OpenHardwareMonitor" }
      if (-not $d.Temp) {
        $c = $cap | Where-Object { "$($_.Identifier)" -match 'cpu' -and "$($_.Name)" -match 'Tctl|Tdie|CPU Package|Package|Core Average|CPU Cores' } | Sort-Object { if ("$($_.Name)" -match 'Tctl|Tdie|Package') { 0 } else { 1 } } | Select-Object -First 1
        if ($c -and (Plausible $c.Value)) { $d.Temp = [math]::Round([double]$c.Value); $d.TempSource = "$nomNs ($($c.Name))" }
      }
      if (-not $d.TempGpu) {
        # v5.6 : noms de capteurs EXACTS (avant : « Core » trouvait aussi d'autres capteurs), GPU Core en priorité
        $c = $cap | Where-Object { "$($_.Identifier)" -match 'gpu' -and "$($_.Name)" -match '^(GPU Core|GPU Hot ?Spot|Hot ?Spot|GPU Edge|Edge)$' } | Sort-Object { if ("$($_.Name)" -eq 'GPU Core') { 0 } else { 1 } } | Select-Object -First 1
        if ($c -and (Plausible $c.Value)) { $d.TempGpu = [math]::Round([double]$c.Value); $d.TempGpuSource = "$nomNs ($($c.Name))" }
      }
    } catch {}
  }
  # 2. LibreHardwareMonitor >= 0.9.5 : serveur web local (Options > Remote Web Server > Run), http://localhost:8085/data.json
  if ((-not $d.Temp -or -not $d.TempGpu) -and (Get-Process LibreHardwareMonitor -ErrorAction SilentlyContinue)) {
    try {
      $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8
      $js = $wc.DownloadString("http://localhost:8085/data.json") | ConvertFrom-Json
      $feuilles = New-Object System.Collections.ArrayList
      $pile = New-Object System.Collections.Stack; $pile.Push(@($js, ""))
      while ($pile.Count) {
        $e = $pile.Pop(); $n = $e[0]; $chemin = "$($e[1])/$($n.Text)"
        if ($n.Children -and @($n.Children).Count) { foreach ($ch in $n.Children) { $pile.Push(@($ch, $chemin)) } }
        elseif ("$($n.Value)" -match '°C') { [void]$feuilles.Add([pscustomobject]@{ Nom = "$($n.Text)"; Chemin = $chemin; Id = "$($n.SensorId)"; Valeur = [double](("$($n.Value)" -replace '[^\d,\.\-]', '') -replace ',', '.') }) }
      }
      if (-not $d.Temp) {
        $c = $feuilles | Where-Object { ($_.Id -match 'cpu' -or $_.Chemin -match 'Ryzen|Intel|Core i|CPU') -and $_.Nom -match 'Tctl|Tdie|Package|Core Average|CPU Cores' } | Select-Object -First 1
        if ($c -and (Plausible $c.Valeur)) { $d.Temp = [math]::Round($c.Valeur); $d.TempSource = "LibreHardwareMonitor ($($c.Nom))" }
      }
      if (-not $d.TempGpu) {
        $c = $feuilles | Where-Object { ($_.Id -match 'gpu' -or $_.Chemin -match 'Radeon|GeForce|RTX|GTX|Arc') -and $_.Nom -match '^(GPU Core|GPU Hot ?Spot|Hot ?Spot|GPU Edge|Edge)$' } | Sort-Object { if ($_.Nom -eq 'GPU Core') { 0 } else { 1 } } | Select-Object -First 1
        if ($c -and (Plausible $c.Valeur)) { $d.TempGpu = [math]::Round($c.Valeur); $d.TempGpuSource = "LibreHardwareMonitor ($($c.Nom))" }
      }
    } catch { $d.LhmWebKo = $true }
  }
  $d.LhmOuvert = [bool](Get-Process LibreHardwareMonitor, OpenHardwareMonitor -ErrorAction SilentlyContinue)
  # 3. compteurs Windows des zones thermiques (souvent dispo sans WMI ACPI) : dixièmes de Kelvin ou Kelvin
  if (-not $d.Temp) {
    try {
      $z = @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction Stop)
      $vals = foreach ($x in $z) { if ($x.HighPrecisionTemperature) { $x.HighPrecisionTemperature / 10 - 273.15 } elseif ($x.Temperature) { $x.Temperature - 273.15 } }
      $c = @($vals | Where-Object { Plausible $_ -Acpi }) | Measure-Object -Maximum
      if ($c.Count) { $d.Temp = [math]::Round($c.Maximum); $d.TempSource = "Windows (zone thermique)" }
    } catch {}
  }
  # 4. ACPI (root/wmi)
  if (-not $d.Temp) {
    try {
      $z = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)
      $c = @($z | ForEach-Object { $_.CurrentTemperature / 10 - 273.15 } | Where-Object { Plausible $_ -Acpi }) | Measure-Object -Maximum
      if ($c.Count) { $d.Temp = [math]::Round($c.Maximum); $d.TempSource = "ACPI" }
    } catch {}
  }
  $d.CpuAmd = [bool]((Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Manufacturer -match 'AMD')
  try { $o = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $d.MemTot = $o.TotalVisibleMemorySize / 1MB; $d.MemLib = $o.FreePhysicalMemory / 1MB } catch {}
  $d
}
# v5.3 : outil de mesure facultatif (dépôt officiel winget). LuKZyR n'installe aucun pilote lui-même.
function Installer-Lhm {
  if ($script:enCours) { [void](Boite (T "Attends la fin de l'opération en cours.")); return }
  $wgLhm = Chemin-Winget
  if (-not $wgLhm) { [void](Boite (T "winget (App Installer) est introuvable sur ce PC. Installe-le depuis le Microsoft Store, ou télécharge LibreHardwareMonitor sur son site officiel.") "OK" "Warning"); return }
  $msg = (T "LibreHardwareMonitor est un outil gratuit et open source qui lit les capteurs (températures, ventilateurs). Il sera installé depuis le dépôt officiel winget.") + "`n`n" +
         (T "Bon à savoir : il utilise son propre pilote de lecture des capteurs, que certains antivirus (dont Microsoft Defender) peuvent signaler. LuKZyR ne l'installe pas lui-même et ne touche pas à l'antivirus.") + "`n`n" +
         (T "Ensuite : ouvre LibreHardwareMonitor, active Options > Remote Web Server > Run, puis Actualiser dans Santé.") + "`n`n" + (T "Installer maintenant ?")
  if (-not $env:LK_TEST) { if ((Boite $msg "YesNo" "Question") -ne "Yes") { return } }
  Log "Installation de LibreHardwareMonitor (winget)."
  Lancer-Plan @(@{ Nom = "Installation de LibreHardwareMonitor"; Fichier = $wgLhm; Args = "install --id LibreHardwareMonitor.LibreHardwareMonitor --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" }) -Resume @("LibreHardwareMonitor") -Titre "LibreHardwareMonitor" -SansPoint
}
function Construire-Sante {
  if ($script:lectureSante) { return }
  $script:lectureSante = $true
  [void](Chargement $pSante (T "Analyse des disques et de la mémoire..."))
  En-Fond "sante" $codeSante @{} { param($r) $script:lectureSante = $false; Remplir-Sante $r }
}
function Remplir-Sante($r) {
  Geler $pages["sante"].Panel $true
  try { Remplir-Sante2 $r } finally { Geler $pages["sante"].Panel $false }
}
function Remplir-Sante2($r) {
  $pg = $pSante; Vider $pg; $y = 0
  $bMaj = New-Object LkButton; $bMaj.Text = (T "Actualiser"); $bMaj.Font = Police 12 "Bold"; $bMaj.Radius = S 10
  $bMaj.Location = Pt 760 0; $bMaj.Size = Sz 160 34; $bMaj.Fill = $cCarte; $bMaj.HoverFill = $cCarteSurvol; $bMaj.ForeColor = $cBlanc
  $bMaj.Icon = "refresh"; $bMaj.Add_Click({ Construire-Sante }); $pg.Controls.Add($bMaj)
  if (-not $r) { [void](Lbl $pg "L'analyse n'a pas pu être faite (voir le Journal)." 4 6 700 22 (Police 13 "Bold") $cOrange $cFond); return }
  $script:alertes = 0; $y = 40
  Section $pg $y "DISQUES"; $y += 28
  foreach ($k in @($r.Disques)) {
    $det = @("$($k.Media)", "$([math]::Round($k.Taille / 1GB)) $uGo")
    if ($null -ne $k.Temp -and $k.Temp -gt 0) { $det += "$($k.Temp) °C" }
    if ($null -ne $k.Usure) { $det += (T "usure") + " $($k.Usure) %" }
    if ($k.Heures) { $det += "$($k.Heures) h" }
    if ($null -ne $k.Erreurs) { $det += (T "erreurs de lecture") + " : $($k.Erreurs)" }
    if (-not $k.Smart) { $det += (T "compteurs SMART non disponibles") }
    $etat = T "En bonne santé"; $coul = $cVert
    if ($k.Sante -ne "Healthy") { $etat = (T "Problème") + " : $($k.Sante)"; $coul = $cRouge; $script:alertes++ }
    elseif ($null -ne $k.Usure -and $k.Usure -gt 80) { $etat = (T "Usure élevée"); $coul = $cOrange; $script:alertes++ }
    elseif ($k.Temp -gt 60) { $etat = (T "Chaud"); $coul = $cOrange; $script:alertes++ }
    Carte-Sante $pg $y $k.Nom (($det | Where-Object { $_ }) -join " · ") $etat $coul "drive"; $y += 72
  }
  Section $pg $y "ESPACE LIBRE"; $y += 28
  foreach ($v in @($r.Volumes)) {
    $pc = [math]::Round(100 * $v.Libre / $v.Taille)
    $etat = "$pc % " + (T "libre"); $coul = $cVert
    if ($pc -lt 10) { $coul = $cRouge; $script:alertes++ } elseif ($pc -lt 20) { $coul = $cOrange }
    Carte-Sante $pg $y ("$($v.Lettre): $($v.Label)".Trim()) ("$([math]::Round($v.Libre / 1GB)) " + (T "Go libres sur") + " $([math]::Round($v.Taille / 1GB)) $uGo · $($v.FS)") $etat $coul "drive"; $y += 72
  }
  Section $pg $y "PROCESSEUR ET MÉMOIRE"; $y += 28
  $temp = $r.Temp
  if ($temp -and $temp -gt 0 -and $temp -lt 120) {
    $coul = if ($temp -ge 90) { $cRouge } elseif ($temp -ge 80) { $cOrange } else { $cVert }
    if ($temp -ge 80) { $script:alertes++ }
    Carte-Sante $pg $y (T "Température processeur") ((T "Source") + " : " + (T $r.TempSource)) "$temp °C" $coul "cpu"
  } else {
    $expl = if ($r.LhmOuvert) { T "LibreHardwareMonitor ouvert : active Options > Remote Web Server > Run, puis Actualiser." }
            elseif ($r.CpuAmd) { T "Les Ryzen ne donnent pas leur température à Windows : LibreHardwareMonitor peut la lire." }
            else { T "Ce PC ne donne pas sa température à Windows : LibreHardwareMonitor peut la lire." }
    $cs = Carte-Sante $pg $y (T "Température processeur") $expl (T "non disponible") $cGris "cpu"
    if (-not $r.LhmOuvert) {
      $bLhm = Bouton $pg "Installer LibreHardwareMonitor" 600 ($y + 70) 320 34
      $bLhm.Add_Click({ Installer-Lhm }); $y += 44
    }
  }
  $y += 72
  if ($r.TempGpu) {
    $tg = $r.TempGpu; $coul = if ($tg -ge 95) { $cRouge } elseif ($tg -ge 85) { $cOrange } else { $cVert }
    if ($tg -ge 85) { $script:alertes++ }
    Carte-Sante $pg $y (T "Température carte graphique") ((T "Source") + " : " + (T $r.TempGpuSource)) "$tg °C" $coul "monitor"; $y += 72
  }
  if ($r.MemTot -gt 0) {
    $tot = $r.MemTot; $lib = $r.MemLib
    $pcR = [math]::Round(100 * ($tot - $lib) / $tot)
    $coul = if ($pcR -ge 90) { $cOrange } else { $cVert }
    Carte-Sante $pg $y (T "Mémoire vive") (("{0:N1} / {1:N1} $uGo " -f ($tot - $lib), $tot) + (T "utilisés")) "$pcR %" $coul "memory"; $y += 72
  }
  $resume = if ($script:alertes) { "$($script:alertes) " + (T "point(s) à surveiller (en orange / rouge).") } else { T "Tout va bien." }
  $cR = $(if ($script:alertes) { $cOrange } else { $cVert })
  [void](Icone $pg $(if ($script:alertes) { "alert" } else { "check-circle" }) 2 5 24 24 18 $cR $cFond)
  [void](Lbl $pg $resume 30 6 500 22 (Police 13 "Bold") $cR $cFond)
  $pages["sante"].Panel.Recalc()
  Log "Santé du PC analysée : $resume"
}
$pSante = NouvellePage "sante" "Santé" "État des disques, de l'espace libre, de la température et de la mémoire." -Defile -Construire { Construire-Sante }

# ===================== SYSTÈME > RÉPARATION ET SÉCURITÉ =====================
$pSys = NouvellePage "sysoutils" "Système" "Stockage, réparation, sécurité et raccourcis Windows." -Defile
$gS = Grille $pSys
Placer-Optims "sysoutils" $gS
G-Section $gS "SÉCURITÉ"
$yS = $gS.Y
# « Tout annuler » : remet les réglages d'origine sauvegardés avant chaque application
$oAnnuler = LigneOption $pSys $yS 0xE7A7 "Tout annuler" "Remet les réglages d'origine (registre, services, alimentation, DNS, démarrage)." $cOrange
$bAnnuler = Bouton $oAnnuler.Carte "Tout annuler" 756 13 148 36 -Couleur $cOrange
foreach ($el in $oAnnuler.Elements) { $el.Add_Click({ Tout-Annuler }) }
$bAnnuler.Add_Click({ Tout-Annuler })
$yS += 70
[void](Lbl $pSys "Non annulables : applis supprimées (débloat, Copilot, OneDrive) ou installées, Edge désinstallé, fichiers temporaires effacés, réparation DISM/SFC. Pour ça : « Restaurer le système » (point de restauration)." 4 $yS 900 36 (Police 11.5) $cOrange $cFond)
$yS += 44
$outils = @(
  @(0xE777, "Restaurer le système", "Revenir à un point de restauration (créé avant chaque application).", { Start-Process rstrui }),
  @(0xE772, "Gestionnaire de périphériques", "Voir les composants et leurs pilotes.", { Start-Process devmgmt.msc }),
  @(0xE72C, "Redémarrer le PC", "Nécessaire après certaines optimisations.", { if ((Boite (T "Redémarrer maintenant ?") "YesNo" "Question") -eq "Yes") { Restart-Computer -Force } })
)
$actionsOutils = @{}
Section $pSys $yS "RACCOURCIS WINDOWS"; $yS += 30
foreach ($o in $outils) {
  $oo = LigneOption $pSys $yS $o[0] $o[1] $o[2]
  $actionsOutils[$o[1]] = $o[3]
  foreach ($el in $oo.Elements) { $el.Tag = $o[1]; $el.Add_Click({ & $actionsOutils[$this.Tag] }) }
  $yS += 70
}

# ===================== PARAMÈTRES =====================
$pT = NouvellePage "parametres" "Paramètres" "Apparence, langue et mises à jour de LuKZyR Optimisation." -Defile
$yOpt = 0
# Thème clair
$oTheme = LigneOption $pT $yOpt 0xE706 "Thème clair" "Interface claire au lieu de sombre (l'accent violet reste)."
$swTheme = New-Object LkToggle; $swTheme.Size = Sz 44 24; $swTheme.Location = Pt 858 19; $swTheme.Checked = $script:themeClair; $swTheme.OffColor = $cOff
$oTheme.Carte.Controls.Add($swTheme)
$swTheme.Add_CheckedChanged({ Appliquer-Theme $swTheme.Checked })
foreach ($el in $oTheme.Elements) { $el.Add_Click({ $swTheme.Checked = -not $swTheme.Checked }) }
$bTheme.Add_Click({ $swTheme.Checked = -not $swTheme.Checked })
$yOpt += 70
# Langue
$oLangue = LigneOption $pT $yOpt 0xE774 "Langue" "Français ou English (l'interface redémarre)."
$boutonsLangue = @{}; $xl = 756
foreach ($lg in "fr", "en") {
  $b = Bouton $oLangue.Carte $lg.ToUpper() $xl 13 70 36 -Principal:($lg -eq $script:langue)
  $b.Tag = $lg; $b.Add_Click({ Changer-Langue $this.Tag }); $boutonsLangue[$lg] = $b; $xl += 78
}
$yOpt += 70
# Animations
$oAnim = LigneOption $pT $yOpt 0xE768 "Animations" "Transitions et effets de l'interface. Désactive-les sur un PC lent."
$swAnim = New-Object LkToggle; $swAnim.Size = Sz 44 24; $swAnim.Location = Pt 858 19; $swAnim.Checked = $script:animAppli; $swAnim.OffColor = $cOff
$oAnim.Carte.Controls.Add($swAnim)
if (-not $script:animWindows) { $oAnim.Desc.Text = (T "Coupées par Windows (Accessibilité > Effets visuels > Effets d'animation).") }
$swAnim.Add_CheckedChanged({ $script:animAppli = $swAnim.Checked; [LkAnim]::On = $swAnim.Checked -and $script:animWindows; Enregistrer-Animations $swAnim.Checked; $swRed.Enabled = $swAnim.Checked; Log "Animations : $(if ($swAnim.Checked) { 'activées' } else { 'désactivées' })." })
foreach ($el in $oAnim.Elements) { $el.Add_Click({ $swAnim.Checked = -not $swAnim.Checked }) }
$yOpt += 70
# v5.5 : animations réduites (courtes, sans glissement ni pulsation)
$oRed = LigneOption $pT $yOpt 0xE768 "Animations réduites" "Effets plus courts et plus discrets, sans glissement ni pulsation."
$swRed = New-Object LkToggle; $swRed.Size = Sz 44 24; $swRed.Location = Pt 858 19; $swRed.Checked = [LkAnim]::Reduit; $swRed.OffColor = $cOff; $swRed.Enabled = $swAnim.Checked
$oRed.Carte.Controls.Add($swRed)
$swRed.Add_CheckedChanged({ [LkAnim]::Reduit = $swRed.Checked; Enregistrer-Pref "AnimationsReduites" ([int]$swRed.Checked); Log "Animations réduites : $(if ($swRed.Checked) { 'oui' } else { 'non' })." })
foreach ($el in $oRed.Elements) { $el.Add_Click({ if ($swRed.Enabled) { $swRed.Checked = -not $swRed.Checked } }) }
$yOpt += 70
# v5.7 : rendu lissé (cartes dessinées hors écran = pas de scintillement). À couper seulement si une carte s'affiche mal.
$oLis = LigneOption $pT $yOpt "sparkles" "Rendu lissé" "Cartes sans scintillement. Coupe-le seulement si l'affichage a un souci (prend effet au prochain lancement)."
$swLis = New-Object LkToggle; $swLis.Size = Sz 44 24; $swLis.Location = Pt 858 19; $swLis.Checked = [LkCard]::Compose; $swLis.OffColor = $cOff
$oLis.Carte.Controls.Add($swLis)
$swLis.Add_CheckedChanged({ Enregistrer-Pref "RenduLisse" ([int]$swLis.Checked); Log "Rendu lissé : $(if ($swLis.Checked) { 'oui' } else { 'non' }) (au prochain lancement)." })
foreach ($el in $oLis.Elements) { $el.Add_Click({ $swLis.Checked = -not $swLis.Checked }) }
$yOpt += 70
# Mise à jour de l'appli
$oMaj = LigneOption $pT $yOpt 0xE895 "Mise à jour de l'appli" "Vérification au démarrage..."
$bMajVerif = Bouton $oMaj.Carte "Vérifier" 756 13 148 36
$bMajVerif.Add_Click({ Verifier-MiseAJour })
$yOpt += 70
# À propos
$oInfo = LigneOption $pT $yOpt 0xE946 "À propos" ("LuKZyR Optimisation $(Version-Affichee) · " + (T "journaux dans C:\ProgramData\Lukzyr"))
# v5.5 : le logo à la place de l'icône générique
$apLogo = New-Object Windows.Forms.PictureBox; $apLogo.Location = Pt 13 14; $apLogo.Size = Sz 34 34; $apLogo.SizeMode = "CenterImage"; $apLogo.BackColor = [Drawing.Color]::Transparent
$apLogo.Image = Logo-Net 30; $oInfo.Icone.Visible = $false; $oInfo.Carte.Controls.Add($apLogo); $apLogo.BringToFront()
$bDossier = Bouton $oInfo.Carte "Ouvrir les journaux" 716 13 188 36
$oInfo.Desc.Width = S 640; $tip.SetToolTip($oInfo.Desc, (T "Réglages enregistrés dans HKCU\Software\Lukzyr, journaux et sauvegardes dans C:\ProgramData\Lukzyr."))
$bDossier.Add_Click({ Ouvrir-Dossier (Join-Path $env:ProgramData "Lukzyr") })

# ===================== MATÉRIEL > BIOS =====================
$nomCarte = if ($profilBios) { $profilBios.Nom } else { "ce PC" }
$pB = NouvellePage "bios" "Guide BIOS" ((T "Personnalisé pour {0}.") -f $nomCarte)
function BoutonBios($txt, $x, $w, $principal) {
  $b = New-Object LkButton; $b.Text = (T $txt); $b.Font = Police 13 "Bold"; $b.Radius = S 10
  $b.Location = Pt $x 0; $b.Size = Sz $w 40
  if ($principal) { $b.Fill = $cAccent; $b.Fill2 = $cAccent2; $b.HoverFill = Hex "#7a40ee" } else { $b.Fill = $cCarte; $b.HoverFill = $cCarteSurvol; $b.ForeColor = $cBlanc }
  $pB.Controls.Add($b); return $b
}
$bExport  = BoutonBios "Exporter le guide" 0 210 $true
$bSupport = BoutonBios "Page support de ma carte mère" 222 262 $false
$bFw      = BoutonBios "Redémarrer dans le BIOS" 496 228 $false
$bExport.Icon = "download"; $bSupport.Icon = "globe"; $bFw.Icon = "power"
$uefi = $profilBios -and $profilBios.Uefi -eq $true
if (-not $uefi) { $bFw.Enabled = $false; $bFw.Text = (T "Redémarrage BIOS : UEFI requis") }
$cb = New-Object LkCard; $cb.Fill = $cCarte; $cb.Radius = S 12; $cb.Location = Pt 0 52; $cb.Size = Sz 936 360
$pB.Controls.Add($cb)
# La barre de défilement Windows (claire) est masquée : la zone de texte est plus large que son cadre ; la molette fait défiler
$clip = New-Object Windows.Forms.Panel; $clip.BackColor = $cCarte; $clip.Location = Pt 16 12; $clip.Size = Sz 904 336
$cb.Controls.Add($clip)
$rtb = New-Object Windows.Forms.RichTextBox
$rtb.ReadOnly = $true; $rtb.BorderStyle = "None"; $rtb.ScrollBars = "Vertical"; $rtb.WordWrap = $true; $rtb.DetectUrls = $true
$rtb.BackColor = $cCarte; $rtb.ForeColor = $cTexte2; $rtb.Location = New-Object Drawing.Point(0, 0); $rtb.Cursor = "Arrow"
$rtb.Size = New-Object Drawing.Size(((S 904) + [Windows.Forms.SystemInformation]::VerticalScrollBarWidth + 2), (S 336))
$clip.Controls.Add($rtb)
$rtb.Add_LinkClicked({ param($s, $e) try { Start-Process $e.LinkText } catch {} })
# Mise en forme : "=== X ===" titre violet, "/!\" avertissement orange, 1re ligne en grand
$fTitre = Police 15 "Bold"; $fTexte = Police 13; $fGrand = Police 17 "Bold"; $fInfo = Police 13 "Regular" "Consolas"
function Remplir-Bios {
$rtb.Clear()
$premiere = $true
foreach ($ligne in ($texteBios -split "`r?`n")) {
  $rtb.SelectionStart = $rtb.TextLength; $rtb.SelectionLength = 0
  if ($premiere) { $rtb.SelectionFont = $fGrand; $rtb.SelectionColor = $cBlanc; $premiere = $false }
  elseif ($ligne -match '^=== (.+) ===$') { $ligne = "`n" + $matches[1]; $rtb.SelectionFont = $fTitre; $rtb.SelectionColor = $cAccentClair }
  elseif ($ligne -match '^/!\\ ') { $ligne = ([string][char]0x26A0) + " " + $ligne.Substring(4); $rtb.SelectionFont = $fTexte; $rtb.SelectionColor = $cOrange }
  elseif ($ligne -match '^[^ /=][^:]{8,18}: ') { $rtb.SelectionFont = $fInfo; $rtb.SelectionColor = $cBlanc }
  else { $rtb.SelectionFont = $fTexte; $rtb.SelectionColor = $cTexte2 }
  $rtb.AppendText($ligne + "`n")
}
$rtb.SelectionStart = 0; $rtb.ScrollToCaret()
}
Remplir-Bios
$bExport.Add_Click({
  try { $c = Export-GuideBios $matBios -Ouvrir; Log "Guide BIOS exporté : $c" }
  catch { [void](Boite ((T "Export impossible") + " : $($_.Exception.Message)") "OK" "Error") }
})
$bSupport.Add_Click({ if ($profilBios -and $profilBios.UrlSupport) { Start-Process $profilBios.UrlSupport; Log "Page support ouverte : $($profilBios.UrlSupport)" } })
$bFw.Add_Click({
  if (-not $uefi) { return }
  if ($script:enCours) { [void](Boite (T "Attends la fin de l'opération en cours.")); return }
  $q = T "Le PC va redémarrer MAINTENANT et ouvrir directement le BIOS (UEFI).`n`nEnregistre et ferme tes fichiers ouverts avant de continuer.`nDans le BIOS : F10 pour sauvegarder et quitter.`n`nRedémarrer dans le BIOS ?"
  if ((Boite $q "YesNo" "Warning") -eq "Yes") {
    Log "Redémarrage dans le BIOS (shutdown /r /fw /t 0)."
    $out = & shutdown.exe /r /fw /t 0 2>&1
    if ($LASTEXITCODE -ne 0) { [void](Boite ((T "Windows a refusé le redémarrage direct dans le BIOS ({0}).`nUtilise la touche indiquée dans le guide au démarrage.") -f "$out") "OK" "Warning") }
  }
})

# ===================== PAGE JOURNAL =====================
$pJ = NouvellePage "journal" "Journal" "Tout ce qui a été fait, en direct."
$cj = New-Object LkCard; $cj.Fill = $cCarte; $cj.Radius = S 12; $cj.Location = Pt 0 0; $cj.Size = Sz 936 402
$pJ.Controls.Add($cj)
$log = New-Object Windows.Forms.TextBox
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = "Vertical"; $log.BorderStyle = "None"; $log.WordWrap = $true
$log.BackColor = $cCarte; $log.ForeColor = $cTexte2; $log.Font = Police 12 "Regular" "Consolas"
$log.Location = Pt 14 12; $log.Size = Sz 908 378
$cj.Controls.Add($log)
# v5.1 : exporter le journal (fichier texte, à joindre si quelque chose s'est mal passé)
$bExport = Bouton $pJ "Exporter le journal" 0 414 200 40 -Principal; $bExport.Icon = "download"
$bDosJ = Bouton $pJ "Ouvrir le dossier des journaux" 212 414 260 40
$lExport = Lbl $pJ "" 486 424 450 22 (Police 12) $cGris $cFond
function Exporter-Journal {
  $nom = "LuKZyR-journal-" + (Get-Date -Format "yyyyMMdd-HHmm") + ".txt"
  $dest = $null
  if ($env:LK_TEST -or $TestAuto) { try { if (-not (Test-Path -LiteralPath $dossierJournal)) { [void](New-Item -ItemType Directory -Path $dossierJournal -Force) } } catch {}; $dest = Join-Path $dossierJournal $nom }
  else {
    $dlg = New-Object Windows.Forms.SaveFileDialog; $dlg.FileName = $nom; $dlg.Filter = (T "Fichier texte") + " (*.txt)|*.txt"
    $dlg.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    if ($dlg.ShowDialog($f) -eq "OK") { $dest = $dlg.FileName }
  }
  if (-not $dest) { return }
  try {
    $entete = "LuKZyR Optimisation $(Version-Affichee) (build $VersionInterne) - " + (Get-Date -Format "dd/MM/yyyy HH:mm") + "`r`n$cpuNom / $(if ($gpuNom) { $gpuNom } else { '-' }) / $ramGo $uGo / $osNom $osVer`r`n`r`n"
    [IO.File]::WriteAllText($dest, $entete + $log.Text, (New-Object Text.UTF8Encoding $true))
    $lExport.ForeColor = $cVert; $lExport.Text = (T "Enregistré") + " : " + [IO.Path]::GetFileName($dest)
    Log ((T "Journal exporté") + " : $dest")
  } catch {
    $lExport.ForeColor = $cRouge; $lExport.Text = (T "Impossible d'enregistrer") + " : $($_.Exception.Message)"
    Log ((T "Impossible d'enregistrer") + " : $dest - $($_.Exception.Message)")
    if (-not $env:LK_TEST) { [void](Boite ((T "Impossible d'enregistrer") + " :`n$dest`n`n$($_.Exception.Message)") "OK" "Error") }
  }
}
$bExport.Add_Click({ Exporter-Journal })
$bDosJ.Add_Click({ Ouvrir-Dossier $dossierJournal })
$log.Add_HandleCreated({ try { [void][LkNative]::SetWindowTheme($this.Handle, $(if ($script:themeClair) { "Explorer" } else { "DarkMode_Explorer" }), $null) } catch {} })

# ===================== TABLEAU DE BORD =====================
Etape-Chargement 88 95 "Tableau de bord..."
$pAccueil = New-Object LkPanel; $pAccueil.Location = Pt 0 0; $pAccueil.Size = Sz 1000 604; $pAccueil.BackColor = $cFond; $pAccueil.Visible = $false
$main.Controls.Add($pAccueil)
$pages["accueil"] = @{ Panel = $pAccueil; Titre = "Tableau de bord"; Sous = ""; Construire = $null; Construite = $true }
$transp = [Drawing.Color]::Transparent
# --- v5.8 (interface « barre latérale ») : salutation + état du PC, boutons Rapport / Optimiser ---
$hr = (Get-Date).Hour
$prenom = "$env:USERNAME".Trim(); if ($prenom.Length -gt 1) { $prenom = $prenom.Substring(0, 1).ToUpper() + $prenom.Substring(1) }
$lSalut = Lbl $pAccueil (((T $(if ($hr -ge 5 -and $hr -lt 18) { "Bonjour" } else { "Bonsoir" })) + " $prenom").Trim()) 26 16 540 20 (Police 12.5 "Bold") $cGris $cFond
$lEtat1 = Lbl $pAccueil "" 24 36 420 42 (Police 25 "Bold") $cBlanc $cFond; $lEtat1.AutoEllipsis = $false
$lEtat2 = Lbl $pAccueil "" 300 36 300 42 (Police 25 "Bold") $cVif $cFond; $lEtat2.AutoEllipsis = $false
$bRapH = Bouton $pAccueil "Rapport système" 604 30 176 40; $bRapH.Icon = "file-text"
$bRapH.Add_Click({ Exporter-Rapport }); $tip.SetToolTip($bRapH, (T "Matériel, pilotes, Windows et réglages appliqués dans un fichier HTML + texte sur le Bureau. Rien n'est envoyé."))
$bOpti = Bouton $pAccueil "Optimiser maintenant" 788 30 188 40 -Principal; $bOpti.Icon = "zap"
$bOpti.Add_Click({ Optimiser }); $tip.SetToolTip($bOpti, (T "Point de restauration + sauvegarde de tes réglages, puis application du profil choisi."))
# --- Carte « Score d'optimisation » (anneau) + 4 lignes d'état ---
$hero = New-Object LkHero; $hero.Location = Pt 24 92; $hero.Size = Sz 560 204; $hero.Radius = S 16
$hero.BackColor = $cFond; $hero.Fill = $cCarte; $hero.Border = $cBord
$hero.GlowRect = New-Object Drawing.Rectangle((S 300), (S -170), (S 380), (S 380)); $hero.GlowAlpha = 30
$pAccueil.Controls.Add($hero)
$hT = Lbl $hero "SCORE D'OPTIMISATION" 24 14 300 18 (Police 10.5 "Bold") $cAccentClair $transp
$hD = Lbl $hero "Point de restauration + sauvegarde de tes réglages avant d'appliquer le profil." 24 180 512 16 (Police 11) $cGris2 $transp
$hero.ProgRect = New-Object Drawing.Rectangle((S 24), (S 198), (S 512), (S 3))
$texteHero = $hD.Text
$orb = New-Object LkOrb; $orb.Location = Pt 20 38; $orb.Size = Sz 136 136; $orb.Score = 0; $orb.Cursor = "Default"
$orb.Font = Police 32 "Bold"; $orb.SmallFont = Police 13.5 "Bold"; $orb.SubFont = Police 11; $orb.ForeColor = $cBlanc
$orb.Text = "–"; $orb.Sub = "/ 100"
$hero.Controls.Add($orb)
# --- Carte « Profils en 1 clic » ---
$cProf = New-Object LkCard; $cProf.Fill = $cCarte; $cProf.Radius = S 16; $cProf.Location = Pt 600 92; $cProf.Size = Sz 376 204
$pAccueil.Controls.Add($cProf)
Section $cProf 6 "PROFILS EN 1 CLIC"; $script:derniereSection.Left = S 18; $script:derniereSection.Width = S 340; $script:derniereSection.BackColor = $cCarte
$pillules = [ordered]@{}; $yp = 44
$iconesProfils = @{ gaming = "gamepad"; equilibre = "gauge"; portable = "power" }
foreach ($k in $profils.Keys) {
  $pl = New-Object LkPill; $pl.Font = Police 13.5 "Bold"; $pl.SubFont = Police 11.5; $pl.Radius = S 10; $pl.SubRight = $true; $pl.Icon = $iconesProfils[$k]
  $pl.Text = (T $profils[$k].Nom)
  $n = $profils[$k].On.Count
  $pl.Sub = $(if ($script:langue -eq "en") { "$n settings" } else { "$n réglages" }) + $(if ($k -eq "portable" -and $portable) { " · " + (T "conseillé") } else { "" })
  $pl.Location = Pt 16 $yp; $pl.Size = Sz 344 46; $pl.Tag = $k
  $pl.Add_Click({ Choisir-Profil $this.Tag })
  $cProf.Controls.Add($pl); $pillules[$k] = $pl; $yp += 52
}

# --- v5.7 : moniteur en direct (CPU, GPU, RAM, disque) ---
# CPU et RAM : 2 appels Windows instantanés ; GPU, mémoire vidéo et température : lus par LkMonitor sur un fil
# d'arrière-plan, SEULEMENT quand le Tableau de bord est affiché (rien du tout sur les autres pages ou réduit).
Section $pAccueil 304 "EN DIRECT"; $script:derniereSection.Left = S 26; $script:derniereSection.Width = S 948
function Stat($i, $cle, $valeur, $icone, [switch]$Barre) {
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.Radius = S 14
  $c.Location = Pt (24 + $i * 240) 334; $c.Size = Sz 232 132
  [void](Icone $c $icone 14 14 34 34 18 $cAccentClair $cCarte -Puce $cAccent)
  [void](Lbl $c $cle 56 14 164 18 (Police 11 "Bold") $cGris $cCarte)
  $v = Lbl $c $valeur 56 32 166 18 (Police 11) $cGris2 $cCarte
  $p = Lbl $c "" 14 54 204 40 (Police 27 "Bold") $cBlanc $cCarte; $p.TextAlign = "MiddleLeft"
  $b = $null; $sp = $null
  if ($Barre) { $b = New-Object LkBar; $b.Location = Pt 16 108; $b.Size = Sz 200 6; $b.Fill = $cAccent; $b.Fill2 = $cCyan; $b.Track = $cPiste; $c.Controls.Add($b) }
  else { $sp = New-Object LkSpark; $sp.Location = Pt 10 94; $sp.Size = Sz 212 32; $c.Controls.Add($sp) }
  $pAccueil.Controls.Add($c)
  return @{ Carte = $c; Pct = $p; Val = $v; Barre = $b; Spark = $sp }
}
$stCpu = Stat 0 "PROCESSEUR" $cpuCourt "cpu"
$stGpu = Stat 1 "CARTE GRAPHIQUE" $gpuCourt "monitor"
$stRam = Stat 2 "MÉMOIRE" "$ramGo $uGo" "memory"
$stC   = Stat 3 ((T "DISQUE") + " $($env:SystemDrive)") "" "drive" -Barre
foreach ($s in $stCpu, $stGpu, $stRam, $stC) { $tip.SetToolTip($s.Carte, (T "Mesures en direct, mises à jour toutes les 1,5 s quand le Tableau de bord est affiché.")) }
$script:statsVues = $false
$script:tempsLhm = @{ Cpu = $null; Gpu = $null; Lu = [datetime]::MinValue; EnCours = $false }
function Pct($lbl, $v, $sfx = " %") { if ($script:statsVues) { $lbl.Text = "$v$sfx" } else { [LkAnim]::CountTo($lbl, [int]$v, $sfx, 700) } }
function Maj-Moniteur { [LkMonitor]::Wanted = ($script:pageActive -eq "accueil" -and $f.WindowState -ne "Minimized"); if ([LkMonitor]::Wanted) { [LkMonitor]::Start() } }
# Températures LibreHardwareMonitor (s'il est ouvert) : lecture en arrière-plan toutes les 10 s au plus
$codeTempsLhm = {
  $r = @{ Cpu = $null; Gpu = $null }
  foreach ($ns in "root/LibreHardwareMonitor", "root/OpenHardwareMonitor") {
    try {
      $cap = @(Get-CimInstance -Namespace $ns -ClassName Sensor -Filter "SensorType='Temperature'" -ErrorAction Stop)
      if (-not $r.Cpu) { $c = $cap | Where-Object { "$($_.Identifier)" -match 'cpu' -and "$($_.Name)" -match 'Tctl|Tdie|Package|Core Average' } | Select-Object -First 1; if ($c -and $c.Value -gt 15 -and $c.Value -lt 115) { $r.Cpu = [math]::Round([double]$c.Value) } }
      if (-not $r.Gpu) { $c = $cap | Where-Object { "$($_.Identifier)" -match 'gpu' -and "$($_.Name)" -match '^(GPU Core|GPU Hot ?Spot|Hot ?Spot|GPU Edge|Edge)$' } | Sort-Object { if ("$($_.Name)" -eq 'GPU Core') { 0 } else { 1 } } | Select-Object -First 1; if ($c -and $c.Value -gt 15 -and $c.Value -lt 115) { $r.Gpu = [math]::Round([double]$c.Value) } }
    } catch {}
  }
  $r
}
function MajStats {
  $cl = [LkNative]::CpuLoad(); if ($cl -ge 0) { $stCpu.Spark.Push($cl); Pct $stCpu.Pct $cl }
  $rl = [LkNative]::RamLoad()
  if ($rl -ge 0) { $stRam.Spark.Push($rl); Pct $stRam.Pct $rl; if ($ramGo) { $stRam.Val.Text = ("{0:N1} / {1} $uGo " -f ($ramGo * $rl / 100.0), $ramGo) + (T "utilisés") + $(if ($ramMhz) { " · $ramMhz MHz" } else { "" }) } }
  $gl = [LkMonitor]::Gpu
  if ($gl -ge 0) { $stGpu.Spark.Push($gl); Pct $stGpu.Pct $gl } elseif (-not $stGpu.Pct.Text) { $stGpu.Pct.Text = "–" }
  # températures : LibreHardwareMonitor (si ouvert), sinon zone thermique Windows (rare sur Ryzen de bureau)
  if (-not $script:tempsLhm.EnCours -and ((Get-Date) - $script:tempsLhm.Lu).TotalSeconds -ge 10) {
    $script:tempsLhm.Lu = Get-Date
    if (@([Diagnostics.Process]::GetProcessesByName("LibreHardwareMonitor")).Count -or @([Diagnostics.Process]::GetProcessesByName("OpenHardwareMonitor")).Count) {
      $script:tempsLhm.EnCours = $true
      En-Fond "temperatures" $codeTempsLhm @{} { param($r) $script:tempsLhm.EnCours = $false; if ($r) { $script:tempsLhm.Cpu = $r.Cpu; $script:tempsLhm.Gpu = $r.Gpu } }
    } else { $script:tempsLhm.Cpu = $null; $script:tempsLhm.Gpu = $null }
  }
  $tc = if ($script:tempsLhm.Cpu) { $script:tempsLhm.Cpu } elseif ([LkMonitor]::Temp -gt 0) { [LkMonitor]::Temp } else { $null }
  $stCpu.Val.Text = $cpuCourt + $(if ($tc) { " · $tc °C" } else { "" })
  $vr = [LkMonitor]::Vram; $vTot = if ($gpus.Count) { $gpus[0].VramGo } else { 0 }
  $txtG = $gpuCourt
  if ($vr -gt 0) { $txtG = ("VRAM {0:N1}" -f ($vr / 1GB)) + $(if ($vTot) { " / $vTot $uGo" } else { " $uGo" }) }
  if ($script:tempsLhm.Gpu) { $txtG += " · $($script:tempsLhm.Gpu) °C" }
  $stGpu.Val.Text = $txtG
  try {
    $dC = New-Object IO.DriveInfo($env:SystemDrive)
    $libre = [math]::Round($dC.AvailableFreeSpace / 1GB); $pc = [int](100 - 100 * $dC.AvailableFreeSpace / $dC.TotalSize)
    $stC.Val.Text = "$libre " + (T "Go libres sur") + " $([math]::Round($dC.TotalSize / 1GB)) $uGo"
    $stC.Barre.Value = $pc; Pct $stC.Pct $pc
    $tip.SetToolTip($stC.Pct, (T "Espace utilisé sur le disque système"))
  } catch {}
  $script:statsVues = $true
}
[void][LkNative]::CpuLoad()
$tStats = New-Object Windows.Forms.Timer; $tStats.Interval = 1500
# jauges mises à jour seulement quand le tableau de bord est visible et la fenêtre pas réduite
$tStats.Add_Tick({ if ($f.WindowState -ne "Minimized" -and $script:pageActive -eq "accueil") { MajStats } }); $tStats.Start()

# --- Bandeau d'alertes (données réelles) ---
function Alerte($i) {
  # v5.8 : 4 lignes d'état à droite de l'anneau de score
  $a = New-Object LkTint; $a.Radius = S 8; $a.Location = Pt 172 (42 + $i * 33) ; $a.Size = Sz 368 29; $a.BackColor = $cCarte
  $ic = Icone $a "" 4 0 22 29 15 $cVert $transp
  $tx = Lbl $a "" 30 0 250 29 (Police 12) $cTexte2 $transp; $tx.TextAlign = "MiddleLeft"
  $ln = Lbl $a "" 262 0 100 29 (Police 11.5 "Bold") $cVert $transp; $ln.TextAlign = "MiddleRight"; $ln.Cursor = "Hand"
  $hero.Controls.Add($a)
  $al = @{ Carte = $a; Icone = $ic; Texte = $tx; Lien = $ln; Action = $null }
  $ln.Tag = $al; $ln.Add_Click({ if ($this.Tag.Action) { & $this.Tag.Action } })
  return $al
}
function Regler-Alerte($al, $glyphe, $couleur, $texte, $lien, $action) {
  $neuf = ($al.Texte.Text -ne $texte)
  $al.Carte.Accent = $couleur; $al.Icone.Text = [string][char]$glyphe; $al.Icone.ForeColor = $couleur
  $al.Texte.Text = $texte; $al.Lien.Text = $lien; $al.Lien.ForeColor = $couleur; $al.Action = $action
  $al.Texte.Width = $al.Carte.Width - (S 28) - $(if ($lien) { (Largeur $lien $al.Lien.Font) + (S 16) } else { S 12 })
  $al.Carte.Invalidate()
  if ($neuf -and $al.Carte.Visible -and [LkAnim]::On) {
    # v5.3 : nouvelle alerte = fondu du fond et du texte
    $al.Carte.Apparaitre()
    [LkAnim]::FadeFore($al.Texte, $cFond, $cTexte2, 320); if ($lien) { [LkAnim]::FadeFore($al.Lien, $cFond, $couleur, 320) }; [LkAnim]::FadeFore($al.Icone, $cFond, $couleur, 320)
  }
}
$alScore = Alerte 0; $alDem = Alerte 1; $alOpt = Alerte 2; $alSante = Alerte 3
$cViolet = $cAccentClair   # suit le thème (plus foncé en clair)
# v5.1 : les lectures (démarrage, disques) se font en arrière-plan ; le bandeau se remplit ensuite
$codeDisques = {
  $pb = @(Get-PhysicalDisk | Where-Object { "$($_.HealthStatus)" -ne "Healthy" } | ForEach-Object { "$($_.FriendlyName)" })
  $vols = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" -and $_.Size -gt 0 } | Sort-Object { $_.SizeRemaining / $_.Size })
  $pire = $vols | Select-Object -First 1
  @{ Problemes = $pb; Lettre = "$($pire.DriveLetter)"; PcLibre = $(if ($pire) { [math]::Round(100 * $pire.SizeRemaining / $pire.Size) } else { 100 }) }
}
function Alerte-Demarrage($r) {
  if (-not $r) { return }
  $l = @($r.Liste | Where-Object { $_.Actif -and -not $_.Protege -and $_.Impact -eq "élevé" })
  $script:scoreDem = $l.Count; try { Maj-Score } catch {}
  if ($l.Count) { Regler-Alerte $alDem 0xE7BA $cOrange ((T "{0} appli(s) lourde(s) au démarrage") -f $l.Count) (T "Voir") { Afficher "demarrage" } }
  else { Regler-Alerte $alDem 0xE73E $cVert (T "Démarrage léger : rien de lourd") (T "Voir") { Afficher "demarrage" } }
}
function Alerte-Disques($d) {
  if ($d) { $script:scoreDisques = -not @($d.Problemes).Count; try { Maj-Score } catch {} }
  if (-not $d -or ($etatMaj.Statut -in @("dispo", "telechargement", "telecharge"))) { return }
  if (@($d.Problemes).Count) { Regler-Alerte $alSante 0xE783 $cRouge ((T "Disque à surveiller : {0}") -f @($d.Problemes)[0]) (T "Santé") { Afficher "sante" } }
  elseif ($d.PcLibre -lt 10) { Regler-Alerte $alSante 0xE783 $cRouge ((T "{0}: presque plein ({1} % libre)") -f $d.Lettre, $d.PcLibre) (T "Santé") { Afficher "sante" } }
  elseif ($d.PcLibre -lt 20) { Regler-Alerte $alSante 0xE7BA $cOrange ((T "{0}: {1} % libre seulement") -f $d.Lettre, $d.PcLibre) (T "Santé") { Afficher "sante" } }
  else { Regler-Alerte $alSante 0xE95E $cVert (T "Disques en bonne santé") (T "Santé") { Afficher "sante" } }
}
function Maj-Alertes {
  # 1. Applis lourdes au démarrage (lu en arrière-plan)
  if (-not $script:alertesInit) { $script:alertesInit = $true; Regler-Alerte $alDem 0xE895 $cAccentClair (T "Lecture du démarrage...") "" $null; Regler-Alerte $alSante 0xE895 $cAccentClair (T "Lecture des disques...") "" $null }
  En-Fond "alertes-demarrage" $codeDemarrage (Vars-Demarrage $false) { param($r) Alerte-Demarrage $r }
  Maj-AlerteOptim
  # 3. Mise à jour disponible, sinon santé des disques
  if ($etatMaj.Statut -in @("dispo", "telechargement", "telecharge")) {
    Regler-Alerte $alSante 0xE896 $cAccentClair ((T "Version {0} disponible") -f $etatMaj.Version) $(if ($etatMaj.Statut -eq "telecharge") { T "Ouvrir" } else { T "Télécharger" }) { $bBan.PerformClick() }
    return
  }
  En-Fond "alertes-disques" $codeDisques @{} { param($d) Alerte-Disques $d }
}
# v5.3 : alerte « dernière optimisation » seule, rafraîchie tout de suite à la fin d'OPTIMISER / Tout annuler
function Maj-AlerteOptim {
  # Dernière optimisation (annulable tant que la sauvegarde existe)
  $sauv = Test-Path (Join-Path $env:ProgramData "Lukzyr\sauvegarde-reglages.json")
  $der = "$((Get-ItemProperty -Path $cleConfig -Name DerniereOptimisation -ErrorAction Ignore).DerniereOptimisation)"
  if (-not $der -and $sauv) { $der = (Get-Item (Join-Path $env:ProgramData "Lukzyr\sauvegarde-reglages.json")).LastWriteTime.ToString("dd/MM HH:mm") }
  if ($der -and $sauv) { Regler-Alerte $alOpt 0xE930 $cVert ((T "Optimisé le {0} · annulable") -f $der) (T "Tout annuler") { Tout-Annuler } }
  elseif ($der) { Regler-Alerte $alOpt 0xE930 $cVert ((T "Dernière optimisation le {0}") -f $der) "" $null }
  else { Regler-Alerte $alOpt 0xE946 $cAccentClair (T "Pas encore optimisé : choisis un profil") "" $null }
}

# ===================== v5.8 : SCORE D'OPTIMISATION (honnête, lecture seule) =====================
# Calculé UNIQUEMENT à partir de ce qui est lu sur ce PC : 10 réglages vérifiés dans le registre (70 points),
# applis lourdes au démarrage (10), espace libre du disque système (10), santé des disques (5), âge du pilote
# graphique (5). Une mesure pas encore lue (démarrage, disques, pilote) n'est pas comptée du tout (ni pour, ni
# contre). VBS n'est pas compté : c'est un compromis sécurité / performance, pas un « mieux ».
function Lire-Reg($chemin, $nom) { try { (Get-ItemProperty -LiteralPath $chemin -Name $nom -ErrorAction Stop).$nom } catch { $null } }
$script:scoreDem = $null; $script:scoreDisques = $null; $script:scoreDetail = @()
$testsScore = @(
  @("Mode Jeu", { $v = Lire-Reg "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled"; ($null -eq $v) -or ($v -ne 0) }),
  @("Captures de jeu en arrière-plan coupées", { (Lire-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled") -eq 0 }),
  @("Planification GPU à accélération matérielle", { (Lire-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode") -eq 2 }),
  @("Priorité aux jeux", { (Lire-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "GPU Priority") -eq 8 }),
  @("Souris sans accélération", { "$(Lire-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed')" -eq "0" }),
  @("Optimisations des jeux en fenêtre", { "$(Lire-Reg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings')" -match 'SwapEffectUpgradeEnable=1' }),
  @("Télémétrie réduite", { $v = Lire-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry"; ($null -ne $v) -and ($v -le 1) }),
  @("Applis de démarrage sans délai", { (Lire-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec") -eq 0 }),
  @("Edge sans préchargement", { (-not (Test-Path -LiteralPath (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"))) -or ((Lire-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled") -eq 0) }),
  @("Assistant de stockage", { (Lire-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" "01") -eq 1 })
)
function Calculer-Score {
  $pts = 0.0; $max = 0.0; $det = @(); $ok = 0
  foreach ($ts in $testsScore) {
    $r = $false; try { $r = [bool](& $ts[1]) } catch {}
    if ($r) { $ok++; $pts += 7 }; $max += 7
    $det += , @($r, (T $ts[0]), $(if ($r) { 7 } else { 0 }), 7)
  }
  if ($null -ne $script:scoreDem) { $p = [math]::Max(0, 10 - 3 * $script:scoreDem); $pts += $p; $max += 10; $det += , @(($script:scoreDem -eq 0), ((T "Applis lourdes au démarrage") + " : $($script:scoreDem)"), $p, 10) }
  try {
    $dC = New-Object IO.DriveInfo($env:SystemDrive); $pl = [math]::Round(100 * $dC.AvailableFreeSpace / [math]::Max(1, $dC.TotalSize))
    $p = if ($pl -ge 20) { 10 } elseif ($pl -ge 10) { 5 } else { 0 }; $pts += $p; $max += 10
    $det += , @(($p -eq 10), ((T "Espace libre sur {0}") -f $env:SystemDrive) + " : $pl %", $p, 10)
  } catch {}
  if ($null -ne $script:scoreDisques) { $p = if ($script:scoreDisques) { 5 } else { 0 }; $pts += $p; $max += 5; $det += , @([bool]$script:scoreDisques, (T "Disques en bonne santé"), $p, 5) }
  $ag = @($script:infosPilotes | Where-Object { $_.Age -ge 0 } | Select-Object -First 1)
  if ($ag.Count) { $p = if ($ag[0].Age -le 180) { 5 } else { 0 }; $pts += $p; $max += 5; $det += , @(($p -eq 5), ((T "Pilote graphique de moins de 6 mois") + " (" + ((T "{0} jours") -f $ag[0].Age) + ")"), $p, 5) }
  $score = if ($max -gt 0) { [int][math]::Round(100 * $pts / $max) } else { 0 }
  return @{ Score = $score; Ok = $ok; Total = $testsScore.Count; Detail = $det }
}
function Maj-Score {
  $r = Calculer-Score; $script:scoreDetail = $r.Detail; $script:score = $r.Score
  if (-not $script:enCours) { $orb.Text = "$($r.Score)"; $orb.Sub = "/ 100"; $orb.SetScore($r.Score / 100.0) }
  $e = if ($r.Score -ge 80) { @("Ton PC est en ", "bonne forme") } elseif ($r.Score -ge 55) { @("Ton PC est ", "presque optimisé") } else { @("Ton PC peut ", "aller plus vite") }
  $lEtat1.Text = (T $e[0]); $lEtat2.Text = (T $e[1])
  $lEtat1.Width = (Largeur $lEtat1.Text $lEtat1.Font) + 2; $lEtat2.Left = $lEtat1.Right - (S 6); $lEtat2.Width = (Largeur $lEtat2.Text $lEtat2.Font) + 4
  $coul = if ($r.Ok -eq $r.Total) { $cVert } elseif ($r.Ok -ge [math]::Ceiling($r.Total / 2)) { $cAccentClair } else { $cOrange }
  Regler-Alerte $alScore $(if ($r.Ok -eq $r.Total) { 0xE73E } else { 0xE945 }) $coul ((T "{0}/{1} réglages recommandés en place") -f $r.Ok, $r.Total) (T "Détails") { Afficher-DetailScore }
  $tip.SetToolTip($orb, (T "Score calculé seulement avec ce qui est lu sur ce PC. Clique sur « Détails » pour voir chaque point."))
}
function Afficher-DetailScore {
  $l = @($script:scoreDetail | ForEach-Object { $(if ($_[0]) { "✓ " } else { "✗ " }) + $_[1] + "   (" + $_[2] + "/" + $_[3] + ")" })
  $msg = ((T "Score d'optimisation : {0}/100") -f $script:score) + "`n`n" + ($l -join "`n") + "`n`n" + (T "Seul ce qui est lu sur ce PC compte. Une mesure pas encore lue n'est pas comptée. VBS n'est pas compté : c'est un compromis sécurité / performance.")
  [void](Boite $msg)
}

function Maj-Tuiles { }   # v5.8 : tuiles supprimées (remplacées par la barre latérale)
# v5.7 : accès rapide aux nouveautés
Section $pAccueil 474 "ACCÈS RAPIDE"; $script:derniereSection.Left = S 26; $script:derniereSection.Width = S 948
$rapides = @{}
$defRapides = @(
  @("session", "gamepad", "Session de jeu", "Ferme les applis en jeu"),
  @("espace", "pie", "Espace disque", "Ce qui prend de la place"),
  @("demarrage", "sliders", "Démarrage", "Applis au démarrage"),
  @("nettoyage", "sparkles", "Nettoyage", "Windows plus léger")
)
for ($i = 0; $i -lt $defRapides.Count; $i++) {
  $d = $defRapides[$i]
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.HoverFill = $cCarteSurvol; $c.Radius = S 12
  $c.Location = Pt (24 + $i * 240) 504; $c.Size = Sz 232 64; $c.Cursor = "Hand"; $c.Tag = $d[0]
  $ic = Icone $c $d[1] 12 14 36 36 20 $cAccentClair $cCarte
  $tt = Lbl $c $d[2] 54 12 150 22 (Police 13.5 "Bold") $cBlanc $cCarte
  $ts = Lbl $c $d[3] 54 34 152 18 (Police 11) $cGris $cCarte
  $ta = Icone $c "chevron" 204 0 22 64 15 $cGris2 $cCarte
  foreach ($el in $c, $ic, $tt, $ts, $ta) {
    $el.Cursor = "Hand"; $el.Tag = $d[0]
    $el.Add_Click({ switch ($this.Tag) { "session" { Afficher "session" } "espace" { Afficher "espace" } "demarrage" { Afficher "demarrage" } "nettoyage" { Afficher-Groupe "nettoyage" } } })
    Survol-Carte $el
  }
  $pAccueil.Controls.Add($c); $rapides[$d[0]] = $ts
}


# ===================== BARRE DU BAS (pages de section) =====================
$barreBas = New-Object LkPanel; $barreBas.Location = Pt 0 548; $barreBas.Size = Sz 1000 56; $barreBas.BackColor = $cFond
$main.Controls.Add($barreBas)
$trait = New-Object Windows.Forms.Panel; $trait.Location = Pt 32 0; $trait.Size = Sz 936 1; $trait.BackColor = $cPiste
$barreBas.Controls.Add($trait)
$compteur = New-Object Windows.Forms.Label
$compteur.Location = Pt 32 14; $compteur.Size = Sz 540 22; $compteur.BackColor = $cFond; $compteur.ForeColor = $cGris; $compteur.Font = Police 13; $compteur.AutoEllipsis = $true
$barreBas.Controls.Add($compteur)
$fondProg = New-Object LkBar; $fondProg.Location = Pt 32 40; $fondProg.Size = Sz 520 4; $fondProg.Track = $cPiste2; $fondProg.Fill = $cAccent; $fondProg.Fill2 = Hex "#2f9bff"; $fondProg.Visible = $false
$barreBas.Controls.Add($fondProg)
$bAnnulerBas = New-Object LkButton; $bAnnulerBas.Text = (T "Tout annuler"); $bAnnulerBas.Icon = "undo"; $bAnnulerBas.Font = Police 12.5 "Bold"; $bAnnulerBas.Radius = S 10
$bAnnulerBas.Location = Pt 600 8; $bAnnulerBas.Size = Sz 164 42; $bAnnulerBas.Fill = $cCarte; $bAnnulerBas.HoverFill = $cCarteSurvol; $bAnnulerBas.ForeColor = $cBlanc
$bAnnulerBas.Add_Click({ Tout-Annuler })
$barreBas.Controls.Add($bAnnulerBas)
$bAppliquer = New-Object LkButton; $bAppliquer.Text = (T "APPLIQUER"); $bAppliquer.Font = Police 15 "Bold"; $bAppliquer.Radius = S 10
$bAppliquer.Location = Pt 776 6; $bAppliquer.Size = Sz 192 46; $bAppliquer.Fill = $cAccent; $bAppliquer.Fill2 = $cAccent2; $bAppliquer.HoverFill = Hex "#7a40ee"
$barreBas.Controls.Add($bAppliquer)

$script:enCours = $false
# v5.7 : un clic sur un interrupteur ne recalcule plus tout sur-le-champ : le compteur est mis à jour 80 ms
# plus tard (une seule fois même si 20 interrupteurs changent), l'animation de l'interrupteur reste fluide
$tCompteur = New-Object Windows.Forms.Timer; $tCompteur.Interval = 80
$tCompteur.Add_Tick({ $tCompteur.Stop(); try { MajCompteur-Maintenant } catch {} })
function MajCompteur { $tCompteur.Stop(); $tCompteur.Start() }
function MajCompteur-Maintenant {
  if ($script:enCours) { return }
  $n = 0; $na = 0; $np = 0; $av = 0
  foreach ($sw in $toggles) {
    if (-not $sw.Checked) { continue }
    $k = "$($sw.Tag.Cle)"
    if ($k -like "app:*" -or $k -eq "majtout") { $na++ } elseif ($k -eq "pilote") { $np++ } else { $n++ }
    if ($sw.Tag.Badge -eq "a" -or $sw.Tag.Badge -eq "d") { $av++ }
  }
  $txt = if ($script:langue -eq "en") { "$n setting$(if ($n -ne 1) { 's' })" } else { "$n réglage$(if ($n -gt 1) { 's' })" }
  if ($na) { $txt += " · " + $(if ($script:langue -eq "en") { "$na app$(if ($na -ne 1) { 's' })" } else { "$na appli$(if ($na -gt 1) { 's' })" }) }
  if ($np) { $txt += " · " + $(if ($script:langue -eq "en") { "$np driver$(if ($np -ne 1) { 's' })" } else { "$np pilote$(if ($np -gt 1) { 's' })" }) }
  $txt += $(if ($script:langue -eq "en") { " selected" } else { " sélectionné(s)" })
  if ($av) { $txt += " · " + $(if ($script:langue -eq "en") { "$av advanced / permanent" } else { "$av avancé(s) / définitif(s)" }) }
  $compteur.Text = $txt
}

# ===================== JOURNAL / FICHIER =====================
$dossierJournal = Join-Path $env:ProgramData "Lukzyr"
[void](New-Item -ItemType Directory -Force $dossierJournal)
$fichierJournal = Join-Path $dossierJournal ("journal-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")
function Log($t) {
  $ligne = "[" + (Get-Date -Format HH:mm:ss) + "]  $t"
  $log.AppendText($ligne + "`r`n")
  try { [IO.File]::AppendAllText($fichierJournal, $ligne + "`r`n", [Text.Encoding]::UTF8) } catch { try { [void](New-Item -ItemType Directory -Force $dossierJournal); [IO.File]::AppendAllText($fichierJournal, $ligne + "`r`n", [Text.Encoding]::UTF8) } catch {} }
}

# ===================== MOTEUR D'EXÉCUTION =====================
# Chaque étape = un processus PowerShell caché ; sa sortie arrive dans le Journal ligne par ligne.
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
# v5.6 : chemin complet de winget.exe (CreateProcess ne résout pas toujours l'alias WindowsApps, surtout en administrateur)
function Chemin-Winget {
  $c = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c -and $c.Source -and (Test-Path $c.Source)) { return $c.Source }
  $alias = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
  if (Test-Path $alias) { return $alias }
  $d = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Sort-Object { try { [version](($_.Directory.Name -split '_')[1]) } catch { [version]"0.0" } } -Descending | Select-Object -First 1
  if ($d) { return $d.FullName }
  return $null
}
function EtapeScript($nom, $script, $argsTxt) { @{ Nom = $nom; Fichier = $ps; Args = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $dir $script)`" $argsTxt" } }

function Construire-Plan($Seulement = $null) {
  $plan = New-Object System.Collections.ArrayList
  $liste = New-Object System.Collections.ArrayList
  $winget = Chemin-Winget
  # Réglages retenus : cochés (et, pour OPTIMISER, seulement ceux du profil)
  $actifs = @($toggles | Where-Object { $_.Checked -and $_.Enabled -and (-not $Seulement -or $Seulement -contains $_.Tag.Cle) })
  $on = @{}; foreach ($sw in $actifs) { $on[[string]$sw.Tag.Cle] = $true }
  foreach ($sw in $actifs) {
    if ($sw.Tag.Cle -ne "pilote") { continue }
    $pi = $sw.Tag.Pilote
    if ($pi.Winget -and $winget) {
      [void]$plan.Add(@{ Nom = "Pilote : $($pi.Nom)"; Fichier = $winget; Args = "install --id $($pi.Winget) --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" })
    } else { [void]$plan.Add(@{ Nom = "Pilote : $($pi.Nom) (page officielle)"; Url = $pi.Url }) }
    [void]$liste.Add("Pilote : $($pi.Nom)")
  }
  if ($on["debloat"] -or $on["telemetrie"] -or $on["copilot"] -or $on["onedrive"]) {
    $a = "-NonInteractif -SansPointRestauration"
    if ($on["debloat"])    { $a += " -Debloat";    [void]$liste.Add("Débloat Windows") }
    if ($on["telemetrie"]) { $a += " -Telemetrie"; [void]$liste.Add("Réduction de la télémétrie") }
    if ($on["copilot"])    { $a += " -Copilot";    [void]$liste.Add("Suppression de Copilot") }
    if ($on["onedrive"])   { $a += " -OneDrive";   [void]$liste.Add("Désinstallation de OneDrive") }
    [void]$plan.Add((EtapeScript "Nettoyage de Windows" "Debloat-PC.ps1" $a))
  }
  $apps = @($actifs | Where-Object { "$($_.Tag.Cle)" -like "app:*" } | ForEach-Object { $_.Tag.Cle.Substring(4) })
  if ($apps.Count -or $on["majtout"]) {
    $a = "-NonInteractif -Apps `"$(if ($apps.Count) { $apps -join ',' } else { 'aucune' })`""
    if ($on["majtout"]) { $a += " -MajTout"; [void]$liste.Add("Mise à jour des autres applis") }
    if ($apps.Count) { [void]$liste.Add((T "Installation") + " : " + ($apps -join ", ")) }
    [void]$plan.Add((EtapeScript "Installation des applications" "Installer-Applis.ps1" $a))
  }
  if ($on["edge"]) { [void]$plan.Add((EtapeScript "Désinstallation d'Edge" "Desinstaller-Edge.ps1" "-NonInteractif")); [void]$liste.Add("Désinstallation de Microsoft Edge") }
  $opts = @($actifs | Where-Object { "$($_.Tag.Cle)" -like "optim:*" })
  if ($opts.Count) {
    $a = "-NonInteractif -SansPointRestauration " + (($opts | ForEach-Object { "-" + $_.Tag.Cle.Substring(6) }) -join " ")
    foreach ($o in $opts) { [void]$liste.Add($o.Tag.Titre) }
    [void]$plan.Add((EtapeScript "Optimisation de Windows" "Optimisation-PC.ps1" $a))
  }
  # Sauvegarde des valeurs d'origine (pour « Tout annuler ») AVANT toute modification
  $aSauver = @($opts | ForEach-Object { $_.Tag.Cle })
  foreach ($k in "debloat", "telemetrie", "copilot") { if ($on[$k]) { $aSauver += $k } }
  if ($aSauver.Count) { $plan.Insert(0, (EtapeScript "Sauvegarde des réglages d'origine" "Sauvegarde-Reglages.ps1" "-Sauvegarder -NonInteractif -Elements `"$($aSauver -join ',')`"")) }
  if ($plan.Count) { $plan.Insert(0, (EtapeScript "Point de restauration" "Point-Restauration.ps1" "-NonInteractif")) }
  $risques = @($actifs | Where-Object { $_.Tag.Badge -in @("a", "d") } | ForEach-Object { "$(if ($_.Tag.Badge -eq 'd') { T 'DÉFINITIF' } else { T 'AVANCÉ' }) : $(T $_.Tag.Titre)" })
  # v5.6 : ce que « Tout annuler » ne pourra PAS défaire (dit avant de commencer)
  $nonRev = @($actifs | Where-Object { $_.Tag.Badge -in @("n", "d") } | ForEach-Object {
    if ("$($_.Tag.Cle)" -like "app:*") { T "Installation des applis" } elseif ($_.Tag.Cle -eq "pilote") { T "Installation des pilotes" } else { T $_.Tag.Titre } } | Select-Object -Unique)
  return @{ Plan = $plan; Liste = $liste; Risques = $risques; NonRev = $nonRev; Edge = [bool]$on["edge"] }
}
# Fenêtre de confirmation commune (APPLIQUER et OPTIMISER)
function Confirmer-Plan($r, $titre = $null) {
  if (-not $r.Plan.Count) { [void](Boite (T "Aucun réglage n'est activé.")); return $false }
  $msg = $(if ($titre) { "$titre`n`n" } else { "" }) + (T "LuKZyR Optimisation va faire :") + "`n`n - " + (($r.Liste | ForEach-Object { T $_ }) -join "`n - ") + "`n`n" + (T "Un point de restauration est créé avant de commencer, et les réglages d'origine sont sauvegardés (bouton « Tout annuler »).")
  if ($r.NonRev.Count) { $msg += "`n`n" + (T "Non annulable avec « Tout annuler » :") + " " + ($r.NonRev -join ", ") + "." }
  if ($r.Risques.Count) { $msg += "`n`n" + (T "Options avancées ou définitives :") + "`n - " + ($r.Risques -join "`n - ") }
  if ($r.Edge) { $msg += "`n`n" + (T "ATTENTION : Edge sera désinstallé. Garde un autre navigateur (Brave).") }
  if (@($r.Liste | Where-Object { $_ -eq "Désactiver VBS / intégrité de la mémoire" }).Count) { $msg += "`n`n" + (T "ATTENTION : désactiver VBS réduit un peu la sécurité de Windows.") }
  if ($TestAuto -or $env:LK_TEST) { Log "[Test] Confirmation acceptée automatiquement :"; foreach ($ligne in ($msg -split "`n")) { if ($ligne.Trim()) { Log "   $ligne" } }; return $true }
  return ((Boite ($msg + "`n`n" + (T "Continuer ?")) "YesNo" $(if ($r.Edge -or $r.Risques.Count) { "Warning" } else { "Question" })) -eq "Yes")
}
# Bouton OPTIMISER : applique le profil choisi (ou celui conseillé) : point de restauration + sauvegarde + réglages
function Optimiser {
  if ($script:enCours) { return }
  $k = if ($script:profilChoisi) { $script:profilChoisi } elseif ($portable) { "portable" } else { "gaming" }
  if ($script:profilChoisi -ne $k) { Choisir-Profil $k }
  $r = Construire-Plan $cles
  $nb = $r.Liste.Count
  if (-not (Confirmer-Plan $r ((T "Profil") + " : " + (T $profils[$k].Nom) + " · " + $(if ($script:langue -eq "en") { "$nb settings" } else { "$nb réglages" })))) { return }
  Lancer-Plan $r.Plan -Ici -Resume $r.Liste -Titre ((T "Profil") + " " + (T $profils[$k].Nom))
}

$script:plan = $null; $script:idx = -1; $script:proc = $null; $script:nbEtapes = 0
$tMoteur = New-Object Windows.Forms.Timer; $tMoteur.Interval = 250
$script:occupe = $false
$tMoteur.Add_Tick({
  # Garde anti ré-entrance : ouvrir une page web peut traiter des messages et relancer le minuteur
  if ($script:occupe) { return }
  $script:occupe = $true
  try { Tick-Moteur } finally { $script:occupe = $false }
})
function Tick-Moteur {
  if ($script:proc) {
    $l = $null
    while ($script:proc.Lines.TryDequeue([ref]$l)) { Log "   $l"; if ($l -match '==>\s*(.+)$') { $et = $script:plan[$script:idx].Nom; $compteur.Text = if ($matches[1].Trim() -eq $et) { "$et..." } else { "$et : $($matches[1].Trim())" } } }
    if (-not $script:proc.Done) { return }
    while ($script:proc.Lines.TryDequeue([ref]$l)) { Log "   $l" }
    $code = $script:proc.ExitCode
    Log ("Fin : " + $script:plan[$script:idx].Nom + $(if ($code -ne 0) { " (code $code)" } else { "" }))
    $nomEt = $script:plan[$script:idx].Nom
    if ($nomEt -eq "Point de restauration") {
      # v5.6 : sans point de restauration, on demande avant de toucher à quoi que ce soit
      $script:pointOk = ($code -eq 0)
      if (-not $script:pointOk) {
        $msgPR = (T "Le point de restauration n'a pas pu être créé (détail dans le Journal).") + "`n`n" + (T "Continuer quand même, SANS point de restauration ?") + "`n" + (T "Non = tout arrêter : rien n'a encore été modifié.")
        $repPR = if ($TestAuto -or $env:LK_TEST) { if ($env:LK_POINT -eq "non") { "No" } else { "Yes" } } else { "$(Boite $msgPR "YesNo" "Warning")" }
        Log ("Point de restauration impossible : " + $(if ($repPR -eq "Yes") { "l'utilisateur continue sans." } else { "arrêt demandé, rien n'a été modifié." }))
        if ($repPR -ne "Yes") { $script:arrete = $true; $script:proc = $null; $script:idx = $script:nbEtapes; Fin-Execution; return }
      }
    }
    if ($code -ne 0) {
      $script:nbErreurs++; $script:etapesErreur += (T $script:plan[$script:idx].Nom)
      Log ("   /!\ " + ((T "L'étape « {0} » s'est terminée avec une erreur (code {1}). Les autres étapes continuent ; le détail est juste au-dessus. Bouton « Exporter le journal » pour le garder.") -f (T $script:plan[$script:idx].Nom), $code))
    }
    $script:proc = $null
  }
  $script:idx++
  $fondProg.Value = [int](100 * $script:idx / [math]::Max(1, $script:nbEtapes))
  if ($script:idx -ge $script:nbEtapes) { Fin-Execution; return }
  $e = $script:plan[$script:idx]
  $compteur.Text = ((T "Étape {0}/{1}") -f ($script:idx + 1), $script:nbEtapes) + " : $(T $e.Nom)..."
  $orb.Sub = (T "Étape {0}/{1}") -f ($script:idx + 1), $script:nbEtapes
  $hero.SetProg([float](100 * $script:idx / [math]::Max(1, $script:nbEtapes)))
  try { $orb.SetProgress([float]($script:idx / [math]::Max(1, $script:nbEtapes))) } catch {}
  $hD.Text = ((T "Étape {0}/{1}") -f ($script:idx + 1), $script:nbEtapes) + " · " + (T $e.Nom) + "..."
  Log "=== $($e.Nom) ==="
  if ($e.Url) { Start-Process $e.Url; Log "   Page officielle ouverte : $($e.Url)"; return }
  try { $script:proc = New-Object LkProc; $script:proc.Start($e.Fichier, $e.Args) }
  catch {
    # v5.6 : une étape qui ne démarre pas compte comme une erreur (avant : comptée comme réussie)
    Log "   Impossible de lancer : $($_.Exception.Message)"; $script:proc = $null
    $script:nbErreurs++; $script:etapesErreur += (T $e.Nom)
    if ($e.Nom -eq "Point de restauration") { $script:pointOk = $false }
  }
}

function Fin-Execution {
  $tMoteur.Stop(); $script:enCours = $false
  $fondProg.Value = 100
  Log "Tout est fini ! Redémarre le PC pour appliquer les changements. Journal : $fichierJournal"
  $compteur.ForeColor = $cVert; $compteur.Text = (T "Terminé. Redémarre le PC pour tout appliquer.")
  if ($script:arrete) { $compteur.ForeColor = $cOrange; $compteur.Text = (T "Arrêté : rien n'a été modifié.") }
  $bAppliquer.Busy = $false; $fondProg.Busy = $false
  $bAppliquer.Text = (T "TERMINÉ"); $bAppliquer.Enabled = $true
  $orb.Busy = $false; $bOpti.Busy = $false; $orb.Text = (T "TERMINÉ"); $orb.Sub = (T "Redémarre le PC")
  # après « Tout annuler », le bouton redevient OPTIMISER (l'appli n'est plus « optimisée »)
  if ($script:estRestauration) { $orb.Text = (T "OPTIMISER"); $orb.Sub = (T "Redémarre le PC") }
  foreach ($pl in $pillules.Values) { $pl.Enabled = $true }
  foreach ($sw in $toggles) { $sw.Enabled = $true }
  if ($script:arrete) { }
  elseif (-not $script:estRestauration) { Enregistrer-Pref "DerniereOptimisation" (Get-Date -Format "dd/MM HH:mm") } else { Enregistrer-Pref "DerniereOptimisation" "" }
  try { Maj-AlerteOptim } catch { Log "Alerte optimisation : $($_.Exception.Message)" }
  try { Maj-Alertes } catch {}
  # Après « Tout annuler » : relire Démarrage et Réseau au prochain affichage (état d'origine remis)
  if ($script:estRestauration) { foreach ($pn in "demarrage", "reseau") { $script:pages[$pn].Construite = $false }; if ($script:pageActive -in @("demarrage", "reseau")) { try { Afficher $script:pageActive -Forcer } catch {} } }
  $hero.SetProg(100); try { $orb.SetProgress(1) } catch {}; $hD.Text = $texteHero; $tCacheProg.Start()
  $duree = [math]::Max(1, [math]::Round(((Get-Date) - $script:debut).TotalMinutes))
  Log ("Résumé : " + $script:resume.Count + " élément(s), $duree min, $($script:nbErreurs) erreur(s).")
  if ($TestAuto) { [IO.File]::WriteAllText((Join-Path $dossierJournal "test-termine.txt"), $fichierJournal) }
  else { Afficher-Resume $duree }
}
$tCacheProg = New-Object Windows.Forms.Timer; $tCacheProg.Interval = 4000
$tCacheProg.Add_Tick({ $tCacheProg.Stop(); if (-not $script:enCours) { $hero.SetProg(-1); try { $orb.SetProgress(-1) } catch {}; try { Maj-Score } catch {} } })

# Fenêtre de résumé après OPTIMISER / APPLIQUER / Tout annuler : ce qui a été fait + redémarrage
function Afficher-Resume($duree) {
  $resto = $script:estRestauration
  $fr = New-Object Windows.Forms.Form; $fr.FormBorderStyle = "None"; $fr.StartPosition = "CenterParent"; $fr.ShowInTaskbar = $false
  $fr.BackColor = $cCarteSurvol; $fr.ClientSize = Sz 520 430; $fr.Font = Police 13; $fr.KeyPreview = $true; $fr.AutoScaleMode = "None"
  DoubleTampon $fr
  $cd = New-Object LkCard; $cd.Fill = $cCarte; $cd.Radius = S 16; $cd.Location = Pt 1 1; $cd.Size = Sz 518 428; $fr.Controls.Add($cd)
  $ok = ($script:nbErreurs -eq 0) -and -not $script:arrete
  $colR = if ($ok) { $cVert } else { $cOrange }
  $ic = Icone $cd $(if ($ok) { "check-circle" } else { "alert" }) 22 18 44 44 26 $colR $cCarte -Puce $colR
  $titre = if ($script:arrete) { T "Arrêté : rien n'a été modifié" } elseif ($resto) { T "Réglages d'origine remis" } elseif ($ok) { T "Optimisation terminée" } else { T "Terminé, avec des erreurs" }
  [void](Lbl $cd $titre 74 20 420 30 (Police 20 "Bold") $cBlanc $cCarte)
  $n = $script:resume.Count
  # v5.6 : « point de restauration créé » seulement s'il l'a vraiment été
  $sousT = if ($script:arrete) { T "Le point de restauration n'a pas pu être créé : tu as choisi de tout arrêter." }
    elseif ($script:sansPoint) { ((T "{0} élément(s) installé(s) en {1} min.") -f $n, $duree) }
    elseif ($resto) { ((T "{0} valeur(s) d'origine remise(s) en {1} min.") -f $n, $duree) }
    elseif ($script:pointOk) { ((T "{0} réglage(s) appliqué(s) en {1} min · point de restauration créé.") -f $n, $duree) }
    else { ((T "{0} réglage(s) appliqué(s) en {1} min · SANS point de restauration.") -f $n, $duree) }
  if ($script:arrete) { $script:resume = @(); $n = 0 }
  if ($script:titreResume) { $sousT = "$($script:titreResume) · $sousT" }
  [void](Lbl $cd $sousT 75 52 420 34 (Police 12) $cGris $cCarte)   # 2 lignes : jamais coupé
  $aff = @($script:resume | Select-Object -First 12 | ForEach-Object { [string][char]0x2713 + "  " + (T $_) })
  if ($n -gt $aff.Count) { $aff += "...  " + ((T "et {0} autre(s)") -f ($n - $aff.Count)) }
  # une ligne par réglage, avec la même icône « coche » que le reste de l'appli
  $yL = 94
  foreach ($l in $aff) {
    $tx = $l -replace "^\u2713  ", ""
    if ($l -match "^\u2713") { [void](Icone $cd "check" 26 ($yL + 1) 16 16 13 $colR $cCarte) }
    [void](Lbl $cd $tx 48 $yL 450 18 (Police 12.5) $cTexte2 $cCarte); $yL += 17
  }
  $msg = if ($script:nbErreurs) { "/!\ " + ((T "{0} étape(s) avec une erreur : {1}. Détails dans le Journal.") -f $script:nbErreurs, ($script:etapesErreur -join ", ")) } else { T "Redémarre le PC pour que tout soit pris en compte." }
  [void](Lbl $cd $msg 26 330 470 36 (Police 12) $(if ($script:nbErreurs) { $cOrange } else { $cGris }) $cCarte)
  $bR = Bouton $cd "Redémarrer maintenant" 26 370 220 42 -Principal
  $bP = Bouton $cd "Plus tard" 256 370 110 42
  $bJ = Bouton $cd "Voir le journal" 376 370 118 42
  $bR.Add_Click({ $fr.Tag = "redemarrer"; $fr.Close() })
  $bP.Add_Click({ $fr.Close() })
  $bJ.Add_Click({ $fr.Close(); Afficher "journal" })
  $fr.Add_KeyDown({ if ($_.KeyCode -eq "Escape") { $fr.Close() } })
  $cd.Add_MouseDown({ if ($_.Button -eq "Left") { [LkNative]::Drag($fr) } })
  Log ("Résumé affiché : $titre · $sousT")
  foreach ($l in $aff) { Log "   $l" }
  if ($env:LK_TEST) {
    # Tests : fenêtre non bloquante, refermée toute seule ; jamais de redémarrage
    $fr.Owner = $f; $fr.StartPosition = "Manual"; $fr.Location = New-Object Drawing.Point(($f.Left + [int](($f.Width - $fr.Width) / 2)), ($f.Top + [int](($f.Height - $fr.Height) / 2)))
    $fr.Show($f); $script:frResume = $fr
    $tR = New-Object Windows.Forms.Timer; $tR.Interval = 30000; $tR.Add_Tick({ $this.Stop(); try { $script:frResume.Close() } catch {} }); $tR.Start()
    return
  }
  [void]$fr.ShowDialog($f)
  if ($fr.Tag -eq "redemarrer") { Log "Redémarrage demandé."; Restart-Computer -Force }
}

$bAppliquer.Add_Click({
  if ($script:enCours) { return }
  $r = Construire-Plan
  # v5.6 : APPLIQUER prend les cases cochées de TOUTES les pages : on le dit, et on propose « seulement cette page »
  $pg = $script:pageActive
  $coches = @($toggles | Where-Object { $_.Checked -and $_.Enabled })
  $ici = @($coches | Where-Object { (Page-De $_) -eq $pg })
  $ailleurs = @($coches | Where-Object { (Page-De $_) -ne $pg })
  if ($ici.Count -and $ailleurs.Count) {
    $nomP = if ($nomsSousPages[$pg]) { T $nomsSousPages[$pg] } else { T $pages[$pg].Titre }
    $autres = @($ailleurs | ForEach-Object { $p2 = Page-De $_; if ($nomsSousPages[$p2]) { T $nomsSousPages[$p2] } elseif ($p2) { T $pages[$p2].Titre } } | Where-Object { $_ } | Select-Object -Unique)
    $msgP = (T "APPLIQUER prend en compte les cases cochées de TOUTES les pages.") + "`n`n" +
      ((T "Sur cette page (« {0} ») : {1} élément(s).") -f $nomP, $ici.Count) + "`n" +
      ((T "Sur d'autres pages ({0}) : {1} élément(s).") -f ($autres -join ", "), $ailleurs.Count) + "`n`n" +
      (T "Oui = tout appliquer") + "`n" + (T "Non = seulement cette page") + "`n" + (T "Annuler = ne rien faire")
    $rep = if ($TestAuto -or $env:LK_TEST) { if ($env:LK_APPLIQUER -eq "page") { "No" } else { "Yes" } } else { "$(Boite $msgP "YesNoCancel" "Question")" }
    if ($env:LK_TEST) { Log "[Test] Choix APPLIQUER : $rep ($($ici.Count) ici, $($ailleurs.Count) ailleurs)" }
    if ($rep -eq "Cancel") { return }
    if ($rep -eq "No") { $r = Construire-Plan @($ici | ForEach-Object { $_.Tag.Cle } | Select-Object -Unique) }
  }
  if (Confirmer-Plan $r) { Lancer-Plan $r.Plan -Resume $r.Liste }
})
function Lancer-Plan($plan, [switch]$Ici, $Resume = $null, $Titre = "", [switch]$SansPoint) {
  if ((Session-Active) -and -not $TestAuto) { [void](Boite (T "Une session de jeu est en cours : termine-la d'abord (Performance > Session de jeu), elle a fermé des applis et peut avoir changé le plan d'alimentation.")); return }
  $script:sansPoint = [bool]$SansPoint
  $script:enCours = $true; $script:plan = @($plan); $script:nbEtapes = $script:plan.Count; $script:idx = -1; $script:estRestauration = $false
  $script:resume = @($Resume | Where-Object { $_ }); $script:titreResume = $Titre; $script:nbErreurs = 0; $script:etapesErreur = @(); $script:debut = Get-Date
  $script:pointOk = $false; $script:arrete = $false
  $tCacheProg.Stop(); $hero.SetProg(0); try { $orb.SetProgress(0) } catch {}
  foreach ($e in $script:plan) { if ("$($e.Args)" -match '-Restaurer') { $script:estRestauration = $true } }
  foreach ($sw in $toggles) { $sw.Enabled = $false }
  $bAppliquer.Enabled = $false; $bAppliquer.Text = $(if ([LkAnim]::On) { T "EN COURS" } else { (T "EN COURS") + "..." }); $bAppliquer.Busy = $true
  $orb.Text = (T "EN COURS"); $orb.Sub = ""; $orb.Busy = $true; $bOpti.Busy = $true
  foreach ($pl in $pillules.Values) { $pl.Enabled = $false }
  $compteur.ForeColor = $cBlanc; $fondProg.Value = 0; $fondProg.Visible = $true; $fondProg.Busy = $true
  Log "Début : $($script:nbEtapes) étape(s)."
  if (-not $Ici) { Afficher "journal" }
  $tMoteur.Start()
}

# ===================== THÈME EN DIRECT =====================
# Remplace chaque couleur de l'ancienne palette par son équivalent dans la nouvelle, dans toute la fenêtre
function Appliquer-Theme([bool]$clair) {
  if ($clair -eq $script:themeClair) { return }
  $de = $palettes[$(if ($script:themeClair) { "clair" } else { "sombre" })]; $vers = $palettes[$(if ($clair) { "clair" } else { "sombre" })]
  $map = @{}; foreach ($k in $de.Keys) { $map[(Hex $de[$k]).ToArgb()] = Hex $vers[$k] }
  function M($col) { if ($col.IsEmpty) { return $col }; $n = $map[$col.ToArgb()]; if ($n) { return $n } else { return $col } }
  [LkCard]::Instant = $true; Geler $f $true
  try {
  $pile = New-Object System.Collections.Stack; $pile.Push($f)
  if ($script:frResume -and -not $script:frResume.IsDisposed) { $pile.Push($script:frResume) }   # fenêtre de résumé ouverte : suit le thème aussi
  while ($pile.Count) {
    $c = $pile.Pop()
    if ($c -is [LkCard]) { $c.HoverFill = M $c.HoverFill; $c.Border = M $c.Border; $c.HoverBorder = M $c.HoverBorder; $c.SetFill((M $c.Fill)) }
    elseif ($c -is [LkHero]) { $c.Fill = M $c.Fill; $c.Border = M $c.Border; $c.BackColor = M $c.BackColor; $c.Invalidate() }
    elseif ($c -is [LkSection]) { $c.Line = M $c.Line; $c.BackColor = M $c.BackColor; $c.Invalidate() }
    elseif ($c -is [LkToggle]) { $c.OffColor = M $c.OffColor; $c.Invalidate() }
    elseif ($c -is [LkBar]) { $c.Track = M $c.Track; $c.Invalidate() }
    elseif ($c -is [LkButton]) { $c.Fill = M $c.Fill; $c.HoverFill = M $c.HoverFill; $c.ForeColor = M $c.ForeColor; $c.Invalidate() }
    elseif ($c -is [LkIndicator]) { $c.Fill = M $c.Fill; $c.Invalidate() }
    elseif ($c -is [LkNav]) { $c.HoverFill = M $c.HoverFill; $c.ActiveFill = M $c.ActiveFill; $c.ActiveFore = M $c.ActiveFore; $c.Invalidate() }
    else {
      if ($c -is [LkScroll]) { $c.Thumb = M $c.Thumb }
      if ($c -is [LkIcon]) { $c.Chip = M $c.Chip }
      $c.BackColor = M $c.BackColor
    }
    if (-not ($c -is [LkButton])) { $c.ForeColor = M $c.ForeColor }
    foreach ($e in $c.Controls) { $pile.Push($e) }
  }
  $bMini.Tag = M $bMini.Tag
  $script:themeClair = $clair
  Charger-Palette $clair
  [LkCard]::BordDefaut = $cBord; [LkCard]::BordSurvolDefaut = $cBordSurvol
  Remplir-Bios
  try { [void][LkNative]::SetWindowTheme($log.Handle, $(if ($clair) { "Explorer" } else { "DarkMode_Explorer" }), $null) } catch {}
  [LkBadge]::Light = $clair
  if ($script:pageActive) { Afficher $script:pageActive -Forcer }
  try { Maj-Alertes } catch {}
  Enregistrer-Pref "Theme" $(if ($clair) { "clair" } else { "sombre" })
  } finally { [LkCard]::Instant = $false; Geler $f $false }
  $f.Invalidate($true)
  Log "Thème $(if ($clair) { 'clair' } else { 'sombre' }) activé."
}

# ===================== LANGUE =====================
function Changer-Langue($lg) {
  if ($lg -eq $script:langue) { return }
  if ($script:enCours) { [void](Boite (T "Attends la fin de l'opération en cours.")); return }
  Enregistrer-Pref "Langue" $lg
  Log "Langue : $lg (redémarrage de l'interface)."
  Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
  [LkAnim]::Closing = $true; $f.Close()
}

# ===================== TOUT ANNULER =====================
function Tout-Annuler {
  if ($script:enCours) { [void](Boite (T "Attends la fin de l'opération en cours.")); return }
  $liste = @(Resume-Sauvegarde)
  if (-not $liste.Count) { [void](Boite (T "Rien à annuler : aucun réglage n'a encore été modifié par LuKZyR Optimisation (ou tout a déjà été restauré).")); return }
  $aff = @($liste | Select-Object -First 22)
  $msg = (T "Ces réglages vont retrouver leur valeur d'origine :") + "`n`n - " + ($aff -join "`n - ")
  if ($liste.Count -gt $aff.Count) { $msg += "`n - ... " + ((T "et {0} autre(s)") -f ($liste.Count - $aff.Count)) }
  $msg += "`n`n" + (T "Ne peuvent PAS être annulés : applis supprimées ou installées, Edge, fichiers temporaires effacés. Pour ça, utilise « Restaurer le système ».")
  if (-not $TestAuto -and -not $env:LK_TEST) { if ((Boite ($msg + "`n`n" + (T "Tout annuler maintenant ?")) "YesNo" "Warning") -ne "Yes") { return } }
  Log "Tout annuler : $($liste.Count) élément(s) à restaurer."
  Lancer-Plan @((EtapeScript "Restauration des réglages d'origine" "Sauvegarde-Reglages.ps1" "-Restaurer -NonInteractif")) -Ici:($script:pageActive -eq "accueil") -Resume $liste
}

# ===================== MISE À JOUR DE L'APPLI =====================
# Vérification en arrière-plan (jamais bloquante, jamais d'erreur au démarrage si hors ligne)
$etatMaj = [hashtable]::Synchronized(@{ Statut = ""; Version = ""; Build = ""; Source = ""; Url = ""; Notes = ""; Fichier = ""; Erreur = ""; Sha256 = "" })
# v5.6 : https obligatoire (version.json ET zip), délai court, empreinte SHA-256 vérifiée si version.json la donne,
# toutes les erreurs restent dans le fil d'arrière-plan (jamais d'exception sur l'interface)
function Url-Https($u) { $x = $null; return ([Uri]::TryCreate("$u".Trim(), [UriKind]::Absolute, [ref]$x) -and $x.Scheme -eq "https") }
function Url-MiseAJour {
  $u = $UrlMiseAJourDefaut
  try { $cf = Join-Path $env:ProgramData "Lukzyr\config.json"; if (Test-Path $cf) { $j = Get-Content $cf -Raw | ConvertFrom-Json; if ($j.urlMiseAJour) { $u = "$($j.urlMiseAJour)" } } } catch {}
  return "$u".Trim()
}
$script:travauxMaj = New-Object System.Collections.ArrayList
function Lancer-Arriere($bloc, $arguments) {
  try {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open(); $rs.SessionStateProxy.SetVariable("etat", $etatMaj)
    $psA = [powershell]::Create(); $psA.Runspace = $rs; [void]$psA.AddScript($bloc)
    foreach ($arg in $arguments) { [void]$psA.AddArgument($arg) }
    [void]$script:travauxMaj.Add(@{ PS = $psA; H = $psA.BeginInvoke() })
    $tMaj.Start()
  } catch { $etatMaj.Statut = "erreur"; $etatMaj.Erreur = $_.Exception.Message }
}
# v5.7 : fonctions communes aux deux lectures (exécutées dans le fil d'arrière-plan)
$codeReseauMaj = {
  # TLS 1.2 ajouté (sans retirer TLS 1.3 s'il existe) : PowerShell 5.1 propose parfois encore TLS 1.0 seul
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }
  function Lire-Https($url, $accept) {
    $rq = [Net.HttpWebRequest]::Create($url); $rq.Timeout = 10000; $rq.ReadWriteTimeout = 10000; $rq.AllowAutoRedirect = $true
    $rq.UserAgent = "LuKZyR-Optimisation"   # obligatoire pour l'API GitHub
    if ($accept) { $rq.Accept = $accept }
    $rq.Headers.Add("Cache-Control", "no-cache")
    try { $rq.Proxy = [Net.WebRequest]::GetSystemWebProxy(); $rq.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials } catch {}
    $rp = $rq.GetResponse()
    try {
      if ($rp.ResponseUri.Scheme -ne "https") { throw "redirection hors https refusée" }
      $sr = New-Object IO.StreamReader($rp.GetResponseStream(), [Text.Encoding]::UTF8); $txt = $sr.ReadToEnd(); $sr.Close()
    } finally { $rp.Close() }
    if ($txt.Length -gt 262144) { throw "réponse trop grosse" }
    return $txt
  }
  # message clair en français à partir de l'erreur réseau
  function Raison($ex) {
    $e = $ex; while ($e.InnerException -and -not ($e -is [Net.WebException])) { $e = $e.InnerException }
    if ($e -is [Net.WebException]) {
      $code = 0; try { if ($e.Response) { $code = [int]$e.Response.StatusCode } } catch {}
      switch ("$($e.Status)") {
        "NameResolutionFailure" { return "pas de connexion Internet (adresse introuvable)" }
        "Timeout" { return "le serveur n'a pas répondu en 10 s" }
        "ConnectFailure" { return "serveur injoignable (pare-feu, proxy ou antivirus ?)" }
        "TrustFailure" { return "connexion sécurisée refusée (date et heure du PC, ou antivirus qui inspecte le HTTPS ?)" }
        "SecureChannelFailure" { return "connexion sécurisée (TLS 1.2) impossible" }
        "ProtocolError" {
          if ($code -eq 404) { return "fichier introuvable sur GitHub (404)" }
          if ($code -eq 403 -or $code -eq 429) { return "GitHub limite les vérifications pour l'instant ($code), réessaie dans une heure" }
          return "réponse du serveur : erreur $code"
        }
      }
    }
    for ($x = $ex; $x; $x = $x.InnerException) {
      if ($x -is [Net.Sockets.SocketException]) { return "pas de connexion Internet ou serveur injoignable" }
      if ($x -is [Security.Authentication.AuthenticationException]) { return "connexion sécurisée (TLS) impossible : date et heure du PC, ou antivirus qui inspecte le HTTPS ?" }
      if ($x -is [TimeoutException]) { return "le serveur n'a pas répondu en 10 s" }
    }
    if ($e -is [Net.WebException]) { return "$($e.Message)" }
    return "$($ex.Message)"
  }
  # versions « 0.1 », « 0.1.2 », « v0.2 bêta », « LuKZyR Optimisation v0.1 beta » ; une finale passe avant la bêta du même numéro
  function Num($v) { $m = [regex]::Match("$v", '\d+(\.\d+){0,3}'); if (-not $m.Success) { return $null }; $x = $m.Value; while (($x -split '\.').Count -lt 3) { $x += ".0" }; try { [version]$x } catch { $null } }
  function Beta($v) { "$v" -match '(?i)b[eêè]ta|alpha|\brc\d*\b|pre' }
  function Comparer($vd, $bd, $vl, $bl, $betaL) {
    $nd = Num $vd; $nl = Num $vl
    if (-not $nd) { return "illisible" }
    if ($nd -gt $nl) { return "dispo" }
    if ($nd -lt $nl) { return "ajour" }
    if ($betaL -and -not (Beta $vd)) { return "dispo" }          # 0.1 finale > 0.1 bêta
    # v5.7 : même version publique (v0.1 bêta pour tous les builds) : on compare le build interne (5.6, 5.7...)
    $bD = Num $bd; $bL = Num $bl
    if ($bD -and $bL -and $bD -gt $bL) { return "dispo" }
    return "ajour"
  }
}
function Verifier-MiseAJour {
  $u = Url-MiseAJour
  if (-not $u) { $etatMaj.Statut = "aucun"; Maj-AffichageMaj; return }
  if (-not (Url-Https $u)) { $etatMaj.Statut = "erreur"; $etatMaj.Erreur = "adresse refusée (https obligatoire) : $u"; Maj-AffichageMaj; return }
  if ($etatMaj.Statut -in @("verif", "telechargement")) { return }
  $etatMaj.Statut = "verif"; $etatMaj.Erreur = ""; $etatMaj.Build = ""; $etatMaj.Source = ""; Maj-AffichageMaj
  $bloc = [scriptblock]::Create($codeReseauMaj.ToString() + "`n" + {
    $url, $urlRel, $versionApp, $betaApp, $buildApp = $args   # (param() impossible : le bloc commence par les fonctions communes)
    $raisons = @()
    function Verifier-Lien($l) { $ux = $null; return ([Uri]::TryCreate("$l", [UriKind]::Absolute, [ref]$ux) -and $ux.Scheme -eq "https" -and $ux.AbsolutePath -match '\.zip$') }
    # 1. version.json du dépôt
    try {
      $j = (Lire-Https $url "application/json") | ConvertFrom-Json
      $v = "$($j.version)"; $b = "$($j.build)"; $lien = "$($j.url)".Trim(); $sha = ("$($j.sha256)" -replace '\s', '').ToLower()
      if (-not (Verifier-Lien $lien)) { throw "lien de téléchargement refusé dans version.json (https et .zip obligatoires)" }
      if ($sha -and $sha -notmatch '^[0-9a-f]{64}$') { throw "empreinte sha256 illisible dans version.json" }
      $r = Comparer $v $b $versionApp $buildApp $betaApp
      if ($r -eq "illisible") { throw "numéro de version illisible dans version.json : $v" }
      $etat.Version = $v; $etat.Build = $b; $etat.Url = $lien; $etat.Notes = "$($j.notes)"; $etat.Sha256 = $sha; $etat.Source = "version.json"; $etat.Statut = $r
      return
    } catch { $raisons += "version.json : " + (Raison $_.Exception) }
    # 2. releases GitHub (titre ou tag « v0.1 beta », fichier .zip joint)
    if ($urlRel) {
      try {
        $rels = @((Lire-Https $urlRel "application/vnd.github+json") | ConvertFrom-Json) | Where-Object { $_ -and -not $_.draft }
        $rel = $null; foreach ($x in $rels) { if (Num "$($x.name) $($x.tag_name)") { $rel = $x; break } }
        if (-not $rel) { throw "aucune release avec un numéro de version" }
        $nomV = if (Num "$($rel.name)") { "$($rel.name)" } else { "$($rel.tag_name)" }
        $zip = @($rel.assets | Where-Object { "$($_.name)" -match '\.zip$' -and "$($_.browser_download_url)" -match '^https://' }) | Select-Object -First 1
        $r = Comparer $nomV "" $versionApp $buildApp $betaApp
        $etat.Version = ("$nomV" -replace '(?i)^.*?(v?\d+(\.\d+){0,3}.*)$', '$1').Trim(); $etat.Build = ""; $etat.Notes = "$($rel.body)"; $etat.Sha256 = ""; $etat.Source = "releases"
        $etat.Url = if ($zip) { "$($zip.browser_download_url)" } else { "" }
        if ($r -eq "dispo" -and -not $etat.Url) { $r = "ajour"; $raisons += "release sans fichier .zip" }
        $etat.Statut = $r
        return
      } catch { $raisons += "releases GitHub : " + (Raison $_.Exception) }
    }
    $etat.Statut = "erreur"; $etat.Erreur = ($raisons -join " ; ")
  }.ToString())
  Lancer-Arriere $bloc @($u, $(if ($u -eq $UrlMiseAJourDefaut) { $UrlReleasesDefaut } else { "" }), $VersionApp, $VersionBeta, $VersionInterne)
}
function Telecharger-MiseAJour {
  try {
    if (-not $etatMaj.Url -or -not (Url-Https $etatMaj.Url)) { return }
    $bureau = [Environment]::GetFolderPath("Desktop")
    $nomZip = [IO.Path]::GetFileName(([uri]$etatMaj.Url).AbsolutePath) -replace '[^\w\.\-]', '_'
    if ($nomZip -notmatch '\.zip$') { $nomZip = "LuKZyR-Optimisation-v$($etatMaj.Version -replace '[^\w\.\-]', '_').zip" }
    $etatMaj.Fichier = Join-Path $bureau $nomZip; $etatMaj.Statut = "telechargement"; Maj-AffichageMaj
  } catch { $etatMaj.Statut = "erreur"; $etatMaj.Erreur = $_.Exception.Message; Maj-AffichageMaj; return }
  $blocT = [scriptblock]::Create($codeReseauMaj.ToString() + "`n" + {
    $url, $dest, $sha = $args
    $tmp = "$dest.part"
    try {
      $rq = [Net.HttpWebRequest]::Create($url); $rq.Timeout = 15000; $rq.ReadWriteTimeout = 30000; $rq.UserAgent = "LuKZyR-Optimisation"
      try { $rq.Proxy = [Net.WebRequest]::GetSystemWebProxy(); $rq.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials } catch {}
      $rp = $rq.GetResponse()
      try {
        if ($rp.ResponseUri.Scheme -ne "https") { throw "redirection hors https refusée" }
        $in = $rp.GetResponseStream(); $out = [IO.File]::Create($tmp)
        try { $in.CopyTo($out) } finally { $out.Close(); $in.Close() }
      } finally { $rp.Close() }
      if ($sha) {
        $h = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $sha) { Remove-Item -LiteralPath $tmp -Force; throw "empreinte SHA-256 différente : fichier supprimé" }
      }
      Move-Item -LiteralPath $tmp -Destination $dest -Force
      $etat.Statut = "telecharge"
    } catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; $etat.Statut = "erreur"; $etat.Erreur = "téléchargement : " + (Raison $_.Exception) }
  }.ToString())
  Lancer-Arriere $blocT @($etatMaj.Url, $etatMaj.Fichier, $etatMaj.Sha256)
}
# Bandeau « nouvelle version » (en haut à droite)
$banniere = New-Object LkCard; $banniere.Fill = $cNavActif; $banniere.Radius = S 12; $banniere.Location = Pt 636 14; $banniere.Size = Sz 332 56; $banniere.Visible = $false; $script:banniereOn = $false
$lBan = Lbl $banniere "" 14 8 170 40 (Police 12 "Bold") $cBlanc $cNavActif
$bBan = New-Object LkButton; $bBan.Text = (T "Télécharger"); $bBan.Font = Police 12 "Bold"; $bBan.Radius = S 10
$bBan.Location = Pt 190 10; $bBan.Size = Sz 130 36; $bBan.Fill = $cAccent; $bBan.Fill2 = $cAccent2; $bBan.HoverFill = Hex "#7a40ee"
$banniere.Controls.Add($bBan); $main.Controls.Add($banniere); $banniere.BringToFront()
$bBan.Add_Click({ if ($etatMaj.Statut -eq "telecharge") { Start-Process explorer.exe "/select,`"$($etatMaj.Fichier)`"" } elseif ($etatMaj.Statut -eq "dispo") { Telecharger-MiseAJour } })
$script:statutVu = ""
# v5.7 : raisons d'échec de la mise à jour traduites morceau par morceau (elles viennent du fil d'arrière-plan)
$fragmentsMaj = @(
  'connexion sécurisée (TLS) impossible : date et heure du PC, ou antivirus qui inspecte le HTTPS ?',
  'connexion sécurisée refusée (date et heure du PC, ou antivirus qui inspecte le HTTPS ?)',
  'lien de téléchargement refusé dans version.json (https et .zip obligatoires)',
  'pas de connexion Internet ou serveur injoignable',
  'serveur injoignable (pare-feu, proxy ou antivirus ?)',
  'pas de connexion Internet (adresse introuvable)',
  'numéro de version illisible dans version.json',
  'empreinte sha256 illisible dans version.json',
  'GitHub limite les vérifications pour l''instant',
  'aucune release avec un numéro de version',
  'connexion sécurisée (TLS 1.2) impossible',
  'le serveur n''a pas répondu en 10 s',
  'fichier introuvable sur GitHub (404)',
  'adresse refusée (https obligatoire)',
  'réponse du serveur : erreur',
  'réessaie dans une heure',
  'release sans fichier .zip',
  'réponse trop grosse',
  'releases GitHub',
  'téléchargement'
)
function Trad-Raison($s) { $s = "$s"; if ($script:langue -ne "en") { return $s }; foreach ($k in $fragmentsMaj) { $s = $s.Replace($k, (T $k)) }; return $s }
function Maj-AffichageMaj {
  $st = $etatMaj.Statut
  $txt = switch ($st) {
    "aucun" { T "Aucun serveur de mise à jour configuré." }
    "verif" { T "Vérification en cours..." }
    "ajour" { (T "Tu as la dernière version") + " ($(Version-Affichee), build $VersionInterne)." }
    "dispo" { (T "Nouvelle version disponible") + " : $($etatMaj.Version)" + $(if ($etatMaj.Build) { " (build $($etatMaj.Build))" } else { "" }) }
    "telechargement" { T "Téléchargement en cours..." }
    "telecharge" { (T "Téléchargée sur le Bureau") + " : $([IO.Path]::GetFileName($etatMaj.Fichier))" }
    "erreur" { (T "Vérification impossible") + " : $(Trad-Raison $etatMaj.Erreur). " + (T "L'appli marche normalement.") }
    default { "" }
  }
  if ($txt) { $oMaj.Desc.Text = $txt; $oMaj.Desc.ForeColor = $(switch ($st) { "dispo" { $cAccentClair } "erreur" { $cOrange } "ajour" { $cVert } default { $cGris } }); $tip.SetToolTip($oMaj.Desc, $txt) }
  $bMajVerif.Enabled = ($st -notin @("verif", "telechargement"))
  # v5.7 : runspaces terminés libérés ; minuteur arrêté quand rien n'est en cours (avant : 1 tic par seconde, à vie)
  foreach ($j in @($script:travauxMaj)) { if ($j.H.IsCompleted) { try { $j.PS.Runspace.Close(); $j.PS.Dispose() } catch {}; [void]$script:travauxMaj.Remove($j) } }
  if ($st -notin @("verif", "telechargement") -and -not $script:travauxMaj.Count) { $tMaj.Stop() }
  if ($st -in @("dispo", "telechargement", "telecharge")) {
    $lBan.Text = $(switch ($st) { "dispo" { (T "Version") + " $($etatMaj.Version) " + (T "disponible") } "telechargement" { T "Téléchargement..." } default { T "Zip enregistré sur le Bureau" } })
    $bBan.Text = $(if ($st -eq "telecharge") { T "Ouvrir" } else { T "Télécharger" }); $bBan.Enabled = ($st -ne "telechargement")
    if (-not $script:banniereOn) { $script:banniereOn = $true; if ($script:pageActive -ne "accueil") { $banniere.Visible = $true; $banniere.BringToFront() } }
  }
  if ($st -ne $script:statutVu) {
    $script:statutVu = $st
    if ($st -in @("dispo", "telechargement", "telecharge")) { try { Maj-Alertes } catch {} }
    if ($st -eq "erreur") { Log "Mise à jour : vérification impossible ($($etatMaj.Erreur))." } elseif ($st -eq "telecharge") { Log "Mise à jour téléchargée : $($etatMaj.Fichier)"; Start-Process explorer.exe "/select,`"$($etatMaj.Fichier)`"" } elseif ($txt -and $st -ne "verif") { Log "Mise à jour : $txt" }
  }
}
$tMaj = New-Object Windows.Forms.Timer; $tMaj.Interval = 1000; $tMaj.Add_Tick({ Maj-AffichageMaj })

# ===================== RECHERCHE D'UN RÉGLAGE (v5.1) =====================
# Champ en haut à droite des pages de section (Ctrl+F) : cherche dans les titres et descriptions
# de tous les réglages et dans les noms de pages ; Entrée ou clic = aller au réglage (il clignote).
function Sans-Accents($t) {
  $n = "$t".ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  return (-join ($n.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne "NonSpacingMark" }))
}
$rech = New-Object LkCard; $rech.Fill = $cCarte; $rech.HoverFill = $cCarteSurvol; $rech.Radius = S 10; $rech.Location = Pt 16 72; $rech.Size = Sz 200 36
$nav.Controls.Add($rech)   # v5.8 : dans la barre latérale, toujours visible
$rIc = Icone $rech "search" 9 0 24 36 16 $cGris $cCarte
$tbRech = New-Object Windows.Forms.TextBox; $tbRech.BorderStyle = "None"; $tbRech.BackColor = $cCarte; $tbRech.ForeColor = $cBlanc; $tbRech.Font = Police 12.5
$tbRech.Location = Pt 36 9; $tbRech.Size = Sz 156 20
$rech.Controls.Add($tbRech)
$rPh = Lbl $rech "Rechercher (Ctrl+F)" 36 0 158 36 (Police 12) $cGris2 $cCarte; $rPh.TextAlign = "MiddleLeft"; $rPh.Cursor = "IBeam"
$rPh.Add_Click({ $tbRech.Focus() }); $rIc.Add_Click({ $tbRech.Focus() })
$rPh.BringToFront()
$script:listeRech = New-Object LkCard; $script:listeRech.Fill = $cCarteSurvol; $script:listeRech.Radius = S 10; $script:listeRech.Location = Pt 12 16; $script:listeRech.Size = Sz 268 40; $script:listeRech.Visible = $false
$main.Controls.Add($script:listeRech)
$script:resultats = @()
function Page-De($ctrl) {
  $map = @{}; foreach ($k in $pages.Keys) { $pn = $pages[$k].Panel; $map[$pn] = $k; if ($pn -is [LkScroll]) { $map[$pn.Content] = $k } }
  $c = $ctrl; while ($c) { if ($map.ContainsKey($c)) { return $map[$c] }; $c = $c.Parent }
  return $null
}
function Index-Recherche {
  $l = @()
  foreach ($k in $pages.Keys) {
    if ($k -eq "accueil") { continue }
    $nomP = if ($nomsSousPages[$k]) { T $nomsSousPages[$k] } else { T $pages[$k].Titre }
    $l += @{ Texte = $nomP; Info = (T "Page"); Cle = (Sans-Accents "$nomP $(T $pages[$k].Sous)"); Page = $k; Ctrl = $null }
  }
  foreach ($sw in $toggles) {
    $pg = Page-De $sw; if (-not $pg) { continue }
    $nomP = if ($nomsSousPages[$pg]) { T $nomsSousPages[$pg] } else { T $pages[$pg].Titre }
    $l += @{ Texte = (T $sw.Tag.Titre); Info = $nomP; Cle = (Sans-Accents "$(T $sw.Tag.Titre) $(T $sw.Tag.Desc)"); Page = $pg; Ctrl = $sw }
  }
  return $l
}
function Chercher($texte) {
  $lr = $script:listeRech; Vider $lr; $script:resultats = @()
  $q = (Sans-Accents $texte).Trim()
  if ($q.Length -lt 2) { $lr.Visible = $false; return }
  if (-not $script:index) { $script:index = Index-Recherche }
  $mots = $q -split '\s+'
  $tr = @($script:index | Where-Object { $e = $_; -not @($mots | Where-Object { $e.Cle -notlike "*$_*" }).Count })
  # Titres qui commencent par la recherche en premier
  # (toujours un tableau : avec 1 seul résultat, PowerShell rendrait la table elle-même)
  $tr = @(@($tr | Sort-Object { if ((Sans-Accents $_.Texte).StartsWith($q)) { 0 } else { 1 } }, { if ($_.Ctrl) { 0 } else { 1 } }) | Select-Object -First 7)
  $script:resultats = $tr
  $y = 4
  if (-not $tr.Count) { [void](Lbl $lr "Aucun réglage trouvé." 12 $y 244 32 (Police 12) $cGris $cCarteSurvol); $y += 34 }
  for ($i = 0; $i -lt $tr.Count; $i++) {
    $e = $tr[$i]
    $row = New-Object LkCard; $row.Fill = $cCarteSurvol; $row.HoverFill = $cNavActif; $row.Radius = S 8; $row.Location = Pt 4 $y; $row.Size = Sz 260 42; $row.Cursor = "Hand"; $row.Tag = $i
    $t1 = Lbl $row $e.Texte 10 4 240 19 (Police 12.5 "Bold") $cBlanc $cCarteSurvol
    $t2 = Lbl $row $e.Info 10 22 240 16 (Police 10.5) $cGris $cCarteSurvol
    foreach ($el in $row, $t1, $t2) { $el.Cursor = "Hand"; $el.Tag = $i; $el.Add_Click({ Aller-A $script:resultats[[int]$this.Tag] }); Survol-Carte $el }
    $lr.Controls.Add($row); $y += 44
  }
  $lr.Height = S ($y + 4); $lr.Visible = $true; $lr.BringToFront()
}
function Aller-A($e) {
  if (-not $e) { return }
  $script:listeRech.Visible = $false; $tbRech.Text = ""
  Afficher $e.Page
  [LkFade]::StopAll()   # v5.7 : on va défiler jusqu'au réglage : pas d'instantané de l'ancienne position
  if ($e.Ctrl) {
    $carte = $e.Ctrl.Parent; $panneau = $pages[$e.Page].Panel
    if ($panneau -is [LkScroll]) { $panneau.ScrollTo([math]::Max(0, $carte.Top - (S 36))) }
    $carte.SetFill($cNavActif); $script:carteFlash = $carte; $tFlash.Stop(); $tFlash.Start()
  }
  Log ((T "Recherche : aller à") + " « $($e.Texte) » ($($e.Info))")
}
$tFlash = New-Object Windows.Forms.Timer; $tFlash.Interval = 1400
$tFlash.Add_Tick({ $tFlash.Stop(); if ($script:carteFlash) { $script:carteFlash.SetFill($cCarte); $script:carteFlash = $null } })
$tbRech.Add_TextChanged({ $rPh.Visible = ($tbRech.Text.Length -eq 0); Chercher $tbRech.Text })
$tbRech.Add_KeyDown({
  if ($_.KeyCode -eq "Enter") { $_.SuppressKeyPress = $true; if ($script:resultats.Count) { Aller-A $script:resultats[0] } }
  elseif ($_.KeyCode -eq "Escape") { $_.SuppressKeyPress = $true; $tbRech.Text = ""; $script:listeRech.Visible = $false }
})
$tbRech.Add_LostFocus({ $tCacheRech.Stop(); $tCacheRech.Start() })
$tCacheRech = New-Object Windows.Forms.Timer; $tCacheRech.Interval = 250
$tCacheRech.Add_Tick({ $tCacheRech.Stop(); if (-not $tbRech.Focused) { $script:listeRech.Visible = $false } })
$f.Add_KeyDown({
  if ($_.Control -and $_.KeyCode -eq "F") {
    $_.SuppressKeyPress = $true
    $tbRech.Focus(); $tbRech.SelectAll()
  }
})

# ===================== DÉMARRAGE =====================
Etape-Chargement 95 99 "Finitions..."
foreach ($k in @($pages.Keys)) { $p = $pages[$k].Panel; if ($p -is [LkScroll]) { $p.Recalc() } }
$f.Add_Shown({ foreach ($k in @($pages.Keys)) { $p = $pages[$k].Panel; if ($p -is [LkScroll]) { $p.Recalc() } }; MajStats })
$f.Add_FormClosing({
  if ([LkAnim]::Closing) { return }   # 2e passage, après le fondu
  if ((Session-Active) -and -not $TestAuto -and -not $env:LK_TEST) {
    $rs = Boite ((T "Une session de jeu est en cours.") + "`n`n" + (T "La terminer maintenant (relancer les applis fermées, remettre le plan d'alimentation) ?") + "`n`n" + (T "Non = la garder : elle sera proposée au prochain lancement.")) "YesNoCancel" "Question"
    if ("$rs" -eq "Cancel") { $_.Cancel = $true; return }
    if ("$rs" -eq "Yes") { try { Terminer-Session } catch {} }
  }
  if (-not $env:LK_TEST -and -not $TestAuto) {
    if ($script:pageActive) { Enregistrer-Pref "DernierePage" $script:pageActive }
    if ($f.WindowState -eq "Normal") { Enregistrer-Pref "FenetreX" "$($f.Left)"; Enregistrer-Pref "FenetreY" "$($f.Top)" }
  }
  if ($script:enCours -and -not $TestAuto) {
    if ((Boite ((T "Une opération est en cours. Quitter quand même ?") + "`n`n" + (T "L'étape en cours sera arrêtée (avec tout ce qu'elle a lancé) et peut rester à moitié faite.")) "YesNo" "Warning") -ne "Yes") { $_.Cancel = $true; return }
  }
  # v5.6 : fermer l'appli arrête aussi le script en cours et ses processus enfants (winget, DISM, installeurs...)
  if ($script:proc) { $tMoteur.Stop(); Log "Fermeture : arrêt de l'étape en cours."; try { $script:proc.KillTree() } catch {}; $script:proc = $null; $script:enCours = $false }
  # Fermeture en fondu (180 ms), puis vraie fermeture
  if ([LkAnim]::On -and $_.CloseReason -eq "UserClosing") { $_.Cancel = $true; [LkAnim]::FadeClose($f, 180) }
})
# Ouverture en fondu (250 ms)
if ([LkAnim]::On) { $f.Opacity = 0 }
$f.Add_Shown({ [LkAnim]::FadeIn($f, 250) })
# v5.2 : l'écran de chargement termine sa barre et s'efface pendant que la fenêtre apparaît
# v5.3 : + filet de sécurité : fermeture forcée 2 s après l'affichage, et à la fermeture de la fenêtre
$tFinChg = New-Object Windows.Forms.Timer; $tFinChg.Interval = 3500
$tFinChg.Add_Tick({ $tFinChg.Stop(); $tPretChg.Stop(); Fermer-Chargement })
# l'écran ne s'efface qu'une fois la fenêtre entièrement opaque (fondu d'entrée fini) : pas de bureau entre les deux
$tPretChg = New-Object Windows.Forms.Timer; $tPretChg.Interval = 40
$tPretChg.Add_Tick({ if ($f.Opacity -ge 0.99) { $tPretChg.Stop(); $f.Update(); Pret-Chargement } })
$f.Add_Shown({ $script:fenetreVue = $true; Fin-Chargement; $tFinChg.Start(); $tPretChg.Start(); $f.Activate() })
$f.Add_FormClosed({ Fermer-Chargement })
# v5.5 : fenêtre réduite ou inactive => pulsations en pause (reprennent au retour)
$script:fActive = $true
function Maj-PauseAnim { [LkAnim]::Pause = ($f.WindowState -eq "Minimized") -or -not $script:fActive }
$f.Add_Activated({ $script:fActive = $true; Maj-PauseAnim })
$f.Add_Deactivate({ $script:fActive = $false; Maj-PauseAnim })
$f.Add_Resize({ Maj-PauseAnim; try { Maj-Moniteur } catch {} })
$tSessionRestee = New-Object Windows.Forms.Timer; $tSessionRestee.Interval = 1800
$tSessionRestee.Add_Tick({
  $tSessionRestee.Stop()
  if (-not (Session-Active) -or $TestAuto -or $env:LK_TEST) { return }
  $e = Lire-Session
  $msg = (T "Une session de jeu n'a pas été terminée") + $(if ($e.Debut) { " (" + ((T "démarrée le {0}") -f ([datetime]"$($e.Debut)").ToString("dd/MM HH:mm")) + ")" } else { "" }) + ".`n`n" + (T "La terminer maintenant (relancer les applis fermées, remettre le plan d'alimentation) ?")
  if ((Boite $msg "YesNo" "Question") -eq "Yes") { Terminer-Session } else { Maj-Session }
})
$f.Add_Shown({ $tSessionRestee.Start(); try { Maj-Moniteur } catch {} })
# Mise à jour : vérifiée 1,5 s après l'ouverture, en arrière-plan
$f.Add_Shown({ $tMaj.Start(); Verifier-MiseAJour })
# Alertes du Tableau de bord : lues juste après l'ouverture (sans retarder l'affichage)
$tAlertes = New-Object Windows.Forms.Timer; $tAlertes.Interval = 400
$tAlertes.Add_Tick({ $tAlertes.Stop(); try { Maj-Alertes } catch { Log "Alertes : $($_.Exception.Message)" }; try { Maj-Score } catch { Log "Score : $($_.Exception.Message)" } })
$f.Add_Shown({ $tAlertes.Start() })
MajCompteur
Log "LuKZyR Optimisation $(Version-Affichee) (build $VersionInterne) - matériel détecté : $cpuNom / $(if ($gpuNom) { $gpuNom } else { 'GPU non détecté' })"
Log ("Écran de chargement : " + $(if ($script:modeChargement) { $script:modeChargement } else { "aucun" }) + $(if ($script:erreurChargement) { " ($($script:erreurChargement))" } else { "" }))
foreach ($x in $script:erreursDetection) { Log ("/!\ " + (T "Détection incomplète (l'appli reste utilisable)") + " - $x") }
# v5.1 : rouvre la dernière page et à la même position (si elle est toujours sur un écran)
$pageDepart = "accueil"
if (-not $env:LK_TEST -and -not $TestAuto) {
  $dp = "$($prefs.DernierePage)"; if ($dp -and $pages.Contains($dp)) { $pageDepart = $dp }
  try {
    $fx = [int]"$($prefs.FenetreX)"; $fy = [int]"$($prefs.FenetreY)"
    if ("$($prefs.FenetreX)" -ne "") {
      $rect = New-Object Drawing.Rectangle($fx, $fy, $f.Width, $f.Height)
      if (@([Windows.Forms.Screen]::AllScreens | Where-Object { $_.WorkingArea.Contains($rect) }).Count) { $f.StartPosition = "Manual"; $f.Location = New-Object Drawing.Point($fx, $fy) }
    }
  } catch {}
}
Afficher $pageDepart
if ($TestAuto) {
  $f.Add_Shown({ foreach ($sw in $toggles) { $sw.Checked = $true }; $bAppliquer.PerformClick() })
}
try { [void]$f.ShowDialog() } catch { if (-not $script:fenetreVue) { Plantage-Demarrage $_.Exception.Message } else { Noter-Plantage $_.Exception.Message } }
Fermer-Chargement
exit 0
