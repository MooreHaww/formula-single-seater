# Frame structural analysis (beam FE)

Model: `matlab/stress/frame_fe.m` (run alone, from `run_all`, or `frame_fe('--selftest')`).
Output: `sim/stress/frame_fe_report.txt` and `media/frame_fe.png`.
Cross-check: both free-free torsion cases on an analysis-only fused solid frame in SOLIDWORKS Simulation, `swh FrameAnalysis` (`tools/sw_harness/FrameAnalysis.cs`). It agrees within 1 % (1504 vs 1503 Nm/deg in the headline case). The result is in `sim/stress/frame_analysis_report.txt` and in the last section below.

## Model

| Item | Choice |
|---|---|
| Geometry | `cad/frame/frame_nodes.csv` and `frame_tubes.csv`, the same files the SOLIDWORKS chassis is built from: 50 nodes, 124 tubes, 49.3 kg on centre-line lengths (since 2026-11-18, with the torsion diagonals; 114 tubes and 43.1–43.5 kg before). The tube masses are scaled to the budget's `m_frame`, 47.5 kg (factor 0.964): the centre-line lengths count each coped end again inside its neighbour. Stiffness does not depend on this. |
| Elements | one 3D Euler-Bernoulli beam per tube, 12 degrees of freedom, rigid joints at the node centres. No joint flexibility, no weld or bracket detail. |
| Sections | the real tube OD and wall from `frame_tubes.csv`: A, I = π(D⁴−d⁴)/64, J = 2I, Z = I/(D/2) |
| Material | 4130 normalised: E 205 GPa, G 80 GPa, ρ 7850 kg/m³, yield 435 MPa. Factor of safety wanted: 1.5 on yield. |
| Units | N, mm, MPa |
| Stress | at both ends of each element: σ = \|N\|/A + √(My²+Mz²)/Z, τ = T·r/J, von Mises √(σ²+3τ²). This is the outer-fibre peak, with no stress concentration at the joints. |

### Suspension loads into the frame

Each corner's six links (lower wishbone front and rear legs, upper wishbone front and rear legs, tie rod, pushrod) are two-force members. For a contact-patch force and moment from `sim/stress/load_cases.csv`, the six link tensions come from the corner statics (6×6 solve, residual about 1e-13). Hardpoints come from `params/car_params.txt` (the rim-limited set of 2026-11-17).

The forces are applied to the frame at the pickups. Each pickup is mapped to its nearest frame node:
- The wishbone pickups sit exactly on nodes.
- The tie rod (95 mm front, 59 mm rear) and the pushrod rocker (28 mm, 22 mm) are offset, and their offset moment r × F is applied as well (a rigid bracket).

### Masses (for inertia relief)

- Frame tubes: half of each tube's mass at each end node, scaled to the budget's 47.5 kg (since 2026-11-18 evening; 49.3 kg of centre-line tubes before).
- Items from `matlab/mass_budget.m` go on the nodes that carry them:
  - driver on the cockpit floor and shoulder nodes;
  - battery on the eight sidepod nodes;
  - wings on their mounting nodes;
  - everything else on the nearest four nodes.
- Unsprung corners (44.4 kg) are not on the frame.
- Sprung total on the frame: 259.4 kg, CG x 941, z 261 mm.

### Boundary conditions

A real car has no fixed point. Every case is solved free-free with **inertia relief**:
1. Find the rigid-body acceleration (3 translations, 3 rotations) that balances the applied loads against the lumped masses: a = (ΦᵀMΦ)⁻¹ΦᵀF.
2. Add the d'Alembert forces −MΦa.
3. Hold a statically determinate 3-2-1 support (FB_L_R in x, y, z; RS2_L_R in y, z; FB_L_L in z). The reactions there are about zero, because the loads now balance.
4. Remove the mass-weighted rigid motion from the displacements.

The driving cases are checked by the acceleration this finds, which must match the case (all within 0.1 % since the frame mass follows the budget; within 1 % before, when the beam tubes carried 1.8 kg more than the budget).

## Load cases

