// Program.cs - entry point of swh.exe. Usage: swh.exe <repo> <step> [args]
// Exit codes: 0 all checks pass, 1 the step ran but a check failed,
//             2 the step stopped before changing anything or hit an error,
//             3 only a person can continue (no SolidWorks / licence prompt).
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using SolidWorks.Interop.sldworks;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class Program
    {
        static int Main(string[] args)
        {
            if (args.Length < 2)
            {
                Console.WriteLine("usage: swh.exe <repo> <step>   steps: status, new-chassis, ImportFrameNodes, BuildTubes, TrimTubes, " +
                                  "CheckChassis, new-layout, BuildLayout, new-assembly, BuildAssembly, SaveStandardViews <file>");
                return 2;
            }
            Repo = Path.GetFullPath(args[0]);
            string step = args[1];
            try
            {
                Connect();
                App.CommandInProgress = true;      // faster out-of-process calls, no UI updates in between
                try { return Run(step, args.Skip(2).ToArray()); }
                finally { try { App.CommandInProgress = false; } catch { } }
            }
            catch (NeedsHumanException e) { Log("NEEDS A PERSON: " + e.Message); return 3; }
            catch (StepStoppedException e) { Log("STOPPED, NOTHING CHANGED: " + e.Message); return 2; }
            catch (COMException e) { Log("COM ERROR 0x" + e.ErrorCode.ToString("X8") + ": " + e.Message + "\n" + e.StackTrace); return 2; }
            catch (Exception e) { Log("ERROR " + e.GetType().Name + ": " + e.Message + "\n" + e.StackTrace); return 2; }
        }

        static int Run(string step, string[] rest)
        {
            switch (step.ToLowerInvariant())
            {
                case "status": return Status();
                case "driventest": return DrivenTest.Run();
                case "eqexperiment": return EqExperiment.Run(rest);
                case "trimexperiment": return TrimExperiment.Run(rest);
                case "findfeat": return Probe4.FindFeat(rest);
                case "trimdefs": return Probe3.TrimDefs(rest);
                case "tree": return Probe2.Tree(rest);
                case "tubeends": return Probe.TubeEnds(rest);
                case "probeviews": return ProbeViews.Run(rest);
                case "nearpoint": return ProbeNear.Run(rest);
                case "overruns": return ProbeOverrun.Run(rest);
                case "mitre": return Mitre.Run(rest);
                case "makeprofile": return MakeProfile.Run(rest);
                case "suspensionparts": return BuildSuspension.Parts();
                case "suspensionassembly": return BuildSuspension.Assemble();
                case "suspensioncheck": return BuildSuspension.Check(rest);
                case "suspensionmotion": return SuspensionMotion.Run(rest);
                case "chassisstatics": return ChassisStatics.Run(rest);
                case "framesolid": return FrameSolid.Run(rest);
                case "restart-sw":
                {
                    // a fresh SolidWorks for a rebuild: after several rebuilds in one session (7 GB, 14,700 handles,
                    // 2026-11-17) OpenDoc6 returned nothing, with no error code, for freshly written parts.
                    // Every document is closed WITHOUT saving first, as close-all does.
                    var old = Process.GetProcessesByName("SLDWORKS");
                    string before = string.Join(", ", old.Select(p => "pid " + p.Id + " " + (p.WorkingSet64 / 1048576) + " MB " + p.HandleCount + " handles"));
                    int nd = App.GetDocuments() is object[] dd ? dd.Length : 0;
                    App.CloseAllDocuments(true);
                    try { App.ExitApp(); } catch { }
                    App = null;
                    foreach (var p in old)
                    {
                        if (!p.WaitForExit(90000)) { Log("SolidWorks pid " + p.Id + " did not exit in 90 s: ended"); p.Kill(); p.WaitForExit(30000); }
                    }
                    System.Threading.Thread.Sleep(3000);
                    Connect();
                    var now = Process.GetProcessesByName("SLDWORKS");
                    Log("closed " + nd + " documents without saving; SolidWorks restarted (" + before + " -> " +
                        string.Join(", ", now.Select(p => "pid " + p.Id)) + "), revision " + App.RevisionNumber());
                    return now.Length == 1 ? 0 : 1;
                }
                case "close-all":
                    // every open document closed WITHOUT saving: the files on disk are what counts
                    int n = App.GetDocuments() is object[] d ? d.Length : 0;
                    App.CloseAllDocuments(true);
                    Log("closed " + n + " open documents without saving");
                    return 0;
                case "new-chassis": return NewDoc(ChassisPath);
                case "new-layout": return NewDoc(LayoutPath);
                case "new-assembly":
                    CloseIfOpen(AssemblyPath);
                    Log("moved aside: " + (MoveAside(AssemblyPath) is string s && s != "" ? s : "(no old assembly)"));
                    return 0;
                case "importframenodes": return ImportFrameNodes.Run();
                case "buildtubes": return BuildTubes.Run();
                case "trimtubes": return TrimTubes.Run(rest);
                case "checkchassis": return TrimTubes.Check();
                case "buildlayout": return BuildLayout.Run();
                case "buildassembly": return BuildAssembly.Run();
                case "savestandardviews": return SaveStandardViews.Run(rest);
                default: Log("unknown step " + step); return 2;
            }
        }

        static int Status()
        {
            Log("SolidWorks " + App.RevisionNumber() + ", visible " + App.Visible);
            var active = App.ActiveDoc as ModelDoc2;
            Log("active: " + (active == null ? "(none)" : active.GetPathName()));
            if (App.GetDocuments() is object[] docs)
                foreach (ModelDoc2 m in docs) Log("open: " + m.GetPathName() + (m.GetSaveFlag() ? "  (unsaved changes)" : ""));
            return 0;
        }

        /// Close the document at path, move the file to old\, make a new MMGS part saved at path.
        static int NewDoc(string path)
        {
            bool was = CloseIfOpen(path);
            string moved = MoveAside(path);
            NewPartAt(path);
            Log((was ? "closed the open " + Path.GetFileName(path) + "; " : "") +
                (moved == "" ? "no old file; " : "old file moved to " + moved + "; ") + "new empty part saved as " + path);
            return 0;
        }
    }
}
