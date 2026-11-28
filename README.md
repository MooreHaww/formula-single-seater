# Formula Single-Seater

A Formula-Student-sized electric single-seater, designed from one parameter file to a lap time. The CAD (SolidWorks 2026, built by scripts), the frame and suspension analysis (MATLAB), the aerodynamics (Ansys Fluent, Student licence) and a lap-time simulation (MATLAB, with a Simulink cross-check) all read the same `params/car_params.txt`.

The proportions follow Formula Student, but the aero package was sized for maximum downforce first and was not checked against the FS rules: the wings are larger than an FS car's, and the rear wing reaches about 1.55 m above the ground (`cfd/geometry_notes.md`, variant C). No rule check was made.

![SolidWorks build-up of the final car (CP with the F and J wing supports)](media/showcase/car_buildup.gif)

![CFD comparison of the aero variants A, B, C and D](media/cfd/vis/compare_ABCD.gif)

Both are simulations: a CAD model built by script, and half-car CFD. Nothing here was built or tested.

![Assembly, iso view](media/views/formula_single_seater_Default_iso.png)

## Rebuild in one command

Requirements:
- SolidWorks 2026 (Student is enough);
- Python 3;
- the .NET SDK: `tools/sw_run.py` compiles the C# harness with the SDK's Roslyn compiler (`C:\Program Files\dotnet\sdk`) and stops without it;
- build123d for the BuildBodies step (bodywork and wing parts): either the project venv (`py -3.12 -m venv .venv`, then `.venv/Scripts/python -m pip install -r cfd/requirements.txt`) or `uvx`. Without it the rebuild stops at BuildBodies.

Then:

```
python tools/sw_run.py rebuild
```

The CAD files (SolidWorks parts and assemblies, STEP files) are stored with Git LFS. If cloning them fails (for example because the LFS quota is used up), the whole CAD can be regenerated with `python tools/sw_run.py rebuild`. Two sets are not part of the rebuild: the fused analysis frame (`python tools/sw_run.py FrameAnalysis`) and the CFD STEP files in `cad/step/cfd/` (`.venv/Scripts/python cad/generate/cfd_variants.py`).

The command:
- closes SolidWorks without saving and starts it fresh;
- builds the chassis weldment from `cad/frame/*.csv` (123 tubes), trims every tube end and checks the result;
- builds the master layout, bodywork and wings, the assembly, and the 24 suspension parts;
- checks suspension clearance over ±30 mm travel and full steering lock, and runs the motion study;
- sets up the SolidWorks Simulation beam studies on the production weldment (torsion, braking, cornering). **They do not solve** ("No load or prescribed displacement is defined", `sim/stress/chassis_statics_report.txt`). The frame stiffness and stress numbers come from the MATLAB beam model (`matlab/stress/frame_fe.m`), cross-checked for torsion by the separate fused-solid analysis frame in SolidWorks Simulation (`FrameAnalysis`, not part of the rebuild);
- saves the standard views to `media/views/`.

Each step writes a report beside its output and stops at the first failure. The step list and the reports are described in `tools/README.md`.

The frame CSVs and the suspension hardpoints come from MATLAB. After changing the parameters, run these first (MATLAB R2026a, from `matlab/`):

```matlab
addpath('common'); setup_paths();
frame_layout(struct('plot', false, 'write', true));   % cad/frame/frame_nodes.csv, frame_tubes.csv
frame_trims();                                         % cad/frame/frame_trims.csv
load_cases();                                          % sim/stress/load_cases.csv
make_media();                                          % GIF, stress plots, mass and lap tables in media/
run_all('test')                                        % 27 self-tests
```

`run_all` without arguments also re-runs the aero post-processing, which writes into `cfd/results/`.

## Results

All numbers come from the scripts named in the table, as of 2026-11-25. None of them is a measurement on a real car.

