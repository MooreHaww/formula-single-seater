// Probe.cs - read-only diagnostic: "TubeEnds <tube id> [<part path>]".
// For every body whose centroid is within 40 mm of the tube's centreline, the
// span it covers along the tube axis (mm from node A), from Body2.GetExtremePoint.
using System;
using System.Linq;
using SolidWorks.Interop.sldworks;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class Probe
    {
        public static int TubeEnds(string[] args)
        {
            var fr = ReadFrame();
            string id = args[0];
            var m = Open(args.Length > 1 ? System.IO.Path.GetFullPath(System.IO.Path.Combine(Repo, args[1])) : ChassisPath);
            var t = fr.Tubes[id];
            double L = Dist3(t[0], t[1], t[2], t[3], t[4], t[5]);
            double ux = (t[3] - t[0]) / L, uy = (t[4] - t[1]) / L, uz = (t[5] - t[2]) / L;
            Log("tube " + id + ": A (" + F(t[0], "0") + "," + F(t[1], "0") + "," + F(t[2], "0") + ") -> B, length " + F(L, "0") + " mm");
            foreach (var b in Bodies((PartDoc)m))
            {
                var c = CentroidVol(b);
                if (DistToSegment(c[0], c[1], c[2], t) > 40) continue;
                double s0 = Along(b, -ux, -uy, -uz, t, ux, uy, uz), s1 = Along(b, ux, uy, uz, t, ux, uy, uz);
                Log("  " + b.Name + ": " + F(c[3], "0") + " mm3, spans " + F(s0) + " .. " + F(s1) + " mm from A (tube 0 .. " + F(L, "0") + ")");
            }
            return 0;
        }

        static double Along(Body2 b, double dx, double dy, double dz, double[] t, double ux, double uy, double uz)
        {
            double x, y, z;
            b.GetExtremePoint(dx, dy, dz, out x, out y, out z);
            return (x * 1000 - t[0]) * ux + (y * 1000 - t[1]) * uy + (z * 1000 - t[2]) * uz;
        }
    }
}
namespace SwHarness
{
    static class Probe2
    {
        public static int Tree(string[] args)
        {
            var m = Ctx.Open(args.Length > 0 ? System.IO.Path.GetFullPath(System.IO.Path.Combine(Ctx.Repo, args[0])) : Ctx.ChassisPath);
            int k = 0;
            foreach (var f in Ctx.TopFeatures(m))
            {
                k++;
                Ctx.Log(k.ToString("000") + "  " + f.Name + "  [" + f.GetTypeName2() + "]");
                foreach (var s in Ctx.SubFeatures(f)) Ctx.Log("       - " + s.Name + "  [" + s.GetTypeName2() + "]");
            }
            return 0;
        }
    }
}
namespace SwHarness
{
    static class Probe3
    {
        /// "TrimDefs [part]": every WeldCornerFeat with the tubes it trims and its boundaries (matched by centroid).
        public static int TrimDefs(string[] args)
        {
            var fr = Ctx.ReadFrame();
            var m = Ctx.Open(args.Length > 0 ? System.IO.Path.GetFullPath(System.IO.Path.Combine(Ctx.Repo, args[0])) : Ctx.ChassisPath);
            foreach (var f in System.Linq.Enumerable.ToList(Ctx.TopFeatures(m)))
            {
                if (f.GetTypeName2() != "WeldCornerFeat") continue;
                var d = (SolidWorks.Interop.sldworks.WeldmentTrimExtendFeatureData)f.GetDefinition();
                d.AccessSelections(m, null);
                int nt = d.GetBodiesToBeTrimmedCount(), nb = d.GetTrimmingBoundaryCount();
                var tb = d.BodiesToBeTrimmed as object[];
                int bt = 0;
                var bnd = d.GetTrimmingBoundary(out bt) as object[];
                Ctx.Log(f.Name + ": trims " + nt + " [" + Names(tb, fr) + "] against " + nb + " [" + Names(bnd, fr) + "]");
                d.ReleaseSelectionAccess();
            }
            return 0;
        }

        static string Names(object[] arr, Ctx.FrameData fr)
        {
            if (arr == null) return "";
            var s = new System.Collections.Generic.List<string>();
            foreach (var o in arr)
            {
                var b = o as SolidWorks.Interop.sldworks.Body2;
                if (b == null) { s.Add("(" + (o == null ? "null" : o.GetType().Name) + ")"); continue; }
                var c = Ctx.CentroidVol(b);
                string best = ""; double bd = 1e30;
                foreach (var id in fr.TubeOrder) { double x = Ctx.DistToSegment(c[0], c[1], c[2], fr.Tubes[id]); if (x < bd) { bd = x; best = id; } }
                s.Add(best);
            }
            return string.Join(" ", s);
        }
    }
}
namespace SwHarness
{
    static class Probe4
    {
        /// "FindFeat <name>...": where a feature is (FeatureByName, owner, parents, error, suppression).
        public static int FindFeat(string[] names)
        {
            var m = Ctx.Open(Ctx.ChassisPath);
            var part = (SolidWorks.Interop.sldworks.PartDoc)m;
            foreach (var nm in names)
            {
                var f = part.FeatureByName(nm) as SolidWorks.Interop.sldworks.Feature;
                if (f == null) { Ctx.Log(nm + ": FeatureByName -> null"); continue; }
                bool w; int e = f.GetErrorCode2(out w);
                var owner = f.GetOwnerFeature() as SolidWorks.Interop.sldworks.Feature;
                var parents = f.GetParents() as object[];
                string ps = parents == null ? "" : string.Join(", ", System.Linq.Enumerable.Select(parents, o => ((SolidWorks.Interop.sldworks.Feature)o).Name));
                var sup = f.IsSuppressed2((int)SolidWorks.Interop.swconst.swInConfigurationOpts_e.swThisConfiguration, null) as bool[];
                Ctx.Log(nm + ": type " + f.GetTypeName2() + ", owner " + (owner == null ? "-" : owner.Name + " [" + owner.GetTypeName2() + "]") +
                        ", parents [" + ps + "], error " + e + (w ? " (warning)" : "") + ", suppressed " + (sup == null ? "?" : sup[0].ToString()));
            }
            return 0;
        }
    }
}
