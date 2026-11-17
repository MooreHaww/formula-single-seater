// TrimExperiment.cs - "TrimExperiment <part> <row name>...": for each row, try the
// trim with all its tubes and with each tube alone, coped and planar; after every
// insert: rebuild, error code, whether the feature is in the tree, volume removed.
// Each trial feature is deleted again. Works on a copy, never on chassis.SLDPRT.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class TrimExperiment
    {
        public static int Run(string[] args)
        {
            string path = Path.GetFullPath(args[0]);
            if (string.Equals(path, ChassisPath, StringComparison.OrdinalIgnoreCase)) throw new StepStoppedException("use a copy, not chassis.SLDPRT");
            var fr = ReadFrame();
            var plan = Csv(P("cad", "frame", "frame_trims.csv")).ToDictionary(r => r[0]);
            var m = Open(path);
            var part = (PartDoc)m; var fm = m.FeatureManager;
            foreach (var row in args.Skip(1))
            {
                // a row name, or a custom trial "T=tube;tube|B=tube;tube"
                var r = row.StartsWith("T=") ? new[] { row, "", row.Split('|')[1].Substring(2), row.Split('|')[0].Substring(2) } : plan[row];
                var tIds = r[3].Split(';'); var bIds = r[2].Split(';');
                var trials = new List<string[]> { tIds };
                if (tIds.Length > 1) trials.AddRange(tIds.Select(t => new[] { t }));
                foreach (int mode in new[] { (int)swWeldmentTrimExtendOptionType_e.swWeldmentTrimExtendOption_CopedCut, 0 })
                foreach (var tr in trials)
                {
                    var bodyOf = Match(part, fr);
                    double v0 = Bodies(part).Sum(b => CentroidVol(b)[3]);
                    m.ClearSelection2(true);
                    var f = fm.InsertWeldmentTrimFeature2((int)swSolidworksWeldmentEndCondOptions_e.swEndConditionTrim, mode, 0.0,
                        tr.Select(id => bodyOf[id]).ToArray(), bIds.Select(id => bodyOf[id]).ToArray()) as Feature;
                    string res;
                    if (f == null) res = "refused " + CreateErrors(fm);
                    else
                    {
                        bool w0; int e0 = f.GetErrorCode2(out w0);
                        m.ForceRebuild3(false);
                        bool w; int e = f.GetErrorCode2(out w);
                        bool inTree = TopFeatures(m).Any(x => x.Name == f.Name);
                        double v1 = Bodies(part).Sum(b => CentroidVol(b)[3]);
                        res = "made " + f.Name + ", error " + e0 + "->" + e + (w ? "w" : "") + ", in tree " + inTree + ", removed " + F(v0 - v1, "0") + " mm3, bodies " + Bodies(part).Length;
                        m.ClearSelection2(true);
                        f.Select2(false, 0);
                        m.Extension.DeleteSelection2(0);
                        m.ForceRebuild3(false);
                    }
                    Log(row + " " + (mode == 0 ? "planar" : "coped ") + " [" + string.Join(" ", tr) + "] vs [" + r[2] + "]: " + res);
                }
            }
            return 0;
        }

        static Dictionary<string, Body2> Match(PartDoc p, FrameData fr)
        {
            var d = new Dictionary<string, Body2>();
            foreach (var b in Bodies(p))
            {
                var c = CentroidVol(b);
                var best = fr.TubeOrder.OrderBy(id => DistToSegment(c[0], c[1], c[2], fr.Tubes[id])).First();
                if (!d.ContainsKey(best)) d[best] = b;
            }
            return d;
        }
    }
}
