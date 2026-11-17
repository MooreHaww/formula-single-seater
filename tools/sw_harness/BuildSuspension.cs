// BuildSuspension.cs - the four double-wishbone corners as simple parts, mated into the
// car assembly at the master-layout hardpoints, and the kinematic check.
//
//   swh SuspensionParts      24 parts in cad\suspension\<corner>_<part>.SLDPRT (FR FL RR RL x
//                            lwb uwb upright hub tie push), built from params\car_params.txt
//   swh SuspensionAssembly   inserts them into cad\formula_single_seater.SLDASM, mates every
//                            joint (point-to-point coincident = ball joint / pivot), locks
//                            each tyre and rim to its hub, adds the wheel-height driver
//   swh SuspensionCheck      sweeps wheel travel by the driver mates, reads the solved poses,
//                            writes cad\suspension\suspension_report.txt (camber, toe, roll
//                            centre, motion ratio, half-track, roll camber, clashes)
//
// Each part is drawn in car coordinates at the static (design) position, so it goes in
// at the identity transform. Points (named reference points) carry the joints:
//   lwb, uwb   P_IN_FWD P_IN_AFT P_OUT          two tube legs (the A-arm)
//   upright    P_LB P_UB P_TIE P_PUSH P_WC P_AX P_FWD P_CP, axis A_SPIN (P_WC-P_AX)
//   hub        P_WC P_AX, axis A_SPIN           a short tube along the spindle
//   tie        P_IN P_OUT                       tie rod (front) / toe link (rear)
//   push       P_OUT P_IN, axis A_ROD           pushrod
// Mates: wishbone inner points to the layout HP_ (right) / HPL_ (left) points: a hinge;
// outer points to the upright: ball joints; tie rod both ends: ball joints; hub on the
// upright's spindle (P_WC coincident, A_SPIN coincident); pushrod outer point to the
// upright, its axis through the layout pushrod_in point (the rocker is not modelled: no
// rocker geometry in car_params.txt, so the pushrod slides through its inner point like a
// damper, which is exactly how suspension_geometry.m measures the motion ratio);
// Drive_<corner>: distance P_WC (upright) to GROUND = wheel-centre height.
// The members are cut back from the joints (rod ends and ball joints are not modelled):
// 20 mm at inboard pivots, 15 mm at ball joints, 30 mm at the pushrod's rocker end.
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
    static class BuildSuspension
    {
        public static readonly string[] Corners = { "FR", "FL", "RR", "RL" };
        public static readonly string[] PartNames = { "lwb", "uwb", "upright", "hub", "tie", "push" };
        static string Dir => P("cad", "suspension");
        public static string PartPath(string corner, string part) => Path.Combine(Dir, corner + "_" + part + ".SLDPRT");
        static string Profile => P("cad", "weldment_profiles", "formula", "tube_round", "25.4x1.6.SLDLFP");          // upright, hub
        static string LinkProfile => P("cad", "weldment_profiles", "formula", "tube_round", "15.9x0.9.SLDLFP");     // wishbones, tie rods, pushrods
        public const double JOINT_R = 12;          // ball joint / rod end housing radius, mm
        public const double PIVOT_MOUNT_MM = 40;   // chassis contact this close to an inboard pivot = the bracket

        // ------------------------------------------------------------------ geometry from params
        public class Corner
        {
            public string Name, Axle, TieName;   // "FR", "f", "tierod"
            public int S;               // +1 right, -1 left
            public double Camber;       // static camber, deg, negative = top inward
            public Dictionary<string, double[]> P = new Dictionary<string, double[]>();   // mm, car coordinates
            public string Hp(string n) => (S > 0 ? "HP_" : "HPL_") + Axle + "_" + n;   // layout point name
        }

        public static Corner MakeCorner(Dictionary<string, double> par, string name)
        {
            var c = new Corner { Name = name, Axle = name[0] == 'F' ? "f" : "r", S = name[1] == 'R' ? 1 : -1 };
            string a = c.Axle;
            Func<string, double[]> hp = n =>
            {
                foreach (var k in new[] { "_x", "_y", "_z" })
                    if (!par.ContainsKey(a + "_" + n + k)) throw new StepStoppedException("car_params.txt has no " + a + "_" + n + k);
                return new[] { par[a + "_" + n + "_x"], c.S * par[a + "_" + n + "_y"], par[a + "_" + n + "_z"] };
            };
            foreach (var n in new[] { "lwb_in_fwd", "lwb_in_aft", "lwb_out", "uwb_in_fwd", "uwb_in_aft", "uwb_out", "pushrod_out", "pushrod_in" })
                c.P[n] = hp(n);
            string tie = a == "f" ? "tierod" : "toelink";
            c.P["tie_in"] = hp(tie + "_in"); c.P["tie_out"] = hp(tie + "_out");
            c.TieName = tie;
            double track = a == "f" ? par["track_front"] : par["track_rear"];
            double xw = a == "f" ? 0 : par["wheelbase"];
            c.Camber = a == "f" ? par["static_camber_front"] : par["static_camber_rear"];
            var wc = new[] { xw, c.S * track / 2, par["tyre_rolling_radius"] };
            // spindle axis outward; negative camber (top inward) tips the outward axis upward
            var ax = new[] { 0, c.S * Math.Cos(c.Camber * Math.PI / 180), -Math.Sin(c.Camber * Math.PI / 180) };
            c.P["wc"] = wc;
            c.P["ax"] = Add(wc, ax, 100);
            c.P["fwd"] = new[] { wc[0] - 100, wc[1], wc[2] };
            c.P["cp"] = new[] { wc[0], wc[1], 0.0 };
            return c;
        }

        // ------------------------------------------------------------------ step 1: parts
        public static int Parts()
        {
            var par = ReadParams(P("params", "car_params.txt"));
            if (!File.Exists(Profile)) throw new StepStoppedException("profile not found: " + Profile);
            if (!File.Exists(LinkProfile) && MakeProfile.Run(new[] { "15.9", "0.9" }) != 0) throw new StepStoppedException("could not make " + LinkProfile);
            var rep = new Report();
            Directory.CreateDirectory(Dir);
            // the parts may be held by the open assembly: close it (without saving; the file on disk is what counts)
            CloseIfOpen(AssemblyPath);
            foreach (var cn in Corners)
            {
                var c = MakeCorner(par, cn);
                var p = c.P;
                var mid = Lerp(p["lwb_out"], p["uwb_out"], 0.5);
                var pushFoot = ClosestOnLine(p["pushrod_out"], p["lwb_out"], p["uwb_out"]);
                var axU = Unit(Sub(p["ax"], p["wc"]));
                var defs = new Dictionary<string, Tuple<Dictionary<string, double[]>, List<double[][]>, string[][]>>
                {
                    ["lwb"] = Def(new[] { "P_IN_FWD", "P_IN_AFT", "P_OUT" }, new[] { p["lwb_in_fwd"], p["lwb_in_aft"], p["lwb_out"] },
                                  new[] { Cut(p["lwb_in_fwd"], p["lwb_out"], 20, 15), Cut(p["lwb_in_aft"], p["lwb_out"], 20, 15) }, null),
                    ["uwb"] = Def(new[] { "P_IN_FWD", "P_IN_AFT", "P_OUT" }, new[] { p["uwb_in_fwd"], p["uwb_in_aft"], p["uwb_out"] },
                                  new[] { Cut(p["uwb_in_fwd"], p["uwb_out"], 20, 15), Cut(p["uwb_in_aft"], p["uwb_out"], 20, 15) }, null),
                    ["upright"] = Def(new[] { "P_LB", "P_UB", "P_TIE", "P_PUSH", "P_WC", "P_AX", "P_FWD", "P_CP" },
                                      new[] { p["lwb_out"], p["uwb_out"], p["tie_out"], p["pushrod_out"], p["wc"], p["ax"], p["fwd"], p["cp"] },
                                      new[] { Cut(p["lwb_out"], p["uwb_out"], 15, 15), Cut(mid, p["tie_out"], 0, 15), new[] { mid, p["wc"] },
                                              Cut(pushFoot, p["pushrod_out"], 0, 10) },
                                      new[] { new[] { "A_SPIN", "P_WC", "P_AX" } }),
                    ["hub"] = Def(new[] { "P_WC", "P_AX" }, new[] { p["wc"], p["ax"] },
                                  new[] { new[] { Add(p["wc"], axU, -10), Add(p["wc"], axU, 45) } },
                                  new[] { new[] { "A_SPIN", "P_WC", "P_AX" } }),
                    ["tie"] = Def(new[] { "P_IN", "P_OUT" }, new[] { p["tie_in"], p["tie_out"] },
                                  new[] { Cut(p["tie_in"], p["tie_out"], 15, 15) }, null),
                    ["push"] = Def(new[] { "P_OUT", "P_IN" }, new[] { p["pushrod_out"], p["pushrod_in"] },
                                   new[] { Cut(p["pushrod_out"], p["pushrod_in"], 15, 30) },
                                   new[] { new[] { "A_ROD", "P_OUT", "P_IN" } }),
                };
                foreach (var kv in defs)
                {
                    string path = PartPath(cn, kv.Key);
                    string prof = kv.Key == "upright" || kv.Key == "hub" ? Profile : LinkProfile;
                    string why = MakePart(path, kv.Value.Item1, kv.Value.Item2, kv.Value.Item3, prof);
                    rep.Note(why == "", cn + "_" + kv.Key + ": " + (why == "" ? kv.Value.Item1.Count + " points, " + kv.Value.Item2.Count + " members" +
                             (kv.Value.Item3 != null ? ", axis " + string.Join(" ", kv.Value.Item3.Select(x => x[0])) : "") +
                             ", tube " + Path.GetFileNameWithoutExtension(prof) : why));
                }
            }
            string full = rep.Text("SuspensionParts, " + Dir);
            WriteReport(Path.Combine(Dir, "suspension_parts_report.txt"), full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }

        static Tuple<Dictionary<string, double[]>, List<double[][]>, string[][]> Def(string[] names, double[][] pts, double[][][] members, string[][] axes)
        {
            var d = new Dictionary<string, double[]>();
            for (int k = 0; k < names.Length; k++) d[names[k]] = pts[k];
            return Tuple.Create(d, members.ToList(), axes);
        }

        /// New part at path (old one moved to cad\suspension\old): members, named points, axes; saved and closed. "" = ok.
        static string MakePart(string path, Dictionary<string, double[]> pts, List<double[][]> members, string[][] axes, string profile)
        {
            CloseIfOpen(path);
            MoveAside(path);
            var m = NewPartAt(path);
            var fm = m.FeatureManager;
            var sk = m.SketchManager;
            var why = new List<string>();
            // members
            m.ClearSelection2(true);
            sk.AddToDB = true;
            sk.Insert3DSketch(true);
            var segs = members.Select(s => sk.CreateLine(s[0][0] / 1000, s[0][1] / 1000, s[0][2] / 1000, s[1][0] / 1000, s[1][1] / 1000, s[1][2] / 1000)).ToList();
            var skf = sk.ActiveSketch as Feature;
            sk.Insert3DSketch(true);
            sk.AddToDB = false;
            if (skf == null) skf = m.Extension.GetLastFeatureAdded() as Feature;
            if (skf != null) Rename(skf, "SKELETON");
            if (segs.Any(x => x == null)) why.Add("a skeleton line was refused");
            else
            {
                m.ClearSelection2(true);
                var mem = BuildTubes.MakeMember(fm, profile, segs.Cast<object>().ToArray(), false);
                if (mem == null) why.Add("structural member refused (" + CreateErrors(fm) + ")");
                else Rename(mem, "MEMBERS");
            }
            // points
            m.ClearSelection2(true);
            sk.AddToDB = true;
            sk.Insert3DSketch(true);
            var names = pts.Keys.ToList();
            var sp = names.Select(n => sk.CreatePoint(pts[n][0] / 1000, pts[n][1] / 1000, pts[n][2] / 1000)).ToList();
            var pkf = sk.ActiveSketch as Feature;
            sk.Insert3DSketch(true);
            sk.AddToDB = false;
            if (pkf == null) pkf = m.Extension.GetLastFeatureAdded() as Feature;
            if (pkf != null) Rename(pkf, "POINTS");
            var refs = new Dictionary<string, Feature>();
            for (int k = 0; k < names.Count; k++)
            {
                m.ClearSelection2(true);
                Feature f = null;
                if (sp[k] != null && sp[k].Select4(false, null))
                {
                    object ret = fm.InsertReferencePoint((int)swRefPointType_e.swRefPointSketchPoint, 0, 0, 1);
                    f = (ret as object[])?.FirstOrDefault() as Feature ?? ret as Feature;
                }
                if (f == null) why.Add("no reference point " + names[k]); else { Rename(f, names[k]); refs[names[k]] = f; }
            }
            // axes through two reference points
            foreach (var a in axes ?? new string[0][])
            {
                m.ClearSelection2(true);
                if (!refs.ContainsKey(a[1]) || !refs.ContainsKey(a[2])) { why.Add("axis " + a[0] + ": points missing"); continue; }
                refs[a[1]].Select2(false, 0); refs[a[2]].Select2(true, 0);
                m.InsertAxis2(true);
                var f = m.Extension.GetLastFeatureAdded() as Feature;
                if (f == null || f.GetTypeName2() != "RefAxis") why.Add("axis " + a[0] + " refused"); else Rename(f, a[0]);
            }
            m.ClearSelection2(true);
            if (pkf != null && pkf.Select2(false, 0)) m.BlankSketch();
            if (skf != null && skf.Select2(false, 0)) m.BlankSketch();
            m.ClearSelection2(true);
            m.ForceRebuild3(false);
            var errs = TrimTubes.AllFeatures(m).Where(f => TrimTubes.ErrorOf(f) != 0).Select(f => f.Name).ToList();
            if (errs.Count > 0) why.Add("features in error: " + string.Join(", ", errs));
            int nb = Bodies((PartDoc)m).Length;
            if (nb != members.Count) why.Add(nb + " bodies for " + members.Count + " members");
            if (!Save(m, out int se)) why.Add("not saved (error " + se + ")");
            App.CloseDoc(m.GetTitle());
            return string.Join("; ", why);
        }

        // ------------------------------------------------------------------ step 2: assembly
        static ModelDoc2 am;
        static AssemblyDoc asm;

        public static int Assemble()
        {
            if (!File.Exists(AssemblyPath)) throw new StepStoppedException("Missing " + AssemblyPath + " (run BuildAssembly)");
            foreach (var cn in Corners) foreach (var pn in PartNames)
                    if (!File.Exists(PartPath(cn, pn))) throw new StepStoppedException("Missing " + PartPath(cn, pn) + " (run SuspensionParts)");
            var par = ReadParams(P("params", "car_params.txt"));
            var rep = new Report();
            am = Open(AssemblyPath); asm = (AssemblyDoc)am;
            var layout = Comps().FirstOrDefault(c => Same(c.GetPathName(), LayoutPath));
            if (layout == null) throw new StepStoppedException("master_layout is not in the assembly");
            var ground = layout.FeatureByName("GROUND") as Feature;
            if (ground == null) throw new StepStoppedException("no GROUND plane in the layout component");

            int nIns = 0, nMates = 0; var bad = new List<string>();
            foreach (var cn in Corners)
            {
                var c = MakeCorner(par, cn);
                var comp = new Dictionary<string, Component2>();
                bool already = false;
                foreach (var pn in PartNames)
                {
                    string path = PartPath(cn, pn);
                    var have = Comps().FirstOrDefault(x => Same(x.GetPathName(), path));
                    if (have != null) { comp[pn] = have; already = true; continue; }
                    var x2 = AddAt(path);
                    if (x2 == null) { bad.Add(cn + "_" + pn + ": AddComponent5 refused"); continue; }
                    comp[pn] = x2; nIns++;
                }
                if (already) { rep.Info(cn + ": suspension components already in the assembly, mates left as they are"); continue; }
                if (comp.Count < PartNames.Length) continue;
                Func<string, string, Feature> F2 = (pn, fn) => comp[pn].FeatureByName(fn) as Feature;
                Func<string, Feature> L = n => layout.FeatureByName(c.Hp(n)) as Feature;
                var mates = new List<Tuple<Feature, Feature, int, string>>
                {
                    T(F2("lwb", "P_IN_FWD"), L("lwb_in_fwd"), cn + "_lwb_fwd_pivot"),
                    T(F2("lwb", "P_IN_AFT"), L("lwb_in_aft"), cn + "_lwb_aft_pivot"),
                    T(F2("uwb", "P_IN_FWD"), L("uwb_in_fwd"), cn + "_uwb_fwd_pivot"),
                    T(F2("uwb", "P_IN_AFT"), L("uwb_in_aft"), cn + "_uwb_aft_pivot"),
                    T(F2("upright", "P_LB"), F2("lwb", "P_OUT"), cn + "_lower_balljoint"),
                    T(F2("upright", "P_UB"), F2("uwb", "P_OUT"), cn + "_upper_balljoint"),
                    T(F2("tie", "P_IN"), L(c.TieName + "_in"), cn + "_tie_inner"),
                    T(F2("tie", "P_OUT"), F2("upright", "P_TIE"), cn + "_tie_outer"),
                    T(F2("hub", "P_WC"), F2("upright", "P_WC"), cn + "_hub_centre"),
                    T(F2("hub", "A_SPIN"), F2("upright", "A_SPIN"), cn + "_hub_axis"),
                    T(F2("push", "P_OUT"), F2("upright", "P_PUSH"), cn + "_push_outer"),
                    T(L("pushrod_in"), F2("push", "A_ROD"), cn + "_push_inner_on_axis"),
                };
                foreach (var mt in mates)
                {
                    if (mt.Item1 == null || mt.Item2 == null) { bad.Add(mt.Item4 + ": a point or axis is missing"); continue; }
                    if (Mate(mt.Item1, mt.Item2, (int)swMateType_e.swMateCOINCIDENT, 0, false, mt.Item4) != null) nMates++;
                    else bad.Add(mt.Item4 + ": AddMate5 refused");
                }
                // wheel-height driver: distance from the upright's wheel centre to GROUND
                double h = par["tyre_rolling_radius"];
                var drv = Mate(F2("upright", "P_WC"), ground, (int)swMateType_e.swMateDISTANCE, h, false, "Drive_" + cn);
                if (drv == null) bad.Add("Drive_" + cn + ": distance mate refused");
                else
                {
                    am.EditRebuild3();
                    double z = World(comp["upright"], c.P["wc"])[2];
                    if (Math.Abs(z - h) > 0.01)
                    {   // the mate took the other side of the plane: flip it
                        Delete(drv);
                        drv = Mate(F2("upright", "P_WC"), ground, (int)swMateType_e.swMateDISTANCE, h, true, "Drive_" + cn);
                        am.EditRebuild3();
                        z = drv == null ? double.NaN : World(comp["upright"], c.P["wc"])[2];
                    }
                    rep.Note(Math.Abs(z - h) <= 0.01, "Drive_" + cn + ": wheel centre at z " + F(z, "0.00") + " mm (" + F(h, "0") + ")");
                    nMates++;
                }
                // tyre and rim: off the layout, locked to the hub
                foreach (var w in new[] { "tyre", "rim" })
                {
                    string wp = P("cad", "body", w + (c.Axle == "f" ? "_front" : "_rear") + ".SLDPRT");
                    var wc = Comps().Where(x => Same(x.GetPathName(), wp)).FirstOrDefault(x => Math.Sign(BoxCentre(x)[1]) == c.S);
                    if (wc == null) { bad.Add(cn + " " + w + ": not in the assembly"); continue; }
                    foreach (var tag in new[] { "_G", "_C", "_X" })
                    {
                        var f = FindFeatureDeep(am, wc.Name2 + tag);
                        if (f != null) Delete(f);
                    }
                    if (wc.IsFixed()) { am.ClearSelection2(true); wc.Select4(false, null, false); asm.UnfixComponent(); am.ClearSelection2(true); }
                    var lk = MateComps(comp["hub"], wc, cn + "_" + w + "_on_hub");
                    if (lk == null) bad.Add(cn + " " + w + ": lock mate to the hub refused"); else nMates++;
                }
            }
            am.ForceRebuild3(false);
            var errs = TrimTubes.AllFeatures(am).Where(f => TrimTubes.ErrorOf(f) != 0).Select(f => f.Name).ToList();
            rep.Note(bad.Count == 0, "components inserted: " + nIns + ", mates made: " + nMates + (bad.Count > 0 ? "; problems: " + string.Join("; ", bad) : ""));
            rep.Note(errs.Count == 0, "assembly features (mates) with errors: " + errs.Count + (errs.Count > 0 ? " (" + string.Join(", ", errs.Take(20)) + ")" : ""));
            // static pose must be the design position: every upright point where it was drawn
            foreach (var cn in Corners)
            {
                var c = MakeCorner(par, cn);
                var up = Comps().FirstOrDefault(x => Same(x.GetPathName(), PartPath(cn, "upright")));
                if (up == null) continue;
                double dmax = new[] { "lwb_out", "uwb_out", "tie_out", "pushrod_out", "wc" }.Max(n => Dist(World(up, c.P[n]), c.P[n]));
                rep.Note(dmax < 0.05, cn + ": static pose, upright points within " + F(dmax, "0.000") + " mm of the hardpoints");
            }
            int e = 0, wn = 0;
            bool saved = am.Save3((int)swSaveAsOptions_e.swSaveAsOptions_Silent, ref e, ref wn);
            rep.Note(saved, saved ? "saved " + AssemblyPath : "NOT saved (error " + e + ")");
            string full = rep.Text("SuspensionAssembly, " + AssemblyPath);
            WriteReport(Path.Combine(Dir, "suspension_assembly_report.txt"), full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }

        static Tuple<Feature, Feature, int, string> T(Feature a, Feature b, string n) => Tuple.Create(a, b, 0, n);

        static Mate2 Mate(Feature a, Feature b, int type, double dist_mm, bool flip, string name)
        {
            Mate2 mt = null;
            foreach (int align in new[] { (int)swMateAlign_e.swMateAlignCLOSEST, (int)swMateAlign_e.swMateAlignALIGNED })
            {
                am.ClearSelection2(true);
                a.Select2(false, 1); b.Select2(true, 1);
                int st;
                double d = dist_mm / 1000;
                mt = asm.AddMate5(type, align, flip, d, d, d, 0, 0, 0, 0, 0, false, false, 0, out st) as Mate2;
                if (mt != null) break;
            }
            am.ClearSelection2(true);
            if (mt != null) Rename(mt as Feature, name);
            return mt;
        }

        static Mate2 MateComps(Component2 a, Component2 b, string name)
        {
            am.ClearSelection2(true);
            var sm = (SelectionMgr)am.SelectionManager;
            var sd = (SelectData)sm.CreateSelectData(); sd.Mark = 1;
            a.Select4(false, sd, false); b.Select4(true, sd, false);
            int st;
            var mt = asm.AddMate5((int)swMateType_e.swMateLOCK, (int)swMateAlign_e.swMateAlignCLOSEST, false, 0, 0, 0, 0, 0, 0, 0, 0, false, false, 0, out st) as Mate2;
            am.ClearSelection2(true);
            if (mt != null) Rename(mt as Feature, name);
            return mt;
        }

        static void Delete(object f)
        {
            am.ClearSelection2(true);
            if (f is Feature ff) ff.Select2(false, 0);
            am.Extension.DeleteSelection2(0);
            am.ClearSelection2(true);
        }

        /// Insert a part at the origin. Tried three times: in one rebuild (2026-11-17) AddComponent5 refused two
        /// freshly written parts once and took them on the next rebuild.
        static Component2 AddAt(string path)
        {
            for (int attempt = 1; attempt <= 3; attempt++)
            {
                int e = 0, w = 0;
                var m = App.OpenDoc6(path, (int)swDocumentTypes_e.swDocPART, (int)swOpenDocOptions_e.swOpenDocOptions_Silent, "", ref e, ref w);
                int ae = 0;
                App.ActivateDoc3(am.GetTitle(), false, (int)swRebuildOnActivation_e.swDontRebuildActiveDoc, ref ae);
                var c = m == null ? null : asm.AddComponent5(path, (int)swAddComponentConfigOptions_e.swAddComponentConfigOptions_CurrentSelectedConfig, "", false, "", 0, 0, 0);
                if (c != null) { if (attempt > 1) Log(Path.GetFileName(path) + ": inserted on attempt " + attempt); return c; }
                Log(Path.GetFileName(path) + ": attempt " + attempt + " failed (OpenDoc6 " + (m == null ? "null, error " + e + ", warning " + w : "ok") + ")");
                CloseIfOpen(path);
                System.Threading.Thread.Sleep(1000);
            }
            return null;
        }

        static List<Component2> Comps() => (asm.GetComponents(true) as object[] ?? new object[0]).OfType<Component2>().ToList();
        static bool Same(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
        static double[] BoxCentre(Component2 c) => c.GetBox(false, false) is double[] b ? new[] { (b[0] + b[3]) * 500, (b[1] + b[4]) * 500, (b[2] + b[5]) * 500 } : new double[3];

        /// A point of a component's part (mm, part = car coordinates at static) where it is now in the assembly (mm).
        public static double[] World(Component2 c, double[] p)
        {
            var mu = (MathUtility)App.GetMathUtility();
            var mp = (MathPoint)mu.CreatePoint(new[] { p[0] / 1000, p[1] / 1000, p[2] / 1000 });
            var r = (MathPoint)mp.MultiplyTransform(c.Transform2);
            var d = (double[])r.ArrayData;
            return new[] { d[0] * 1000, d[1] * 1000, d[2] * 1000 };
        }

        // ------------------------------------------------------------------ step 3: check
        public class Pose { public double Travel, Camber, Toe, Dy, Push, Rc, WcZ, LegErr; public double[] Lb, Ub, Wc, Cp; }

        public static int Check(string[] args)
        {
            if (!File.Exists(AssemblyPath)) throw new StepStoppedException("Missing " + AssemblyPath);
            var par = ReadParams(P("params", "car_params.txt"));
            double bump = par.ContainsKey("wheel_travel_bump") ? par["wheel_travel_bump"] : 30;
            double droop = par.ContainsKey("wheel_travel_droop") ? par["wheel_travel_droop"] : 30;
            double h0 = par["tyre_rolling_radius"];
            var rep = new Report();
            am = Open(AssemblyPath); asm = (AssemblyDoc)am;
            var drv = Corners.ToDictionary(cn => cn, cn => FindFeatureDeep(am, "Drive_" + cn));
            if (drv.Values.Any(v => v == null)) throw new StepStoppedException("no Drive_<corner> mates (run SuspensionAssembly)");
            var up = Corners.ToDictionary(cn => cn, cn => Comps().FirstOrDefault(x => Same(x.GetPathName(), PartPath(cn, "upright"))));
            var travels = new List<double>();
            for (double t = -droop; t <= bump + 1e-9; t += 5) travels.Add(t);
            var res = Corners.ToDictionary(cn => cn, cn => new List<Pose>());
            var sb = new StringBuilder();
            var failSolve = new List<string>();
            foreach (double t in travels)
            {
                foreach (var cn in Corners) SetDistance(drv[cn], h0 + t);
                bool ok = am.EditRebuild3();
                foreach (var cn in Corners)
                {
                    var c = MakeCorner(par, cn);
                    var q = Measure(c, up[cn], t);
                    res[cn].Add(q);
                    if (Math.Abs(q.WcZ - (h0 + t)) > 0.05 || q.LegErr > 0.05)
                        failSolve.Add(cn + " at " + F(t, "0") + " mm: wheel centre z " + F(q.WcZ, "0.00") + ", link length error " + F(q.LegErr, "0.000") + " mm");
                }
            }
            rep.Note(failSolve.Count == 0, "mates solved at every step (" + travels.Count + " steps, " + F(-droop, "0") + " to +" + F(bump, "0") +
                     " mm; wheel centre at the demanded height and every wishbone leg and tie rod at its drawn length, 0.05 mm)" +
                     (failSolve.Count > 0 ? ": " + string.Join("; ", failSolve.Take(8)) : ""));
            // left and right must agree (mirror)
            double asym = 0;
            foreach (var pr in new[] { Tuple.Create("FR", "FL"), Tuple.Create("RR", "RL") })
                for (int i = 0; i < travels.Count; i++)
                    asym = Math.Max(asym, Math.Max(Math.Abs(res[pr.Item1][i].Camber - res[pr.Item2][i].Camber), Math.Abs(res[pr.Item1][i].Toe - res[pr.Item2][i].Toe)));
            rep.Note(asym < 0.01, "left and right corners agree (mirror): largest camber/toe difference " + F(asym, "0.0000") + " deg");

            // numbers, front and rear (right-hand corners), compared with suspension_geometry.m
            var mat = MatlabResults();
            sb.Append("\nWheel travel sweep (right-hand corners; + = bump; camber negative = top inward; toe + = toe-in)\n");
            foreach (var cn in new[] { "FR", "RR" })
            {
                sb.Append("\n" + cn + "\n  travel   camber    toe     half-track  pushrod  roll centre\n");
                foreach (var q in res[cn])
                    sb.Append("  " + F(q.Travel, "+0;-0;0").PadLeft(5) + "  " + F(q.Camber, "0.000").PadLeft(7) + "  " + F(q.Toe, "0.000").PadLeft(6) + "  " +
                              F(q.Dy, "0.00").PadLeft(9) + "  " + F(q.Push, "0.00").PadLeft(7) + "  " + F(q.Rc, "0.0").PadLeft(8) + "\n");
            }
            sb.Append("\nSummary              front       rear      suspension_geometry.m (F / R)\n");
            var sum = new Dictionary<string, double[]>();
            foreach (var cn in new[] { "FR", "RR" })
            {
                var L = res[cn];
                double[] x = L.Select(q => q.Travel).ToArray();
                var q0 = L.First(q => Math.Abs(q.Travel) < 1e-9);
                sum[cn] = new[] {
                    Slope(x, L.Select(q => q.Camber).ToArray()),
                    L.Max(q => q.Toe) - L.Min(q => q.Toe),
                    q0.Rc,
                    Math.Abs(Slope(x, L.Select(q => q.Push).ToArray())) * (cn[0] == 'F' ? Par(par, "rocker_ratio_front", 1) : Par(par, "rocker_ratio_rear", 1)),
                    L.Max(q => Math.Abs(q.Dy)),
                    L.Min(q => q.Rc), L.Max(q => q.Rc), q0.Camber, q0.Toe };
            }
            string[] lab = { "camber gain (deg/mm)", "bump steer (deg)", "roll centre (mm)", "motion ratio", "half-track max (mm)" };
            string[] fmt = { "0.0000", "0.000", "0.0", "0.000", "0.00" };
            double[] tol = { 0.002, 0.01, 2.0, 0.01, double.NaN };
            for (int k = 0; k < lab.Length; k++)
            {
                string mref = mat != null && k < 4 ? F(mat[k][0], fmt[k]) + " / " + F(mat[k][1], fmt[k]) : "";
                sb.Append("  " + lab[k].PadRight(22) + F(sum["FR"][k], fmt[k]).PadLeft(8) + "  " + F(sum["RR"][k], fmt[k]).PadLeft(8) + "      " + mref + "\n");
                if (mat != null && k < 4)
                {
                    bool ok = Math.Abs(sum["FR"][k] - mat[k][0]) <= tol[k] && Math.Abs(sum["RR"][k] - mat[k][1]) <= tol[k];
                    rep.Note(ok, lab[k] + ": SolidWorks F " + F(sum["FR"][k], fmt[k]) + " / R " + F(sum["RR"][k], fmt[k]) + ", suspension_geometry.m F " +
                             F(mat[k][0], fmt[k]) + " / R " + F(mat[k][1], fmt[k]) + " (agree within " + F(tol[k], fmt[k]) + ")");
                }
            }
            if (mat == null) rep.Note(false, "no 'Results:' line from suspension_geometry.m in car_params.txt to compare with");
            sb.Append("  roll centre over travel: front " + F(sum["FR"][5], "0") + " to " + F(sum["FR"][6], "0") + " mm, rear " + F(sum["RR"][5], "0") + " to " + F(sum["RR"][6], "0") + " mm\n");
            sb.Append("  static camber / toe: front " + F(sum["FR"][7], "0.00") + " / " + F(sum["FR"][8], "0.00") + " deg, rear " + F(sum["RR"][7], "0.00") + " / " + F(sum["RR"][8], "0.00") + " deg\n");

            // roll: body rolls by phi, the outer wheel goes into bump by track/2 * sin(phi), the inner into droop.
            // Camber to the ground = camber to the body + phi (outer) / - phi (inner).
            sb.Append("\nCamber to the ground in roll (outer / inner wheel, deg; camber to the body from the sweep)\n");
            foreach (var cn in new[] { "FR", "RR" })
            {
                double track = cn[0] == 'F' ? par["track_front"] : par["track_rear"];
                var x = res[cn].Select(q => q.Travel).ToArray(); var y = res[cn].Select(q => q.Camber).ToArray();
                sb.Append("  " + (cn[0] == 'F' ? "front" : "rear ") + ":");
                foreach (double phi in new[] { 1.0, 2.0 })
                {
                    double z = track / 2 * Math.Sin(phi * Math.PI / 180);
                    double co = Interp(x, y, z) + phi, ci = Interp(x, y, -z) - phi;
                    sb.Append("  roll " + F(phi, "0") + " deg (travel +/-" + F(z, "0.0") + " mm): " + F(co, "0.00") + " / " + F(ci, "0.00"));
                }
                sb.Append("\n");
            }

            // joint package: every outer joint (with its housing) inside the rim must clear the barrel
            double rBarrelIn = par["rim_diameter"] / 2 - 11;     // build_parts.build_rim: barrel 7 mm below the bead seat, 4 mm wall
            double halfW = par["rim_width"] / 2;
            sb.Append("\nOuter joints against the rim (barrel inside radius " + F(rBarrelIn, "0") + " mm, rim " + F(-halfW, "0") + " to +" + F(halfW, "0") +
                      " mm along the spindle from the wheel centre; joint housing radius " + F(JOINT_R, "0") + " mm)\n");
            var pkgBad = new List<string>();
            foreach (var cn in new[] { "FR", "RR" })
            {
                var c = MakeCorner(par, cn);
                var axU = Unit(Sub(c.P["ax"], c.P["wc"]));
                foreach (var jn in new[] { "lwb_out", "uwb_out", "tie_out", "pushrod_out" })
                {
                    var d = Sub(c.P[jn], c.P["wc"]);
                    double ax = d[0] * axU[0] + d[1] * axU[1] + d[2] * axU[2];
                    double rad = Math.Sqrt(Math.Max(0, d[0] * d[0] + d[1] * d[1] + d[2] * d[2] - ax * ax));
                    bool inRim = ax >= -halfW && ax <= halfW;
                    double margin = rBarrelIn - (rad + JOINT_R);
                    bool ok = !inRim || margin >= 0;
                    string nm = jn == "tie_out" ? c.TieName + "_out" : jn;
                    sb.Append("  " + cn + " " + nm.PadRight(12) + " radius " + F(rad, "0.0").PadLeft(6) + " mm, along the spindle " + F(ax, "0.0").PadLeft(6) + " mm" +
                              (inRim ? ", inside the rim, margin to the barrel " + F(margin, "0.0") + " mm" + (ok ? "" : "  <- does not fit") : ", outside the rim") + "\n");
                    if (!ok) pkgBad.Add(cn + " " + nm + " (radius " + F(rad, "0") + " + " + F(JOINT_R, "0") + " > " + F(rBarrelIn, "0") + " mm)");
                }
            }
            rep.Warn(pkgBad.Count == 0, "outer ball joints fit inside the rim barrel" + (pkgBad.Count > 0 ? ": NOT " + string.Join("; ", pkgBad) +
                     " (hardpoints from suspension_geometry.m; moving them changes the kinematics, so they are reported, not changed)" : ""));

            // clashes: interference at full droop, static and full bump
            sb.Append("\nInterference (suspension parts, tyres and rims against everything)\n");
            var stat = new Dictionary<string, double>();
            var poses = new[] { 0.0, bump, -droop };
            var clashLines = new List<string>();
            foreach (double t in poses)
            {
                foreach (var cn in Corners) SetDistance(drv[cn], h0 + t);
                am.EditRebuild3();
                var pairs = Interferences(Corners.ToDictionary(cn => cn, cn => MakeCorner(par, cn)));
                sb.Append("  travel " + F(t, "+0;-0;0") + " mm: " + (pairs.Count == 0 ? "none" : string.Join("; ", pairs.Select(kv => kv.Key + " " + F(kv.Value, "0") + " mm3"))) + "\n");
                if (t == 0) stat = pairs;
                foreach (var kv in pairs)
                {
                    bool expected = IsMount(kv.Key);
                    double was = stat.TryGetValue(kv.Key, out double v0) ? v0 : 0;
                    if (!expected && (t == 0 || kv.Value > was + 1)) clashLines.Add(kv.Key + " at travel " + F(t, "+0;-0;0") + " mm: " + F(kv.Value, "0") + " mm3");
                }
            }
            rep.Warn(clashLines.Count == 0, "wheel travel " + F(-droop, "0") + " to +" + F(bump, "0") + " mm without clashes (not clashes: rim in tyre, hub in rim, the parts of one corner at their joints, a link touching the chassis within " + F(PIVOT_MOUNT_MM, "0") + " mm of its inboard pivot = the bracket)" +
                     (clashLines.Count > 0 ? ": " + string.Join("; ", clashLines.Distinct().Take(20)) : ""));

            // back to static, save
            foreach (var cn in Corners) SetDistance(drv[cn], h0);
            am.EditRebuild3();
            int e = 0, wn = 0;
            bool saved = am.Save3((int)swSaveAsOptions_e.swSaveAsOptions_Silent, ref e, ref wn);
            rep.Note(saved, saved ? "back at static and saved " + AssemblyPath : "NOT saved (error " + e + ")");
            string full = rep.Text("SuspensionCheck, " + AssemblyPath) + "\n" + sb;
            WriteReport(Path.Combine(Dir, "suspension_report.txt"), full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }

        static readonly HashSet<string> MountAtPivot = new HashSet<string>();

        static bool IsMount(string pair)
        {
            if (MountAtPivot.Contains(pair)) return true;
            var a = pair.Split(new[] { " / " }, StringSplitOptions.None);
            if (a.Length != 2) return false;
            Func<string, string> kind = n =>
            {
                n = n.ToLowerInvariant();
                foreach (var k in new[] { "hub", "rim", "tyre", "upright", "lwb", "uwb", "tie", "push", "chassis" }) if (n.Contains(k)) return k;
                return n;
            };
            Func<string, string> corner = n => n.Length >= 2 && Corners.Contains(n.Substring(0, 2)) ? n.Substring(0, 2) : "";
            string k1 = kind(a[0]), k2 = kind(a[1]);
            var set = new HashSet<string> { k1, k2 };
            bool sameCorner = corner(a[0]) != "" && corner(a[0]) == corner(a[1]);
            // parts of one corner that meet at a joint (the members stop short, the joints are what is left)
            if (sameCorner && (set.SetEquals(new[] { "hub", "upright" }) || set.SetEquals(new[] { "lwb", "upright" }) || set.SetEquals(new[] { "uwb", "upright" }) ||
                               set.SetEquals(new[] { "tie", "upright" }) || set.SetEquals(new[] { "push", "upright" }))) return true;
            if (set.SetEquals(new[] { "rim", "tyre" })) return true;
            if (set.SetEquals(new[] { "hub", "rim" })) return true;
            return false;
        }

        static Dictionary<string, double> Interferences(Dictionary<string, Corner> cs)
        {
            var res = new Dictionary<string, double>();
            var where = new Dictionary<string, List<double[]>>();
            var idm = asm.InterferenceDetectionManager;
            if (idm == null) return res;
            idm.TreatCoincidenceAsInterference = false;
            idm.IncludeMultibodyPartInterferences = false;
            var ints = idm.GetInterferences() as object[] ?? new object[0];
            foreach (Interference itf in ints)
            {
                var names = (itf.Components as object[] ?? new object[0]).OfType<Component2>().Select(c => c.Name2).OrderBy(x => x).ToList();
                bool ours = names.Any(n => Corners.Any(cn => n.StartsWith(cn + "_")) || n.StartsWith("tyre") || n.StartsWith("rim"));
                if (!ours) continue;
                string k = string.Join(" / ", names);
                res[k] = (res.TryGetValue(k, out double v) ? v : 0) + itf.Volume * 1e9;
                if (!where.ContainsKey(k)) where[k] = new List<double[]>();
                try { if (itf.GetInterferenceBody() is Body2 ib && ib.GetBodyBox() is double[] bx) where[k].Add(new[] { (bx[0] + bx[3]) * 500, (bx[1] + bx[4]) * 500, (bx[2] + bx[5]) * 500 }); }
                catch { }
            }
            idm.Done();
            // a link touching the chassis only next to its own inboard pivot: that is the bracket, not a clash
            foreach (var k in res.Keys.ToList())
            {
                var nm = k.Split(new[] { " / " }, StringSplitOptions.None);
                string link = nm.FirstOrDefault(n => Corners.Any(cn => n.StartsWith(cn + "_")));
                if (link == null || !nm.Any(n => n.StartsWith("chassis")) || !where.ContainsKey(k) || where[k].Count == 0) continue;
                var c = cs[link.Substring(0, 2)];
                var piv = new[] { "lwb_in_fwd", "lwb_in_aft", "uwb_in_fwd", "uwb_in_aft", "tie_in", "pushrod_in" }.Select(n => c.P[n]).ToList();
                if (where[k].All(w => piv.Min(pp => Dist(pp, w)) <= PIVOT_MOUNT_MM)) MountAtPivot.Add(k);
            }
            return res.Where(kv => kv.Value >= 1).ToDictionary(kv => kv.Key, kv => kv.Value);
        }

        public static void SetDistance(Feature mateFeat, double mm)
        {
            var dd = mateFeat.GetFirstDisplayDimension() as DisplayDimension;
            var dim = dd?.GetDimension2(0);
            if (dim == null) throw new StepStoppedException(mateFeat.Name + " has no dimension");
            dim.SetSystemValue3(mm / 1000, (int)swSetValueInConfiguration_e.swSetValue_InThisConfiguration, null);
        }

        static Pose Measure(Corner c, Component2 up, double t)
        {
            var p = c.P;
            Func<string, double[]> W = n => World(up, p[n]);
            var lb = W("lwb_out"); var ub = W("uwb_out"); var tie = W("tie_out"); var push = W("pushrod_out");
            var wc = W("wc"); var ax = W("ax"); var fw = W("fwd"); var cp = W("cp");
            var a = Sub(ax, wc); var f = Sub(fw, wc);
            // right-hand sign conventions (suspension_geometry.m); the left corner is mirrored first
            if (c.S < 0) { a[1] = -a[1]; f[1] = -f[1]; }
            double camber = -Math.Atan(a[2] / a[1]) * 180 / Math.PI;
            double toe = Math.Atan(f[1] / f[0]) * 180 / Math.PI;
            double leg = new[] {
                Math.Abs(Dist(lb, p["lwb_in_fwd"]) - Dist(p["lwb_out"], p["lwb_in_fwd"])),
                Math.Abs(Dist(lb, p["lwb_in_aft"]) - Dist(p["lwb_out"], p["lwb_in_aft"])),
                Math.Abs(Dist(ub, p["uwb_in_fwd"]) - Dist(p["uwb_out"], p["uwb_in_fwd"])),
                Math.Abs(Dist(ub, p["uwb_in_aft"]) - Dist(p["uwb_out"], p["uwb_in_aft"])),
                Math.Abs(Dist(tie, p["tie_in"]) - Dist(p["tie_out"], p["tie_in"])) }.Max();
            return new Pose
            {
                Travel = t, Camber = camber, Toe = toe, Dy = c.S * (cp[1] - p["cp"][1]),
                Push = Dist(push, p["pushrod_in"]) - Dist(p["pushrod_out"], p["pushrod_in"]),
                Rc = RollCentre(c, lb, ub, cp, wc[0]), WcZ = wc[2], LegErr = leg, Lb = lb, Ub = ub, Wc = wc, Cp = cp
            };
        }

        /// Front-view instant centre (inboard axes projected to x = wheel centre, joined to the ball joints);
        /// roll centre = where IC -> contact patch crosses y = 0, height above the contact patch (suspension_geometry.m).
        static double RollCentre(Corner c, double[] lb, double[] ub, double[] cp, double xw)
        {
            var p = c.P;
            Func<double[], double[], double[]> atX = (a, b) => { var d = Sub(b, a); if (Math.Abs(d[0]) < 1e-9) return a; double t = (xw - a[0]) / d[0]; return Add(a, d, t); };
            var upA = atX(p["uwb_in_fwd"], p["uwb_in_aft"]); var loA = atX(p["lwb_in_fwd"], p["lwb_in_aft"]);
            double[] d1 = { ub[1] - upA[1], ub[2] - upA[2] }, d2 = { lb[1] - loA[1], lb[2] - loA[2] };
            double den = d1[0] * d2[1] - d1[1] * d2[0];
            if (Math.Abs(den) < 1e-9) return 0;
            double[] r = { loA[1] - upA[1], loA[2] - upA[2] };
            double s = (r[0] * d2[1] - r[1] * d2[0]) / den;
            double icy = upA[1] + s * d1[0], icz = upA[2] + s * d1[1];
            double u = (0 - icy) / (cp[1] - icy);
            return icz + u * (cp[2] - icz) - cp[2];
        }

        /// camber gain, bump steer, roll centre, motion ratio (F, R) from the "Results:" comment line in car_params.txt.
        static double[][] MatlabResults()
        {
            var line = ReadLines(P("params", "car_params.txt")).FirstOrDefault(l => l.Contains("Results:") && l.Contains("camber gain"));
            if (line == null) return null;
            var nums = System.Text.RegularExpressions.Regex.Matches(line, @"F (-?[0-9.]+) / R (-?[0-9.]+)").Cast<System.Text.RegularExpressions.Match>()
                .Select(mm => new[] { Val(mm.Groups[1].Value), Val(mm.Groups[2].Value) }).ToArray();
            return nums.Length >= 4 ? nums.Take(4).ToArray() : null;
        }

        static double Par(Dictionary<string, double> par, string k, double dflt) => par.TryGetValue(k, out double v) ? v : dflt;

        static double Slope(double[] x, double[] y)
        {
            double mx = x.Average(), my = y.Average();
            return x.Zip(y, (a, b) => (a - mx) * (b - my)).Sum() / x.Sum(a => (a - mx) * (a - mx));
        }

        static double Interp(double[] x, double[] y, double v)
        {
            for (int i = 0; i + 1 < x.Length; i++)
                if (v >= x[i] && v <= x[i + 1]) return y[i] + (y[i + 1] - y[i]) * (v - x[i]) / (x[i + 1] - x[i]);
            return double.NaN;
        }

        // ------------------------------------------------------------------ vectors (mm)
        static double[] Sub(double[] a, double[] b) => new[] { a[0] - b[0], a[1] - b[1], a[2] - b[2] };
        static double[] Add(double[] a, double[] d, double s) => new[] { a[0] + s * d[0], a[1] + s * d[1], a[2] + s * d[2] };
        static double[] Lerp(double[] a, double[] b, double t) => Add(a, Sub(b, a), t);
        static double Dist(double[] a, double[] b) => Dist3(a[0], a[1], a[2], b[0], b[1], b[2]);
        static double[] Unit(double[] a) { double L = Math.Sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]); return new[] { a[0] / L, a[1] / L, a[2] / L }; }
        /// The segment a-b cut back by ca mm at a and cb mm at b.
        static double[][] Cut(double[] a, double[] b, double ca, double cb)
        {
            var u = Unit(Sub(b, a));
            return new[] { Add(a, u, ca), Add(b, u, -cb) };
        }
        static double[] ClosestOnLine(double[] p, double[] a, double[] b)
        {
            var d = Sub(b, a);
            double t = ((p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1] + (p[2] - a[2]) * d[2]) / (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
            return Add(a, d, t);
        }
    }
}
