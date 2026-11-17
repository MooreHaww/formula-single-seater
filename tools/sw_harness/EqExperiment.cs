// EqExperiment.cs - "EqExperiment <copy of master_layout>": which equation forms Add2/Add3 accept
// for a plane distance while car_params.txt is linked. Diagnostic only, works on a copy.
using System;
using System.IO;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class EqExperiment
    {
        public static int Run(string[] args)
        {
            string path = Path.GetFullPath(args[0]);
            if (string.Equals(path, LayoutPath, StringComparison.OrdinalIgnoreCase)) throw new StepStoppedException("use a copy");
            byte[] before = File.ReadAllBytes(P("params", "car_params.txt"));
            var m = Open(path);
            var eq = m.GetEquationMgr();
            Log("linked " + eq.LinkToFile + ", count " + eq.GetCount() + ", file " + eq.FilePath + ", D1@REAR_AXLE " + ((m.Parameter("D1@REAR_AXLE") as Dimension) != null));
            string[] forms = {
                "\"D1@REAR_AXLE\" = \"wheelbase\"",
                "\"D1@REAR_AXLE\"= \"wheelbase\"",
                "\"D1@REAR_AXLE\" = 1550",
                "\"D1@REAR_AXLE\"=\"wheelbase\"",
            };
            int all = (int)swInConfigurationOpts_e.swAllConfiguration;
            foreach (var f in forms)
            {
                int n0 = eq.GetCount();
                int i3 = eq.Add3(-1, f, true, all, null);
                Log("Add3 linked   " + f + " -> " + i3 + ", count " + n0 + " -> " + eq.GetCount() + ", status " + eq.Status);
                if (i3 >= 0) { eq.Delete(i3); continue; }
                int i2 = eq.Add2(-1, f, true);
                Log("Add2 linked   " + f + " -> " + i2 + ", count -> " + eq.GetCount());
                if (i2 >= 0) { eq.Delete(i2); continue; }
                int iIdx = eq.Add3(eq.GetCount(), f, true, all, null);
                Log("Add3 at end   " + f + " -> " + iIdx);
                if (iIdx >= 0) eq.Delete(iIdx);
            }
            // unlinked
            eq.LinkToFile = false;
            Log("unlinked: linked " + eq.LinkToFile + ", count " + eq.GetCount());
            int u = eq.Add3(-1, forms[0], true, all, null);
            Log("Add3 unlinked " + forms[0] + " -> " + u + ", count " + eq.GetCount());
            m.ForceRebuild3(false);
            var rp = FindFeature(m, "REAR_AXLE");
            eq.LinkToFile = true;
            bool upd = eq.UpdateValuesFromExternalEquationFile();
            Log("relinked: linked " + eq.LinkToFile + ", update " + upd + ", count " + eq.GetCount() + ", index of D1@REAR_AXLE " + Idx(eq, "D1@REAR_AXLE"));
            byte[] after = File.ReadAllBytes(P("params", "car_params.txt"));
            Log("car_params.txt changed: " + !System.Linq.Enumerable.SequenceEqual(before, after));
            if (!System.Linq.Enumerable.SequenceEqual(before, after)) File.WriteAllBytes(P("params", "car_params.txt"), before);
            return 0;
        }

        static int Idx(EquationMgr eq, string t)
        {
            for (int i = 0; i < eq.GetCount(); i++) if (eq.Equation[i].Contains(t)) return i;
            return -1;
        }
    }
}
