# Fluent half-car setup (Ring 5), scripted

Everything runs from Python (PyFluent 0.44 against Ansys Student 2026 R1); nothing is clicked. The manual journal `halfcar_setup.jou` is superseded and kept only for reference.

```bash
.venv/Scripts/python cad/generate/cfd_variants.py              # geometry, all variants, with checks
.venv/Scripts/python cfd/fluent_halfcar.py mesh C              # -> cfd/cases/halfcar_C.msh.h5
.venv/Scripts/python cfd/fluent_halfcar.py solve C --iters 1500
.venv/Scripts/python cfd/postprocess.py --update-variants      # tables, plots, lap-sim aero table
```

Geometry and zones: `cfd/geometry_notes.md`. Python packages: `cfd/requirements.txt`.

## The Student limit (measured on this install)

Fluent Meshing itself refuses a larger mesh and exits. This is the message it printed on 2026-11-17 for a 1,393,684-cell mesh of variant C:

> This is a student license, and can only be used with meshes containing less than 1048576 cells or 1048576 unmeshed faces.

So the limit is **1,048,576 cells** (2^20), and the mesher will not even write the file. `fluent_halfcar.py` stops before that with its own message. Cores: 4 (Student).

## Mesh settings (same for every variant, so the ranking is fair)

| Setting | Value | Why |
|---|---|---|
| Workflow | Watertight Geometry, import of `fluid_<V>.step` (the air as one solid), one zone per CAD face, zones named by bounding-box match to `faces_<V>.csv` | the STEP reader drops names |
| Minimum size | 2.5 mm, never scaled | at 3 mm (one cell per slot gap) the slots fail |
| Wing faces (`car_fw`, `car_rw`) | 12 mm | at 14 to 17 mm the surface mesh fails ("breakout detected") at the rear flap on Y = 0 and the front-flap trailing edges |
| Body, floor, wheels, ground | 48, 36, 28, 320 mm (24, 18, 14, 160 x `--scale 2`) | coarsened to get under the limit |
| Bodies of influence | near car 80 mm, wake 140 mm (40, 70 x 2) | |
| Curvature normal angle | 18 deg | 24 deg broke the front-flap trailing edge |
| Surface growth | 1.2 | 1.3 broke the surface mesh at scale 1.3 |
| Prism layers | **2**, smooth transition, rate 1.2, on car and wheels (not the moving ground) | 3 and 4 layers put C over the limit |
| Volume | poly-hexcore, max cell 640 mm | |

Result for variant C: 955,009 cells, minimum orthogonal quality 0.10, 247k surface faces (wings 130k of them). Most cells come from the surface faces (about 4.8 cells per face), not from the refinement boxes. Volume growth rate had no effect on the count.

Search for those settings (all on C; each mesh about 3 minutes):

| Try | Cells | Result |
|---|---|---|
| all sizes x1 (4 layers) | 1,393,684 | over the limit |
| all sizes x1.2 | - | surface mesh failed (slots) |
| non-wing x1.3, 4 layers | 1,321,381 | over |
| non-wing x1.3, wings x1.4 | - | surface mesh failed (rear flap at Y = 0, front-flap TE) |
| curvature 24 deg, 3 layers | - | surface mesh failed (front-flap TE) |
| non-wing x1.6, 3 layers | 1,185,528 | over |
| ... + surface growth 1.3 | 1,130,091 | over |
| non-wing x2, 2 layers | **955,009** | **used** |

Variant D then failed the surface mesh with the same settings (slot at the rear endplate, beam wing at the pylon face, front-flap ends). Eleven attempts with other settings (min 2.0 mm meshes but gives 1.09 to 1.19 M cells; coarser wing faces give self-intersections in the slots; finer wings or other curvature angles fail elsewhere; 3 mm trailing edges fail in three places) did not give a mesh under the limit. The fix was in D's own geometry (beam wing inside the pylon chord, 10 mm fins, `cfd/geometry_notes.md`); D then meshed with the common settings.

| Variant | Cells | Min orthogonal quality |
|---|---|---|
| A | 271,859 | 0.10 |
| B | 900,187 | 0.10 |
| C | 955,009 | 0.10 |
| D | 1,042,343 (0.6 % under the limit) | 0.13 |

