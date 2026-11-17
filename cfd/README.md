# cfd/

Ring 5 lives here. Ansys Student 2026 R1 (Fluent), driven entirely from Python (PyFluent); SimScale is the backup.

| Path | What |
|---|---|
| `fluent_halfcar.py` | Mesh and solve one variant without clicks: `.venv/Scripts/python cfd/fluent_halfcar.py all C`. See `fluent_halfcar_setup.md`. |
| `postprocess.py` | Forces and wake planes of every run to tables and plots; `--update-variants` puts the CFD numbers into `params/aero_variants.csv` (the lap sim's aero table). |
| `fluent_halfcar_setup.md` | What the scripts do, what has run on this PC, the cell limit, first-run checklist, how to read the results. |
| `geometry_notes.md` | The half-car geometry from `cad/generate/cfd_variants.py`: zones, domain, checks, simplifications. |
| `ansys_quickstart.md` | Install notes and a single-wing smoke test (manual, by clicking). |
| `requirements.txt` | Python packages of the project venv. |
| `halfcar_setup.jou` | Old manual journal, superseded by `fluent_halfcar.py`; kept for reference. |
| `cases/` | Meshes, case and data files, logs. Ignored by git (hundreds of MB); keep them locally. |
| `results/runs/<V><tag>/` | Per run: `run_info.json`, `mesh_info.json`, `forces.out` (half-car force history, every iteration). |
| `results/wake/<V><tag>_<n>L.csv` | Wake-plane node exports (u, v, w, k, total pressure) at n car lengths behind the rear axle. |
| `results/cfd_summary.csv`, `results/wake_cfd.csv` | Written by `postprocess.py`: one row per run / per plane. |
| `results/forces.csv` | Written by `postprocess.py` (full-car forces), read by `matlab/aero_plots.m`. |
| `results/aero_summary.csv` | Written by `matlab/aero_plots.m`. |

**Status 2026-11-17:** all four variants meshed under the Student limit and solved, 1500 iterations each. Results in `../media/cfd/cfd_results.md`. CFD rows are in `params/aero_variants.csv`; variant A is marked NOT converged (its downforce is near zero and swings by ClA +-0.006).

## forces.csv columns

```
variant,speed_mps,downforce_N,drag_N,downforce_front_N,cells,note
```

Full-car values. `downforce_front_N` is the aero load on the **front axle** (from the downforce and the pitching moment about the front contact point: front = DF - M / wheelbase), not the force on the front wing. Rows with a different `cells` or `speed_mps` for the same variant are mesh and speed checks; `aero_plots.m` reports them as percent changes.

## Trust table

| Result | Trust |
|---|---|
| Ranking of variants | Reasonable: same meshing and solver settings for all four. The only result to act on. |
| Size of differences between variants | Indicative |
| Absolute downforce and drag | Rough, could be off by tens of percent (one mesh per variant under the Student cell limit, wall functions, no mesh study); never quoted without that warning |
| Open-wheel flow, wheel wake | Poor; steady RANS cannot capture the unsteady separation off rotating wheels |
| Front/rear aero balance | Rough; floor and diffuser are sensitive to the near-ground mesh |
| Wake at 2 to 3 lengths | Weakest result; the mesh coarsens downstream (only about 750 mesh nodes per half plane beyond 1 length) and RANS smears the wake. Good for comparing variants, not for absolute decay |
