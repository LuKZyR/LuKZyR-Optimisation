// HelixFlux Optimisation v0.1 bêta (version interne 5.3) - écran de chargement de l'appli (scripts\LkChargement.dll)
// v5.2 : l'écran était piloté par un minuteur PowerShell dans un 2e runspace ; si ce minuteur cessait
// d'être servi, plus rien ne pouvait le fermer (écran figé « Prêt 65 % » au-dessus de l'appli).
// v5.3 : écran 100 % C# sur son propre fil (aucun code PowerShell n'y tourne), état partagé en champs
// volatils, et PLUSIEURS chemins de fermeture indépendants :
//   1. Finish() (fenêtre principale affichée)  -> la barre file à 100 %
//      Ready()  (fenêtre principale entièrement opaque) -> fondu de l'écran (pas de bureau entre les deux)
//   2. Close()  (fenêtre principale fermée, ou filet de sécurité 2 s après l'affichage) -> WM_CLOSE posté
//   3. chien de garde interne : dès qu'une fenêtre visible « HelixFlux Optimisation » de CE processus existe
//      depuis 2 s -> Finish ; Finish + 2,5 s sans Ready -> fondu ; Finish + 4 s -> fermeture forcée
//   4. plafond absolu (10 min) ; fil d'arrière-plan : il meurt avec le processus
// Jamais TopMost.
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("HelixFlux Optimisation - chargement")]
[assembly: AssemblyProduct("HelixFlux Optimisation")]
[assembly: AssemblyCompany("Lukzyr")]
[assembly: AssemblyCopyright("Copyright © 2026 Lukzyr")]
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]
[assembly: AssemblyInformationalVersion("0.1.0-beta")]

public static class LkChargement {
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  internal static volatile float Pct = 0, Max = 20;
  internal static volatile string Etape = "";
  internal static volatile bool Fin, Ferme, Pret;
  internal static volatile int FinTick;
  internal static volatile IntPtr Hwnd = IntPtr.Zero;
  internal static bool Clair; internal static string Version = "", Racine = "", TitreFenetre = "HelixFlux Optimisation";
  static Thread fil; static readonly object verrou = new object();
  public static string DerniereErreur = "";

  public static bool Start(bool clair, string version, string racine, string etape, float pct, float max) {
    lock (verrou) {
      if (fil != null) return true;
      Clair = clair; Version = version ?? ""; Racine = racine ?? ""; Etape = etape ?? ""; Pct = pct; Max = max;
      try {
        fil = new Thread(Executer); fil.IsBackground = true; fil.Name = "LkChargement";
        fil.SetApartmentState(ApartmentState.STA); fil.Start(); return true;
      } catch (Exception ex) { DerniereErreur = ex.Message; return false; }
    }
  }
  static void Executer() {
    try { Application.Run(new LkEcranChargement()); }
    catch (Exception ex) { DerniereErreur = ex.Message; }
    finally { Hwnd = IntPtr.Zero; }
  }
  public static void Step(float pct, float max, string etape) {
    if (Fin) return;
    if (pct > Pct) Pct = pct; Max = Math.Max(max, Pct); if (etape != null) Etape = etape;
  }
  public static void Finish(string etape) {
    if (etape != null) Etape = etape;
    Pct = 100; Max = 100;
    if (!Fin) { FinTick = Environment.TickCount; Fin = true; }
  }
  public static void Ready() { if (!Fin) Finish(null); Pret = true; }
  public static void Close() {
    if (!Fin) Finish(null);
    Ferme = true;
    IntPtr h = Hwnd; if (h != IntPtr.Zero) { try { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); } catch { } }
  }
  public static bool Active { get { Thread t = fil; return t != null && t.IsAlive && Hwnd != IntPtr.Zero; } }
}

