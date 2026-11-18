# Formula Single-Seater

A Formula-Student-sized electric single-seater, designed from one parameter file to a lap time. The CAD (SolidWorks 2026, built by scripts), the frame and suspension analysis (MATLAB), the aerodynamics (Ansys Fluent, Student licence) and a lap-time simulation (MATLAB, with a Simulink cross-check) all read the same `params/car_params.txt`.

The proportions follow Formula Student, but the rules do not: the wings are larger than the FS rules allow, because the aero brief was maximum downforce first.

![Assembly, iso view](media/views/formula_single_seater_Default_iso.png)

## Rebuild in one command

With SolidWorks 2026 (Student is enough) and Python 3 installed:

```
python tools/sw_run.py rebuild
```

The command:
- closes SolidWorks without saving and starts it fresh;
- builds the chassis weldment from `cad/frame/*.csv` (124 tubes), trims every tube end and checks the result;
- builds the master layout, bodywork and wings, the assembly, and the 24 suspension parts;
- checks suspension clearance over ±30 mm travel and full steering lock, and runs the motion study and the frame beam studies;
- saves the standard views to `media/views/`.

Each step writes a report beside its output and stops at the first failure. The step list and the reports are described in `tools/README.md`.

The frame CSVs and the suspension hardpoints come from MATLAB. After changing the parameters, run these first (MATLAB R2026a, from `matlab/`):

```matlab
addpath('common'); setup_paths();
frame_layout(struct('plot', false, 'write', true));   % cad/frame/frame_nodes.csv, frame_tubes.csv
frame_trims();                                         % cad/frame/frame_trims.csv
load_cases();                                          % sim/stress/load_cases.csv
make_media();                                          % GIF, stress plots, mass and lap tables in media/
run_all('test')                                        % 24 self-tests
```

`run_all` without arguments also re-runs the aero post-processing, which writes into `cfd/results/`.

## Results

All numbers come from the scripts named in the table, as of 2026-11-18. None of them is a measurement on a real car.

| Quantity | Value | Source |
|---|---|---|
| Mass, car without / with driver | 235.6 / 305.6 kg, 41.8 % front, CG height 312 mm | `matlab/mass_budget.m`, `media/mass_table.md` |
| Frame | 124 tubes of 25.4 mm 4130, 49.3 kg (centre-line lengths, no welds) | `matlab/cad/frame_layout.m` |
| Frame torsional stiffness | 1503 Nm/deg (834 before the 10 torsion diagonals added on 2026-11-18); a fused solid model in SOLIDWORKS Simulation gives 1504 (same load case, 2.9 M-node mesh) | `matlab/stress/frame_fe.m` (beam model), `tools/sw_harness/FrameAnalysis.cs` (solid cross-check) |
| Frame, lowest factor of safety on yield | 2.67, bump case (3 g total wheel load), nominal beam stress | `matlab/stress/frame_fe.m`, `docs/stress_frame.md` |
| Camber gain, front / rear | −0.039 / −0.043 deg/mm | `matlab/suspension_geometry.m` |
| Bump steer over ±30 mm, front / rear | 0.010 / 0.021 deg | same |
| Static roll centre, front / rear | 60 / 79 mm | same |
| Motion ratio, front / rear | 0.71 / 0.77 | same |
| Outer ball joint housing to rim barrel, smallest | 4.0 mm (rear upper joint), with a 12.5 mm housing radius assumed | `matlab/suspension_optimise.m` |
| Aero, variant C (maximum wings), half-car CFD | ClA 3.98 m², CdA 1.63 m², L/D 2.44, 45 % on the front axle | `media/cfd/cfd_results.md` |
| Lap time, FS-style autocross, variant C | 61.09 s point-mass, 62.21 s with four-wheel load transfer | `media/lap_time_table.md` |
| Lap time, fast circuit, variant C | 82.58 s point-mass, 82.78 s four-wheel | same |
| Wings worth (A no wings → C), autocross / fast circuit | 5.54 s / 1.59 s | same |
| Skidpad / 75 m acceleration, variant C | 4.89 s / 4.35 s; 0–100 km/h 3.48 s | `matlab/accel_test.m`, lap sim |
| Simulink 75 m model vs MATLAB | 4.3518 s vs 4.3518 s | `matlab/simulink/run_accel_simulink.m` |
| Following one car length behind (variant C) | 64 % of the free-stream dynamic pressure in the follower's window; +2.15 s autocross, +1.23 s fast circuit | CFD wake plane, `matlab/lapsim/lap_experiments.m` |

