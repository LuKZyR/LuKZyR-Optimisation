param([switch]$TestAuto)
# =====================================================================
#  HELIXFLUX OPTIMISATION v0.1 bêta (version interne 5.3)  -  Tableau de bord
#  Détecte le matériel, propose les pilotes officiels, nettoie et optimise
#  -TestAuto : (tests uniquement) active tout et applique sans confirmation
# =====================================================================
$VersionApp = "0.1"          # version publique (comparée au version.json des mises à jour)
$VersionBeta = $true         # v0.1 bêta = version interne 5.3
$VersionInterne = "5.3"
# Mise à jour automatique : adresse d'un fichier version.json (voir LISEZ-MOI).
# Vide = pas de serveur. Peut aussi être réglée dans C:\ProgramData\Lukzyr\config.json : { "urlMiseAJour": "https://..." }
$UrlMiseAJourDefaut = ""
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $extra = if ($TestAuto) { " -TestAuto" } else { "" }
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"$extra" -Verb RunAs
    exit
}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# v5.2 : écran de chargement affiché TOUT DE SUITE (avant la compilation de l'interface et la détection du matériel)
. (Join-Path (Split-Path -Parent $PSCommandPath) "Chargement.ps1")
Demarrer-Chargement (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) $VersionApp $VersionBeta
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Drawing.Text; using System.Windows.Forms;
using System.Runtime.InteropServices; using System.Collections.Concurrent; using System.Collections.Generic; using System.Diagnostics; using System.Text;

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
  public static GraphicsPath Round(RectangleF r, float rad) {
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
    int dur = (int)(ms * Lent); Stopwatch sw = Stopwatch.StartNew();
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
    ms = (int)(ms * Lent); Stopwatch sw = Stopwatch.StartNew(); apply(0f);
    Add(() => { float p = Math.Min(1f, (float)sw.ElapsedMilliseconds / ms); apply(Ease5(p)); if (p >= 1f) { if (done != null) done(); return false; } return true; });
  }
  public static Color Mix(Color a, Color b, float p) {
    if (p <= 0f) return a; if (p >= 1f) return b;
    return Color.FromArgb((int)(a.A + (b.A - a.A) * p), (int)(a.R + (b.R - a.R) * p), (int)(a.G + (b.G - a.G) * p), (int)(a.B + (b.B - a.B) * p));
  }
  // Interpolation de 0 à 1 (adoucie) sur ms millisecondes ; apply(p) est appelée à chaque image
  public static void Tween(int ms, Action<float> apply, Action done) {
    if (!On || ms <= 0) { apply(1f); if (done != null) done(); return; }
    if (Reduit) ms = Math.Min(ms, 120);
    ms = (int)(ms * Lent);
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
  public Color Fill = Color.FromArgb(167, 139, 250);
  public LkIndicator() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(Parent != null ? Parent.BackColor : BackColor); }
  protected override void OnPaint(PaintEventArgs e) {
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, Width - 1, Height - 1), (Math.Min(Width, Height) - 1) / 2f)) using (SolidBrush b = new SolidBrush(Fill)) e.Graphics.FillPath(b, p);
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
  public LkCard() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  Color Target { get { return hover && !HoverFill.IsEmpty ? HoverFill : Fill; } }
  public Color CurrentFill { get { return shown.IsEmpty ? Target : shown; } }
  public static Color BackOf(Control c) { if (c.Parent == null) return c.BackColor; LkCard k = c.Parent as LkCard; return k != null ? k.CurrentFill : c.Parent.BackColor; }
  public void SetHover(bool h) { if (HoverFill.IsEmpty || hover == h) return; Color from = CurrentFill; hover = h; Retarget(from); }
  public void SetFill(Color c) { Color from = CurrentFill; Fill = c; Retarget(from); }
  void Retarget(Color from) {
    Color to = Target; int my = ++tok;
    float h0 = hp, h1 = hover ? 1f : 0f;
    if (!IsHandleCreated || !Visible) { shown = to; hp = h1; Sync(); return; }
    LkAnim.Tween(160, p => { if (my != tok) return; shown = LkAnim.Mix(from, to, p); hp = h0 + (h1 - h0) * p; Sync(); }, null);
  }
  void Sync() { Color c0 = CurrentFill; foreach (Control c in Controls) { if (c is Label) c.BackColor = c0; else c.Invalidate(); } Invalidate(); }
  protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(LkCard.BackOf(this)); }
  protected override void OnPaint(PaintEventArgs e) {
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, Width - 0.5f, Height - 0.5f), Radius))
    using (SolidBrush b = new SolidBrush(CurrentFill)) e.Graphics.FillPath(b, p);
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
  protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(LkCard.BackOf(this)); }
  protected override void OnPaint(PaintEventArgs e) {
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
  protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(LkCard.BackOf(this)); }
  protected override void OnPaint(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; float r = Height / 2f;
    using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, Width - 1, Height - 1), r)) using (SolidBrush b = new SolidBrush(Track)) g.FillPath(b, p);
    float w = (Width - 1) * shown / 100f;
    if (w >= 1) { if (w < Height) w = Height; using (GraphicsPath p = LkNative.Round(new RectangleF(0, 0, w, Height - 1), r)) using (Brush b = Fill2.IsEmpty ? (Brush)new SolidBrush(Fill) : new LinearGradientBrush(new RectangleF(-1, 0, Width + 2, Height), Fill2, Fill, 0f)) g.FillPath(b, p); }
    if (busy && LkAnim.On) {
      float sw = (Width - 1) * 0.22f, x = -sw + (Width - 1 + sw) * phase;
      using (GraphicsPath clip = LkNative.Round(new RectangleF(0, 0, Width - 1, Height - 1), r)) {
        g.SetClip(clip);
        using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(x - 1, 0, sw + 2, Height), Color.FromArgb(0, 200, 180, 255), Color.FromArgb(0, 200, 180, 255), 0f)) {
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
  protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(LkCard.BackOf(this)); }
  protected override void OnPaint(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    Color c; string txt = Text;
    if (busy) {
      c = LkAnim.On ? LkAnim.Mix(Fill, Color.FromArgb(178, 140, 255), pulse * 0.55f) : Fill;
      if (LkAnim.On) txt = Text.TrimEnd('.', ' ') + new string('.', dots).PadRight(3);
    } else c = !Enabled ? DisabledFill : LkAnim.Mix(Fill, HoverFill, h);
    RectangleF rc = new RectangleF(0, 0, Width - 1, Height - 1);
    if (pressed) { float d = Math.Max(1f, Height * 0.04f); rc.Inflate(-d, -d); c = LkAnim.Mix(c, Color.Black, 0.12f); }
    using (GraphicsPath p = LkNative.Round(rc, Radius)) using (SolidBrush b = new SolidBrush(c)) g.FillPath(b, p);
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
  public Panel Content = new Panel(); int off; public int Bar = 8; public Color Thumb = Color.FromArgb(60, 60, 80);
  public LkScroll() {
    SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    Controls.Add(Content); Application.AddMessageFilter(this);
  }
  public void Recalc() {
    int h = 0; foreach (Control c in Content.Controls) h = Math.Max(h, c.Bottom);
    Content.BackColor = BackColor; Content.Width = Width - Bar - 4; Content.Height = Math.Max(h + 4, Height); ScrollTo(off);
  }
  public void ScrollTo(int y) { off = Math.Max(0, Math.Min(y, Content.Height - Height)); Content.Top = -off; Invalidate(); }
  public bool PreFilterMessage(ref Message m) {
    if (m.Msg != 0x020A || !Visible || Content.Height <= Height) return false;
    Control p = this; while (p != null) { if (!p.Visible) return false; p = p.Parent; }
    if (!RectangleToScreen(ClientRectangle).Contains(Cursor.Position)) return false;
    int delta = (short)((long)m.WParam >> 16); ScrollTo(off - delta * 60 / 120); return true;
  }
  protected override void OnPaint(PaintEventArgs e) {
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
  protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(LkCard.BackOf(this)); }
  protected override void OnPaint(PaintEventArgs e) {
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
    {"spinner", "a 12 12 9 -90 270"}
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
        foreach (string part in d.Split(';')) {
          string[] a = part.Trim().Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
          if (a.Length == 0) continue;
          float[] v = new float[a.Length - 1];
          for (int i = 1; i < a.Length; i++) v[i - 1] = float.Parse(a[i], System.Globalization.CultureInfo.InvariantCulture);
          switch (a[0]) {
            case "l": g.DrawLine(pen, ox + v[0] * k, oy + v[1] * k, ox + v[2] * k, oy + v[3] * k); break;
            case "p": case "P": {
              PointF[] pts = new PointF[v.Length / 2];
              for (int i = 0; i < pts.Length; i++) pts[i] = new PointF(ox + v[2 * i] * k, oy + v[2 * i + 1] * k);
              if (a[0] == "P") g.DrawPolygon(pen, pts); else g.DrawLines(pen, pts); break; }
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
  protected override void OnPaintBackground(PaintEventArgs e) {
    LkCard k = Parent as LkCard;
    if (k != null) e.Graphics.Clear(k.CurrentFill); else if (BackColor.A == 255) e.Graphics.Clear(BackColor); else base.OnPaintBackground(e);
  }
  protected override void OnPaint(PaintEventArgs e) {
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
  protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(LkCard.BackOf(this)); }
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
  protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(LkCard.BackOf(this)); }
  protected override void OnPaint(PaintEventArgs e) {
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
    if (Prog >= 0 && progShown >= 0 && ProgRect.Width > 0) {
      RectangleF pr = ProgRect; float rr = pr.Height / 2f;
      Color tr = LkBadge.Light ? Color.FromArgb(228, 228, 234) : Color.FromArgb(36, 36, 44);
      using (GraphicsPath t = LkNative.Round(pr, rr)) using (SolidBrush b = new SolidBrush(tr)) g.FillPath(b, t);
      float w = pr.Width * Math.Max(0f, Math.Min(100f, progShown)) / 100f;
      if (w >= 1) { if (w < pr.Height) w = pr.Height; using (GraphicsPath t = LkNative.Round(new RectangleF(pr.X, pr.Y, w, pr.Height), rr)) using (SolidBrush b = new SolidBrush(Color.FromArgb(140, 82, 255))) g.FillPath(b, t); }
    }
  }
}

// Pastille de profil dans le bandeau (titre + sous-titre), sélection en blanc plein
public class LkPill : Control {
  // v5.4 (épuré) : contour fin, rempli d'une teinte légère quand il est choisi
  public string Sub = ""; public bool Selected; public int Radius = 12; public Font SubFont; float h; int tok;
  public LkPill() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true); BackColor = Color.Transparent; Cursor = Cursors.Hand; }
  void Survol(float to) { float from = h; int my = ++tok; LkAnim.Tween(130, p => { if (my != tok) return; h = from + (to - from) * p; Invalidate(); }, null); }
  protected override void OnMouseEnter(EventArgs e) { Survol(1f); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { Survol(0f); base.OnMouseLeave(e); }
  protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
  protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(LkCard.BackOf(this)); }
  protected override void OnPaint(PaintEventArgs e) {
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
    using (SolidBrush b1 = new SolidBrush(c1)) g.DrawString(Text, Font, b1, pad, Height * 0.14f);
    if (SubFont != null) using (SolidBrush b2 = new SolidBrush(c2)) g.DrawString(Sub, SubFont, b2, pad, Height * 0.54f);
  }
}

