# Build log

One entry per session. Newest at the bottom. Each entry: date, ring, what was done, what was checked, next step.

## Machine

Read on 2026-11-16 from PowerShell (`Get-CimInstance Win32_Processor / Win32_ComputerSystem / Win32_VideoController`, `nvidia-smi`):

| Item | Value |
|---|---|
| CPU | AMD Ryzen 7 9800X3D, 8 cores / 8 threads reported (SMT appears off), 4.7 GHz max, 96 MB 3D V-Cache |
| RAM | 32 GB (31.1 GB usable) |
| GPU | NVIDIA GeForce RTX 5070, 12 GB, driver 621.01 (WMI reports 4 GB because of its 32-bit field; nvidia-smi gives 12,227 MiB). Plus the Ryzen's integrated Radeon. |
| OS | Windows 11 Pro 24H2+, build 26300 |

What that means for the plan: Fluent in Ansys Student uses at most 4 cores regardless, so the 8-core CPU is not the bottleneck; a 900,000-cell steady RANS case is 1 to 2 hours per run and 4 to 6 GB of RAM. SolidWorks Simulation and Motion are single-threaded for most of their work and benefit from the high clock. The GPU is for RealView, Visualize renders and nothing in the simulations.

## Software

| Tool | Version | Checked |
|---|---|---|
| SolidWorks Design Premium for Students 2026 | Simulation and Motion add-ins on (no Flow Simulation) | 2026-11-16, by the owner |
| MATLAB R2026a Update 5 | Simulink, Simscape, Simscape Driveline, Simscape Multibody, Vehicle Dynamics Blockset. No other toolboxes (so no Optimization, Curve Fitting or Aerospace functions in the scripts). | 2026-11-16, `ver` via the MATLAB MCP tool |
| Ansys Student (Fluent) | to be installed | |
| SimScale | backup, free plan | |

## Entries

### 2026-11-16, Ring 0 start, repo skeleton and all scripts written up front

- Repo structure created: `params/`, `cad/`, `matlab/`, `sim/`, `cfd/`, `docs/`, `media/`.
- `params/car_params.txt` written (178 entries, SolidWorks equation format) with the Ring 1 starting values; `matlab/common/read_car_params.m` reads it and prints a table.
- Airfoil files generated (NACA 4-digit, `cad/airfoils/`), three SolidWorks macros written as `.bas` text (untested, need the app).
- MATLAB: `accel_test.m`, lap simulator with four tracks, cornering-speed-vs-downforce plot, aero sweep, following-car penalty, sensitivity, `load_cases.m`, `suspension_plots.m`, `aero_plots.m`, `wake_postprocess.m`, Simulink 6b builder, `run_all.m`. Every script has a self-test with a hand-checkable answer; 14 of 14 pass.
- Simulink 6b model reproduces the MATLAB 75 m time to within 0.01 %.
- CFD guide and journal written (untested, need Ansys).
- Not done: nothing in SolidWorks yet (rim, bracket, practice assembly are the owner's first-day work). No commits yet.
- Next: first-day checklist steps 1, 5, 6 (Ansys download, rim, bracket), then MATLAB Onramp.

### 2026-11-16 (second session), pre-CAD engineering and build playbook

- `matlab/suspension_geometry.m`: 3D double-wishbone kinematics (Newton solve of the upright pose) giving camber gain, bump steer, roll centre, motion ratio, KPI, caster, scrub, trail. Hardpoints tuned by grid search and written into `params/car_params.txt` (between the BEGIN/END markers) and `params/suspension_hardpoints.txt`. Results, front / rear: camber gain -0.039 / -0.048 deg/mm, bump steer 0.011 / 0.006 deg over +-30 mm, roll centre 60 / 69 mm static (10 to 128 mm migration in parallel travel), motion ratio 0.71 / 0.77, KPI 6.0 / 5.7 deg, caster 4.7 / 3.7 deg, scrub 19 / 17 mm.
- `matlab/cad/frame_layout.m`: 42 nodes, 98 tubes, 35.4 m, 37.3 kg of 25.4 mm steel tube, written to `cad/frame/frame_nodes.csv` and `frame_tubes.csv`, with a clearance check against driver legs, torso, helmet, battery, motor and diff. Packaging changes it forced: battery 180 x 510 x 370 mm behind the main hoop (34 L, marginal for 6 kWh; sidepod packs listed as the v2 alternative), rear forward pickups moved to X 1485, motor behind the rear box at X 1850 with a 300 mm chain drive, main hoop raised to 980, driver hip at X 850 with a 40 deg seat back.
- `docs/cad_playbook/`: 16 files, one per part in build order, plus `macro_review.md`.
- Macros: three small fixes applied (guarded preference calls, title-line parsing, empty-file guard), `ImportFrameNodes.bas` added. All four still untested.
- Self-tests now 16 (14 + suspension_geometry + frame_layout).
