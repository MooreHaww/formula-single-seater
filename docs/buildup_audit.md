# Build-up film audit (2026-11-28)

What the final assembly `cad/formula_single_seater.SLDASM` contains, what the build-up film showed before this audit (`media/showcase/car_buildup.mp4` of 2026-11-25, made by `tools/sw_harness/ShowcaseBuild.cs`), and what the re-recorded film shows.

**How I read the brief.**
- "Every component in the final assembly" means every component in the SOLIDWORKS assembly after `python tools/sw_run.py rebuild`. The film is made from that assembly, so it can only show what the assembly holds.
- The brief's list (steering, powertrain, connectors and so on) is a checklist. Where a category is **not in the CAD at all**, it is listed in the second table. It is not modelled here: that would be new design work (envelopes, mounts, masses), not a film fix.
- "Missing from the film" covers both things: a component that never appears, and a component that appears but cannot be seen in its still.

## 1. Components in the assembly

52 top-level components after the first 2026-11-28 rebuild (48 before; the 4 wing supports are new); 80 after the second, with the 28 packaging envelopes of section 4. Counts are SOLIDWORKS components; "per side" parts are separate R and L components.

| Component | Components | Made by | Old film (2026-11-25) | New film (2026-11-28) |
|---|---|---|---|---|
| `master_layout`: planes, axle axes, hardpoints (reference geometry, no solid) | 1 | BuildLayout | hidden throughout (correct: not a part) | hidden throughout |
| `chassis`: 123 tubes in 7 groups (bulkhead, front, sis, hoop, hoop_brace, sidepod, rear), incl. the 9 torsion diagonals | 1 (123 bodies) | BuildTubes, TrimTubes | yes: 21 stills, 3 per group | yes, unchanged |
| Lower wishbones `FL/FR/RL/RR_lwb` | 4 | SuspensionParts | **one still with all links together, dark grey against the blue frame: hard to see** | own still, light grey |
| Upper wishbones `*_uwb` | 4 | SuspensionParts | (same still) | own still |
| Uprights `*_upright` | 4 | SuspensionParts | yes, with the hubs | yes, with the hubs |
| Hubs `*_hub` | 4 | SuspensionParts | yes | yes |
| Front tie rods (steering) and rear toe links `*_tie` | 4 | SuspensionParts | (in the links still) | own still, after the uprights they connect to |
| Pushrods `*_push` | 4 | SuspensionParts | (in the links still) | own still, amber |
| Rims `rim_front`, `rim_rear` (left: second instances) | 4 | BuildBodies, BuildAssembly | yes | yes |
| Tyres `tyre_front`, `tyre_rear` (left: second instances) | 4 | BuildBodies, BuildAssembly | yes | yes |
| Floor and diffuser `floor_diffuser` | 1 | BuildBodies | yes | yes |
| Sidepods `sidepod_R`, `sidepod_L` | 2 | BuildBodies | yes | yes |
| Nose `nose` | 1 | BuildBodies | yes | yes |
| Front wing: `fw_main`, `fw_flap1`, `fw_flap2`, `fw_endplate_R/L` | 5 | BuildBodies | yes, **floating** (no supports existed) | yes, on its supports |
| **Front wing supports J** `fw_support_R/L` (new) | 2 | BuildBodies (`build_parts.build_fw_support`) | **no (did not exist)** | own still, before the front wing |
| Rear wing: `rw_main`, `rw_flap1`, `rw_flap2`, `rw_endplate_R/L` | 5 | BuildBodies | yes, **floating** | yes, on its supports |
| **Rear wing supports F** `rw_support_R/L` (new) | 2 | BuildBodies (`build_parts.build_rw_support`) | **no (did not exist)** | own still, before the rear wing |
| **Packaging envelopes** `env_*` (section 4; not designed parts) | 28 | BuildBodies (`envelopes.py`) | no (did not exist) | eight stills after the pushrods: rockers and dampers, steering, brakes, motor and drive, batteries, electronics, seat, driver |
| Ground plate `cad/showcase/ground.SLDPRT` | (film only, added and not saved) | ShowcaseBuild | yes | yes |