| Quantity | Value | Source |
|---|---|---|
| Mass, car without / with driver | 232.6 / 302.6 kg, 42.3 % front, CG 895 mm behind the front axle, 320 mm high (2026-11-28, reconciliation: the budget positions of the wings, floor, bodywork, cockpit, corners, chain drive and driver now come from the CAD, and the budget CG agrees with the CAD CG within 0.3 mm; before it, 902 / 309 mm. Also 2026-11-28: the four wing supports, 1.73 kg, have their own lines and are taken off the wing guesses, so the total is the v1.0.0 total; the CG height moved from 311 to 309 mm. The lap times and loads in this README were computed with the v1.0.0 CG and not re-run) | `matlab/mass_budget.m`, `media/mass_table.md` |
| Frame | 123 tubes of 25.4 mm OD (material: see below), 46.26 kg as the trimmed SOLIDWORKS weldment (48.7 kg on centre-line lengths, which count each coped end twice); no welds or brackets (6.4 kg allowance on its own line) | `params/car_params.txt`, `cad/chassis/check_chassis_report.txt` (measured), `matlab/cad/frame_trimmed_mass.m` (CG) |
| Frame torsional stiffness | 1476 Nm/deg, 1.6 % under the 1500 target (834 without the 9 diagonal tubes; 1503 with a tenth, RT1-RRK, removed on 2026-11-25 because it met its cross tubes at 5.4 deg); a fused solid model in SOLIDWORKS Simulation gives 1470 (same load case, 2.9 M-node mesh) | `matlab/stress/frame_fe.m` (beam model), `tools/sw_harness/FrameAnalysis.cs` (solid cross-check) |
| Frame, lowest factor of safety on yield | 2.62, bump case (3 g total wheel load), nominal beam stress, against 4130's yield (435 MPa): it assumes 4130 tube | `matlab/stress/frame_fe.m`, `docs/stress_frame.md` |
| Camber gain, front / rear | −0.039 / −0.043 deg/mm | `matlab/suspension_geometry.m` |
| Bump steer over ±30 mm, front / rear | 0.010 / 0.021 deg | same |
| Static roll centre, front / rear | 60 / 79 mm | same |
| Motion ratio, front / rear | 0.71 / 0.77 | same |
| Outer ball joint housing to rim barrel, smallest | 4.0 mm (rear upper joint), valid only for the assumed 12.5 mm housing radius: a bigger rod end reduces it one-for-one | `matlab/suspension_optimise.m` |
| Aero, as built (CP: variant C's wings on the SOLIDWORKS nose, sidepods and floor plate), half-car CFD | ClA 3.89 m², CdA 1.66 m², L/D 2.34, 43 % on the front axle (steady RANS that does not settle: the downforce oscillates in a 2.5 % band and its mean is used) | `media/cfd/cfd_results.md`, `params/aero_variants.csv` |
| Lap time, FS-style autocross, as built (CP) | 61.12 s point-mass, 62.12 s with four-wheel load transfer | `media/lap_time_table.md`, `media/results_table.md` |
| Lap time, fast circuit, as built (CP) | 82.97 s point-mass, 83.08 s four-wheel | same |
| Wings worth (A no wings → C, like for like), autocross / fast circuit | 5.60 s / 1.63 s | same |
| Skidpad / 75 m acceleration, as built (CP) | 4.89 s / 4.35 s; 0–100 km/h 3.47 s | `matlab/accel_test.m`, lap sim |
| Simulink 75 m model vs MATLAB (CP) | 4.3499 s vs 4.3499 s | `matlab/simulink/run_accel_simulink.m` |
| Following one car length behind (CP) | 64 % of the free-stream dynamic pressure in the follower's window (CP's own wake); +2.14 s autocross, +1.21 s fast circuit | CFD wake plane, `matlab/lapsim/lap_experiments.m` |
| Cornering balance at a 45 m radius (CP, four-wheel) | 112.9 km/h, rear axle at its limit first, balance −6.5 % (front use minus rear use); neutral with 39 % of the aero load on the front axle against the 43 % CP has | `matlab/lapsim/cornering_balance_study.m`, `media/cornering_balance.md` |

**Frame material.** The CAD weldment is built in **AISI 1020**, so the CAD frame mass uses 1020's density. The stress model (`frame_fe`) and the solid check (`FrameAnalysis`) use **4130 normalised** (yield 435 MPa), and every factor of safety is measured against 4130's yield, so it assumes 4130 tube. 1020's yield is lower (about 350 MPa); the densities are nearly equal. The CAD material was not changed.

### Lap times, aero variants (point-mass)

CP is the car as built: C's wings on the SOLIDWORKS nose, sidepods and 10 mm floor plate. It is the reference everywhere else in the repo (load cases, stress cases, cornering balance, sensitivity). Since 2026-11-25, **B and D are on the same as-built bodywork as CP** (CFD runs B_AB and D_AB), so B, D and CP compare like for like. A and C are still on the older CFD bodywork.