// Gros bouton rond « OPTIMISER » : halo qui respire en continu, pulsation plus forte pendant l'exécution
public class LkOrb : Control {
  public string Sub = ""; public Font SubFont; bool busy; float phase; float h; int tok; bool loop; Stopwatch sw = Stopwatch.StartNew(); int dots;
  float ripple; float prog = -1f, progShown = -1f; int ptok;
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
  protected override void OnPaint(PaintEventArgs e) {
    // v5.4 (épuré) : disque plein violet, anneau fin qui respire très doucement, anneau de progression
    Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
    bool L = LkBadge.Light;
    Color acc = Color.FromArgb(140, 82, 255);
    float cx = Width / 2f, cy = Height / 2f, R = Math.Min(Width, Height) / 2f - 2;
    float ph = LkAnim.On ? phase : 0f;
    float rp = R * 0.94f, w = Math.Max(2f, R * 0.035f);
    Color piste = L ? Color.FromArgb(226, 222, 245) : Color.FromArgb(40, 34, 64);
    using (Pen tr = new Pen(LkAnim.Mix(piste, Color.FromArgb(L ? 205 : 62, L ? 196 : 50, L ? 245 : 110), busy ? ph : ph * 0.5f), w)) g.DrawEllipse(tr, cx - rp, cy - rp, rp * 2, rp * 2);
    if (progShown >= 0f && progShown > 0.002f) using (Pen pn = new Pen(L ? Color.FromArgb(124, 77, 255) : Color.FromArgb(167, 139, 250), w * 1.6f)) { pn.StartCap = LineCap.Round; pn.EndCap = LineCap.Round; g.DrawArc(pn, cx - rp, cy - rp, rp * 2, rp * 2, -90f, 360f * progShown); }
    float ri = R * (0.78f + 0.015f * h);
    Color fill = busy ? LkAnim.Mix(acc, Color.FromArgb(160, 112, 255), ph * 0.6f) : LkAnim.Mix(acc, Color.FromArgb(122, 64, 238), h);
    using (SolidBrush b = new SolidBrush(fill)) g.FillEllipse(b, cx - ri, cy - ri, ri * 2, ri * 2);
    string t = Text; if (busy && LkAnim.On) t = Text.TrimEnd('.', ' ') + new string('.', dots).PadRight(3);
    StringFormat sf = new StringFormat(); sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
    using (SolidBrush b = new SolidBrush(Color.White)) g.DrawString(t, Font, b, new RectangleF(cx - ri, cy - ri * 0.55f, ri * 2, ri * 0.7f), sf);
    if (SubFont != null) using (SolidBrush b = new SolidBrush(Color.FromArgb(215, 255, 255, 255))) g.DrawString(Sub, SubFont, b, new RectangleF(cx - ri * 0.92f, cy + ri * 0.12f, ri * 1.84f, ri * 0.5f), sf);
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
}
"@
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
function Boite($msg, $boutons = "OK", $icone = "Information") { [Windows.Forms.MessageBox]::Show($msg, "HelixFlux Optimisation", $boutons, $icone) }
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
function Police($px, $style = "Regular", $famille = "Segoe UI") {
  New-Object Drawing.Font($famille, [float]($px * $sc), [Drawing.FontStyle]$style, [Drawing.GraphicsUnit]::Pixel) }

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
$portable = [bool](Lire-Wmi "batterie" { Get-CimInstance Win32_Battery })

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
  sombre = [ordered]@{ Titre = "#121216"; Fond = "#121217"; Carte = "#18181e"; CarteSurvol = "#1e1e25"; Blanc = "#ededf2"; Gris = "#8b8b9a"; Gris2 = "#6c6c7a"; Gris3 = "#565663"
    AccentClair = "#a78bfa"; NavActif = "#1c1730"; NavSurvol = "#17171c"; Piste = "#25252d"; Piste2 = "#1f1f26"; Pouce = "#2d2d36"; Texte2 = "#c6c6d2"; BoutonTitre = "#202027"; Off = "#35353f"; Orange = "#f0a03c"; Vert = "#a594f9"; Rouge = "#f0716f" }
  clair  = [ordered]@{ Titre = "#f7f7f9"; Fond = "#f7f7fa"; Carte = "#fdfdfe"; CarteSurvol = "#f1f1f5"; Blanc = "#18181f"; Gris = "#5f5f6e"; Gris2 = "#74748a"; Gris3 = "#9a9aab"
    AccentClair = "#7c4dff"; NavActif = "#ece6ff"; NavSurvol = "#ececf1"; Piste = "#e4e4ea"; Piste2 = "#eaeaef"; Pouce = "#cdcdd8"; Texte2 = "#33333f"; BoutonTitre = "#e6e6ec"; Off = "#c9c9d4"; Orange = "#b45309"; Vert = "#6d4ce0"; Rouge = "#b91c1c" }
}
function Charger-Palette($clair) {
  $pl = $palettes[$(if ($clair) { "clair" } else { "sombre" })]
  $script:cTitre = Hex $pl.Titre; $script:cSide = Hex $pl.Titre; $script:cFond = Hex $pl.Fond; $script:cCarte = Hex $pl.Carte; $script:cCarteSurvol = Hex $pl.CarteSurvol
  $script:cBlanc = Hex $pl.Blanc; $script:cGris = Hex $pl.Gris; $script:cGris2 = Hex $pl.Gris2; $script:cGris3 = Hex $pl.Gris3
  $script:cAccentClair = Hex $pl.AccentClair; $script:cNavActif = Hex $pl.NavActif; $script:cNavSurvol = Hex $pl.NavSurvol
  $script:cPiste = Hex $pl.Piste; $script:cPiste2 = Hex $pl.Piste2; $script:cPouce = Hex $pl.Pouce; $script:cTexte2 = Hex $pl.Texte2; $script:cBoutonTitre = Hex $pl.BoutonTitre; $script:cOff = Hex $pl.Off
  $script:cTexteActif = if ($clair) { Hex "#4b22c9" } else { [Drawing.Color]::White }
  $script:cOrange = Hex $pl.Orange; $script:cVert = Hex $pl.Vert; $script:cRouge = Hex $pl.Rouge
}
Charger-Palette $script:themeClair
[LkBadge]::Light = $script:themeClair
$cAccent  = Hex "#8c52ff"

# ===================== FENÊTRE =====================
Etape-Chargement 70 80 "Préparation de l'interface..."
$f = New-Object Windows.Forms.Form
$f.Text = "HelixFlux Optimisation"
$f.ClientSize = Sz 1000 660
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
# Logo : UN seul jeu de fichiers à remplacer (assets\helixflux.ico pour la fenêtre et l'exe, assets\logo.png pour l'en-tête)
$ico = Join-Path $racine "assets\helixflux.ico"
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

