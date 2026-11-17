// SuspensionMotion.cs - Motion study "Bump sweep" in the car assembly (Animation): one oscillating
// linear motor per upright (A_SPIN axis, along the layout's GROUND normal), the Drive_<corner> mates
// suppressed in the study only. The study starts at full droop; the motor moves A (1 - cos 2 pi f t), so
// the wheels rise to 2 s and are back at droop at 4 s. Calculated, then read along the timeline every
// 0.25 s: start and end at droop, one way at a time, left = right, the bump reached, and the front-right
// camber gain against suspension_geometry.m. An existing study is reused, never deleted (see below).
//   swh SuspensionMotion        cad\suspension\suspension_motion_report.txt
// Study types the installation offers are read with GetSupportedStudyTypes and
// written to the report. Animation needs no add-in; Basic Motion and Motion
// Analysis would take forces and motors, which a kinematic sweep does not need.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using SolidWorks.Interop.swmotionstudy;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class SuspensionMotion
    {
        const string STUDY = "Bump sweep";

        public static int Run(string[] args)
        {
            if (!File.Exists(AssemblyPath)) throw new StepStoppedException("Missing " + AssemblyPath);
            var par = ReadParams(P("params", "car_params.txt"));
            double bump = par.ContainsKey("wheel_travel_bump") ? par["wheel_travel_bump"] : 30;
            double droop = par.ContainsKey("wheel_travel_droop") ? par["wheel_travel_droop"] : 30;
            double h0 = par["tyre_rolling_radius"];
            var rep = new Report();
            var sb = new StringBuilder();
            var am = Open(AssemblyPath);
            var asm = (AssemblyDoc)am;
            var comps = (asm.GetComponents(true) as object[] ?? new object[0]).OfType<Component2>().ToList();
            var drv = BuildSuspension.Corners.ToDictionary(cn => cn, cn => FindFeatureDeep(am, "Drive_" + cn));
            if (drv.Values.Any(v => v == null)) throw new StepStoppedException("no Drive_<corner> mates (run SuspensionAssembly)");
            var up = BuildSuspension.Corners.ToDictionary(cn => cn, cn => comps.FirstOrDefault(c =>
                string.Equals(c.GetPathName(), BuildSuspension.PartPath(cn, "upright"), StringComparison.OrdinalIgnoreCase)));
            var corner = BuildSuspension.Corners.ToDictionary(cn => cn, cn => BuildSuspension.MakeCorner(par, cn));

            var msm = am.Extension.GetMotionStudyManager() as MotionStudyManager;
            if (msm == null) throw new StepStoppedException("GetMotionStudyManager returned nothing");
            // (GetMotionStudyNames crashed SolidWorks 2026 SP2.1 over COM, 2026-11-17: count and look up by name instead)
            rep.Info("motion studies before: " + msm.GetMotionStudyCount());
            // An existing study is reused, never deleted and made again: once a motion study has been deleted from an
            // assembly, CreateFeature refuses every motor in that assembly (also after save, close and reopen;
            // seen 2026-11-17). In an assembly built fresh by the rebuild they are taken.
            var st = msm.GetMotionStudy(STUDY) as MotionStudy;
            bool reuse = st != null;
            var motorsIn = new Func<int>(() => ((st?.GetMotionFeatures() as object[]) ?? new object[0]).OfType<Feature>()
                .Count(f => f.Name.StartsWith("Motor_") || (f.GetTypeName2() ?? "").IndexOf("Motor", StringComparison.OrdinalIgnoreCase) >= 0));
            if (reuse) rep.Info("'" + STUDY + "' is already in the assembly with " + motorsIn() + " motors: reused and calculated again");
            // the study starts at full droop: an oscillating motor in an Animation study moves as A (1 - cos 2 pi f t),
            // from 0 to 2A and back (seen 2026-11-17), so from droop it reaches full bump at 2 s and is back at droop
            // at 4 s. The motor's displacement is not the wheel centre's (A = 30 mm moves the front wheel centres about
            // 53 mm, the rear 44 with the 2026-11-17 hardpoints; cause not found, see below): the bump reached is reported.
            // The model is put at droop before the study is made (its start state).
            var ampOf = BuildSuspension.Corners.ToDictionary(cn => cn, cn => (bump + droop) / 2);
            if (!reuse)
            {
                foreach (var cn in BuildSuspension.Corners) BuildSuspension.SetDistance(drv[cn], h0 - droop);
                am.EditRebuild3();
                st = msm.CreateMotionStudy() as MotionStudy;
                if (st == null) throw new StepStoppedException("CreateMotionStudy returned nothing");
                st.Name = STUDY;
            }
            int sup = 0; st.GetSupportedStudyTypes(out sup);
            var kinds = new List<string>();
            foreach (swMotionStudyType_e k in Enum.GetValues(typeof(swMotionStudyType_e))) if ((sup & (int)k) != 0) kinds.Add(k.ToString());
            rep.Info("study types this installation offers (GetSupportedStudyTypes = " + sup + "): " + string.Join(", ", kinds));
            if (!reuse) st.StudyType = (int)swMotionStudyType_e.swMotionStudyTypeAssembly;    // Animation
            st.Activate();
            if (!reuse) st.SetDuration(4.0);
            rep.Note(st.IsActive && st.StudyType == (int)swMotionStudyType_e.swMotionStudyTypeAssembly,
                     "study '" + st.Name + "' " + (reuse ? "found" : "made") + ", type Animation, active " + st.IsActive + ", duration " + F(st.GetDuration(), "0.0") + " s");

            // drive: one linear motor per upright, oscillating +/- the travel at 0.25 Hz (bump at 1 s, droop at 3 s),
            // along the layout's GROUND normal, relative to the layout. The Drive_<corner> distance mates hold the
            // wheel height in the model, so they are suppressed in this study only.
            // (Keys on the Drive mates' distances, set with SetTime + SetSystemValue3 + EditRebuild3, do not become
            // timeline keys through the API: tried first on 2026-11-17, the wheels stayed at 222 mm all the way.)
            double amp = (bump + droop) / 2, freq = 0.25;
            var layout = comps.FirstOrDefault(c => string.Equals(c.GetPathName(), LayoutPath, StringComparison.OrdinalIgnoreCase));
            var ground = layout?.FeatureByName("GROUND") as Feature;
            if (layout == null || ground == null) throw new StepStoppedException("no master_layout component / GROUND plane");
            int nMot = 0; var motErr = new List<string>();
            var motorFeat = new Dictionary<string, Feature>();
            string used = null, typeUsed = null;
            var typeErr = new List<string>();
            if (reuse)
            {
                nMot = motorsIn();
                foreach (var f in ((st.GetMotionFeatures() as object[]) ?? new object[0]).OfType<Feature>())
                    foreach (var cn in BuildSuspension.Corners) if (f.Name == "Motor_" + cn) motorFeat[cn] = f;
            }
            else
            {
            int nSup = 0;
            foreach (var cn in BuildSuspension.Corners)
            {
                am.ClearSelection2(true);
                if (drv[cn].Select2(false, 0) && am.EditSuppress2()) nSup++;
            }
            am.ClearSelection2(true);
            rep.Note(nSup == 4, "Drive mates suppressed in the study: " + nSup + " of 4");
            // motors through the API: tried in the Animation study first, then Basic Motion, then Motion Analysis
            foreach (var stype in new[] { swMotionStudyType_e.swMotionStudyTypeAssembly, swMotionStudyType_e.swMotionStudyTypePhysicalSimulation, swMotionStudyType_e.swMotionStudyTypeCosmosMotion })
            {
            if ((sup & (int)stype) == 0) continue;
            st.StudyType = (int)stype;
            if (st.StudyType != (int)stype) { typeErr.Add(stype + ": StudyType did not change"); continue; }
            nMot = 0; motErr.Clear();
            foreach (var cn in BuildSuspension.Corners)
            {
                // the motor's location and direction: tried in order, the first combination SolidWorks takes is kept
                // (an axis feature, then faces and edges of the upright's bodies, raw and through GetCorresponding;
                // direction the layout's GROUND plane, then a planar face of the upright)
                var locs = new List<Tuple<string, object>>();
                // the wheel centre point first (2026-11-17: tried to make the wheel centre reach the full +30 mm; it
                // did not change anything: with the motor on P_WC the wheel centre still reaches +22.7 front, +14.2
                // rear of a 60 mm motor stroke from droop, exactly as on A_SPIN, so the motor's location is not what
                // limits the stroke)
                locs.Add(Tuple.Create("P_WC point", (object)up[cn].FeatureByName("P_WC")));
                locs.Add(Tuple.Create("A_SPIN axis", (object)up[cn].FeatureByName("A_SPIN")));
                object info;
                var bodies = (up[cn].GetBodies3((int)swBodyType_e.swSolidBody, out info) as object[] ?? new object[0]).OfType<Body2>().ToList();
                var faces = bodies.SelectMany(bd => (bd.GetFaces() as object[] ?? new object[0]).OfType<Face2>()).ToList();
                var edges = bodies.SelectMany(bd => (bd.GetEdges() as object[] ?? new object[0]).OfType<Edge>()).ToList();
                var cyl = faces.FirstOrDefault(f => ((Surface)f.GetSurface()).IsCylinder());
                var pla = faces.FirstOrDefault(f => ((Surface)f.GetSurface()).IsPlane());
                var circ = edges.FirstOrDefault(ed => ((Curve)ed.GetCurve()).IsCircle());
                if (cyl != null) { locs.Add(Tuple.Create("cylindrical face", (object)cyl)); locs.Add(Tuple.Create("cylindrical face (corresponding)", up[cn].GetCorresponding(cyl))); }
                if (circ != null) { locs.Add(Tuple.Create("circular edge", (object)circ)); locs.Add(Tuple.Create("circular edge (corresponding)", up[cn].GetCorresponding(circ))); }
                if (pla != null) locs.Add(Tuple.Create("planar face (corresponding)", up[cn].GetCorresponding(pla)));
                var dirs = new List<Tuple<string, object>> { Tuple.Create("GROUND plane", (object)ground) };
                if (pla != null) dirs.Add(Tuple.Create("planar face of the upright", up[cn].GetCorresponding(pla)));
                Feature mf = null;
                var order = used == null ? locs.SelectMany(l => dirs.Select(d => Tuple.Create(l, d))).ToList()
                                         : locs.SelectMany(l => dirs.Select(d => Tuple.Create(l, d))).OrderBy(x => x.Item1.Item1 + " / " + x.Item2.Item1 == used ? 0 : 1).ToList();
                var tried = new List<string>();
                foreach (var ld in order)
                {
                    if (ld.Item1.Item2 == null || ld.Item2.Item2 == null) continue;
                    var md = st.CreateDefinition((int)swFeatureNameID_e.swFmAEMLinearMotor) as SimulationMotorFeatureData;
                    if (md == null) { tried.Add("CreateDefinition(linear motor) returned nothing"); break; }
                    try
                    {
                        md.Location = ld.Item1.Item2;
                        md.DirectionReference = ld.Item2.Item2;
                        // (RelativeComponent = layout also tried: refused in every combination)
                        md.OscillatingMotor(ampOf[cn] / 1000, freq);     // A in m
                        mf = st.CreateFeature(md) as Feature;
                    }
                    catch (Exception ex) { tried.Add(ld.Item1.Item1 + " / " + ld.Item2.Item1 + ": " + ex.Message); continue; }
                    string combo = ld.Item1.Item1 + " / " + ld.Item2.Item1;
                    if (mf != null) { used = combo; break; }
                    tried.Add(combo + ": refused");
                }
                if (mf == null) motErr.Add(cn + ": no combination taken (" + string.Join("; ", tried) + ")");
                else { nMot++; Rename(mf, "Motor_" + cn); motorFeat[cn] = mf; }
            }
            if (nMot > 0) { typeUsed = stype.ToString(); break; }
            typeErr.Add(stype + ": every motor refused");
            }
            rep.Info("study type for the motors: " + (typeUsed ?? "none took a motor") + (typeErr.Count > 0 ? " (" + string.Join("; ", typeErr) + ")" : ""));
            if (used != null) rep.Info("motor location / direction SolidWorks took: " + used);
            }
            if (nMot == 0)
            {
                // SolidWorks 2026 SP2.1 Student, 2026-11-17: MotionStudy.CreateFeature returns nothing for a linear
                // motor in all three study types and every location / direction tried (see the INFO lines), and
                // keys on mate distances do not take (above). The study stays in the assembly, undriven; the
                // kinematic bump sweep is SuspensionCheck's (the same mates, stepped through the Drive mates).
                rep.Warn(false, "Motion study made but NOT driven: the API refused every linear motor (" + string.Join("; ", motErr.Take(1)) +
                         ") and does not take keys on mate distances; the bump sweep is in suspension_report.txt (SuspensionCheck). " +
                         "Motors are refused in an assembly that has had a motion study deleted: python tools/sw_run.py rebuild makes a fresh one");
                foreach (var cn in BuildSuspension.Corners) { am.ClearSelection2(true); drv[cn].Select2(false, 0); am.EditUnsuppress2(); }
                am.ClearSelection2(true);
                // an undriven study is left out of the saved assembly: its stored start state makes SolidWorks ask
                // "Update Initial Animation State" (a modal dialog) whenever the chassis changes, which stops a rebuild
                var main = msm.GetMotionStudy("Motion Study 1") as MotionStudy;
                main?.Activate();
                bool del = msm.DeleteMotionStudy(STUDY);
                rep.Note(del && msm.GetMotionStudy(STUDY) == null, "undriven study '" + STUDY + "' deleted again, so the saved assembly holds no study with a stale start state");
            }
            else
            {
            rep.Note(nMot == 4, "linear motors on the uprights: " + nMot + " of 4" + (reuse ? " (in the reused study)" : "") + ", oscillating " + F(amp, "0") + " mm at " + F(freq, "0.00") + " Hz" +
                     (motErr.Count > 0 ? "; " + string.Join("; ", motErr) : ""));
            Func<bool> calcStop = () =>
            {
                bool ok = st.Calculate();
                try { st.Stop(); } catch { }
                System.Threading.Thread.Sleep(1000);
                return ok;
            };
            Func<double, Dictionary<string, double>> zAt = tt =>
            {
                st.SetTime(tt);
                for (int k = 0; k < 20 && Math.Abs(st.GetTime() - tt) > 1e-4; k++) { System.Threading.Thread.Sleep(100); st.SetTime(tt); }
                Dictionary<string, double> prev = null, cur = null;
                int same = 0;
                for (int k = 0; k < 20 && same < 2; k++)
                {
                    am.GraphicsRedraw2();
                    System.Threading.Thread.Sleep(200);
                    cur = BuildSuspension.Corners.ToDictionary(cn => cn, cn => BuildSuspension.World(up[cn], corner[cn].P["wc"])[2]);
                    same = prev != null && BuildSuspension.Corners.All(cn => Math.Abs(cur[cn] - prev[cn]) < 0.01) ? same + 1 : 0;
                    prev = cur;
                }
                return cur;
            };
            bool calc = calcStop();
            rep.Info("Calculate returned " + calc);
            // (Calibrating each motor's A on the wheel-centre stroke was tried, 2026-11-17: ModifyDefinition takes the new
            // amplitude, but with A about 35 mm the animation stops short at the top on some corners (FR held at +28 mm
            // while its mirror FL reached +30), and the poses read after a jump in time were not reliable. One motor
            // amplitude, read once along the timeline in order, gives a smooth and repeatable sweep: kept.)

            // step through the timeline
            var rows = new List<Tuple<double, Dictionary<string, double>, double>>();
            for (double t = 0; t <= 4.0001; t += 0.25)
            {
                var z = zAt(t);
                var c = corner["FR"];
                var wc = BuildSuspension.World(up["FR"], c.P["wc"]); var ax = BuildSuspension.World(up["FR"], c.P["ax"]);
                rows.Add(Tuple.Create(t, z, -Math.Atan((ax[2] - wc[2]) / (ax[1] - wc[1])) * 180 / Math.PI));
            }
            // checks: every wheel starts at full droop and is back there at 4 s, rises to 2 s and falls after, left and
            // right alike; the bump it reaches is reported (the motor's displacement is not the wheel centre's)
            double worst = 0; bool mono = true;
            foreach (var r in rows.Where(r => Math.Abs(r.Item1) < 1e-6 || Math.Abs(r.Item1 - 4) < 1e-6))
                worst = Math.Max(worst, r.Item2.Values.Max(v => Math.Abs(v - (h0 - droop))));
            var top = rows.First(r => Math.Abs(r.Item1 - 2) < 1e-6).Item2;
            double lr = Math.Max(Math.Abs(top["FR"] - top["FL"]), Math.Abs(top["RR"] - top["RL"]));
            for (int i = 1; i < rows.Count; i++)
                foreach (var cn in BuildSuspension.Corners)
                {
                    double d = rows[i].Item2[cn] - rows[i - 1].Item2[cn];
                    if ((rows[i].Item1 <= 2 && d < -0.01) || (rows[i].Item1 > 2 && d > 0.01)) mono = false;
                }
            sb.Append("\nTimeline (wheel centre height above GROUND, mm; front right camber, deg)\n   t s     FR       FL       RR       RL    FR camber\n");
            var cambers = new List<Tuple<double, double>>();
            foreach (var r in rows)
            {
                cambers.Add(Tuple.Create(r.Item2["FR"] - h0, r.Item3));
                sb.Append("  " + F(r.Item1, "0.00").PadLeft(4) + "  " + string.Join(" ", BuildSuspension.Corners.Select(cn => F(r.Item2[cn], "0.0").PadLeft(8))) +
                          "  " + F(r.Item3, "0.000").PadLeft(8) + "\n");
            }
            rep.Note(worst < 0.5 && mono && lr < 0.5, "the study moves every wheel up from full droop (" + F(h0 - droop, "0") + " mm at 0 s) and back (4 s), " +
                     "one way at a time, left and right alike: start/end miss " + F(worst, "0.00") + " mm, left-right difference at the top " + F(lr, "0.00") + " mm" +
                     (mono ? "" : ", NOT monotonic (see the timeline below)"));
            double reachF = top["FR"] - h0, reachR = top["RR"] - h0;
            rep.Warn(Math.Min(reachF, reachR) >= bump - 0.5, "bump reached in the study: front +" + F(reachF, "0.0") + " mm, rear +" + F(reachR, "0.0") + " mm of +" + F(bump, "0") +
                     " (the motor's stroke is " + F(2 * amp, "0") + " mm from droop; the wheel centre falls short by the same amount with the motor on the axis or on the wheel-centre point, cause not found. The full -" +
                     F(droop, "0") + "..+" + F(bump, "0") + " sweep is SuspensionCheck's)");
            // camber against travel in the study: least-squares slope, as suspension_geometry.m and SuspensionCheck
            double gain = double.NaN;
            if (cambers.Count > 3)
            {
                double mx = cambers.Average(x => x.Item1), my = cambers.Average(x => x.Item2);
                double sxx = cambers.Sum(x => (x.Item1 - mx) * (x.Item1 - mx));
                if (sxx > 1) gain = cambers.Sum(x => (x.Item1 - mx) * (x.Item2 - my)) / sxx;
            }
            var mref = ReadLines(P("params", "car_params.txt")).FirstOrDefault(l => l.Contains("Results:") && l.Contains("camber gain"));
            double gRef = double.NaN;
            if (mref != null) { var mm = System.Text.RegularExpressions.Regex.Match(mref, @"camber gain F (-?[0-9.]+)"); if (mm.Success) gRef = Val(mm.Groups[1].Value); }
            rep.Note(!double.IsNaN(gain) && Math.Abs(gain - gRef) <= 0.002, "front camber gain in the study " + F(gain, "0.0000") + " deg/mm, suspension_geometry.m " + F(gRef, "0.0000") + " (agree within 0.002)");

            }

            // back to the model (the Model tab) and to static: the study keeps its own start state (full droop)
            if (nMot > 0) st.SetTime(0);         // (the undriven study is deleted above)
            bool toModel = false;
            try { toModel = msm.ActivateMotionStudy("Model"); } catch { }
            rep.Info("ActivateMotionStudy(\"Model\") returned " + toModel);
            foreach (var cn in BuildSuspension.Corners) BuildSuspension.SetDistance(drv[cn], h0);
            am.EditRebuild3();
            double off = BuildSuspension.Corners.Max(cn => Math.Abs(BuildSuspension.World(up[cn], corner[cn].P["wc"])[2] - h0));
            if (off > 0.01)
            {   // the keys went into the model itself: put the Drive mates back to static
                foreach (var cn in BuildSuspension.Corners) BuildSuspension.SetDistance(drv[cn], h0);
                am.EditRebuild3();
                off = BuildSuspension.Corners.Max(cn => Math.Abs(BuildSuspension.World(up[cn], corner[cn].P["wc"])[2] - h0));
            }
            rep.Note(off <= 0.01, "model back at static after the study: wheel centres within " + F(off, "0.000") + " mm of " + F(h0, "0") + " mm");
            int e = 0, wn = 0;
            bool saved = am.Save3((int)swSaveAsOptions_e.swSaveAsOptions_Silent, ref e, ref wn);
            rep.Note(saved, saved ? "saved " + AssemblyPath + (nMot > 0 ? " with the study" : "") : "NOT saved (error " + e + ")");
            string full = rep.Text("SuspensionMotion, " + AssemblyPath) + "\n" + sb;
            WriteReport(P("cad", "suspension", "suspension_motion_report.txt"), full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }
    }
}