What 2 prism layers mean: wall functions (SST with Fluent's y+-insensitive treatment), first cell a few mm, y+ roughly 30 to 150 at 20 m/s. Separation on the flaps and the diffuser is predicted less well than with a resolved boundary layer. This is one of the reasons only the ranking is trusted.

## Solver settings

| Setting | Value |
|---|---|
| Solver | pressure-based, steady, coupled, second order (pressure, momentum, k, omega) |
| Turbulence | k-omega SST |
| Air | 1.2 kg/m3, 1.8e-5 Pa s |
| Inlet | 20 m/s, turbulence intensity 0.5 %, viscosity ratio 10 |
| Outlet | gauge 0 Pa |
| Ground | moving wall, 20 m/s in +X |
| Wheels | rotating wall, omega = U / R_loaded = 90.1 rad/s about (0, -1, 0) through each wheel centre |
| Symmetry | Y = 0, side and top (slip) |
| Reference | area 1.1 / 2 m2 (half model), length 1.55 m |
| Reports | drag (+X) and downforce (-Z) for the total, the wheels and each car zone; pitching moment about the Y axis through the front contact point; all every iteration to `cfd/results/runs/<V><tag>/forces.out` |
| Stop | since 2026-11-18: residuals are monitored only (`criterion_type none`); the run stops when downforce, drag and pitching moment each vary by less than 0.1 % over the previous 100 iterations (first 300 ignored), or at `--iters` (default 1200). Before 2026-11-18: residuals 1e-4 AND forces, which never stopped a run (see below) |
| Exports | four wake planes (0.5, 1, 2, 3 car lengths behind the rear axle) as node CSV: u, v, w, k, total pressure |

## What has run on this PC

| Date | Run | Result |
|---|---|---|
| 2026-11-17 | variant A probe, coarse (292,828 cells), 25 iterations | whole chain works: mesh, solve, reports, wake export |
| 2026-11-17 | meshes of all four variants, common settings | table above |
| 2026-11-17 | solves C, B, D, A, 1500 iterations each (17:09 to 21:39; C 83 min, B 82, D 82, A 23) | `media/cfd/cfd_results.md`, table below |

| Variant | ClA (m2) | CdA (m2) | L/D | front axle share | forces | continuity residual drop |
|---|---|---|---|---|---|---|
| A | -0.03 | 0.42 | - | n/a (total near zero) | drag converged; downforce mean steady (drift 0.01 %) but swings by 1.5 N on the half car (ClA +-0.006), so the 2 % band test fails: marked NOT converged, used with `--force` | 1.2 orders |
| B | 3.43 | 1.29 | 2.65 | 0.45 | converged | 1.7 orders |
| C | 3.98 | 1.63 | 2.44 | 0.45 | converged | 2.2 orders |
| D | 4.20 | 1.77 | 2.37 | 0.38 | converged | 2.1 orders |

Forces were flat from about iteration 200 on B, C and D, but the residuals stalled 1 to 2 orders short of the checklist's three (a common state for a steady RANS run around a bluff body with an unsteady wake). Two things did not work as planned:
- The force-based stop (0.2 % over 100 iterations) was accepted by Fluent without error but never stopped a run, so every run used the full 1500 iterations. **Cause, found 2026-11-18:** with residual criteria active, Fluent stops only when the residuals AND the report criteria are met, and continuity stalls at 6e-3. Fix in `set_convergence()`: residual `criterion_type = "none"`, stop on the three force reports alone. First run with the fix: C_coarse stopped at iteration 407.
- B and D each had one failed launch ("Connection refused" from the gRPC channel); the retry in `fluent_halfcar.py` started them on the second attempt.

### 2026-11-18: mesh checks, convergence, y+, variant CP

| Run | Cells | What changed against the base run | Iterations | ClA | CdA | front share |
|---|---|---|---|---|---|---|
| C_num | 955,009 | C continued 400 iterations with poor-mesh numerics and high-order relaxation | 1500+400 | +0.03 % | 0.00 % | 0.000 |
| C_coarse | 941,430 | `--scale 2.6` (volume, ground and non-wing faces 1.3x coarser) | 407 (force stop) | −0.29 % | −0.10 % | +0.001 |
| C_w | 1,037,523 | three wake-window boxes at 50 mm (`--boi win --win-size 50`) | 401 | −0.15 % | −0.09 % | 0.000 |
| C_bl1 | 871,424 | 1 prism layer instead of 2 (`--set bl_layers=1`) | 401 | +0.12 % | −2.40 % | +0.010 |
| D_bl1 | 949,206 | the same on D | 1200 | −0.28 % | −1.19 % | +0.010 |
| C_curv, D_curv | - | curvature angle 24 or 21 deg instead of 18 (coarser surface) | - | surface mesh failed at the wing slots, no result | | |
| CP | 1,007,086 | C with the SolidWorks nose, sidepods and 10 mm floor plate | 1200 | 3.89 (−2.3 %) | 1.66 (+1.8 %) | 0.43 |

**Why the body surface does not coarsen with `--scale`:** the curvature (18 deg) and proximity size functions set the face size on the car, not the zone face size. At `--scale 2.6` the body had 27,944 faces against 28,079. A `--scale` change is a volume-mesh check. The surface cannot be coarsened or refined in a useful way under the limit: a coarser curvature angle breaks the wing slots, and a finer one goes over 1,048,576 cells.

**Mesh uncertainty (measured, discretisation only):**
- ClA: within 0.3 % in all checks.
- CdA: within 2.4 %, mostly from the prism layers.
- Front share: within 0.01.
- These are lower bounds: no finer surface mesh was possible.
- Model error is not measured: steady RANS SST, wall functions, no wind-tunnel data. So the +-20 % ClA / +-15 % CdA ranges in `params/aero_variants.csv` stay assumptions.
- What was measured: **the ranking does not move with the mesh.** With 1 layer the D-to-C ClA gap is 5.0 % against 5.4 %. The lap sim needs a 5.5 % error in D's ClA relative to C to swap them on the autocross, 10.7 % in C's relative to B, and 23.6 % in B's CdA relative to C on the fast circuit.

**y+ (C, area average / median; share of faces with y+ 5 to 30):**
- front wing 75 / 31 (45 %);
- rear wing 70 / 40 (36 %);
- floor 82 / 31 (46 %);
- body 151 / 42 (36 %);
- wheels 123 / 70 to 76 (6 to 11 %).

The first cell sits in the log layer on most of the car, and the buffer layer on 36 to 46 % of the wings and floor. With SST, Fluent then uses wall functions (its y+-insensitive treatment blends to the log law above y+ of about 11). Separation on the flaps and the diffuser is modelled, not resolved. Going from 2 layers to 1 raises the wing y+ by about 15 % and changes CdA by 1 to 2 %.

**Convergence:**
- **Residuals** (scaled, final):

  | Run | continuity | momentum | k and omega |
  |---|---|---|---|
  | A | 6.7e-2 | 1e-6 | 1e-3 |
  | B | 1.9e-2 | 1e-6 | 5e-4 |
  | C | 6.3e-3 | 3e-7 | 1e-4 |
  | D | 8.3e-3 | 4e-7 | 1.6e-4 |

  - Continuity stalls and does not drop further with 400 more iterations and stiffer numerics (C_num: 4.3e-3, forces +0.03 %).
  - Global mass imbalance is 1e-7 to 5e-7 of the inlet flow, so mass is conserved. The stalled residual is local unsteadiness in the wakes.
- **Forces:**
  - C is steady: band 0.04 %. The force stop would have ended it at about iteration 560, and its checks stopped at about 400.
  - B and D oscillate with a fixed amplitude (downforce band 0.13 to 0.16 %, period 14 to 36 iterations). They are stationary, not drifting, and their means are good to under 0.1 %. They do not meet the 0.1 % stop and run to `--iters`.
  - CP is unsteady (band 2.5 %): the parts' sidepod tails shed vortices. Its 200-iteration means drift by under 1 %. Postprocess marks it NOT converged; its mean is good to about 1 %.
  - A steady solver cannot do better on these flows; a transient run would, but it costs far more than the Student setup allows here.

## Reading the results

`cfd/postprocess.py` averages the last 200 iterations, doubles to the full car, and gets the front axle load from the pitching moment (front = DF - M / wheelbase). It calls a run force-converged when the mean moves less than 1 % between the last two 200-iteration windows and the band within the last window is under 2 %. It writes `media/cfd/cfd_results.md` and the plots. With `--update-variants` it puts the converged runs into `params/aero_variants.csv` with source "CFD ...", so the lap sim uses them (`aero_estimate` never overwrites a CFD row). The pre-CFD estimate stays in `params/aero_variants_estimate.csv` for the before/after table in `media/results_table.md`.

**What the numbers mean:** one mesh per variant at the Student limit, 2 prism layers, steady RANS, no mesh-independence study, no test data. Absolute ClA, CdA and balance could be off by tens of percent. **Only the ranking of the variants is trustworthy** (same geometry rules, same mesh settings, same solver). The CFD rows in the variant table carry an assumed range of +-20 % ClA and +-15 % CdA.

## Checklist for the first look at a run

1. `forces.out`: downforce and drag flat over the last few hundred iterations (`media/cfd/cfd_convergence.png`); postprocess says "force-converged".
2. Residuals in `cfd/cases/solve_<V>.log` dropped at least three orders.
3. The downforce sign: variants B to D positive, A near zero.
4. Wake CdA from the 0.5 L plane (momentum only, in `cfd_results.md`) of the same order as the force CdA.
5. Open the case in the Fluent GUI (`cfd/cases/halfcar_<V>.cas.h5`): contours of y+ on the wings (expect 30 to 150), pressure on the floor, no reversed flow at the outlet.
6. Mesh check on one variant (C): `--scale 2.6 --tag coarse` (done 2026-11-18: a volume check, only 1.4 % fewer cells) and `--set bl_layers=1` (near-wall check); differences of more than 5 % would mean the numbers move with the mesh. Measured: under 0.3 % ClA, 2.4 % CdA.

## Fallbacks

- Surface mesh fails: the message gives a coordinate; compare it with `cad/step/cfd/check_report.txt` (wing slots, flap ends, trailing edges are the usual places). Widen the gap or blunt the edge in `cad/generate/cfd_variants.py`, not the mesh sizes.
  - A local face size on the narrow trailing-edge strips (`--set te_size=...`, off by default) is a second tool, but a fragile one; see the slot study below.
- Over the limit: fewer prism layers or coarser non-wing faces; the wing faces cannot go above 12 mm with the current slots.
- Diverges: start with first order for 200 iterations, or lower the Courant number of the coupled solver.

## Slot study: trailing-edge face size (2026-11-28)

**Why.** G (rear support with ridges) and K (pointed front lens) never meshed. All their failures, and CPFF's and F's first ones, were at two places:
- front flap 1's inner end (X -590, Y 300, Z 151);
- rear flap 1's trailing edge (X 2215, Z 1359).

Both are next to the flap trailing-edge strips, which are narrower than the 2.5 mm minimum size. These are the blunt 97 %-chord trailing edges in `cad/generate/cfd_variants.py`, identical in every variant:

| Strip | Width |
|---|---|
| front flap 1 | 1.62 mm |
| rear flap 1 | 1.77 mm |
| front flap 2 | 1.07 mm |
| rear flap 2 | 1.13 mm |

**The tool.** `fluent_halfcar.py` can put its own face size on these strips:
- Each strip is its own sizing zone during the surface mesh. The zones are matched back into the wing zone afterwards, so the force zones do not change.
- Settings:
  - `te_size` (mm, 0 = off, the default);
  - `te_sel` (refine only strips wider than this; the default is `te_size`, and 0 means all four);
  - `te_size2` (size for the narrower strips);
  - `te_growth` (growth away from the strips; the default is the global 1.2).
- With all of them off (the default), the mesh is CP's, unchanged.

**What happened.** One bl_layers=1 mesh per cell, each a few minutes. The meshes are deterministic, so a cell is a fact, not luck.

| Setting | G | K | CP | J |
|---|---|---|---|---|
| 1.0 mm on all four, growth 1.2 | meshes, 1,130,790 (over) | meshes, 1,079,030 (over) | | |
| **A:** 1.5 mm on the flap-1 strips, growth 1.2 | **meshes, 1,018,541** | fails: front flap 2, inner end | **meshes, 965,287** | |
| 1.5 mm on all four, growth 1.2 | fails: rear slot at Y 0 (X 2026) | same | same | |
| **B:** 1.0 mm on all four, growth 1.5 | fails: front flap 1 TE | **meshes, 964,633** | fails: front flap 1 TE | fails: 22 self-intersections |
| 1.0 mm on all four, growth 1.4 | meshes, 1,024,935 | fails: 32 self-intersections | fails: rear flap 1 TE | |
| 1.0 mm on all four, growth 1.3 | | fails: rear slot at Y 0 | fails: front flap 2, inner end | |
| 1.5 mm flap 1 + 1.0 mm flap 2, growth 1.2 | fails: front flap 2 TE | fails: rear slot at Y 0 | fails: front flap 1, inner end | |

**What it means.**
- The narrow strips are part of the cause: refining them made G and K mesh for the first time.
- They are not the whole cause. Each setting moves the failure to another slot spot (both flap-1 and flap-2 ends, the rear slot on the symmetry plane), and no setting meshed G, K and CP together.
- The slots are at the edge of what this surface mesher accepts at a 2.5 mm minimum size. The real fix is in the geometry: thicker trailing edges only on the flap ends, or wider slots, for all variants at once. That changes CP's wings, so it means a new CP reference, and it was not done.

**What was used.**
- **Fix A for G and for the check run CP_bl1ta.**
- **Fix B for K only.** Neither CP nor J meshes on B, so K has no same-mesh reference. Only K's own support force is compared, and the totals are not claimed.