# --- Barre du haut : logo, onglets, paramètres, thème, réduire, fermer ---
$titreBar = New-Object Windows.Forms.Panel
$titreBar.Location = Pt 0 0; $titreBar.Size = Sz 1000 56; $titreBar.BackColor = $cTitre
DoubleTampon $titreBar
$f.Controls.Add($titreBar)
$logoImg = New-Object Windows.Forms.PictureBox; $logoImg.Location = Pt 20 15; $logoImg.Size = Sz 26 26; $logoImg.SizeMode = "Zoom"; $logoImg.BackColor = $cTitre
# v5.5 : logo réduit une seule fois en haute qualité à la taille exacte (net en petite taille)
function Logo-Net($taille) {
  try {
    $src = if (Test-Path $logoPng) { [Drawing.Image]::FromFile($logoPng) } elseif (Test-Path $ico) { (New-Object Drawing.Icon($ico, 256, 256)).ToBitmap() } else { return $null }
    $n = S $taille; $bm = New-Object Drawing.Bitmap $n, $n; $gr = [Drawing.Graphics]::FromImage($bm)
    $gr.InterpolationMode = "HighQualityBicubic"; $gr.PixelOffsetMode = "HighQuality"; $gr.SmoothingMode = "AntiAlias"
    $gr.DrawImage($src, 0, 0, $n, $n); $gr.Dispose(); $src.Dispose(); return $bm
  } catch { return $null }
}
$logoImg.SizeMode = "CenterImage"; $logoImg.Image = Logo-Net 26
$titreBar.Controls.Add($logoImg)
$traitTitre = New-Object Windows.Forms.Panel; $traitTitre.Location = Pt 0 55; $traitTitre.Size = Sz 1000 1; $traitTitre.BackColor = $cPiste2
$titreBar.Controls.Add($traitTitre)
$logo = Lbl $titreBar "HELIXFLUX" 52 7 120 26 (Police 16 "Bold") $cBlanc $cTitre; $logo.TextAlign = "MiddleLeft"
$credit = Lbl $titreBar "by Lukzyr" 53 32 120 16 (Police 10.5) $cGris2 $cTitre; $credit.TextAlign = "MiddleLeft"
# v0.1 : petit badge « BÊTA » à côté du nom
$wLogo = [math]::Ceiling((Largeur "HELIXFLUX" $logo.Font) / $sc) + 2; $logo.Width = S $wLogo
$bBeta = $null
if ($VersionBeta) {
  $bBeta = New-Object LkBadge; $bBeta.Text = (T "BÊTA"); $bBeta.Font = Police 9.5 "Bold"; $bBeta.Radius = S 5; $bBeta.Alpha = 26
  $bBeta.Accent = Hex "#a78bfa"; $bBeta.AccentLight = Hex "#6d28d9"
  $bBeta.Location = Pt (52 + $wLogo + 4) 11; $bBeta.Size = New-Object Drawing.Size(((Largeur $bBeta.Text $bBeta.Font) + (S 12)), (S 18))
  $titreBar.Controls.Add($bBeta); $tip.SetToolTip($bBeta, (T "Version bêta : merci de signaler les bugs (Journal > Exporter le journal)."))
}
foreach ($c in $titreBar, $logo, $credit, $logoImg) { $c.Add_MouseDown({ if ($_.Button -eq "Left") { [LkNative]::Drag($f) } }) }
function BoutonTitre($txt, $x, $survol, $taille = 16) {
  $b = Icone $titreBar $txt $x 0 44 56 $taille $cGris $cTitre
  $b.Cursor = "Hand"; $b.Tag = $survol
  $b.Add_MouseEnter({ $this.BackColor = $this.Tag; $this.ForeColor = $cBlanc }); $b.Add_MouseLeave({ $this.BackColor = $cTitre; $this.ForeColor = $cGris })
  return $b
}
$bFermer = BoutonTitre "x" 956 (Hex "#c4283c") 15
$bMini   = BoutonTitre "minus" 912 $cBoutonTitre 15
$bTheme  = BoutonTitre "theme" 868 $cBoutonTitre 17
foreach ($bt in $bFermer, $bMini, $bTheme) { $bt.BringToFront() }   # toujours au-dessus des onglets
$traitTitre.BringToFront()
$tip.SetToolTip($bFermer, (T "Fermer")); $tip.SetToolTip($bMini, (T "Réduire")); $tip.SetToolTip($bTheme, (T "Thème clair / sombre"))
$bFermer.Add_Click({ $f.Close() })
$bMini.Add_Click({ $f.WindowState = "Minimized" })

# Sections (onglets) et leurs sous-pages (pastilles en haut de la zone)
$groupes = [ordered]@{
  accueil     = @{ Nom = "Tableau de bord"; Pages = @("accueil") }
  performance = @{ Nom = "Performance"; Pages = @("perf") }
  nettoyage   = @{ Nom = "Nettoyage"; Pages = @("nettoyage") }
  applis      = @{ Nom = "Applications"; Pages = @("applis") }
  systeme     = @{ Nom = "Système"; Pages = @("demarrage", "reseau", "sysoutils") }
  materiel    = @{ Nom = "Matériel"; Pages = @("infos", "pilotes", "sante", "bios") }
  journal     = @{ Nom = "Journal"; Pages = @("journal") }
  parametres  = @{ Nom = "Paramètres"; Pages = @("parametres") }
}
$groupeDe = @{}; $derniere = @{}
foreach ($g in $groupes.Keys) { foreach ($pg in $groupes[$g].Pages) { $groupeDe[$pg] = $g }; $derniere[$g] = $groupes[$g].Pages[0] }
$nomsSousPages = @{ infos = "Mon PC"; demarrage = "Démarrage"; reseau = "Réseau"; sysoutils = "Réparation et sécurité"; pilotes = "Pilotes"; sante = "Santé"; bios = "BIOS" }

# Onglets texte : largeur mesurée (en gras pour ne pas bouger quand l'onglet devient actif)
$fTab = Police 13.5; $fTabActif = Police 13.5 "Bold"
$onglets = @{}
$xTab = $(if ($bBeta) { [math]::Max(160, [math]::Ceiling(($bBeta.Right / $sc) + 10)) } else { 160 }); $placeTabs = 824 - $xTab
$nomsTabs = @($groupes.Keys | Where-Object { $_ -ne "parametres" })
$largeurs = @{}; $total = 0
foreach ($taille in 13.5, 12.5, 11.5) {
  $fTab = Police $taille; $fTabActif = Police $taille "Bold"; $total = 0
  foreach ($g in $nomsTabs) { $largeurs[$g] = [math]::Ceiling((Largeur (T $groupes[$g].Nom) $fTabActif) / $sc); $total += $largeurs[$g] }
  if ($total + 8 * $nomsTabs.Count -le $placeTabs) { break }
}
$pad = [math]::Max(3, [math]::Min(14, [math]::Floor(($placeTabs - $total) / (2 * $nomsTabs.Count))))
function Onglet($g, $x, $w, $texte, $font, $icone = $null) {
  if ($icone) { $l = Icone $titreBar $icone $x 0 $w 56 19 $cGris $cTitre; $tip.SetToolTip($l, (T "Paramètres")) }
  else { $l = Lbl $titreBar $texte $x 0 $w 56 $font $cGris $cTitre; $l.TextAlign = "MiddleCenter" }
  $l.Cursor = "Hand"; $l.Tag = $g
  $l.Add_Click({ Afficher-Groupe $this.Tag })
  $l.Add_MouseEnter({ if ($this.Tag -ne $script:groupeActif) { $this.ForeColor = $cBlanc } })
  $l.Add_MouseLeave({ if ($this.Tag -ne $script:groupeActif) { $this.ForeColor = $cGris } })
  $script:onglets[$g] = $l
}
foreach ($g in $nomsTabs) { $w = $largeurs[$g] + 2 * $pad; Onglet $g $xTab $w $groupes[$g].Nom $fTab; $xTab += $w }
# Paramètres : roue dentée à droite
Onglet "parametres" ([math]::Max(824, $xTab)) 44 "" $null "settings"
# Soulignement violet qui glisse vers l'onglet actif
$souligne = New-Object LkIndicator; $souligne.Fill = $cAccentClair; $souligne.Size = Sz 40 2; $souligne.Location = Pt 160 53
$titreBar.Controls.Add($souligne); $souligne.BringToFront()

# --- Zone principale ---
$main = New-Object LkPanel
$main.Location = Pt 0 56; $main.Size = Sz 1000 604; $main.BackColor = $cFond
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
  if ($Defile) { $p = New-Object LkScroll; $p.Bar = S 8; $p.Thumb = $cPouce } else { $p = New-Object LkPanel }
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
  foreach ($k in $onglets.Keys) {
    $o = $onglets[$k]; $actif = ($k -eq $g)
    $o.ForeColor = if ($actif) { $cTexteActif } else { $cGris }
    if ($k -ne "parametres") { $o.Font = if ($actif) { $fTabActif } else { $fTab } } elseif ($actif) { $o.ForeColor = $cAccentClair }
  }
  $o = $onglets[$g]; $wS = [math]::Max((S 18), $o.Width - 2 * (S $pad))
  if ($g -eq "parametres") { $wS = S 22 }
  $xS = $o.Left + [int](($o.Width - $wS) / 2)
  [LkAnim]::PlaceXW($souligne, $xS, $wS, $(if ($anime) { 200 } else { 0 }))
  $titreBar.Update()
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
  if ($nom -eq "perf" -and -not $script:verifsLancees) { $script:verifsLancees = $true; try { Lancer-Verifs } catch { Log "Vérifications : $($_.Exception.Message)" } }
  $anime = [LkAnim]::On -and $ancienne -and $ancienne -ne $nom -and $f.Visible
  $gel = $f.Visible -and $main.IsHandleCreated
  if ($gel) { [LkNative]::Redraw($main, $false) }
  try {
    $main.SuspendLayout()
    foreach ($c in $h1, $sub, $zone, $barreBas, $rech) { if ($c) { $c.Visible = -not $accueil } }
    if ($script:listeRech) { $script:listeRech.Visible = $false }
    if ($accueil) { $nouv.Left = $(if ($anime) { S 12 } else { 0 }); $nouv.Visible = $true; $nouv.BringToFront() }
    else {
      $pages["accueil"].Panel.Visible = $false
      foreach ($k in $barresPastilles.Keys) { $barresPastilles[$k].Visible = ($k -eq $g) }
      if ($barresPastilles.ContainsKey($g)) {
        foreach ($pg in $groupes[$g].Pages) {
          $b = $pastilles[$pg]
          if ($pg -eq $nom) { $b.Fill = $cAccent; $b.HoverFill = Hex "#7a40ee"; $b.ForeColor = [Drawing.Color]::White } else { $b.Fill = $cFond; $b.HoverFill = $cCarteSurvol; $b.ForeColor = $cGris }
          $b.Invalidate()
        }
      }
      $nouv.Left = $(if ($anime) { S 12 } else { 0 }); $nouv.Visible = $true; $nouv.BringToFront()
      foreach ($k in @($pages.Keys)) { if ($k -ne $nom -and $k -ne "accueil") { $pages[$k].Panel.Visible = $false; $pages[$k].Panel.Left = 0 } }
      $h1.Text = (T $info.Titre); $sub.Text = (T $info.Sous)
    }
    $banniere.Visible = $script:banniereOn -and -not $accueil
    if ($rech -and -not $accueil) { $rech.BringToFront() }
    $main.ResumeLayout()
  } finally {
    if ($gel) { [LkNative]::Redraw($main, $true) }
  }
  # Le titre reste lisible pendant le fondu (il part du gris, jamais de la couleur du fond)
  $h1.ForeColor = $cBlanc; $sub.ForeColor = $cGris
  if ($anime) {
    [LkAnim]::SlideIn($nouv, (S 12), 200)
    $contenu = if ($nouv -is [LkScroll]) { $nouv.Content } else { $nouv }
    [LkAnim]::Stagger($contenu, (S 10), 260, 30, 12)
    if (-not $accueil) { [LkAnim]::FadeFore($h1, $cGris, $cBlanc, 200) }
  }
}