**Result of the audit.**
- **Missing from the old film:** the four wing supports (they did not exist in the CAD), so both wings floated.
- **In the old film but not visible:** the 16 links (8 wishbones, 4 tie rods / toe links, 4 pushrods) appeared all at once in one still, dark grey (0.28) next to dark-blue tubes, mostly hidden behind the frame. They now come in four stills (lower wishbones, upper wishbones, tie rods and toe links, pushrods), in light grey with amber pushrods.
- Everything else in the assembly was in the old film and still is.
- Film order now (second session): frame (7 groups), lower wishbones, upper wishbones, uprights and hubs, tie rods and toe links, pushrods, rockers and dampers, steering, brakes, motor and drive, batteries, electronics, seat, driver, rims and tyres, floor, sidepods, nose, front supports, front wing, rear supports, rear wing. The envelopes come in inboard systems first, each after what carries or drives it; the driver last before the wheels and bodywork. 44 stills, 21.2 s, MP4 0.57 MB, GIF 0.45 MB. That is inboard to outboard for the suspension (wishbones on the frame pickups, uprights on the wishbones, links to the uprights), and each wing after the supports that carry it.

## 2. Parts of the car that are not in the CAD (so not in any film)

These are in the mass budget (`params/car_params.txt`) or in the design, but no SOLIDWORKS component existed for them at the first audit. Since the second session on 2026-11-28 most of them have a packaging envelope (section 4): simple bodies with the budget mass, not designed parts. The last column gives that state.

| Category | What the car has (budget line or design) | In the CAD (first audit) | Since section 4 |
|---|---|---|---|
| Steering | steering wheel, column and rack (in `m_cockpit`, 3.0 kg GUESS) | only the tie rods (`F*_tie`); their inner ends sit on the layout's rack points | envelopes: rack, column, wheel |
| Suspension connectors | rockers (`RRK` node and rocker ratios exist), dampers and springs, rod ends and ball joints | none: the pushrod ends at the layout's `pushrod_in` point (no rocker geometry in the parameters); ball joints are named points only | envelopes: 4 rockers, 4 spring/dampers; rod ends and ball joints still not |
| Brakes | discs and calipers (in the corner lines), master cylinders, lines (`m_brake_hydraulics`) | none | envelopes: 4 discs with calipers; hydraulics not |
| Powertrain | motor (Emrax 228 class, `m_motor`), chain drive with diff, halfshafts and sprockets (`m_chain_drive`), inverter and HV (`m_inverter_hv`) | none (the frame and the CFD leave envelopes for them) | envelopes: motor, diff, chain, 2 halfshafts, inverter |
| Energy storage | two sidepod battery packs (`m_battery`, 45 kg) | none (the frame's sidepod battery structure and the sidepod's clearance box only) | envelopes: 2 packs |
| Electronics and cooling | LV electronics, radiator, pump, hoses | none | envelope: LV electronics / ECU; cooling not |
| Cockpit | seat, harness, pedal box, firewall, headrest | none | envelope: seat; harness, pedal box, firewall, headrest not |
| Driver | 70 kg (`mass_driver`) | none (boxes and a sphere in the packaging checks and the CFD body only) | envelopes: legs, torso, helmet (the `frame_layout.m` boxes) |
| Brackets and welds | 6.4 kg GUESS, incl. the wing-support mounts | none: the supports touch the tube, wing and nose; no clamp, insert or bolt is drawn | not |
| Bodywork behind the main hoop | the CFD model has a motor cover (hull tail) | none: the parts stop at the sidepods; the rear supports therefore stand on the frame tube `RT2_cross` | not |

## 3. Checks

- The ShowcaseBuild report (`media/showcase/frames_build/showcase_build_report.txt`) counts every group above and fails if a count is off (4 of each link type, 8 uprights and hubs, 8 rims and tyres, 5 + 5 wing parts, 2 + 2 supports) and lists any component it does not know (none).
- The film is captioned per stage; the stage counter in the corner counts the stages above.