| Case | Source | What is applied |
|---|---|---|
| Torsion (headline) | — | +1000 N up at the front-left contact patch and −1000 N at front-right, through the links. At the rear the opposite, scaled by the track ratio so the torque is the same. Net force and moment are zero. |
| Torsion, couples at nodes | — | ±F/4 at each of the four wishbone pickup nodes per side, front and rear opposite. This is the set-up of the SOLIDWORKS studies (beam and solid). |
| Torsion, rear held | — | rear eight wishbone nodes fixed in x, y, z, front couple. This is an upper bound: holding eight nodes stiffens the rear bay. |
| Braking | `load_cases.csv` | 1.5 g, with downforce at the braking speed |
| Cornering | `load_cases.csv` | 1.6 g lateral, with downforce |
| Bump | `load_cases.csv` | 2 g vertical (3 g total wheel load including static), no downforce |
| Corner + brake | `load_cases.csv` | combined, 0.7 × each |

For each driving case:
- The tyre forces go through the links as above.
- Downforce goes on the wing mounting nodes (front share on FB, rear share on RT).
- Gravity and the unsprung corners' own inertia are taken out per corner.

Twist is measured as the rotation about x of each axle's wishbone pickups, from their vertical displacements: atan(Δuz/Δy), averaged over the four pairs. Twist = front − rear. Stiffness = front torque / twist.

## Torsion diagonals (2026-11-18): the frame as it now is

Target: at least 1500 Nm/deg in the headline case (wheel loads through the links, free-free), judged by this beam model.

**Search:** `matlab/stress/frame_diagonal_search.m`, written to `sim/stress/frame_diagonals.txt`.
- **Candidates:** one 25.4 × 1.6 tube across each bay face that had no diagonal: floor, top, transverse planes, and the sidepod floor and top.
- **Clearance:** each candidate is checked against frame_layout's envelopes (driver, battery, motor, diff; 10 mm, helmet 50 mm).
- **Dropped, too close:**

  | Diagonal | Short by | Envelope |
  |---|---|---|
  | footwell floor FS2_L–FH_L | 12 mm | heel rest |
  | rear box floor | 16 mm | diff |
  | footwell top | 23 mm | legs |
  | engine bay top | 73 mm | motor |
  | rear box top | 20 mm | diff |
  | main hoop plane | 39 mm | motor |
  | RS1 plane | 40 mm | diff |

- **Excluded on purpose:**
  - the cockpit top, which is the cockpit opening;
  - the FS2 plane, which crosses the window between the FS2 cross tubes that the pedals and feet pass through.
- **Method:**
  - floor only and floor plus top: every subset;
  - all candidates: subsets in order of added mass. The first one that reaches the target is the lightest.
  - Two diagonals are needed in every set (front box floor and front box top), so they are fixed. 1507 subsets were solved.

**What each family can reach** (new rear hardpoints; 834 Nm/deg and 41.9 kg without them). Frame kg is the weldment-scaled mass (centre-line × 0.964) since the evening of 2026-11-18; the search picks the same sets either way:

| Diagonals | Best Nm/deg | Frame kg | Reaches 1500? |
|---|---|---|---|
| floor only (4 that fit) | 1161 | 44.29 | no |
| floor + top (8 that fit) | 1368 | 46.47 | no |
| every candidate that fits (13) | 1588 | — | yes |
| **lightest set reaching 1500 (chosen)** | **1503** | **47.50 (+5.56)** | yes |
| same set but with the footwell floor diagonal instead of the sidepod tops (needs the heel rest 12 mm higher) | 1523 | 46.4 | yes, 1.1 kg lighter |

**Chosen set:** 10 tubes, in `matlab/cad/frame_layout.m`:
- Floor:
  - nose floor FB_L_R–FS1_L_L;
  - front box floor FS1_L_R–FS2_L_L;
  - cockpit floor FH_L_R–MH_L_L, under the seat, 17 mm beyond the 10 mm torso rule;
  - engine bay floor MH_L_R–RS1_L_L.
- Top:
  - nose top FB_U_R–FS1_U_L;
  - front box top FS1_U_R–FS2_U_L;
  - rear top RT1_R–RRK_L.
