// Common.cs - shared helpers for the SolidWorks harness (swh.exe).
// Built by tools/sw_run.py against the installed SolidWorks 2026 interop DLLs.
// No message boxes anywhere: every result goes to a report file and stdout.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;

namespace SwHarness
{
    /// Thrown when only a person can continue (no SolidWorks, licence prompt, ...).
    public class NeedsHumanException : Exception { public NeedsHumanException(string m) : base(m) { } }

    /// Thrown when a step cannot start (input missing, wrong document); nothing changed.
    public class StepStoppedException : Exception { public StepStoppedException(string m) : base(m) { } }

    public static class Ctx
    {
        public static SldWorks App;
        public static string Repo;
        public static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

        public static string P(params string[] parts) => Path.Combine(new[] { Repo }.Concat(parts).ToArray());
        public static string ChassisPath => P("cad", "chassis", "chassis.SLDPRT");
        public static string LayoutPath => P("cad", "layout", "master_layout.SLDPRT");
        public static string AssemblyPath => P("cad", "formula_single_seater.SLDASM");

        [DllImport("oleaut32.dll", PreserveSig = false)]
        static extern void GetActiveObject(ref Guid rclsid, IntPtr reserved, [MarshalAs(UnmanagedType.IUnknown)] out object ppunk);
        [DllImport("ole32.dll")]
        static extern int CLSIDFromProgID([MarshalAs(UnmanagedType.LPWStr)] string progId, out Guid clsid);

        static object TryActive()
        {
            try
            {
                CLSIDFromProgID("SldWorks.Application", out Guid g);
                GetActiveObject(ref g, IntPtr.Zero, out object o);
                return o;
            }
            catch { return null; }
        }

        /// Connect to the running SolidWorks; start it if none runs (waits up to startWaitS).
        public static void Connect(int startWaitS = 300)
        {
            object o = TryActive();
            if (o == null)
            {
                string exe = @"C:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\SLDWORKS.exe";
                if (!File.Exists(exe)) throw new NeedsHumanException("SolidWorks is not running and " + exe + " was not found.");
                Log("SolidWorks not running: starting " + exe);
                Process.Start(exe);
                var sw = Stopwatch.StartNew();
                while (o == null && sw.Elapsed.TotalSeconds < startWaitS)
                {
                    System.Threading.Thread.Sleep(3000);
                    o = TryActive();
                }
                if (o == null)
                    throw new NeedsHumanException("SolidWorks was started but did not register within " + startWaitS +
                        " s. Most likely a licence or sign-in dialog is waiting for a person.");
                System.Threading.Thread.Sleep(10000);
            }
            App = (SldWorks)o;
            App.Visible = true;
        }

        public static void Log(string s) { Console.WriteLine(s); Console.Out.Flush(); }

        public static string Now() => DateTime.Now.ToString("yyyy-MM-dd HH:mm", Inv);
        public static string F(double v, string fmt = "0.0") => v.ToString(fmt, Inv);

        // ---------------------------------------------------------------- files
        public static string[] ReadLines(string path) =>
            File.ReadAllText(path).Replace("\r", "").Split('\n');

        /// Data rows of a CSV (header and #-comments dropped), split on commas, trimmed.
        public static List<string[]> Csv(string path)
        {
            var rows = new List<string[]>();
            var lines = ReadLines(path);
            for (int k = 1; k < lines.Length; k++)
            {
                string ln = lines[k].Trim();
                if (ln == "" || ln.StartsWith("#")) continue;
                rows.Add(ln.Split(',').Select(s => s.Trim()).ToArray());
            }
            return rows;
        }

        public static double Val(string s)
        {
            double.TryParse(s.Trim(), NumberStyles.Float, Inv, out double v);
            return v;
        }

