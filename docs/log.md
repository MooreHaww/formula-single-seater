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
