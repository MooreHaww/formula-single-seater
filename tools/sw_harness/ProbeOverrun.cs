// ProbeOverrun.cs - diagnostic: how far every tube body reaches past its two nodes along
// its own axis (mm). swh overruns [n]   lists the n largest (default 40).
using System;
using System.Linq;
using SolidWorks.Interop.sldworks;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class ProbeOverrun
    {
        public static int Run(string[] a)
        {
            int n = a.Length > 0 ? int.Parse(a[0]) : 40;
            var fr = ReadFrame();
            var m = Open(ChassisPath);
            var bodyOf = TrimTubes.MatchBodies(TrimTubes.Snap((PartDoc)m), fr, out string un);
            var rows = new System.Collections.Generic.List<Tuple<double, string>>();
            foreach (var kv in bodyOf)
            {
                var t = fr.Tubes[kv.Key];
                double L = Dist3(t[0], t[1], t[2], t[3], t[4], t[5]);
                double ux = (t[3] - t[0]) / L, uy = (t[4] - t[1]) / L, uz = (t[5] - t[2]) / L;
                kv.Value.GetExtremePoint(-ux, -uy, -uz, out double x0, out double y0, out double z0);
                kv.Value.GetExtremePoint(ux, uy, uz, out double x1, out double y1, out double z1);
                double s0 = -((x0 * 1000 - t[0]) * ux + (y0 * 1000 - t[1]) * uy + (z0 * 1000 - t[2]) * uz);
                double s1 = (x1 * 1000 - t[0]) * ux + (y1 * 1000 - t[1]) * uy + (z1 * 1000 - t[2]) * uz - L;
                string na = fr.TubeRows.First(r => r[0] == kv.Key)[1], nb = fr.TubeRows.First(r => r[0] == kv.Key)[2];
                rows.Add(Tuple.Create(s0, kv.Key + " past " + na + ": " + F(s0, "0") + " mm"));
                rows.Add(Tuple.Create(s1, kv.Key + " past " + nb + ": " + F(s1, "0") + " mm"));
            }
            Log("unmatched: " + (un == "" ? "none" : un));
            foreach (var r in rows.OrderByDescending(r => r.Item1).Take(n)) Log(r.Item2);
            return 0;
        }
    }
}
