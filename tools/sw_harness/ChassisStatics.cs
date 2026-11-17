// ChassisStatics.cs - SOLIDWORKS Simulation static studies on the chassis weldment (beam mesh).
//   swh ChassisStatics        studies "Torsion", "Braking", "Cornering" in cad\chassis\chassis.SLDPRT,
//                             report sim\stress\chassis_statics_report.txt
//
// The frame's structural members are beams; Simulation finds the joints at the tube ends.
// Loads go in at the frame nodes that carry the suspension pickups (the wishbone inboard
// points sit exactly on frame nodes; the tie rod / toe link and the pushrod rocker go to the
// nearest node).
//   Torsion    free-free with inertia relief, a balanced pair of couples: at the front +F up
//              on the left wishbone pickups and -F on the right (F/4 at each of the four nodes
//              per side), at the rear the opposite couple of the same torque. Stiffness =
//              torque / (front twist - rear twist), each twist from the vertical displacements
//              of that axle's pickup nodes. (No fixtures: AddRestraint takes no beam joint
//              through the API here, see below.)
// Joints: the API hands out no joint objects (CWJoints has no getter), and AddForce2 with
// swsSelectionBeamEndJoints refuses the node's sketch point (error 18), a tube vertex (11)
// and the tube body (18); AddRestraint refuses all three (1, 16, 1). AddForce2 with
// swsSelectionFaceEdgeVertexPoint on the node's sketch point is taken (swh ChassisStatics probe).
// (SelectByID2("", "SIMULATION", node) hung SolidWorks for 30 min: not used.)
//   Braking,   the wheel forces of sim\stress\load_cases.csv at the contact patches,
//   Cornering  turned into link forces with the upright's six-link statics (two legs per
//              wishbone, tie rod, pushrod: six two-force members, six equations), applied to
//              the frame at the pickups; free-free with inertia relief (the car decelerates /
//              turns, nothing is held).
// load_cases.csv axes: Fx forward, Fy towards the inside of the turn (the left wheels: the
// right ones carry more), Fz up; car axes are x rearward, y right, z up: x = -Fx, y = -Fy.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using SolidWorks.Interop.cosworks;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class ChassisStatics
    {
        const double YIELD_MPA = 435;    // AISI 4130 normalised (the frame material in car_params / BuildTubes)
        static Report rep;
        static bool ApiLimit;
        static StringBuilder sb;

        public static int Run(string[] args)
        {
            rep = new Report(); sb = new StringBuilder(); ApiLimit = false;
            string reportFile = P("sim", "stress", "chassis_statics_report.txt");
            var fr = ReadFrame();
            var par = ReadParams(P("params", "car_params.txt"));
            string casesFile = P("sim", "stress", "load_cases.csv");
            if (!File.Exists(casesFile)) throw new StepStoppedException("Missing " + casesFile + " (matlab load_cases)");
            var cases = Csv(casesFile).Where(r => r.Length >= 5 && r[0] != "case").ToList();

            // 1. the Simulation add-in
            string swDir = Path.GetDirectoryName(App.GetExecutablePath());
            string dll = Path.Combine(swDir, "Simulation", "cosworks.dll");
            int lr = File.Exists(dll) ? App.LoadAddIn(dll) : -99;
            var cb = App.GetAddInObject("SldWorks.Simulation") as CwAddincallback;
            var cw = cb?.CosmosWorks;
            rep.Note(cw != null, "Simulation add-in: " + dll + (File.Exists(dll) ? "" : " NOT FOUND") + ", LoadAddIn returned " + lr +
                     (cw != null ? ", CosmosWorks object version " + cw.VersionNumber : ", GetAddInObject(\"SldWorks.Simulation\") gave no CosmosWorks object"));
            if (cw == null) return Finish(reportFile);

            var m = Open(ChassisPath);
            var cwDoc = cw.ActiveDoc as CWModelDoc;
            if (cwDoc == null) { rep.Note(false, "CosmosWorks.ActiveDoc is empty with the chassis open"); return Finish(reportFile); }
            var sm = cwDoc.StudyManager as CWStudyManager;

            // frame node -> a joint entity (the node's point in the FRAME_<group> member sketches)
            var nodePt = NodePoints(m, fr);
            rep.Note(nodePt.Count == fr.Nodes.Count, "frame nodes found as sketch points: " + nodePt.Count + " of " + fr.Nodes.Count);
            if (args.Contains("probe")) { Probe(sm, m, fr, nodePt); return Finish(P("sim", "stress", "chassis_statics_probe.txt")); }

            // pickups -> frame nodes, per corner
            var corners = BuildSuspension.Corners.ToDictionary(cn => cn, cn => BuildSuspension.MakeCorner(par, cn));
            Func<double[], string> nearest = q => fr.Nodes.OrderBy(kv => Dist3(kv.Value[0], kv.Value[1], kv.Value[2], q[0], q[1], q[2])).First().Key;
            string[] links = { "lwb_in_fwd", "lwb_in_aft", "uwb_in_fwd", "uwb_in_aft", "tie_in", "pushrod_in" };
            var pickNode = corners.ToDictionary(kv => kv.Key, kv => links.ToDictionary(l => l, l => nearest(kv.Value.P[l])));
            sb.Append("\nPickup -> frame node (distance)\n");
            foreach (var cn in new[] { "FR", "RR" })
                foreach (var l in links)
                {
                    var q = corners[cn].P[l]; var n = fr.Nodes[pickNode[cn][l]];
                    sb.Append("  " + cn + " " + l.PadRight(11) + " -> " + pickNode[cn][l].PadRight(8) + " " + F(Dist3(n[0], n[1], n[2], q[0], q[1], q[2]), "0.0") + " mm\n");
                }

            // 2. torsion
            double Ft = 1000;
            string[] wb = { "lwb_in_fwd", "lwb_in_aft", "uwb_in_fwd", "uwb_in_aft" };
            Func<string, List<string>> nodesOf = cn => wb.Select(l => pickNode[cn][l]).ToList();
            Func<string, double> yOf = cn => nodesOf(cn).Average(n => fr.Nodes[n][1]);
            double spanF = Math.Abs(yOf("FR") - yOf("FL")), spanR = Math.Abs(yOf("RR") - yOf("RL"));
            double torque = Ft * spanF / 1000;                                               // Nm
            double Fr = Ft * spanF / spanR;                                                  // rear couple, same torque
            var loadsT = new Dictionary<string, double[]>();
            foreach (var cn in new[] { "FL", "FR" }) foreach (var n in nodesOf(cn)) Add(loadsT, n, new[] { 0, 0, (cn == "FL" ? 1 : -1) * Ft / 4 });
            foreach (var cn in new[] { "RL", "RR" }) foreach (var n in nodesOf(cn)) Add(loadsT, n, new[] { 0, 0, (cn == "RL" ? -1 : 1) * Fr / 4 });
            var tor = RunStudy(sm, m, "Torsion", nodePt, new List<string>(), loadsT, true);
            if (tor != null)
            {
                Func<string, string, double> tw = (l, r) =>
                {
                    double uzL = nodesOf(l).Average(n => tor.Uz(fr.Nodes[n])), uzR = nodesOf(r).Average(n => tor.Uz(fr.Nodes[n]));
                    return Math.Atan((uzL - uzR) / (yOf(r) - yOf(l))) * 180 / Math.PI;     // left up: positive
                };
                double twF = tw("FL", "FR"), twR = tw("RL", "RR"), twist = twF - twR;
                double k = torque / Math.Abs(twist);
                sb.Append("\nTorsion: free-free, inertia relief. Front couple " + F(Ft, "0") + " N (left up, right down, " + F(spanF, "0") + " mm apart), rear couple " +
                          F(Fr, "0") + " N the other way (" + F(spanR, "0") + " mm apart)\n" +
                          "  front twist " + F(twF, "0.00000") + " deg, rear twist " + F(twR, "0.00000") + " deg\n" +
                          "  torque " + F(torque, "0") + " Nm, twist " + F(twist, "0.0000") + " deg  ->  torsional stiffness " + F(k, "0") + " Nm/deg\n");
                rep.Note(!double.IsNaN(k) && k > 0, "Torsion: stiffness " + F(k, "0") + " Nm/deg (twist " + F(twist, "0.0000") + " deg under " + F(torque, "0") +
                         " Nm), peak beam stress " + F(tor.MaxStress, "0.0") + " MPa, max displacement " + F(tor.MaxDisp, "0.000") + " mm");
            }

            // 3. braking and cornering: wheel loads -> link forces -> frame nodes, inertia relief
            foreach (var cs in new[] { Tuple.Create("braking", "Braking"), Tuple.Create("cornering", "Cornering") })
            {
                var rows = cases.Where(r => r[0] == cs.Item1).ToList();
                if (rows.Count != 4) { rep.Note(false, cs.Item2 + ": " + rows.Count + " rows for '" + cs.Item1 + "' in load_cases.csv (4 expected)"); continue; }
                var loads = new Dictionary<string, double[]>();
                sb.Append("\n" + cs.Item2 + " (load_cases.csv '" + cs.Item1 + "'): link forces, N (+ = tension)\n");
                foreach (var r in rows)
                {
                    string cn = r[1] == "FL" ? "FL" : r[1] == "FR" ? "FR" : r[1] == "RL" ? "RL" : "RR";
                    var c = corners[cn];
                    var Ftyre = new[] { -Val(r[2]), -Val(r[3]), Val(r[4]) };        // car axes
                    var T = LinkForces(c, Ftyre, out double resid);
                    sb.Append("  " + cn + " tyre (" + string.Join(", ", Ftyre.Select(v => F(v, "0"))) + "): " +
                              string.Join(", ", links.Select((l, i) => l.Replace("_in", "") + " " + F(T[i], "0"))) + "  (residual " + F(resid, "0.000") + ")\n");
                    for (int i = 0; i < 6; i++)
                    {
                        var u = Unit(Sub(c.P[links[i]], c.P[OuterOf(links[i])]));     // outer -> inner
                        Add(loads, pickNode[cn][links[i]], new[] { -T[i] * u[0], -T[i] * u[1], -T[i] * u[2] });
                    }
                }
                var res = RunStudy(sm, m, cs.Item2, nodePt, new List<string>(), loads, true);
                if (res != null)
                {
                    double fos = YIELD_MPA / res.MaxStress;
                    rep.Note(fos >= 1.5, cs.Item2 + ": peak beam stress " + F(res.MaxStress, "0.0") + " MPa, factor of safety on yield (" + F(YIELD_MPA, "0") + " MPa) " +
                             F(fos, "0.00") + " (1.5 wanted), max displacement " + F(res.MaxDisp, "0.000") + " mm");
                }
            }

            if (ApiLimit)
                sb.Append("\nWhy the studies are not solved (SolidWorks 2026 SP2.1 Student, Simulation API, 2026-11-17)\n" +
                    "  The chassis is a weldment, so Simulation meshes the tubes as beams and joins them at joints. Beam loads and fixtures go on joints.\n" +
                    "  CWJoints (BeamManager.GetJointGroup) can recalculate joints but has no getter: the API hands out no joint objects.\n" +
                    "  Tried at one node (swh ChassisStatics probe), AddForce2 with each selection type: the node's sketch point (taken only as\n" +
                    "  face/edge/vertex/point, error 18 as beam joint, 19 as beam), the nearest tube vertex (error 11 for all three, 11 mm off the node anyway),\n" +
                    "  the tube body (taken as a whole-beam load or as a point load, error 18 as joint). AddRestraint (fixed) refuses all three (1, 16, 1).\n" +
                    "  The forces taken on sketch points are kept in the study, but the solver reports no load: they never reach the joints.\n" +
                    "  SelectByID2(\"\", \"SIMULATION\", node) to pick a joint the way the UI does hung SolidWorks for 30 min (killed and restarted).\n" +
                    "  Torsion was changed to a balanced pair of couples with inertia relief so that it needs no fixture; it also failed only on the loads.\n" +
                    "  What would work: a person picks the joints in each study (a minute per study; the forces and their values are listed above),\n" +
                    "  or a solid-mesh model of the frame with forces on tube faces (not attempted: 0.9 to 1.6 mm walls need a very fine mesh).\n");

            // save the part with the studies
            bool saved = Save(m, out int se);
            rep.Note(saved, saved ? "saved " + ChassisPath + " with the studies" : "NOT saved (error " + se + ")");
            return Finish(reportFile);
        }

        static int Finish(string reportFile)
        {
            string full = rep.Text("ChassisStatics, " + ChassisPath) + "\n" + sb;
            WriteReport(reportFile, full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }

        class Result
        {
            public double MaxStress, MaxDisp;
            public List<double[]> Nodes = new List<double[]>();   // x y z (mm), ux uy uz (mm)
            public double Uz(double[] p) => Nodes.Count == 0 ? double.NaN : Nodes.OrderBy(n => Dist3(n[0], n[1], n[2], p[0], p[1], p[2])).First()[5];
        }

        static Result RunStudy(CWStudyManager sm, ModelDoc2 m, string name, Dictionary<string, object> nodePt, List<string> fixedNodes,
                               Dictionary<string, double[]> loads, bool inertiaRelief)
        {
            // an old study of that name goes first
            for (int i = sm.StudyCount - 1; i >= 0; i--)
                if (sm.GetStudy(i) is CWStudy old && old.Name == name) sm.DeleteStudy(name);
            int err;
            var st = sm.CreateNewStudy3(name, (int)swsAnalysisStudyType_e.swsAnalysisStudyTypeStatic, (int)swsMeshType_e.swsMeshTypeBeam, out err) as CWStudy;
            if (st == null)
                st = sm.CreateNewStudy3(name, (int)swsAnalysisStudyType_e.swsAnalysisStudyTypeStatic, (int)swsMeshType_e.swsMeshTypeMixed, out err) as CWStudy;
            if (st == null) { rep.Note(false, name + ": CreateNewStudy3 refused (error " + err + ")"); return null; }
            var bm = st.BeamManager as CWBeamManager;
            int nb = bm?.BeamCount ?? 0;
            var jg = bm?.GetJointGroup(out err) as CWJoints;
            if (jg != null) { jg.JointsBeginEdit(); jg.CalculateJoints(); jg.JointsEndEdit(); }
            var opt = st.StaticStudyOptions as CWStaticStudyOptions;
            if (opt != null && inertiaRelief) { opt.UseInertialRelief2 = true; opt.UseSoftSpring2 = true; }   // free-free: soft springs hold the rigid-body modes
            string resDir = P("sim", "stress", "results");
            Directory.CreateDirectory(resDir);
            if (opt != null) opt.ResultFolder = resDir;                      // solver files out of cad/chassis
            string optTxt = opt == null ? "no static options object" : "inertia relief " + opt.UseInertialRelief2 + ", soft springs " + opt.UseSoftSpring2;
            var solids = st.SolidManager as CWSolidManager;
            int nComp = solids?.ComponentCount ?? -1;
            var lr = st.LoadsAndRestraintsManager as CWLoadsAndRestraintsManager;
            var probs = new List<string>();
            // fixtures
            if (fixedNodes.Count > 0)
            {
                var ents = fixedNodes.Where(nodePt.ContainsKey).Select(n => nodePt[n]).ToArray();
                var rs = lr.AddRestraint((int)swsRestraintType_e.swsRestraintTypeFixed, ents, null, out err) as CWRestraint;
                if (rs == null || err != 0) probs.Add("fixture on " + ents.Length + " joints: error " + err);
            }
            // loads: one force feature per node, components along the Front plane (x, y in plane, z normal)
            var front = TopFeatures(m).Where(f => f.GetTypeName2() == "RefPlane").FirstOrDefault();
            int nLoads = 0;
            double sx = 0, sy = 0, sz = 0;
            foreach (var kv in loads)
            {
                if (!nodePt.ContainsKey(kv.Key)) { probs.Add("no joint for node " + kv.Key); continue; }
                var fo = lr.AddForce2((int)swsForceType_e.swsForceTypeForceOrMoment, (int)swsSelectionType_e.swsSelectionFaceEdgeVertexPoint,
                                      new object[] { nodePt[kv.Key] }, front, out err) as CWForce;
                if (fo == null || err != 0) { probs.Add("force at " + kv.Key + ": error " + err); continue; }
                fo.ForceBeginEdit();
                fo.Unit = (int)swsForceUnit_e.swsForceUnitNOrNm;
                fo.SetForceComponentValues2(true, true, true, kv.Value[0], kv.Value[1], kv.Value[2]);
                int fe = fo.ForceEndEdit();
                if (fe != 0) { probs.Add("force at " + kv.Key + ": ForceEndEdit " + fe); continue; }
                nLoads++; sx += kv.Value[0]; sy += kv.Value[1]; sz += kv.Value[2];
            }
            // mesh and run
            var mesh = st.Mesh as CWMesh;
            double es = 0, tol = 0;
            mesh?.GetDefaultElementSizeAndTolerance((int)swsLinearUnit_e.swsLinearUnitMillimeters, out es, out tol);
            int me = st.CreateMesh((int)swsLinearUnit_e.swsLinearUnitMillimeters, es, tol);
            int ne = (st.Mesh as CWMesh)?.ElementCount ?? 0;
            int re = st.RunAnalysis();
            var r = new Result();
            var res = st.Results as CWResults;
            if (res != null)
            {
                if (res.GetBeamMinMaxStress((int)swsBeamStressComponent_e.swsBeamStressComponentWorstCase, 1, (int)swsStrengthUnit_e.swsStrengthUnitNewtonPerSquareMillimeter, out err) is object[] bs && bs.Length >= 4)
                    r.MaxStress = Math.Max(Math.Abs(Convert.ToDouble(bs[1])), Math.Abs(Convert.ToDouble(bs[3])));
                else if (res.GetBeamMinMaxStress((int)swsBeamStressComponent_e.swsBeamStressComponentWorstCase, 1, (int)swsStrengthUnit_e.swsStrengthUnitNewtonPerSquareMillimeter, out err) is double[] bd && bd.Length >= 4)
                    r.MaxStress = Math.Max(Math.Abs(bd[1]), Math.Abs(bd[3]));
                else r.MaxStress = double.NaN;
                var dd = res.GetMinMaxDisplacement((int)swsDisplacementComponent_e.swsDisplacementComponentURES, 1, null, (int)swsLinearUnit_e.swsLinearUnitMillimeters, out err);
                var da = ToD(dd);
                r.MaxDisp = da.Length >= 4 ? da[3] : double.NaN;
                // node coordinates and displacements for the twist
                var nodes = ToD((st.Mesh as CWMesh)?.GetNodes());       // node, x, y, z (m)
                var tdisp = ToD(res.GetTranslationalDisplacement(1, null, (int)swsLinearUnit_e.swsLinearUnitMillimeters, out err));  // node, ux, uy, uz
                var dispBy = new Dictionary<int, double[]>();
                for (int i = 0; i + 3 < tdisp.Length; i += 4) dispBy[(int)tdisp[i]] = new[] { tdisp[i + 1], tdisp[i + 2], tdisp[i + 3] };
                for (int i = 0; i + 3 < nodes.Length; i += 4)
                    if (dispBy.TryGetValue((int)nodes[i], out var u)) r.Nodes.Add(new[] { nodes[i + 1] * 1000, nodes[i + 2] * 1000, nodes[i + 3] * 1000, u[0], u[1], u[2] });
            }
            bool ok = st != null && probs.Count == 0 && me == 0 && re == 0 && !double.IsNaN(r.MaxStress) && r.MaxStress > 0;
            // the solver's own words, when the run fails
            string outFile = new[] { opt?.ResultFolder, resDir, Path.GetDirectoryName(ChassisPath) }.Where(d => !string.IsNullOrEmpty(d))
                .Select(d => Path.Combine(d, Path.GetFileNameWithoutExtension(ChassisPath) + "-" + name + ".OUT")).FirstOrDefault(File.Exists);
            string solverErr = outFile == null ? null : File.ReadAllLines(outFile).Where(l => l.Contains("ERROR")).Select(l => l.Trim()).FirstOrDefault();
            if (!ok && re == 24 && solverErr != null && solverErr.Contains("No load"))
            {
                // SolidWorks 2026 SP2.1 Student, 2026-11-17: the beam joints cannot be reached through the API (see the header)
                ApiLimit = true;
                rep.Warn(false, name + ": study set up (" + nb + " beams, " + nLoads + " forces at the frame nodes' sketch points, sum " + F(sx, "0") + ", " + F(sy, "0") + ", " + F(sz, "0") +
                         " N, meshed " + ne + " elements) but NOT solved: the solver reports '" + solverErr + "' (" + Path.GetFileName(outFile) +
                         "): forces on sketch points are accepted by AddForce2 yet not passed to the beam joints, and the API hands out no joint entity");
                return null;
            }
            rep.Note(ok, name + ": static study, " + (st.MeshType == (int)swsMeshType_e.swsMeshTypeBeam ? "beam" : "mesh type " + st.MeshType) + ", " + nb + " beams, " +
                     (fixedNodes.Count > 0 ? fixedNodes.Count + " joints fixed" : "no fixtures") + (inertiaRelief ? ", inertia relief" : "") + ", " + nLoads + " joint forces (sum " +
                     F(sx, "0") + ", " + F(sy, "0") + ", " + F(sz, "0") + " N), mesh " + (me == 0 ? "ok, " + ne + " elements" : "error " + me) +
                     ", run " + (re == 0 ? "ok" : "error " + re) + " (" + optTxt + ", solid-manager components " + nComp + "), " + r.Nodes.Count + " nodes read" + (probs.Count > 0 ? "; problems: " + string.Join("; ", probs.Take(10)) : ""));
            return ok ? r : null;
        }

        /// swh ChassisStatics probe: which entities AddForce2 / AddRestraint take on this beam study, one node.
        static void Probe(CWStudyManager sm, ModelDoc2 m, FrameData fr, Dictionary<string, object> nodePt)
        {
            string node = "FS1_L_R"; var q = fr.Nodes[node];
            string prog = P("sim", "stress", "chassis_statics_probe_progress.txt");
            File.WriteAllText(prog, "");
            Action<string> PI = t => { rep.Info(t); File.AppendAllText(prog, DateTime.Now.ToString("HH:mm:ss ") + t + System.Environment.NewLine); };
            int err;
            for (int i = sm.StudyCount - 1; i >= 0; i--) if (sm.GetStudy(i) is CWStudy old && old.Name == "Probe") sm.DeleteStudy("Probe");
            var st = sm.CreateNewStudy3("Probe", (int)swsAnalysisStudyType_e.swsAnalysisStudyTypeStatic, (int)swsMeshType_e.swsMeshTypeBeam, out err) as CWStudy;
            PI("CreateNewStudy3 beam: " + (st != null) + " error " + err + (st != null ? ", MeshType " + st.MeshType : ""));
            if (st == null) return;
            var bm = st.BeamManager as CWBeamManager;
            PI("beams " + bm.BeamCount);
            var jg = bm.GetJointGroup(out err) as CWJoints;
            if (jg != null) { jg.JointsBeginEdit(); jg.CalculateJoints(); int je = jg.JointsEndEdit(); PI("joints recalculated, end edit " + je); }
            int me = st.CreateMesh((int)swsLinearUnit_e.swsLinearUnitMillimeters, 10, 0.5);
            PI("mesh " + me);
            var lr = st.LoadsAndRestraintsManager as CWLoadsAndRestraintsManager;
            var front = TopFeatures(m).Where(f => f.GetTypeName2() == "RefPlane").FirstOrDefault();
            var cands = new List<Tuple<string, object>>();
            cands.Add(Tuple.Create("SketchPoint", nodePt[node]));
            var bodies = ((m as PartDoc).GetBodies2((int)swBodyType_e.swSolidBody, false) as object[] ?? new object[0]).OfType<Body2>().ToList();
            Vertex bestV = null; double bd = 1e9; Body2 bestB = null; double bb = 1e9;
            foreach (var b in bodies)
            {
                foreach (Vertex v in (b.GetVertices() as object[] ?? new object[0]).OfType<Vertex>())
                {
                    var pt = v.GetPoint() as double[];
                    double d = Dist3(pt[0] * 1000, pt[1] * 1000, pt[2] * 1000, q[0], q[1], q[2]);
                    if (d < bd) { bd = d; bestV = v; }
                }
                var bx = b.GetBodyBox() as double[];
                double cx = Math.Max(bx[0] * 1000 - q[0], Math.Max(0, q[0] - bx[3] * 1000)), cy = Math.Max(bx[1] * 1000 - q[1], Math.Max(0, q[1] - bx[4] * 1000)), cz = Math.Max(bx[2] * 1000 - q[2], Math.Max(0, q[2] - bx[5] * 1000));
                double dd = Math.Sqrt(cx * cx + cy * cy + cz * cz);
                if (dd < bb) { bb = dd; bestB = b; }
            }
            PI("nearest vertex " + F(bd, "0.0") + " mm, nearest body box " + F(bb, "0.0") + " mm (" + bestB?.Name + ")");
            if (bestV != null) cands.Add(Tuple.Create("Vertex", (object)bestV));
            if (bestB != null) cands.Add(Tuple.Create("Body2", (object)bestB));
            // (SelectByID2("", "SIMULATION", node) hung SolidWorks 2026 SP2.1 for 30 min, 2026-11-17: not tried again)
            m.ClearSelection2(true);
            foreach (var c in cands)
                foreach (int seltype in new[] { 0, 1, 2 })
                {
                    object fo = null;
                    try { fo = lr.AddForce2((int)swsForceType_e.swsForceTypeForceOrMoment, seltype, new object[] { c.Item2 }, front, out err); }
                    catch (Exception ex) { err = -1; PI("  AddForce2 " + c.Item1 + " sel " + seltype + ": " + ex.Message); continue; }
                    PI("  AddForce2 " + c.Item1 + " sel " + seltype + ": " + (fo != null) + " error " + err);
                    object rs = null; int e2 = 0;
                    try { rs = lr.AddRestraint((int)swsRestraintType_e.swsRestraintTypeFixed, new object[] { c.Item2 }, null, out e2); } catch (Exception ex) { PI("    AddRestraint: " + ex.Message); }
                    if (seltype == 0) PI("  AddRestraint " + c.Item1 + ": " + (rs != null) + " error " + e2);
                }
            sm.DeleteStudy("Probe");
        }

        static double[] ToD(object o)
        {
            if (o is double[] d) return d;
            if (o is object[] a) return a.Select(x => x is double v ? v : Convert.ToDouble(x)).ToArray();
            if (o is float[] f) return f.Select(x => (double)x).ToArray();
            return new double[0];
        }

        /// The sketch point at every frame node, from the FRAME_<group> member sketches.
        static Dictionary<string, object> NodePoints(ModelDoc2 m, FrameData fr)
        {
            var res = new Dictionary<string, object>();
            foreach (var f in TopFeatures(m).Where(f => f.Name.StartsWith("FRAME_")))
            {
                var sk = f.GetSpecificFeature2() as Sketch;
                foreach (SketchPoint sp in (sk?.GetSketchPoints2() as object[] ?? new object[0]).OfType<SketchPoint>())
                {
                    double x = sp.X * 1000, y = sp.Y * 1000, z = sp.Z * 1000;
                    var hit = fr.Nodes.FirstOrDefault(kv => Dist3(kv.Value[0], kv.Value[1], kv.Value[2], x, y, z) < 0.05);
                    if (hit.Key != null && !res.ContainsKey(hit.Key)) res[hit.Key] = sp;
                }
            }
            return res;
        }

        static string OuterOf(string inner) =>
            inner.StartsWith("lwb") ? "lwb_out" : inner.StartsWith("uwb") ? "uwb_out" : inner == "tie_in" ? "tie_out" : "pushrod_out";

        /// Link tensions (N) holding the upright against a tyre force F at the contact patch: six two-force members.
        static double[] LinkForces(BuildSuspension.Corner c, double[] Ft, out double resid)
        {
            string[] links = { "lwb_in_fwd", "lwb_in_aft", "uwb_in_fwd", "uwb_in_aft", "tie_in", "pushrod_in" };
            var A = new double[6, 6]; var b = new double[6];
            var o = c.P["wc"];
            for (int i = 0; i < 6; i++)
            {
                var po = c.P[OuterOf(links[i])];
                var u = Unit(Sub(c.P[links[i]], po));        // force on the upright along u (tension pulls it inboard)
                var rr = Sub(po, o);
                var mo = Cross(rr, u);
                for (int k = 0; k < 3; k++) { A[k, i] = u[k]; A[k + 3, i] = mo[k] / 1000; }
            }
            var rc = Sub(c.P["cp"], o); var mt = Cross(rc, Ft);
            for (int k = 0; k < 3; k++) { b[k] = -Ft[k]; b[k + 3] = -mt[k] / 1000; }
            var x = Solve(A, b);
            resid = 0;
            for (int k = 0; k < 6; k++) { double s = -b[k]; for (int i = 0; i < 6; i++) s -= A[k, i] * x[i]; resid = Math.Max(resid, Math.Abs(s + 0)); }
            // residual of A x = b
            resid = 0;
            for (int k = 0; k < 6; k++) { double s = 0; for (int i = 0; i < 6; i++) s += A[k, i] * x[i]; resid = Math.Max(resid, Math.Abs(s - b[k])); }
            return x;
        }

        static double[] Solve(double[,] A0, double[] b0)
        {
            int n = b0.Length; var A = (double[,])A0.Clone(); var b = (double[])b0.Clone();
            for (int c = 0; c < n; c++)
            {
                int p = c; for (int r = c + 1; r < n; r++) if (Math.Abs(A[r, c]) > Math.Abs(A[p, c])) p = r;
                for (int k = 0; k < n; k++) { var t = A[c, k]; A[c, k] = A[p, k]; A[p, k] = t; }
                { var t = b[c]; b[c] = b[p]; b[p] = t; }
                for (int r = c + 1; r < n; r++) { double f = A[r, c] / A[c, c]; for (int k = c; k < n; k++) A[r, k] -= f * A[c, k]; b[r] -= f * b[c]; }
            }
            var x = new double[n];
            for (int r = n - 1; r >= 0; r--) { double s = b[r]; for (int k = r + 1; k < n; k++) s -= A[r, k] * x[k]; x[r] = s / A[r, r]; }
            return x;
        }

        static void Add(Dictionary<string, double[]> d, string k, double[] v)
        {
            if (!d.ContainsKey(k)) d[k] = new double[3];
            for (int i = 0; i < 3; i++) d[k][i] += v[i];
        }

        static double[] Sub(double[] a, double[] b) => new[] { a[0] - b[0], a[1] - b[1], a[2] - b[2] };
        static double[] Cross(double[] p, double[] q) => new[] { p[1] * q[2] - p[2] * q[1], p[2] * q[0] - p[0] * q[2], p[0] * q[1] - p[1] * q[0] };
        static double[] Unit(double[] a) { double L = Math.Sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]); return new[] { a[0] / L, a[1] / L, a[2] / L }; }
    }
}
