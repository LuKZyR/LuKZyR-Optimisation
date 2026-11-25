// LuKZyR Optimisation - lanceur .exe
// Demande les droits administrateur (manifeste requireAdministrator) puis lance l'interface PowerShell
// scripts\LuKZyR-Optimisation.ps1 située à côté de l'exe. Aucune dépendance (.NET Framework 4.x de Windows).
// v5.2 : affiche TOUT DE SUITE un écran de chargement (même look que celui de l'appli) pendant que
// PowerShell démarre ; il passe la main dès que l'écran de chargement de l'appli (ou la fenêtre) apparaît.
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("LuKZyR Optimisation")]
[assembly: AssemblyProduct("LuKZyR Optimisation")]
[assembly: AssemblyDescription("Lanceur de LuKZyR Optimisation")]
[assembly: AssemblyCompany("Lukzyr")]
[assembly: AssemblyCopyright("Copyright © 2026 Lukzyr")]
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]
[assembly: AssemblyInformationalVersion("0.1.0-beta")]   // v0.1 bêta = version interne 5.6

class Chargement : Form {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowW(string cls, string titre);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
  protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); try { int v = 2; DwmSetWindowAttribute(Handle, 33, ref v, 4); } catch { } }
  // la fenêtre doit être VISIBLE (sinon un trou entre les deux écrans pendant que PowerShell la prépare)
  static bool FenetreVisible(string titre) { IntPtr h = FindWindowW(null, titre); return h != IntPtr.Zero && IsWindowVisible(h); }
  readonly Color fond, bord, texte, gris, acc, piste, violet = Color.FromArgb(140, 82, 255);
  readonly float s; readonly string etape, version; Image logo; readonly Stopwatch sw = Stopwatch.StartNew();
  readonly Timer tm = new Timer(); float aff, ang; double der; Process proc; readonly Func<Process> lancer; bool fondu;
  public Chargement(bool clair, bool en, string racine, string version, Func<Process> lancer) {
    this.lancer = lancer; this.version = version;
    if (clair) { fond = C("#f6f6fa"); bord = C("#dcdce8"); texte = C("#1a1a24"); gris = C("#55556e"); acc = C("#7c4dff"); piste = C("#e3e3ec"); }
    else { fond = C("#0f0f15"); bord = C("#26263a"); texte = C("#f2f2f7"); gris = C("#8a8aa3"); acc = C("#a78bfa"); piste = C("#24242e"); }
    etape = en ? "Starting..." : "Démarrage...";
    using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) s = Math.Max(1f, g.DpiX / 96f);
    Text = "LuKZyR Optimisation - lanceur"; FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.CenterScreen;
    ClientSize = new Size((int)(440 * s), (int)(270 * s)); BackColor = fond; ShowInTaskbar = true; DoubleBuffered = true;
    try { string ico = Path.Combine(racine, @"assets\lukzyr.ico"); if (File.Exists(ico)) Icon = new Icon(ico); } catch { }
    try { string png = Path.Combine(racine, @"assets\logo.png"); if (File.Exists(png)) logo = Image.FromFile(png); else if (Icon != null) logo = new Icon(Icon, 64, 64).ToBitmap(); } catch { }
    tm.Interval = 30; tm.Tick += Tick;
  }
  static Color C(string h) { return ColorTranslator.FromHtml(h); }
  float S(float v) { return v * s; }
  protected override void OnShown(EventArgs e) {
    base.OnShown(e); tm.Start(); Refresh();
    try { proc = lancer(); } catch (Exception ex) { tm.Stop(); Hide(); MessageBox.Show("Impossible de lancer PowerShell :\n" + ex.Message, "LuKZyR Optimisation", MessageBoxButtons.OK, MessageBoxIcon.Error); Close(); }
  }
  void Tick(object o, EventArgs e) { try { Tick2(); } catch { try { tm.Stop(); Close(); } catch { } } }
  void Tick2() {
    double t = sw.Elapsed.TotalSeconds; float dt = (float)Math.Min(0.2, t - der); der = t;
    ang = (ang + 330 * dt) % 360;
    float cible = (float)(2 + 8 * (1 - Math.Exp(-t / 4.0)));   // le lanceur ne fait que démarrer PowerShell : 0 -> 10 %
    if (cible > aff) aff += (cible - aff) * Math.Min(1f, dt * 7);
    if (!fondu && t > 0.3) {
      // l'écran de chargement de l'appli (même place, même taille) ou la fenêtre est là : on passe la main
      if (FenetreVisible("LuKZyR Optimisation - chargement") || FenetreVisible("LuKZyR Optimisation")) { tm.Stop(); Close(); return; }
      bool fini = false; try { fini = proc != null && proc.HasExited; } catch { }
      // v5.6 : PowerShell s'est arrêté sans ouvrir la fenêtre : code 3 = l'appli a déjà affiché son message ;
      // autre code d'erreur = on affiche nous-mêmes l'erreur (sortie d'erreur de PowerShell) au lieu de disparaître
      if (fini) {
        int code = 0; try { code = proc.ExitCode; } catch { }
        if (code != 0 && code != 3) { tm.Stop(); Hide(); Lanceur.SignalerPlantage(code); Close(); return; }
        if (t > 3) fondu = true;
      }
      if (t > 120) fondu = true;
    }
    if (fondu) { Opacity -= dt * 4.5; if (Opacity <= 0.03) { tm.Stop(); Close(); return; } }
    Invalidate();
  }
  static GraphicsPath Arrondi(float x, float y, float w, float h, float r) {
    GraphicsPath p = new GraphicsPath(); float d = Math.Min(r * 2, Math.Min(w, h));
    if (d < 1) { p.AddRectangle(new RectangleF(x, y, w, h)); return p; }
    p.AddArc(x, y, d, d, 180, 90); p.AddArc(x + w - d, y, d, d, 270, 90); p.AddArc(x + w - d, y + h - d, d, d, 0, 90); p.AddArc(x, y + h - d, d, d, 90, 90); p.CloseFigure(); return p;
  }
  protected override void OnPaint(PaintEventArgs e) {
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
    using (Font f = new Font("Segoe UI", S(24), FontStyle.Bold, GraphicsUnit.Pixel)) TextRenderer.DrawText(g, "LuKZyR", f, new Rectangle(0, (int)S(112), W, (int)S(34)), acc, fl);
    using (Font f = new Font("Segoe UI", S(12.5f), FontStyle.Regular, GraphicsUnit.Pixel)) TextRenderer.DrawText(g, "Optimisation", f, new Rectangle(0, (int)S(144), W, (int)S(20)), gris, fl);
    float xb = S(64), wb = W - 2 * xb, ye = S(188);
    using (Pen p = new Pen(Color.FromArgb(60, acc), S(2))) g.DrawEllipse(p, xb, ye, S(13), S(13));
    using (Pen p = new Pen(acc, S(2))) { p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; g.DrawArc(p, xb, ye, S(13), S(13), ang, 100); }
    using (Font f = new Font("Segoe UI", S(12.5f), FontStyle.Regular, GraphicsUnit.Pixel)) TextRenderer.DrawText(g, etape, f, new Rectangle((int)(xb + S(22)), (int)(ye - S(4)), (int)(wb - S(70)), (int)S(22)), texte, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix);
    using (Font f = new Font("Segoe UI", S(12.5f), FontStyle.Bold, GraphicsUnit.Pixel)) TextRenderer.DrawText(g, (int)aff + " %", f, new Rectangle((int)(xb + wb - S(60)), (int)(ye - S(4)), (int)S(60), (int)S(22)), acc, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
    float yb = S(216), hb = S(6);
    using (GraphicsPath p = Arrondi(xb, yb, wb, hb, hb / 2)) using (SolidBrush b = new SolidBrush(piste)) g.FillPath(b, p);
    float wf = wb * Math.Min(100, aff) / 100;
    if (wf >= 1) using (GraphicsPath p = Arrondi(xb, yb, Math.Max(wf, hb), hb, hb / 2)) using (LinearGradientBrush lg = new LinearGradientBrush(new PointF(xb, 0), new PointF(xb + wb, 0), C("#12e0ff"), violet)) g.FillPath(lg, p);
    using (Font f = new Font("Segoe UI", S(10.5f), FontStyle.Regular, GraphicsUnit.Pixel)) TextRenderer.DrawText(g, version, f, new Rectangle(0, (int)S(238), W, (int)S(20)), gris, fl);
  }
}