### Lap times, all four aero variants (point-mass)

| Track | A no wings | B moderate | C maximum | D wake-tuned |
|---|---|---|---|---|
| skidpad | 5.13 s | 4.92 s | 4.89 s | 4.88 s |
| accel 75 m | 4.41 s | 4.34 s | 4.35 s | 4.34 s |
| autocross | 66.62 s | 61.72 s | 61.09 s | 60.75 s |
| fast circuit | 84.17 s | 79.84 s | 82.58 s | 84.34 s |

On the fast circuit the drag of C and D costs more than their downforce gains, because the car is power-limited on the straights (80 kW).

### Frame torsion diagonals: before and after

| | Before | After |
|---|---|---|
| Torsional stiffness (through the suspension links) | 834 Nm/deg | 1503 Nm/deg |
| Frame tubes | 43.5 kg | 49.3 kg |
| Car without driver | 229.1 kg | 235.6 kg |
| Autocross, variant C, point-mass / four-wheel | 60.84 / 62.03 s | 61.09 / 62.21 s |
| Fast circuit, variant C, point-mass / four-wheel | 82.45 / 82.68 s | 82.58 / 82.78 s |

The lap sim treats the chassis as rigid. It therefore shows only the cost of the added mass (+0.25 s on the autocross), not any benefit of the stiffer frame.

The diagonals were chosen by `matlab/stress/frame_diagonal_search.m`: the lightest set that reaches 1500 Nm/deg and clears the driver, battery, motor and diff envelopes. Floor diagonals alone reach 1161 Nm/deg, and floor plus top diagonals reach 1368. The sidepod tops and the front bulkhead plane are also needed.

### Media

| File | What |
|---|---|
| `media/views/*_iso.png` and the other five views | SolidWorks standard views of the chassis, the assembly, the master layout, the suspension (corners and frame only) and the fused analysis frame |
| `media/suspension_bump_steer.gif` | front and rear corner through ±30 mm of travel, then the front corner lock to lock (MATLAB kinematics) |
| `media/frame_stress_cases.png`, `frame_stress_bump.png`, `frame_torsion_diagonals.png`, `frame_fe.png` | frame stress per load case, the bump case on the frame, stiffness by diagonal family, deformed shapes |
| `media/mass_table.md`, `media/lap_time_table.md`, `media/results_table.md` | mass budget, lap times, aero before/after CFD |
| `media/cfd/` | CFD forces, convergence, wake planes |

![Suspension bump and steer](media/suspension_bump_steer.gif)

![Frame stress per load case](media/frame_stress_cases.png)

## Assumptions and limits

These are the things the numbers above depend on that were not measured, or were simplified.

- **Tyres.** Friction is assumed: μ 1.40 at 750 N with a load-sensitivity exponent of 0.10. There is no tyre data behind these values. The lap times and the cornering balance move with both. On the autocross, 10 % less grip costs 3.8 s and 10 % more gains 3.2 s.
- **Aero.**
  - The CFD is a half car, steady RANS (k-ω SST), one mesh per variant, with no mesh-independence or y+ study and no wind-tunnel or track comparison. Only the ranking of the variants is trustworthy; the absolute ClA and CdA may be off by tens of percent.
  - Variant A's downforce did not converge.
  - The front/rear aero split is an estimate. The balance target used for trimming (0.40 front) is a target, not a result.
