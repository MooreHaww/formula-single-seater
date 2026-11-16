# Fluent half-car setup guide (Ring 5)

**Status: untested, needs the app.** Written for Ansys Student 2025/2026 (Fluent with the Watertight Geometry meshing workflow) without the software open. Menu names may differ by a word; the TUI commands in `halfcar_setup.jou` need checking against your version's prompts (type the command path with `?` to see the options).

Limits that shape everything: Ansys Student caps the model at 1,000,000 cells and 4 solver cores. The whole setup is built around that.

## 0. Conventions used by every file in this repo

| Item | Convention |
|---|---|
| Frame | The SolidWorks master-layout frame: **x rearward** (downstream, same as the flow), **y to the right**, **z up**, origin on the ground under the front axle centre. Keep it when importing; do not let SpaceClaim or Fluent Meshing re-orient. |
| Units | STEP from SolidWorks is in mm. Scale to metres in Fluent Meshing (Import Geometry > Units: mm) or `/mesh/scale 0.001 0.001 0.001` in the solver. Check: wheelbase must read 1.55 m. |
| Half model | Keep the **y >= 0** half. The symmetry plane is y = 0. |
| Speed | 20 m/s (72 km/h) for every variant, 30 m/s for the speed check. Same as `cfd_speed` in `params/car_params.txt`. |
| Rear axle | x = 1.550 m (wheelbase). Car length L = 2.950 m (`overall_length`). |
| Wake planes | Constant-x planes at x = 1.55 + n L for n = 0.5, 1, 2, 3: **x = 3.025, 4.500, 7.450, 10.400 m**. |
| Window | Following-car window on each plane: 0 <= y <= 0.7 m, 0 <= z <= 1.2 m (half of 1.4 m wide, 1.2 m high). |
| Force sign | Downforce is **negative z force** on the car surfaces; drag is positive x. Report lift with the force vector (0, 0, -1) so the number comes out positive for downforce. |
| Half to full | Every force from the half model is **half the car**. `cfd/results/forces.csv` holds **full-car values** (multiply by 2 before you write the row). |

## 1. Geometry (SolidWorks side, Ring 2f)

One watertight solid per variant, exported by `cad/macros/ExportConfigsSTEP.bas` to `cfd/geometry/cfd_body_<variant>.STEP`:

- Half car already cut at y = 0 (Cut-Extrude from the Right plane) so Fluent sees a flat symmetry face.
- Wheels closed (no spokes), tyres as plain solids of revolution with a small flat where they touch the ground (a 10 mm contact patch avoids the tangent-point mesh failure).
- No suspension links, no frame tubes, no gaps thinner than 5 mm. Wing elements and endplates are the real ones from the configuration.
- Ground clearance from `ride_height_front` / `ride_height_rear`. The car sits on z = 0.
- Run **Tools > Evaluate > Check** in SolidWorks: one closed solid, no open edges. This is the Ring 2 check.

## 2. Air box

Draw it in SpaceClaim (Student) or as an enclosure in Fluent Meshing:

| Face | Position | Boundary type and name |
|---|---|---|
| Inlet | x = -3 L = -8.85 m (ahead of the nose) | velocity-inlet `inlet` |
| Outlet | x = +5 L behind the rear axle = 16.3 m (holds the 3 L plane with margin) | pressure-outlet `outlet` |
| Symmetry | y = 0 | symmetry `symmetry` |
| Side | y = +4 m | symmetry `side` (slip) |
| Ground | z = 0 | wall `ground`, moving at 20 m/s in +x |
| Top | z = +4 m | symmetry `top` |

Blockage check: frontal area of the half car (about 0.55 m2) over the half box cross-section (4 x 4 = 16 m2) is 3.4 %, acceptable.

Two refinement boxes (Bodies of Influence in the Watertight workflow):
- **Car box**: x from -1 to 4.5 m, y 0 to 1.0 m, z 0 to 1.5 m, cell size 20 mm.
- **Wake box**: x from 4.5 to 10.5 m, y 0 to 1.2 m, z 0 to 1.6 m, cell size 40 mm (keeps the 1 L to 3 L planes resolved).

## 3. Mesh (Fluent Meshing, Watertight Geometry workflow)

Same settings for every variant; only the geometry file changes. That is what makes the comparison fair.