static class Lanceur {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int MessageBoxW(IntPtr h, string texte, string titre, uint type);
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

  static string dossierDonnees = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Lukzyr");
  public static string FichierErreurs = Path.Combine(dossierDonnees, "erreurs-powershell.txt");
  // v5.6 : message visible + journal quand l'appli s'arrête au démarrage
  public static void SignalerPlantage(int code) {
    string detail = "";
    try { if (File.Exists(FichierErreurs)) { detail = File.ReadAllText(FichierErreurs).Trim(); if (detail.Length > 1200) detail = "..." + detail.Substring(detail.Length - 1200); } } catch { }
    string journal = Path.Combine(dossierDonnees, "plantage-demarrage.txt");
    try { File.AppendAllText(journal, "[" + DateTime.Now.ToString("s") + "] code " + code + "\r\n" + detail + "\r\n"); } catch { }
    MessageBoxW(IntPtr.Zero, "LuKZyR Optimisation n'a pas pu démarrer (code " + code + ").\n\n" + (detail.Length > 0 ? detail + "\n\n" : "") + "Détails enregistrés dans :\n" + journal, "LuKZyR Optimisation", 0x10);
  }

  [STAThread]
  static int Main() {
    string dossier = AppDomain.CurrentDomain.BaseDirectory;
    string script = Path.Combine(dossier, "scripts", "LuKZyR-Optimisation.ps1");
    if (!File.Exists(script)) {
      MessageBoxW(IntPtr.Zero, "Fichier introuvable :\n" + script + "\n\nGarde l'exe dans le dossier LuKZyR-Optimisation (avec le dossier scripts).", "LuKZyR Optimisation", 0x10);
      return 1;
    }
    string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
    if (!File.Exists(ps)) ps = "powershell.exe";
    bool lance = false;
    Func<Process> lancer = () => {
      if (lance) return null; lance = true;
      // v5.6 : la sortie d'erreur de PowerShell va dans un fichier (cmd /c ... 2> fichier) : lisible si l'appli
      // s'arrête au démarrage, sans tuyau qui se fermerait quand le lanceur disparaît
      try { Directory.CreateDirectory(dossierDonnees); File.Delete(FichierErreurs); } catch { }
      string cmd = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
      ProcessStartInfo si = new ProcessStartInfo(cmd, "/d /c \"\"" + ps + "\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" 2>\"" + FichierErreurs + "\"\"");
      si.UseShellExecute = false; si.CreateNoWindow = true; si.WorkingDirectory = dossier;
      return Process.Start(si);
    };
    // Préférences de l'appli (thème, langue) pour un écran de chargement identique
    bool clair = false, en = false;
    try {
      using (RegistryKey k = Registry.CurrentUser.OpenSubKey(@"Software\Lukzyr")) {
        if (k != null) { clair = string.Equals(k.GetValue("Theme") as string, "clair"); string l = k.GetValue("Langue") as string; en = l == "en" || (l != "fr" && System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName != "fr"); }
        else en = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName != "fr";
      }
    } catch { }
    string version = "v0.1" + (en ? " beta" : " bêta");   // version publique (interne 5.6)
    try {
      SetProcessDPIAware();
      Application.EnableVisualStyles();
      Application.Run(new Chargement(clair, en, dossier, version, lancer));
      return 0;
    } catch (Exception) {
      // Écran de chargement impossible : on lance quand même l'appli
      try { lancer(); return 0; } catch (Exception ex2) { MessageBoxW(IntPtr.Zero, "Impossible de lancer PowerShell :\n" + ex2.Message, "LuKZyR Optimisation", 0x10); return 2; }
    }
  }
}