## 4. Packaging envelopes (added 2026-11-28, second session)

**How I read the brief.**
- Each budget line that has no CAD body gets simple envelope parts (boxes, cylinders, one sphere). Their sizes come from the parameters where these exist; otherwise the assumption is written in `cad/generate/envelopes.py`. Each envelope's mass comes from its budget line.
- The envelopes take their mass from existing budget lines and add none, so `mass_car` does not change because of them.
- The CG computed from the envelope geometry is reported next to the budget CG. Neither one was adjusted.
- Clashes are reported here and not fixed. Nothing in the frame or the suspension was changed.
- The envelopes are **space reservations, not designed parts**: no mounts, no fasteners, no detail.

**What was added.**
- 28 parts `env_*`, made by `cad/generate/envelopes.py` (called by `build_parts.py`, so `python tools/sw_run.py rebuild` builds them).
- BuildAssembly imports and mates them like every other STEP body. It sets each part's density to mass / volume from `cad/generate/envelopes_mass.csv`, so SolidWorks' mass of each part equals the mass below.
- The film shows them in eight stages, after the pushrods and before the wheels.

| Envelope (parts) | Shape and position (mm, car axes) | Mass (kg) and budget line | Size from |
|---|---|---|---|
| Driver legs `env_driver_legs` | box x 200..850, y ±190, z 150..430, minus the torso box | 21.0, `mass_driver` (30 %, the `x_driver` comment) | `matlab/cad/frame_layout.m` `envelopes()` (the box the frame tubes were checked against) |
| Driver torso `env_driver_torso` | box x 790..1250, y ±230, z 120..649. Its back face is in the main-hoop plane. Built from hip (850, 180), seat back 40° from vertical, shoulder 560 mm up the seat back at (1210, 609). | 43.0, `mass_driver` (GUESS split of the 70 %) | same |
| Driver head `env_driver_head` | helmet sphere r 150 at (1339, 0, 762), 200 mm beyond the shoulder along the seat back, minus the torso box | 6.0, `mass_driver` (GUESS: head with helmet) | same |
| Seat `env_seat` | pan x 600..1250, y ±200, z 100..120; back x 1250..1265, z 100..600 | 1.0, `m_cockpit` (comment: seat 1.0) | under and behind the driver envelope (assumption) |
| Steering rack `env_steering_rack` | cylinder r 20 along Y, y ±200, at x −70, z 181.5 | 1.4, `m_cockpit` (GUESS split of "wheel, column and rack 3.0") | on the tie-rod inner points (±245; 45 mm left for the rack bar) |
| Steering column `env_steering_column` | cylinder r 15 from the pinion (−70, 0, 202), starting 25 mm up the column, to the wheel | 0.6, `m_cockpit` (GUESS split) | assumption |
| Steering wheel `env_steering_wheel` | disc d 260 × 30 at (600, 0, 480), square to the column (22.6° up) | 1.0, `m_cockpit` (GUESS split) | 50 mm behind the front hoop; its top (z 600) is below the front-hoop top (z 680) |
| Rockers `env_rocker_FR/FL/RR/RL` | disc r 40 × 20, axis X, centred on the rocker mount node (FBT_R/L at (0, ±280, 430); RRK_R/L at (1550, ±290, 470)) | 0.3 each, `m_susp_links_*` (comment: rocker 0.3) | frame nodes. The layout's pushrod inner point is 28 mm (front) or 22 mm (rear) from the node. |
| Spring/dampers `env_damper_*` | cylinder d 50, 200 long, along Y, from 40 mm inboard of the node towards the centreline; 48 mm above the node (10 mm clear of the mount cross tube) | 0.6 each, `m_susp_links_*` (comment: damper 0.6) | assumption: no damper hardpoints exist; the inner anchor is not designed |
| Brakes `env_brake_*` | disc d 190 (bore 100) × 6 in the wheel's centre plane plus a caliper box 45 × 40 × 80 behind the wheel centre, fused | 1.8 each, `m_corners_*` (comment: brake 1.8) | inside the 10 in rim (assumption) |
| Motor `env_motor` | cylinder d 230 × 110, axis Y, at (1340, 0, 270) | 12.3, `m_motor` | `motor_*` parameters, as `frame_layout.m` |
| Diff `env_diff` | cylinder r 80, y ±150, on the rear axle (1550, 222) | 6.0, `m_chain_drive` (comment: diff 6.0) | `frame_layout.m` |
| Chain `env_chain` | hull of the sprockets (motor r 45, diff r 100), y 155..175 | 2.3, `m_chain_drive` (comment: sprockets and chain 2.3) | assumption. The motor ends at y 55, so a shaft extension is implied. |
| Halfshafts `env_halfshaft_R/L` | cylinder r 15 along Y at the axle, from the diff (or chain) to y ±470 | 1.0 each, `m_chain_drive` (comment: halfshafts 2.0) | assumption |
| Battery packs `env_battery_R/L` | box x 690..1220, y ±(335..500), z 105..295 | 22.5 each, `m_battery` | `battery_*` parameters, as `frame_layout.m` and the sidepod clearance box |
| Inverter and HV `env_inverter` | box 170 × 280 × 120 centred at the budget position (1380, 0, 500) | 10.0, `m_inverter_hv` | assumption (170 long so that it clears the RT1 cross tube by 12 mm) |
| LV electronics / ECU `env_lv_electronics` | box 120 × 300 × 60 centred at the budget position (500, 0, 450) | 3.0, `m_lv_electronics` | assumption |