- Front bulkhead plane FB_L_R–FB_U_L, behind the anti-intrusion plate.
- Sidepod top diagonal FH_M–SP2_U on both sides, 5 mm beyond the battery rule.

The SOLIDWORKS group sizes are unchanged (all 25.4 × 1.6). No new diagonal comes within one tube diameter of another tube except at its own nodes (checked for every tube pair).

**Before and after** (same loads, same rear hardpoints; "before" = the frame files with these 10 tubes dropped, `frame_fe(struct('drop_tubes', ["_diag", "FH_M-SP2_U"]))`):

| | Before | After |
|---|---|---|
| Torsion, through the links | 834 Nm/deg | **1503 Nm/deg** |
| Torsion, couples at the nodes | 758 | 1386 |
| Torsion, rear held (upper bound) | 1798 | 2589 |
| Frame tubes (weldment-scaled; centre-line 43.5 / 49.3 kg) | 41.9 kg | 47.5 kg (+5.6) |
| Stiffness per kg | 19.9 | 31.6 Nm/deg/kg |
| Peak at the test torque | 203 MPa, FH_T_cross | 197 MPa, FH_T_cross |
| Car without driver (mass budget, brackets and welds 13 % of the frame) | 227.5 kg | 233.8 kg |
| CG x, z (with driver) | 910, 313 mm | 903, 312 mm |

Twist at the test torque fell from 1.43° to 0.79°.

### Driving cases with the diagonals

