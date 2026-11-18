// FrameAnalysis.cs - torsion of the frame as ONE fused solid in SOLIDWORKS Simulation, to cross-check
// matlab/stress/frame_fe.m. Analysis only: the production chassis (cad/chassis/chassis.SLDPRT) is not opened.
//   swh FrameAnalysis [size_mm ...] [--overlap 1.0] [--build-only] [--probe]
//        part   cad\analysis\frame_analysis.SLDPRT (an old one is moved to cad\analysis\old\)
//        report sim\stress\frame_analysis_report.txt
//
// Why a separate part: the weldment's coped tube ends touch their neighbours only along lines, so neither Combine
// nor bonded contact joins them reliably (FrameSolid.cs, 2026-11-17). Here the frame is rebuilt from the same data
// (cad/frame/frame_nodes.csv, frame_tubes.csv, frame_trims.csv) as temporary bodies:
//   1. Every tube is a hollow cylinder (OD and wall from frame_tubes.csv) on its centreline.
//   2. At a node where frame_trims.csv trims the tube, it runs to the node centre and is coped against each of its
//      boundary tubes there by a cylinder of the boundary tube's OD/2 - overlap (default 1.0 mm, under the 1.6 mm
//      wall): the end sits in the neighbour's wall by the overlap, so the two solids share volume, while the
//      neighbour's bore stays closed by the rest of its wall. This is the weldment's cope with the tube pushed 1 mm
//      into the wall.
//   3. At a node where the tube is not trimmed (it runs through, or is one of two collinear halves) it is extended
//      past the node centre by OD/2, so it covers the copes of the tubes trimmed against it (also at corners).
//   4. All tubes are united (Body2.Operations2 add, each tube added when a tube sharing a node is already in).
//   5. Load faces: a cube of side 2h (h = 20 mm, or less if loaded nodes are closer) is imprinted on the body around
//      every loaded node, splitting the tube faces there; the faces inside the cube carry that node's loads.
// Study (one per case in sim/stress/frame_torsion_loads.csv, written by frame_fe):
//   "nodes": the couples at the 16 wishbone nodes (frame_fe torsion_nodes, the like-for-like case);
//   "links": the 24 link forces of the 1000 N wheel-force torsion case at the real pickup points (frame_fe's
//            headline 1503 Nm/deg).
//   Each force is a remote load (direct transfer, distributed coupling) at its point on the faces around its node:
//   the force reaches the frame as a force at the point, as in frame_fe, spread over the joint as a bracket would.
//   Static, solid mesh, AISI 4130 normalised (E 205 GPa, as frame_fe), free-free with inertia relief.
//   Twist as in frame_fe: per corner pair, atan((uz left - uz right)/(y right - y left)) at the four wishbone nodes,
//   uz = mean over the mesh nodes on the faces inside the node's cube; stiffness = frame_fe's torque / twist.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using SolidWorks.Interop.cosworks;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class FrameAnalysis
    {
        const string MAT_LIB_REL = @"lang\english\sldmaterials\solidworks materials.sldmat";
        const string MAT = "AISI 4130 Steel, normalized at 870C";
        static readonly string NL = ((char)10).ToString();
        static Report rep;
        static StringBuilder sb;
        static DateTime tStart;
        static string tag = "";                    // --tag x: cad/analysis/frame_analysis_x.SLDPRT and its own report (variants)
        static string PartPath => P("cad", "analysis", "frame_analysis" + tag + ".SLDPRT");
        static void Stage(string s) => Log("   [" + F((DateTime.Now - tStart).TotalSeconds, "0") + " s] " + s);

        class Load { public string Case, Kind, Node; public double[] X, Fv; public double T, Twist, K; }

        public static int Run(string[] args)
        {
            if (args.Contains("--probe")) return Probe();
            rep = new Report(); sb = new StringBuilder(); tStart = DateTime.Now;
            tag = "";
            for (int i = 0; i + 1 < args.Length; i++) if (args[i] == "--tag") tag = "_" + args[i + 1];
            string reportFile = P("sim", "stress", "frame_analysis" + tag + "_report.txt");
            double overlap = 1.0;
            var sizes = new List<double>();
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--overlap" && i + 1 < args.Length) { overlap = double.Parse(args[++i], CultureInfo.InvariantCulture); continue; }
                if (args[i] == "--tag") { i++; continue; }
                if (!args[i].StartsWith("--") && double.TryParse(args[i], NumberStyles.Float, CultureInfo.InvariantCulture, out double s)) sizes.Add(s);
            }
            if (sizes.Count == 0) sizes.Add(5);
            var fr = ReadFrame();
            string loadFile = P("sim", "stress", "frame_torsion_loads.csv");
            if (!File.Exists(loadFile)) throw new StepStoppedException("Missing " + loadFile + " (run frame_fe in MATLAB)");
            var loads = Csv(loadFile).Where(r => r.Length >= 12).Select(r => new Load
            {
                Case = r[0], Kind = r[1], Node = r[2], X = new[] { Val(r[3]), Val(r[4]), Val(r[5]) },
                Fv = new[] { Val(r[6]), Val(r[7]), Val(r[8]) }, T = Val(r[9]), Twist = Val(r[10]), K = Val(r[11])
            }).ToList();
            var loadNodes = loads.Select(l => l.Node).Distinct().ToList();
            var missing = loadNodes.Where(n => !fr.Nodes.ContainsKey(n)).ToList();
            if (missing.Count > 0) throw new StepStoppedException("frame_torsion_loads.csv names nodes not in frame_nodes.csv: " + string.Join(" ", missing) + " (rerun frame_fe after frame_layout)");

            // ---------------------------------------------------------------- 1-5: the fused frame
            bool readOnly = args.Contains("--results");          // read the solved studies of the saved part again
            double h = CubeHalf(fr, loadNodes);
            ModelDoc2 m;
            if (readOnly)
            {
                CloseIfOpen(PartPath);
                m = Open(PartPath);
                rep.Info("--results: " + PartPath + " opened as saved, its studies read without meshing or solving");
            }
            else m = BuildPart(fr, loadNodes, overlap, h);
            if (m == null || args.Contains("--build-only")) return Finish(reportFile);

            // ---------------------------------------------------------------- studies
            var cw = (App.GetAddInObject("SldWorks.Simulation") as CwAddincallback)?.CosmosWorks;
            if (cw == null) { rep.Note(false, "Simulation add-in: no CosmosWorks object"); return Finish(reportFile); }
            var sm = (cw.ActiveDoc as CWModelDoc)?.StudyManager as CWStudyManager;
            if (sm == null) { rep.Note(false, "no Simulation study manager for " + PartPath); return Finish(reportFile); }
            var part = (PartDoc)m;
            var body = (part.GetBodies2((int)swBodyType_e.swSolidBody, true) as object[]).OfType<Body2>().First();
            var faces = (body.GetFaces() as object[]).OfType<Face2>().ToList();
            var facesAt = new Dictionary<string, List<Face2>>();
            foreach (var n in loadNodes)
            {
                var q = fr.Nodes[n];
                facesAt[n] = faces.Where(f =>
                {
                    var b = f.GetBox() as double[];
                    return b != null && Enumerable.Range(0, 3).All(k => b[k] * 1000 >= q[k] - h - 0.05 && b[k + 3] * 1000 <= q[k] + h + 0.05);
                }).ToList();
            }
            var noFace = facesAt.Where(kv => kv.Value.Count == 0).Select(kv => kv.Key).ToList();
            rep.Note(noFace.Count == 0, "load faces: " + loadNodes.Count + " loaded nodes, " + facesAt.Sum(kv => kv.Value.Count) + " faces inside their " + F(2 * h, "0") + " mm cubes (" +
                     facesAt.Values.Min(v => v.Count) + " to " + facesAt.Values.Max(v => v.Count) + " per node)" + (noFace.Count > 0 ? "; NO faces at " + string.Join(" ", noFace) : ""));
            if (noFace.Count > 0) return Finish(reportFile);

            string exe = App.GetExecutablePath();
            string lib = new[] { Path.Combine(exe, MAT_LIB_REL), Path.Combine(Path.GetDirectoryName(exe) ?? "", MAT_LIB_REL) }.FirstOrDefault(File.Exists) ?? Path.Combine(exe, MAT_LIB_REL);
            string resDir = P("sim", "stress", "results");
            Directory.CreateDirectory(resDir);
            var results = new List<string>();
            foreach (var cs in new[] { "nodes", "links" })
            {
                var cl = loads.Where(l => l.Case == cs).ToList();
                if (cl.Count == 0) { rep.Note(false, "case '" + cs + "' not in " + loadFile); continue; }
                if (readOnly)
                {
                    CWStudy old = null;
                    for (int i = 0; i < sm.StudyCount; i++) if (sm.GetStudy(i) is CWStudy s0 && s0.Name == "Torsion " + cs) old = s0;
                    if (old == null) { rep.Note(false, "--results: no study 'Torsion " + cs + "' in " + PartPath); continue; }
                    string r0 = Solve(old, cs, sizes[0], cl, fr, facesAt, m, true);
                    if (r0 != null) results.Add(r0);
                    continue;
                }
                var st = NewStudy(sm, "Torsion " + cs, lib, resDir);
                if (st == null) continue;
                // loads
                var lr = st.LoadsAndRestraintsManager as CWLoadsAndRestraintsManager;
                int nOk = 0; var probs = new List<string>();
                double[] sumF = new double[3]; double mxF = 0, mxR = 0;
                double xMid = fr.Nodes.Values.Average(v => v[0]);
                foreach (var l in cl.Where(l => l.Kind == "load"))
                {
                    int err;
                    var rl = lr.AddRemoteLoad((int)swsRemoteLoadType_e.swsRemoteLoadType_DirectLoad, facesAt[l.Node].Cast<object>().ToArray(),
                                              (int)swsLinearUnit_e.swsLinearUnitMillimeters, l.X[0], l.X[1], l.X[2], out err) as CWRemoteLoad;
                    if (rl == null || err != 0) { probs.Add(l.Node + ": AddRemoteLoad error " + err); continue; }
                    rl.RemoteLoadBeginEdit();
                    rl.ConnectionType = (int)swsRemoteLoadConnectionType_e.swsRemoteLoadConnectionType_Distributed;
                    rl.ForceOrTranslationUnit = (int)swsForceUnit_e.swsForceUnitNOrNm;
                    rl.SetForceOrTranslationValues2(true, true, l.Fv[0], true, l.Fv[1], true, l.Fv[2]);
                    int ee = rl.RemoteLoadEndEdit();
                    if (ee != 0) { probs.Add(l.Node + ": RemoteLoadEndEdit " + ee); continue; }
                    bool inc, bx, by, bz; double fx, fy, fz;
                    rl.GetForceOrTranslationValues2(out inc, out bx, out fx, out by, out fy, out bz, out fz);
                    if (Math.Abs(fx - l.Fv[0]) + Math.Abs(fy - l.Fv[1]) + Math.Abs(fz - l.Fv[2]) > 1e-3) { probs.Add(l.Node + ": read back " + F(fx, "0.0") + " " + F(fy, "0.0") + " " + F(fz, "0.0")); continue; }
                    nOk++;
                    for (int k = 0; k < 3; k++) sumF[k] += l.Fv[k];
                    double mx = (l.Fv[2] * l.X[1] - l.Fv[1] * l.X[2]) / 1000;
                    if (l.X[0] < xMid) mxF += mx; else mxR += mx;
                }
                int nWant = cl.Count(l => l.Kind == "load");
                rep.Note(nOk == nWant && probs.Count == 0, "study 'Torsion " + cs + "': " + nOk + " of " + nWant + " remote loads (direct, distributed coupling) on the faces at their nodes; sum of forces " +
                         string.Join(" ", sumF.Select(v => F(v, "0.000"))) + " N, moment about x front " + F(mxF, "0.0") + " / rear " + F(mxR, "0.0") + " Nm" + (probs.Count > 0 ? "; " + string.Join("; ", probs) : ""));
                foreach (var size in sizes)
                {
                    string r = Solve(st, cs, size, cl, fr, facesAt, m, false);
                    if (r != null) results.Add(r);
                }
            }
            sb.Append("\nSummary (stiffness = frame_fe's torque / twist of the solid, same twist measure)\n" + string.Join("", results));
            bool saved = Save(m, out int se);
            rep.Note(saved, saved ? "saved " + PartPath + " with the studies" : "NOT saved (error " + se + ")");
            return Finish(reportFile);
        }

        // ================================================================ geometry
        /// Half side of the load cubes: 20 mm, or less so that the cubes of two loaded nodes cannot meet.
        static double CubeHalf(FrameData fr, List<string> loadNodes)
        {
            double dMin = double.MaxValue;
            for (int i = 0; i < loadNodes.Count; i++)
                for (int j = i + 1; j < loadNodes.Count; j++)
                {
                    var a = fr.Nodes[loadNodes[i]]; var b = fr.Nodes[loadNodes[j]];
                    dMin = Math.Min(dMin, Math.Max(Math.Abs(a[0] - b[0]), Math.Max(Math.Abs(a[1] - b[1]), Math.Abs(a[2] - b[2]))));
                }
            return Math.Min(20, 0.45 * dMin);
        }

        static ModelDoc2 BuildPart(FrameData fr, List<string> loadNodes, double overlap, double h)
        {
            var mod = (Modeler)App.GetModeler();
            var t0 = DateTime.Now;
            var od = new Dictionary<string, double>(); var wall = new Dictionary<string, double>();
            foreach (var r in fr.TubeRows.Where(r => fr.Tubes.ContainsKey(r[0])))
            {
                od[r[0]] = r.Length > 4 ? Val(r[4]) : 25.4; wall[r[0]] = r.Length > 5 ? Val(r[5]) : 1.6;
            }
            // trims: (tube, node) -> boundary tubes
            var bound = new Dictionary<string, List<string>>();
            foreach (var r in Csv(P("cad", "frame", "frame_trims.csv")).Where(r => r.Length >= 4))
                foreach (var t in r[3].Split(';'))
                    bound[t + "@" + r[1]] = r[2].Split(';').ToList();
            // material span of each tube: (start point, unit direction, length), mm
            var span = new Dictionary<string, Tuple<double[], double[], double>>();
            var row = fr.TubeRows.Where(r => fr.Tubes.ContainsKey(r[0])).ToDictionary(r => r[0]);
            int nExt = 0, nCope = 0;
            foreach (var id in fr.TubeOrder)
            {
                var c = fr.Tubes[id];
                double[] a = { c[0], c[1], c[2] }, b = { c[3], c[4], c[5] };
                double L = Dist3(a[0], a[1], a[2], b[0], b[1], b[2]);
                double[] d = { (b[0] - a[0]) / L, (b[1] - a[1]) / L, (b[2] - a[2]) / L };
                double ea = bound.ContainsKey(id + "@" + row[id][1]) ? 0 : od[id] / 2, eb = bound.ContainsKey(id + "@" + row[id][2]) ? 0 : od[id] / 2;
                nExt += (ea > 0 ? 1 : 0) + (eb > 0 ? 1 : 0); nCope += (ea > 0 ? 0 : 1) + (eb > 0 ? 0 : 1);
                span[id] = Tuple.Create(new[] { a[0] - d[0] * ea, a[1] - d[1] * ea, a[2] - d[2] * ea }, d, L + ea + eb);
            }
            Func<double[], double[], double, double, Body2> cyl = (p, d, r, L) =>
                mod.CreateBodyFromCyl(new double[] { p[0] / 1000, p[1] / 1000, p[2] / 1000, d[0], d[1], d[2], r / 1000, L / 1000 }) as Body2;
            // 1-3: tubes, coped
            var pieces = new Dictionary<string, List<Body2>>();
            var probs = new List<string>(); var scraps = new List<string>();
            int nNoCut = 0;
            foreach (var id in fr.TubeOrder)
            {
                var s = span[id];
                var outer = cyl(s.Item1, s.Item2, od[id] / 2, s.Item3);
                var inner = cyl(new[] { s.Item1[0] - s.Item2[0], s.Item1[1] - s.Item2[1], s.Item1[2] - s.Item2[2] }, s.Item2, od[id] / 2 - wall[id], s.Item3 + 2);
                int err;
                var cur = (outer.Operations2((int)swBodyOperationType_e.SWBODYCUT, inner, out err) as object[])?.OfType<Body2>().ToList();
                if (cur == null || cur.Count != 1) { probs.Add(id + ": hollow tube failed (error " + err + ")"); continue; }
                foreach (var nd in new[] { row[id][1], row[id][2] })
                {
                    if (!bound.TryGetValue(id + "@" + nd, out var bl)) continue;
                    foreach (var bt in bl)
                    {
                        if (!span.ContainsKey(bt)) { probs.Add(id + " at " + nd + ": boundary " + bt + " unknown"); continue; }
                        var bs = span[bt];
                        var next = new List<Body2>();
                        foreach (var piece in cur)
                        {
                            var cutter = cyl(bs.Item1, bs.Item2, od[bt] / 2 - overlap, bs.Item3);
                            // on a copy: a refused operation can leave its input body unusable (2026-11-18)
                            var res = ((piece.Copy() as Body2).Operations2((int)swBodyOperationType_e.SWBODYCUT, cutter, out err) as object[])?.OfType<Body2>().ToList();
                            if (err == 0 && (res == null || res.Count == 0)) { next.Add(piece); nNoCut++; }     // the cutter does not reach this piece
                            else if (err != 0 || res == null) { probs.Add(id + " cut by " + bt + ": error " + err); next.Add(piece); }
                            else next.AddRange(res);
                        }
                        cur = next;
                    }
                }
                // slivers: a cope can leave a scrap beyond the boundary tube; keep only pieces above 1 % of the tube
                double vMax = cur.Max(Vol);
                var drop = cur.Where(p => Vol(p) < 0.01 * vMax).ToList();
                if (drop.Count > 0) scraps.Add(id + ": " + drop.Count + " scrap piece(s) of " + string.Join("/", drop.Select(p => F(Vol(p), "0"))) + " mm3 left out");
                pieces[id] = cur.Except(drop).ToList();
            }
            Stage("tubes made and coped: " + pieces.Count + " (" + nCope + " coped ends, " + nExt + " ends run through)");
            double volParts = pieces.Values.SelectMany(v => v).Sum(Vol);
            // 4: union, breadth-first over shared nodes
            var nodesOf = fr.TubeOrder.ToDictionary(id => id, id => new[] { row[id][1], row[id][2] });
            var order = new List<string>(); var seen = new HashSet<string>(); var q = new Queue<string>();
            string first = fr.TubeOrder.First(pieces.ContainsKey);
            q.Enqueue(first); seen.Add(first);
            while (q.Count > 0)
            {
                var c = q.Dequeue(); order.Add(c);
                foreach (var nb in fr.TubeOrder.Where(t => pieces.ContainsKey(t) && !seen.Contains(t) && nodesOf[t].Intersect(nodesOf[c]).Any())) { seen.Add(nb); q.Enqueue(nb); }
            }
            var apart = fr.TubeOrder.Where(t => pieces.ContainsKey(t) && !seen.Contains(t)).ToList();
            var acc = new List<Body2> { pieces[order[0]][0] };
            var bad = new List<string>();
            foreach (var id in order) foreach (var pc in pieces[id])
            {
                if (pc == pieces[order[0]][0]) continue;
                int err;
                // the tool joins one of the bodies in acc (usually the main one); keep the result and the untouched rest
                var main = acc.OrderByDescending(Vol).First();
                var res = ((main.Copy() as Body2).Operations2((int)swBodyOperationType_e.SWBODYADD, pc, out err) as object[])?.OfType<Body2>().ToList();
                if (err != 0 || res == null || res.Count == 0) { bad.Add(id + " (error " + err + ")"); acc.Add(pc); continue; }
                acc.Remove(main); acc.AddRange(res);
                if (res.Count > 1) bad.Add(id + " (did not join: " + res.Count + " bodies)");
            }
            // a piece that missed the main body may join later pieces: try the leftovers again
            for (int pass = 0; pass < 3 && acc.Count > 1; pass++)
                foreach (var b in acc.OrderBy(Vol).Take(acc.Count - 1).ToList())
                {
                    var main = acc.OrderByDescending(Vol).First();
                    int err;
                    var res = ((main.Copy() as Body2).Operations2((int)swBodyOperationType_e.SWBODYADD, b, out err) as object[])?.OfType<Body2>().ToList();
                    if (err == 0 && res != null && res.Count == 1) { acc.Remove(main); acc.Remove(b); acc.Add(res[0]); }
                }
            Stage("united: " + acc.Count + " bod" + (acc.Count == 1 ? "y" : "ies"));
            var fused = acc.OrderByDescending(Vol).First();
            // 5: load faces, a cube around every loaded node imprinted on the body
            int nf0 = fused.GetFaceCount(); var imp = new List<string>();
            foreach (var n in loadNodes)
            {
                var c = fr.Nodes[n];
                var box = mod.CreateBodyFromBox3(new double[] { c[0] / 1000, c[1] / 1000, (c[2] - h) / 1000, 0, 0, 1, 2 * h / 1000, 2 * h / 1000, 2 * h / 1000 }) as Body2;
                object te, toe, tv, tov;
                bool ok = false;
                try { ok = mod.ImprintingFaces((fused.GetFaces() as object[]).OfType<Face2>().ToArray(), (box.GetFaces() as object[]).OfType<Face2>().ToArray(), 0, out te, out toe, out tv, out tov); }
                catch (Exception ex) { imp.Add(n + " (" + ex.Message + ")"); continue; }
                if (!ok) imp.Add(n);
            }
            Stage("imprinted " + (loadNodes.Count - imp.Count) + " node cubes, faces " + nf0 + " -> " + fused.GetFaceCount());
            // the part
            CloseIfOpen(PartPath);
            if (File.Exists(PartPath))
            {
                string old = P("cad", "analysis", "old");
                Directory.CreateDirectory(old);
                File.Move(PartPath, Path.Combine(old, "frame_analysis_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".SLDPRT"));
            }
            var m = NewPartAt(PartPath);
            var np = (PartDoc)m;
            var feat = np.CreateFeatureFromBody3(fused, false, 0) as Feature;
            var bodies = (np.GetBodies2((int)swBodyType_e.swSolidBody, true) as object[] ?? new object[0]).OfType<Body2>().ToList();
            double vol = bodies.Sum(Vol), volCsv = fr.TubeVol.Values.Sum();
            Save(m, out _);
            rep.Note(probs.Count == 0, "tubes from frame_tubes.csv: " + pieces.Count + " of " + fr.TubeOrder.Count + ", hollow, coped against their frame_trims.csv boundaries " + F(overlap, "0.0") + " mm into the wall (" + nCope + " ends), " +
                     nExt + " ends run " + F(12.7, "0.0") + " mm past the node" + (probs.Count > 0 ? "; " + string.Join("; ", probs) : ""));
            rep.Info("copes: " + nNoCut + " boundary cutters did not reach the piece (nothing to cut); scraps beyond a boundary tube left out (under 1 % of the tube): " + (scraps.Count == 0 ? "none" : string.Join("; ", scraps)));
            rep.Note(acc.Count == 1 && bad.Count == 0 && apart.Count == 0, "fused into one solid: " + acc.Count + " bod" + (acc.Count == 1 ? "y" : "ies") + " after the union" +
                     (bad.Count > 0 ? "; joined late or not at all: " + string.Join(", ", bad) : "") + (apart.Count > 0 ? "; not reached through shared nodes: " + string.Join(" ", apart) : "") +
                     " (" + F((DateTime.Now - t0).TotalSeconds, "0") + " s)");
            rep.Note(feat != null && bodies.Count == 1, "part " + PartPath + ": " + bodies.Count + " solid bod" + (bodies.Count == 1 ? "y" : "ies") + (feat == null ? ", CreateFeatureFromBody3 refused" : ""));
            rep.Note(imp.Count == 0, "load faces imprinted: a " + F(2 * h, "0") + " mm cube around each of " + loadNodes.Count + " loaded nodes, body faces " + nf0 + " -> " + fused.GetFaceCount() + (imp.Count > 0 ? "; failed at " + string.Join(" ", imp) : ""));
            // volume: the copes remove what the weldment trims; the run-through ends and the 1 mm overlaps add a little
            double dv = (vol - volCsv) / volCsv * 100;
            rep.Note(Math.Abs(dv) < 8, "volume " + F(vol / 1000, "0.0") + " cm3 = " + F(vol * 7.85e-6, "0.00") + " kg of steel, centreline tubes in frame_tubes.csv " + F(volCsv / 1000, "0.0") + " cm3 (" + F(dv, "+0.0;-0.0") + " %, limit 8 %); pieces before the union " + F(volParts / 1000, "0.0") + " cm3");
            sb.Append("Model: one fused solid from the frame CSVs, " + fr.TubeOrder.Count + " tubes, overlap " + F(overlap, "0.0") + " mm, load cubes " + F(2 * h, "0") + " mm\n");
            return bodies.Count >= 1 ? m : null;
        }

        // ================================================================ study
        static CWStudy NewStudy(CWStudyManager sm, string name, string lib, string resDir)
        {
            int err;
            var st = sm.CreateNewStudy3(name, (int)swsAnalysisStudyType_e.swsAnalysisStudyTypeStatic, (int)swsMeshType_e.swsMeshTypeSolid, out err) as CWStudy;
            if (st == null) { rep.Note(false, "CreateNewStudy3 '" + name + "' refused, error " + err); return null; }
            var solids = st.SolidManager as CWSolidManager;
            int nBod = 0, nMat = 0;
            for (int c = 0; c < (solids?.ComponentCount ?? 0); c++)
            {
                var comp = solids.GetComponentAt(c, out err) as CWSolidComponent;
                for (int i = 0; i < (comp?.SolidBodyCount ?? 0); i++)
                {
                    var sbd = comp.GetSolidBodyAt(i, out err) as CWSolidBody;
                    if (sbd == null) continue;
                    nBod++;
                    if (sbd.SetLibraryMaterial2(lib, MAT) || sbd.SetLibraryMaterial(lib, MAT) == 0) nMat++;
                }
            }
            var opt = st.StaticStudyOptions as CWStaticStudyOptions;
            if (opt != null) { opt.UseInertialRelief2 = true; opt.UseSoftSpring2 = false; opt.ResultFolder = resDir; }
            rep.Note(nBod == 1 && nMat == 1, "study '" + name + "': static, solid mesh, " + nBod + " solid body, material '" + MAT + "' on " + nMat + ", free-free with inertia relief (no soft springs)");
            return st;
        }

        static string Solve(CWStudy st, string cs, double size, List<Load> cl, FrameData fr, Dictionary<string, List<Face2>> facesAt, ModelDoc2 m, bool readOnly)
        {
            if (readOnly)
            {
                var ms = st.Mesh as CWMesh;
                return Read(st, cs, size, cl, fr, facesAt, ms?.ElementCount ?? 0, ms?.NodeCount ?? 0, double.NaN, double.NaN);
            }
            Stage(st.Name + ": meshing at " + F(size, "0.0") + " mm");
            var mesh = st.Mesh as CWMesh;
            if (mesh != null) mesh.Quality = (int)swsMeshQuality_e.swsMeshQualityHigh;
            var t0 = DateTime.Now;
            int me = st.CreateMesh((int)swsLinearUnit_e.swsLinearUnitMillimeters, size, size * 0.05);
            mesh = st.Mesh as CWMesh;
            int nEl = mesh?.ElementCount ?? 0, nNo = mesh?.NodeCount ?? 0;
            double tMesh = (DateTime.Now - t0).TotalSeconds;
            rep.Note(me == 0 && nEl > 0, st.Name + ", " + F(size, "0.0") + " mm: mesh " + (me == 0 ? nEl + " elements, " + nNo + " nodes" : "error " + me) + " (" + F(tMesh, "0") + " s)");
            if (me != 0 || nEl == 0) return null;
            Save(m, out _);              // so `FrameAnalysis --results` can read a solved study again without solving
            Stage(st.Name + ": solving, " + nNo + " nodes");
            t0 = DateTime.Now;
            int re = st.RunAnalysis();
            double tRun = (DateTime.Now - t0).TotalSeconds;
            rep.Note(re == 0, st.Name + ", " + F(size, "0.0") + " mm: run " + (re == 0 ? "ok" : "error " + re) + " (" + F(tRun, "0") + " s)");
            if (re != 0) return null;
            Save(m, out _);
            Stage(st.Name + ": solved, reading the results");
            return Read(st, cs, size, cl, fr, facesAt, nEl, nNo, tMesh, tRun);
        }

        static string Read(CWStudy st, string cs, double size, List<Load> cl, FrameData fr, Dictionary<string, List<Face2>> facesAt, int nEl, int nNo, double tMesh, double tRun)
        {
            // Results through the API for the faces at the wishbone nodes only: asking for all 1.9 M nodes (GetNodes,
            // displacements, min/max stress) kept SolidWorks busy for over 20 min after a 2 min solve (2026-11-18).
            var res = st.Results as CWResults;
            // a failed mesh (the 3 mm try, 2026-11-18) throws away the study's earlier mesh and results
            if (res == null) { rep.Note(false, st.Name + ": no results in the study (the last mesh failed or it was never solved)"); return null; }
            int err;
            var uzCache = new Dictionary<string, double[]>();          // node -> mean uz, n, spread
            string fmtNote = null;
            Func<string, double[]> uzAt = n =>
            {
                if (uzCache.TryGetValue(n, out var c)) return c;
                // GetTranslationalDisplacement's second argument is a reference plane, not entities (it gives every node);
                // GetDisplacementForEntities gives the nodes of the selected faces
                object raw = res.GetDisplacementForEntities((int)swsDisplacementComponent_e.swsDisplacementComponentUZ, 1, null,
                                                            facesAt[n].Cast<object>().ToArray(), (int)swsLinearUnit_e.swsLinearUnitMillimeters, out err);
                double[] td;
                try { td = ToD(raw); }
                catch (Exception ex)
                {
                    string what = raw == null ? "null" : raw.GetType().Name + (raw is Array ra && ra.Length > 0 ? " of " + ra.Length + ", first " + (ra.GetValue(0)?.GetType().Name ?? "null") : "");
                    throw new StepStoppedException("displacement result at " + n + " not readable (" + what + ", error " + err + "): " + ex.Message);
                }
                if (err != 0 || td.Length == 0) throw new StepStoppedException("no displacement result at " + n + " (error " + err + ", " + td.Length + " values)");
                // format: (node number, value) pairs, or the values alone; told apart by the node numbers being whole and positive
                bool pairs = td.Length % 2 == 0 && Enumerable.Range(0, td.Length / 2).All(i => td[2 * i] >= 1 && Math.Abs(td[2 * i] - Math.Round(td[2 * i])) < 1e-9);
                if (fmtNote == null) fmtNote = "GetDisplacementForEntities UZ at " + n + ": " + td.Length + " numbers, read as " + (pairs ? "(node, value) pairs" : "values") + "; first " +
                                               string.Join(" ", td.Take(6).Select(x => x.ToString("G6", CultureInfo.InvariantCulture)));
                var v = new List<double>();
                if (pairs) for (int i = 1; i < td.Length; i += 2) v.Add(td[i]);
                else v.AddRange(td);
                c = v.Count == 0 ? new[] { double.NaN, 0, 0 } : new[] { v.Average(), v.Count, v.Max() - v.Min() };
                uzCache[n] = c; return c;
            };
            Func<string, int, string> role = (c, i) => cl.First(l => l.Kind == c + i).Node;
            Func<string, string, double> tw = (L, R) =>
            {
                double s = 0;
                for (int i = 1; i <= 4; i++)
                {
                    string nl = role(L, i), nr = role(R, i);
                    s += Math.Atan((uzAt(nl)[0] - uzAt(nr)[0]) / (fr.Nodes[nr][1] - fr.Nodes[nl][1])) * 180 / Math.PI;
                }
                return s / 4;
            };
            double T = Math.Abs(cl[0].T), kM = cl[0].K;
            double twF = tw("FL", "FR"), twR = tw("RL", "RR"), k = T / Math.Abs(twF - twR);
            double d = (k - kM) / kM * 100;
            // peak von Mises from the solver's own output (Pa)
            double vmMax = double.NaN; int vmNode = 0;
            string outFile = Path.Combine(P("sim", "stress", "results"), Path.GetFileNameWithoutExtension(PartPath) + "-" + st.Name + ".OUT");
            if (File.Exists(outFile))
            {
                var ol = File.ReadAllLines(outFile);
                for (int i = 0; i < ol.Length - 2; i++)
                    if (ol[i].Contains("MAXIMUM NODAL VON MISES STRESS"))
                        for (int j = i + 1; j < Math.Min(ol.Length, i + 6); j++)
                        {
                            string t = ol[j].Trim();
                            if (t.StartsWith("NODE")) int.TryParse(t.Substring(4).Trim(), out vmNode);
                            if (t.StartsWith("MAX.")) { vmMax = double.Parse(t.Substring(4).Trim(), CultureInfo.InvariantCulture) / 1e6; break; }
                        }
            }
            // where the peak is: one node location, the nearest frame node, and whether it lies in a load cube
            string vmWhere = "";
            var msh = st.Mesh as CWMesh;
            if (vmNode > 0 && msh != null)
            {
                double px, py, pz;
                if (msh.GetNodeLocation(vmNode, out px, out py, out pz) == 0)
                {
                    px *= 1000; py *= 1000; pz *= 1000;
                    var near = fr.Nodes.OrderBy(kv => Dist3(kv.Value[0], kv.Value[1], kv.Value[2], px, py, pz)).First();
                    double dn = Dist3(near.Value[0], near.Value[1], near.Value[2], px, py, pz);
                    double hh = facesAt.Count > 0 ? CubeHalf(fr, facesAt.Keys.ToList()) : 0;
                    var inCube = facesAt.Keys.Where(n => Enumerable.Range(0, 3).All(k => Math.Abs(fr.Nodes[n][k] - new[] { px, py, pz }[k]) <= hh + 0.1)).ToList();
                    vmWhere = " at mesh node " + vmNode + " (" + F(px, "0") + ", " + F(py, "0") + ", " + F(pz, "0") + " mm), " + F(dn, "0") + " mm from frame node " + near.Key +
                              (inCube.Count > 0 ? ", INSIDE the load cube of " + string.Join(" ", inCube) + " (where a remote load enters: a local artefact)" : ", outside every load cube");
                }
            }
            sb.Append(NL + "Torsion '" + cs + "', mesh " + F(size, "0.0") + " mm (" + nEl + " elements, " + nNo + " nodes, mesh " + F(tMesh, "0") + " s, run " + F(tRun, "0") + " s)" + NL +                       "  torque (frame_fe's figure) " + F(T, "0.0") + " Nm, front twist " + F(twF, "0.00000") + " deg, rear twist " + F(twR, "0.00000") + " deg" + NL +                       "  -> " + F(k, "0") + " Nm/deg; frame_fe " + F(kM, "0") + " Nm/deg (twist " + F(cl[0].Twist, "0.00000") + " deg); solid " + F(d, "+0;-0") + " %" + NL +                       "  peak von Mises " + F(vmMax, "0.0") + " MPa (solver output)" + vmWhere + NL +                       "  uz at the wishbone nodes (mean over the mesh nodes on the faces in the node's cube; count; spread), mm:" + NL);
            foreach (var c in new[] { "FL", "FR", "RL", "RR" })
                for (int i = 1; i <= 4; i++)
                {
                    var u = uzAt(role(c, i));
                    sb.Append("    " + c + i + " " + role(c, i).PadRight(10) + F(u[0], "0.00000").PadLeft(10) + F(u[1], "0").PadLeft(7) + F(u[2], "0.00000").PadLeft(10) + NL);
                }
            if (fmtNote != null) rep.Info(fmtNote);
            rep.Note(k > 0 && !double.IsNaN(k), "torsion '" + cs + "' on the fused solid, " + F(size, "0.0") + " mm mesh: " + F(k, "0") + " Nm/deg; frame_fe " + F(kM, "0") + " Nm/deg; difference " + F(d, "+0;-0") + " %");
            return "  " + cs.PadRight(6) + F(size, "0.0").PadLeft(5) + " mm  " + nNo.ToString().PadLeft(8) + " nodes  solid " + F(k, "0").PadLeft(5) + "  frame_fe " + F(kM, "0").PadLeft(5) + "  " + F(d, "+0;-0").PadLeft(4) + " %\n";
        }

        // ================================================================ helpers
        static double Vol(Body2 b)
        {
            var mp = b.GetMassProperties(1.0) as double[];
            return mp != null && mp.Length > 3 ? mp[3] * 1e9 : 0;
        }

        static double[] ToD(object o)
        {
            // the Simulation API returns double[], float[], object[] of boxed numbers, or object[] of such arrays
            if (o == null) return new double[0];
            if (o is double[] d) return d;
            if (o is float[] f) return f.Select(x => (double)x).ToArray();
            if (o is int[] n) return n.Select(x => (double)x).ToArray();
            if (o is Array a)
            {
                var r = new List<double>();
                foreach (var x in a)
                {
                    if (x == null) continue;
                    if (x is Array) r.AddRange(ToD(x));
                    else r.Add(Convert.ToDouble(x, CultureInfo.InvariantCulture));
                }
                return r.ToArray();
            }
            return new[] { Convert.ToDouble(o, CultureInfo.InvariantCulture) };
        }

        static int Finish(string reportFile)
        {
            string full = rep.Text("FrameAnalysis, " + PartPath) + "\n" + sb;
            WriteReport(reportFile, full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }

        /// API probe (2026-11-18): CreateBodyFromCyl = base centre, axis, radius, length; CreateBodyFromBox3 = base
        /// centre, axis (the height direction), width, length, height; ImprintingFaces needs typed Face2[] arrays
        /// (object[] crashes SolidWorks' server); SplitFaceOnParam reports success but splits nothing on a temp body.
        static int Probe()
        {
            var mod = (Modeler)App.GetModeler();
            var c = mod.CreateBodyFromCyl(new double[] { 0, 0, 0, 0, 0, 1, 0.01, 0.1 }) as Body2;
            Log("cyl r10 h100 at 0 axis z: box " + string.Join(" ", (c.GetBodyBox() as double[]).Select(v => F(v * 1000, "0.0"))));
            var bx = mod.CreateBodyFromBox3(new double[] { 0, 0, 0, 0, 0, 1, 0.02, 0.04, 0.06 }) as Body2;
            Log("box w20 l40 h60 at 0 axis z: box " + string.Join(" ", (bx.GetBodyBox() as double[]).Select(v => F(v * 1000, "0.0"))));
            return 0;
        }
    }
}
