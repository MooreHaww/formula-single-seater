// ImportFrameNodes.cs - port of cad/macros/ImportFrameNodes.bas.
// Opens cad/chassis/chassis.SLDPRT, draws one 3D sketch FRAME_<group> per tube
// group from cad/frame/*.csv (one line per tube), saves, writes
// cad/chassis/import_frame_nodes_report.txt. Stops, changing nothing, if a
// FRAME_* sketch exists already.
using System.Collections.Generic;
using System.Linq;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class ImportFrameNodes
    {
        public static readonly string[] Known = { "hoop", "hoop_brace", "sis", "bulkhead", "sidepod", "front", "rear" };

        public static int Run()
        {
            string reportFile = P("cad", "chassis", "import_frame_nodes_report.txt");
            var fr = ReadFrame();
            var m = Open(ChassisPath);
            if (m.GetType() != (int)swDocumentTypes_e.swDocPART) throw new StepStoppedException("chassis is not a part");

            var groups = new Dictionary<string, List<string[]>>();
            int missing = 0;
            foreach (var r in fr.TubeRows)
            {
                if (!fr.Nodes.ContainsKey(r[1]) || !fr.Nodes.ContainsKey(r[2])) { missing++; continue; }
                string g = r[3] == "" ? "other" : r[3];
                if (!groups.ContainsKey(g)) groups[g] = new List<string[]>();
                groups[g].Add(r);
            }
            var order = Known.Where(groups.ContainsKey).Concat(groups.Keys.Where(g => !Known.Contains(g))).ToList();
            foreach (var g in order)
                if (FindFeature(m, "FRAME_" + g) != null)
                    throw new StepStoppedException("FRAME_" + g + " exists already in " + ChassisPath + " (run new-chassis for a clean part)");

            var rep = new Report();
            var sk = m.SketchManager;
            sk.AddToDB = false;            // inference on, so lines sharing a node share the end point
            sk.DisplayWhenAdded = false;
            int total = 0;
            foreach (var g in order)
            {
                string wanted = "FRAME_" + g;
                m.ClearSelection2(true);
                sk.Insert3DSketch(true);
                int n = 0;
                foreach (var r in groups[g])
                {
                    var a = fr.Nodes[r[1]]; var b = fr.Nodes[r[2]];
                    var seg = sk.CreateLine(a[0] / 1000, a[1] / 1000, a[2] / 1000, b[0] / 1000, b[1] / 1000, b[2] / 1000);
                    if (seg != null) n++;
                }
                var feat = sk.ActiveSketch as Feature;
                sk.Insert3DSketch(true);
                if (feat == null) feat = m.Extension.GetLastFeatureAdded() as Feature;
                bool named = Rename(feat, wanted);
                // count the segments that are really in the sketch
                int inSketch = 0;
                if (feat?.GetSpecificFeature2() is Sketch s && s.GetSketchSegments() is object[] segs) inSketch = segs.Length;
                rep.Note(named && inSketch == groups[g].Count,
                    wanted + ": " + inSketch + " lines in the sketch, " + groups[g].Count + " tubes in the CSV" +
                    (named ? "" : ", NOT renamed (is " + (feat == null ? "nothing" : feat.Name) + ")"));
                total += inSketch;
            }
            sk.DisplayWhenAdded = true;
            m.ClearSelection2(true);
            m.ViewZoomtofit2();
            rep.Note(total == fr.Tubes.Count, "total: " + total + " lines in " + order.Count + " sketches, " + fr.Tubes.Count +
                     " tubes in frame_tubes.csv (" + missing + " skipped for missing nodes)");
            bool saved = Save(m, out int errs);
            rep.Note(saved, saved ? "saved " + m.GetPathName() : "NOT saved (error " + errs + ")");
            string full = rep.Text("ImportFrameNodes, " + ChassisPath);
            WriteReport(reportFile, full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }
    }
}
