# Frame structural analysis (beam FE)

Model: `matlab/stress/frame_fe.m` (run alone, from `run_all`, or `frame_fe('--selftest')`).
Output: `sim/stress/frame_fe_report.txt` and `media/frame_fe.png`.
Cross-check: the torsion case on the frame as solids in SOLIDWORKS Simulation, `swh FrameSolid` (`tools/sw_harness/FrameSolid.cs`). The result is in `sim/stress/frame_solid_report.txt` and in the last section below.

## Model

| Item | Choice |
|---|---|
| Geometry | `cad/frame/frame_nodes.csv` and `frame_tubes.csv`, the same files the SOLIDWORKS chassis is built from: 50 nodes, 114 tubes, 43.1 kg |
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

- Frame tubes: half of each tube's mass at each end node.
- Items from `matlab/mass_budget.m` go on the nodes that carry them:
  - driver on the cockpit floor and shoulder nodes;
  - battery on the eight sidepod nodes;
  - wings on their mounting nodes;
  - everything else on the nearest four nodes.
- Unsprung corners (44.4 kg) are not on the frame.
- Sprung total on the frame: 254 kg, CG x 958, z 262 mm.

### Boundary conditions

A real car has no fixed point. Every case is solved free-free with **inertia relief**:
1. Find the rigid-body acceleration (3 translations, 3 rotations) that balances the applied loads against the lumped masses: a = (ΦᵀMΦ)⁻¹ΦᵀF.
2. Add the d'Alembert forces −MΦa.
3. Hold a statically determinate 3-2-1 support (FB_L_R in x, y, z; RS2_L_R in y, z; FB_L_L in z). The reactions there are about zero, because the loads now balance.
4. Remove the mass-weighted rigid motion from the displacements.

The driving cases are checked by the acceleration this finds, which must match the case (all within 0.1 %).

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

## Results (frame of 2026-11-17, 43.1 kg)

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

None of this is applied to the frame files: changing the frame is a design decision.

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
- Rigid joints at node centres: real welded joints are a little softer, but the bigger difference is the joint offset (tube ends are not at a point), which beams ignore.
- No brackets, no weld detail, no fatigue.
- The peak stresses are nominal: real values near the welds are higher by a stress-concentration factor of roughly 1.5 to 3. The FoS above should be read against that.

## Cross-check on solids (SOLIDWORKS Simulation): runs, but no valid number

`python tools/sw_run.py FrameSolid 5` sets up the torsion case "couples at the wishbone nodes" on the frame as solids, through the harness:
- copy of `chassis.SLDPRT`;
- static study, solid mesh;
- AISI 4130;
- free-free with inertia relief;
- each node force on the tube edge nearest the node.

That is a load on the geometry, not on a joint. Face loads were not used, because a tube face here runs the full tube length and would spread the load along it.

**Student can run it.** At 5 mm it meshes to 722k second-order tets and 1.46 M nodes in 38 s, and solves in about 60 s.

**The result is not valid:**
- **Stiffness:** the solid model gives 18 to 43 Nm/deg depending on the run, against 763 for the beam model.
- **Joint check:** the step looks at the mesh nodes within 20 mm of each frame node. In every run, one or two tubes do not move with their node; their displacement spreads are huge. A different pair failed each run: FH_M–MH_M_R in one, RS1_L in another. Those tubes are not joined to the frame and float on the soft springs.

**Why:**
- **Geometry check:** the trimmed weldment tubes touch their neighbours. The closest distance is under 0.01 mm for 356 of the 444 tube pairs that share a node, and all 114 tubes form one connected group.
- **But only along lines and points, not across faces.** The coped ends of thin-wall tubes meet the next tube's cylinder at an edge. Bonded contact needs touching faces, so it joins some of these contacts and misses others.
- **Combining the bodies fails for the same reason:**
  - the Combine feature is refused;
  - an in-memory Boolean union (`--fuse`) keeps 82 of 114 tubes apart, either as a disjoint result or with error 547.

**What would make it work** (not done; it changes the CAD build, not the analysis):
- Build the solid frame for analysis separately from the weldment: each tube extended 1 to 2 mm into its neighbours, then all united. Overlapping solids fuse cleanly.
- Or add weld beads (fillet bodies) at each node.

Until then, the frame numbers in this document are the MATLAB beam model's. The beam model is self-tested against hand calculations, but nothing independent has checked it on the full frame yet.
