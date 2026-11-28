# cfd/

Ring 5 lives here. Ansys Student 2026 R1 (Fluent), driven entirely from Python (PyFluent); SimScale is the backup.

| Path | What |
|---|---|
| `fluent_halfcar.py` | Mesh and solve one variant without clicks: `.venv/Scripts/python cfd/fluent_halfcar.py all C`. See `fluent_halfcar_setup.md`. `--set te_size=1.5` (off by default): local face size on the narrow flap trailing edges, the fix that meshed G (slot study in `fluent_halfcar_setup.md`). |
| `postprocess.py` | Forces and wake planes of every run to tables and plots; `--update-variants` puts the CFD numbers into `params/aero_variants.csv` (the lap sim's aero table). |
| `visualise.py` | Pictures and films of A, B (= run B_AB), C (= run CP), D (= run D_AB) from the saved case and data files, no Fluent licence needed: `.venv/Scripts/python cfd/visualise.py all` (about 8 min once the export cache exists). Steps `export`, `stills`, `anims`, `compare`, `smoke`; `--selftest`. Writes `../media/cfd/vis/`. |
| `vis_common.py`, `vis_render.py`, `vis_smoke.py` | Used by `visualise.py`: streamline tracing and captions; stills, orbit / sweep / build-up films and the A-D comparison; the smoke tunnel films. |
| `support_forces.py`, `support_flow.py`, `support_table.py` | Wing supports (rear 2026-11-26, front 2026-11-27; `--front`, zone `car_fws`, `support_table.py` for the comparison table). `support_forces.py`: force on the supports from a per-face export of a saved run, checked against Fluent's own zone reports (picks CP's pylon out of `car_rw`). `support_flow.py`: planes next to the support, `../media/cfd/supports/support_flow.png`. |
| `vis_supports.py`, `support_charts.py`, `support_summary.py` | Wing-support pictures (2026-11-28), no Fluent licence: `vis_supports.py all` (local 4 mm / 2 mm grids around the supports in `cases/vis/<run>/sup_*`, then side-by-side particle films of the rear supports CP_bl1/E/F/H and the front CP_bl1/J, `supports_compare.gif` for the README, and the CP_bl1 vs CPFF wake film); `support_charts.py` (support drag, totals with the 2.2 % band, lap time and balance); `support_summary.py` (one-page image). All write `../media/cfd/supports/`; `--selftest` on each. |
| `explore.py` | Opens one result ready to explore: `.venv/Scripts/python cfd/explore.py C` (CFD-Post with car Cp, streamlines, wake planes at 1/2/3 L, symmetry speed) or `... C --fluent` (Fluent window with case and data read). `--test` checks it without a window. |
| `cases/vis/<run>/` | Cache of `visualise.py export` (car surface, 12.5 mm and 30 mm resampled grids, about 260 MB per run) and the CFD-Post session files. Ignored by git; remade on demand. |
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

**Status 2026-11-18:**
- Mesh checks on C (volume coarsening, wake-window refinement, 1 prism layer) and on D (1 layer): ClA moves by under 0.3 %, CdA by under 2.4 %, and the B/C/D lap ranking does not change.
- The force-based stop now works.
- Variant CP (SolidWorks bodywork): ClA −2.3 %, CdA +1.8 % against C.
- Details are in `fluent_halfcar_setup.md`.
- `params/aero_variants.csv`: row C now comes from run CP, the SolidWorks bodywork (`TABLE_RUN` in `postprocess.py`, user's choice 2026-11-18). A, B and D are still on the older CFD bodywork. The following-car penalty still uses C's wake planes.
- New actions in `fluent_halfcar.py`: `post` (re-export wake planes, window boxes and y+ from a saved run) and `cont` (continue a run). New options: `--boi win`, `--set KEY=VALUE`.

**Status 2026-11-25:** pictures and films of the saved results in `../media/cfd/vis/` (`visualise.py`), and `explore.py` to open a result in CFD-Post or Fluent. No new solves. The surface Cp is that of the wall-adjacent cell, and the 3D fields are resampled onto 12.5 mm and 30 mm grids, so the pictures are a little smoother than Fluent's own. Like every number here they are steady RANS on a Student mesh: only the ranking of the variants is trustworthy.

**Status 2026-11-25 (later):**
- B and D are re-solved on CP's as-built bodywork as runs B_AB and D_AB, and they now feed rows B and D of `params/aero_variants.csv` (`TABLE_RUN` in `postprocess.py`). The old rows are in `params/aero_variants_simplified_BD.csv`.
- **D_AB's diffuser is 12°, not 14°**, and D_AB has 1 prism layer; CP_bl1 is CP with 1 layer, for comparison. See `geometry_notes.md`.
- `visualise.py` shows B_AB and D_AB as B and D. The old B and D pictures are in `../media/cfd/vis_old_simplified/` (git-ignored).
- Only the ranking is trustworthy.

**Status 2026-11-26:**
- Rear-wing support variants E, F, H (new letters; the old variant E wake test is deleted) were solved as E_bl1, F_bl1 and H_bl1 against CP_bl1.
- Each support has its own zone `car_rws`. G did not mesh.
- Results: `../media/cfd/supports/wing_supports_results.md`. Only the ranking is trustworthy.

**Status 2026-11-27:**
- Front-wing supports: J_bl1 (lens front supports) and CPFF_bl1 (J front plus F rear) were solved against CP_bl1. Each front support has its own zone `car_fws`. K did not mesh.
- CP_bl1r is a repeat of CP_bl1 with `--set boi_near=39`, as a noise estimate.
- `support_table.py` writes the comparison table (`results/support_table.csv`).
- `support_flow.py --front` draws `../media/cfd/supports/support_flow_front.png`.
- Results: the front-wing section of `../media/cfd/supports/wing_supports_results.md`.

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
| Absolute downforce and drag | Rough. The mesh checks move them by under 0.3 % (ClA) and 2.4 % (CdA), but the surface mesh could not be varied, and model error (steady RANS, wall functions at y+ 30 to 150, no test data) is unmeasured: could still be off by tens of percent; never quoted without that warning |
| Open-wheel flow, wheel wake | Poor; steady RANS cannot capture the unsteady separation off rotating wheels |
| Front/rear aero balance | Rough; floor and diffuser are sensitive to the near-ground mesh |
| Wake in the following car's window (`results/wake_boxes.csv`) | Deficit and TKE change by under 10 % when the window mesh is refined to 50 mm (C_w against C); vorticity changes by 30 %, so it is mesh-dependent. E's wake numbers are snapshots of an unsteady flow (about 10 %) |
| Wake at 2 to 3 lengths | Weakest result; the mesh coarsens downstream (only about 750 mesh nodes per half plane beyond 1 length) and RANS smears the wake. Good for comparing variants, not for absolute decay |