**D's diffuser is 12° in this comparison, not 14°.** The 14° diffuser would not mesh on the as-built bodywork. D_AB was also meshed with 1 prism layer instead of 2, to stay under the cell limit; on the old bodywork that change moved ClA by −0.2 % and CdA by −1.0 %. The old B and D results (older bodywork, 14° diffuser) are in `params/aero_variants_simplified_BD.csv`.

| Track | A no wings | B moderate, as built | C maximum | D wake-tuned, as built, 12° diffuser | **CP as built** |
|---|---|---|---|---|---|
| skidpad | 5.12 s | 4.92 s | 4.89 s | 4.89 s | **4.89 s** |
| accel 75 m | 4.41 s | 4.34 s | 4.35 s | 4.34 s | **4.35 s** |
| autocross | 66.59 s | 61.72 s | 60.99 s | 60.90 s | **61.12 s** |
| fast circuit | 84.15 s | 79.90 s | 82.52 s | 84.26 s | **82.97 s** |

On the fast circuit the drag of C and D costs more than their downforce gains, because the car is power-limited on the straights (80 kW). The SOLIDWORKS bodywork costs 0.13 s on the autocross and 0.45 s on the fast circuit against C (ClA −2.3 %, CdA +1.6 %).

### B, D and CP on the same as-built bodywork

From half-car CFD at 20 m/s. Steady RANS on a Student mesh, so **only the ranking is trustworthy**. Wake q-ratio is the follower's window average at 1 / 2 / 3 car lengths behind the rear axle (1 = clean air; lower = dirtier air for the follower, which is our goal). Lap times are point-mass. The following penalty puts the same car behind, one length back, in that variant's own wake.

| | B (as built) | D (as built, **12° diffuser**) | CP (as built) | B old | D old |
|---|---|---|---|---|---|
| ClA / CdA (m²) | 3.36 / 1.32 | 4.03 / 1.76 | 3.89 / 1.66 | 3.43 / 1.29 | 4.20 / 1.77 |
| L/D, front axle share | 2.54, 0.43 | 2.29, 0.39 | 2.34, 0.43 | 2.65, 0.45 | 2.37, 0.38 |
| Wake q-ratio at 1 / 2 / 3 L | 0.67 / 0.89 / 0.95 | 0.65 / 0.92 / 0.98 | 0.64 / 0.92 / 0.98 | 0.66 / 0.86 / 0.93 | 0.65 / 0.92 / 0.97 |
| Skidpad / autocross / fast circuit (s) | 4.92 / 61.72 / 79.90 | 4.89 / 60.90 / 84.26 | 4.89 / 61.12 / 82.97 | 4.92 / 61.64 / 79.79 | 4.88 / 60.65 / 84.31 |
| Following penalty, autocross / fast circuit (s) | +1.69 / +1.14 | +2.14 / +1.14 | +2.14 / +1.21 | +1.80 / +1.22 | +2.21 / +1.09 |

On the as-built bodywork:
- B loses 2 % of its old downforce and D 4 %. Part of D's loss is the shallower 12° diffuser.
- The ranking is unchanged from the old bodywork:
  - D is fastest on the skidpad and autocross, but its lead over CP (0.01 s and 0.22 s) comes from a downforce difference smaller than CP's own run-to-run spread (see below), so D and CP are not separated.
  - B is fastest on the power-limited fast circuit.

**Dirty air is the goal:** we want the following car to be disturbed, so a lower q-ratio and a bigger following penalty are better for us.
- At 1 car length, CP and D disturb a follower most (q-ratio 0.64 / 0.65, autocross penalty +2.14 s each), and B least (0.67, +1.69 s).
- At 2 and 3 lengths, B's wake persists slightly longer (0.89 / 0.95, against 0.92 / 0.98 for CP and D).

**CP is the chosen car.** D's downforce lead over CP on the as-built hull (ClA +1.3 %, D_AB against CP_bl1) is smaller than the 2.2 % between CP's own two runs (CP and CP_bl1), so D and CP cannot be told apart on downforce.

Full tables: `media/cfd/cfd_results.md`, `media/results_table.md`, `media/lap_as_built_BD.csv`.

### Frame torsion diagonals: before and after

