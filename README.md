# Formula Single-Seater

Formula-style single-seater designed in SolidWorks and tested virtually: suspension motion, stress, CFD downforce and drag, and a MATLAB lap-time simulation.

> Template. Fields in angle brackets are filled at Ring 7 with the real numbers from `run_all.m` and the study reports. The hero render goes at the top.

<!-- ![Hero render](media/hero.png) -->

## Why it exists

To design one complete race car from a blank parameter file to a lap time, with every number traceable to a simulation I ran, and to learn SolidWorks, Fluent and MATLAB/Simulink on something I care about. The aero brief was maximum downforce first and an honestly measured wake second. The wings are deliberately bigger than Formula Student rules allow; the proportions are FS, the rules are not.

## What it does

- A parametric CAD assembly driven by one text file (`params/car_params.txt`): change the wheelbase, press Rebuild, the whole car follows.
- SolidWorks Motion bump and steering sweeps that give camber gain, bump steer and motion ratio.
- SolidWorks Simulation: front upright stress with a mesh check, and chassis torsional stiffness.
- Fluent CFD on a half car for four aero variants, with a measured wake on planes 0.5 to 3 car lengths behind.
- A MATLAB lap simulator on four tracks, a Simulink acceleration model that agrees with it, and plots that show what the downforce is worth and what it costs.

## Results

| Headline | Value |
|---|---|
| Lap time, FS autocross, variant C | `<s>` |
| Lap time, fast circuit, variant C | `<s>` |
| Wings worth (A to C), autocross / fast circuit | `<s>` / `<s>` |
| ClA / CdA / L/D, variant C (CFD, 20 m/s) | `<m2>` / `<m2>` / `<>` |
| Max corner speed, R = 120 m, A vs C | `<km/h>` vs `<km/h>` |
| Car one length behind keeps | `<%>` of its downforce |
| Following penalty, fast circuit | `<s>` per lap |
| Chassis torsional stiffness | `<Nm/deg>` at `<kg>` |
| Front upright minimum safety factor | `<>` |
| Camber gain front / rear | `<deg/mm>` / `<deg/mm>` |
| 0 to 100 km/h / 75 m | `<s>` / `<s>` (Simulink `<s>`) |

Plots: `media/cornering_speed_vs_downforce.png`, `media/laptime_contour_fast_circuit.png`, `media/aero_drag_vs_downforce.png`, `media/wake/wake_metrics.png`.

## How it was built

Eight rings, each ending with a check and a report (`docs/ring_report_template.md`, log in `docs/log.md`):

0. Learning ramp: practice parts, first MATLAB script, CFD smoke test.
1. Concept and parameters: `params/car_params.txt`, layout sketch, variant list (`docs/concept.md`).
2. CAD: master layout, spaceframe, suspension, body and wings, CFD bodies.
3. Motion: bump and steering sweeps (`sim/motion/`, `matlab/suspension_plots.m`).
4. Stress: load cases (`matlab/load_cases.m`), upright, chassis torsion (`sim/stress/`).
5. CFD: four variants, mesh and speed checks, wake planes (`cfd/`).
6. Lap time: `matlab/lapsim/`, Simulink 6b (`matlab/simulink/`).
7. Release: renders, this README, v1.0.0.

## What I wanted to learn

`<two or three lines at Ring 7>`

## How to open and run

CAD: open `cad/<assembly>.SLDASM` in SolidWorks 2026 (Simulation and Motion add-ins on). The equations link to `params/car_params.txt`; if the link breaks on a fresh clone, Tools > Equations > Link to external file and pick it again.

MATLAB (R2026a, needs Simulink for the 6b comparison only):

```matlab
run('matlab/run_all.m')      % self-tests, then every analysis; figures in media/
run_all('test')              % self-tests only
```

Scripts whose input does not exist yet (motion CSVs, CFD results) run on synthetic data or the parameter-file estimates and say so in their titles.

## Repository layout

```
params/     car_params.txt (single source of truth) 
cad/        SolidWorks parts and assemblies (git LFS), airfoils/, macros/, practice/
matlab/     accel_test, load_cases, suspension_plots, aero_plots, run_all; common/, lapsim/, simulink/, cfd/, cad/
sim/        motion/ and stress/ exports and reports
cfd/        Fluent guide and journal, geometry/, results/
docs/       work plan, log, concept, ring reports, per-ring write-ups
media/      figures, renders, GIFs
```

## Limits of the simulations

- Lap sim: point mass, no weight transfer or transients, perfect driver. For comparing setups only.
- CFD: steady RANS under 1,000,000 cells. Variant ranking is reasonable; absolute forces are rough; the far wake is the weakest number. Full trust table in `cfd/README.md`.
- Stress: static linear; no fatigue, welds, bolts or bearings.
- Motion: rigid links, no compliance.

## Licence

MIT for the MATLAB scripts and macros (`LICENSE`), CC BY 4.0 for the CAD and renders (`LICENSE-CAD`).
