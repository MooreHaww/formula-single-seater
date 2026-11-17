// BuildLayout.cs - port of cad/macros/BuildLayout.bas with the fixes from its first run.
// Builds cad/layout/master_layout.SLDPRT (run new-layout first for an empty part):
//   GROUND / CENTRE / FRONT_AXLE = default Front / Top / Right planes (car coordinates
//   are SolidWorks coordinates), car_params.txt linked as the equation file,
//   REAR_AXLE, MAIN_HOOP, FRONT_HOOP, WHEEL_CENTRE_HEIGHT offset planes whose distance
//   is an equation "D1@<plane>" = "<global variable>", FRONT_AXLE_AXIS and
//   REAR_AXLE_AXIS, hardpoint sketches HP_front_right / HP_rear_right with one named
//   reference point HP_<name> per hardpoint; save; close and reopen; checks;
//   cad/layout/build_layout_report.txt.
// Fixes against the VBA v1 run:
//   * Axes: the API returns True as 1 (not -1); VBA "If Not 1" is True, so v1 called
//     the created axes "refused". Here the result is checked by the feature created.
//   * Equations: AutomaticSolveOrder on; every line of car_params.txt is compared with
//     what SolidWorks loaded (missing names = the lines behind the Equations warning).
//   * Planes: the equation is added because LinkToFile is read correctly now (v1 read
//     the linked state through the same "Not 1" trap and skipped every equation).
//   * car_params.txt is guarded: its bytes are compared before and after; if SolidWorks
//     writes into it, the original is put back and the step fails.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class BuildLayout
    {
        static ModelDoc2 m;
        static Report rep;

        public static int Run()
        {
            string paramsFile = P("params", "car_params.txt");
            string reportFile = P("cad", "layout", "build_layout_report.txt");
            if (!File.Exists(paramsFile)) throw new StepStoppedException("Missing " + paramsFile);
            byte[] paramsBefore = File.ReadAllBytes(paramsFile);
            var par = ReadParams(paramsFile);
            foreach (var need in new[] { "wheelbase", "main_hoop_x", "front_hoop_x", "tyre_rolling_radius" })
                if (!par.ContainsKey(need)) throw new StepStoppedException("car_params.txt has no numeric value for " + need);
            var hpFront = HardpointNames(par, "f_"); var hpRear = HardpointNames(par, "r_");
            if (hpFront.Count == 0 || hpRear.Count == 0) throw new StepStoppedException("car_params.txt has no f_*/r_* hardpoint triples");

            m = Open(LayoutPath);
            if (m.GetType() != (int)swDocumentTypes_e.swDocPART) throw new StepStoppedException("master_layout is not a part");
            if (FindFeature(m, "GROUND") != null) throw new StepStoppedException("master_layout already has a GROUND plane (run new-layout for an empty part)");
            SetMmgs(m);
            var planes = TopFeatures(m).Where(f => f.GetTypeName2() == "RefPlane").Take(3).ToList();
            if (planes.Count < 3) throw new StepStoppedException("the three default planes were not found");
            rep = new Report();

            // 2. equation file
            var eq = m.GetEquationMgr();
            eq.AutomaticSolveOrder = true;
            eq.FilePath = paramsFile;
            eq.LinkToFile = true;
            bool upd = eq.UpdateValuesFromExternalEquationFile();
            rep.Note(eq.LinkToFile && eq.GetCount() > 0, "equation file " + (eq.LinkToFile ? "linked" : "NOT linked") + ": " + eq.GetCount() +
                     " equations / global variables loaded, update from file " + (upd ? "ok" : "returned false") + ", automatic solve order " + eq.AutomaticSolveOrder);
            string eqDiag = EquationDiagnostics(eq, paramsFile, par);

            // default planes renamed
            Named(planes[0], "GROUND"); Named(planes[1], "CENTRE"); Named(planes[2], "FRONT_AXLE");

            // 3. planes
            var fRear = OffsetPlane(planes[2], "REAR_AXLE", par["wheelbase"], 0, "wheelbase", eq);
            OffsetPlane(planes[2], "MAIN_HOOP", par["main_hoop_x"], 0, "main_hoop_x", eq);
            OffsetPlane(planes[2], "FRONT_HOOP", par["front_hoop_x"], 0, "front_hoop_x", eq);
            var fWheel = OffsetPlane(planes[0], "WHEEL_CENTRE_HEIGHT", par["tyre_rolling_radius"], 2, "tyre_rolling_radius", eq);

            // 4. axes
            MakeAxis(planes[2], fWheel, "FRONT_AXLE_AXIS");
            MakeAxis(fRear, fWheel, "REAR_AXLE_AXIS");

            // 5. hardpoints
            HardpointSketch(par, hpFront, "HP_front_right");
            HardpointSketch(par, hpRear, "HP_rear_right");
            // left side, mirrored in y (HPL_*): the suspension corners on the left mate to these
            HardpointSketch(par, hpFront, "HP_front_left", -1, "HPL_");
            HardpointSketch(par, hpRear, "HP_rear_left", -1, "HPL_");

            m.ClearSelection2(true);
            m.ForceRebuild3(false);
            m.ShowNamedView2("*Isometric", 7);
            m.ViewZoomtofit2();
            var errs = TrimTubes.AllFeatures(m).Where(f => TrimTubes.ErrorOf(f) != 0).Select(f => f.Name).ToList();
            rep.Note(errs.Count == 0, "features with rebuild errors: " + errs.Count + (errs.Count > 0 ? " (" + string.Join(", ", errs) + ")" : ""));

            // 6. save, guard car_params.txt, reopen and check again
            bool saved = Save(m, out int serr);
            rep.Note(saved, saved ? "saved " + m.GetPathName() : "NOT saved (error " + serr + ")");
            byte[] paramsAfter = File.ReadAllBytes(paramsFile);
            if (!paramsAfter.SequenceEqual(paramsBefore))
            {
                string diff = LineDiff(paramsBefore, paramsAfter);
                File.WriteAllBytes(paramsFile, paramsBefore);
                rep.Note(false, "car_params.txt was changed by SolidWorks while linked; the original was put back. Changes it made:\n" + diff);
            }
            else rep.Note(true, "car_params.txt unchanged by SolidWorks (byte compare before/after)");

            string path = m.GetPathName();
            App.CloseDoc(m.GetTitle());
            m = Open(path);
            var eq2 = m.GetEquationMgr();
            rep.Note(eq2.LinkToFile && eq2.GetCount() > 0, "after reopening: equation file " + (eq2.LinkToFile ? "linked" : "NOT linked") + ", " + eq2.GetCount() + " equations");
            foreach (var pl in new[] { Tuple.Create("REAR_AXLE", "wheelbase", 0), Tuple.Create("MAIN_HOOP", "main_hoop_x", 0),
                                       Tuple.Create("FRONT_HOOP", "front_hoop_x", 0), Tuple.Create("WHEEL_CENTRE_HEIGHT", "tyre_rolling_radius", 2) })
            {
                var f = FindFeature(m, pl.Item1);
                double pos = f == null ? double.NaN : PlaneOrigin(f, pl.Item3) * 1000;
                int idx = FindEquation(eq2, "D1@" + pl.Item1);
                rep.Note(f != null && Math.Abs(pos - par[pl.Item2]) < 0.01 && idx >= 0,
                         "after reopening: " + pl.Item1 + " at " + F(pos) + " mm (" + pl.Item2 + " = " + F(par[pl.Item2]) + "), " +
                         (idx >= 0 ? "driven by equation " + eq2.Equation[idx] : "NO equation"));
            }
            foreach (var ax in new[] { "FRONT_AXLE_AXIS", "REAR_AXLE_AXIS" })
            {
                var f = FindFeature(m, ax);
                rep.Note(f != null && f.GetTypeName2() == "RefAxis", "after reopening: " + ax + (f == null ? " missing" : " [" + f.GetTypeName2() + "]"));
            }
            int nHp = TopFeatures(m).Count(f => f.Name.StartsWith("HP_") && f.GetTypeName2() == "RefPoint");
            rep.Note(nHp == hpFront.Count + hpRear.Count, "after reopening: " + nHp + " reference points HP_* (" + (hpFront.Count + hpRear.Count) + " hardpoints)");
            int nHpl = TopFeatures(m).Count(f => f.Name.StartsWith("HPL_") && f.GetTypeName2() == "RefPoint");
            rep.Note(nHpl == hpFront.Count + hpRear.Count, "after reopening: " + nHpl + " reference points HPL_* (left side, mirrored)");

            string full = rep.Text("BuildLayout, " + path, "ALL PASS", "SOME STEPS FAILED") + "\n\n" + eqDiag;
            WriteReport(reportFile, full);
            Log(full.Length > 6000 ? full.Substring(0, 6000) + "\n... (full text in " + reportFile + ")" : full);
            return rep.AllPass ? 0 : 1;
        }

        // ------------------------------------------------------------------ equations
        static int FindEquation(EquationMgr eq, string token)
        {
            for (int i = 0; i < eq.GetCount(); i++) if (eq.Equation[i].Contains("\"" + token + "\"")) return i;
            return -1;
        }

        static string LhsName(string s)
        {
            s = s.Trim();
            if (!s.StartsWith("\"")) return null;
            int q = s.IndexOf('"', 1);
            return q > 1 ? s.Substring(1, q - 1) : null;
        }

        /// Every quoted line of car_params.txt vs what SolidWorks loaded: names not loaded, duplicates,
        /// numeric values that differ. These are the lines behind a warning on the Equations folder.
        static string EquationDiagnostics(EquationMgr eq, string paramsFile, Dictionary<string, double> par)
        {
            var lines = ReadLines(paramsFile);
            var fileNames = new List<Tuple<int, string, string>>();
            for (int k = 0; k < lines.Length; k++)
            {
                string nm = LhsName(lines[k]);
                if (nm != null) fileNames.Add(Tuple.Create(k + 1, nm, lines[k].Trim()));
            }
            var loaded = new Dictionary<string, int>();
            for (int i = 0; i < eq.GetCount(); i++) { string nm = LhsName(eq.Equation[i]); if (nm != null && !loaded.ContainsKey(nm)) loaded[nm] = i; }
            var sb = new StringBuilder("Equation check: " + fileNames.Count + " quoted lines in car_params.txt, " + eq.GetCount() + " equations loaded by SolidWorks, " +
                                       eq.GetDisabledEquationCount() + " disabled, EvaluateAll returned " + eq.EvaluateAll() + ", Status " + eq.Status + "\n");
            var dups = fileNames.GroupBy(t => t.Item2).Where(g => g.Count() > 1).ToList();
            sb.Append("Duplicate names in the file: " + (dups.Count == 0 ? "none" : string.Join(", ", dups.Select(g => g.Key + " (lines " + string.Join(", ", g.Select(t => t.Item1)) + ")"))) + "\n");
            var missing = fileNames.Where(t => !loaded.ContainsKey(t.Item2)).ToList();
            sb.Append("Lines SolidWorks did not load (" + missing.Count + "):\n");
            foreach (var t in missing) sb.Append("  line " + t.Item1 + ": " + (t.Item3.Length > 200 ? t.Item3.Substring(0, 200) + " ..." : t.Item3) + "\n");
            var bad = new List<string>();
            foreach (var kv in par)
                if (loaded.TryGetValue(kv.Key, out int i) && Math.Abs(eq.Value[i] - kv.Value) > 1e-6 * Math.Max(1, Math.Abs(kv.Value)))
                    bad.Add(kv.Key + ": file " + kv.Value.ToString(Inv) + ", SolidWorks " + eq.Value[i].ToString(Inv));
            sb.Append("Numeric values that differ from the file (" + bad.Count + "): " + (bad.Count == 0 ? "none" : string.Join("; ", bad)) + "\n");
            rep.Note(missing.Count == 0 && dups.Count == 0, "equations: " + (fileNames.Count - missing.Count) + " of " + fileNames.Count +
                     " lines of car_params.txt loaded" + (missing.Count > 0 ? ", NOT loaded: " + string.Join(", ", missing.Select(t => t.Item2 + " (line " + t.Item1 + ")")) : "") +
                     (dups.Count > 0 ? ", duplicate names: " + string.Join(", ", dups.Select(g => g.Key)) : ""));
            rep.Note(bad.Count == 0, "equations: numeric values equal to the file (" + par.Count + " numeric names)" + (bad.Count > 0 ? ", " + bad.Count + " differ" : ""));
            return sb.ToString();
        }

        static string LineDiff(byte[] a, byte[] b)
        {
            var la = Encoding.UTF8.GetString(a).Replace("\r", "").Split('\n');
            var lb = Encoding.UTF8.GetString(b).Replace("\r", "").Split('\n');
            var sa = new HashSet<string>(la); var sbs = new HashSet<string>(lb);
            var sb = new StringBuilder();
            foreach (var l in lb.Where(l => !sa.Contains(l)).Take(30)) sb.Append("    + " + l + "\n");
            foreach (var l in la.Where(l => !sbs.Contains(l)).Take(30)) sb.Append("    - " + l + "\n");
            if (la.Length != lb.Length || sb.Length == 0) sb.Append("    (lines " + la.Length + " -> " + lb.Length + (sb.Length == 0 ? "; only line endings or encoding differ" : "") + ")\n");
            return sb.ToString();
        }

        // ------------------------------------------------------------------ planes, axes
        static Feature OffsetPlane(Feature baseF, string nm, double value_mm, int axis, string globalName, EquationMgr eq)
        {
            Feature f = null; double pos = double.NaN;
            for (int attempt = 1; attempt <= 2; attempt++)
            {
                int opt = (int)swRefPlaneReferenceConstraints_e.swRefPlaneReferenceConstraint_Distance;
                if ((value_mm < 0) ^ (attempt == 2)) opt += (int)swRefPlaneReferenceConstraints_e.swRefPlaneReferenceConstraint_OptionFlip;
                m.ClearSelection2(true);
                baseF.Select2(false, 0);
                f = m.FeatureManager.InsertRefPlane(opt, Math.Abs(value_mm) / 1000, 0, 0, 0, 0) as Feature;
                if (f == null) { rep.Note(false, nm + ": InsertRefPlane refused"); return null; }
                pos = PlaneOrigin(f, axis) * 1000;
                if (Math.Abs(pos - value_mm) < 0.01) break;
                if (attempt == 1) { m.ClearSelection2(true); f.Select2(false, 0); m.Extension.DeleteSelection2((int)swDeleteSelectionOptions_e.swDelete_Absorbed); }
            }
            Named(f, nm);
            if (Math.Abs(pos - value_mm) >= 0.01) { rep.Note(false, nm + ": lands at " + F(pos) + " mm, expected " + F(value_mm)); return f; }
            // tie the distance to the global variable
            string dimName = "D1@" + nm;
            var dim = m.Parameter(dimName) as Dimension;
            if (dim == null) { rep.Note(false, nm + " at " + F(value_mm) + " mm, but no dimension " + dimName + " to drive"); return f; }
            string expr = "\"" + dimName + "\" = " + (value_mm < 0 ? "-" : "") + "\"" + globalName + "\"";
            // Add3 returns -1 for every form tried, linked or not (2026 SP2.1); Add2 adds it.
            int idx = eq.Add2(-1, expr, true);
            if (idx < 0) idx = eq.Add3(-1, expr, true, (int)swInConfigurationOpts_e.swAllConfiguration, null);
            m.ForceRebuild3(false);
            double pos2 = PlaneOrigin(f, axis) * 1000;
            rep.Note(idx >= 0 && Math.Abs(pos2 - value_mm) < 0.01, nm + " at " + F(pos2) + " mm" +
                     (idx >= 0 ? ", distance driven by " + expr : ", equation " + expr + " refused (value only)"));
            return f;
        }

        static double PlaneOrigin(Feature f, int axis)
        {
            var rp = f.GetSpecificFeature2() as RefPlane;
            var xf = rp?.Transform;
            return xf?.ArrayData is double[] d ? d[9 + axis] : double.NaN;
        }

        static void MakeAxis(Feature f1, Feature f2, string nm)
        {
            if (f1 == null || f2 == null) { rep.Note(false, nm + ": a plane is missing"); return; }
            m.ClearSelection2(true);
            f1.Select2(false, 0); f2.Select2(true, 0);
            int before = TopFeatures(m).Count(x => x.GetTypeName2() == "RefAxis");
            bool ret = m.InsertAxis2(true);
            var f = m.Extension.GetLastFeatureAdded() as Feature;
            int after = TopFeatures(m).Count(x => x.GetTypeName2() == "RefAxis");
            bool made = f != null && f.GetTypeName2() == "RefAxis" && after == before + 1;
            if (made) Named(f, nm);
            rep.Note(made, nm + (made ? " (" + f1.Name + " x " + f2.Name + ")" : ": no axis made") + ", InsertAxis2 returned " + ret);
            m.ClearSelection2(true);
        }

        // ------------------------------------------------------------------ hardpoints
        static void HardpointSketch(Dictionary<string, double> par, List<string> names, string sketchName, int ySign = 1, string prefix = "HP_")
        {
            var sk = m.SketchManager;
            m.ClearSelection2(true);
            sk.AddToDB = true;
            sk.Insert3DSketch(true);
            var pts = names.Select(n => sk.CreatePoint(par[n + "_x"] / 1000, ySign * par[n + "_y"] / 1000, par[n + "_z"] / 1000)).ToList();
            var feat = sk.ActiveSketch as Feature;
            sk.Insert3DSketch(true);
            sk.AddToDB = false;
            if (feat == null) feat = m.Extension.GetLastFeatureAdded() as Feature;
            Named(feat, sketchName);
            int made = 0; var bad = new List<string>();
            for (int k = 0; k < names.Count; k++)
            {
                Feature f = null;
                m.ClearSelection2(true);
                if (pts[k] != null && pts[k].Select4(false, null))
                {
                    object ret = m.FeatureManager.InsertReferencePoint((int)swRefPointType_e.swRefPointSketchPoint, 0, 0, 1);
                    f = (ret as object[])?.FirstOrDefault() as Feature ?? ret as Feature;
                }
                if (f == null) bad.Add(names[k]); else { Named(f, prefix + names[k]); made++; }
            }
            m.ClearSelection2(true);
            rep.Note(made == names.Count, sketchName + ": " + names.Count + " points, " + made + " named reference points " + prefix + "*" +
                     (bad.Count > 0 ? " (none for: " + string.Join(" ", bad) + ")" : ""));
        }

        static List<string> HardpointNames(Dictionary<string, double> par, string prefix) =>
            par.Keys.Where(k => k.StartsWith(prefix) && k.EndsWith("_x"))
               .Select(k => k.Substring(0, k.Length - 2))
               .Where(b => par.ContainsKey(b + "_y") && par.ContainsKey(b + "_z")).ToList();

        static void Named(Feature f, string nm)
        {
            if (f == null) { rep.Note(false, nm + ": no feature to rename"); return; }
            if (!Rename(f, nm)) rep.Note(false, nm + ": NOT renamed (is " + f.Name + ")");
        }
    }
}