Per budget line: envelopes 70 of 70 kg driver, 4.0 of 9.5 kg cockpit (harness, pedal box, firewall and headrest are not modelled), 1.8 of 4.2 kg per axle of links (the wishbones, pushrods and tie rods are the SolidWorks members), 3.6 of 22.2 kg per axle of corners, and the whole of the motor, chain drive, battery, inverter and LV electronics lines. Still not in the CAD: brackets and welds, cooling, brake hydraulics, fasteners, harness, pedal box, firewall and headrest.

**Three placements I corrected myself, not reported as clashes:** the column started inside the rack, the seat back ran into the helmet, and the dampers sat 2.3 mm above their mount cross tubes. All three were my own envelope choices, with no frame or suspension change behind them. The column now starts 25 mm up from the pinion, the seat back stops at z 600, and the dampers are 10 mm clear.

### Packaging clashes

Rules (`cad/generate/check_clearances.py`, results in `cad/generate/packaging_report.txt`):
- frame tube ≥ 10 mm (the `frame_layout.m` rule);
- tyre ≥ 25 mm at static, ±30 mm travel and ±28° steer;
- brake to its own rim ≥ 5 mm;
- suspension member ≥ 5 mm, static;
- no overlap with a body part, a rim or another envelope.

These clashes are findings. They do not fail the BuildBodies step. Fixes are suggestions only; none was made.