# Badges de risque : SÛR (vert) / AVANCÉ (orange) / DÉFINITIF (rouge)
$badges = @{
  s = @{ Texte = "SÛR"; Clair = "#9a9aae"; Fonce = "#6b6b80"; Icone = "shield-check" }
  a = @{ Texte = "AVANCÉ"; Clair = "#f5a524"; Fonce = "#c2410c"; Icone = "alert" }
  d = @{ Texte = "DÉFINITIF"; Clair = "#f87171"; Fonce = "#dc2626"; Icone = "lock" }
}
$fBadge = Police 9.5 "Bold"
$aidesBadge = @{
  s = "SÛR : réversible avec « Tout annuler »."
  a = "AVANCÉ : réversible, mais change un comportement important de Windows. Lis bien la description."
  d = "DÉFINITIF : ne peut pas être annulé par « Tout annuler » (seulement par un point de restauration)."
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
function G-Fin($g) { if ($g.Col -eq 1) { $g.Y += $g.H + 10; $g.Col = 0 } }
function G-Section($g, $texte) { G-Fin $g; if ($g.Y -gt 0) { $g.Y += 4 }; Section $g.Page $g.Y $texte; $g.Y += 30 }
function G-Option($g, $titre, $desc, $badge, $actif, $cle, $couleur = $null) {
  $x = if ($g.Col) { 465 } else { 0 }
  $sw = Ligne $g.Page $g.Y $titre $desc $actif $couleur $cle -X $x -W 455 -Badge $badge
  $g.H = 76
  if ($g.Col) { $g.Col = 0; $g.Y += 86 } else { $g.Col = 1 }
  return $sw
}
function Section($page, $y, $texte) { [void](Lbl $page $texte 4 ($y + 6) 800 18 (Police 10.5 "Bold") $cGris $cFond) }
# Carte-action : icône + titre + description (+ contrôle à droite), cliquable
function Survol-Carte($el) {
  $el.Add_MouseEnter({ $cd = $this; while ($cd -and -not ($cd -is [LkCard])) { $cd = $cd.Parent }; if ($cd) { $cd.SetHover($true) } })
  $el.Add_MouseLeave({ $cd = $this; while ($cd -and -not ($cd -is [LkCard])) { $cd = $cd.Parent }; if ($cd -and -not $cd.ClientRectangle.Contains($cd.PointToClient([Windows.Forms.Cursor]::Position))) { $cd.SetHover($false) } })
}
function LigneOption($page, $y, $glyphe, $titre, $desc, $couleurIcone = $null, $X = 0, $W = 920, $Badge = $null) {
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.HoverFill = $cCarteSurvol; $c.Radius = S 12
  $c.Location = Pt $X $y; $c.Size = Sz $W 62; $c.Cursor = "Hand"
  $colI = if ($couleurIcone) { $couleurIcone } else { $cAccentClair }
  $ic = Icone $c ([string][char]$glyphe) 13 14 34 34 19 $colI $cCarte -Puce $colI
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
  elseif ($Principal) { $b.Fill = $cAccent; $b.HoverFill = Hex "#7a40ee" } else { $b.Fill = $cCarteSurvol; $b.HoverFill = $cNavActif; $b.ForeColor = $cBlanc }
  $parent.Controls.Add($b); $b.BringToFront(); return $b   # v5.3 : jamais caché sous un texte de la carte
}

# ===================== MATÉRIEL > MON PC =====================
$pInfos = NouvellePage "infos" "Matériel" "Composants détectés sur ce PC."
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
  $c.Location = Pt (($i % 2) * 468) ([math]::Floor($i / 2) * 124); $c.Size = Sz 458 114
  [void](Lbl $c $infos[$i][0] 18 14 400 16 (Police 10.5 "Bold") $cAccentClair $cCarte)
  [void](Lbl $c $infos[$i][1] 18 36 380 70 (Police 13 "Bold") $cBlanc $cCarte)
  [void](Icone $c $iconesInfos[$i] 406 14 36 36 19 $cAccentClair $cCarte -Puce $cAccent)
  $pInfos.Controls.Add($c)
}

# ===================== MATÉRIEL > PILOTES =====================
$pP = NouvellePage "pilotes" "Pilotes" "Pilotes officiels des fabricants de tes composants." -Defile
$y = 0
foreach ($pi in $pilotes) {
  $sw = Ligne $pP $y $pi.Nom $pi.Desc $false $null "pilote" -Badge "s"
  $sw.Tag.Pilote = $pi; $y += 86
}
if (-not $pilotes.Count) { [void](Lbl $pP "Aucun pilote spécifique détecté sur ce PC." 2 0 600 20 (Police 13) $cGris $cFond) }

# ===================== NETTOYAGE & CONFIDENTIALITÉ =====================
$pN = NouvellePage "nettoyage" "Nettoyage et confidentialité" "Windows plus léger, moins de pubs et de suivi. Store, Xbox, Defender et Windows Update restent intacts." -Defile
$gN = Grille $pN
G-Section $gN "WINDOWS PLUS LÉGER"
$swDebloat  = G-Option $gN "Débloat Windows" "Applis préinstallées inutiles (réinstallables depuis le Store), pubs, Bing, widgets." "s" $true "debloat"
$swCopilot  = G-Option $gN "Supprimer Copilot" "Retire l'appli Copilot et masque son bouton." "a" $false "copilot"
$swOneDrive = G-Option $gN "Désinstaller OneDrive" "Tes fichiers déjà synchronisés restent sur le PC." "a" $false "onedrive"
$swEdge     = G-Option $gN "Désinstaller Microsoft Edge" "Garde WebView2. Fait après l'installation de Brave." "d" $false "edge" $cOrange
G-Section $gN "CONFIDENTIALITÉ"
$swTelem    = G-Option $gN "Réduire la télémétrie" "Données de diagnostic au minimum, service DiagTrack arrêté." "s" $true "telemetrie"