class LkEcranChargement : Form {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  // InternalGetWindowText : lit le titre SANS envoyer WM_GETTEXT. GetWindowText sur une fenêtre de CE processus
  // attend que le fil de la fenêtre (PowerShell, parfois occupé) réponde : l'écran se figeait le temps que l'appli finisse.
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int InternalGetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);

  readonly Color fond, bord, texte, gris, acc, piste, violet = Color.FromArgb(140, 82, 255), bleuLogo = Color.FromArgb(47, 155, 255);   // v5.5 : dégradé du logo HelixFlux
  readonly float s; Image logo; readonly Stopwatch sw = Stopwatch.StartNew();
  readonly System.Windows.Forms.Timer tm = new System.Windows.Forms.Timer();
  float aff, ang; double der, vuFenetre = -1, derVerif = -1, debutFondu = -1; bool fondu;
  readonly uint pid = (uint)Process.GetCurrentProcess().Id;
  Font fT, fS, fE, fP, fV;

  public LkEcranChargement() {
    try { SetProcessDPIAware(); } catch { }
    if (LkChargement.Clair) { fond = C("#f6f6fa"); bord = C("#dcdce8"); texte = C("#1a1a24"); gris = C("#55556e"); acc = C("#7c4dff"); piste = C("#e3e3ec"); }
    else { fond = C("#0f0f15"); bord = C("#26263a"); texte = C("#f2f2f7"); gris = C("#8a8aa3"); acc = C("#a78bfa"); piste = C("#24242e"); }
    using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) s = Math.Max(1f, g.DpiX / 96f);
    Text = "HelixFlux Optimisation - chargement"; FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.CenterScreen;
    ClientSize = new Size((int)(440 * s), (int)(270 * s)); BackColor = fond; ShowInTaskbar = true; TopMost = false;
    SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
    try { string ico = Path.Combine(LkChargement.Racine, @"assets\helixflux.ico"); if (File.Exists(ico)) Icon = new Icon(ico); } catch { }
    try { string png = Path.Combine(LkChargement.Racine, @"assets\logo.png"); if (File.Exists(png)) { using (Image im = Image.FromFile(png)) logo = new Bitmap(im); } else if (Icon != null) logo = new Icon(Icon, 64, 64).ToBitmap(); } catch { }
    fT = new Font("Segoe UI", 24 * s, FontStyle.Bold, GraphicsUnit.Pixel); fS = new Font("Segoe UI", 12.5f * s, FontStyle.Regular, GraphicsUnit.Pixel);
    fE = new Font("Segoe UI", 12.5f * s, FontStyle.Regular, GraphicsUnit.Pixel); fP = new Font("Segoe UI", 12.5f * s, FontStyle.Bold, GraphicsUnit.Pixel);
    fV = new Font("Segoe UI", 10.5f * s, FontStyle.Regular, GraphicsUnit.Pixel);
    aff = LkChargement.Pct;
    tm.Interval = 15; tm.Tick += Tick;   // ~60 images/s
  }
  static Color C(string h) { return ColorTranslator.FromHtml(h); }
  float S(float v) { return v * s; }
  protected override void OnHandleCreated(EventArgs e) {
    base.OnHandleCreated(e); LkChargement.Hwnd = Handle;
    try { int v = 2; DwmSetWindowAttribute(Handle, 33, ref v, 4); } catch { }   // coins arrondis (Windows 11)
  }
  protected override void OnShown(EventArgs e) { base.OnShown(e); tm.Start(); }
  protected override void OnFormClosed(FormClosedEventArgs e) { tm.Stop(); LkChargement.Hwnd = IntPtr.Zero; base.OnFormClosed(e); }

  // Fenêtre principale de CE processus visible ?
  bool FenetrePrincipaleVisible() {
    bool trouve = false;
    try {
      EnumWindows(delegate (IntPtr h, IntPtr l) {
        uint p; GetWindowThreadProcessId(h, out p);
        if (p != pid || !IsWindowVisible(h)) return true;
        StringBuilder sb = new StringBuilder(128); InternalGetWindowText(h, sb, 128);
        if (sb.ToString() == LkChargement.TitreFenetre) { trouve = true; return false; }
        return true;
      }, IntPtr.Zero);
    } catch { }
    return trouve;
  }

  void Tick(object o, EventArgs e) {
    try {
      double t = sw.Elapsed.TotalSeconds; float dt = (float)Math.Min(0.1, t - der); der = t;
      if (LkChargement.Ferme || t > 600) { Close(); return; }
      ang = (ang + 330 * dt) % 360;
      // chien de garde : la fenêtre de l'appli est là ?
      if (t - derVerif > 0.2) {
        derVerif = t;
        if (FenetrePrincipaleVisible()) { if (vuFenetre < 0) vuFenetre = t; } else vuFenetre = -1;
        if (vuFenetre >= 0 && t - vuFenetre > 2 && !LkChargement.Fin) LkChargement.Finish(null);
      }
      float p0 = LkChargement.Pct, p1 = LkChargement.Max; bool fin = LkChargement.Fin;
      // pendant une étape, la barre avance doucement vers la fin de l'étape sans la dépasser
      float cible = fin ? 100 : Math.Max(p0, Math.Min(p1 - 0.5f, aff + dt * 6f));
      if (cible > aff) aff += (cible - aff) * Math.Min(1f, dt * (fin ? 14f : 8f));
      if (fin) {
        double depuisFin = (Environment.TickCount - LkChargement.FinTick) / 1000.0;
        if (aff > 99.4f) aff = 100;
        // fondu seulement quand la fenêtre de l'appli est déjà bien visible (pas de bureau entre les deux)
        if (!fondu && aff >= 100 && (LkChargement.Pret || depuisFin > 2.5)) { fondu = true; debutFondu = t; }
        if (depuisFin > 4) { Close(); return; }   // fermeture forcée quoi qu'il arrive
      }
      if (fondu) {
        double op = 1 - (t - debutFondu) / 0.35; op = op * op * (3 - 2 * op);   // adoucissement
        if (op <= 0.02) { Close(); return; }
        Opacity = Math.Max(0.02, Math.Min(1, op));
      }
      Invalidate();
    } catch { try { Close(); } catch { } }
  }

  static GraphicsPath Arrondi(float x, float y, float w, float h, float r) {
    GraphicsPath p = new GraphicsPath(); float d = Math.Min(r * 2, Math.Min(w, h));
    if (d < 1) { p.AddRectangle(new RectangleF(x, y, w, h)); return p; }
    p.AddArc(x, y, d, d, 180, 90); p.AddArc(x + w - d, y, d, d, 270, 90); p.AddArc(x + w - d, y + h - d, d, d, 0, 90); p.AddArc(x, y + h - d, d, d, 90, 90); p.CloseFigure(); return p;
  }
  protected override void OnPaint(PaintEventArgs e) {
    try {
      Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      int W = ClientSize.Width, H = ClientSize.Height; double t = sw.Elapsed.TotalSeconds;
      using (Pen p = new Pen(bord, Math.Max(1f, S(1)))) g.DrawRectangle(p, 0, 0, W - 1, H - 1);
      float cx = W / 2f, cy = S(76), pu = (float)(0.5 + 0.5 * Math.Sin(t * 2.4));
      for (int i = 5; i >= 0; i--) {
        float r = S(30 + i * 7) * (1 + 0.05f * pu); int a = (int)(Math.Max(0, 26 - i * 4) * (0.55 + 0.45 * pu));
        using (SolidBrush b = new SolidBrush(Color.FromArgb(a, violet))) g.FillEllipse(b, cx - r, cy - r, 2 * r, 2 * r);
      }
      if (logo != null) g.DrawImage(logo, cx - S(28), cy - S(28), S(56), S(56));
      TextFormatFlags fl = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix;
      TextRenderer.DrawText(g, "HELIXFLUX", fT, new Rectangle(0, (int)S(112), W, (int)S(34)), acc, fl);
      TextRenderer.DrawText(g, "Optimisation  ·  by Lukzyr", fS, new Rectangle(0, (int)S(144), W, (int)S(20)), gris, fl);
      float xb = S(64), wb = W - 2 * xb, ye = S(188);
      using (Pen p = new Pen(Color.FromArgb(60, acc), S(2))) g.DrawEllipse(p, xb, ye, S(13), S(13));
      using (Pen p = new Pen(acc, S(2))) { p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; g.DrawArc(p, xb, ye, S(13), S(13), ang, 100); }
      TextRenderer.DrawText(g, LkChargement.Etape ?? "", fE, new Rectangle((int)(xb + S(22)), (int)(ye - S(4)), (int)(wb - S(70)), (int)S(22)), texte, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
      TextRenderer.DrawText(g, (int)Math.Floor(aff) + " %", fP, new Rectangle((int)(xb + wb - S(60)), (int)(ye - S(4)), (int)S(60), (int)S(22)), acc, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
      float yb = S(216), hb = S(6);
      using (GraphicsPath p = Arrondi(xb, yb, wb, hb, hb / 2)) using (SolidBrush b = new SolidBrush(piste)) g.FillPath(b, p);
      float wf = wb * Math.Min(100, aff) / 100;
      if (wf >= 1) {
        using (GraphicsPath p = Arrondi(xb, yb, Math.Max(wf, hb), hb, hb / 2)) {
          using (LinearGradientBrush lg = new LinearGradientBrush(new PointF(xb, 0), new PointF(xb + wb, 0), bleuLogo, violet)) g.FillPath(lg, p);
          float xr = xb + (float)((t * 0.6) % 1.4 - 0.2) * wb, wr = S(60);
          g.SetClip(p);
          using (LinearGradientBrush rb = new LinearGradientBrush(new PointF(xr - wr, 0), new PointF(xr + wr, 0), Color.Transparent, Color.Transparent)) {
            ColorBlend bl = new ColorBlend(3); bl.Colors = new[] { Color.FromArgb(0, 255, 255, 255), Color.FromArgb(110, 255, 255, 255), Color.FromArgb(0, 255, 255, 255) }; bl.Positions = new[] { 0f, 0.5f, 1f };
            rb.InterpolationColors = bl; g.FillRectangle(rb, xr - wr, yb, 2 * wr, hb);
          }
          g.ResetClip();
        }
      }
      TextRenderer.DrawText(g, LkChargement.Version ?? "", fV, new Rectangle(0, (int)S(238), W, (int)S(20)), gris, fl);
    } catch { }
  }
}