| # | Clash | Size | Suggested fix (not done) |
|---|---|---|---|
| 1 | Seat pan vs lower cross tubes `FH_L_cross`, `MH_L_cross` and the diagonal `FH_L-MH_L_diag` | 7.3 mm gap (rule 10) | The driver envelope's torso bottom (hip z 180 − 60) leaves 27 mm above the 92.7 mm tube tops for the seat. Either lower the seat into a 20 mm pan between the tubes, or raise `driver_hip_z` by 3 mm or more. |
| 2 | Steering column vs `FS2_U_cross` (x 140, z 273) | 5610 mm³ overlap | Route the column above the FS2 upper cross tube (column start higher, or a U-joint ahead of FS2), or move the rack. |
| 3 | Steering rack vs the front lower diagonal `FS1_L-FS2_L_diag` | 231 mm³ overlap | The diagonal crosses x −70 at z 150. Raise the rack about 12 mm (to the 10 mm rule), or move it to where the diagonal is lower. |
| 4, 7 | Front rockers FR, FL vs their own mount node (`FBT_cross`, joint, `FBT-FS1_U`, `FBT-FS2_U`) | about 46 000 mm³ each | The layout puts the pushrod's inner end 28 mm from the node at the same x, so a rocker there sits in the node's tubes. Mount the rocker on a bracket beside the node (offset in x or y) and move `pushrod_in` with it. This changes the suspension hardpoints. |
| 5, 8 | Front rockers FR, FL vs the nose | 3649 mm³ each | The rocker disc on the node reaches through the nose shell. The nose needs a blister there, or the rocker has to sit lower or further inboard. |
| 6, 9 | Front dampers FR, FL vs the nose | 4137 mm³ each | Same: lay the dampers inside the nose (lower, along x), or give the nose a blister. |
| 10, 11 | Rear rockers RR, RL vs their own mount node (`RRK_cross`, joint, `RRK-RT1`, `RRK-RT2`) | about 43 000 mm³ each | As #4: a rocker bracket beside `RRK`, and `pushrod_in` moved with it (22 mm from the node now). |
| 12 | Chain vs `RS1_U_cross` and `RS1_L_cross` (x 1485 to 1490) | 10 134 + 2143 mm³ | The chain run from the motor (x 1340) to the diff (x 1550) passes through the rear box's front cross tubes. Fix: move the motor behind RS1 so the chain stays inside the rear box, or make one of the RS1 cross tubes removable (bolted). |
| 13, 15 | Halfshafts R, L vs the rear diagonals `RS1_L-RS2_U` | 50 mm³ each | The diagonal passes the axle line (x 1550) at z 188, 34 mm below the shaft centre. Shift the diagonal's lower node, or check this against a real CV joint size. |
| 14, 16 | Halfshafts R, L vs the rear pushrods RR, RL | 6860 mm³ each | The rear pushrod lies in the axle's x plane (x 1550 at both ends) and crosses the halfshaft at y 449, z 222. Move the pushrod's inner or outer point in x (about 40 mm or more), or run the pushrod in front of the shaft. This changes the suspension hardpoints. |
| 17 | Driver legs vs steering wheel | 387 cm³ | The legs envelope is one box up to z 430 all the way from x 200 to 850, so it takes the knee space the wheel needs. A wheel below the front-hoop top cannot clear it. Refine the legs envelope (shins and thighs sloped), or check with the FS template. |
| 18 | Driver legs vs steering column | 214 cm³ | Same cause: the column runs between the legs, and the box has no gap between them. Split the legs box into two legs. |
| 19 | Driver legs vs LV electronics box (budget position x 500, z 450) | 360 cm³ | Move the LV box up or forward (dash above the knees), or give it a budget position outside the legs. |
| 20 | Driver torso vs motor | 269 cm³ | The motor (x 1340, d 230) starts at x 1225, 25 mm ahead of the main-hoop plane where the torso envelope's back face is. Move the motor 25 mm or more rearward (`motor_x` 1365 or more, which shortens the chain to the diff), or lower it. |
| 21 | Seat back vs motor | 264 cm³ | Same cause as #20: the seat back stands in the main-hoop plane and the motor reaches into it. |
| 22 | Steering column vs LV electronics box | 78 cm³ | The budget position for the LV electronics sits on the column's path. Split the box either side of the column, or move it (see #19). |

Found by SuspensionCheck, which moves the wheels ±30 mm. The envelopes do not move: they are mated to the car, not to the hubs or rockers.

| # | Clash | Size | Suggested fix (not done) |
|---|---|---|---|
| 23–26 | Brake envelopes FR, FL, RR, RL vs their own rim at +30 and −30 mm travel | 4657 to 5140 mm³ each | An artefact of static envelopes: the brake turns and moves with its wheel. Lock each `env_brake_*` to its hub in SuspensionAssembly, as the rims are; then the 5 mm rim check holds over travel too. |
| 27–30 | Rocker envelopes FR, FL, RR, RL vs their pushrods at +30 mm bump | 125 mm³ front, 468 mm³ rear | Partly an artefact (a real rocker turns with the pushrod). It also shows that the pushrod's inner end sweeps through the rocker's space: the rocker needs its own geometry (pivot, arms) before the sweep can be checked. |