        public static void WriteReport(string path, string txt)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, txt.Replace("\r\n", "\n").Replace("\n", "\r\n") + "\r\n");
        }

        /// car_params.txt: "name"= number  ' comment. Non-numeric values skipped.
        public static Dictionary<string, double> ReadParams(string path)
        {
            var d = new Dictionary<string, double>();
            if (!File.Exists(path)) return d;
            foreach (string raw in ReadLines(path))
            {
                string ln = raw.Trim();
                if (!ln.StartsWith("\"")) continue;
                int q2 = ln.IndexOf('"', 1);
                if (q2 <= 1) continue;
                string nm = ln.Substring(1, q2 - 1);
                string v = ln.Substring(q2 + 1);
                int c = v.IndexOf('\'');
                if (c >= 0) v = v.Substring(0, c);
                v = v.Trim();
                if (v.StartsWith("=")) v = v.Substring(1).Trim();
                if (double.TryParse(v, NumberStyles.Float, Inv, out double x)) d[nm] = x;
            }
            return d;
        }

        /// Move a file out of the way: <dir>\old\<name>_<yyyymmdd_hhmmss><ext>. Returns the new path or "".
        public static string MoveAside(string path)
        {
            if (!File.Exists(path)) return "";
            string dir = Path.Combine(Path.GetDirectoryName(path), "old");
            Directory.CreateDirectory(dir);
            string dest = Path.Combine(dir, Path.GetFileNameWithoutExtension(path) + "_" +
                DateTime.Now.ToString("yyyyMMdd_HHmmss", Inv) + Path.GetExtension(path));
            File.Move(path, dest);
            return dest;
        }

        // ---------------------------------------------------------------- documents
        public static ModelDoc2 FindOpenDoc(string path)
        {
            object[] docs = App.GetDocuments() as object[];
            if (docs == null) return null;
            foreach (object o in docs)
            {
                var m = o as ModelDoc2;
                if (m != null && string.Equals(m.GetPathName(), path, StringComparison.OrdinalIgnoreCase)) return m;
            }
            return null;
        }

        /// Close a document by path without saving (the file on disk is what counts).
        public static bool CloseIfOpen(string path)
        {
            var m = FindOpenDoc(path);
            if (m == null) return false;
            App.CloseDoc(m.GetTitle());
            return true;
        }

        /// Open a part or assembly silently and make it the active document.
        public static ModelDoc2 Open(string path)
        {
            if (!File.Exists(path)) throw new StepStoppedException("Not found: " + path);
            int type = path.EndsWith(".SLDASM", StringComparison.OrdinalIgnoreCase) ? (int)swDocumentTypes_e.swDocASSEMBLY
                                                                                  : (int)swDocumentTypes_e.swDocPART;
            int errs = 0, warns = 0;
            var m = App.OpenDoc6(path, type, (int)swOpenDocOptions_e.swOpenDocOptions_Silent, "", ref errs, ref warns);
            if (m == null) throw new StepStoppedException("SolidWorks could not open " + path + " (error " + errs + ", warning " + warns + ")");
            int aerr = 0;
            App.ActivateDoc3(m.GetTitle(), false, (int)swRebuildOnActivation_e.swDontRebuildActiveDoc, ref aerr);
            return m;
        }

        /// New part from the default template, units set to MMGS, saved at path.
        public static ModelDoc2 NewPartAt(string path)
        {
            string tmpl = App.GetUserPreferenceStringValue((int)swUserPreferenceStringValue_e.swDefaultTemplatePart);
            var m = App.NewDocument(tmpl, 0, 0, 0) as ModelDoc2;
            if (m == null) throw new StepStoppedException("No new part from the default template " + tmpl);
            SetMmgs(m);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            int errs = 0, warns = 0;
            bool ok = m.Extension.SaveAs3(path, (int)swSaveAsVersion_e.swSaveAsCurrentVersion,
                (int)swSaveAsOptions_e.swSaveAsOptions_Silent, null, null, ref errs, ref warns);
            if (!ok) throw new StepStoppedException("New part could not be saved as " + path + " (error " + errs + ")");
            return m;
        }

        public static void SetMmgs(ModelDoc2 m)
        {
            m.Extension.SetUserPreferenceInteger((int)swUserPreferenceIntegerValue_e.swUnitSystem, 0,
                (int)swUnitSystem_e.swUnitSystem_MMGS);
        }

        public static bool Save(ModelDoc2 m, out int errs)
        {
            errs = 0; int warns = 0;
            return m.Save3((int)swSaveAsOptions_e.swSaveAsOptions_Silent, ref errs, ref warns);
        }

        // ---------------------------------------------------------------- features
        public static IEnumerable<Feature> TopFeatures(ModelDoc2 m)
        {
            var f = m.FirstFeature() as Feature;
            while (f != null)
            {
                yield return f;
                f = f.GetNextFeature() as Feature;
            }
        }

        public static IEnumerable<Feature> SubFeatures(Feature f)
        {
            var s = f.GetFirstSubFeature() as Feature;
            while (s != null)
            {
                yield return s;
                s = s.GetNextSubFeature() as Feature;
            }
        }

        public static Feature FindFeature(ModelDoc2 m, string nm) =>
            TopFeatures(m).FirstOrDefault(f => string.Equals(f.Name, nm, StringComparison.OrdinalIgnoreCase));

        public static Feature FindFeatureDeep(ModelDoc2 m, string nm)
        {
            foreach (var f in TopFeatures(m))
            {
                if (string.Equals(f.Name, nm, StringComparison.OrdinalIgnoreCase)) return f;
                foreach (var s in SubFeatures(f))
                    if (string.Equals(s.Name, nm, StringComparison.OrdinalIgnoreCase)) return s;
            }
            return null;
        }

        /// Rename; returns true if the feature now has that name.
        public static bool Rename(Feature f, string nm)
        {
            if (f == null) return false;
            try { f.Name = nm; } catch { }
            return f.Name == nm;
        }

        public static string CreateErrors(FeatureManager fm)
        {
            object msgs; string featType;
            int n = fm.GetCreateFeatureErrors(out msgs, out featType);
            var arr = msgs as object[];
            string s = (n > 0 && arr != null) ? string.Join("; ", arr.Select(x => Convert.ToString(x))) : "";
            return s == "" ? "(no message)" : s;
        }

        // ---------------------------------------------------------------- bodies
        public static Body2[] Bodies(PartDoc p)
        {
            var arr = p.GetBodies2((int)swBodyType_e.swSolidBody, false) as object[];
            return arr == null ? new Body2[0] : arr.Cast<Body2>().ToArray();
        }

        /// Centroid (mm) and volume (mm3) of a body.
        public static double[] CentroidVol(Body2 b)
        {
            var mp = b.GetMassProperties(7900.0) as double[];
            return new[] { mp[0] * 1000, mp[1] * 1000, mp[2] * 1000, mp[3] * 1e9 };
        }

        public static double Mass(ModelDoc2 m)
        {
            var mp = m.Extension.CreateMassProperty() as MassProperty;
            return mp == null ? 0 : mp.Mass;
        }

        /// Update the cut list and total it: bodies, sum of LENGTH (mm) x bodies per item.
        public static void CutList(ModelDoc2 m, out int nBodies, out double cutLen_m, out int lenMissing, out int nFolders)
        {
            nBodies = 0; cutLen_m = 0; lenMissing = 0; nFolders = 0;
            foreach (var f in TopFeatures(m).Where(f => f.GetTypeName2() == "SolidBodyFolder"))
            {
                var bf = f.GetSpecificFeature2() as BodyFolder;
                if (bf != null) { bf.SetAutomaticUpdate(true); bf.UpdateCutList(); }
            }
            m.ForceRebuild3(false);
            foreach (var f in TopFeatures(m).Where(f => f.GetTypeName2() == "SolidBodyFolder").ToList())
            {
                foreach (var sf in SubFeatures(f).Where(s => s.GetTypeName2() == "CutListFolder").ToList())
                {
                    var bf = sf.GetSpecificFeature2() as BodyFolder;
                    int cnt = bf == null ? 0 : bf.GetBodyCount();
                    if (cnt <= 0) continue;
                    nFolders++;
                    nBodies += cnt;
                    var cpm = sf.CustomPropertyManager;
                    string valOut = "", resOut = ""; bool wasRes, linked;
                    if (cpm != null) cpm.Get6("LENGTH", false, out valOut, out resOut, out wasRes, out linked);
                    if (double.TryParse(resOut, NumberStyles.Float, Inv, out double L)) cutLen_m += L / 1000.0 * cnt;
                    else lenMissing++;
                }
            }
        }

        // ---------------------------------------------------------------- frame data
        public class FrameData
        {
            public Dictionary<string, double[]> Nodes = new Dictionary<string, double[]>();   // mm
            public List<string[]> TubeRows = new List<string[]>();
            public Dictionary<string, double[]> Tubes = new Dictionary<string, double[]>();   // id -> ax..bz mm
            public Dictionary<string, double> TubeVol = new Dictionary<string, double>();     // mm3
            public List<string> TubeOrder = new List<string>();
        }

        public static FrameData ReadFrame()
        {
            string nodesFile = P("cad", "frame", "frame_nodes.csv"), tubesFile = P("cad", "frame", "frame_tubes.csv");
            if (!File.Exists(nodesFile) || !File.Exists(tubesFile))
                throw new StepStoppedException("Missing " + nodesFile + " or " + tubesFile + " (run frame_layout in MATLAB)");
            var fr = new FrameData();
            foreach (var r in Csv(nodesFile))
                if (r.Length >= 4) fr.Nodes[r[0]] = new[] { Val(r[1]), Val(r[2]), Val(r[3]) };
            foreach (var r in Csv(tubesFile))
            {
                if (r.Length < 4) continue;
                fr.TubeRows.Add(r);
                if (!fr.Nodes.ContainsKey(r[1]) || !fr.Nodes.ContainsKey(r[2])) continue;
                var a = fr.Nodes[r[1]]; var b = fr.Nodes[r[2]];
                fr.Tubes[r[0]] = new[] { a[0], a[1], a[2], b[0], b[1], b[2] };
                fr.TubeOrder.Add(r[0]);
                if (r.Length >= 6)
                {
                    double od = Val(r[4]), w = Val(r[5]);
                    fr.TubeVol[r[0]] = Math.PI / 4 * (od * od - (od - 2 * w) * (od - 2 * w)) * Dist3(a[0], a[1], a[2], b[0], b[1], b[2]);
                }
            }
            return fr;
        }

        public static double Dist3(double x1, double y1, double z1, double x2, double y2, double z2) =>
            Math.Sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2) + (z1 - z2) * (z1 - z2));

        public static double DistToSegment(double x, double y, double z, double[] t)
        {
            double vx = t[3] - t[0], vy = t[4] - t[1], vz = t[5] - t[2];
            double L2 = vx * vx + vy * vy + vz * vz, u = 0;
            if (L2 > 0) u = ((x - t[0]) * vx + (y - t[1]) * vy + (z - t[2]) * vz) / L2;
            u = Math.Max(0, Math.Min(1, u));
            return Dist3(x, y, z, t[0] + u * vx, t[1] + u * vy, t[2] + u * vz);
        }
    }

    /// PASS/FAIL report collector.
    public class Report
    {
        public StringBuilder Body = new StringBuilder();
        public StringBuilder Failures = new StringBuilder();
        public bool AllPass = true;

        public void Note(bool ok, string txt)
        {
            Body.Append(ok ? "PASS  " : "FAIL  ").Append(txt).Append("\n");
            if (!ok) { Failures.Append("- ").Append(txt).Append("\n"); AllPass = false; }
        }
        public void Info(string txt) => Body.Append("INFO  ").Append(txt).Append("\n");
        public void Line(string txt) => Body.Append(txt).Append("\n");

        public List<string> Warnings = new List<string>();
        /// A finding that does not fail the step (WARN, listed under Warnings).
        public void Warn(bool ok, string txt)
        {
            Body.Append(ok ? "PASS  " : "WARN  ").Append(txt).Append("\n");
            if (!ok) Warnings.Add(txt);
        }

        public string Text(string title, string passWord = "ALL PASS", string failWord = "SOME CHECKS FAILED") =>
            (AllPass ? passWord + (Warnings.Count > 0 ? " (" + Warnings.Count + " warning" + (Warnings.Count > 1 ? "s" : "") + ")" : "") : failWord) +
            "   (" + Ctx.Now() + ", harness swh.exe)  " + title + "\n\n" + Body +
            "\n" + (Failures.Length == 0 ? "No failures." : "Failures:\n" + Failures) +
            (Warnings.Count == 0 ? "" : "\nWarnings (do not fail the step):\n" + string.Join("", Warnings.Select(w => "- " + w + "\n")));
    }
}