| | Before | After |
|---|---|---|
| Torsional stiffness (through the suspension links) | 834 Nm/deg | 1476 Nm/deg |
| Frame tubes (trimmed-weldment mass; centre-line 43.5 / 48.7 kg) | 41.4 kg | 46.26 kg |
| Car without driver | 227.0 kg | 232.6 kg |
| Autocross, as built (CP), point-mass / four-wheel | 60.90 / 61.97 s | 61.12 / 62.12 s |
| Fast circuit, as built (CP), point-mass / four-wheel | 82.87 / 82.99 s | 82.97 / 83.08 s |

The lap sim treats the chassis as rigid. It therefore shows only the cost of the added mass (+0.22 s on the autocross), not any benefit of the stiffer frame.

The diagonals were chosen by `matlab/stress/frame_diagonal_search.m`: the lightest set that reaches 1500 Nm/deg, clears the driver, battery, motor and diff envelopes, and meets no frame tube at under 10 deg. Floor diagonals alone reach 1161 Nm/deg, and floor plus top diagonals reach 1354. The sidepod tops and the front bulkhead plane are also needed. The search's chosen set had a tenth tube, RT1-RRK (rear top, ahead of the rocker mount). It was removed on 2026-11-25: it met the RT1 and RRK cross tubes, 60 mm apart, at 5.4 deg, so it could only be built as a gouged joint about 270 mm long at each end. Without it the frame gives 1476 Nm/deg. The lightest way back to 1500 is its twin behind the rocker mount (RRK-RT2, 1501 Nm/deg, +0.59 kg, 12.3 deg joints); nothing lighter reaches the target. It was not added.

### Media

| File | What |
|---|---|
| `media/views/*_iso.png` and the other five views | SolidWorks standard views of the chassis, the assembly, the master layout, the suspension (corners and frame only) and the fused analysis frame (re-saved on 2026-11-25 from the 123-tube analysis part). `media/views/` is git-ignored except `formula_single_seater_Default_iso.png` (the picture at the top): the other views are local only |
| `media/suspension_bump_steer.gif` | front and rear corner through ±30 mm of travel, then the front corner lock to lock (MATLAB kinematics) |
| `media/frame_stress_cases.png`, `frame_stress_bump.png`, `frame_torsion_diagonals.png`, `frame_fe.png` | frame stress per load case, the bump case on the frame, stiffness by diagonal family, deformed shapes |
| `media/mass_table.md`, `media/lap_time_table.md`, `media/results_table.md` | mass budget, lap times, aero before/after CFD |
| `media/cfd/` | CFD forces, convergence, wake planes |

![Frame stress per load case](media/frame_stress_cases.png)

## Showcase

Every film below is a simulation or a CAD model. Nothing in them was built or tested.

### Car build-up


https://github.com/user-attachments/assets/e47ae17a-36b9-46d6-aa46-5714b42f49ec


The as-built car (CP) assembled stage by stage in SolidWorks, from the frame tubes to the rear wing (CAD model, from a fixed camera). The rockers, dampers, steering, brakes, motor and drive, batteries, electronics, seat and driver are packaging envelopes (simple boxes, cylinders and a sphere with their budget masses), not designed parts.

### Suspension

![Suspension bump and steer](media/suspension_bump_steer.gif)

The front and rear corners through ±30 mm of wheel travel, then the front corner from lock to lock (MATLAB kinematics simulation).

### Aerodynamics: A-B-C-D comparison

https://github.com/user-attachments/assets/ba47a421-25e1-4267-8622-a06a7c22719d