# ===================== APPLICATIONS =====================
$pAp = NouvellePage "applis" "Applications" "Installées depuis leurs sources officielles (winget). Décochées = rien ne se passe." -Defile
$gA = Grille $pAp
G-Section $gA "JEUX"
$swSteam    = G-Option $gA "Steam" "La plus grande boutique de jeux PC." "s" $true "app:Steam"
$swEpic     = G-Option $gA "Epic Games Launcher" "Jeux gratuits chaque semaine et Fortnite." "s" $true "app:Epic Games"
$swUbisoft  = G-Option $gA "Ubisoft Connect" "Launcher des jeux Ubisoft (Assassin's Creed, Rainbow Six...)." "s" $true "app:Ubisoft Connect"
$swRockstar = G-Option $gA "Rockstar Games Launcher" "Launcher de GTA V, Red Dead Redemption 2..." "s" $true "app:Rockstar Games"
$swEA       = G-Option $gA "EA app" "Launcher des jeux EA (EA SPORTS FC, Battlefield, Les Sims...)." "s" $false "app:EA app"
$swBnet     = G-Option $gA "Battle.net" "Launcher Blizzard (Call of Duty, Diablo, Overwatch...)." "s" $false "app:Battle.net"
$swGog      = G-Option $gA "GOG Galaxy" "Jeux sans DRM et bibliothèque de tous tes launchers." "s" $false "app:GOG Galaxy"
G-Section $gA "COMMUNICATION ET MUSIQUE"
$swDiscord  = G-Option $gA "Discord" "Discussion vocale et texte pour jouer entre amis." "s" $true "app:Discord"
$swSpotify  = G-Option $gA "Spotify" "Musique et podcasts en streaming." "s" $true "app:Spotify"
G-Section $gA "NAVIGATEURS"
$swBrave    = G-Option $gA "Brave" "Navigateur rapide avec bloqueur de pubs intégré." "s" $true "app:Brave"
G-Section $gA "CRÉATION ET UTILITAIRES"
$swObs      = G-Option $gA "OBS Studio" "Enregistrement et streaming de tes parties." "s" $false "app:OBS Studio"
$sw7zip     = G-Option $gA "7-Zip" "Ouvre et crée les archives .zip, .7z, .rar." "s" $false "app:7-Zip"
$swVlc      = G-Option $gA "VLC" "Lit toutes les vidéos et musiques." "s" $false "app:VLC"
G-Section $gA "ENTRETIEN"
$swMaj      = G-Option $gA "Mettre à jour les autres applis" "Met à jour tout ce que winget sait gérer." "s" $false "majtout"
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
  @("VBS",               "Désactiver VBS / intégrité de la mémoire", "+5 à 10 % de FPS, mais un peu moins de sécurité.", $false, "a", "perf", "MÉMOIRE ET SÉCURITÉ"),
  @("Transparence",      "Désactiver la transparence", "Effets visuels plus légers.", $true, "s", "perf", "AFFICHAGE"),
  @("DelaiDemarrage",    "Applis de démarrage sans délai", "Windows lance tes applis de démarrage sans attendre 10 secondes.", $true, "s", "perf", "DÉMARRAGE ET ARRIÈRE-PLAN"),
  @("EdgeArrierePlan",   "Edge sans préchargement", "Edge ne démarre plus avec Windows et ne reste plus ouvert une fois fermé.", $true, "s", "perf", "DÉMARRAGE ET ARRIÈRE-PLAN"),
  @("AppsArrierePlan",   "Bloquer les applis du Store en arrière-plan", "Un peu moins de mémoire utilisée. Certaines notifications peuvent arriver en retard.", $false, "a", "perf", "DÉMARRAGE ET ARRIÈRE-PLAN"),
  @("OptimDistribution", "Désactiver l'Optimisation de la distribution", "Windows ne partage plus tes mises à jour avec d'autres PC (moins de bande passante).", $true, "s", "nettoyage", "CONFIDENTIALITÉ"),
  @("NettoyageTemp",     "Nettoyage des fichiers temporaires", "Vide les dossiers Temp de Windows et de l'utilisateur (fichiers effacés).", $true, "s", "nettoyage", "FICHIERS"),
  @("AssistantStockage", "Assistant de stockage", "Nettoyage automatique des fichiers inutiles.", $true, "s", "nettoyage", "FICHIERS"),
  @("WinSxS",            "Nettoyage des composants Windows", "Supprime les anciennes versions des composants (5 à 15 min). Mises à jour toujours désinstallables.", $false, "s", "nettoyage", "FICHIERS"),
  @("TRIM",              "TRIM des SSD", "Garde les SSD rapides.", $true, "s", "sysoutils", "STOCKAGE"),
  @("Reparation",        "Réparation DISM + SFC", "Vérifie et répare les fichiers Windows (environ 15 min).", $false, "a", "sysoutils", "RÉPARATION")
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
G-Fin $gO; $gO.Y += 4; Section $pO $gO.Y "VÉRIFICATIONS (RIEN N'EST MODIFIÉ)"; $gO.Y += 30
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
  $pg.Controls.Clear()
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
  $pg = $pDem; $pg.Controls.Clear()
  if (-not $r) { [void](Lbl $pg "La liste des applis au démarrage n'a pas pu être lue (voir le Journal)." 2 0 800 20 (Police 13) $cOrange $cFond); $pages["demarrage"].Construite = $false; return }
  $script:demarrage = @($r.Liste)
  $y = 0
  if (-not $script:demarrage.Count) { [void](Lbl $pg "Aucune appli au démarrage trouvée." 2 0 600 20 (Police 13) $cGris $cFond); $y = 30 }
  foreach ($el in $script:demarrage) {
    $desc = "$(if ($el.Editeur) { $el.Editeur } else { T 'Éditeur inconnu' }) · $(T 'Impact estimé') : $(T $el.Impact) · $(T $el.Ou)"
    if ($el.Protege) {
      $sw = Ligne $pg $y $el.Nom ("$desc · " + (T "Logiciel de sécurité : non modifiable")) $true $cVert "demarrage" -Hors
      $sw.Enabled = $false
    } else {
      $sw = Ligne $pg $y $el.Nom $desc $el.Actif $null "demarrage" -Hors
      $sw.Tag.Element = $el
      $sw.Add_CheckedChanged({ Basculer-Demarrage $this.Tag.Element $this.Checked })
    }
    $y += 72
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
$pDem = NouvellePage "demarrage" "Démarrage" "Applis lancées avec Windows : désactive celles qui ralentissent (réversible)." -Defile -Construire { Construire-Demarrage }

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
    if ($kk -eq $k) { $b.Fill = $cAccent; $b.HoverFill = Hex "#7a40ee"; $b.ForeColor = [Drawing.Color]::White } else { $b.Fill = $cCarte; $b.HoverFill = $cCarteSurvol; $b.ForeColor = $cBlanc }
    $b.Invalidate()
  }
  $lDnsDet.Text = if ($dnsChoix[$k].Srv.Count) { (T "Serveurs") + " : " + ($dnsChoix[$k].Srv -join "  ·  ") } else { T "Les serveurs DNS donnés par ta box / ton fournisseur d'accès (réglage d'origine de Windows)." }
}
$bDnsAppl = New-Object LkButton; $bDnsAppl.Text = (T "Appliquer ce DNS"); $bDnsAppl.Font = Police 13 "Bold"; $bDnsAppl.Radius = S 10
$bDnsAppl.Location = Pt 0 196; $bDnsAppl.Size = Sz 220 42; $bDnsAppl.Fill = $cAccent; $bDnsAppl.HoverFill = Hex "#7a40ee"
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
        $c = $cap | Where-Object { "$($_.Identifier)" -match 'gpu' -and "$($_.Name)" -match 'GPU Core|Core|Hot Spot|Edge' } | Select-Object -First 1
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
        $c = $feuilles | Where-Object { ($_.Id -match 'gpu' -or $_.Chemin -match 'Radeon|GeForce|RTX|GTX|Arc') -and $_.Nom -match 'GPU Core|Core|Hot Spot|Edge' } | Select-Object -First 1
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
# v5.3 : outil de mesure facultatif (dépôt officiel winget). HelixFlux n'installe aucun pilote lui-même.
function Installer-Lhm {
  if ($script:enCours) { [void](Boite (T "Attends la fin de l'opération en cours.")); return }
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { [void](Boite (T "winget (App Installer) est introuvable sur ce PC. Installe-le depuis le Microsoft Store, ou télécharge LibreHardwareMonitor sur son site officiel.") "OK" "Warning"); return }
  $msg = (T "LibreHardwareMonitor est un outil gratuit et open source qui lit les capteurs (températures, ventilateurs). Il sera installé depuis le dépôt officiel winget.") + "`n`n" +
         (T "Bon à savoir : il utilise son propre pilote de lecture des capteurs, que certains antivirus (dont Microsoft Defender) peuvent signaler. HelixFlux ne l'installe pas lui-même et ne touche pas à l'antivirus.") + "`n`n" +
         (T "Ensuite : ouvre LibreHardwareMonitor, active Options > Remote Web Server > Run, puis Actualiser dans Santé.") + "`n`n" + (T "Installer maintenant ?")
  if (-not $env:LK_TEST) { if ((Boite $msg "YesNo" "Question") -ne "Yes") { return } }
  Log "Installation de LibreHardwareMonitor (winget)."
  Lancer-Plan @(@{ Nom = "Installation de LibreHardwareMonitor"; Fichier = "winget"; Args = "install --id LibreHardwareMonitor.LibreHardwareMonitor --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" }) -Resume @("LibreHardwareMonitor") -Titre "LibreHardwareMonitor" -SansPoint
}
function Construire-Sante {
  if ($script:lectureSante) { return }
  $script:lectureSante = $true
  [void](Chargement $pSante (T "Analyse des disques et de la mémoire..."))
  En-Fond "sante" $codeSante @{} { param($r) $script:lectureSante = $false; Remplir-Sante $r }
}
function Remplir-Sante($r) {
  $pg = $pSante; $pg.Controls.Clear(); $y = 0
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
$pT = NouvellePage "parametres" "Paramètres" "Apparence, langue et mises à jour de HelixFlux Optimisation." -Defile
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
# Mise à jour de l'appli
$oMaj = LigneOption $pT $yOpt 0xE895 "Mise à jour de l'appli" "Vérification au démarrage..."
$bMajVerif = Bouton $oMaj.Carte "Vérifier" 756 13 148 36
$bMajVerif.Add_Click({ Verifier-MiseAJour })
$yOpt += 70
# À propos
$oInfo = LigneOption $pT $yOpt 0xE946 "À propos" ("HelixFlux Optimisation $(Version-Affichee) · by Lukzyr · " + (T "journaux dans C:\ProgramData\Lukzyr"))
# v5.5 : le logo HelixFlux à la place de l'icône générique
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
  if ($principal) { $b.Fill = $cAccent; $b.HoverFill = Hex "#7a40ee" } else { $b.Fill = $cCarte; $b.HoverFill = $cCarteSurvol; $b.ForeColor = $cBlanc }
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
  $nom = "HelixFlux-journal-" + (Get-Date -Format "yyyyMMdd-HHmm") + ".txt"
  $dest = $null
  if ($env:LK_TEST -or $TestAuto) { try { if (-not (Test-Path -LiteralPath $dossierJournal)) { [void](New-Item -ItemType Directory -Path $dossierJournal -Force) } } catch {}; $dest = Join-Path $dossierJournal $nom }
  else {
    $dlg = New-Object Windows.Forms.SaveFileDialog; $dlg.FileName = $nom; $dlg.Filter = (T "Fichier texte") + " (*.txt)|*.txt"
    $dlg.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    if ($dlg.ShowDialog($f) -eq "OK") { $dest = $dlg.FileName }
  }
  if (-not $dest) { return }
  try {
    $entete = "HelixFlux Optimisation $(Version-Affichee) (build $VersionInterne) - " + (Get-Date -Format "dd/MM/yyyy HH:mm") + "`r`n$cpuNom / $(if ($gpuNom) { $gpuNom } else { '-' }) / $ramGo $uGo / $osNom $osVer`r`n`r`n"
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
# --- Bandeau « Optimiser en 1 clic » ---
$hero = New-Object LkHero; $hero.Location = Pt 24 10; $hero.Size = Sz 952 262; $hero.Radius = S 18
$pAccueil.Controls.Add($hero)
$hT = Lbl $hero "Optimiser en 1 clic" 24 34 600 40 (Police 26 "Bold") $cBlanc $transp
$hD = Lbl $hero "Choisis un profil : HelixFlux crée un point de restauration, sauvegarde tes réglages puis applique tout." 25 80 500 44 (Police 13) $cGris $transp
$pillules = [ordered]@{}; $xp = 24
foreach ($k in $profils.Keys) {
  $pl = New-Object LkPill; $pl.Font = Police 13 "Bold"; $pl.SubFont = Police 11; $pl.Radius = S 12
  $pl.Text = (T $profils[$k].Nom)
  $n = $profils[$k].On.Count
  $pl.Sub = $(if ($script:langue -eq "en") { "$n settings" } else { "$n réglages" }) + $(if ($k -eq "portable" -and $portable) { " · " + (T "conseillé") } else { "" })
  $pl.Location = Pt $xp 148; $pl.Size = Sz 156 54; $pl.Tag = $k
  $pl.Add_Click({ Choisir-Profil $this.Tag })
  $hero.Controls.Add($pl); $pillules[$k] = $pl; $xp += 166
}
# Barre de progression d'OPTIMISER (dans le bandeau, sous les profils)
$hero.ProgRect = New-Object Drawing.Rectangle((S 24), (S 222), (S 488), (S 3))
$texteHero = $hD.Text
$orb = New-Object LkOrb; $orb.Location = Pt 724 22; $orb.Size = Sz 204 204
$orb.Font = Police 17 "Bold"; $orb.SubFont = Police 11
$orb.Text = (T "OPTIMISER"); $orb.Sub = (T "≈ 5 min · annulable")
$hero.Controls.Add($orb)
$orb.Add_Click({ Optimiser })

# --- Jauges (valeurs réelles, mises à jour toutes les 2 s) ---
function Stat($i, $cle, $valeur, $icone) {
  # v5.4 (épuré) : pas d'encadré, juste libellé, valeur et une barre fine
  $c = New-Object LkCard; $c.Fill = $cFond; $c.Radius = S 4
  $col = if ($i -ge 2) { $i - 1 } else { $i }
  $c.Location = Pt (48 + $col * 304) 302; $c.Size = Sz 272 70
  [void](Icone $c $icone 0 1 18 18 14 $cGris $cFond)
  $k = Lbl $c $cle 24 2 120 16 (Police 10.5 "Bold") $cGris $cFond
  $p = Lbl $c "" 160 2 112 16 (Police 10.5 "Bold") $cGris $cFond; $p.TextAlign = "TopRight"
  $v = Lbl $c $valeur 0 24 272 24 (Police 15 "Bold") $cBlanc $cFond; $v.AutoEllipsis = $true
  $b = New-Object LkBar; $b.Location = Pt 0 58; $b.Size = Sz 272 3; $b.Fill = $cAccent; $b.Fill2 = Hex "#2f9bff"; $b.Track = $cPiste
  $c.Controls.Add($b); $pAccueil.Controls.Add($c)
  return @{ Carte = $c; Pct = $p; Val = $v; Barre = $b }
}
$stCpu = Stat 0 "CPU" $cpuCourt "cpu"
$stGpu = Stat 1 "GPU" $gpuCourt "monitor"
$ramTxt = "$ramGo $uGo" + $(if ($ramMhz) { " · $ramMhz MHz" } else { "" })
$stRam = Stat 2 "RAM" $ramTxt "memory"
$stC   = Stat 3 "$($env:SystemDrive)" "" "drive"
$stGpu.Barre.Visible = $false
$stGpu.Carte.Visible = $false   # v5.4 (épuré) : 3 infos clés seulement (le GPU reste dans Matériel > Infos)
$sepAccueil = New-Object Windows.Forms.Panel; $sepAccueil.Location = Pt 48 284; $sepAccueil.Size = Sz 904 1; $sepAccueil.BackColor = $cPiste2
$pAccueil.Controls.Add($sepAccueil)

# Charge GPU : compteur Windows lu en arrière-plan (sinon seulement le nom)
$gpuEtat = [hashtable]::Synchronized(@{ Load = -1 })
# v5.5 : la carte GPU du tableau de bord est masquée : la lecture en boucle (CIM toutes les 2 s) n'est plus lancée
if ($false) {
  $rs = [runspacefactory]::CreateRunspace(); $rs.Open(); $rs.SessionStateProxy.SetVariable("etat", $gpuEtat)
  $psGpu = [powershell]::Create(); $psGpu.Runspace = $rs
  [void]$psGpu.AddScript({
    while ($true) {
      try {
        $e = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop | Where-Object { $_.Name -like "*engtype_3D*" })
        if (-not $e.Count) { $etat.Load = -1; break }
        $etat.Load = [math]::Min(100, [int](($e | Measure-Object UtilizationPercentage -Sum).Sum))
      } catch { $etat.Load = -1; break }
      Start-Sleep -Seconds 2
    }
  })
  $gpuJob = $psGpu.BeginInvoke()
}
$script:statsVues = $false
function Pct($lbl, $v) { if ($script:statsVues) { $lbl.Text = "$v %" } else { [LkAnim]::CountTo($lbl, [int]$v, " %", 700) } }
function MajStats {
  $cl = [LkNative]::CpuLoad(); if ($cl -ge 0) { $stCpu.Barre.Value = $cl; Pct $stCpu.Pct $cl }
  $rl = [LkNative]::RamLoad(); if ($rl -ge 0) { $stRam.Barre.Value = $rl; Pct $stRam.Pct $rl }
  if ($gpuEtat.Load -ge 0) { $stGpu.Barre.Visible = $true; $stGpu.Barre.Value = $gpuEtat.Load; $stGpu.Pct.Text = "$($gpuEtat.Load) %" }
  try {
    $dC = New-Object IO.DriveInfo($env:SystemDrive)
    $libre = [math]::Round($dC.AvailableFreeSpace / 1GB); $pc = [int](100 - 100 * $dC.AvailableFreeSpace / $dC.TotalSize)
    $sfx = " " + (T "Go libres")
    if ($script:statsVues) { $stC.Val.Text = "$libre$sfx" } else { [LkAnim]::CountTo($stC.Val, [int]$libre, $sfx, 700) }
    $stC.Barre.Value = $pc; Pct $stC.Pct $pc
  } catch {}
  $script:statsVues = $true
}
[void][LkNative]::CpuLoad()
$tStats = New-Object Windows.Forms.Timer; $tStats.Interval = 2000
# v5.5 : jauges mises à jour seulement quand le tableau de bord est visible et la fenêtre pas réduite
$tStats.Add_Tick({ if ($f.WindowState -ne "Minimized" -and $script:pageActive -eq "accueil") { MajStats } }); $tStats.Start()

# --- Bandeau d'alertes (données réelles) ---
function Alerte($i) {
  $a = New-Object LkTint; $a.Radius = S 12; $a.Location = Pt (48 + $i * 304) 398; $a.Size = Sz 290 46; $a.BackColor = $cFond
  $ic = Icone $a "" 0 0 22 46 16 $cVert $transp
  $tx = Lbl $a "" 28 0 186 46 (Police 12) $cTexte2 $transp; $tx.TextAlign = "MiddleLeft"
  $ln = Lbl $a "" 188 0 102 46 (Police 12 "Bold") $cVert $transp; $ln.TextAlign = "MiddleRight"; $ln.Cursor = "Hand"
  $pAccueil.Controls.Add($a)
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
$alDem = Alerte 0; $alOpt = Alerte 1; $alSante = Alerte 2
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
  if ($l.Count) { Regler-Alerte $alDem 0xE7BA $cOrange ((T "{0} appli(s) lourde(s) au démarrage") -f $l.Count) (T "Voir") { Afficher "demarrage" } }
  else { Regler-Alerte $alDem 0xE73E $cVert (T "Démarrage léger : rien de lourd") (T "Voir") { Afficher "demarrage" } }
}
function Alerte-Disques($d) {
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

# --- Tuiles vers les sections ---
$tuiles = @{}
$defTuiles = @(
  @("performance", 0xE945, "#a78bfa", "Performance"),
  @("nettoyage",   0xE74D, "#34d399", "Nettoyage et confidentialité"),
  @("applis",      0xE71D, "#60a5fa", "Applications"),
  @("systeme",     0xE770, "#f472b6", "Système"),
  @("materiel",    0xE950, "#fbbf24", "Matériel"),
  @("parametres",  0xE713, "#94a3b8", "Paramètres")
)
for ($i = 0; $i -lt $defTuiles.Count; $i++) {
  $d = $defTuiles[$i]
  $c = New-Object LkCard; $c.Fill = $cCarte; $c.HoverFill = $cCarteSurvol; $c.Radius = S 14
  $c.Location = Pt (24 + ($i % 3) * 321) (398 + [math]::Floor($i / 3) * 84); $c.Size = Sz 309 74; $c.Cursor = "Hand"; $c.Tag = $d[0]; $c.Visible = $false
  $ib = New-Object LkBadge; $ib.Text = ""; $ib.Icon = [LkIcons]::Resolve([string][char]$d[1]); $ib.IconSize = [float](22 * $sc); $ib.Radius = S 12; $ib.Alpha = 36
  $ib.Accent = Hex $d[2]; $ib.AccentLight = [LkAnim]::Mix((Hex $d[2]), [Drawing.Color]::Black, 0.25); $ib.Location = Pt 16 15; $ib.Size = Sz 44 44
  $c.Controls.Add($ib)
  $tt = Lbl $c $d[3] 74 15 194 22 (Police 14 "Bold") $cBlanc $cCarte
  foreach ($tp in 13, 12) { if ((Largeur $tt.Text $tt.Font) -gt $tt.Width) { $tt.Font = Police $tp "Bold" } }
  $ts = Lbl $c "" 74 39 200 18 (Police 12) $cGris $cCarte
  $ta = Icone $c "chevron" 270 0 26 74 16 $cGris2 $cCarte
  foreach ($el in $c, $ib, $tt, $ts, $ta) {
    $el.Cursor = "Hand"; $el.Tag = $d[0]
    $el.Add_Click({ Afficher-Groupe $this.Tag })
    Survol-Carte $el
  }
  $pAccueil.Controls.Add($c); $tuiles[$d[0]] = $ts
}
$tuiles["systeme"].Text = (T "Démarrage, réseau, réparation")
$tuiles["materiel"].Text = (T "Pilotes, santé, BIOS")
$tuiles["parametres"].Text = (T "Thème, langue, mises à jour")
function Maj-Tuiles {
  foreach ($k in "perf", "nettoyage", "applis") {
    $l = @($toggles | Where-Object { $_.Parent -and $_.Parent.Parent -eq $pages[$k].Panel.Content -and ($k -ne "applis" -or "$($_.Tag.Cle)" -like "app:*") })
    $n = $l.Count; $a = @($l | Where-Object { $_.Checked }).Count
    $txt = if ($script:langue -eq "en") { "$n settings · $a on" } else { "$n réglages · $a activés" }
    if ($k -eq "applis") { $txt = if ($script:langue -eq "en") { "$n apps · $a selected" } else { "$n applis · $a cochées" } }
    $tuiles[$(if ($k -eq "perf") { "performance" } else { $k })].Text = $txt
  }
}
$pied = Lbl $pAccueil "Avant chaque changement : point de restauration + sauvegarde des réglages. « Tout annuler » à tout moment." 48 560 900 20 (Police 11.5) $cGris2 $cFond


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
$bAppliquer.Location = Pt 776 6; $bAppliquer.Size = Sz 192 46; $bAppliquer.Fill = $cAccent; $bAppliquer.HoverFill = Hex "#7a40ee"
$barreBas.Controls.Add($bAppliquer)

$script:enCours = $false
function MajCompteur {
  if ($script:enCours) { return }
  $coches = @($toggles | Where-Object { $_.Checked })
  $na = @($coches | Where-Object { "$($_.Tag.Cle)" -like "app:*" -or "$($_.Tag.Cle)" -eq "majtout" }).Count
  $np = @($coches | Where-Object { "$($_.Tag.Cle)" -eq "pilote" }).Count
  $n = $coches.Count - $na - $np
  $av = @($coches | Where-Object { $_.Tag.Badge -in @("a", "d") }).Count
  $txt = if ($script:langue -eq "en") { "$n setting$(if ($n -ne 1) { 's' })" } else { "$n réglage$(if ($n -gt 1) { 's' })" }
  if ($na) { $txt += " · " + $(if ($script:langue -eq "en") { "$na app$(if ($na -ne 1) { 's' })" } else { "$na appli$(if ($na -gt 1) { 's' })" }) }
  if ($np) { $txt += " · " + $(if ($script:langue -eq "en") { "$np driver$(if ($np -ne 1) { 's' })" } else { "$np pilote$(if ($np -gt 1) { 's' })" }) }
  $txt += $(if ($script:langue -eq "en") { " selected" } else { " sélectionné(s)" })
  if ($av) { $txt += " · " + $(if ($script:langue -eq "en") { "$av advanced / permanent" } else { "$av avancé(s) / définitif(s)" }) }
  $compteur.Text = $txt
  if ($tuiles) { Maj-Tuiles }
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
function EtapeScript($nom, $script, $argsTxt) { @{ Nom = $nom; Fichier = $ps; Args = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $dir $script)`" $argsTxt" } }

function Construire-Plan($Seulement = $null) {
  $plan = New-Object System.Collections.ArrayList
  $liste = New-Object System.Collections.ArrayList
  $winget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
  # Réglages retenus : cochés (et, pour OPTIMISER, seulement ceux du profil)
  $actifs = @($toggles | Where-Object { $_.Checked -and $_.Enabled -and (-not $Seulement -or $Seulement -contains $_.Tag.Cle) })
  $on = @{}; foreach ($sw in $actifs) { $on[[string]$sw.Tag.Cle] = $true }
  foreach ($sw in $actifs) {
    if ($sw.Tag.Cle -ne "pilote") { continue }
    $pi = $sw.Tag.Pilote
    if ($pi.Winget -and $winget) {
      [void]$plan.Add(@{ Nom = "Pilote : $($pi.Nom)"; Fichier = "winget"; Args = "install --id $($pi.Winget) --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" })
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
  return @{ Plan = $plan; Liste = $liste; Risques = $risques; Edge = [bool]$on["edge"] }
}
# Fenêtre de confirmation commune (APPLIQUER et OPTIMISER)
function Confirmer-Plan($r, $titre = $null) {
  if (-not $r.Plan.Count) { [void](Boite (T "Aucun réglage n'est activé.")); return $false }
  $msg = $(if ($titre) { "$titre`n`n" } else { "" }) + (T "HelixFlux Optimisation va faire :") + "`n`n - " + (($r.Liste | ForEach-Object { T $_ }) -join "`n - ") + "`n`n" + (T "Un point de restauration est créé avant de commencer, et les réglages d'origine sont sauvegardés (bouton « Tout annuler »).")
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
  catch { Log "   Impossible de lancer : $($_.Exception.Message)"; $script:proc = $null }
}

function Fin-Execution {
  $tMoteur.Stop(); $script:enCours = $false
  $fondProg.Value = 100
  Log "Tout est fini ! Redémarre le PC pour appliquer les changements. Journal : $fichierJournal"
  $compteur.ForeColor = $cVert; $compteur.Text = (T "Terminé. Redémarre le PC pour tout appliquer.")
  $bAppliquer.Busy = $false; $fondProg.Busy = $false
  $bAppliquer.Text = (T "TERMINÉ"); $bAppliquer.Enabled = $true
  $orb.Busy = $false; $orb.Text = (T "TERMINÉ"); $orb.Sub = (T "Redémarre le PC")
  # après « Tout annuler », le bouton redevient OPTIMISER (l'appli n'est plus « optimisée »)
  if ($script:estRestauration) { $orb.Text = (T "OPTIMISER"); $orb.Sub = (T "Redémarre le PC") }
  foreach ($pl in $pillules.Values) { $pl.Enabled = $true }
  foreach ($sw in $toggles) { $sw.Enabled = $true }
  if (-not $script:estRestauration) { Enregistrer-Pref "DerniereOptimisation" (Get-Date -Format "dd/MM HH:mm") } else { Enregistrer-Pref "DerniereOptimisation" "" }
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
$tCacheProg.Add_Tick({ $tCacheProg.Stop(); if (-not $script:enCours) { $hero.SetProg(-1); try { $orb.SetProgress(-1) } catch {} } })

# Fenêtre de résumé après OPTIMISER / APPLIQUER / Tout annuler : ce qui a été fait + redémarrage
function Afficher-Resume($duree) {
  $resto = $script:estRestauration
  $fr = New-Object Windows.Forms.Form; $fr.FormBorderStyle = "None"; $fr.StartPosition = "CenterParent"; $fr.ShowInTaskbar = $false
  $fr.BackColor = $cCarteSurvol; $fr.ClientSize = Sz 520 430; $fr.Font = Police 13; $fr.KeyPreview = $true; $fr.AutoScaleMode = "None"
  DoubleTampon $fr
  $cd = New-Object LkCard; $cd.Fill = $cCarte; $cd.Radius = S 16; $cd.Location = Pt 1 1; $cd.Size = Sz 518 428; $fr.Controls.Add($cd)
  $ok = ($script:nbErreurs -eq 0)
  $colR = if ($ok) { $cVert } else { $cOrange }
  $ic = Icone $cd $(if ($ok) { "check-circle" } else { "alert" }) 22 18 44 44 26 $colR $cCarte -Puce $colR
  $titre = if ($resto) { T "Réglages d'origine remis" } elseif ($ok) { T "Optimisation terminée" } else { T "Terminé, avec des erreurs" }
  [void](Lbl $cd $titre 74 20 420 30 (Police 20 "Bold") $cBlanc $cCarte)
  $n = $script:resume.Count
  $sousT = if ($script:sansPoint) { ((T "{0} élément(s) installé(s) en {1} min.") -f $n, $duree) } elseif ($resto) { ((T "{0} valeur(s) d'origine remise(s) en {1} min.") -f $n, $duree) } else { ((T "{0} réglage(s) appliqué(s) en {1} min · point de restauration créé.") -f $n, $duree) }
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
  if (Confirmer-Plan $r) { Lancer-Plan $r.Plan -Resume $r.Liste }
})
function Lancer-Plan($plan, [switch]$Ici, $Resume = $null, $Titre = "", [switch]$SansPoint) {
  $script:sansPoint = [bool]$SansPoint
  $script:enCours = $true; $script:plan = @($plan); $script:nbEtapes = $script:plan.Count; $script:idx = -1; $script:estRestauration = $false
  $script:resume = @($Resume | Where-Object { $_ }); $script:titreResume = $Titre; $script:nbErreurs = 0; $script:etapesErreur = @(); $script:debut = Get-Date
  $tCacheProg.Stop(); $hero.SetProg(0); try { $orb.SetProgress(0) } catch {}
  foreach ($e in $script:plan) { if ("$($e.Args)" -match '-Restaurer') { $script:estRestauration = $true } }
  foreach ($sw in $toggles) { $sw.Enabled = $false }
  $bAppliquer.Enabled = $false; $bAppliquer.Text = $(if ([LkAnim]::On) { T "EN COURS" } else { (T "EN COURS") + "..." }); $bAppliquer.Busy = $true
  $orb.Text = (T "EN COURS"); $orb.Sub = ""; $orb.Busy = $true
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
  $pile = New-Object System.Collections.Stack; $pile.Push($f)
  if ($script:frResume -and -not $script:frResume.IsDisposed) { $pile.Push($script:frResume) }   # fenêtre de résumé ouverte : suit le thème aussi
  while ($pile.Count) {
    $c = $pile.Pop()
    if ($c -is [LkCard]) { $c.HoverFill = M $c.HoverFill; $c.SetFill((M $c.Fill)) }
    elseif ($c -is [LkToggle]) { $c.OffColor = M $c.OffColor; $c.Invalidate() }
    elseif ($c -is [LkBar]) { $c.Track = M $c.Track; $c.Invalidate() }
    elseif ($c -is [LkButton]) { $c.Fill = M $c.Fill; $c.HoverFill = M $c.HoverFill; $c.ForeColor = M $c.ForeColor; $c.Invalidate() }
    elseif ($c -is [LkIndicator]) { $c.Fill = M $c.Fill; $c.Invalidate() }
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
  Remplir-Bios
  try { [void][LkNative]::SetWindowTheme($log.Handle, $(if ($clair) { "Explorer" } else { "DarkMode_Explorer" }), $null) } catch {}
  [LkBadge]::Light = $clair
  if ($script:pageActive) { Afficher $script:pageActive -Forcer }
  try { Maj-Alertes } catch {}
  Enregistrer-Pref "Theme" $(if ($clair) { "clair" } else { "sombre" })
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
  if (-not $liste.Count) { [void](Boite (T "Rien à annuler : aucun réglage n'a encore été modifié par HelixFlux Optimisation (ou tout a déjà été restauré).")); return }
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
$etatMaj = [hashtable]::Synchronized(@{ Statut = ""; Version = ""; Url = ""; Notes = ""; Fichier = ""; Erreur = "" })
function Url-MiseAJour {
  $u = $UrlMiseAJourDefaut
  try { $cf = Join-Path $env:ProgramData "Lukzyr\config.json"; if (Test-Path $cf) { $j = Get-Content $cf -Raw | ConvertFrom-Json; if ($j.urlMiseAJour) { $u = "$($j.urlMiseAJour)" } } } catch {}
  return "$u".Trim()
}
function Lancer-Arriere($bloc, $arguments) {
  try {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open(); $rs.SessionStateProxy.SetVariable("etat", $etatMaj)
    $psA = [powershell]::Create(); $psA.Runspace = $rs; [void]$psA.AddScript($bloc)
    foreach ($arg in $arguments) { [void]$psA.AddArgument($arg) }
    [void]$psA.BeginInvoke()
  } catch { $etatMaj.Statut = "erreur"; $etatMaj.Erreur = $_.Exception.Message }
}
function Verifier-MiseAJour {
  $u = Url-MiseAJour
  if (-not $u) { $etatMaj.Statut = "aucun"; Maj-AffichageMaj; return }
  $etatMaj.Statut = "verif"; Maj-AffichageMaj
  Lancer-Arriere {
    param($url, $versionApp, $betaApp)
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add("User-Agent", "HelixFluxOptimisation")
      $j = $wc.DownloadString($url) | ConvertFrom-Json
      $etat.Version = "$($j.version)"; $etat.Url = "$($j.url)"; $etat.Notes = "$($j.notes)"
      # v0.1 : versions du type « 0.1 », « 0.1.2 », « 0.2-beta », « v0.2 bêta » ; une finale passe avant la bêta du même numéro
      function Num($v) { $m = [regex]::Match("$v", '\d+(\.\d+){0,3}'); if (-not $m.Success) { return $null }; $x = $m.Value; while (($x -split '\.').Count -lt 3) { $x += ".0" }; [version]$x }
      function Beta($v) { "$v" -match '(?i)b[eê]ta|alpha|rc|pre' }
      $nd = Num $etat.Version; $nl = Num $versionApp
      $etat.Statut = if (-not $nd) { "erreur" } elseif ($nd -gt $nl) { "dispo" } elseif ($nd -eq $nl -and $betaApp -and -not (Beta $etat.Version)) { "dispo" } else { "ajour" }
      if (-not $nd) { $etat.Erreur = "version illisible : $($etat.Version)" }
    } catch { $etat.Statut = "erreur"; $etat.Erreur = $_.Exception.Message }
  } @($u, $VersionApp, $VersionBeta)
}
function Telecharger-MiseAJour {
  if (-not $etatMaj.Url) { return }
  $bureau = [Environment]::GetFolderPath("Desktop")
  $nomZip = [IO.Path]::GetFileName(([uri]$etatMaj.Url).AbsolutePath); if ($nomZip -notmatch '\.zip$') { $nomZip = "HelixFlux-Optimisation-v$($etatMaj.Version).zip" }
  $etatMaj.Fichier = Join-Path $bureau $nomZip; $etatMaj.Statut = "telechargement"; Maj-AffichageMaj
  Lancer-Arriere {
    param($url, $dest)
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $wc = New-Object Net.WebClient; $wc.Headers.Add("User-Agent", "HelixFluxOptimisation"); $wc.DownloadFile($url, $dest)
      $etat.Statut = "telecharge"
    } catch { $etat.Statut = "erreur"; $etat.Erreur = $_.Exception.Message }
  } @($etatMaj.Url, $etatMaj.Fichier)
}
# Bandeau « nouvelle version » (en haut à droite)
$banniere = New-Object LkCard; $banniere.Fill = $cNavActif; $banniere.Radius = S 12; $banniere.Location = Pt 636 14; $banniere.Size = Sz 332 56; $banniere.Visible = $false; $script:banniereOn = $false
$lBan = Lbl $banniere "" 14 8 170 40 (Police 12 "Bold") $cBlanc $cNavActif
$bBan = New-Object LkButton; $bBan.Text = (T "Télécharger"); $bBan.Font = Police 12 "Bold"; $bBan.Radius = S 10
$bBan.Location = Pt 190 10; $bBan.Size = Sz 130 36; $bBan.Fill = $cAccent; $bBan.HoverFill = Hex "#7a40ee"
$banniere.Controls.Add($bBan); $main.Controls.Add($banniere); $banniere.BringToFront()
$bBan.Add_Click({ if ($etatMaj.Statut -eq "telecharge") { Start-Process explorer.exe "/select,`"$($etatMaj.Fichier)`"" } elseif ($etatMaj.Statut -eq "dispo") { Telecharger-MiseAJour } })
$script:statutVu = ""
function Maj-AffichageMaj {
  $st = $etatMaj.Statut
  $txt = switch ($st) {
    "aucun" { T "Aucun serveur de mise à jour configuré." }
    "verif" { T "Vérification en cours..." }
    "ajour" { (T "Tu as la dernière version") + " ($(Version-Affichee))." }
    "dispo" { (T "Nouvelle version disponible") + " : $($etatMaj.Version)" }
    "telechargement" { T "Téléchargement en cours..." }
    "telecharge" { (T "Téléchargée sur le Bureau") + " : $([IO.Path]::GetFileName($etatMaj.Fichier))" }
    "erreur" { T "Pas de connexion au serveur de mise à jour (l'appli marche normalement)." }
    default { "" }
  }
  if ($txt) { $oMaj.Desc.Text = $txt }
  if ($st -in @("dispo", "telechargement", "telecharge")) {
    $lBan.Text = $(switch ($st) { "dispo" { (T "Version") + " $($etatMaj.Version) " + (T "disponible") } "telechargement" { T "Téléchargement..." } default { T "Zip enregistré sur le Bureau" } })
    $bBan.Text = $(if ($st -eq "telecharge") { T "Ouvrir" } else { T "Télécharger" }); $bBan.Enabled = ($st -ne "telechargement")
    if (-not $script:banniereOn) { $script:banniereOn = $true; if ($script:pageActive -ne "accueil") { $banniere.Visible = $true; $banniere.BringToFront() } }
  }
  if ($st -ne $script:statutVu) {
    $script:statutVu = $st
    if ($st -in @("dispo", "telechargement", "telecharge")) { try { Maj-Alertes } catch {} }
    if ($st -eq "erreur") { Log "Mise à jour : serveur injoignable ($($etatMaj.Erreur))." } elseif ($st -eq "telecharge") { Log "Mise à jour téléchargée : $($etatMaj.Fichier)"; Start-Process explorer.exe "/select,`"$($etatMaj.Fichier)`"" } elseif ($txt -and $st -ne "verif") { Log "Mise à jour : $txt" }
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
$rech = New-Object LkCard; $rech.Fill = $cCarte; $rech.HoverFill = $cCarteSurvol; $rech.Radius = S 10; $rech.Location = Pt 700 18; $rech.Size = Sz 268 36; $rech.Visible = $false
$main.Controls.Add($rech)
$rIc = Icone $rech "search" 9 0 24 36 16 $cGris $cCarte
$tbRech = New-Object Windows.Forms.TextBox; $tbRech.BorderStyle = "None"; $tbRech.BackColor = $cCarte; $tbRech.ForeColor = $cBlanc; $tbRech.Font = Police 12.5
$tbRech.Location = Pt 38 9; $tbRech.Size = Sz 220 20
$rech.Controls.Add($tbRech)
$rPh = Lbl $rech "Rechercher un réglage (Ctrl+F)" 38 0 222 36 (Police 12) $cGris2 $cCarte; $rPh.TextAlign = "MiddleLeft"; $rPh.Cursor = "IBeam"
$rPh.Add_Click({ $tbRech.Focus() }); $rIc.Add_Click({ $tbRech.Focus() })
$rPh.BringToFront()
$script:listeRech = New-Object LkCard; $script:listeRech.Fill = $cCarteSurvol; $script:listeRech.Radius = S 10; $script:listeRech.Location = Pt 700 58; $script:listeRech.Size = Sz 268 40; $script:listeRech.Visible = $false
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
  $lr = $script:listeRech; $lr.Controls.Clear(); $script:resultats = @()
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
    if ($script:pageActive -eq "accueil") { Afficher-Groupe "performance" }
    $tbRech.Focus(); $tbRech.SelectAll()
  }
})

# ===================== DÉMARRAGE =====================
Etape-Chargement 95 99 "Finitions..."
foreach ($k in @($pages.Keys)) { $p = $pages[$k].Panel; if ($p -is [LkScroll]) { $p.Recalc() } }
$f.Add_Shown({ foreach ($k in @($pages.Keys)) { $p = $pages[$k].Panel; if ($p -is [LkScroll]) { $p.Recalc() } }; MajStats })
$f.Add_FormClosing({
  if ([LkAnim]::Closing) { return }   # 2e passage, après le fondu
  if (-not $env:LK_TEST -and -not $TestAuto) {
    if ($script:pageActive) { Enregistrer-Pref "DernierePage" $script:pageActive }
    if ($f.WindowState -eq "Normal") { Enregistrer-Pref "FenetreX" "$($f.Left)"; Enregistrer-Pref "FenetreY" "$($f.Top)" }
  }
  if ($script:enCours -and -not $TestAuto) { if ((Boite (T "Une opération est en cours. Quitter quand même ?") "YesNo" "Warning") -ne "Yes") { $_.Cancel = $true; return } }
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
$f.Add_Shown({ Fin-Chargement; $tFinChg.Start(); $tPretChg.Start(); $f.Activate() })
$f.Add_FormClosed({ Fermer-Chargement })
$f.Add_FormClosed({ if ($psGpu) { try { $psGpu.Stop() } catch {} } })
# v5.5 : fenêtre réduite ou inactive => pulsations en pause (reprennent au retour)
$script:fActive = $true
function Maj-PauseAnim { [LkAnim]::Pause = ($f.WindowState -eq "Minimized") -or -not $script:fActive }
$f.Add_Activated({ $script:fActive = $true; Maj-PauseAnim })
$f.Add_Deactivate({ $script:fActive = $false; Maj-PauseAnim })
$f.Add_Resize({ Maj-PauseAnim })
# Mise à jour : vérifiée 1,5 s après l'ouverture, en arrière-plan
$f.Add_Shown({ $tMaj.Start(); Verifier-MiseAJour })
# Alertes du Tableau de bord : lues juste après l'ouverture (sans retarder l'affichage)
$tAlertes = New-Object Windows.Forms.Timer; $tAlertes.Interval = 400
$tAlertes.Add_Tick({ $tAlertes.Stop(); try { Maj-Alertes } catch { Log "Alertes : $($_.Exception.Message)" } })
$f.Add_Shown({ $tAlertes.Start() })
MajCompteur
Log "HelixFlux Optimisation $(Version-Affichee) (build $VersionInterne) - matériel détecté : $cpuNom / $(if ($gpuNom) { $gpuNom } else { 'GPU non détecté' })"
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
[void]$f.ShowDialog()
Fermer-Chargement
