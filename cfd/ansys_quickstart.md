# Ansys Student quickstart: install, then a single-wing smoke test

**Status (2026-11-17):** Ansys Student 2026 R1 is installed at `C:\Program Files\ANSYS Inc\ANSYS Student\v261` (`AWP_ROOT261` set) and PyFluent 0.44 drives its meshing and solver with the Student licence (no GUI needed). The install steps and the smoke test below are still untested by clicking. Originally written from memory of Ansys Student 2024 R2 to 2025 R2 for the 2026 R1 Student release without it installed. Product names, dialog labels and limits marked **verify** must be checked against the installed version (Help > Ansys Help, or the Student page's own notes) before trusting them; correct this file as you go.

Why this exists: before the half-car case in `fluent_halfcar_setup.md` (900,000 cells, hours per run) you want one small run on a shape with a known answer, to learn the Workbench and Fluent clicks and to see what a converged, believable result looks like. The shape is the practice wing element from `docs/ring0_practice/06_airfoil_import.md` (NACA 0012, 300 mm chord, 500 mm span) exported as STEP.

## 1. Install (about 1 hour, mostly download)

1. Go to the Ansys Student page (ansys.com > Academic > Students > Ansys Student) and download the **Ansys Student 2026 R1** package (**verify** the current release name; mid-2025 it was 2025 R2). It is one installer of several GB; no account is strictly required for the download (**verify**: the page has asked for an email in some years).
2. Requirements that matter on this PC (Ryzen 7 9800X3D, 32 GB, RTX 5070, Windows 11 Pro): 64-bit Windows 10/11, about 30 GB free disk, a graphics driver newer than 2023. All fine. Disable antivirus real-time scanning for the install folder if the installer stalls at "Configuring" (**verify** whether 2026 R1 still trips on this).
3. Run the installer **as administrator**. Accept the licence. Install directory: default `C:\Program Files\ANSYS Inc\` (keep the default; the Student licence file is written next to it). The Student installer has no product selection: it installs Mechanical, Fluent, CFX, Discovery, SpaceClaim (**verify** whether SpaceClaim is still included in 2026 R1 or replaced by Discovery only), LS-DYNA and Electronics Desktop in one go. 20 to 40 minutes.
4. No licence server: the Student licence is built in and checked at start. First start of Workbench shows "Ansys Student" in the title bar. If it instead opens a licence-server dialog, the installer did not register the Student licence; re-run the installer and choose Repair (**verify**).
5. Start menu entries you will use: **Workbench 2026 R1**, **Fluent 2026 R1** (the standalone launcher), SpaceClaim / Discovery. Open Workbench once and close it, to let it create its settings folder.
6. Record the install date, version and the limits table below in `docs/log.md` under Software.

### Limits that shape every run

| Limit | Student value | Where it bites |
|---|---|---|
| Fluent cells | **1,048,576 (measured 2026-11-17)**: Fluent Meshing printed "can only be used with meshes containing less than 1048576 cells or 1048576 unmeshed faces" and exited for a 1,393,684-cell mesh | the half car is meshed to about 955,000 |
| Mechanical nodes / elements | 128,000 | not used here |
| Parallel cores | 4 (used by `cfd/fluent_halfcar.py`; more not tried) | see `fluent_halfcar_setup.md` for measured run times |
| Geometry (SpaceClaim / Discovery) | no face limit for Student (**verify**) | |
| Commercial use | not allowed | this project is personal and educational |

## 2. Geometry: wing in a box (20 min)

The test is quasi-2D: the wing spans the whole width of the box between two symmetry planes, so the answer should approach the 2D NACA 0012 at the same angle. Angle of attack 5 degrees; Reynolds number at 20 m/s and 0.3 m chord is 20 x 0.3 / 1.5e-5 = 400,000.

Export from SolidWorks first: open `cad/practice/wing_element.SLDPRT`, rotate it to 5 degrees nose up before export so that the inlet flow can stay along +x: Insert > Features > **Move/Copy** (**verify** the 2026 path; it is Move/Copy Bodies under Insert > Features), Rotate about the Y axis through the leading edge by 5 degrees, with the sign that lifts the leading edge (positive lift in +z for a positive angle; check in a side view). Save As `cfd/geometry/wing_element_naca0012_aoa5.STEP` (AP214, solid geometry). Frame: x along the chord (flow direction), y along the span, z up.

In Workbench:

1. File > New. From the Toolbox on the left drag **Fluid Flow (Fluent)** onto the Project Schematic. A block with Geometry, Mesh, Setup, Solution, Results appears.
2. Right-click **Geometry** > New SpaceClaim Geometry (or Discovery; **verify** which 2026 R1 offers). File > Open (or Import) the STEP. Check units: the wing should read 300 mm long (Measure tool or the ruler in the Design tab). If it reads 0.3 or 300,000 the import units are wrong; File > SpaceClaim Options > Units, or re-import with units set to millimetre.
3. **Enclosure**: Prepare tab > **Enclosure** > Box, custom size. Distances from the wing: -x (upstream) 2000 mm, +x (downstream) 4000 mm, -z 1500 mm, +z 1500 mm, y both sides **0** (so the box's side faces coincide with the wing's end faces; the wing then runs wall to wall) (**verify**: an enclosure with 0 distance on a side may be refused; if so, use 1 mm and then Pull the wing end faces 1 mm to the box faces, or make the wing 502 mm in SolidWorks). Tick the option that makes the wing a void in the air body (default for Enclosure). The structure tree shows the Enclosure body as the fluid and the wing as a tool body: **suppress or hide the wing solid for physics** (right-click > Suppress for Physics), so only the air is meshed.
4. **Named Selections** (Groups panel, or Workbench's Named Selection tool): select the box face at -x > create group `inlet`; +x > `outlet`; -z and +z > `top_bottom` (one group with both, they are far-field; make them symmetry); the two y faces > `sides`; every wing face (click one face of the void, then Ctrl+A on faces of that body, or use the selection filter) > `wing`. Exact lower-case names, they are referred to below and by the half-car journal convention.
5. Save the project as `cfd/cases/wing_smoke_test.wbpj` (the `cases/` folder is git-ignored). Close SpaceClaim.

## 3. Mesh in Fluent Meshing, Watertight Geometry workflow (30 min)

1. In Workbench, right-click **Mesh** ... stop. The default Mesh cell is Ansys Meshing, not Fluent Meshing. For consistency with the half-car guide, use **Fluent Meshing**: either delete the Mesh cell's link and open the Setup cell with "Fluent Meshing" ticked in the launcher (**verify** the 2026 R1 launcher has the "Meshing" radio button under Dimension/Options), or start the standalone **Fluent 2026 R1** launcher, tick Meshing mode, Double precision, 4 processes, Start. Alternative that also works for the smoke test: Ansys Meshing in the Mesh cell with an inflation layer on `wing` and a body sizing of 10 mm; the rest of this guide assumes Fluent Meshing.
2. **Workflow** panel > **Watertight Geometry**.
3. **Import Geometry**: pick the SpaceClaim file or the STEP enclosure export (File > Export in SpaceClaim as `.scdoc` or `.pmdb`; Fluent Meshing reads `.scdoc` directly, **verify**). Units mm. Update.
4. **Add Local Sizing**: yes. Curvature on `wing`: min 1 mm, max 10 mm, normal angle 10 degrees. Add a **Body of Influence**? There is none in the geometry; skip, and instead set Proximity on `wing` with 1 cells gap? Simpler: in **Generate the Surface Mesh**, min size 1, max size 100, growth rate 1.2, and the wake is refined later by the volume mesh growth. For a 500 mm span quasi-2D case this is enough.
5. **Describe Geometry**: "The geometry consists of only fluid regions with no voids"? No: the enclosure has the wing as a void. Choose **fluid regions with voids**? **verify** the exact radio labels in 2026; the point is: one fluid region, the wing is a wall. No capping needed (the box is closed).
6. **Update Boundaries**: the named selections appear; set types inlet = velocity-inlet, outlet = pressure-outlet, top_bottom = symmetry, sides = symmetry, wing = wall. Update.
7. **Update Regions**: one fluid region. Update.
8. **Add Boundary Layers**: on `wing`, **smooth-transition** or **uniform**: 8 layers, first height 0.1 mm, growth 1.2 (**verify** the offset method names). Target y+ of the first cell at 20 m/s: y+ = y u_tau / nu; with Cf about 0.005, u_tau = 20 x sqrt(0.0025) = 1.0 m/s, so y = 0.1 mm gives y+ about 7, in the buffer layer. Fluent's SST with its enhanced wall treatment handles y+ from 1 to 30 acceptably for a smoke test (**verify** the k-omega SST near-wall default in 2026 R1 is "y+-insensitive"). The half car uses 0.5 mm first cells for the wall-function range deliberately.
9. **Generate the Volume Mesh**: **poly-hexcore**, max cell length 100 mm, buffer layers 2, peel layers 1. Update. Expect **250,000 to 450,000 cells**. If above 800,000, raise the max surface size to 150; if far below 150,000 the wing sizing did not apply.
10. Check: Mesh > Check (console shows min orthogonal quality; want > 0.15) and Display the mesh on a cut plane at y = 250 mm (half span): a thick band of small cells around the wing, boundary layers visible, cells growing smoothly to the box.
11. Switch to Solution mode (the button at the top of the workflow, or File > Write Mesh then open the solver). Save: File > Write > Case as `cfd/cases/wing_smoke_test.cas.h5`.

## 4. Set up and run in Fluent (20 min setup, 10 to 20 min run)

Pressure-based, steady, SST, same as the half car so you learn the same panels once.

| Panel (tree on the left) | Setting |
|---|---|
| General | Pressure-based, Absolute, Steady. Units stay SI (the mesh was scaled on import; check Mesh > Scale shows x extent -2.0 to 4.3 m, not mm) |
| Models > Viscous | **k-omega SST**, defaults |
| Materials > air | density 1.2 kg/m3, viscosity 1.8e-5 kg/m-s (edit the defaults so they match `air_density`) |
| Boundary Conditions > inlet | velocity-inlet, magnitude **20** m/s normal to boundary, turbulence: intensity 0.5 %, viscosity ratio 10 |
| outlet | pressure-outlet, gauge 0 Pa, backflow as the inlet |
| top_bottom, sides | symmetry (already) |
| wing | wall, stationary, no slip |
| Reference Values | compute from inlet; area **0.15** m2 (chord 0.3 x span 0.5), length 0.3 m, density 1.2, velocity 20 |
| Methods | Coupled, pseudo-transient (Pseudo Time Method: Global time step), second order for pressure, momentum, k and omega |
| Report Definitions | New > Force Report > **Lift**: wall zone `wing`, force vector (0, 0, 1); create a report file, a plot and a convergence monitor (tick all three). New > **Drag**: `wing`, vector (1, 0, 0), same three ticks. Also **Lift Coefficient** and **Drag Coefficient** reports (same dialogs, coefficient type) so you see Cl and Cd directly |
| Monitors > Residuals | 1e-5 for all, or untick "check convergence" and stop on the force monitors instead |
| Initialization | Hybrid initialization |
| Run Calculation | 600 iterations |

Calculate. The console prints residuals every iteration; the lift and drag plots update live. Expect 1 to 2 seconds per iteration on 4 cores for 350,000 cells: 10 to 20 minutes.

When it stops: File > Write > Case & Data `cfd/cases/wing_smoke_test_done.cas.h5` / `.dat.h5`. The report files (`lift-rfile.out`, `drag-rfile.out`, in the working folder of the Fluent session, usually the project's `dp0/FFF/Fluent/` folder) are plain text: iteration, value.

## 5. What a good result looks like

Read the last 100 iterations of the Cl and Cd monitors (average them if they oscillate by less than 1 %).

| Quantity | Expected | Why |
|---|---|---|
| Cl at 5 degrees | **0.45 to 0.60** | thin-airfoil theory 2 pi alpha = 0.548; measured NACA 0012 at Re 4e5 is about 0.52; a quasi-2D RANS on a modest mesh lands a little under |
| Cd | **0.012 to 0.030** | measured about 0.013 at this Re with a laminar bucket; fully turbulent RANS gives 0.018 to 0.025; wall-function-range y+ pushes it up |
| Lift force (0.15 m2, 20 m/s, 1.2 kg/m3) | 0.5 x 1.2 x 400 x 0.15 x 0.52 = **18.7 N** (16 to 22 N) | |
| Drag force | 0.4 to 1.1 N | |
| L/D | 20 to 40 | |
| Residuals | continuity below 1e-4, others below 1e-5, all falling or flat, no sawtooth growth | |
| Monitors | Cl and Cd flat within 1 % over the last 200 iterations | the half-car convergence criterion |
| Minimum pressure coefficient on the wing | about **-1.9** near the leading edge on the suction side | Cp min of NACA 0012 at 5 degrees is close to -1.9 (**verify** against a tabulated XFOIL run: `xfoil` NACA 0012, Re 4e5, alpha 5 gives Cp min about -1.95) |
| Wall y+ on `wing` | 1 to 30, no large patches above 50 | Results > Contours > Turbulence > Wall Yplus on `wing` |

Pictures to save into `media/cfd/` (make the folder): contour of static pressure on a cut plane at mid span (Results > Surfaces > Create > Plane, y = 0.25 m; Contours > Pressure > Static Pressure on that plane, range auto): a red stagnation spot at the leading edge, a blue suction region on top near the LE, pressure recovering toward the TE. Velocity magnitude on the same plane: accelerated flow over the top, a thin wake behind the TE, no separation bubble bigger than a few percent of the chord at 5 degrees. Cp along the chord: Plots > XY Plot, Pressure Coefficient vs x on `wing`: the classic loop, suction peak then recovery.

Append the result to `cfd/results/forces.csv`? No: that file is for the car variants. Record the smoke test in `docs/log.md` as "Fluent smoke test: Cl x.xx, Cd x.xxx, cells N, iterations M, y+ range" and keep the case files locally.

## 6. What a bad result looks like, and the usual cause

| Symptom | Cause, fix |
|---|---|
| Cl near zero or negative | angle of attack not applied (wing exported at 0 degrees) or lift vector along the wrong axis; check the geometry in a side view, check the report vector is the up axis of the STEP (z) |
| Cl right, Cd 0.1 or more | mesh too coarse at the wing (no boundary layers generated, check the mesh cut plane), or first-order schemes, or the drag report includes the box walls |
| Residuals stall at 1e-3, monitors oscillating | large separation (angle too high) or poor cells (orthogonal quality < 0.05); run 200 iterations first order then second, lower the pseudo-time scale factor to 0.5 |
| "Reversed flow in N faces on pressure-outlet" | normal in the first 50 iterations; if it persists, the outlet is too close or the backflow turbulence is unset |
| Cell count over the licence limit at mesh generation | the max size did not apply or the boundary layers are too many; the console says "licence limit" and refuses to proceed |
| Fluent reads the wing as 0.3 mm or 300 m | units at import; Mesh > Scale in the solver, or re-import with mm |
| Lift changes by more than 5 % when you refine the mesh once (max size 100 -> 70, first height 0.1 -> 0.05) | mesh not converged; for a smoke test note it and move on, for the car it is the mesh-check row in `forces.csv` |

## 7. Then

The half-car case is scripted: `fluent_halfcar_setup.md` and `fluent_halfcar.py` (PyFluent; meshing and solving without the GUI). The old journal `halfcar_setup.jou` is superseded. This smoke test is still the quickest way to learn what a believable result looks like in the GUI.
