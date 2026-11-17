// SaveStandardViews.cs - port of cad/macros/SaveStandardViews.bas.
// Opens the given part or assembly, saves six PNG views (iso, front, right, top, rear,
// bottom) to media/views/<doc>_<config>_<view>.png on a plain white background,
// shaded with edges, zoom to fit; restores the user's background settings.
// Report: media/views/<doc>_views_report.txt (each file checked for size).
using System;
using System.IO;
using System.Linq;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class SaveStandardViews
    {
        public static int Run(string file)
        {
            if (file == "") throw new StepStoppedException("SaveStandardViews needs a file: a .SLDPRT or .SLDASM path");
            string path = Path.IsPathRooted(file) ? file : Path.Combine(Repo, file);
            if (!File.Exists(path)) throw new StepStoppedException("No such file " + path);
            var m = Open(path);
            string outDir = P("media", "views");
            Directory.CreateDirectory(outDir);
            string doc = Path.GetFileNameWithoutExtension(path);
            string cfg = (m.ConfigurationManager.ActiveConfiguration.Name ?? "Default");
            foreach (var c in new[] { '\\', '/', ':', '*', '?', '"', '<', '>', '|', ' ' }) cfg = cfg.Replace(c, '_');
            while (cfg.Contains("__")) cfg = cfg.Replace("__", "_");
            cfg = cfg.Trim('_');     // "Default<As Machined>" -> Default_As_Machined
            var rep = new Report();

            int pApp = (int)swUserPreferenceIntegerValue_e.swColorsBackgroundAppearance;
            int pCol = (int)swUserPreferenceIntegerValue_e.swSystemColorsViewportBackground;
            int pGrad = (int)swUserPreferenceToggle_e.swColorsGradientPartBackground;
            int oldApp = App.GetUserPreferenceIntegerValue(pApp), oldCol = App.GetUserPreferenceIntegerValue(pCol);
            bool oldGrad = App.GetUserPreferenceToggle(pGrad);
            try
            {
                App.SetUserPreferenceIntegerValue(pApp, (int)swColorsBackgroundAppearance_e.swColorsBackgroundAppearance_Plain);
                App.SetUserPreferenceIntegerValue(pCol, 0xFFFFFF);
                App.SetUserPreferenceToggle(pGrad, false);
                if (m.ActiveView is ModelView v) v.DisplayMode = (int)swViewDisplayMode_e.swViewDisplayMode_ShadedWithEdges;

                // Car views, not SolidWorks' standard ones: the car is modelled Z up (GROUND = Front
                // plane), x rearwards from the front axle, so SolidWorks' "Top" is an upside-down side
                // view. Each view = (screen right, screen up) in car axes; the viewer looks from right x up.
                double s2 = Math.Sqrt(2), s6 = Math.Sqrt(6);
                var views = new (string name, double[] r, double[] u)[] {
                    ("iso",    new[] { 1 / s2, -1 / s2, 0 }, new[] { 1 / s6, 1 / s6, 2 / s6 }),  // from front-left, above
                    ("front",  new[] { 0.0, -1, 0 },         new[] { 0.0, 0, 1 }),               // from ahead of the nose
                    ("side",   new[] { 1.0, 0, 0 },          new[] { 0.0, 0, 1 }),               // nose to the left
                    ("top",    new[] { 1.0, 0, 0 },          new[] { 0.0, 1, 0 }),               // plan, nose to the left
                    ("rear",   new[] { 0.0, 1, 0 },          new[] { 0.0, 0, 1 }),
                    ("bottom", new[] { 1.0, 0, 0 },          new[] { 0.0, -1, 0 }) };
                var mu = (MathUtility)App.GetMathUtility();
                foreach (var vw in views)
                {
                    double[] r = vw.r, u = vw.u, n = { r[1] * u[2] - r[2] * u[1], r[2] * u[0] - r[0] * u[2], r[0] * u[1] - r[1] * u[0] };
                    // ModelView.Orientation3: the columns of the 3x3 are screen right, screen up, toward the viewer (probed)
                    var d = new double[] { r[0], u[0], n[0], r[1], u[1], n[1], r[2], u[2], n[2], 0, 0, 0, 1, 0, 0, 0 };
                    var mv = (ModelView)m.ActiveView;
                    mv.Orientation3 = (MathTransform)mu.CreateTransform(d);
                    m.ViewZoomtofit2();
                    m.GraphicsRedraw2();
                    var back = (double[])((MathTransform)mv.Orientation3).ArrayData;
                    bool oriented = Enumerable.Range(0, 9).All(i => Math.Abs(back[i] - d[i]) < 1e-3);
                    if (!oriented) rep.Note(false, vw.name + ": view orientation not taken (read back " + string.Join(" ", back.Take(9).Select(x => F(x, "0.00"))) + ")");
                    string vname = vw.name;
                    string outFile = Path.Combine(outDir, doc + "_" + cfg + "_" + vname + ".png");
                    DateTime t0 = DateTime.Now.AddSeconds(-1);
                    int e = 0, w = 0;
                    bool ok = m.Extension.SaveAs3(outFile, (int)swSaveAsVersion_e.swSaveAsCurrentVersion, (int)swSaveAsOptions_e.swSaveAsOptions_Silent, null, null, ref e, ref w);
                    var fi = new FileInfo(outFile);
                    bool fresh = fi.Exists && fi.LastWriteTime >= t0 && fi.Length > 5000;
                    rep.Note(ok && fresh, vname + ": " + (ok ? "" : "SaveAs3 refused (error " + e + "), ") +
                             (fi.Exists ? Path.GetFileName(outFile) + ", " + (fi.Length / 1024) + " kB" + (fresh ? "" : " (old or nearly empty)") : "no file"));
                }
            }
            finally
            {
                App.SetUserPreferenceIntegerValue(pApp, oldApp);
                App.SetUserPreferenceIntegerValue(pCol, oldCol);
                App.SetUserPreferenceToggle(pGrad, oldGrad);
                m.GraphicsRedraw2();
            }
            bool restored = App.GetUserPreferenceIntegerValue(pApp) == oldApp && App.GetUserPreferenceIntegerValue(pCol) == oldCol;
            rep.Note(restored, "background settings restored to the user's own");
            string full = rep.Text("SaveStandardViews, " + path);
            WriteReport(Path.Combine(outDir, doc + "_views_report.txt"), full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }
    }
}
