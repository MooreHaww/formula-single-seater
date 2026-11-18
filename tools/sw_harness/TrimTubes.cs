// TrimTubes.cs - port of cad/macros/TrimTubes.bas v4 (same logic, same report).
// One Trim/Extend feature Trim_<node> per row of cad/frame/frame_trims.csv
// (coped end trim, planar fallback); bodies matched to tubes by the distance
// from the body centroid to the tube's centreline segment; done rows recorded
// as custom properties TrimDone_<node>; body count after every trim; stub
// cleanup (one Delete/Keep Body feature StubsDeleted_<n>); checks; save;
// cad/chassis/trim_tubes_report.txt.
// "--expect-nothing": the run must change nothing (exit 1 if it does).
// Check(): CheckChassis, read-only: bodies = tubes, mass, cut length, one body per tube.
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
    static class TrimTubes
    {
        const string TRIM_VERSION = "TrimTubes v4 (harness port), 2026-11-17: match = distance from body centroid to tube centreline segment, " +
                                    "radius 12 mm, tie margin 8 mm; done rows recorded as custom properties TrimDone_<node>; body count after every trim; stub cleanup";
        const double MATCH_MM = 12, TIE_MM = 8;
        const double STUB_MAX_MM3 = 20000, STUB_MAX_FRACTION = 0.25, STUB_NODE_MM = 60;

        internal class B { public Body2 Body; public string Name; public double X, Y, Z, Vol; }

        internal static List<B> Snap(PartDoc p) => Bodies(p).Select(b =>
        {
            var c = CentroidVol(b);
            return new B { Body = b, Name = b.Name, X = c[0], Y = c[1], Z = c[2], Vol = c[3] };
        }).ToList();

        public static int Run(string[] args)
        {
            bool expectNothing = args.Contains("--expect-nothing");
            string reportFile = P("cad", "chassis", "trim_tubes_report.txt");
            string planFile = P("cad", "frame", "frame_trims.csv");
            if (!File.Exists(planFile)) throw new StepStoppedException("Missing " + planFile + " (run frame_trims in MATLAB)");
            var fr = ReadFrame();
            var m = Open(ChassisPath);
            var part = (PartDoc)m;
            var fm = m.FeatureManager;

            var rows = Csv(planFile).Where(r => r.Length >= 4).ToList();   // trim, node, boundary, trimmed
            if (rows.Count == 0) throw new StepStoppedException("No rows in " + planFile);
            int nRows = rows.Count;

            // 1. diagnostics and checks, nothing changed
            var cpm = m.Extension.CustomPropertyManager[""];
            string treeTxt = FeatureTree(m, out string trimList, out int nTrimAll);
            string diagTxt = MatchTable(Snap(part), fr);
            var rowDone = new string[nRows];
            int nDoneRows = 0;
            for (int r = 0; r < nRows; r++)
            {
                string rec = DoneRecord(cpm, RecKey(rows[r]));
                var byName = part.FeatureByName(rows[r][0]) as Feature;
                var byRec = rec == "" ? null : part.FeatureByName(rec) as Feature;
                if (byName != null && ErrorOf(byName) == 0) rowDone[r] = "by name";
                else if (byRec != null && ErrorOf(byRec) == 0) rowDone[r] = "by record TrimDone_" + RecKey(rows[r]) + " = " + rec;
                else if (rec == NONE_NEEDED) rowDone[r] = "by record TrimDone_" + RecKey(rows[r]) + ": none needed";
                if (rowDone[r] != null) nDoneRows++;
            }
            string header = TRIM_VERSION + "\nPart: " + m.GetPathName() + "\nTrim features in the part before this run: " + nTrimAll +
                            "; plan rows already done (by name or record): " + nDoneRows + "\n";
            var errored = AllFeatures(m).Where(x => x.GetTypeName2() == "WeldCornerFeat" && ErrorOf(x) != 0).Select(x => x.Name).ToList();
            if (errored.Count > 0)
            {
                WriteReport(reportFile, "STOPPED, NOTHING CHANGED   (" + Now() + ")\n" + header + "\n" + errored.Count +
                    " trim features are in error (they cut nothing): " + string.Join(", ", errored) +
                    "\nRebuild the chassis (python tools/sw_run.py rebuild) or delete those features by hand.\n");
                throw new StepStoppedException(errored.Count + " trim features in error: " + string.Join(", ", errored));
            }
            if (nTrimAll > nDoneRows)
            {
                WriteReport(reportFile, "STOPPED, NOTHING CHANGED   (" + Now() + ")\n" + header + "\nThe part has " + nTrimAll +
                    " trim features but only " + nDoneRows + " plan rows are known to be done, so " + (nTrimAll - nDoneRows) +
                    " trim features cannot be tied to a row. Running would trim those tube ends again.\n\nTrim features:\n" + trimList +
                    "\nFeature tree (top level):\n" + treeTxt + "\n" + diagTxt);
                throw new StepStoppedException(nTrimAll + " trim features in the part, only " + nDoneRows + " plan rows known done. Report: " + reportFile);
            }
            var snap0 = Snap(part);
            var bodyOf = MatchBodies(snap0, fr, out string unmatched);
            int nBodies0 = snap0.Count;
            var state = new string[nRows];
            int nToDo = 0, nKept = 0;
            for (int r = 0; r < nRows; r++)
            {
                if (rowDone[r] != null) { state[r] = "kept " + rowDone[r]; nKept++; continue; }
                var why = new StringBuilder();
                foreach (var id in (rows[r][2] + ";" + rows[r][3]).Split(';'))
                {
                    if (!fr.Tubes.ContainsKey(id)) why.Append(id + " not in frame_tubes.csv; ");
                    else if (!bodyOf.ContainsKey(id)) why.Append(id + " has no matching body; ");
                }
                if (why.Length == 0) { state[r] = "todo"; nToDo++; } else state[r] = "skip: " + why;
            }
            if (nToDo == 0)
            {
                string pre = string.Concat(Enumerable.Range(0, nRows).Where(r => state[r].StartsWith("skip"))
                                           .Select(r => "  " + rows[r][0] + ": " + state[r].Substring(6) + "\n"));
                var stubs0 = new List<Body2>();
                string stubTxt0 = FindStubs(Snap(part), fr, stubs0);
                bool longEnds0 = Mitre.Overruns(m, fr).Any(e => e.Reach > Mitre.MITRE_MIN_MM);
                if (pre == "" && stubs0.Count == 0 && !longEnds0)
                {
                    string txt = "NOTHING CHANGED (" + Now() + "): all " + nKept + " plan rows done, no stubs\n" + header + "\n" + stubTxt0 +
                                 "\nTrim features:\n" + trimList + "\n" + diagTxt;
                    WriteReport(reportFile, txt);
                    Log(txt.Split('\n')[0]);
                    return Check();      // the full check of the part as it is
                }
                if (pre != "")
                {
                    WriteReport(reportFile, "NOTHING CHANGED (" + Now() + ")\n\nBodies: " + nBodies0 + ", tubes in CSV: " + fr.Tubes.Count +
                        "\nUnmatched: " + unmatched + "\n\n" + pre + "\n" + header + "\nTrim features:\n" + trimList + "\n" + diagTxt);
                    throw new StepStoppedException("No trim row can be made:\n" + pre + "Report: " + reportFile);
                }
                // all rows done but stubs to clean or long ends to mitre: carry on
            }

            double mass0 = Mass(m);
            var rep = new Report();
            // 1b. mitre cuts first (Mitre.cs): the slivers BuildTubes leaves at shallow joints make some coped trims
            //     error (RRK-RT1); cut back, those tubes need no trim or trim cleanly
            var longEndsPre = Mitre.Overruns(m, fr).Where(e => e.Reach > Mitre.MITRE_MIN_MM).ToList();
            int nMitre = longEndsPre.Count == 0 ? 0 : Mitre.Cut(m, fr, longEndsPre, rep);
            if (longEndsPre.Count > 0) m.ForceRebuild3(false);

            // 2. trims
            var split = new StringBuilder();
            int nDone = 0; string trimType = "";
            var droppedTxt = new StringBuilder();
            int nNone = 0;
            for (int r = 0; r < nRows; r++)
            {
                string name = rows[r][0], node = rows[r][1], bnd = rows[r][2], trm = rows[r][3], key = RecKey(rows[r]);
                if (state[r].StartsWith("kept")) { rep.Note(true, name + ": already done (" + state[r].Substring(5) + "), kept"); continue; }
                if (state[r].StartsWith("skip")) { rep.Note(false, name + ": not made, " + state[r].Substring(6)); continue; }
                var snap = Snap(part);
                bodyOf = MatchBodies(snap, fr, out _);
                var namesBefore = new HashSet<string>(snap.Select(b => b.Name));
                int countBefore = snap.Count;
                var bIds = bnd.Split(';'); var tIds = trm.Split(';');
                var lost = bIds.Concat(tIds).Where(id => !bodyOf.ContainsKey(id)).ToList();
                if (lost.Count > 0) { rep.Note(false, name + ": lost the match for " + string.Join(" ", lost) + " after earlier trims"); continue; }
                var bArr = bIds.Select(id => bodyOf[id]).ToArray();
                // A trim whose tube list contains one tube that the structural member already
                // shaped against this boundary (nothing left to cut) is created by the API but
                // stays in error (code 1, "unknown"), cuts nothing at all and is skipped by the
                // feature-tree walk. So: check the error; on error delete it, try every tube
                // alone, and make the row from the tubes that trim cleanly.
                string mode;
                var dropped = new List<string>();
                var dropOv = new Dictionary<string, double>();
                var f = MakeRow(m, fm, tIds.Select(id => bodyOf[id]).ToArray(), bArr, out mode);
                var keep = tIds.ToList();
                var separate = new List<string>();
                if (f == null)
                {
                    string allErr = mode;
                    keep.Clear();
                    // a deleted feature leaves the Body2 handles stale: match again before every call
                    foreach (var id in tIds)
                    {
                        bodyOf = MatchBodies(Snap(part), fr, out _);
                        bArr = bIds.Select(x => bodyOf[x]).ToArray();
                        var one = MakeRow(m, fm, new[] { bodyOf[id] }, bArr, out string m1);
                        if (one != null) { keep.Add(id); DeleteFeature(m, one); continue; }
                        bodyOf = MatchBodies(Snap(part), fr, out _);
                        bArr = bIds.Select(x => bodyOf[x]).ToArray();
                        double ov = Overlap(bodyOf[id], bArr);
                        dropOv[id] = ov;
                        dropped.Add(id + " (" + m1 + "; overlap with the boundary " + F(ov, "0") + " mm3)");
                    }
                    bodyOf = MatchBodies(Snap(part), fr, out _);
                    bArr = bIds.Select(x => bodyOf[x]).ToArray();
                    f = keep.Count == 0 ? null : MakeRow(m, fm, keep.Select(id => bodyOf[id]).ToArray(), bArr, out mode);
                    mode += "; all " + tIds.Length + " together: " + allErr;
                    if (f == null && keep.Count > 1)
                    {
                        // every kept tube trims alone, but not all together (seen at RS1_U, 2026-11-17):
                        // grow the row one tube at a time, keeping it error-free; the tubes that do not
                        // fit get a trim feature of their own below
                        var set = new List<string>();
                        separate.Clear();
                        foreach (var id in keep)
                        {
                            bodyOf = MatchBodies(Snap(part), fr, out _);
                            bArr = bIds.Select(x => bodyOf[x]).ToArray();
                            var g = MakeRow(m, fm, set.Concat(new[] { id }).Select(x => bodyOf[x]).ToArray(), bArr, out _);
                            if (g != null) { DeleteFeature(m, g); set.Add(id); } else separate.Add(id);
                        }
                        bodyOf = MatchBodies(Snap(part), fr, out _);
                        bArr = bIds.Select(x => bodyOf[x]).ToArray();
                        f = set.Count == 0 ? null : MakeRow(m, fm, set.Select(id => bodyOf[id]).ToArray(), bArr, out mode);
                        if (f != null) { mode += "; the " + keep.Count + " tubes that trim alone errored together, so " + set.Count + " together and " + separate.Count + " tried in a trim of its own"; keep = set; }
                        else separate.Clear();
                    }
                }
                if (f == null && dropOv.Count == tIds.Length && dropOv.Values.All(v => v <= DROP_MAX_MM3))
                {
                    // every tube of the row is already cut by the structural members: nothing to trim
                    cpm.Add3("TrimDone_" + key, (int)swCustomInfoType_e.swCustomInfoText, NONE_NEEDED, (int)swCustomPropertyAddOption_e.swCustomPropertyReplaceValue);
                    rep.Note(true, name + ": none needed, every tube is already cut against " + bnd + " by the structural member (" + string.Join("; ", dropped) + ")");
                    droppedTxt.Append("- " + name + ": none needed: " + string.Join("; ", dropped) + "\n");
                    nNone++;
                    continue;
                }
                if (f == null)
                {
                    // last try (RRK-RT1, 2026-11-17): every tube against one boundary tube at a time
                    var single = new List<string>();
                    foreach (var id in tIds)
                        foreach (var bo in bIds)
                        {
                            bodyOf = MatchBodies(Snap(part), fr, out _);
                            var g = MakeRow(m, fm, new[] { bodyOf[id] }, new[] { bodyOf[bo] }, out _);
                            if (g == null) continue;
                            string nmG = single.Count == 0 ? name : name + "_" + (single.Count + 1);
                            while (part.FeatureByName(nmG) != null) nmG += "x";
                            Rename(g, nmG);
                            single.Add(g.Name + " (" + id + " against " + bo + ")");
                            nDone++;
                        }
                    if (single.Count > 0)
                    {
                        bodyOf = MatchBodies(Snap(part), fr, out _);
                        var left = tIds.ToDictionary(id => id, id => Overlap(bodyOf[id], bIds.Select(x => bodyOf[x]).ToArray()));
                        bool okS = left.Values.All(v => v <= DROP_MAX_MM3);
                        cpm.Add3("TrimDone_" + key, (int)swCustomInfoType_e.swCustomInfoText, string.Join(";", single), (int)swCustomPropertyAddOption_e.swCustomPropertyReplaceValue);
                        rep.Note(okS, name + ": the row errors (" + mode + "); trimmed one boundary tube at a time: " + string.Join(", ", single) +
                                 "; overlap left with the boundary: " + string.Join(", ", left.Select(kv => kv.Key + " " + F(kv.Value, "0") + " mm3")));
                        continue;
                    }
                    rep.Note(false, name + " at node " + node + ": no trim without error (" + mode + "), boundary " + bnd + ", trimmed " + trm +
                             (dropped.Count > 0 ? "; tubes: " + string.Join("; ", dropped) : ""));
                    continue;
                }
                if (!Rename(f, name)) mode += ", NOT renamed (is " + f.Name + ")";
                nDone++;
                if (trimType == "") trimType = f.GetTypeName2();
                cpm.Add3("TrimDone_" + key, (int)swCustomInfoType_e.swCustomInfoText, f.Name, (int)swCustomPropertyAddOption_e.swCustomPropertyReplaceValue);
                // a tube left out that still overlaps the boundary: trim it in a second feature
                // Trim_<node>_2 against the boundary plus every other tube at this node it runs into
                // (SolidWorks errors when the tube end lies in two tubes and only one is the boundary)
                var second = new List<string>();
                foreach (var id in separate)
                {
                    bodyOf = MatchBodies(Snap(part), fr, out _);
                    bArr = bIds.Select(x => bodyOf[x]).ToArray();
                    var fs = MakeRow(m, fm, new[] { bodyOf[id] }, bArr, out string ms);
                    if (fs == null)
                    {
                        bodyOf = MatchBodies(Snap(part), fr, out _);
                        dropOv[id] = Overlap(bodyOf[id], bIds.Select(x => bodyOf[x]).ToArray());
                        second.Add(id + ": its own trim failed (" + ms + "), overlap " + F(dropOv[id], "0") + " mm3");
                        continue;
                    }
                    string nmS = name + "_2"; int kS = 2;
                    while (part.FeatureByName(nmS) != null) nmS = name + "_" + (++kS);
                    Rename(fs, nmS);
                    cpm.Add3("TrimDone_" + key + "_" + kS, (int)swCustomInfoType_e.swCustomInfoText, fs.Name, (int)swCustomPropertyAddOption_e.swCustomPropertyReplaceValue);
                    second.Add(id + ": trimmed alone in " + fs.Name);
                    nDone++;
                }
                foreach (var id in dropOv.Where(kv => kv.Value > DROP_MAX_MM3).Select(kv => kv.Key).ToList())
                {
                    bodyOf = MatchBodies(Snap(part), fr, out _);
                    var extra = fr.TubeOrder.Where(o => o != id && !bIds.Contains(o) && TubeAtNode(fr, o, node) && bodyOf.ContainsKey(o))
                                  .Where(o => Overlap(bodyOf[id], new[] { bodyOf[o] }) > DROP_MAX_MM3).ToList();
                    var b2 = bIds.Concat(extra).Select(x => bodyOf[x]).ToArray();
                    var f2 = extra.Count == 0 ? null : MakeRow(m, fm, new[] { bodyOf[id] }, b2, out string m2);
                    if (f2 == null)
                    {
                        // last try (RRK-RT1, 2026-11-17): one trim per boundary tube, each alone
                        var single = new List<string>();
                        foreach (var bo in bIds.Concat(extra))
                        {
                            bodyOf = MatchBodies(Snap(part), fr, out _);
                            var g = MakeRow(m, fm, new[] { bodyOf[id] }, new[] { bodyOf[bo] }, out _);
                            if (g == null) continue;
                            string nmG = name + "_2"; int kG = 2;
                            while (part.FeatureByName(nmG) != null) nmG = name + "_" + (++kG);
                            Rename(g, nmG);
                            cpm.Add3("TrimDone_" + key + "_" + kG, (int)swCustomInfoType_e.swCustomInfoText, g.Name, (int)swCustomPropertyAddOption_e.swCustomPropertyReplaceValue);
                            single.Add(g.Name + " against " + bo);
                            nDone++;
                        }
                        bodyOf = MatchBodies(Snap(part), fr, out _);
                        dropOv[id] = Overlap(bodyOf[id], bIds.Select(x => bodyOf[x]).ToArray());
                        second.Add(id + ": second trim against " + bnd + ";" + string.Join(";", extra) + " failed too" +
                                   (single.Count > 0 ? "; trimmed one boundary at a time: " + string.Join(", ", single) : "; one boundary at a time failed too") +
                                   ", overlap now " + F(dropOv[id], "0") + " mm3");
                        continue;
                    }
                    string nm2 = name + "_2"; int k2 = 2;
                    while (part.FeatureByName(nm2) != null) nm2 = name + "_" + (++k2);
                    Rename(f2, nm2);
                    cpm.Add3("TrimDone_" + key + "_" + k2, (int)swCustomInfoType_e.swCustomInfoText, f2.Name, (int)swCustomPropertyAddOption_e.swCustomPropertyReplaceValue);
                    second.Add(id + ": trimmed in " + f2.Name + " against " + bnd + ";" + string.Join(";", extra));
                    dropOv[id] = 0;     // done
                    nDone++;
                }
                if (second.Count > 0) mode += "; " + string.Join("; ", second);
                // a tube may be left out only if (practically) nothing of it is inside the boundary
                bool dropOk = dropOv.Values.All(v => v <= DROP_MAX_MM3);
                rep.Note(dropOk, name + ": " + keep.Count + " ends against " + bArr.Length + " boundary tube(s), " + mode +
                         (dropped.Count > 0 ? "; left out (already cut by the structural member, the trim errors on them): " + string.Join("; ", dropped) : ""));
                if (dropped.Count > 0) droppedTxt.Append("- " + name + ": " + string.Join("; ", dropped) + "\n");
                int nAfter = Bodies(part).Length;
                if (nAfter != countBefore)
                {
                    string newNames = string.Join("; ", Snap(part).Where(b => !namesBefore.Contains(b.Name))
                        .Select(b => b.Name + " at (" + F(b.X, "0") + "," + F(b.Y, "0") + "," + F(b.Z, "0") + ") mm, " + F(b.Vol, "0") + " mm3"));
                    if (newNames == "") newNames = "(no new names; compare the AFTER table)";
                    split.Append("- " + name + ": bodies " + countBefore + " -> " + nAfter + "; trimmed " + trm + " against " + bnd +
                                 "; bodies with a new name after it: " + newNames + "\n");
                    rep.Line("SPLIT " + name + ": bodies " + countBefore + " -> " + nAfter + " (new body names: " + newNames + ")");
                }
            }
            m.ClearSelection2(true);
            m.ForceRebuild3(false);

            // 2b. stub cleanup
            var stubs = new List<Body2>();
            string stubTxt = FindStubs(Snap(part), fr, stubs);
            int nDel = 0;
            if (stubs.Count > 0)
            {
                string delName = DeleteStubs(m, fm, stubs, cpm);
                if (delName == "") rep.Note(false, "stub cleanup: Delete/Keep Body refused (" + CreateErrors(fm) + "), " + stubs.Count + " stubs stay");
                else { nDel = stubs.Count; rep.Note(true, delName + ": " + nDel + " stub bodies deleted"); }
                m.ForceRebuild3(false);
            }

            // 2c. mitre cuts: tube ends left reaching past their node (Mitre.cs)
            var longEnds = Mitre.Overruns(m, fr).Where(e => e.Reach > Mitre.MITRE_MIN_MM).ToList();
            nMitre += longEnds.Count == 0 ? 0 : Mitre.Cut(m, fr, longEnds, rep);
            if (longEnds.Count > 0) m.ForceRebuild3(false);
            double maxReach = Mitre.Overruns(m, fr).Max(e => e.Reach);
            rep.Note(maxReach <= Mitre.MITRE_MIN_MM + 0.5, "tube ends past their node: largest " + F(maxReach, "0") + " mm (limit " + F(Mitre.MITRE_MIN_MM, "0") +
                     " mm), " + nMitre + " mitre cuts made in this run");

            // 3. totals
            CutList(m, out int nCut, out double cutLen_m, out int lenMissing, out int nFolders);
            int nBodies1 = Bodies(part).Length;
            double mass1 = Mass(m);
            rep.Line("");
            rep.Note(nBodies1 == fr.Tubes.Count, "bodies: " + nBodies0 + " before, " + nBodies1 + " after, " + fr.Tubes.Count +
                     " tubes in frame_tubes.csv (must be equal after the run)");
            rep.Note(mass1 <= mass0 + 1e-3 && mass1 >= 38 && mass1 <= 46, "mass: " + F(mass0, "0.00") + " kg before, " + F(mass1, "0.00") +
                     " kg after (" + F(mass1 - mass0, "+0.00;-0.00") + " kg; must not rise, 38 to 46)");
            if (lenMissing > 0 || nFolders == 0) rep.Info("cut length: LENGTH missing on " + lenMissing + " of " + nFolders + " cut-list items");
            else rep.Info("cut length after trim: " + F(cutLen_m, "0.00") + " m (" + nCut + " bodies in the cut list)");
            if (expectNothing) rep.Note(nDone == 0 && nDel == 0 && nMitre == 0, "second run changes nothing: " + nDone + " trims made, " + nDel + " stubs deleted, " + nMitre + " mitre cuts");
            if (nDone > 0 || nDel > 0 || nMitre > 0)
            {
                bool saved = Save(m, out int errs);
                rep.Note(saved, saved ? "saved: " + m.GetPathName() : "NOT saved (error " + errs + ")");
            }
            else rep.Info("nothing changed, not saved");

            string full = rep.Text("TrimTubes: " + nDone + " trims made, " + nNone + " none needed, " + nKept + " kept, " + nDel + " stubs deleted, " + nRows + " in plan") +
                "\n\n" + header +
                "made = new trim features inserted in this run; kept = rows already done before it (by name Trim_<node> or record TrimDone_<node>)\n" +
                "\nTrims that changed the body count:\n" + (split.Length == 0 ? "  (none in this run)\n" : split.ToString()) +
                "\nTubes left out of a trim (already cut by the structural member; overlap with the boundary measured):\n" +
                (droppedTxt.Length == 0 ? "  (none)\n" : droppedTxt.ToString()) +
                "\nStubs found after the trims:\n" + stubTxt +
                (unmatched == "" ? "" : "\nBodies or tubes without a match before trimming: " + unmatched) +
                (trimType == "" ? "" : "\nType name of the trim features made in this run: " + trimType) +
                "\n\nTrim features before this run:\n" + trimList + "\nBEFORE this run:\n" + diagTxt + "\nAFTER this run:\n" + MatchTable(Snap(part), fr);
            WriteReport(reportFile, full);
            Log(full.Substring(0, full.IndexOf("\n\n" + header, StringComparison.Ordinal)));
            return rep.AllPass ? 0 : 1;
        }

        /// CheckChassis: read-only checks of the saved chassis; cad/chassis/check_chassis_report.txt.
        public static int Check()
        {
            var fr = ReadFrame();
            var m = Open(ChassisPath);
            var part = (PartDoc)m;
            var rep = new Report();
            double csvLen = fr.TubeRows.Where(r => r.Length >= 7).Sum(r => Val(r[6])) / 1000;
            var snap = Snap(part);
            var bodyOf = MatchBodies(snap, fr, out string unmatched);
            rep.Note(snap.Count == fr.Tubes.Count, "bodies: " + snap.Count + " (" + fr.Tubes.Count + " tubes in frame_tubes.csv)");
            rep.Note(bodyOf.Count == fr.Tubes.Count && unmatched == "", "one body per tube: " + bodyOf.Count + " of " + fr.Tubes.Count + " matched" +
                     (unmatched == "" ? "" : "; " + unmatched));
            CutList(m, out int nCut, out double cutLen, out int lenMissing, out int nFolders);
            rep.Note(nCut == fr.Tubes.Count, "cut-list bodies: " + nCut + " in " + nFolders + " items");
            rep.Note(lenMissing == 0 && Math.Abs(cutLen - csvLen) <= 0.05 * csvLen, "cut length: " + F(cutLen, "0.00") + " m vs " + F(csvLen, "0.00") +
                     " m centreline sum in CSV (limit 5 %)" + (lenMissing > 0 ? ", LENGTH missing on " + lenMissing : ""));
            double mass = Mass(m);
            // range from the CSV mass (centre-line lengths, 7850 kg/m3); trimmed AISI 1020 bodies come out a
            // few % under. A fixed 38 to 46 kg until the torsion diagonals (2026-11-18)
            double csvMass = fr.TubeRows.Where(r => r.Length >= 8).Sum(r => Val(r[7]));
            rep.Note(mass >= 0.85 * csvMass && mass <= 1.05 * csvMass, "mass: " + F(mass, "0.00") + " kg (CSV " + F(csvMass, "0.00") +
                     " kg; expected " + F(0.85 * csvMass, "0.0") + " to " + F(1.05 * csvMass, "0.0") + ")");
            var plan = Csv(P("cad", "frame", "frame_trims.csv")).Where(r => r.Length >= 4).ToList();
            var cpm = m.Extension.CustomPropertyManager[""];
            int nFeat = 0, nNone = 0; var notDone = new List<string>();
            foreach (var r in plan)
            {
                var f = part.FeatureByName(r[0]) as Feature;
                if (f != null && ErrorOf(f) == 0) nFeat++;
                else if (DoneRecord(cpm, RecKey(r)) == NONE_NEEDED) nNone++;
                else notDone.Add(r[0]);
            }
            rep.Note(notDone.Count == 0, "trim rows done: " + nFeat + " with a Trim_<node> feature without error, " + nNone +
                     " none needed (already cut by the structural members), " + plan.Count + " rows in frame_trims.csv" +
                     (notDone.Count > 0 ? "; NOT done: " + string.Join(", ", notDone) : ""));
            var errs = AllFeatures(m).Where(f => ErrorOf(f) != 0).Select(f => f.Name + " [" + f.GetTypeName2() + "]").ToList();
            rep.Note(errs.Count == 0, "features with rebuild errors (all features, FeatureManager.GetFeatures): " + errs.Count +
                     (errs.Count > 0 ? ": " + string.Join(", ", errs) : ""));
            // tubes that share a node: how much of one is still inside the other (temporary body intersection)
            bodyOf = MatchBodies(Snap(part), fr, out _);      // CutList rebuilt the part: fresh handles
            var ovs = new List<Tuple<double, string>>();
            var ids = fr.TubeOrder.Where(bodyOf.ContainsKey).ToList();
            for (int i = 0; i < ids.Count; i++)
                for (int j = i + 1; j < ids.Count; j++)
                {
                    var ri = fr.TubeRows.First(r => r[0] == ids[i]); var rj = fr.TubeRows.First(r => r[0] == ids[j]);
                    string shared = new[] { ri[1], ri[2] }.Intersect(new[] { rj[1], rj[2] }).FirstOrDefault();
                    if (shared == null) continue;
                    double v = Overlap(bodyOf[ids[i]], new[] { bodyOf[ids[j]] });
                    ovs.Add(Tuple.Create(v, ids[i] + " / " + ids[j] + " at " + shared));
                }
            var big = ovs.Where(o => double.IsNaN(o.Item1) || o.Item1 > OVERLAP_MAX_MM3).OrderByDescending(o => double.IsNaN(o.Item1) ? 1e12 : o.Item1).ToList();
            // WARN, not FAIL: the trim plan (matlab frame_trims.m) cuts each tube against the boundary of its node only;
            // two "trimmed" tubes can still overlap each other. Which tube runs through is a design decision.
            rep.Warn(big.Count == 0, "tube pairs at a shared node: " + ovs.Count + " checked, largest overlap " +
                     F(ovs.Count == 0 ? 0 : ovs.Where(o => !double.IsNaN(o.Item1)).DefaultIfEmpty(Tuple.Create(0.0, "")).Max(o => o.Item1), "0") + " mm3, " +
                     ovs.Count(o => double.IsNaN(o.Item1)) + " not measurable, " + big.Count + " above " + F(OVERLAP_MAX_MM3, "0") + " mm3" +
                     (big.Count > 0 ? ": " + string.Join("; ", big.Take(30).Select(o => o.Item2 + " " + F(o.Item1, "0") + " mm3")) +
                     " (both tubes are 'trimmed' in frame_trims.csv, neither is cut against the other)" : ""));
            string full = rep.Text("CheckChassis, " + m.GetPathName());
            WriteReport(P("cad", "chassis", "check_chassis_report.txt"), full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }

        const double DROP_MAX_MM3 = 50;   // a tube may be left out of a trim only if it overlaps the boundary by less than this

        const double OVERLAP_MAX_MM3 = 200;   // CheckChassis: tube pairs at a node may overlap less than this (welding noise)

        public const string NONE_NEEDED = "(none needed: already cut by the structural members)";

        static bool TubeAtNode(FrameData fr, string id, string node) =>
            fr.TubeRows.Any(r => r[0] == id && (r[1] == node || r[2] == node));

        /// Trim (coped, planar fallback); returns the feature only if it is free of errors, else deletes it.
        static Feature MakeRow(ModelDoc2 m, FeatureManager fm, Body2[] t, Body2[] b, out string mode)
        {
            mode = "";
            // remember the tubes by centroid, so fresh handles can be found after a delete
            var tc = t.Select(CentroidVol).ToArray(); var bc = b.Select(CentroidVol).ToArray();
            var part = (PartDoc)m;
            foreach (int opt in new[] { (int)swWeldmentTrimExtendOptionType_e.swWeldmentTrimExtendOption_CopedCut, 0 })
            {
                if (opt == 0 && mode.Contains("in error")) { t = Refind(part, tc); b = Refind(part, bc); }
                m.ClearSelection2(true);
                var f = TrimFeature(fm, t, b, opt);
                string label = opt == 0 ? "planar" : "coped";
                if (f == null) { mode += (mode == "" ? "" : ", ") + label + " refused (" + CreateErrors(fm) + ")"; continue; }
                int e = ErrorOf(f);
                if (e == 0) { mode = label + (mode == "" ? "" : " (" + mode + ")"); return f; }
                mode += (mode == "" ? "" : ", ") + label + " made but in error " + e;
                DeleteFeature(m, f);
            }
            return null;
        }

        /// Bodies of the part nearest (by centroid) to the given centroids.
        static Body2[] Refind(PartDoc p, double[][] cs)
        {
            var all = Bodies(p).Select(x => new { B = x, C = CentroidVol(x) }).ToList();
            return cs.Select(c => all.OrderBy(a => Dist3(a.C[0], a.C[1], a.C[2], c[0], c[1], c[2])).First().B).ToArray();
        }

        static void DeleteFeature(ModelDoc2 m, Feature f)
        {
            m.ClearSelection2(true);
            f.Select2(false, 0);
            m.Extension.DeleteSelection2(0);
            m.ClearSelection2(true);
        }

        public static int ErrorOf(Feature f) { bool w; int e = f.GetErrorCode2(out w); return w ? 0 : e; }

        /// Every feature, including those the FirstFeature/GetNextFeature walk skips (features in error).
        public static IEnumerable<Feature> AllFeatures(ModelDoc2 m) =>
            (m.FeatureManager.GetFeatures(false) as object[] ?? new object[0]).OfType<Feature>();

        /// Volume (mm3) of the intersection of a body with the boundary bodies (temporary copies; the part is not changed).
        static double Overlap(Body2 a, Body2[] bnd)
        {
            double v = 0;
            foreach (var b in bnd)
            {
                var ca = a.Copy() as Body2; var cb = b.Copy() as Body2;
                if (ca == null || cb == null) return double.NaN;
                int err;
                if (ca.Operations2((int)swBodyOperationType_e.SWBODYINTERSECT, cb, out err) is object[] res)
                    foreach (Body2 r in res.OfType<Body2>())
                        if (r.GetMassProperties(7900.0) is double[] mp) v += mp[3] * 1e9;
            }
            return v;
        }

        // Arrays of bodies must be typed (Body2[]), see BuildTubes.MakeMember.
        static Feature TrimFeature(FeatureManager fm, Body2[] t, Body2[] b, int opts) =>
            fm.InsertWeldmentTrimFeature2((int)swSolidworksWeldmentEndCondOptions_e.swEndConditionTrim, opts, 0.0, t, b) as Feature;

        internal static Dictionary<string, Body2> MatchBodies(List<B> snap, FrameData fr, out string unmatched)
        {
            var res = new Dictionary<string, Body2>();
            var sb = new StringBuilder();
            if (snap.Count == 0) { unmatched = "no solid bodies"; return res; }
            for (int k = 0; k < snap.Count; k++)
            {
                var b = snap[k];
                double best = 1e30, second = 1e30; string bestId = "", secondId = "";
                foreach (var id in fr.TubeOrder)
                {
                    double s = DistToSegment(b.X, b.Y, b.Z, fr.Tubes[id]);
                    if (s < best) { second = best; secondId = bestId; best = s; bestId = id; }
                    else if (s < second) { second = s; secondId = id; }
                }
                if (bestId != "" && best <= MATCH_MM && second - best >= TIE_MM && !res.ContainsKey(bestId)) res[bestId] = b.Body;
                else sb.Append("body " + k + " at (" + F(b.X, "0") + "," + F(b.Y, "0") + "," + F(b.Z, "0") + ") mm, best " + bestId + " " + F(best) +
                               " mm, next " + secondId + " " + F(second) + " mm" + (res.ContainsKey(bestId) ? " (already taken)" : "") + "; ");
            }
            foreach (var id in fr.TubeOrder) if (!res.ContainsKey(id)) sb.Append("tube " + id + " has no body; ");
            unmatched = sb.ToString();
            return res;
        }

        static string MatchTable(List<B> snap, FrameData fr)
        {
            if (snap.Count == 0) return "No solid bodies.\n";
            int nB = snap.Count, nT = fr.TubeOrder.Count;
            var d = new double[nT, nB];
            for (int i = 0; i < nT; i++) for (int k = 0; k < nB; k++) d[i, k] = DistToSegment(snap[k].X, snap[k].Y, snap[k].Z, fr.Tubes[fr.TubeOrder[i]]);
            var sb = new StringBuilder("Tube table (mm). tube | centreline A -> B | nearest body: index, name, centroid, distance to segment | next body: index, distance | OK if nearest <= " +
                                       F(MATCH_MM, "0") + " and next >= nearest + " + F(TIE_MM, "0") + "\n");
            for (int i = 0; i < nT; i++)
            {
                var t = fr.Tubes[fr.TubeOrder[i]];
                var ord = Enumerable.Range(0, nB).OrderBy(k => d[i, k]).ToList();
                int b1 = ord[0], b2 = nB > 1 ? ord[1] : -1;
                bool ok = d[i, b1] <= MATCH_MM && (b2 < 0 || d[i, b2] - d[i, b1] >= TIE_MM);
                sb.Append("  " + fr.TubeOrder[i] + " | (" + F(t[0], "0") + "," + F(t[1], "0") + "," + F(t[2], "0") + ") -> (" + F(t[3], "0") + "," + F(t[4], "0") + "," +
                          F(t[5], "0") + ") | body " + b1 + " " + snap[b1].Name + " (" + F(snap[b1].X) + "," + F(snap[b1].Y) + "," + F(snap[b1].Z) + ") " + F(d[i, b1]) +
                          (b2 >= 0 ? " | body " + b2 + " " + F(d[i, b2]) : "") + " | " + (ok ? "OK" : "NO MATCH") + "\n");
            }
            sb.Append("\nBodies matched to no tube (mm): index, name, centroid | nearest tube, distance | next tube, distance\n");
            int nBad = 0;
            for (int k = 0; k < nB; k++)
            {
                var ord = Enumerable.Range(0, nT).OrderBy(i => d[i, k]).ToList();
                int t1 = ord[0], t2 = nT > 1 ? ord[1] : -1;
                bool ok = d[t1, k] <= MATCH_MM && (t2 < 0 || d[t2, k] - d[t1, k] >= TIE_MM);
                if (ok) continue;
                nBad++;
                sb.Append("  body " + k + " " + snap[k].Name + " (" + F(snap[k].X) + "," + F(snap[k].Y) + "," + F(snap[k].Z) + ") | " + fr.TubeOrder[t1] + " " +
                          F(d[t1, k]) + (t2 >= 0 ? " | " + fr.TubeOrder[t2] + " " + F(d[t2, k]) : "") + "\n");
            }
            if (nBad == 0) sb.Append("  (none: every body matches one tube)\n");
            return sb.ToString();
        }

        static string FindStubs(List<B> snap, FrameData fr, List<Body2> stubs)
        {
            if (snap.Count == 0) return "  (no bodies)\n";
            var nearest = snap.Select(b => fr.TubeOrder.OrderBy(id => DistToSegment(b.X, b.Y, b.Z, fr.Tubes[id])).First()).ToList();
            var largest = new Dictionary<string, int>();
            for (int k = 0; k < snap.Count; k++)
                if (!largest.ContainsKey(nearest[k]) || snap[k].Vol > snap[largest[nearest[k]]].Vol) largest[nearest[k]] = k;
            var sb = new StringBuilder();
            for (int k = 0; k < snap.Count; k++)
            {
                if (largest[nearest[k]] == k) continue;
                var b = snap[k]; var t = fr.Tubes[nearest[k]];
                double dEnd = Math.Min(Dist3(b.X, b.Y, b.Z, t[0], t[1], t[2]), Dist3(b.X, b.Y, b.Z, t[3], t[4], t[5]));
                fr.TubeVol.TryGetValue(nearest[k], out double tv);
                bool isStub = b.Vol <= STUB_MAX_MM3 && tv > 0 && b.Vol <= STUB_MAX_FRACTION * tv && dEnd <= STUB_NODE_MM;
                sb.Append("  " + (isStub ? "STUB  " : "EXTRA ") + b.Name + " at (" + F(b.X) + "," + F(b.Y) + "," + F(b.Z) + ") mm, " + F(b.Vol, "0") + " mm3 (" +
                          F(tv > 0 ? b.Vol / tv * 100 : 0) + " % of tube " + nearest[k] + "), " + F(dEnd) + " mm from its nearest end node" +
                          (isStub ? " -> delete" : " -> NOT a stub, left alone") + "\n");
                if (isStub) stubs.Add(b.Body);
            }
            foreach (var id in fr.TubeOrder) if (!largest.ContainsKey(id)) sb.Append("  tube " + id + " has no body\n");
            return sb.Length == 0 ? "  (none: one body per tube)\n" : sb.ToString();
        }

        static string DeleteStubs(ModelDoc2 m, FeatureManager fm, List<Body2> stubs, CustomPropertyManager cpm)
        {
            m.ClearSelection2(true);
            string names = string.Join(" ", stubs.Select(b => b.Name));
            foreach (var b in stubs) b.Select2(true, null);
            var f = fm.InsertDeleteBody2(false) as Feature;
            m.ClearSelection2(true);
            if (f == null) return "";
            int n = 1;
            while (FindFeatureDeep(m, "StubsDeleted_" + n) != null) n++;
            Rename(f, "StubsDeleted_" + n);
            cpm.Add3("TrimStubs_" + n, (int)swCustomInfoType_e.swCustomInfoText, names.Length > 250 ? names.Substring(0, 250) : names,
                     (int)swCustomPropertyAddOption_e.swCustomPropertyReplaceValue);
            return f.Name;
        }

        static string FeatureTree(ModelDoc2 m, out string trimList, out int nTrim)
        {
            var tree = new StringBuilder(); var tl = new StringBuilder(); int n = 0, k = 0;
            foreach (var f in TopFeatures(m))
            {
                k++;
                tree.Append("  " + k.ToString("000") + "  " + f.Name + "  [" + f.GetTypeName2() + "]\n");
                if (IsTrim(f)) { n++; tl.Append("  " + f.Name + "  [" + f.GetTypeName2() + "]\n"); }
                foreach (var s in SubFeatures(f))
                    if (IsTrim(s)) { n++; tl.Append("  " + s.Name + "  [" + s.GetTypeName2() + "]  (sub-feature of " + f.Name + ")\n"); }
            }
            trimList = tl.Length == 0 ? "  (none)\n" : tl.ToString();
            nTrim = n;
            return tree.ToString();
        }

        static bool IsTrim(Feature f)
        {
            string nm = f.Name.ToLowerInvariant();
            return nm.StartsWith("trim_") || nm.StartsWith("trim/extend") || f.GetTypeName2().IndexOf("Trim", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        /// Record key of a plan row: the trim name without "Trim_" (= the node for the first
        /// row of a node; a node with tubes at several rank levels has rows Trim_<node>_b<k>).
        static string RecKey(string[] row) => row[0].StartsWith("Trim_") ? row[0].Substring(5) : row[1];

        static string DoneRecord(CustomPropertyManager cpm, string node)
        {
            if (cpm == null) return "";
            cpm.Get6("TrimDone_" + node, false, out string v, out string res, out bool wasRes, out bool linked);
            return res ?? "";
        }
    }
}
