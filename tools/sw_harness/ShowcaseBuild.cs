// ShowcaseBuild.cs - stills for the car build-up film (python tools/sw_run.py showcase-build).
// Opens the assembly (the as-built car, CP), adds a ground plate (cad/showcase/ground.SLDPRT, made here if
// missing) WITHOUT saving the assembly, fixes one perspective three-quarter-front camera, then shows the car
// stage by stage and saves one PNG per stage to media/showcase/frames_build/ with a manifest
// (index, file, stage, caption). The frame tubes come in group by group, a few tubes per still: the
// chassis bodies are hidden in the chassis part (Body2.HideBody), which the assembly shows. Then the
// suspension inboard to outboard (lower and upper wishbones, uprights and hubs, tie rods and toe links,
// pushrods), the packaging envelopes (rockers and dampers, steering, brakes, motor and drive, batteries,
// electronics, seat, driver: space reservations, not designed parts), wheels, floor, sidepods, nose, and
// each wing after its supports (docs/buildup_audit.md).
// Nothing is saved: the assembly and the chassis are closed without saving by close-all afterwards.
// Report: media/showcase/frames_build/showcase_build_report.txt
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
    static class ShowcaseBuild
    {
        // frame tube groups in build order, with their caption
        static readonly (string group, string caption)[] FrameGroups = {
            ("bulkhead", "Frame: front bulkhead"),
            ("front", "Frame: front box and footwell"),
            ("sis", "Frame: side impact tubes"),
            ("hoop", "Frame: front and main hoops"),
            ("hoop_brace", "Frame: hoop braces"),
            ("sidepod", "Frame: sidepod battery structure"),
            ("rear", "Frame: rear box"),
        };
        const int CHUNKS = 3;     // stills per tube group

        public static int Run(string[] args)
        {
            var rep = new Report();
            string outDir = P("media", "showcase", "frames_build");
            Directory.CreateDirectory(outDir);
            foreach (var f in Directory.GetFiles(outDir, "*.png")) File.Delete(f);
            string groundPath = P("cad", "showcase", "ground.SLDPRT");
            // made fresh every run (a few seconds): its size sets the framing
            if (File.Exists(groundPath)) File.Delete(groundPath);
            MakeGround(groundPath, rep);

            var m = Open(AssemblyPath);
            var asm = (AssemblyDoc)m;
            var comps = (asm.GetComponents(true) as object[] ?? new object[0]).OfType<Component2>().ToList();
            rep.Info("assembly " + AssemblyPath + ": " + comps.Count + " top-level components");

            // ground plate at the assembly origin (car axes: z up, ground at z = 0). AddComponent5 needs the part
            // open in the session (refused otherwise, 2026-11-25), then the assembly active again.
            Component2 g = null;
            for (int attempt = 1; attempt <= 3 && g == null; attempt++)
            {
                int ge = 0, gw = 0, ae = 0;
                var gm = App.OpenDoc6(groundPath, (int)swDocumentTypes_e.swDocPART, (int)swOpenDocOptions_e.swOpenDocOptions_Silent, "", ref ge, ref gw);
                if (attempt == 1 && gm != null)
                {
                    var pb = ((PartDoc)gm).GetPartBox(true) as double[];
                    rep.Note(pb != null && Math.Abs(pb[5]) < 1e-4 && pb[2] < 0, "ground plate " + groundPath + ": z " + (pb == null ? "?" : F(pb[2] * 1000, "0") + " to " + F(pb[5] * 1000, "0")) + " mm (top face at 0)");
                }
                App.ActivateDoc3(m.GetTitle(), false, (int)swRebuildOnActivation_e.swDontRebuildActiveDoc, ref ae);
                g = gm == null ? null : asm.AddComponent5(groundPath, (int)swAddComponentConfigOptions_e.swAddComponentConfigOptions_CurrentSelectedConfig, "", false, "", 0, 0, 0);
                if (g == null) { Log("ground plate: attempt " + attempt + " refused (OpenDoc6 " + (gm == null ? "error " + ge : "ok") + ")"); System.Threading.Thread.Sleep(1000); }
            }
            if (g == null) throw new StepStoppedException("the ground plate could not be added to the assembly");
            var mu = (MathUtility)App.GetMathUtility();
            g.Transform2 = (MathTransform)mu.CreateTransform(new double[] { 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0 });
            var gb = g.GetBox(false, false) as double[];
            rep.Note(gb != null && Math.Abs(gb[5] * 1000) < 0.5, "ground plate added at the origin, top face at z " + (gb == null ? "?" : F(gb[5] * 1000, "0.0")) + " mm");

            // tyres must stand on it: lowest point of the tyres
            var tyres = comps.Where(c => c.Name2.StartsWith("tyre_", StringComparison.OrdinalIgnoreCase)).ToList();
            double zt = tyres.Select(c => c.GetBox(false, false) as double[]).Where(b => b != null).Select(b => b[2] * 1000).DefaultIfEmpty(double.NaN).Min();
            rep.Note(Math.Abs(zt) < 5, "tyres: " + tyres.Count + " components, lowest point z " + F(zt, "0.0") + " mm (on the ground within 5 mm)");

            Func<string, List<Component2>> pick = pre => comps.Where(c => c.Name2.StartsWith(pre, StringComparison.OrdinalIgnoreCase)).ToList();
            var layout = pick("master_layout");
            var chassisC = pick("chassis").FirstOrDefault();
            if (chassisC == null) throw new StepStoppedException("no chassis component in the assembly");
            string[] corners = { "FL_", "FR_", "RL_", "RR_" };
            Func<string, List<Component2>> corner = suf => comps.Where(c => corners.Any(k => c.Name2.StartsWith(k)) && c.Name2.Contains(suf)).ToList();
            var lwb = corner("_lwb"); var uwb = corner("_uwb"); var tie = corner("_tie"); var push = corner("_push");
            var arms = lwb.Concat(uwb).Concat(tie).Concat(push).ToList();
            var uprights = comps.Where(c => corners.Any(k => c.Name2.StartsWith(k)) && new[] { "_upright", "_hub" }.Any(s => c.Name2.Contains(s))).ToList();
            var wheels = pick("rim_").Concat(pick("tyre_")).ToList();
            var floor = pick("floor_diffuser");
            var sidepods = pick("sidepod_");
            var nose = pick("nose");
            // wing supports (2026-11-28) are their own stage, before the wing they carry
            var fws = pick("fw_support");
            var rws = pick("rw_support");
            var fw = pick("fw_").Except(fws).ToList();
            var rw = pick("rw_").Except(rws).ToList();
            // packaging envelopes (env_*, 2026-11-28): one stage per system
            var rkd = pick("env_rocker_").Concat(pick("env_damper_")).ToList();
            var steer = pick("env_steering_");
            var brakes = pick("env_brake_");
            var drive = pick("env_motor").Concat(pick("env_diff")).Concat(pick("env_chain")).Concat(pick("env_halfshaft_")).ToList();
            var batt = pick("env_battery_");
            var elec = pick("env_inverter").Concat(pick("env_lv_electronics")).ToList();
            var seat = pick("env_seat");
            var driver = pick("env_driver_");
            var envs = rkd.Concat(steer).Concat(brakes).Concat(drive).Concat(batt).Concat(elec).Concat(seat).Concat(driver).ToList();
            var envAll = pick("env_");
            var known = new HashSet<Component2>(layout.Concat(new[] { chassisC, g }).Concat(arms).Concat(uprights).Concat(wheels).Concat(floor).Concat(sidepods).Concat(nose).Concat(fw).Concat(rw).Concat(fws).Concat(rws).Concat(envs));
            var other = comps.Where(c => !known.Contains(c)).ToList();
            rep.Note(lwb.Count == 4 && uwb.Count == 4 && tie.Count == 4 && push.Count == 4 && uprights.Count == 8 && wheels.Count == 8 && floor.Count == 1 &&
                     sidepods.Count == 2 && nose.Count == 1 && fw.Count == 5 && rw.Count == 5 && fws.Count == 2 && rws.Count == 2,
                "components: lower wishbones " + lwb.Count + " (4), upper wishbones " + uwb.Count + " (4), tie rods and toe links " + tie.Count + " (4), pushrods " + push.Count +
                " (4), uprights and hubs " + uprights.Count + " (8), rims and tyres " + wheels.Count + " (8), floor " + floor.Count + ", sidepods " + sidepods.Count +
                ", nose " + nose.Count + ", front wing " + fw.Count + " (5), front supports " + fws.Count + " (2), rear wing " + rw.Count + " (5), rear supports " + rws.Count + " (2)");
            rep.Note(rkd.Count == 8 && steer.Count == 3 && brakes.Count == 4 && drive.Count == 5 && batt.Count == 2 && elec.Count == 2 && seat.Count == 1 &&
                     driver.Count == 3 && envs.Count == envAll.Count,
                "packaging envelopes: rockers and dampers " + rkd.Count + " (8), steering " + steer.Count + " (3), brakes " + brakes.Count + " (4), motor and drive " +
                drive.Count + " (5), batteries " + batt.Count + " (2), electronics " + elec.Count + " (2), seat " + seat.Count + " (1), driver " + driver.Count +
                " (3); every env_ component in a stage: " + envs.Count + " of " + envAll.Count);
            if (other.Count > 0) rep.Info("other components (hidden throughout): " + string.Join(", ", other.Select(c => c.Name2)));

            // chassis tube bodies, matched to frame_tubes.csv and grouped
            var part = chassisC.GetModelDoc2() as PartDoc;
            if (part == null) throw new StepStoppedException("the chassis component has no part document loaded");
            var fr = ReadFrame();
            var match = TrimTubes.MatchBodies(TrimTubes.Snap(part), fr, out string unmatched);
            rep.Note(match.Count == fr.Tubes.Count, "chassis bodies matched to frame_tubes.csv: " + match.Count + " of " + fr.Tubes.Count + (unmatched == "" ? "" : " (" + unmatched + ")"));
            var groupOf = fr.TubeRows.Where(r => r.Length >= 4).ToDictionary(r => r[0], r => r[3]);
            var allBodies = Bodies(part);

            // the scene: plain white, shaded with edges, no sketches or planes, perspective
            int pApp = (int)swUserPreferenceIntegerValue_e.swColorsBackgroundAppearance;
            int pCol = (int)swUserPreferenceIntegerValue_e.swSystemColorsViewportBackground;
            int pGrad = (int)swUserPreferenceToggle_e.swColorsGradientPartBackground;
            int oldApp = App.GetUserPreferenceIntegerValue(pApp), oldCol = App.GetUserPreferenceIntegerValue(pCol);
            bool oldGrad = App.GetUserPreferenceToggle(pGrad);
            int pHide = (int)swUserPreferenceToggle_e.swViewDisplayHideAllTypes;
            // picture export: screen capture of the view as it stands. The default (print capture, scale to fit)
            // zoomed every still out to the whole ground plate (2026-11-25); the camera must stay fixed.
            int pCap = (int)swUserPreferenceIntegerValue_e.swTiffScreenOrPrintCapture;
            int oldCap = App.GetUserPreferenceIntegerValue(pCap);
            var manifest = new StringBuilder("index,file,stage,caption\n");
            int idx = 0;
            try
            {
                App.SetUserPreferenceIntegerValue(pApp, (int)swColorsBackgroundAppearance_e.swColorsBackgroundAppearance_Plain);
                App.SetUserPreferenceIntegerValue(pCol, 0xFFFFFF);
                App.SetUserPreferenceToggle(pGrad, false);
                App.SetUserPreferenceIntegerValue(pCap, 0);
                m.SetUserPreferenceToggle(pHide, true);
                // film colours, on the components in this session only (the assembly is not saved)
                Action<IEnumerable<Component2>, double, double, double> paint = (cs, rr, gg2, bb) =>
                    { foreach (var c in cs) c.MaterialPropertyValues = new double[] { rr, gg2, bb, 1, 1, 0.4, 0.3, 0, 0 }; };
                paint(new[] { g }, 0.93, 0.93, 0.94);
                paint(new[] { chassisC }, 0.13, 0.32, 0.58);
                // links lighter than before (dark grey links vanished against the blue frame, 2026-11-28 audit),
                // pushrods in amber so they read as their own stage
                paint(lwb.Concat(uwb).Concat(tie), 0.62, 0.63, 0.66);
                paint(push, 0.93, 0.62, 0.10);
                paint(uprights, 0.28, 0.28, 0.30);
                paint(pick("rim_"), 0.78, 0.78, 0.80);
                paint(pick("tyre_"), 0.13, 0.13, 0.13);
                paint(floor, 0.20, 0.20, 0.22);
                paint(sidepods.Concat(nose), 0.78, 0.16, 0.12);
                paint(fw.Concat(rw), 0.17, 0.17, 0.19);
                paint(fws.Concat(rws), 0.36, 0.38, 0.42);   // carbon supports, a shade lighter than the wings so they show
                // envelopes: plain system colours (they are space reservations, the captions say so)
                paint(rkd, 0.95, 0.84, 0.25);
                paint(steer, 0.55, 0.56, 0.60);
                paint(brakes, 0.45, 0.45, 0.48);
                paint(drive, 0.30, 0.55, 0.40);
                paint(batt, 0.10, 0.60, 0.62);
                paint(elec, 0.48, 0.32, 0.66);
                paint(seat, 0.10, 0.10, 0.11);
                paint(driver, 0.86, 0.86, 0.90);
                foreach (var c in layout.Concat(other)) c.Visible = (int)swComponentVisibilityState_e.swComponentHidden;
                var mv = (ModelView)m.ActiveView;
                mv.DisplayMode = (int)swViewDisplayMode_e.swViewDisplayMode_ShadedWithEdges;

                // camera: three-quarter front, ahead of the front axle (-x) on the same side as the standard iso
                // picture (-y; +y is the car's right, the _R nodes), 18 deg up
                double az = 38 * Math.PI / 180, el = 18 * Math.PI / 180;
                double[] n = { -Math.Cos(el) * Math.Cos(az), -Math.Cos(el) * Math.Sin(az), Math.Sin(el) };   // toward the viewer
                double[] r = Norm(new[] { -n[1], n[0], 0.0 });                                                 // z x n: screen right, level
                double[] u = { n[1] * r[2] - n[2] * r[1], n[2] * r[0] - n[0] * r[2], n[0] * r[1] - n[1] * r[0] };   // n x r: screen up
                var d = new double[] { r[0], u[0], n[0], r[1], u[1], n[1], r[2], u[2], n[2], 0, 0, 0, 1, 0, 0, 0 };
                mv.Orientation3 = (MathTransform)mu.CreateTransform(d);
                if (!mv.HasPerspective()) mv.AddPerspective();
                // fit to the whole car on its ground plate, a little wider; that camera (orientation, scale,
                // translation) is recorded and put back before every still. Showing the plate after a fit to the
                // car alone re-framed the view to the plate and cut the rear wing off (2026-11-25).
                m.ViewZoomtofit2();
                mv.Scale2 = mv.Scale2 * 0.95;
                m.GraphicsRedraw2();
                cam = (d, mv.Scale2, (MathVector)mv.Translation3);
                var back = (double[])((MathTransform)mv.Orientation3).ArrayData;
                rep.Note(Enumerable.Range(0, 9).All(i => Math.Abs(back[i] - d[i]) < 1e-3), "camera: three-quarter front, azimuth 38 deg, elevation 18 deg, perspective " + mv.HasPerspective());
                // the fit still: whole car, no ground (the film assembler crops every still to this one's box)
                Shot(m, outDir, ref idx, "fit", "", manifest, rep);

                // empty scene
                Show(comps, false, layout); foreach (var b in allBodies) b.HideBody(true);
                chassisC.Visible = (int)swComponentVisibilityState_e.swComponentVisible;   // its bodies are all hidden
                m.GraphicsRedraw2();
                Shot(m, outDir, ref idx, "empty", "Empty scene", manifest, rep);

                // frame, group by group, front to back inside a group
                foreach (var (grp, cap) in FrameGroups)
                {
                    var tubes = match.Where(kv => groupOf.TryGetValue(kv.Key, out var gg) && gg == grp)
                                     .OrderBy(kv => fr.Tubes[kv.Key][0] + fr.Tubes[kv.Key][3]).ToList();
                    if (tubes.Count == 0) { rep.Note(false, "frame group " + grp + ": no tubes"); continue; }
                    for (int k = 1; k <= CHUNKS; k++)
                    {
                        int upTo = (int)Math.Ceiling(tubes.Count * k / (double)CHUNKS);
                        foreach (var kv in tubes.Take(upTo)) kv.Value.HideBody(false);
                        m.GraphicsRedraw2();
                        Shot(m, outDir, ref idx, "frame_" + grp + "_" + k, cap, manifest, rep);
                    }
                }
                rep.Note(allBodies.All(b => b.Visible), "every chassis body shown after the frame stages (" + allBodies.Length + ")");

                var stages = new (List<Component2> cs, string stage, string cap)[] {
                    // inboard to outboard: wishbones on the frame pickups, uprights and hubs on the wishbones,
                    // tie rods (steering) and toe links to the uprights, pushrods, then the wheels
                    (lwb, "lower_wishbones", "Suspension: lower wishbones"),
                    (uwb, "upper_wishbones", "Suspension: upper wishbones"),
                    (uprights, "uprights", "Suspension: uprights and hubs"),
                    (tie, "tie_rods", "Steering tie rods and rear toe links"),
                    (push, "pushrods", "Suspension: pushrods"),
                    // packaging envelopes, inboard systems first (each on what carries or drives it)
                    (rkd, "rockers_dampers", "Rockers and spring/dampers (envelopes)"),
                    (steer, "steering", "Steering rack, column and wheel (envelopes)"),
                    (brakes, "brakes", "Brake discs and calipers (envelopes)"),
                    (drive, "drive", "Motor, chain, diff and halfshafts (envelopes)"),
                    (batt, "battery", "Battery packs in the sidepod structure (envelopes)"),
                    (elec, "electronics", "Inverter and LV electronics (envelopes)"),
                    (seat, "seat", "Seat (envelope)"),
                    (driver, "driver", "Driver: legs, torso, helmet (envelope)"),
                    (wheels, "wheels", "Rims and tyres"),
                    (floor, "floor", "Floor and diffuser"),
                    (sidepods, "sidepods", "Sidepods"),
                    (nose, "nose", "Nose"),
                    (fws, "front_supports", "Front wing supports (lens, J)"),
                    (fw, "front_wing", "Front wing"),
                    (rws, "rear_supports", "Rear wing supports (lens, F)"),
                    (rw, "rear_wing", "Rear wing: the final car (CP with F and J supports)"),
                };
                foreach (var (cs, stage, cap) in stages)
                {
                    foreach (var c in cs) c.Visible = (int)swComponentVisibilityState_e.swComponentVisible;
                    m.GraphicsRedraw2();
                    Shot(m, outDir, ref idx, stage, cap, manifest, rep);
                }
            }
            finally
            {
                App.SetUserPreferenceIntegerValue(pApp, oldApp);
                App.SetUserPreferenceIntegerValue(pCol, oldCol);
                App.SetUserPreferenceToggle(pGrad, oldGrad);
                App.SetUserPreferenceIntegerValue(pCap, oldCap);
            }
            File.WriteAllText(Path.Combine(outDir, "manifest.csv"), manifest.ToString());
            rep.Note(idx >= 44, "stills saved: " + idx + " (manifest.csv); the assembly and chassis are NOT saved (close-all closes them without saving)");
            bool restored = App.GetUserPreferenceIntegerValue(pApp) == oldApp && App.GetUserPreferenceIntegerValue(pCol) == oldCol && App.GetUserPreferenceIntegerValue(pCap) == oldCap;
            rep.Note(restored, "background and picture-capture settings restored to the user's own (capture was " + oldCap + ")");
            string full = rep.Text("ShowcaseBuild, " + AssemblyPath);
            WriteReport(Path.Combine(outDir, "showcase_build_report.txt"), full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }

        static void Show(List<Component2> comps, bool on, List<Component2> keepHidden)
        {
            foreach (var c in comps)
                c.Visible = (int)(on && !keepHidden.Contains(c) ? swComponentVisibilityState_e.swComponentVisible : swComponentVisibilityState_e.swComponentHidden);
        }

        static double[] Norm(double[] v) { double l = Math.Sqrt(v.Sum(x => x * x)); return v.Select(x => x / l).ToArray(); }

        static (double[] orient, double scale, MathVector trans) cam;

        static void Shot(ModelDoc2 m, string dir, ref int idx, string stage, string cap, StringBuilder man, Report rep)
        {
            if (cam.orient != null)
            {
                var mv = (ModelView)m.ActiveView;
                var mu = (MathUtility)App.GetMathUtility();
                mv.Orientation3 = (MathTransform)mu.CreateTransform(cam.orient);
                mv.Scale2 = cam.scale;
                mv.Translation3 = cam.trans;
                m.GraphicsRedraw2();
                if (Math.Abs(mv.Scale2 - cam.scale) > 1e-9 * Math.Max(1, cam.scale)) rep.Note(false, "still " + idx + ": the camera scale did not take");
            }
            string name = idx.ToString("00") + "_" + stage + ".png";
            string file = Path.Combine(dir, name);
            DateTime t0 = DateTime.Now.AddSeconds(-1);
            int e = 0, w = 0;
            bool ok = m.Extension.SaveAs3(file, (int)swSaveAsVersion_e.swSaveAsCurrentVersion, (int)swSaveAsOptions_e.swSaveAsOptions_Silent, null, null, ref e, ref w);
            var fi = new FileInfo(file);
            bool fresh = ok && fi.Exists && fi.LastWriteTime >= t0 && fi.Length > 5000;
            if (!fresh) rep.Note(false, name + ": " + (ok ? "no fresh file" : "SaveAs3 refused (error " + e + ")"));
            man.Append(idx).Append(',').Append(name).Append(',').Append(stage).Append(",\"").Append(cap.Replace("\"", "'")).Append("\"\n");
            idx++;
        }

        /// A 4.4 x 2.7 m light grey plate (the car with its wings is about 3.0 x 1.6 m), 10 mm thick, top face on the Front plane (z = 0 in car axes, the ground).
        static void MakeGround(string path, Report rep)
        {
            var m = NewPartAt(path);
            bool sel = m.Extension.SelectByID2("Front Plane", "PLANE", 0, 0, 0, false, 0, null, 0);
            if (!sel) throw new StepStoppedException("ground plate: Front Plane not found in the default part template");
            m.SketchManager.InsertSketch(true);
            m.SketchManager.CreateCornerRectangle(-1.4, -1.35, 0, 3.0, 1.35, 0);
            m.SketchManager.InsertSketch(true);
            var fm = m.FeatureManager;
            // blind 10 mm, direction reversed so the plate lies below z = 0
            var f = fm.FeatureExtrusion2(true, false, true, (int)swEndConditions_e.swEndCondBlind, 0, 0.010, 0, false, false, false, false,
                                         0, 0, false, false, false, false, true, true, true, 0, 0, false);
            if (f == null) throw new StepStoppedException("ground plate: extrusion refused (" + CreateErrors(fm) + ")");
            var box = ((PartDoc)m).GetPartBox(true) as double[];
            if (box != null && box[5] > 1e-4)
            {
                // came out above z = 0: flip it
                DeleteLast(m, f);
                m.Extension.SelectByID2("Sketch1", "SKETCH", 0, 0, 0, false, 0, null, 0);
                f = fm.FeatureExtrusion2(true, false, false, (int)swEndConditions_e.swEndCondBlind, 0, 0.010, 0, false, false, false, false,
                                         0, 0, false, false, false, false, true, true, true, 0, 0, false);
                box = ((PartDoc)m).GetPartBox(true) as double[];
            }
            m.MaterialPropertyValues = new double[] { 0.86, 0.87, 0.88, 1, 1, 0.3, 0.3, 0, 0 };
            bool saved = Save(m, out int errs);
            rep.Note(saved && box != null && Math.Abs(box[5]) < 1e-4, "ground plate made: " + path + ", z " + (box == null ? "?" : F(box[2] * 1000, "0") + " to " + F(box[5] * 1000, "0")) + " mm" + (saved ? "" : ", NOT saved (" + errs + ")"));
            App.CloseDoc(m.GetTitle());
        }

        static void DeleteLast(ModelDoc2 m, Feature f)
        {
            m.ClearSelection2(true);
            f.Select2(false, 0);
            m.Extension.DeleteSelection2((int)swDeleteSelectionOptions_e.swDelete_Absorbed);
        }
    }
}