- **CFD mesh limit.** The Ansys Student licence stops at 1,048,576 cells (measured: above that, Fluent Meshing exits without writing a mesh). The meshes are 0.27 to 1.04 M cells, so the near-wall resolution and the far wake are coarse.
- **Roll centres** are static: computed at ride height and held fixed with roll in the cornering model.
- **No anti-roll bar.** The roll stiffness split (38 % front) comes from the ride frequencies alone; tyre stiffness is ignored.
- **Frame stiffness and stress** come from a MATLAB beam model:
  - rigid joints at the node centres;
  - no weld detail, no stress concentration, no fatigue.
  - It is self-tested against hand calculations for single tubes.
  - **Torsional stiffness is confirmed by a solid model.** A separate analysis-only solid frame (`cad/analysis/frame_analysis.SLDPRT`, built from the same tube data, tube ends overlapping their neighbours by 1 mm and fused into one body) gives 1504 Nm/deg against the beam model's 1503 in the headline case, and 1374 against 1386 with couples at the nodes. Going from a 5 mm to a 4 mm mesh changes this by 0.3 %; a 3 mm mesh failed to mesh on the Student licence (see `docs/stress_frame.md`).
  - **Stresses are not confirmed.** The solid model's peaks sit where the point loads enter and are not used. The frame stresses and factors of safety are the beam model's nominal values.
  - **What neither model includes:** both assume perfectly fused joints, with no welds as built, no brackets and no fabrication tolerances. The real frame will be softer than both by an amount neither can predict. Only a physical torsion test would settle it.
- **Mass and CG.** 24 % of the mass is a placeholder (flag GUESS in `media/mass_table.md`), including the brackets and welds, the inverter, the wings and the bodywork. The CG height is therefore partly a guess too.
- **Lap simulation.**
  - Quasi-steady, perfect driver, no transients.
  - The point-mass model has no load transfer. The four-wheel model adds steady load transfer at the corner limit only.
  - The chassis is rigid in both.
  - Use the lap times to compare set-ups, not to predict a real lap.
- **Suspension.**
  - The kinematics have rigid links and bushings with no compliance.
  - The ball-joint housing size (12.5 mm radius) is an assumption: an Aurora COM-5T spherical bearing (5/16 in bore, 19.05 mm OD) in a 3 mm-wall steel cup.
  - The SOLIDWORKS motion study reaches only +23 mm (front) and +14 mm (rear) of bump, against the ±30 mm asked for. The cause is not found. The ±30 mm clearance check is done instead by the SuspensionCheck step, which poses the corners directly.
  - The rear lower wishbone and pushrod tubes overlap by 7–13 mm³ near their shared outer joint at droop and static (SuspensionCheck warning). The links are modelled as plain tubes meeting at the joint centre; real rod ends and a clevis would set their spacing.
- **Packaging.** The driver is represented by boxes (legs, torso) and a helmet sphere, not a manikin. The pedal box has no envelope of its own; the frame keeps the window between the FS2 cross tubes free for it. The frame clearances are checked against these boxes only.

## Repository layout

```
params/     car_params.txt (single source of truth, with the mass and CG budget), suspension_hardpoints.txt, aero tables
cad/        SolidWorks parts and assemblies, frame/ (node, tube and trim CSVs), analysis/ (fused solid frame for the torsion cross-check), generate/ (Python geometry), macros/
matlab/     run_all, make_media, mass_budget, suspension_geometry, suspension_optimise, load_cases; cad/ (frame_layout, frame_trims),
            stress/ (frame_fe, frame_diagonal_search), lapsim/, simulink/, aero/, cfd/
tools/      sw_run.py and the C# SolidWorks harness (sw_harness/), README with every step
sim/        stress/ and motion/ reports
cfd/        Fluent set-up, journals, results
docs/       log.md (newest summary at the top), stress_frame.md, concept and playbook notes
media/      figures, GIF, tables, SolidWorks views
```

## Licence

MIT for the scripts and macros (`LICENSE`), CC BY 4.0 for the CAD and renders (`LICENSE-CAD`).