1. Import Geometry: the STEP, units mm.
2. Add Local Sizing: car surfaces (named selection `car*`) curvature 8 mm min / 40 mm max, normal angle 12 deg; wing trailing edges proximity 3 mm; the two bodies of influence above.
3. Generate Surface Mesh: min 3 mm, max 400 mm, growth 1.2.
4. Describe Geometry: fluid region only, no wrapping (the body is watertight).
5. Update Boundaries: assign the six box faces as in the table; everything else wall `car`.
6. Add Boundary Layers: 5 layers, first height 0.5 mm, growth 1.2 on `car` and `ground` (wall-function y+ of 30 to 100 at 20 m/s; a full resolution to y+ 1 would blow the cell budget).
7. Generate Volume Mesh: **poly-hexcore**, max cell length 400 mm, peel layers 1.
8. Check cell count. Target **850,000 to 950,000**. If above 1,000,000: raise the wake box size to 50 mm first, then the car box to 25 mm. If well below 700,000: reduce the car box to 16 mm.
9. Check quality: orthogonal quality min > 0.1. Improve if not.
10. Switch to Solution, save as `cfd/cases/halfcar_<variant>.cas.h5`.

Mesh sensitivity run (variant C): repeat with every local size times 1.26 (half the cells, since cells scale with size cubed). Record both cell counts in `forces.csv`.

## 4. Solver settings (identical for every run)

| Setting | Value |
|---|---|
| Solver | pressure-based, steady, absolute velocity |
| Turbulence | k-omega SST, default constants, production limiter on |
| Air | density 1.2 kg/m3, viscosity 1.8e-5 Pa s (constant, matches `air_density`) |
| Inlet | velocity magnitude 20 m/s normal to boundary, turbulent intensity 0.5 %, viscosity ratio 10 |
| Outlet | gauge pressure 0, backflow turbulence as the inlet |
| Ground | moving wall, translational, (20, 0, 0) m/s, no slip |
| Wheels | rotating wall about the wheel axle: axis direction (0, 1, 0), origin at the hub centre (front: x = 0, z = 0.2285 m; rear: x = 1.55, z = 0.2285 m), speed = 20 / 0.2285 = 87.5 rad/s. Needs the tyres as their own named selection `wheel_front`, `wheel_rear`. |
| Car | stationary no-slip wall |
| Scheme | coupled, pseudo-transient, second order upwind for everything, default under-relaxation |
| Reference values | area 1.1 m2 (`frontal_area`), density 1.2, velocity 20, length 1.55 (for Fluent's own Cl and Cd; the MATLAB script uses forces, not coefficients) |
| Monitors | lift (vector 0 0 -1) and drag (vector 1 0 0) on `car` plus the wheels, written every iteration to `forces_<variant>.out` |
| Initialise | hybrid |
| Iterations | 1500, or until the force monitors are flat for 300 iterations |

Convergence check for the ring report: residuals below 1e-4 and the lift and drag monitors flat (less than 1 % drift over the last 300 iterations). Screenshot the monitor plot.

## 5. After the run

1. Read the final lift and drag from the monitor file (average the last 200 iterations if they oscillate). Multiply by 2. Also report the force on the front wing surfaces alone (`fw*`) times 2 for `downforce_front_N`.
2. Append one row to `cfd/results/forces.csv`:
   `variant,speed_mps,downforce_N,drag_N,downforce_front_N,cells,note`
3. Create the four wake planes (Surface > Create > Plane, "YZ Plane" at the x values above, or the `surface/plane-surface` commands in the journal) named `plane_0.5L`, `plane_1L`, `plane_2L`, `plane_3L`.
4. File > Export > Solution Data: ASCII, comma delimited, **node values**, surfaces = the four planes, one file per plane, quantities x-velocity, y-velocity, z-velocity, turb-kinetic-energy. Save as `cfd/results/wake/<variant>_<n>L.csv` (for example `C_1L.csv`, `C_0.5L.csv`).
5. Contours of velocity magnitude on each plane and a side-view streamline picture: save as PNG into `media/cfd/`.
6. Run in MATLAB: `aero_plots` then `wake_postprocess`.

## 6. Expected run time on this PC

Ryzen 7 9800X3D, 32 GB RAM, 4 cores allowed by the Student licence: a 900,000-cell poly-hexcore case runs roughly 2 to 4 seconds per iteration with the coupled solver, so 1500 iterations is 1 to 2 hours. Memory is about 4 to 6 GB. Start a run at the end of a session and read it the next day. The GPU is not used by the CPU solver.

## 7. Fallbacks

- Mesh will not generate: thicken wing trailing edges to 2 mm, add a 10 mm flat under each tyre, check for slivers between flap and endplate.
- Count over 1,000,000: coarsen the wake box first.
- Solution diverges: run 200 iterations first order, then switch to second order; lower the pseudo-transient time scale factor to 0.5.
- Fluent unusable: SimScale with the same boundary table (it has a similar Watertight meshing and k-omega SST). Spend its 10 runs on A, B, C and one mesh check.
