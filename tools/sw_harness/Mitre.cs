// Mitre.cs - cuts the slivers left at shallow tube joints.
// BuildTubes lengthens a tube by about 2r/tan(angle) past a node so that it reaches
// the neighbouring tube; the coped trim then removes only the part inside the
// boundary tube, and the rest sticks out of the joint (153 mm at the main-hoop bend,
// 38 mm through the nose at FB_U). Rule: every tube end that reaches more than
// MITRE_MIN_MM past its node (measured on the solid body) is cut by the mitre plane
// between it and the most nearly in-line other tube at that node: the plane through
// the node whose normal is a - b (a, b unit vectors from the node along the two
// tubes), so it bisects the angle between them. One Trim/Extend feature per tube end,
// named Mitre_<tube>_<node>; its plane is MitrePlane_<tube>_<node>, made from a
// 3D sketch line along the normal.
//   swh mitre             cuts every end above the limit (used by TrimTubes)
//   swh mitre <tube> <node>   one end only (experiment)
using System;
using System.Collections.Generic;
using System.Linq;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class Mitre
    {
        public const double MITRE_MIN_MM = 15;   // ends square to a neighbour reach r = 12.7 mm past the node: left alone

        public class End { public string Tube, Node, Other; public double Reach; }

        public static int Run(string[] a)
        {
            var fr = ReadFrame();
            var m = Open(ChassisPath);
            var rep = new Report();
            var ends = Overruns(m, fr);
            if (a.Length >= 2) ends = ends.Where(e => e.Tube == a[0] && e.Node == a[1]).ToList();
            else ends = ends.Where(e => e.Reach > MITRE_MIN_MM).ToList();
            int made = Cut(m, fr, ends, rep);
            var after = Overruns(m, fr).OrderByDescending(e => e.Reach).ToList();
            foreach (var e in after.Take(6)) Log("after: " + e.Tube + " past " + e.Node + " " + F(e.Reach, "0") + " mm");
            Log(rep.Text("mitre " + ChassisPath));
            return rep.AllPass ? 0 : 1;
        }

        /// Reach (mm) of every tube body past each of its two nodes, with the most nearly in-line other tube there.
        public static List<End> Overruns(ModelDoc2 m, FrameData fr)
        {
            var bodyOf = TrimTubes.MatchBodies(TrimTubes.Snap((PartDoc)m), fr, out _);
            var res = new List<End>();
            foreach (var kv in bodyOf)
            {
                var t = fr.Tubes[kv.Key];
                var row = fr.TubeRows.First(r => r[0] == kv.Key);
                for (int s = 0; s < 2; s++)
                {
                    string node = row[1 + s];
                    var n = fr.Nodes[node];
                    // u: unit vector from the node outward along the tube's extension (away from the tube)
                    double[] far = s == 0 ? new[] { t[3], t[4], t[5] } : new[] { t[0], t[1], t[2] };
                    var u = Unit(n[0] - far[0], n[1] - far[1], n[2] - far[2]);
                    kv.Value.GetExtremePoint(u[0], u[1], u[2], out double x, out double y, out double z);
                    double reach = (x * 1000 - n[0]) * u[0] + (y * 1000 - n[1]) * u[1] + (z * 1000 - n[2]) * u[2];
                    // most nearly in-line other tube at the node: away vector closest to u
                    string best = null; double bestDot = -2;
                    foreach (var r in fr.TubeRows)
                    {
                        if (r[0] == kv.Key || !fr.Tubes.ContainsKey(r[0]) || (r[1] != node && r[2] != node)) continue;
                        var o = fr.Nodes[r[1] == node ? r[2] : r[1]];
                        var b = Unit(o[0] - n[0], o[1] - n[1], o[2] - n[2]);
                        double d = b[0] * u[0] + b[1] * u[1] + b[2] * u[2];
                        if (d > bestDot) { bestDot = d; best = r[0]; }
                    }
                    res.Add(new End { Tube = kv.Key, Node = node, Other = best, Reach = reach });
                }
            }
            return res;
        }

        public static string FeatName(End e) => "Mitre_" + e.Tube + "_" + e.Node;

        /// One mitre trim per end; returns the number made. Ends whose feature already exists are skipped.
        public static int Cut(ModelDoc2 m, FrameData fr, List<End> ends, Report rep)
        {
            var fm = m.FeatureManager; var part = (PartDoc)m;
            int made = 0;
            foreach (var e in ends)
            {
                string nm = FeatName(e);
                if (TrimTubes.AllFeatures(m).Any(f => f.Name == nm)) { rep.Info(nm + ": already there"); continue; }
                if (e.Other == null) { rep.Note(false, nm + ": no other tube at " + e.Node); continue; }
                var n = fr.Nodes[e.Node];
                var a = Away(fr, e.Tube, e.Node); var b = Away(fr, e.Other, e.Node);
                var nrm = Unit(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
                // plane: perpendicular to a 3D sketch line from the node along the normal, through the node
                // plane through three 3D sketch points: the node and two points in the plane
                var u = Cross(nrm, a); if (Norm(u) < 1e-6) u = Cross(nrm, new[] { 0.0, 0.0, 1.0 }); if (Norm(u) < 1e-6) u = Cross(nrm, new[] { 0.0, 1.0, 0.0 });
                u = Unit(u[0], u[1], u[2]); var v = Cross(nrm, u);
                var sk = m.SketchManager;
                m.ClearSelection2(true);
                sk.AddToDB = true;
                sk.Insert3DSketch(true);
                var pts = new[] { new[] { 0.0, 0.0, 0.0 }, u, v }.Select(d =>
                    sk.CreatePoint((n[0] + 100 * d[0]) / 1000, (n[1] + 100 * d[1]) / 1000, (n[2] + 100 * d[2]) / 1000)).ToList();
                var skf = sk.ActiveSketch as Feature;
                sk.Insert3DSketch(true);
                sk.AddToDB = false;
                if (skf == null) skf = m.Extension.GetLastFeatureAdded() as Feature;
                Rename(skf, "MitrePts_" + e.Tube + "_" + e.Node);
                m.ClearSelection2(true);
                Feature pl = null;
                int c = (int)swRefPlaneReferenceConstraints_e.swRefPlaneReferenceConstraint_Coincident;
                var sm = (SelectionMgr)m.SelectionManager;
                Func<int, SelectData> mk = k => { var sd = (SelectData)sm.CreateSelectData(); sd.Mark = k; return sd; };
                if (pts.All(p => p != null) && pts[0].Select4(false, mk(0)) && pts[1].Select4(true, mk(1)) && pts[2].Select4(true, mk(2)))
                    pl = fm.InsertRefPlane(c, 0, c, 0, c, 0) as Feature;
                m.ClearSelection2(true);
                if (skf != null && skf.Select2(false, 0)) m.BlankSketch();
                m.ClearSelection2(true);
                if (pl == null) { rep.Note(false, nm + ": mitre plane refused"); continue; }
                Rename(pl, "MitrePlane_" + e.Tube + "_" + e.Node);
                m.ClearSelection2(true); if (pl.Select2(false, 0)) m.BlankRefGeom(); m.ClearSelection2(true);
                var bodyOf = TrimTubes.MatchBodies(TrimTubes.Snap(part), fr, out _);
                if (!bodyOf.TryGetValue(e.Tube, out Body2 body)) { rep.Note(false, nm + ": no body for " + e.Tube); continue; }
                double v0 = Vol(body);
                // Cut With Surface: the weldment Trim/Extend takes bodies or faces only (a plane makes it error 1),
                // so the plane cuts the one body (feature scope); the side kept is the one that leaves the tube body
                // larger and below the reach limit, tried with Flip false then true.
                string how = ""; bool ok = false; double r1 = double.NaN, v1 = double.NaN;
                foreach (bool flip in new[] { false, true })
                {
                    bodyOf = TrimTubes.MatchBodies(TrimTubes.Snap(part), fr, out _);
                    if (!bodyOf.TryGetValue(e.Tube, out body)) { how += " no body for " + e.Tube; break; }
                    m.ClearSelection2(true);
                    var sm2 = (SelectionMgr)m.SelectionManager;
                    var sd = (SelectData)sm2.CreateSelectData(); sd.Mark = 0;
                    if (!pl.Select2(false, 0)) { how += " plane not selectable"; break; }
                    int cerr;
                    var f = fm.InsertCutSurface(flip, 0, true, false, new Body2[] { body }, out cerr) as Feature;
                    m.ClearSelection2(true);
                    if (f == null) { how += " flip " + flip + ": refused (error " + cerr + ")"; continue; }
                    int err = TrimTubes.ErrorOf(f);
                    bodyOf = TrimTubes.MatchBodies(TrimTubes.Snap(part), fr, out _);
                    v1 = bodyOf.TryGetValue(e.Tube, out Body2 b1) ? Vol(b1) : double.NaN;
                    var after = Overruns(m, fr).FirstOrDefault(x => x.Tube == e.Tube && x.Node == e.Node);
                    r1 = after?.Reach ?? double.NaN;
                    ok = err == 0 && r1 <= MITRE_MIN_MM && v1 > 0.5 * v0;
                    how += " flip " + flip + ": reach " + F(r1, "0") + " mm, volume " + F(v1, "0") + " mm3" + (err != 0 ? ", in error " + err : "") + ";";
                    if (ok) { Rename(f, nm); break; }
                    m.ClearSelection2(true); f.Select2(false, 0); m.Extension.DeleteSelection2(0); m.ClearSelection2(true);
                }
                rep.Note(ok, nm + ": cut by the plane between " + e.Tube + " and " + e.Other + ", reach " + F(e.Reach, "0") + " -> " + F(r1, "0") +
                         " mm, volume " + F(v0, "0") + " -> " + F(v1, "0") + " mm3" + (ok ? "" : " (" + how.Trim() + ")"));
                if (ok) made++;
            }
            return made;
        }

        static double Vol(Body2 b) => b.GetMassProperties(1.0) is double[] mp ? mp[3] * 1e9 : double.NaN;

        static double[] Away(FrameData fr, string tube, string node)
        {
            var r = fr.TubeRows.First(x => x[0] == tube);
            var n = fr.Nodes[node]; var o = fr.Nodes[r[1] == node ? r[2] : r[1]];
            return Unit(o[0] - n[0], o[1] - n[1], o[2] - n[2]);
        }

        static double[] Cross(double[] p, double[] q) => new[] { p[1] * q[2] - p[2] * q[1], p[2] * q[0] - p[0] * q[2], p[0] * q[1] - p[1] * q[0] };
        static double Norm(double[] p) => Math.Sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
        static double[] Unit(double x, double y, double z) { double L = Math.Sqrt(x * x + y * y + z * z); return new[] { x / L, y / L, z / L }; }
    }
}
