// ProbeNear.cs - diagnostic: which chassis bodies reach near a point. swh nearpoint x y z [radius]
// For every body: its extreme point in the direction from its centroid toward the target;
// lists bodies whose extreme point is within radius (default 25 mm) of the target, with the
// tube whose centreline is nearest to the body's centroid.
using System;
using System.Linq;
using SolidWorks.Interop.sldworks;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class ProbeNear
    {
        public static int Run(string[] a)
        {
            double tx = double.Parse(a[0], Inv), ty = double.Parse(a[1], Inv), tz = double.Parse(a[2], Inv);
            double rad = a.Length > 3 ? double.Parse(a[3], Inv) : 25;
            var fr = ReadFrame();
            var m = Open(ChassisPath);
            foreach (var b in Bodies((PartDoc)m))
            {
                var c = CentroidVol(b);
                double dx = tx - c[0], dy = ty - c[1], dz = tz - c[2], L = Math.Sqrt(dx * dx + dy * dy + dz * dz);
                if (L < 1e-6) continue;
                b.GetExtremePoint(dx / L, dy / L, dz / L, out double x, out double y, out double z);
                x *= 1000; y *= 1000; z *= 1000;
                double d = Math.Sqrt((x - tx) * (x - tx) + (y - ty) * (y - ty) + (z - tz) * (z - tz));
                if (d > rad) continue;
                string tube = fr.Tubes.OrderBy(t => DistToSegment(c[0], c[1], c[2], t.Value)).First().Key;
                Log(b.Name + " (tube " + tube + "): reaches (" + F(x, "0") + ", " + F(y, "0") + ", " + F(z, "0") + "), " + F(d, "0") + " mm from the target");
            }
            return 0;
        }
    }
}