The four aero variants side by side: A, B, C (the chosen car's run, CP) and D, from half-car CFD (Ansys Fluent simulation).

### Aerodynamics: smoke tunnel A-B-D side by side

https://github.com/user-attachments/assets/eac0df49-c4b6-4f87-930a-9f305555b851

Simulated smoke streaks past variants A, B and D, side by side (CFD simulation).

### Aerodynamics: smoke tunnel of the chosen car

https://github.com/user-attachments/assets/30718f1d-2759-4b36-a5e1-756d0a409edb

Simulated smoke streaks past the chosen car, CP (C's wings on the as-built bodywork; labelled C in the film), from half-car CFD (simulation).

### Aerodynamics: wing supports

![Rear-wing supports in CFD: CP's flat plate against three lens sections](media/cfd/supports/supports_compare.gif)

Simulated particle streaks past the rear-wing support: CP's flat 16 mm plate against three lens sections (E, F, H), seen from the side and in section from above (half-car CFD, steady RANS; v1.0.0 has no supports; since 2026-11-28 the CAD has F at the rear and J at the front). Numbers and limits: `media/cfd/supports/wing_supports_results.md`.

### Aerodynamics: the final car against C

![Smoke tunnel: C (run CP) above the final car FINAL](media/cfd/vis/smoke_C_FINAL.gif)

Simulated smoke streaks past C (run CP) and the final car FINAL (C's wings with the F rear and J front wing supports; CFD only), same seeds and camera. FINAL ran with 1 prism layer (2 layers went over the Student cell limit). Against CP_bl1 (also 1 layer) it has ClA +3.9 %, beyond the 2.2 % noise, with CdA +1.0 % and the aero balance 3 points further rearward. Steady RANS, one run per variant: only the ranking is trustworthy. Numbers: section "Final car" of `media/cfd/cfd_results.md`. The lap sim still uses CP until the CAD mass is updated.

### Lap-time simulation



https://github.com/user-attachments/assets/4eaeda68-8c1b-4781-bf8a-4aa6db40e209


https://github.com/user-attachments/assets/28090279-5a15-492d-81df-d57c260b1b90


The as-built car (CP) round the autocross and the fast circuit in real time, with speed, lateral and longitudinal g and the lap clock (MATLAB lap-time simulation, four-wheel model).

## Assumptions and limits

These are the things the numbers above depend on that were not measured, or were simplified.

**Nothing in this repository has been built or tested physically. Every number is from a model.**

- **Tyres.** Friction is assumed: μ 1.40 at 750 N with a load-sensitivity exponent of 0.10. There is no tyre data behind these values. Every lap time, the cornering balance and the frame load cases (`sim/stress/load_cases.csv`, same μ) depend on these two numbers. On the autocross, 10 % less grip costs 3.8 s and 10 % more gains 3.2 s. The sign of the cornering balance (rear axle limits first) has not been checked against a different load sensitivity.
- **Aero.**
  - The CFD is a half car, steady RANS (k-ω SST), one mesh per variant, with no wind-tunnel or track comparison. Only the ranking of the variants is trustworthy; the absolute ClA and CdA may be off by tens of percent.
  - There is no full mesh-independence study. Mesh checks on variant C: coarser non-wing surfaces moved ClA −0.3 % and CdA −0.1 %; 1 prism layer instead of 2 moved ClA +0.1 % and CdA −2.4 %; wake refinement boxes −0.1 %. The wing surface mesh could not be coarsened (the slots stop meshing), and the cell limit leaves no room to refine it. y+ medians are about 28–54 on the car's surfaces and 70–98 on the wheels, so the walls are on wall functions, not a resolved sublayer (`media/cfd/cfd_results.md`).
  - The ranking itself is not robust where two variants are closer than the measured layer and mesh effect: CP's own 1-layer run moved ClA by +2.2 %, more than D's lead over CP.
  - Variant A's downforce did not converge.
  - B and D were re-solved on the as-built bodywork (runs B_AB, D_AB). **D's diffuser there is 12°, not D's 14°:** at 14° the diffuser roof grazes the as-built hull, and the two fixes tried failed to mesh. D_AB has 1 prism layer instead of 2 (cell limit). A and C stay on the older CFD bodywork.
  - **Wing supports (front and rear).** Since 2026-11-28 the CAD has the lens supports the CFD chose (F rear, J front; `docs/log.md`); v1.0.0 has none. The front wing's nearest gap to the nose is about 38 mm (flap 2), and mounting is not designed for either wing. The CFD model is different. `cad/generate/cfd_variants.py` adds idealised pylons to both wings, fused into the one car solid:
    - front wing: one flat plate each side, 16 mm thick (Y 60 to 76 mm), running from the main element's middle line (72 to 93 % of its chord) up to Z 230 mm, into the nose. It is counted in the front-wing force zone.
    - rear wing: one flat plate each side, 16 mm thick, 260 mm chord, 150 mm from the centreline, running from 300 mm above the ground up into the main element. It is counted in the rear-wing force zone.

    So the aero results include the drag and interference of these idealised pylons only, not of a designed mount; real mounts would differ.
  - The front/rear aero split is an estimate. The balance target used for trimming (0.40 front) is a target, not a result.
- **Wing supports in the CAD.** The supports are not structurally designed: loads, stiffness, strength, flutter and the mount hardware are not worked out (geometry and sandwich mass only). The CFD's rear wing sits 19.4 mm further back than the CAD's (main-element leading edge X 1606.9 against 1587.5; the CFD cuts the trailing edges at 0.97 c). The CAD supports keep the CFD's absolute X, so the CAD and CFD supports match but the wings around them do not, by 19.4 mm.
- **CFD mesh limit.** The Ansys Student licence stops at 1,048,576 cells (measured: above that, Fluent Meshing exits without writing a mesh). The meshes are 0.27 to 1.04 M cells, so the near-wall resolution and the far wake are coarse.
- **Roll centres** are static: computed at ride height and held fixed with roll in the cornering model.
- **No anti-roll bar.** The roll stiffness split (38 % front) comes from the ride frequencies alone; tyre stiffness is ignored.
- **SolidWorks Simulation does not solve on the production weldment.** The beam studies (ChassisStatics: torsion, braking, cornering) are set up but do not solve ("No load or prescribed displacement is defined"). The only SolidWorks results are on the separate fused-solid analysis frame, for torsion only.
- **Frame material.** The CAD weldment is AISI 1020; the stress model and the solid check use 4130 normalised (yield 435 MPa). The factors of safety are for 4130 and assume 4130 tube.
- **Frame below target.** The frame is 24 Nm/deg under its own 1500 Nm/deg target, by decision (2026-11-25).
- **Frame stiffness and stress** come from a MATLAB beam model:
  - rigid joints at the node centres;
  - no weld detail, no stress concentration, no fatigue.
  - It is self-tested against hand calculations for single tubes.
  - **Torsional stiffness is confirmed by a solid model.** A separate analysis-only solid frame (`cad/analysis/frame_analysis.SLDPRT`, built from the same tube data, tube ends overlapping their neighbours by 1 mm and fused into one body) gives 1470 Nm/deg against the beam model's 1476 in the headline case, and 1350 against 1365 with couples at the nodes (123 tubes, 2026-11-25). The mesh study was done on the 2026-11-18 frame (124 tubes, with RT1-RRK): going from a 5 mm to a 4 mm mesh changed the result by 0.3 % or less, and a 3 mm mesh failed to mesh on the Student licence. The 123-tube frame was solved at 4 mm only (see `docs/log.md` and `docs/stress_frame.md`).
  - **Stresses are not confirmed.** The solid model's peaks sit where the point loads enter and are not used. The frame stresses and factors of safety are the beam model's nominal values.
  - **What neither model includes:** both assume perfectly fused joints, with no welds as built, no brackets and no fabrication tolerances. The real frame will be softer than both by an amount neither can predict. Only a physical torsion test would settle it.
- **Mass and CG.** 24 % of the mass is a placeholder (flag GUESS in `media/mass_table.md`), including the inverter, the wings and the bodywork. The 6.4 kg for brackets and welds is a guess (about 13 % of the centre-line frame) and is not drawn. The CG height is therefore partly a guess too. Placing each budget mass at its CAD body or envelope gives a CG of 895.1 mm / 319.6 mm (with driver; 42.25 % front); the budget gives 894.9 / 319.9 (`cad/generate/cad_cg_report.txt`). On 2026-11-28 the budget positions that were wrong (front wing and bodywork about 400 mm too far back, driver 50 mm forward and 59 mm low, chain drive, corners, cockpit, rear wing, floor) were set from the CAD; before that the budget said 902 / 309. The driver is the `frame_layout.m` pose with uniform-density boxes: a segment model of the same pose puts the driver 16 mm further back and 36 mm higher, which would move the car's CG about +4 mm in x and +8 mm in z.
- **Lap simulation.**
  - Quasi-steady, perfect driver, no transients.
  - The point-mass model has no load transfer. The four-wheel model adds steady load transfer at the corner limit only.
  - The chassis is rigid in both. The frame stiffness (1476 Nm/deg) and its loss without RT1-RRK do not enter any lap time; the lap sim only sees the frame's mass.
  - Use the lap times to compare set-ups, not to predict a real lap.
- **Suspension.**
  - The kinematics have rigid links and bushings with no compliance.
  - The ball-joint housing size (12.5 mm radius) is an assumption: an Aurora COM-5T spherical bearing (5/16 in bore, 19.05 mm OD) in a 3 mm-wall steel cup.
  - The SOLIDWORKS motion study reaches only +23 mm (front) and +14 mm (rear) of bump, against the ±30 mm asked for. The cause is not found. The ±30 mm clearance check is done instead by the SuspensionCheck step, which poses the corners directly.
  - The rear lower wishbone and pushrod tubes overlap by 7–13 mm³ near their shared outer joint at droop and static (SuspensionCheck warning). The links are modelled as plain tubes meeting at the joint centre; real rod ends and a clevis would set their spacing.
- **Packaging.** The driver is represented by boxes (legs, torso) and a helmet sphere, not a manikin. Since 2026-11-28 these and the other unmodelled systems are in the CAD assembly as packaging envelopes (`env_*`, `cad/generate/envelopes.py`): space reservations with their budget masses, not designed parts. They show 30 packaging clashes, 22 static and 8 over wheel travel (rockers in their mount nodes, chain through the rear cross tubes, motor 25 mm into the driver's torso box, halfshafts through the rear pushrods, and more), listed with suggested fixes in `docs/buildup_audit.md` and not fixed. The pedal box has no envelope of its own; the frame keeps the window between the FS2 cross tubes free for it. The frame clearances are checked against these boxes only.

## Future work

- **Design the wing mountings (front and rear).** Since 2026-11-28 the CAD has the CFD's F (rear) and J (front) supports as geometry: CFRP skin over a foam core, 1.73 kg for the four, the rear pair standing on the frame tube RT2_cross, the front pair between the wing and the nose. Their structure (loads, stiffness, flutter) and the mount hardware are not designed. The CFD has idealised flat pylons on both wings: front, one each side from the main element into the nose; rear, one each side from 300 mm above the ground into the main element. These are not a design.
- **Wing supports: rear wing, first CFD round (2026-11-26; CFD only, not in CAD).**
  - **What was run.** Three rear-wing supports were compared in the half-car CFD on the as-built car, against CP's idealised flat pylon. All four runs had 1 prism layer (cell limit), so the reference is CP_bl1. Each support has the pylon's envelope: 228 mm chord, 16 mm thick, two per car. The three sections:
    - E: lens;
    - F: lens with a rounded front edge;
    - H: lens with a flared blunt tail.
  - **The ridged support (G) could not be meshed** in three attempts (the failures were at the wing slots). It was meshed and run later with a mesh fix (finishing round below).
  - **Found** (steady RANS, only the ranking is trustworthy):
    - The lens supports keep the flow attached where the flat plate separates.
    - The support's own drag falls from 4.3 N (half car) to 0.8 N (E) and 0.4 N (F); H's blunt tail costs 2.8 N.
    - The rear wing above them carries 7 to 9 % more downforce, and total ClA rises 4.2 % (E) and 4.4 % (F), about twice CP's 2.2 % run-to-run spread. So CP's ClA probably carries a penalty of about 4 % from its idealised pylon.
    - Total drag and the wake behind the car do not change measurably.
    - The aero balance moves rearward, from 43 % to about 40 % front.
    - No support makes downforce itself.
  - **Would build:** F (lens, 5 mm front-edge radius).
  - **Lap time and balance with F: a sensitivity result for the next version, not the released car.** CP stays the default aero car everywhere (the CAD got the F and J supports on 2026-11-28). Method:
    - aero row `CPF` in `params/aero_variants.csv` (run F_bl1, marked CFD only);
    - compared with CP_bl1 (same 1-layer mesh settings), with the same car, tyres and lap-sim settings (`matlab/lapsim/support_sensitivity.m`, `media/support_sensitivity.md`);
    - a difference counts only if it is larger than the effect of CP's 2.2 % aero spread on that result.

    Results:
    - F's extra rear downforce (ClA +4.5 %, front share 0.431 to 0.393) makes the car faster on the skidpad (-0.01 s point-mass, -0.03 s four-wheel) and the autocross (-0.32 s / -0.61 s). Both are larger than the spread (0.005 s and 0.13 s).
    - It moves the 45 m cornering balance from -6.2 % (rear axle at its limit first) to +0.4 % (front first, nearly neutral), and the 45 m grip speed from 113.8 to 117.9 km/h. Both are larger than the spread (1.5 points of balance).
    - On the fast circuit it is slower (+0.20 s / +0.13 s). That comes from its CdA +1.3 % and is inside the spread (0.51 s), so it is not claimed.
  - **Not done yet:**
    - 2 prism layers;
    - yaw;
    - structure;
    - CAD.
  - **Details:** `media/cfd/supports/wing_supports_results.md` and `docs/wing_supports_plan.md`.
- **Wing supports: front wing, second CFD round (2026-11-27; CFD only, not in CAD).**
  - **Limits:**
    - The released v1.0.0 has no supports on either wing (the CAD has F and J since 2026-11-28).
    - These are CFD results with one run per variant.
    - The runs are steady RANS, so only the ranking is trustworthy.
  - **What was run.** CP's flat front pylons (16 mm plates, 84 mm chord, only 60-100 mm exposed between the wing and the nose) were replaced in the same envelope by:
    - J: F's lens with a round front edge;
    - CPFF: J at the front plus F at the rear.
    - A pointed lens (K) failed to mesh in three attempts, at the wing slots and not at the support. It was run later with a mesh fix (finishing round below).
    - A repeat of CP_bl1 with a 1 mm change in a mesh refinement box moved ClA by 0.9 % and CdA by 0.7 %: a second noise estimate, inside CP's 2.2 % spread.
  - **Found:**
    - J cuts the front support's own drag by two thirds (0.45 to 0.15 N, half car). The front pylon is a small part, though: 0.2 % of the car's drag.
    - Unlike at the rear, the front wing does not gain downforce, and no total (ClA, CdA, balance, wake) changes beyond the noise.
    - CPFF cannot be told apart from CPF in the CFD or in the lap sim: every lap-time difference is inside the 2.2 % band. The 45 m balance is -0.3 % vs +0.4 %, inside its band of 1.5 points.
    - Row `CPFF` in `params/aero_variants.csv` is CFD only; CP stays the default.
  - **Would build:** J at the front, for its own lower drag rather than a measured gain, and F at the rear.
  - **Not done:** K (run later, below), a rounded flat plate, 2 prism layers, yaw, structure (the front supports carry the front wing); CAD done 2026-11-28 as geometry only.
  - **Details:** the front-wing section of `media/cfd/supports/wing_supports_results.md`, with the flow picture `support_flow_front.png`.
- **Wing supports: finishing round (2026-11-28; CFD only, not in CAD).**
  - **Limits:** CFD only, steady RANS, one run per variant. The released v1.0.0 has no supports (the CAD has F and J since 2026-11-28).
  - **G and K meshed after all**, with a local face size on the flap trailing edges (1.1-1.8 mm wide, under the 2.5 mm minimum size; `cfd/fluent_halfcar_setup.md`).
    - The fix that meshes G also meshes CP, and CP on it moved by less than the noise (ClA -0.9 %).
    - K needed a different fix that no reference meshes on.
  - **Found:**
    - G's ridges do not help: its support drags 0.91 N (half car), against F's 0.41 and E's 0.81.
    - K's 0.144 N against J's 0.152 is inside the mesh effect, so not claimed.
    - F (rear) and J (front) stay the recommendation; no combination was run.
  - **Pictures:**
    - films of the air past each support (`supports_compare.gif` above);
    - a wake film CP_bl1 vs CPFF;
    - charts of support drag, totals and lap time with the 2.2 % band;
    - a one-page summary (`media/cfd/supports/supports_summary.png`).
- Make the SolidWorks Simulation beam studies on the production weldment solve, so the frame stress has a second source.
- Decide the frame material in the CAD (AISI 1020 now) against the 4130 the stress model assumes.
- Reach the motion study's ±30 mm of bump (it stops at +23 / +14 mm).
- Tyre data in place of the assumed grip, and a physical torsion test of the frame.

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

MIT for the source code: Python, MATLAB, C#, VBA macros and Fluent journals (`LICENSE`). CC BY 4.0 (`LICENSE-CAD`) for the CAD files (`cad/`, including the CFD geometry in `cad/step/cfd/`), the renders and images (`media/`), `params/`, `sim/`, `cfd/results/`, `docs/`, and the data files anywhere in the repository (CSV, JSON, Markdown, PDF).