In SolidWorks, the BuildAssembly interference check finds 19 pairs, matching #2 to #12, #13, #15 and #17 to #22. It does not see #1, which is a gap and not an overlap, or #14 and #16, because the pushrods are added later; SuspensionCheck finds those two at 1421 mm³ each, against the hollow tube. The volumes differ from the Python check because SolidWorks uses the trimmed weldment and hollow links, and Python uses solid cylinders with joint cubes.

**No clashes:**
- battery packs (with the frame, sidepods and each other);
- motor and inverter with the frame;
- brakes with their rims (5 mm rule), the uprights and the hubs;
- every envelope with the tyres over travel and steer;
- the driver envelope with the frame (as `frame_layout.m` found).

**Observation, not a clash:** the helmet centre is 89 mm behind the main-hoop plane (x 1339 against 1250). The head passes through the hoop's opening, between the rear braces. This follows from hip x 850, seat back 40° and the main hoop at 1250. The frame_layout.m tube check passes because no tube is near the head. The FS rule lines (helmet 50 mm below the line from the main-hoop top to the front-hoop top, and to the brace) were not checked here.

### CG: budget against CAD

`cad/generate/cad_cg.py` keeps every budget line's mass and puts it at the CAD bodies that stand for it:
- envelopes, STEP bodies and suspension members where they exist;
- the budget position where nothing in the CAD stands for the line.

Nothing was changed in either the budget or the CAD. Report: `cad/generate/cad_cg_report.txt`. All figures are after the wing-mass fix (232.56 / 302.56 kg).

| | Budget CG x / z (mm) | CAD CG x / z (mm) | CAD − budget |
|---|---|---|---|
| Car without driver (232.56 kg) | 920.0 / 302.6 | 891.7 / 295.0 | x −28.3, z −7.6 |
| Car with driver (302.56 kg) | 901.5 / 308.9 | 891.3 / 316.6 | x −10.2, z +7.7 |
| Front axle share, with driver | 41.84 % | 42.50 % | +0.66 points |

Largest differences between a budget line's position and its CAD bodies:
- **Driver:** +50 mm back, +59 mm up. The `frame_layout.m` boxes are uniform-density volumes. The torso box (43 kg) reaches up to the shoulder line, and the head is behind the main hoop. The budget puts the legs at Z 180 and the torso and head at X 960, Z 400.
- **Front wing:** −406 mm. The CAD wing's volume centre is at X −706; the budget assumed the chord stack around X −300.
- **Bodywork:** −392 mm, −60 mm. The nose and sidepods' volume centre is at X 308; the budget's X 700 included the cockpit surround, which is not modelled.
- **Chain drive:** −83 mm. The budget comment places the motor sprocket at X 1850, but `motor_x` is 1340: the comment is out of date.
- **Cockpit:** −94 mm.
- **Corners:** z −16 mm. The budget uses Z 240; the wheel centre is at 222.

Which one is right is not settled here. The CAD positions are better for the bodies that exist, but the envelope masses are spread uniformly, and the driver's mass is certainly not uniform.

**Reconciled later on 2026-11-28.** The budget positions were corrected from the CAD (reasons in each line's comment in `params/car_params.txt`, detail in `docs/log.md`). `cad_cg.py` now places the wings, floor, nose and sidepods at their surface (area) centroids, because they are skins whose mass goes with area; the cockpit parts with no CAD body (pedal box, harness, firewall and headrest) are placed at layout positions. After that the budget and the CAD agree: with driver 894.9 / 319.9 against 895.1 / 319.6 mm; without driver 896.4 / 299.1 against 896.7 / 298.8 mm. The table above is the state before the reconciliation.

**Not checked:**
- the envelopes' own masses (they are the budget's, several of them GUESS);
- moving envelopes (brakes, halfshafts, rockers) over suspension travel, except as listed in #23 to #30;
- the FS template (95th percentile) against the driver envelope;
- cable, hose and cooling routes;
- pedal box, harness, firewall, headrest, radiator;
- access for assembly and service.
