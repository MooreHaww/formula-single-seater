// BuildAssembly.cs - port of cad/macros/BuildAssembly.bas.
// Top assembly cad/formula_single_seater.SLDASM from the master layout, the chassis
// and the build123d STEP bodies in cad/step (top level only; cad/step/cfd is not read).
// Every part is modelled in car coordinates and sits at the origin:
//   layout fixed; every other part placed with an identity transform and mated with
//   three Coincident plane mates to GROUND / CENTRE / FRONT_AXLE (fixed if refused);
//   left tyres and rims as second instances turned 180 deg about the vertical axis
//   through their axle, fixed; interference (coincidence and the chassis' own tube
//   contacts not counted); mass; save; cad/build_assembly_report.txt.
// Wing supports and the packaging envelopes (env_*) get a document density so their
// SolidWorks mass equals the budget mass (SupportDensity).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class BuildAssembly
    {
        static ModelDoc2 am;
        static AssemblyDoc asm;
        static Report rep;
        static Component2 layoutComp;

        public static int Run()
        {
            string reportFile = P("cad", "build_assembly_report.txt");
            if (!File.Exists(LayoutPath) || !File.Exists(ChassisPath))
                throw new StepStoppedException("Missing " + (File.Exists(LayoutPath) ? "" : LayoutPath + " (BuildLayout) ") + (File.Exists(ChassisPath) ? "" : ChassisPath + " (BuildTubes)"));
            var par = ReadParams(P("params", "car_params.txt"));
            double wheelbase = par.ContainsKey("wheelbase") ? par["wheelbase"] : 1550;
            rep = new Report();

            // STEP -> SLDPRT (once)
            var parts = new List<string> { ChassisPath };
            var steps = Directory.GetFiles(P("cad", "step"), "*.step", SearchOption.TopDirectoryOnly).OrderBy(x => x).ToList();
            int nImported = 0;
            // a part that is to be replaced is held by the open assembly: close that first
            // (without saving; the file on disk is what counts)
            if (steps.Any(st => { string pp = P("cad", "body", Path.GetFileNameWithoutExtension(st) + ".SLDPRT");
                                  return File.Exists(pp) && File.GetLastWriteTime(st) > File.GetLastWriteTime(pp); }))
                CloseIfOpen(AssemblyPath);
            foreach (var st in steps)
            {
                string pp = P("cad", "body", Path.GetFileNameWithoutExtension(st) + ".SLDPRT");
                if (File.Exists(pp) && File.GetLastWriteTime(st) > File.GetLastWriteTime(pp))
                {   // the STEP was regenerated after the import: import again, keep the old part in cad\body\old
                    CloseIfOpen(pp);
                    rep.Info(Path.GetFileName(st) + " is newer than its part: old part moved to " + MoveAside(pp));
                }
                if (!File.Exists(pp)) { if (ImportStep(st, pp)) nImported++; }
                if (File.Exists(pp)) parts.Add(pp);
            }
            rep.Note(parts.Count == steps.Count + 1, "parts: chassis + " + (parts.Count - 1) + " of " + steps.Count + " STEP bodies as cad\\body\\*.SLDPRT (" + nImported + " imported in this run)");

            // the assembly
            bool isNew = !File.Exists(AssemblyPath);
            if (isNew)
            {
                string tmpl = App.GetUserPreferenceStringValue((int)swUserPreferenceStringValue_e.swDefaultTemplateAssembly);
                am = App.NewDocument(tmpl, 0, 0, 0) as ModelDoc2;
                if (am == null) throw new StepStoppedException("No assembly from the default template " + tmpl);
                SetMmgs(am);
            }
            else am = Open(AssemblyPath);
            asm = (AssemblyDoc)am;
            var present = Components().GroupBy(c => c.GetPathName().ToLowerInvariant()).ToDictionary(g => g.Key, g => g.First());

            // layout first, fixed
            if (present.TryGetValue(LayoutPath.ToLowerInvariant(), out layoutComp)) rep.Note(true, "master_layout: already in the assembly");
            else
            {
                layoutComp = AddAt(LayoutPath, Identity());
                if (layoutComp == null) rep.Note(false, "master_layout: AddComponent5 refused, nothing can be mated");
                else { FixIt(layoutComp); rep.Note(layoutComp.IsFixed(), "master_layout: inserted, " + (layoutComp.IsFixed() ? "fixed" : "NOT fixed")); }
            }

            int nMated = 0, nFixed = 0, nKept = 0;
            foreach (var pp in parts)
            {
                if (present.ContainsKey(pp.ToLowerInvariant())) { nKept++; continue; }
                var c = AddAt(pp, Identity());
                if (c == null) { rep.Note(false, Path.GetFileName(pp) + ": AddComponent5 refused"); continue; }
                if (MateToLayout(c)) nMated++;
                else { FixIt(c); nFixed++; rep.Note(c.IsFixed(), Path.GetFileName(pp) + ": plane mates refused, fixed in place instead"); }
            }
            rep.Note(true, "parts: " + nMated + " mated to GROUND/CENTRE/FRONT_AXLE, " + nFixed + " fixed instead, " + nKept + " already there");

            // left wheels
            int nLeft = 0;
            foreach (var w in new[] { "tyre_front", "rim_front", "tyre_rear", "rim_rear" })
            {
                string wp = P("cad", "body", w + ".SLDPRT");
                if (!File.Exists(wp) || Components().Count(c => string.Equals(c.GetPathName(), wp, StringComparison.OrdinalIgnoreCase)) >= 2) continue;
                var c = AddAt(wp, TurnedAboutZ(w.EndsWith("rear") ? wheelbase / 1000 : 0));
                if (c == null) rep.Note(false, w + " left: AddComponent5 refused");
                else { FixIt(c); nLeft++; }
            }
            if (nLeft > 0) rep.Note(true, "left wheels: " + nLeft + " instances turned 180 deg about the axle's vertical axis, fixed");

            am.ClearSelection2(true);
            am.ForceRebuild3(false);
            am.ShowNamedView2("*Isometric", 7);
            am.ViewZoomtofit2();

            // placement check: every component's bounding box against its part's own box (identity placement)
            var errs = TrimTubes.AllFeatures(am).Where(f => TrimTubes.ErrorOf(f) != 0).Select(f => f.Name).ToList();
            rep.Note(errs.Count == 0, "assembly features (mates) with errors: " + errs.Count + (errs.Count > 0 ? " (" + string.Join(", ", errs.Take(20)) + ")" : ""));
            rep.Info("components: " + Components().Count);

            // interference
            var idm = asm.InterferenceDetectionManager;
            if (idm == null) rep.Note(false, "interference detection: manager not available");
            else
            {
                idm.TreatCoincidenceAsInterference = false;
                idm.IncludeMultibodyPartInterferences = false;
                var ints = idm.GetInterferences() as object[] ?? new object[0];
                // grouped per component pair; below 1 mm3 = touching (tyre on rim, flap on rim face)
                var all = new List<Tuple<string, double>>();
                var wheres = new List<string>();
                foreach (Interference itf in ints)
                {
                    var comps = (itf.Components as object[] ?? new object[0]).OfType<Component2>().Select(c => c.Name2).OrderBy(x => x);
                    string where = "";
                    try
                    {   // where: the interference body's box centre in car coordinates, mm
                        if (itf.GetInterferenceBody() is Body2 ib && ib.GetBodyBox() is double[] bx)
                            where = " at (" + F((bx[0] + bx[3]) * 500, "0") + ", " + F((bx[1] + bx[4]) * 500, "0") + ", " + F((bx[2] + bx[5]) * 500, "0") + ")";
                    }
                    catch { }
                    all.Add(Tuple.Create(string.Join(" / ", comps), itf.Volume * 1e9));
                    if (where != "") wheres.Add(string.Join(" / ", comps) + where + " " + F(itf.Volume * 1e9, "0") + " mm3");
                }
                idm.Done();
                var groups = all.GroupBy(t => t.Item1).Select(g => new { pair = g.Key, n = g.Count(), vol = g.Sum(t => t.Item2) }).ToList();
                var clash = groups.Where(g => g.vol >= 1).OrderByDescending(g => g.vol).ToList();
                var touch = groups.Where(g => g.vol < 1).Select(g => g.pair).ToList();
                if (touch.Count > 0) rep.Info("touching only (< 1 mm3, not a clash): " + string.Join(", ", touch));
                if (clash.Count == 0) rep.Note(true, "interference: none");
                else
                {
                    // a design finding about the bodies' geometry, not a build fault: reported, does not stop the rebuild
                    rep.Warn(false, "interference: " + clash.Count + " component pair(s) overlap, " + F(clash.Sum(g => g.vol) / 1000, "0.0") +
                             " cm3 in all (bodywork / wings / wheels vs frame: geometry to fix in cad/generate, see the list)");
                    foreach (var g in clash)
                    {
                        rep.Line("    " + g.pair + ": " + F(g.vol, "0") + " mm3 in " + g.n + " place(s)");
                        foreach (var wline in wheres.Where(x => x.StartsWith(g.pair + " at ")).Take(60)) rep.Line("        " + wline.Substring(g.pair.Length + 1));
                    }
                }
            }
            var mp = am.Extension.CreateMassProperty() as MassProperty;
            if (mp != null)
            {
                var cg = (double[])mp.CenterOfMass;
                rep.Info("mass of what is in the assembly: " + F(mp.Mass) + " kg, CG x " + F(cg[0] * 1000, "0") + " / y " + F(cg[1] * 1000, "0") + " / z " +
                         F(cg[2] * 1000, "0") + " mm (SolidWorks' own sum, not the car: the packaging envelopes and wing supports carry their budget masses, the other imported bodies are at SolidWorks' default density and the suspension is added later; cad/generate/cad_cg_report.txt has the CG from the geometry at budget masses)");
            }

            // save
            int e = 0, wn = 0;
            bool saved = isNew ? am.Extension.SaveAs3(AssemblyPath, (int)swSaveAsVersion_e.swSaveAsCurrentVersion, (int)swSaveAsOptions_e.swSaveAsOptions_Silent, null, null, ref e, ref wn)
                               : am.Save3((int)swSaveAsOptions_e.swSaveAsOptions_Silent, ref e, ref wn);
            rep.Note(saved, saved ? "saved " + AssemblyPath : "NOT saved (error " + e + ")");
            string full = rep.Text("BuildAssembly, " + AssemblyPath);
            WriteReport(reportFile, full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }

        static List<Component2> Components() => (asm.GetComponents(true) as object[] ?? new object[0]).OfType<Component2>().ToList();

        static bool ImportStep(string stepPath, string partPath)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(partPath));
            int err = 0;
            var m = App.LoadFile4(stepPath, "r", null, ref err) as ModelDoc2;
            if (m == null) { rep.Note(false, Path.GetFileName(stepPath) + ": STEP import refused (error " + err + ")"); return false; }
            SupportDensity(m, Path.GetFileNameWithoutExtension(partPath));
            int e = 0, w = 0;
            bool ok = m.Extension.SaveAs3(partPath, (int)swSaveAsVersion_e.swSaveAsCurrentVersion, (int)swSaveAsOptions_e.swSaveAsOptions_Silent, null, null, ref e, ref w);
            rep.Note(ok, Path.GetFileName(stepPath) + ": imported" + (ok ? " and saved as cad\\body\\" + Path.GetFileName(partPath) : ", NOT saved (error " + e + ")"));
            App.CloseDoc(m.GetTitle());
            return ok;
        }

        /// Wing supports (fw_support_R/L, rw_support_R/L, 2026-11-28): CFRP skin over a foam core, which a
        /// single solid cannot carry as a material. The part gets the sandwich's equivalent density
        /// (mass / volume from cad/generate/supports_mass.csv, written by build_parts.py) as its document
        /// density, so SolidWorks' mass of the part equals the budget line. Checked against the CSV mass.
        /// Packaging envelopes (env_*, 2026-11-28): space reservations, not designed parts. Same idea: the
        /// density is the budget mass / volume from cad/generate/envelopes_mass.csv (columns part, budget_line,
        /// mass_kg, volume_mm3, ...), so the assembly's mass properties carry the budget mass at the envelope.
        static void SupportDensity(ModelDoc2 m, string name)
        {
            bool sup = name.Contains("_support_"), env = name.StartsWith("env_");
            if (!sup && !env) return;
            string csv = P("cad", "generate", sup ? "supports_mass.csv" : "envelopes_mass.csv");
            var row = File.Exists(csv) ? Csv(csv).FirstOrDefault(r => r.Length >= 6 && r[0] == name) : null;
            if (row == null) { rep.Note(false, name + ": no row in " + csv + " (run BuildBodies first)"); return; }
            double vol = Val(row[sup ? 1 : 3]) * 1e-9, mass = Val(row[sup ? 5 : 2]);   // m3, kg
            double rho = mass / vol;                                       // kg/m3
            bool set = m.Extension.SetUserPreferenceDouble((int)swUserPreferenceDoubleValue_e.swMaterialPropertyDensity,
                                                           (int)swUserPreferenceOption_e.swDetailingNoOptionSpecified, rho);
            double got = Mass(m);
            rep.Note(set && Math.Abs(got - mass) <= 0.01 * mass,
                     name + ": density " + F(rho, "0.0") + " kg/m3 (" + (sup ? "CFRP 1.5 mm skin + PMI foam core, equivalent" : "packaging envelope: budget line " + row[1] + " / volume") +
                     "), SolidWorks mass " + F(got, "0.000") + " kg vs " + F(mass, "0.000") + " kg in " + Path.GetFileName(csv) + " (within 1 %)");
        }

        static Component2 AddAt(string path, MathTransform xf)
        {
            int e = 0, w = 0;
            var m = App.OpenDoc6(path, (int)swDocumentTypes_e.swDocPART, (int)swOpenDocOptions_e.swOpenDocOptions_Silent, "", ref e, ref w);
            int ae = 0;
            App.ActivateDoc3(am.GetTitle(), false, (int)swRebuildOnActivation_e.swDontRebuildActiveDoc, ref ae);
            if (m == null) return null;
            Log("  adding " + Path.GetFileName(path));
            var c = asm.AddComponent5(path, (int)swAddComponentConfigOptions_e.swAddComponentConfigOptions_CurrentSelectedConfig, "", false, "", 0, 0, 0);
            // the part's own window is not needed once it is a component (the assembly keeps the model loaded);
            // with every part window left open SolidWorks crashed twice in OpenDoc6 here (RPC failed, 2026-11-28, 56 components)
            if (!string.Equals(m.GetPathName(), am.GetPathName(), StringComparison.OrdinalIgnoreCase)) App.CloseDoc(m.GetTitle());
            App.ActivateDoc3(am.GetTitle(), false, (int)swRebuildOnActivation_e.swDontRebuildActiveDoc, ref ae);
            if (c == null) return null;
            if (xf != null) c.Transform2 = xf;
            return c;
        }

        static bool MateToLayout(Component2 c)
        {
            if (layoutComp == null) return false;
            var m = c.GetModelDoc2() as ModelDoc2;
            if (m == null) return false;
            var names = TopFeatures(m).Where(f => f.GetTypeName2() == "RefPlane").Take(3).Select(f => f.Name).ToList();
            if (names.Count < 3) return false;
            string[] targets = { "GROUND", "CENTRE", "FRONT_AXLE" }, tags = { "_G", "_C", "_X" };
            bool ok = true;
            for (int k = 0; k < 3; k++)
                if (!MatePlanes(layoutComp.FeatureByName(targets[k]) as Feature, c.FeatureByName(names[k]) as Feature, c.Name2 + tags[k])) ok = false;
            return ok;
        }

        static bool MatePlanes(Feature f1, Feature f2, string mateName)
        {
            if (f1 == null || f2 == null) return false;
            Mate2 mt = null;
            foreach (int align in new[] { (int)swMateAlign_e.swMateAlignALIGNED, (int)swMateAlign_e.swMateAlignCLOSEST })
            {
                am.ClearSelection2(true);
                f1.Select2(false, 1); f2.Select2(true, 1);
                int st = 0;
                mt = asm.AddMate5((int)swMateType_e.swMateCOINCIDENT, align, false, 0, 0, 0, 0, 0, 0, 0, 0, false, false, 0, out st) as Mate2;
                if (mt != null) break;
            }
            am.ClearSelection2(true);
            if (mt == null) return false;
            Rename(mt as Feature, mateName);
            return true;
        }

        static void FixIt(Component2 c)
        {
            am.ClearSelection2(true);
            if (c.Select4(false, null, false)) asm.FixComponent();
            am.ClearSelection2(true);
        }

        static MathTransform Identity() => Xf(new double[] { 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0 });

        /// 180 deg about the vertical (Z) axis through (xAxle, 0): (x, y, z) -> (2 xAxle - x, -y, z). Metres.
        static MathTransform TurnedAboutZ(double xAxle) => Xf(new double[] { -1, 0, 0, 0, -1, 0, 0, 0, 1, 2 * xAxle, 0, 0, 1, 0, 0, 0 });

        static MathTransform Xf(double[] d) => (MathTransform)((MathUtility)App.GetMathUtility()).CreateTransform(d);
    }
}