These use `load_cases.csv` regenerated at 303.8 kg with driver (frame at the weldment's 47.5 kg) and the as-built aero, CP (ClA 3.89, 43 % front), since the evening of 2026-11-18. Before that: 305.6 kg and variant C (ClA 3.98); every peak moved by 1 MPa or less.

| Case | Peak von Mises, MPa | Where | FoS on yield | Max elastic deflection |
|---|---|---|---|---|
| Cornering 1.6 g | 109 | RRK-RT1_R (rear rocker mount) | 3.99 | 1.16 mm at FBT_R |
| Braking 1.5 g | 86 | RRK-RT1_R | 5.07 | 0.48 mm |
| Bump 3 g total | 162 | RRK-RT1_R | 2.68 | 0.35 mm |
| Corner + brake | 107 | FS2_L-FH_L_R | 4.08 | 1.42 mm at FS2_L_R |

**Bump stress rose, but not because of the diagonals.** It went from 123 MPa (2026-11-17) to 163 MPa (162 MPa at the weldment mass). Without the diagonals, on the same loads, it is 167 MPa.

The rise comes from the rear suspension re-optimisation for the joint margin. The rear upper inner pivots moved 30 mm outboard, to y 350. RT1/RT2 sit on them, so the rocker-mount tube RRK–RT1 now runs at an angle across 60 mm, where it used to run straight.

Every case is still above the 1.5 FoS wanted on yield. This beam model has no stress concentration, so a factor of 1.5 to 3 at the welds applies on top.

The largest cornering deflection fell from 2.13 mm (FB_U, front bulkhead top) to 1.16 mm. In corner + brake, the deflection at the front pickup FS2_L fell from 1.79 to 1.42 mm.

## Earlier results (frame of 2026-11-17, 43.1 kg, before the diagonals)

### Torsion

| Set-up | Stiffness, Nm/deg | Peak von Mises at the test torque |
|---|---|---|
| **Wheel loads through the links, free-free** | **841** (1194 Nm, 1.42°) | 199 MPa in FH_T_cross (front hoop top cross tube) |
| Couples at the wishbone nodes, free-free | 763 | 89 MPa, FH_T_cross |
| Rear pickups held (upper bound) | 1960 | 71 MPa |

- Mass efficiency: 841 / 43.1 = **19.5 Nm/deg per kg**.
- Where the twist happens (through-the-links case, rotation about x along the car):
  - front bulkhead to front hoop (x −300 to 650): 1.00°;
  - front hoop to main hoop (650 to 1250): 0.48°;
  - main hoop to the rear axle (1250 to 1700): 0.34°.
  - The front bay is the softest part of the frame, then the cockpit.

**Finding: the frame is torsionally soft.** Formula Student frames of this mass are usually 1500 to 3000 Nm/deg. At 841 Nm/deg the frame is roughly as stiff as the roll stiffness the springs give, so it will soak up part of the load transfer the springs and anti-roll bars are meant to set.

**Why:** the side planes of every bay are triangulated, but no horizontal plane is. Neither the floor nor the top of any bay has a diagonal; each is a rectangle of two longitudinals and two cross tubes. A bay with an untriangulated face resists twist only by bending its tubes.

**Levers, tested** with `frame_fe(struct('extra_tubes', [...]))`. This what-if option adds 25.4 × 1.6 tubes in the model only and changes no file.

| Added tube(s) | Nm/deg | Frame kg |
|---|---|---|
| none (as built) | 841 | 43.1 |
| front bay top FS1_U_R–FS2_U_L | 850 | 43.7 |
| nose floor FB_L_R–FS1_L_L | 857 | 43.6 |
| rear bay floor RS1_L_R–RS2_L_L | 898 | 43.7 |
| rear floor MH_L_R–RS1_L_L | 931 | 43.7 |
| front bay floor FS1_L_R–FS2_L_L | 937 | 43.7 |
| cockpit floor FH_L_R–MH_L_L | 1032 | 43.9 |
| floor FS2_L_R–FH_L_L | 1035 | 43.8 |
| floor FS2–FH + cockpit floor | 1161 | 44.6 |
| floor FS1–FS2, FS2–FH, cockpit, MH–RS1 | **1255** | 45.8 (27.4 Nm/deg/kg) |
| all six floor diagonals | 1281 | 46.8 |

- Floor diagonals do the work; top diagonals barely help, because the top of a bay is already partly closed by the hoops.
- Four floor diagonals take the frame from 841 to about 1250 Nm/deg for 2.7 kg.
- Going further needs the cockpit top, which is open by rule: the driver gets in there. That is the main limit, and it calls for a stiffer front hoop bracing and side-pod structure rather than more floor tubes.
- The cockpit floor diagonal runs under the seat and must be checked against the driver package.
- Peak torsion stress at the test torque rises from 199 to about 245 MPa with the diagonals: the stiffer frame takes more load in the hoop-top cross tube.

This was a what-if when it was written. The design decision was taken on 2026-11-18 (see the section above).

### Driving cases

| Case | Peak von Mises, MPa | Where | FoS on yield | Max elastic deflection |
|---|---|---|---|---|
| Cornering 1.6 g | 86 | RRK-RT1_R (rear rocker mount) | 5.09 | 2.01 mm at FB_U_L (front bulkhead top) |
| Braking 1.5 g | 63 | RRK-RT1_R | 6.89 | 0.46 mm |
| Bump 3 g total | 123 | RRK-RT1_L (rear rocker mount) | 3.53 | 0.30 mm |
| Corner + brake | 109 | FS2_L-FH_L_L | 4.00 | 1.74 mm at FS2_L_R (front pickup) |

These use `sim/stress/load_cases.csv` as regenerated by the CFD session at 21:42, with the CFD downforce, which is about 10 % less on C than the estimate.

Every case is above the 1.5 factor of safety wanted on yield. The highest stresses are at the rear rocker mounts and the front suspension bay, where the pushrod and wishbone loads go in. Those tubes need the most care at the brackets: the beam model has no stress concentration there.

The largest pickup deflection, about 1.8 mm in cornering, is at the front. That is where compliance shows up as camber and toe change, the same front bay as the torsion finding.

## Self-test (hand-checkable)

`frame_fe('--selftest')` checks:
- a single cantilever tube: tip deflection PL³/3EI and root stress M/Z;
- the same tube in pure torsion: twist TL/GJ, von Mises √3·τ;
- axial: PL/EA;
- inertia relief on two masses: acceleration P/m;
- the frame torsion case is antisymmetric (left and right uz equal and opposite);
- every driving case's solved acceleration is within 5 % of the case.

## Limits

- Linear static, small deflection.
- Rigid joints at node centres. The fused solid model, which has finite joints and wall flexibility, agrees within 1 % in torsion: on this frame the two effects cancel. Welds as built are softer than either model.
- No brackets, no weld detail, no fatigue.
- The peak stresses are nominal: real values near the welds are higher by a stress-concentration factor of roughly 1.5 to 3. The FoS above should be read against that.

## Cross-check on solids (SOLIDWORKS Simulation, 2026-11-18): the beam model's torsion is confirmed within 1 %

`python tools/sw_run.py FrameAnalysis 4` (`tools/sw_harness/FrameAnalysis.cs`). Report: `sim/stress/frame_analysis_report.txt`. Mesh study: `sim/stress/frame_analysis_mesh_study.txt`. Overlap study: `sim/stress/frame_analysis_ov05_report.txt` and `_ov15_report.txt`.

### The analysis-only solid frame

`cad/analysis/frame_analysis.SLDPRT` is a separate part. It is built by the harness from the same `cad/frame/frame_nodes.csv`, `frame_tubes.csv` and `frame_trims.csv` as the production chassis. `chassis.SLDPRT` is never opened.

**Construction:**
- Every tube is a hollow cylinder on its centreline, with OD and wall from the CSV.
- **Coped ends:** where `frame_trims.csv` trims a tube at a node, the tube runs to the node centre and is coped against each of its boundary tubes by a cylinder of the boundary tube's radius minus 1.0 mm. The end therefore sits 1.0 mm deep in the neighbour's 1.6 mm wall. The two solids share volume, and the neighbour's bore stays closed. This is the weldment's cope, pushed 1 mm into the wall.
- **Run-through ends:** where a tube is not trimmed (it runs through, or is one of two collinear halves), it runs OD/2 past the node, so it covers the copes of the tubes trimmed against it, at corners too.
- **Fusing:** all 124 tubes are united into one body in about 15 s. Count: 196 coped ends, 52 run-through ends. A few cope scraps under 6 mm³ were left out.
- **Mass:** 47.0 kg of steel, against 49.3 kg for centreline-length tubes. The difference is the tube ends inside their neighbours at the joints. The mass budget now uses 47.5 kg (see the end of this section).
- **Load faces:** a 40 mm cube is imprinted on the body around each of the 20 loaded nodes, which splits the tube faces there.

### The study

- Static, solid mesh (second-order tetrahedra), AISI 4130 normalised (E 205 GPa, as frame_fe).
- Free-free with inertia relief, no soft springs. The solver reports zero unbalanced force and moment.
- **Loads:** the two free-free torsion cases of frame_fe, written by it to `sim/stress/frame_torsion_loads.csv`:
  - **nodes:** ±F/4 at the 16 wishbone nodes (front couple 526.5 Nm, the rear one opposite);
  - **links:** the 24 link forces of the headline case (1000 N up and down at the front contact patches, the same torque the other way at the rear) at the real inner pickup points, 1200 Nm per axle.
- **Load application:** each force is a remote load (direct transfer, distributed coupling) at its point, on the faces inside its node's cube. It reaches the frame spread over the joint, as through a bracket. A force at the pickup point equals frame_fe's force plus bracket moment at the node.
- **Twist,** measured as in frame_fe: per axle, the mean of atan(Δuz/Δy) over the four left/right wishbone node pairs. uz at a node is the mean over the mesh nodes on the faces in its cube (1,700 to 3,700 nodes each). Stiffness = frame_fe's torque / (front twist − rear twist).

### Result

| Case | Solid, 5 mm mesh (1.87 M nodes) | Solid, 4 mm mesh (2.93 M nodes) | frame_fe (beam) | Difference at 4 mm |
|---|---|---|---|---|
| Couples at the wishbone nodes | 1379 Nm/deg | 1374 Nm/deg | 1386 Nm/deg | −0.9 % |
| Wheel forces through the links (headline) | 1509 Nm/deg | 1504 Nm/deg | 1503 Nm/deg | +0.1 % |

**Mesh convergence:** going from 5 to 4 mm changes the stiffness by 0.3 % or less. A 3 mm mesh (about 6 M nodes) failed in both studies with mesh error 8 after about 250 s. Code 8 is not in the API's documented list (0–7), and the cause was not found; memory or a size limit of the Student licence are possible. So the wall is resolved by one or two quadratic elements through its 1.6 mm, and that was not refined further.

**Overlap sensitivity** (5 mm mesh): the overlap only makes the union possible; it does not change the result.

| Overlap into the neighbour's wall | Fused volume | Nodes case | Links case |
|---|---|---|---|
| 0.5 mm | 5990.7 cm3 | 1379 Nm/deg | 1509 Nm/deg |
| 1.0 mm (used) | 5990.6 cm3 | 1379 | 1509 |
| 1.5 mm | 5989.9 cm3 | 1379 | 1509 |

Once a tube end sits inside its neighbour's wall, the union is the same shape for any overlap between 0 and the 1.6 mm wall.

**Checks on the solution:**
- Left and right displacements are equal and opposite within 2 %.
- Inside each node's 40 mm cube, the spread of uz is 0.07 to 0.17 mm (nodes case). That is what a rigid rotation of 0.2° across 40 mm gives, so every joint moves as one piece. In the 2026-11-17 weldment try, unjoined tubes showed spreads of 50 to 160 mm.
- The front/rear split of the twist differs from frame_fe by an almost equal amount at both axles (nodes case: front 0.218° vs 0.256°, rear −0.165° vs −0.124°). That is a rigid-body rotation about x. It comes from the inertia-relief reference: frame_fe carries the 300 kg of lumped sprung masses, the solid only its own 47 kg of steel. It cancels in the front − rear twist that defines stiffness.
- **Peak von Mises: not a frame stress.** It is 162 MPa (nodes) and 668 MPa (links) at 4 mm, and does not converge between meshes (256 and 648 MPa at 5 mm). Both peaks lie inside a load cube, 17 mm from a pickup node, where a whole link force enters through a few faces. The frame stresses in this document stay frame_fe's. The solid model was not used to check them.

### What it says about both models

- **The beam model's torsional stiffness is confirmed** to about 1 % in both load cases. The 1503 Nm/deg headline holds, and so does the diagonal search judged by it.
- **The agreement is closer than the modelling differences would suggest.** Two effects the beam model ignores push in opposite directions:
  - Finite joints stiffen the solid: the tube ends overlap inside the joint, so the free tube lengths are shorter than node to node.
  - Local wall flexibility softens it: tube walls ovalise where a neighbour lands on them, which rigid beam joints cannot show.

  In this frame the two cancel to within 1 %. This run does not show how large each one is separately. On a frame with shorter tubes or thinner walls, they need not cancel.
- **What neither model includes,** so this check does not cover it:
  - welds as built (both models assume perfectly fused joints);
  - brackets and their own compliance;
  - heat-affected material;
  - fabrication tolerances;
  - the suspension links' own stretch.

  A measured frame will be softer than both, by an amount neither model can say. A physical torsion test is the remaining check.
- **Mass:** the solid has 47.0 kg of steel against frame_fe's 49.3 kg. The beam model counts full centreline lengths, which overlap at the joints. The CAD weldment (47.5 kg in BuildTubes) agrees with the solid. Since the evening of 2026-11-18 the mass budget's `m_frame` is 47.5 kg, with its CG from the coped CSV tubes (`matlab/cad/frame_trimmed_mass.m`: 46.9 kg, x 840.7, z 335.3 mm), and frame_fe scales its tube masses to it. The trimmed weldment itself reads 45.3 kg in CheckChassis (x 840.3, z 335.5 mm). It is lighter because the mitre-plane cuts at shallow joints remove more steel than a cope does (docs/log.md, 2026-11-18 late).

### The earlier attempt (2026-11-17): why the weldment itself could not be used

`FrameSolid` used a copy of the trimmed weldment `chassis.SLDPRT`. It meshed and solved on the Student licence, but gave 18 to 44 Nm/deg against 763 for the beam model of that frame. One or two tubes floated in every run.

The coped thin-wall ends touch their neighbours only along lines and points, not across faces. Because of that:
- bonded contact joins some contacts and misses others;
- the Combine feature is refused;
- an in-memory union kept 82 of 114 tubes apart.

That step is kept as the record (`sim/stress/frame_solid_report.txt`). FrameAnalysis replaces its result.
