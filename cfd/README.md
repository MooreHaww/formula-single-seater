# cfd/

Ring 5 lives here. Ansys Student (Fluent) is primary, SimScale the backup.

| Path | What |
|---|---|
| `fluent_halfcar_setup.md` | The setup guide: frame, air box, mesh sizes, solver settings, what to export. Untested, needs the app. |
| `halfcar_setup.jou` | Solver journal that applies the settings, runs, and exports the wake planes. Untested, needs the app. |
| `geometry/` | STEP exports per variant from `cad/macros/ExportConfigsSTEP.bas` (git LFS). |
| `cases/` | Fluent case and data files. Ignored by git (too large); keep them locally. |
| `results/forces.csv` | One row per run, **full-car** forces. Read by `matlab/aero_plots.m`. |
| `results/wake/<variant>_<n>L.csv` | Node exports of the wake planes. Read by `matlab/cfd/wake_postprocess.m`. |
| `results/aero_summary.csv`, `results/wake_summary.csv` | Written by the MATLAB scripts. |

## forces.csv columns

```
variant,speed_mps,downforce_N,drag_N,downforce_front_N,cells,note
C,20,1980,690,870,920000,baseline
C,20,2080,710,900,460000,half mesh
C,30,4420,1540,1950,920000,speed check
```

`downforce_front_N` is the force on the front wing surfaces (`fw*`), used for the front/rear split. Rows with a different `cells` or `speed_mps` for the same variant are the mesh and speed checks; `aero_plots.m` reports them as percent changes against the baseline row (the one at `cfd_speed` with the most cells).

## Trust table (goes into docs/cfd.md with the numbers)

| Result | Trust |
|---|---|
| Ranking of variants | Reasonable |
| Size of differences between variants | Indicative |
| Absolute downforce and drag | Rough, could be off by tens of percent; never quoted without that warning |
| Open-wheel flow, wheel wake | Poor; steady coarse RANS cannot capture the unsteady separation off rotating wheels |
| Front/rear aero balance | Rough; floor and diffuser are sensitive to the near-ground mesh |
| Wake at 2 to 3 lengths | Weakest result; the method smears the wake and models rather than resolves its turbulence. Good for comparing variants, not for absolute decay |
