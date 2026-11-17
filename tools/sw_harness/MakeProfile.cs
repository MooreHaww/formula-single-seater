// MakeProfile.cs - a round-tube weldment profile of another size, made from an existing one:
// opens the library feature part, sets its outer and inner circle diameters, saves it under
// the new name. swh makeprofile <od> <wall>   (from 25.4x1.6.SLDLFP in the same folder)
using System;
using System.IO;
using System.Linq;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class MakeProfile
    {
        public static int Run(string[] a)
        {
            double od = Val(a[0]), wall = Val(a[1]);
            string dir = P("cad", "weldment_profiles", "formula", "tube_round");
            string src = Path.Combine(dir, "25.4x1.6.SLDLFP");
            string dst = Path.Combine(dir, a[0] + "x" + a[1] + ".SLDLFP");
            if (File.Exists(dst)) { Log("exists: " + dst); return 0; }
            int e = 0, w = 0;
            var m = App.OpenDoc6(src, (int)swDocumentTypes_e.swDocPART, (int)swOpenDocOptions_e.swOpenDocOptions_Silent, "", ref e, ref w);
            if (m == null) throw new StepStoppedException("could not open " + src + " (error " + e + ")");
            // every diameter dimension in the sketches: the larger is the outside, the smaller the inside
            var dims = new System.Collections.Generic.List<Dimension>();
            foreach (var f in TrimTubes.AllFeatures(m))
            {
                var dd = f.GetFirstDisplayDimension() as DisplayDimension;
                while (dd != null)
                {
                    var d = dd.GetDimension2(0);
                    if (d != null) { dims.Add(d); Log("  " + d.GetNameForSelection() + " = " + F(d.GetSystemValue3((int)swInConfigurationOpts_e.swThisConfiguration, null) is double[] v ? v[0] * 1000 : double.NaN, "0.00") + " mm"); }
                    dd = f.GetNextDisplayDimension(dd) as DisplayDimension;
                }
            }
            Func<Dimension, double> val = d => (d.GetSystemValue3((int)swInConfigurationOpts_e.swThisConfiguration, null) as double[])[0] * 1000;
            dims = dims.GroupBy(d => d.GetNameForSelection()).Select(g => g.First()).ToList();
            var big = dims.Where(d => Math.Abs(val(d) - 25.4) < 0.01).ToList();
            var small = dims.Where(d => Math.Abs(val(d) - 22.2) < 0.01).ToList();
            if (big.Count != 1 || small.Count != 1) throw new StepStoppedException("expected one 25.4 and one 22.2 mm dimension, found " + big.Count + " and " + small.Count);
            big[0].SetSystemValue3(od / 1000, (int)swSetValueInConfiguration_e.swSetValue_InAllConfigurations, null);
            small[0].SetSystemValue3((od - 2 * wall) / 1000, (int)swSetValueInConfiguration_e.swSetValue_InAllConfigurations, null);
            m.ForceRebuild3(false);
            bool ok = m.Extension.SaveAs3(dst, (int)swSaveAsVersion_e.swSaveAsCurrentVersion, (int)swSaveAsOptions_e.swSaveAsOptions_Silent | (int)swSaveAsOptions_e.swSaveAsOptions_Copy, null, null, ref e, ref w);
            App.CloseDoc(m.GetTitle());
            Log((ok ? "saved " : "NOT saved (error " + e + ") ") + dst + ": OD " + F(od, "0.0") + ", wall " + F(wall, "0.0") + " mm");
            return ok && File.Exists(dst) ? 0 : 1;
        }
    }
}
