// ProbeViews.cs - diagnostic: prints ModelView.Orientation3 for each standard view of the active document.
using System;
using System.Linq;
using SolidWorks.Interop.sldworks;
using static SwHarness.Ctx;

namespace SwHarness
{
    static class ProbeViews
    {
        public static int Run(string[] args)
        {
            var m = args.Length > 0 ? Open(System.IO.Path.Combine(Repo, args[0])) : (ModelDoc2)App.ActiveDoc;
            var v = (ModelView)m.ActiveView;
            foreach (int k in new[] { 1, 2, 3, 4, 5, 6, 7 })
            {
                m.ShowNamedView2("", k);
                var d = (double[])((MathTransform)v.Orientation3).ArrayData;
                Log("view " + k + ": " + string.Join(" ", d.Take(9).Select(x => F(x, "0.000"))) + " | t " + string.Join(" ", d.Skip(9).Take(3).Select(x => F(x, "0.000"))) + " s " + F(d[12], "0.000"));
            }
            return 0;
        }
    }
}
