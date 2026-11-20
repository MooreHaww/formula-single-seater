// BuildTubes.cs - port of cad/macros/BuildTubes.bas.
// One Structural Member SM_<group> per FRAME_<group> sketch (profile from
// cad/weldment_profiles/formula/tube_round/<od>x<wall>.sldlfp), material
// AISI 1020, cut list, checks, save, cad/chassis/build_tubes_report.txt.
// Attempts per group: A one group (miter), B one group per segment,
// C every segment as its own feature (failing segments listed).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class BuildTubes
    {
        const string MAT_DB = "SOLIDWORKS Materials";
        // Groups built one structural member feature per tube (2026-11-19). Inside one feature with a group per
        // segment, SolidWorks cuts the groups against each other where they meet: run-through tubes lost 4-9 % of
        // their steel, and at near-collinear joints a member was cut back past its node (FS2_L-FH_L 8.6-10.9 mm,
        // RS2_U-RT2 9.0 mm), leaving ends no trim could close. Built alone, every tube runs node to node (volume
        // 1.000 of its centre-line tube) and TrimTubes copes every joint from frame_trims.csv. The hoop and
        // hoop_brace groups stay one feature: SolidWorks refuses 12 of their 22 segments as features of their own.
        static readonly HashSet<string> PER_TUBE = new HashSet<string> { "sis", "bulkhead", "sidepod", "front", "rear" };

        public static int Run()
        {
            string reportFile = P("cad", "chassis", "build_tubes_report.txt");
            string profDir = P("cad", "weldment_profiles", "formula", "tube_round");
            var fr = ReadFrame();
            var m = Open(ChassisPath);
            var part = (PartDoc)m;
            var fm = m.FeatureManager;

            // sizes and counts per group
            var sizes = new Dictionary<string, string>();
            var badSize = new Dictionary<string, string>();
            var expCount = new Dictionary<string, int>();
            var tubeByPair = new Dictionary<string, string>();
            var order = new List<string>(ImportFrameNodes.Known);
            foreach (var g in order) expCount[g] = 0;
            double csvLength_m = 0; int csvTubes = 0;
            foreach (var r in fr.TubeRows.Where(r => r.Length >= 7))
            {
                string g = r[3], sz = r[4] + "x" + r[5];
                csvLength_m += Val(r[6]) / 1000; csvTubes++;
                if (!expCount.ContainsKey(g)) { expCount[g] = 0; order.Add(g); }
                expCount[g]++;
                if (!sizes.ContainsKey(g)) sizes[g] = sz; else if (sizes[g] != sz) badSize[g] = sizes[g] + " and " + sz;
                tubeByPair[PairKey(r[1], r[2])] = r[0] + " (" + r[1] + " - " + r[2] + ", " + F(Val(r[6]), "0") + " mm)";
            }

            // 0. checks per group
            var segsBy = new Dictionary<string, object[]>();
            var prof = new Dictionary<string, string>();
            var exists = new Dictionary<string, string>();   // group -> how it exists
            var fail = new Dictionary<string, string>();
            int nToBuild = 0;
            foreach (var g in order)
            {
                if (FindFeature(m, "SM_" + g) != null) exists[g] = "SM_" + g;
                var skf = FindFeature(m, "FRAME_" + g);
                if (skf == null) { fail[g] = "no sketch named FRAME_" + g + " (run ImportFrameNodes)"; continue; }
                if (!exists.ContainsKey(g))
                {
                    string kids = MembersFromSketch(skf);
                    if (kids != "") exists[g] = kids;
                }
                var sketch = skf.GetSpecificFeature2() as Sketch;
                var segs = (sketch?.GetSketchSegments() as object[] ?? new object[0])
                    .Cast<SketchSegment>().Where(s => !s.ConstructionGeometry).Cast<object>().ToArray();
                if (segs.Length == 0) { fail[g] = "FRAME_" + g + " has no segments"; continue; }
                segsBy[g] = segs;
                if (exists.ContainsKey(g)) continue;
                if (!sizes.ContainsKey(g)) { fail[g] = "group not in frame_tubes.csv"; continue; }
                if (segs.Length != expCount[g])
                { fail[g] = "FRAME_" + g + " has " + segs.Length + " segments but frame_tubes.csv has " + expCount[g] + " tubes"; continue; }
                if (badSize.ContainsKey(g)) { fail[g] = "mixes tube sizes " + badSize[g]; continue; }
                prof[g] = Path.Combine(profDir, sizes[g] + ".sldlfp");
                if (!File.Exists(prof[g])) { fail[g] = "profile file not found: " + prof[g]; continue; }
                nToBuild++;
            }
            if (nToBuild == 0)
            {
                if (fail.Count == 0)
                {
                    Log("All " + exists.Count + " structural members already exist; nothing to build. Nothing was changed.");
                    return Totals(m, part, fr, csvTubes, csvLength_m, new Report(), reportFile, false);
                }
                throw new StepStoppedException("No group can be built:\n" + string.Join("\n", fail.Select(kv => "  " + kv.Key + ": " + kv.Value)));
            }

            // 2. weldment feature
            if (!HasWeldmentFeature(m, part) && fm.InsertWeldmentFeature() == null)
                throw new StepStoppedException("Could not insert the Weldment feature");

            // 3. members
            var rep = new Report();
            foreach (var g in order)
            {
                if (exists.ContainsKey(g))
                {
                    int ns = segsBy.ContainsKey(g) ? segsBy[g].Length : 0;
                    rep.Note(ns == expCount[g], "SM_" + g + ": existed as " + exists[g] + ", kept (" + ns + " segments, " + expCount[g] + " tubes in CSV)");
                    continue;
                }
                if (fail.ContainsKey(g))
                {
                    if (expCount[g] > 0 || segsBy.ContainsKey(g)) rep.Note(false, g + ": not built, " + fail[g]);
                    continue;
                }
                var segs = segsBy[g];
                m.ClearSelection2(true);
                bool perFeature = PER_TUBE.Contains(g);
                var sm = perFeature ? null : MakeMember(fm, prof[g], segs, true);
                string mode = "one group";
                if (sm == null && !perFeature)
                {
                    m.ClearSelection2(true);
                    sm = MakeMember(fm, prof[g], segs, false);
                    mode = "one group per segment";
                }
                int nOk;
                if (sm != null)
                {
                    if (!Rename(sm, "SM_" + g)) mode += ", " + sm.Name + " NOT renamed to SM_" + g;
                    nOk = segs.Length;
                }
                else
                {
                    string errB = CreateErrors(fm);
                    mode = perFeature ? "one feature per tube" : "segment by segment (one feature refused: " + errB + ")";
                    nOk = 0;
                    var bad = new List<string>();
                    foreach (var seg in segs)
                    {
                        string label = SegmentLabel((SketchSegment)seg, fr.Nodes, tubeByPair);
                        m.ClearSelection2(true);
                        var one = MakeMember(fm, prof[g], new[] { seg }, true);
                        if (one == null) bad.Add("    " + label + ": " + CreateErrors(fm));
                        else { Rename(one, "SM_" + g + "_" + label.Split(' ')[0]); nOk++; }
                    }
                    if (bad.Count > 0) rep.Failures.Append("- " + g + ": " + bad.Count + " of " + segs.Length + " segments refused even alone:\n" + string.Join("\n", bad) + "\n");
                }
                rep.Note(nOk == expCount[g] && segs.Length == expCount[g],
                    "SM_" + g + ": " + nOk + " of " + segs.Length + " segments built (" + expCount[g] + " tubes in CSV), " + sizes[g] + ", " + mode);
            }
            m.ClearSelection2(true);
            m.ForceRebuild3(false);

            // 4. material
            string cfg = ((Configuration)m.ConfigurationManager.ActiveConfiguration).Name;
            part.SetMaterialPropertyName2(cfg, MAT_DB, "AISI 1020");
            string db; string mat = part.GetMaterialPropertyName2(cfg, out db);
            if (!string.Equals(mat, "AISI 1020", StringComparison.OrdinalIgnoreCase))
            {
                part.SetMaterialPropertyName2(cfg, MAT_DB, "Plain Carbon Steel");
                mat = part.GetMaterialPropertyName2(cfg, out db);
            }
            rep.Note(mat != "", mat == "" ? "material: not set" : "material: " + mat + " (" + db + ")");
            m.ForceRebuild3(false);
            return Totals(m, part, fr, csvTubes, csvLength_m, rep, reportFile, true);
        }

        static int Totals(ModelDoc2 m, PartDoc part, FrameData fr, int csvTubes, double csvLength_m, Report rep, string reportFile, bool save)
        {
            CutList(m, out int nBodies, out double cutLen_m, out int lenMissing, out int nFolders);
            double mass = Mass(m);
            rep.Note(nBodies == csvTubes, "cut-list bodies: " + nBodies + " (" + csvTubes + " tubes in CSV, " + nFolders + " cut-list items)");
            if (lenMissing > 0 || nFolders == 0)
                rep.Note(false, "cut length: LENGTH property missing on " + lenMissing + " of " + nFolders + " cut-list items");
            else
                rep.Note(Math.Abs(cutLen_m - csvLength_m) <= 0.05 * csvLength_m, "cut length: " + F(cutLen_m, "0.00") + " m vs " +
                    F(csvLength_m, "0.00") + " m in CSV (" + F(100 * (cutLen_m / csvLength_m - 1), "+0.0;-0.0") + " %, limit 5 %)");
            // expected mass from the CSV (frame_layout.m, steel 7850 kg/m3, centre-line lengths):
            // the bodies here are cut at the nodes (shorter than centre-line), and the
            // material is AISI 1020 (7900), so the part is a few % under; the range
            // was a fixed 38 to 46 kg until the torsion diagonals (2026-11-18)
            double csvMass = fr.TubeRows.Where(r => r.Length >= 8).Sum(r => Val(r[7]));
            double lo = 0.85 * csvMass, hi = 1.05 * csvMass;
            rep.Note(mass >= lo && mass <= hi, "mass: " + F(mass) + " kg (CSV " + F(csvMass) + " kg; expected " + F(lo) + " to " + F(hi) + ")");
            if (save)
            {
                bool saved = Save(m, out int errs);
                rep.Note(saved, saved ? "saved: " + m.GetPathName() : "NOT saved (error " + errs + ")");
            }
            else rep.Info("nothing changed, not saved");
            string full = rep.Text("BuildTubes, " + m.GetPathName());
            WriteReport(reportFile, full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }

        // Arrays of SolidWorks objects must be typed interface arrays (SketchSegment[],
        // StructuralMemberGroup[]): they reach SolidWorks as SAFEARRAY(VT_DISPATCH) like a
        // VBA "As Object" array. An object[] arrives as SAFEARRAY(VARIANT) and the
        // Segments setter silently drops it (read back: null), so every member is refused.
        internal static Feature MakeMember(FeatureManager fm, string profPath, object[] segs, bool oneGroup)
        {
            var parts = oneGroup ? new List<object[]> { segs } : segs.Select(s => new[] { s }).ToList();
            var groups = new List<StructuralMemberGroup>();
            foreach (var p in parts)
            {
                var grp = (StructuralMemberGroup)fm.CreateStructuralMemberGroup();
                grp.Segments = p.Cast<SketchSegment>().ToArray();
                grp.ApplyCornerTreatment = oneGroup;
                if (oneGroup) grp.CornerTreatmentType = (int)swSolidworksWeldmentEndCondOptions_e.swEndConditionMiter;
                groups.Add(grp);
            }
            var arr = groups.ToArray();
            var f = fm.InsertStructuralWeldment5(profPath, (int)swConnectedSegmentsOption_e.swConnectedSegments_SimpleCut, true, arr, "") as Feature;
            if (f == null)
                f = fm.InsertStructuralWeldment4(profPath, (int)swConnectedSegmentsOption_e.swConnectedSegments_SimpleCut, true, arr) as Feature;
            return f;
        }

        static string MembersFromSketch(Feature skf) =>
            skf.GetChildren() is object[] kids ? string.Join(", ", kids.OfType<Feature>().Select(k => k.Name)) : "";

        static string SegmentLabel(SketchSegment seg, Dictionary<string, double[]> nodes, Dictionary<string, string> tubeByPair)
        {
            if (seg.GetType() != (int)swSketchSegments_e.swSketchLINE) return "non-line segment, length " + F(seg.GetLength() * 1000, "0") + " mm";
            var ln = (SketchLine)seg;
            var p1 = (SketchPoint)ln.GetStartPoint2(); var p2 = (SketchPoint)ln.GetEndPoint2();
            string a = NearestNode(p1.X * 1000, p1.Y * 1000, p1.Z * 1000, nodes), b = NearestNode(p2.X * 1000, p2.Y * 1000, p2.Z * 1000, nodes);
            if (a != "" && b != "" && tubeByPair.TryGetValue(PairKey(a, b), out string t)) return t;
            return "unmatched (" + F(p1.X * 1000, "0") + "," + F(p1.Y * 1000, "0") + "," + F(p1.Z * 1000, "0") + ")-(" +
                   F(p2.X * 1000, "0") + "," + F(p2.Y * 1000, "0") + "," + F(p2.Z * 1000, "0") + ") mm";
        }

        static string NearestNode(double x, double y, double z, Dictionary<string, double[]> nodes) =>
            nodes.Where(kv => Math.Abs(kv.Value[0] - x) < 0.5 && Math.Abs(kv.Value[1] - y) < 0.5 && Math.Abs(kv.Value[2] - z) < 0.5)
                 .Select(kv => kv.Key).FirstOrDefault() ?? "";

        static string PairKey(string a, string b) => string.CompareOrdinal(a, b) < 0 ? a + "|" + b : b + "|" + a;

        static bool HasWeldmentFeature(ModelDoc2 m, PartDoc p)
        {
            if (p.IsWeldment()) return true;
            foreach (var f in TopFeatures(m))
            {
                if (f.GetTypeName2() == "WeldmentFeature") return true;
                string nm = f.Name;
                if (nm.StartsWith("Weldment", StringComparison.OrdinalIgnoreCase) && (nm.Length == 8 || nm.Substring(8).All(char.IsDigit))) return true;
            }
            return false;
        }
    }
}
