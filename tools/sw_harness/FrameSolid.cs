// FrameSolid.cs - torsion of the frame as SOLIDS in SOLIDWORKS Simulation, to cross-check matlab/stress/frame_fe.m.
//   swh FrameSolid [size_mm] [--fuse] [--combine] [--check-only]
//        cad\chassis\chassis_solid.SLDPRT, study "Torsion solid", report sim\stress\frame_solid_report.txt
//
// Why solids: the beam studies of ChassisStatics cannot be loaded through the API (no joint entities). On solids the
// loads go on the geometry itself.
//   1. Default: chassis.SLDPRT is copied on disk (it stays as it is), the copy's beam studies are deleted, the 114 tube
//      bodies stay apart and Simulation's global bonded contact is to join them where faces touch.
//      --fuse: the tube bodies are united in memory (Body2.Operations2 add, breadth-first over the touching pairs) and
//      put into a new part as one body. --combine: a Combine feature on the copy. --check-only: stop after the
//      connectivity check (closest distance between every two tubes at a shared node).
//   2. FINDING, 2026-11-17 (SOLIDWORKS 2026 SP2.1 Student): the study meshes (1.46 M nodes at 5 mm) and solves in about
//      a minute, but the result is NOT valid. The coped tube ends touch their neighbours (closest distance under
//      0.01 mm) only along lines and points, not across faces: Combine is refused, the in-memory union keeps 82 of
//      114 tubes apart (disjoint result or error 547), and bonded contact leaves one or two tubes unjoined (a different
//      pair on each run), which float on the soft springs. The joint check below finds them and marks the stiffness
//      NOT VALID. A valid solid model needs tube ends that overlap their neighbours slightly (or a fused frame built
//      from the centrelines), not the weldment as trimmed.
//   3. Static study, solid mesh (beam members converted to solids if Simulation still sees any), AISI 4130 normalised,
//      free-free with inertia relief and soft springs.
//   4. Loads: the case frame_fe calls "couples at the wishbone nodes": at the front +F/4 up at each of the four left
//      wishbone pickup nodes and -F/4 at the right ones, at the rear the opposite couple of the same torque. On solids
//      each node's force goes on ONE edge: the weld seam (intersection edge of two tubes) closest to the node point
//      within 40 mm, the line where a pickup bracket would be welded. (A tube face here runs the whole tube length,
//      so a face load would spread along the tube instead of acting at the node.) One edge per force keeps 'total
//      force' and 'force per entity' the same thing.
//   5. Twist per axle from the mesh nodes within 30 mm of each pickup node (their mean vertical displacement), as in
//      frame_fe; stiffness = front torque / (front twist - rear twist), compared with frame_fe's value for the same case
//      (read from sim\stress\frame_fe_report.txt).
// Mesh: solid tetrahedra, high quality (second order), element size from the argument (default 4 mm, about 2.5 x the
// 1.6 mm wall: one element through the wall; 5 mm was used for the runs above).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using SolidWorks.Interop.cosworks;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class FrameSolid
    {
        const string STUDY = "Torsion solid";
        const string MAT_LIB_REL = @"lang\english\sldmaterials\solidworks materials.sldmat";
        const string MAT = "AISI 4130 Steel, normalized at 870C";
        const double YIELD_MPA = 435;
        static Report rep;
        static StringBuilder sb;
        static string SolidPath => P("cad", "chassis", "chassis_solid.SLDPRT");

        public static int Run(string[] args)
        {
            rep = new Report(); sb = new StringBuilder(); tStart = DateTime.Now;
            string reportFile = P("sim", "stress", "frame_solid_report.txt");
            bool combine = args.Contains("--combine");     // Combine feature on the weldment copy: refused on 2026 SP2.1
            var num = args.Where(a => !a.StartsWith("--")).ToArray();
            double size = num.Length > 0 && double.TryParse(num[0], NumberStyles.Float, CultureInfo.InvariantCulture, out double s0) ? s0 : 4.0;
            var fr = ReadFrame();
            var par = ReadParams(P("params", "car_params.txt"));

            // 1. the solid frame
            CloseIfOpen(SolidPath);
            if (FindOpenDoc(ChassisPath) != null) CloseIfOpen(ChassisPath);
            ModelDoc2 m;
            if (!args.Contains("--fuse"))
            {
                // the weldment copied as it is: 114 bodies, Simulation's bonded contact between them
                File.Copy(ChassisPath, SolidPath, true);
                m = Open(SolidPath);
            }
            else m = Fused(fr);
            if (m == null) return Finish(reportFile);
            var cb = App.GetAddInObject("SldWorks.Simulation") as CwAddincallback;
            var cw = cb?.CosmosWorks;
            if (cw == null) { rep.Note(false, "Simulation add-in: no CosmosWorks object"); return Finish(reportFile); }
            var cwDoc = cw.ActiveDoc as CWModelDoc;
            var sm = cwDoc?.StudyManager as CWStudyManager;
            if (sm == null) { rep.Note(false, "no Simulation study manager for " + SolidPath); return Finish(reportFile); }
            int nOld = 0;
            for (int i = sm.StudyCount - 1; i >= 0; i--)
                if (sm.GetStudy(i) is CWStudy old) { sm.DeleteStudy(old.Name); nOld++; }
            if (nOld > 0) rep.Info(nOld + " beam studies deleted in " + SolidPath);

            // 2. one body
            var part = m as PartDoc;
            var bodies = (part.GetBodies2((int)swBodyType_e.swSolidBody, true) as object[] ?? new object[0]).OfType<Body2>().ToList();
            int n0 = bodies.Count;
            Stage("opened the copy, " + n0 + " solid bodies" + (combine ? "; joining them (Combine)" : "; Combine skipped, Simulation bonds the touching bodies"));
            var t0 = DateTime.Now;
            Feature comb = null;
            if (combine && n0 > 1)
            {
                m.ClearSelection2(true);
                comb = m.FeatureManager.InsertCombineFeature((int)swBodyOperationType_e.SWBODYADD, null, bodies.Cast<object>().ToArray()) as Feature;
                if (comb == null)
                    comb = m.FeatureManager.InsertCombineFeature((int)swBodyOperationType_e.SWBODYADD, bodies[0], bodies.Skip(1).Cast<object>().ToArray()) as Feature;
            }
            Stage("Combine " + (combine ? "done" : "skipped"));
            if (args.Contains("--check-only")) { Connectivity(m, part, fr); Stage("--check-only: stop before the study"); return Finish(reportFile); }
            var after = (part.GetBodies2((int)swBodyType_e.swSolidBody, true) as object[] ?? new object[0]).OfType<Body2>().ToList();
            if (!combine) rep.Info("tubes left as " + after.Count + " bodies: Simulation's global bonded contact joins the touching tubes");
            else rep.Note(comb != null && after.Count >= 1, "tubes joined: " + n0 + " bodies -> " + after.Count + " (Combine " + (comb != null ? comb.Name : "REFUSED") + ", " +
                     F((DateTime.Now - t0).TotalSeconds, "0") + " s)" + (after.Count > 1 ? "; bodies left apart: " + string.Join(", ", after.OrderBy(b => Vol(b)).Take(after.Count - 1).Select(b => b.Name + " " + F(Vol(b), "0") + " mm3")) +
                     " (bonded by the global contact if they touch)" : ""));
            double vol = after.Sum(Vol);
            sb.Append("Model: " + after.Count + " solid bod" + (after.Count == 1 ? "y" : "ies") + ", volume " + F(vol / 1000, "0.0") + " cm3 = " + F(vol * 7.85e-6, "0.00") + " kg of steel\n");

            // pickups -> nodes, as in ChassisStatics / frame_fe
            var corners = BuildSuspension.Corners.ToDictionary(cn => cn, cn => BuildSuspension.MakeCorner(par, cn));
            Func<double[], string> nearest = q => fr.Nodes.OrderBy(kv => Dist3(kv.Value[0], kv.Value[1], kv.Value[2], q[0], q[1], q[2])).First().Key;
            string[] wb = { "lwb_in_fwd", "lwb_in_aft", "uwb_in_fwd", "uwb_in_aft" };
            Func<string, List<string>> nodesOf = cn => wb.Select(l => nearest(corners[cn].P[l])).ToList();
            Func<string, double> yOf = cn => nodesOf(cn).Average(n => fr.Nodes[n][1]);
            double Ft = 1000, spanR = Math.Abs(yOf("RR") - yOf("RL"));
            var loads = new Dictionary<string, double>();          // node -> Fz, N
            foreach (var cn in new[] { "FL", "FR" }) foreach (var n in nodesOf(cn)) loads[n] = (cn == "FL" ? 1 : -1) * Ft / 4;
            double torque = loads.Sum(kv => kv.Value * fr.Nodes[kv.Key][1]) / 1000;        // Nm about x, front couple
            double Fr = Math.Abs(torque) * 1000 / spanR;
            foreach (var cn in new[] { "RL", "RR" }) foreach (var n in nodesOf(cn)) loads[n] = (cn == "RL" ? -1 : 1) * Fr / 4;

            Stage("study set-up");
            // 3. study
            int err;
            var st = sm.CreateNewStudy3(STUDY, (int)swsAnalysisStudyType_e.swsAnalysisStudyTypeStatic, (int)swsMeshType_e.swsMeshTypeSolid, out err) as CWStudy;
            if (st == null) { rep.Note(false, "CreateNewStudy3 (static, solid mesh) refused, error " + err); return Finish(reportFile); }
            var bm = st.BeamManager as CWBeamManager;
            int nBeams = bm?.BeamCount ?? 0, nConv = 0;
            for (int i = nBeams - 1; i >= 0; i--)
            {
                var bb = bm.GetBeamBodyAt(i, out err) as CWBeamBody;
                if (bb != null) { bb.ConvertToSolidBody(); nConv++; }
            }
            var solids = st.SolidManager as CWSolidManager;
            // GetExecutablePath gives the folder on some installs and the exe on others: try both
            string exe = App.GetExecutablePath();
            string lib = new[] { Path.Combine(exe, MAT_LIB_REL), Path.Combine(Path.GetDirectoryName(exe) ?? "", MAT_LIB_REL) }.FirstOrDefault(File.Exists)
                         ?? Path.Combine(exe, MAT_LIB_REL);
            int nBod = 0, nMat = 0;
            var matBefore = new HashSet<string>(); var matErr = new HashSet<string>();
            for (int c = 0; c < (solids?.ComponentCount ?? 0); c++)
            {
                var comp = solids.GetComponentAt(c, out err) as CWSolidComponent;
                for (int i = 0; i < (comp?.SolidBodyCount ?? 0); i++)
                {
                    var sbd = comp.GetSolidBodyAt(i, out err) as CWSolidBody;
                    if (sbd == null) continue;
                    nBod++;
                    try { matBefore.Add((sbd.GetSolidBodyMaterial() as CWMaterial)?.MaterialName ?? "(none)"); } catch (Exception ex) { matBefore.Add("(" + ex.Message + ")"); }
                    if (sbd.SetLibraryMaterial2(lib, MAT)) { nMat++; continue; }
                    int me1 = sbd.SetLibraryMaterial(lib, MAT);
                    if (me1 == 0) nMat++; else matErr.Add("SetLibraryMaterial error " + me1);
                }
            }
            rep.Note(nBod > 0 && nMat == nBod, "study '" + STUDY + "': static, solid mesh, " + nBod + " solid bodies (" + nBeams + " beam members seen, " + nConv + " converted to solids), material '" + MAT + "' on " + nMat +
                     " (library " + lib + (File.Exists(lib) ? "" : ", NOT FOUND") + "; material before: " + string.Join(", ", matBefore) + (matErr.Count > 0 ? "; " + string.Join(", ", matErr) : "") + ")");
            var opt = st.StaticStudyOptions as CWStaticStudyOptions;
            string resDir = P("sim", "stress", "results");
            Directory.CreateDirectory(resDir);
            if (opt != null) { opt.UseInertialRelief2 = true; opt.UseSoftSpring2 = true; opt.ResultFolder = resDir; }

            Stage("loads on the weld seams");
            // 4. loads on the weld seams
            var body = after.OrderByDescending(Vol).First();
            var edges = after.SelectMany(b => (b.GetEdges() as object[] ?? new object[0]).OfType<Edge>()).ToList();
            var lr = st.LoadsAndRestraintsManager as CWLoadsAndRestraintsManager;
            var front = TopFeatures(m).Where(f => f.GetTypeName2() == "RefPlane").FirstOrDefault();
            var probs = new List<string>();
            sb.Append("\nLoads (one weld-seam edge per pickup node, N vertical)\n");
            int nLoads = 0;
            foreach (var kv in loads)
            {
                var q = fr.Nodes[kv.Key];
                var e = SeamNear(edges, q, 40, out double dMin, out double dMax, out double len);
                if (e == null) { probs.Add("no edge within 40 mm of " + kv.Key); continue; }
                var fo = lr.AddForce2((int)swsForceType_e.swsForceTypeForceOrMoment, (int)swsSelectionType_e.swsSelectionFaceEdgeVertexPoint,
                                      new object[] { e }, front, out err) as CWForce;
                if (fo == null || err != 0) { probs.Add("force at " + kv.Key + ": error " + err); continue; }
                fo.ForceBeginEdit();
                fo.Unit = (int)swsForceUnit_e.swsForceUnitNOrNm;
                fo.SetForceComponentValues2(true, true, true, 0, 0, kv.Value);
                int fe = fo.ForceEndEdit();
                if (fe != 0) { probs.Add("force at " + kv.Key + ": ForceEndEdit " + fe); continue; }
                nLoads++;
                sb.Append("  " + kv.Key.PadRight(9) + F(kv.Value, "+0.0;-0.0").PadLeft(8) + " N on an edge " + F(len, "0") + " mm long, " + F(dMin, "0") + " to " + F(dMax, "0") + " mm from the node\n");
            }
            rep.Note(nLoads == loads.Count && probs.Count == 0, nLoads + " of " + loads.Count + " node forces placed (front couple " + F(Math.Abs(torque), "0.0") + " Nm, rear couple the same torque the other way)" +
                     (probs.Count > 0 ? ": " + string.Join("; ", probs) : ""));

            Stage("meshing at " + F(size, "0.0") + " mm");
            // 5. mesh, run
            var mesh = st.Mesh as CWMesh;
            if (mesh != null) { mesh.Quality = (int)swsMeshQuality_e.swsMeshQualityHigh; }
            t0 = DateTime.Now;
            int me = st.CreateMesh((int)swsLinearUnit_e.swsLinearUnitMillimeters, size, size * 0.05);
            mesh = st.Mesh as CWMesh;
            int nEl = mesh?.ElementCount ?? 0, nNo = mesh?.NodeCount ?? 0;
            rep.Note(me == 0 && nEl > 0, "mesh: solid, high quality, element size " + F(size, "0.0") + " mm: " + (me == 0 ? nEl + " elements, " + nNo + " nodes" : "error " + me) +
                     " (" + F((DateTime.Now - t0).TotalSeconds, "0") + " s)");
            if (me != 0 || nEl == 0) { Save(m, out _); return Finish(reportFile); }
            Stage("solving, " + nEl + " elements");
            t0 = DateTime.Now;
            int re = st.RunAnalysis();
            Stage("solve returned " + re);
            double tRun = (DateTime.Now - t0).TotalSeconds;
            string outFile = Path.Combine(resDir, Path.GetFileNameWithoutExtension(SolidPath) + "-" + STUDY + ".OUT");
            string solverErr = File.Exists(outFile) ? File.ReadAllLines(outFile).Where(l => l.Contains("ERROR")).Select(l => l.Trim()).FirstOrDefault() : null;
            rep.Note(re == 0, "run: " + (re == 0 ? "ok" : "error " + re + (solverErr != null ? " ('" + solverErr + "')" : "")) + " (" + F(tRun, "0") + " s)");
            if (re != 0) { Save(m, out _); return Finish(reportFile); }

            // 6. results
            var res = st.Results as CWResults;
            var nodes = ToD(mesh.GetNodes());                                     // node, x, y, z (m)
            var tdisp = ToD(res.GetTranslationalDisplacement(1, null, (int)swsLinearUnit_e.swsLinearUnitMillimeters, out err));
            var uzBy = new Dictionary<int, double>();
            for (int i = 0; i + 3 < tdisp.Length; i += 4) uzBy[(int)tdisp[i]] = tdisp[i + 3];
            var pts = new List<double[]>();                                        // x y z (mm), uz
            for (int i = 0; i + 3 < nodes.Length; i += 4)
                if (uzBy.TryGetValue((int)nodes[i], out double uz)) pts.Add(new[] { nodes[i + 1] * 1000, nodes[i + 2] * 1000, nodes[i + 3] * 1000, uz });
            Func<string, double> uzAt = n =>
            {
                var q = fr.Nodes[n];
                var near = pts.Where(p => Dist3(p[0], p[1], p[2], q[0], q[1], q[2]) < 30).ToList();
                return near.Count == 0 ? double.NaN : near.Average(p => p[3]);
            };
            Func<string, string, double> tw = (l, r) =>
            {
                var L = nodesOf(l); var R = nodesOf(r);
                double s = 0; for (int i = 0; i < 4; i++) s += Math.Atan((uzAt(L[i]) - uzAt(R[i])) / (fr.Nodes[R[i]][1] - fr.Nodes[L[i]][1])) * 180 / Math.PI;
                return s / 4;
            };
            // diagnostics: at each frame node, the mean and the spread (max - min) of uz over the mesh nodes within
            // 20 mm. Tubes bonded at a joint move together (spread about rotation x 20 mm, hundredths of a mm);
            // a tube that is not joined there shows as a spread of the order of the displacement itself.
            sb.Append("\nDisplacement at the frame nodes (mesh nodes within 20 mm): uz mean, uz spread, mm\n");
            var spreadBy = new List<Tuple<string, double, double>>();
            foreach (var kv in fr.Nodes.OrderBy(k2 => k2.Value[0]))
            {
                var q = kv.Value;
                var near = pts.Where(p => Dist3(p[0], p[1], p[2], q[0], q[1], q[2]) < 20).Select(p => p[3]).ToList();
                if (near.Count == 0) continue;
                spreadBy.Add(Tuple.Create(kv.Key, near.Average(), near.Max() - near.Min()));
            }
            foreach (var t in spreadBy) sb.Append("  " + t.Item1.PadRight(9) + F(t.Item2, "0.0000").PadLeft(10) + F(t.Item3, "0.0000").PadLeft(10) + "\n");
            var bad = spreadBy.Where(t => t.Item3 > 0.2 * Math.Max(1e-6, spreadBy.Max(u => Math.Abs(u.Item2)))).Select(t => t.Item1 + " " + F(t.Item3, "0.00")).ToList();
            bool valid = bad.Count == 0;
            rep.Warn(bad.Count == 0, "joints that move as one (uz spread within 20 mm of each node under 20 % of the largest |uz|)" + (bad.Count > 0 ? ": NOT at " + string.Join(", ", bad) : ""));
            double twF = tw("FL", "FR"), twR = tw("RL", "RR"), twist = twF - twR;
            double k = Math.Abs(torque / twist);
            double vmMax = double.NaN;
            var vm = ToD(res.GetMinMaxStress((int)swsStressComponent_e.swsStressComponentVON, 0, 1, null, (int)swsStrengthUnit_e.swsStrengthUnitNewtonPerSquareMillimeter, out err));
            if (vm.Length >= 4) vmMax = vm[3];
            sb.Append("\nTorsion, free-free with inertia relief, couples at the wishbone nodes (frame_fe: 'equal and opposite couples front and rear')\n" +
                      "  front couple " + F(Math.Abs(torque), "0.0") + " Nm, front twist " + F(twF, "0.00000") + " deg, rear twist " + F(twR, "0.00000") + " deg\n" +
                      "  -> torsional stiffness " + F(k, "0") + " Nm/deg" + (valid ? "" : " -- NOT VALID: some tubes are not joined at their nodes (see the uz spreads above), they float on the soft springs") + "; peak von Mises " + F(vmMax, "0.0") + " MPa (at a loaded seam: a line load, so a local peak)\n" +
                      "  mesh " + nEl + " elements, " + nNo + " nodes, " + F(size, "0.0") + " mm, run " + F(tRun, "0") + " s\n");
            double kM = MatlabK();
            if (!double.IsNaN(kM))
            {
                double d = (k - kM) / kM * 100;
                sb.Append("  MATLAB beam model (frame_fe, same case): " + F(kM, "0") + " Nm/deg; solids " + F(d, "+0;-0") + " %\n");
                rep.Note(valid && !double.IsNaN(k) && k > 0, "torsion on solids: " + F(k, "0") + " Nm/deg" + (valid ? "" : " NOT VALID (tubes not joined)") + " (twist " + F(twist, "0.0000") + " deg under " + F(Math.Abs(torque), "0") + " Nm); MATLAB beam model " + F(kM, "0") +
                         " Nm/deg, difference " + F(d, "+0;-0") + " %");
                rep.Warn(Math.Abs(d) <= 25, "solids and beams agree within 25 % (" + F(d, "+0;-0") + " %)");
            }
            else rep.Note(valid && !double.IsNaN(k) && k > 0, "torsion on solids: " + F(k, "0") + " Nm/deg (frame_fe report not found to compare)");
            bool saved = Save(m, out int se);
            rep.Note(saved, saved ? "saved " + SolidPath + " with the study" : "NOT saved (error " + se + ")");
            return Finish(reportFile);
        }

        /// The frame as ONE solid in a new part: the 114 tube bodies of chassis.SLDPRT copied and united in memory
        /// (Body2.Operations2 add), each tube added when a tube it touches is already in, so every union is between
        /// touching bodies; the result put into a new part (CreateFeatureFromBody3), saved as chassis_solid.SLDPRT.
        /// chassis.SLDPRT is opened read-only in effect and closed without saving. No weldment, no beams.
        static ModelDoc2 Fused(FrameData fr)
        {
            var t0 = DateTime.Now;
            var src = Open(ChassisPath);
            var part = (PartDoc)src;
            var touch = Connectivity(src, part, fr, out Dictionary<string, Body2> bodyOf);
            var ids = bodyOf.Keys.ToList();
            // breadth-first from the tube with most touching neighbours
            var order = new List<string>(); var seen = new HashSet<string>();
            var q = new Queue<string>();
            string start = ids.OrderByDescending(i => touch.ContainsKey(i) ? touch[i].Count : 0).First();
            q.Enqueue(start); seen.Add(start);
            while (q.Count > 0)
            {
                var c = q.Dequeue(); order.Add(c);
                if (touch.ContainsKey(c)) foreach (var nb in touch[c]) if (seen.Add(nb)) q.Enqueue(nb);
            }
            order.AddRange(ids.Where(i => !seen.Contains(i)));
            Body2 acc = bodyOf[order[0]].Copy() as Body2;
            var apart = new List<Body2>(); var failed = new List<string>();
            int nFused = 1;
            for (int k = 1; k < order.Count; k++)
            {
                var b = bodyOf[order[k]].Copy() as Body2;
                int err;
                var res = (acc.Copy() as Body2).Operations2((int)swBodyOperationType_e.SWBODYADD, b, out err) as object[];
                var rb = res?.OfType<Body2>().ToList() ?? new List<Body2>();
                if (err == 0 && rb.Count == 1) { acc = rb[0]; nFused++; }
                else { failed.Add(order[k] + " (error " + err + ", " + rb.Count + " bodies)"); apart.Add(bodyOf[order[k]].Copy() as Body2); }
                if (k % 20 == 0) Stage("fused " + nFused + " of " + (k + 1));
            }
            App.CloseDoc(src.GetTitle());          // nothing was changed in it
            if (File.Exists(SolidPath)) File.Delete(SolidPath);
            var m = NewPartAt(SolidPath);
            var np = (PartDoc)m;
            int nFeat = 0;
            foreach (var b in new[] { acc }.Concat(apart))
                if (np.CreateFeatureFromBody3(b, false, 0) != null) nFeat++;
            Save(m, out _);
            int nb2 = ((np.GetBodies2((int)swBodyType_e.swSolidBody, true) as object[]) ?? new object[0]).Length;
            rep.Note(failed.Count == 0 && nb2 == 1, "frame fused into one solid: " + nFused + " of " + order.Count + " tubes united in memory, in a new part as " + nb2 + " bod" + (nb2 == 1 ? "y" : "ies") +
                     " (" + F((DateTime.Now - t0).TotalSeconds, "0") + " s)" + (failed.Count > 0 ? "; not united (kept as separate bodies, bonded only where faces touch): " + string.Join(", ", failed) : ""));
            Stage("fused: " + nFused + " of " + order.Count + ", part has " + nb2 + " bodies");
            return m;
        }

        static void Connectivity(ModelDoc2 m, PartDoc part, FrameData fr) => Connectivity(m, part, fr, out _);

        /// Which tubes touch: closest distance between every two tube bodies that share a node (Simulation's bonded
        /// contact joins only touching faces), then the groups of tubes connected through touching pairs.
        static Dictionary<string, List<string>> Connectivity(ModelDoc2 m, PartDoc part, FrameData fr, out Dictionary<string, Body2> bodyOf)
        {
            Stage("connectivity: closest distance between tubes at shared nodes");
            bodyOf = TrimTubes.MatchBodies(TrimTubes.Snap(part), fr, out string unmatched);
            var touch = new Dictionary<string, List<string>>();
            var ids = fr.TubeOrder.Where(bodyOf.ContainsKey).ToList();
            var gaps = new List<Tuple<string, string, string, double>>();
            var parent = ids.ToDictionary(i => i, i => i);
            Func<string, string> find = null;
            find = i => parent[i] == i ? i : (parent[i] = find(parent[i]));
            int nPairs = 0, nFail = 0;
            for (int i = 0; i < ids.Count; i++)
                for (int j = i + 1; j < ids.Count; j++)
                {
                    var ri = fr.TubeRows.First(r => r[0] == ids[i]); var rj = fr.TubeRows.First(r => r[0] == ids[j]);
                    string shared = new[] { ri[1], ri[2] }.Intersect(new[] { rj[1], rj[2] }).FirstOrDefault();
                    if (shared == null) continue;
                    nPairs++;
                    double d;
                    try { object p1, p2; d = m.ClosestDistance(bodyOf[ids[i]], bodyOf[ids[j]], out p1, out p2) * 1000; }
                    catch { d = double.NaN; }
                    if (double.IsNaN(d) || d < 0) { nFail++; continue; }
                    gaps.Add(Tuple.Create(ids[i], ids[j], shared, d));
                    if (d < 0.01)
                    {
                        parent[find(ids[i])] = find(ids[j]);
                        if (!touch.ContainsKey(ids[i])) touch[ids[i]] = new List<string>();
                        if (!touch.ContainsKey(ids[j])) touch[ids[j]] = new List<string>();
                        touch[ids[i]].Add(ids[j]); touch[ids[j]].Add(ids[i]);
                    }
                }
            var groups = ids.GroupBy(find).OrderByDescending(g => g.Count()).ToList();
            var open = gaps.Where(g => g.Item4 >= 0.01).OrderBy(g => g.Item3).ToList();
            sb.Append("\nConnectivity (closest distance between tube bodies sharing a node; touching = under 0.01 mm)\n" +
                      "  " + nPairs + " pairs, " + gaps.Count(g => g.Item4 < 0.01) + " touching, " + open.Count + " apart, " + nFail + " not measurable" +
                      (unmatched != "" ? "; unmatched bodies: " + unmatched : "") + "\n");
            foreach (var g in open) sb.Append("  apart " + g.Item1 + " / " + g.Item2 + " at " + g.Item3 + ": " + F(g.Item4, "0.000") + " mm\n");
            sb.Append("  connected groups: " + groups.Count + (groups.Count > 1 ? " (" + string.Join("; ", groups.Skip(1).Select(g => string.Join(" ", g))) + " apart from the main " + groups[0].Count() + ")" : "") + "\n");
            rep.Note(groups.Count == 1, "connectivity: " + groups.Count + " group(s) of tubes joined by touching pairs" +
                     (groups.Count > 1 ? "; apart from the main " + groups[0].Count() + ": " + string.Join("; ", groups.Skip(1).Select(g => string.Join(" ", g))) : "") +
                     " (" + open.Count + " node pairs not touching, " + nFail + " not measurable)");
            Stage("connectivity done: " + groups.Count + " group(s)");
            return touch;
        }

        static DateTime tStart = DateTime.Now;
        static void Stage(string s) => Log("   [" + F((DateTime.Now - tStart).TotalSeconds, "0") + " s] " + s);

        /// The edge closest to q (mm) whose points all lie within rMax: a weld seam at the node.
        static Edge SeamNear(List<Edge> edges, double[] q, double rMax, out double dMin, out double dMax, out double len)
        {
            Edge best = null; dMin = dMax = len = double.NaN; double bestScore = double.MaxValue;
            foreach (var e in edges)
            {
                var cpd = e.GetCurveParams3() as CurveParamData;
                var c = e.GetCurve() as Curve;
                if (cpd == null || c == null) continue;
                double u0 = cpd.UMinValue, u1 = cpd.UMaxValue, lo = double.MaxValue, hi = 0;
                for (int i = 0; i <= 12; i++)
                {
                    var p = c.Evaluate2(u0 + (u1 - u0) * i / 12.0, 0) as double[];
                    if (p == null) continue;
                    double d = Dist3(p[0] * 1000, p[1] * 1000, p[2] * 1000, q[0], q[1], q[2]);
                    lo = Math.Min(lo, d); hi = Math.Max(hi, d);
                }
                if (hi > rMax) continue;
                double L = c.GetLength3(u0, u1) * 1000;
                double score = lo - 0.05 * L;                          // close to the node, and a real seam rather than a sliver
                if (score < bestScore) { bestScore = score; best = e; dMin = lo; dMax = hi; len = L; }
            }
            return best;
        }

        static double Vol(Body2 b)
        {
            var mp = b.GetMassProperties(1.0) as double[];
            return mp != null && mp.Length > 3 ? mp[3] * 1e9 : 0;
        }

        static double MatlabK()
        {
            string f = P("sim", "stress", "frame_fe_report.txt");
            if (!File.Exists(f)) return double.NaN;
            var lines = File.ReadAllLines(f);
            for (int i = 0; i < lines.Length - 1; i++)
                if (lines[i].Contains("equal and opposite couples front and rear"))
                {
                    var mm = Regex.Match(lines[i + 1], @"->\s*([0-9.]+)\s*Nm/deg");
                    if (mm.Success) return double.Parse(mm.Groups[1].Value, CultureInfo.InvariantCulture);
                }
            return double.NaN;
        }

        static double[] ToD(object o)
        {
            if (o is double[] d) return d;
            if (o is object[] a) return a.Select(x => x is double v ? v : Convert.ToDouble(x)).ToArray();
            if (o is float[] f) return f.Select(x => (double)x).ToArray();
            return new double[0];
        }

        static int Finish(string reportFile)
        {
            string full = rep.Text("FrameSolid, " + SolidPath) + "\n" + sb;
            WriteReport(reportFile, full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }
    }
}
