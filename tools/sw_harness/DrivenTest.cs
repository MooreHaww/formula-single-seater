// DrivenTest.cs - "DrivenTest": proves the layout planes follow car_params.txt. On a copy of
// master_layout.SLDPRT linked to a copy of car_params.txt with wheelbase +50 and
// main_hoop_x +20, REAR_AXLE and MAIN_HOOP must move by that much. Nothing in the repo changes.
using System;
using System.IO;
using System.Linq;
using SolidWorks.Interop.sldworks;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class DrivenTest
    {
        public static int Run()
        {
            string dir = Path.Combine(Path.GetTempPath(), "swh_driven_test");
            Directory.CreateDirectory(dir);
            string part = Path.Combine(dir, "layout_test.SLDPRT"), pars = Path.Combine(dir, "car_params_test.txt");
            CloseIfOpen(part);
            File.Copy(LayoutPath, part, true);
            var par = ReadParams(P("params", "car_params.txt"));
            var lines = File.ReadAllLines(P("params", "car_params.txt")).Select(l =>
                l.StartsWith("\"wheelbase\"=") ? "\"wheelbase\"= " + (par["wheelbase"] + 50).ToString(Inv) :
                l.StartsWith("\"main_hoop_x\"=") ? "\"main_hoop_x\"= " + (par["main_hoop_x"] + 20).ToString(Inv) : l).ToArray();
            File.WriteAllLines(pars, lines);
            var m = Open(part);
            var eq = m.GetEquationMgr();
            eq.FilePath = pars;
            eq.LinkToFile = true;
            eq.UpdateValuesFromExternalEquationFile();
            m.ForceRebuild3(false);
            var rep = new Report();
            foreach (var t in new[] { Tuple.Create("REAR_AXLE", par["wheelbase"] + 50), Tuple.Create("MAIN_HOOP", par["main_hoop_x"] + 20),
                                      Tuple.Create("FRONT_HOOP", par["front_hoop_x"]) })
            {
                var rp = FindFeature(m, t.Item1).GetSpecificFeature2() as RefPlane;
                double x = ((double[])rp.Transform.ArrayData)[9] * 1000;
                rep.Note(Math.Abs(x - t.Item2) < 0.01, t.Item1 + " at " + F(x) + " mm with the changed file (expected " + F(t.Item2) + ")");
            }
            App.CloseDoc(m.GetTitle());
            string full = rep.Text("DrivenTest: planes follow car_params.txt (copy linked to a copy with wheelbase +50, main_hoop_x +20)");
            WriteReport(P("cad", "layout", "driven_test_report.txt"), full);
            Log(full);
            return rep.AllPass ? 0 : 1;
        }
    }
}
