# Wing supports in CFD: plan and progress (rear wing, variants E-H)

**Resume rule:** at the start of every session and after every step, read this file, then update it. Tick a box only when the step is done and checked. The newest status line is at the bottom of "Status".

## How I read the brief (written 2026-11-26, before any work)

- **Base.** Every new variant is CP (C's wings on the as-built SOLIDWORKS bodywork) with only the **rear** wing's idealised pylon replaced by the new support. The front wing keeps CP's pylon (one flat 16 mm plate each side, Y 60-76 mm, from the main element's middle line up into the nose, counted in the front-wing zone `car_fw`). The front wing is out of scope this round.
- **Same envelope as CP's rear pylon**, so only the section shape changes: X 1667 to 1895 mm (chord 228 mm), centred at Y 150 mm, 16 mm maximum thickness, same side outline (from inside the hull tail up into the main element, top edge on the element's middle line). One support in the half model = two per car. The exposed height is about 650 mm (hull top at Z 450-550, wing at Z 1145-1172).
- **The four supports** (each differs from E by one thing):
  - **E:** biconvex circular-arc lens, 16 mm thick at mid-chord, sharp front and back edges.
  - **F:** E with a rounded front edge (front half replaced by a round nose; rear half identical to E).
  - **G:** E plus curved ridges (strakes) on both faces, horizontal at the front, curving up towards the back, to turn air upwards. First try: 3 ridges per face, 10 mm thick, standing 8 mm proud of the face, from 20 % to 85 % of the chord, turned up 20 deg at the back.
  - **H:** E's front half; the rear half flares from 16 mm to a 24 mm wide flat blunt base at the same trailing-edge X.
- **The support gets its own force zone** (`car_rws`), so its force is reported separately; it is still part of the total. CP's pylon sits inside its rear-wing zone `car_rw`, so for CP and CP_bl1 the pylon force is summed from per-face pressure and shear exported from the saved solutions (no re-solve, CP's data untouched), and that sum method is checked against Fluent's own `car_rw` report.
- **Prism layers (decided 2026-11-26: 1 layer for all, reference CP_bl1; F at 2 layers was 1,080,650 cells):** CP has 2 layers and 1,007,086 cells, 41k under the limit. All four are meshed first; if any needs 1 layer, all four use 1 layer and are compared against CP_bl1 (CP with 1 layer), so the comparison stays like for like.
- **Solver:** exactly CP's (`fluent_halfcar.py solve`, defaults, 1200 iterations, force stop). Solves run in the background, one at a time (one Student licence).
- **Order:** E, G, H, F. If a variant does not mesh: at most 3 fix attempts, each for a different cause. For G, simplify the ridges (fewer, larger) and record exactly what changed.
- **Old variant E** (2026-11-18 wake experiment) is deleted; the letters E-H now mean the supports.
- **Trust:** steady RANS, only the ranking is trustworthy. CP's run-to-run spread is about 2.2 % (CP vs CP_bl1 ClA), so no effect under 2.2 % on totals is claimed. The support's own force is the less noisy measure.
- **Not changed:** CP, A, B, C, D data, `params/aero_variants.csv`, SOLIDWORKS files. No Fluent case/data files in git (cfd/cases is git-ignored).

## Variants

| Variant | Section | Status | Cells | Layers | Support force (half car, N, down / drag) | ClA | CdA | Front share | q-ratio 1 / 2 / 3 L |
|---|---|---|---|---|---|---|---|---|---|
| CP | flat 16 mm plate (idealised) | reference, existing run | 1,007,086 | 2 | -0.10 / 4.57 (face export) | 3.89 | 1.66 | 0.43 | 0.64 / 0.92 / 0.98 |
| CP_bl1 | same | reference, existing run | 918,527 | 1 | -0.12 / 4.34 (face export) | 3.98 | 1.67 | 0.43 | 0.65 / 0.91 / 0.97 |
| E_bl1 | lens, 3 mm square edges | solved, checks pass | 977,893 | 1 | -0.1 / 0.8 | 4.14 | 1.69 | 0.40 | 0.66 / 0.92 / 0.97 |
| G | E + 2 ridges per face | NOT RUN: failed to mesh 3 times | | | | | | | |
| H_bl1 | E front, flared 24 mm blunt base | solved, checks pass | 945,815 | 1 | -0.1 / 2.8 | 4.09 | 1.69 | 0.41 | 0.66 / 0.92 / 0.97 |
| F_bl1 | E rear, 5 mm round nose | solved, checks pass | 987,878 | 1 | -0.0 / 0.4 | 4.15 | 1.69 | 0.39 | 0.66 / 0.92 / 0.97 |

## Steps

- [x] 0. Old variant E removed (files, runs, wake data, tables regenerated, docs), nothing else depended on it. Log line added.
- [x] 1. This plan file.
- [x] 2. Front wing mounting checked (`build_front_wing`): one flat plate each side, 16 mm (Y 60-76), from 72-93 % of the main element's chord up to Z 230 into the nose, fused into the front wing and counted in `car_fw`. Untouched this round.
- [x] 3. Code: support builder and `car_rws` zone in `cad/generate/cfd_variants.py`; zone in `cfd/fluent_halfcar.py` (walls, face size as the wing); postprocess reads the extra force column. CP's code path unchanged.
- [x] 4. Geometry E, G, H, F built, 35 of 35 checks pass (`cfd_variants.py --only E,G,H,F`); body, floor, front-wing and rear-wing faces identical in count to CP's (support faces moved to `car_rws`). Pictures: `media/cfd/supports/supports_sections.png`, `supports_3d.png` (`cad/generate/render_rw_supports.py`). F's nose radius 5 mm (front arc re-fitted so the chord stays 228 mm). Shared domain/BOI STEP files restored (only their timestamps had changed).
- [x] 5. Meshed with 1 layer: E 977,893, H 945,815, F 987,878 cells. G failed 3 times (not run).
- [x] 6. E_bl1 solved (1200 it), checks pass (see Status).
- [x] 7. G: not solved (did not mesh in 3 attempts).
- [x] 8. H_bl1 solved, checks pass.
- [x] 9. F_bl1 solved, checks pass.
- [x] 10. CP / CP_bl1 pylon force from the saved solutions (face export), method checked against the zone total.
- [x] 11. Per-solve checks for every run: forces converged, y+, cells, mass balance, per-part forces add up to the total.
- [x] 12. Comparison: support force, ClA, CdA, front share, wake planes, picture of the air near the supports.
- [x] 13. Write-up: results file, log (summary at top, detail at bottom), README Future work (only results that exist), final table, what I would build, what was NOT checked.

## Status

- 2026-11-26: steps 0 and 1 done.
- 2026-11-26: steps 2-4 done. Next: mesh E, G, H, F (step 5).
- 2026-11-26: step 5, first meshing (knife-edged sections, 2 layers): **E failed**, surface mesh "31 self-intersections" (log `cfd/cases/mesh_E.log`). G, H, F meshed in the same chain to see which edge is at fault. Fix attempt 1 for E (cause: knife edges thinner than the 2.5 mm minimum cell size): lens edges cut square 3 mm thick (`RWS_EDGE_T`), arcs re-fitted so chord 228 mm and 16 mm mid-chord thickness stay. Coded, not yet built.
- 2026-11-26: first meshing result: **all four failed** (E 31 self-intersections; G surface mesh failed; H breakout + 10 self-intersecting triangles; F breakout, surface mesh failed). Each had at least one knife edge (H only at the front, F only at the back), so fix 1 (3 mm square edges) is applied to all four: attempt 1 of 3 for each. Logs of the failed try in `cfd/cases/mesh_try1/`. Geometry rebuilt (35 of 35 checks), re-meshing E, G, H, F.
- 2026-11-26: second meshing (3 mm edges, 2 layers; logs in `cfd/cases/mesh_try2/`): **H meshed, 1,036,476 cells. F meshed but 1,080,650 cells, over the limit** -> all variants use 1 prism layer and are compared against **CP_bl1**. E failed (CAD tessellation "Breakout detected", surface mesh failed); G failed (16 self-intersections).
- Fix attempt 2 for E and G (cause: E's and G's front and rear arcs lay on one circle, so each side became ONE face from edge to edge, 4 support faces; F and H, which meshed, have the side split at mid-chord, 6 faces): rear edge 3.05 mm instead of 3.00 (`RWS_EDGE_DIFF`), so the arcs are different circles and the faces stay split. Applies to F's rear arcs too (0.05 mm). Rebuilt, 35 of 35 checks.
- 2026-11-26: chain started (`cfd/cases/chain_EGHF.sh`, progress in `cfd/cases/chain_EGHF.out`): mesh E, G, H, F with `--tag _bl1 --set bl_layers=1`, then solve each that meshed in the order E, G, H, F (about 65 min each). Runs are named E_bl1 ... F_bl1. If G fails again: attempt 3 = fewer, larger ridges.
- 2026-11-26, chain 1 result: **E meshed (977,893 cells, 1 layer); H meshed (945,815).** G failed (breakout, "duplicate front edge" at X 2027, Y 441, Z 1234: rear-wing flap 1, not at the support); F failed (breakout, "front could not be closed" at X 2217, Y 293, Z 1359: rear flap 2). The solves did not start: I passed `--tag _bl1` and the driver adds its own underscore (files came out `E__bl1`); renamed to E_bl1 / H_bl1 (meshes and run folders, `mesh_file` path fixed). Unused 2-layer and failed run folders deleted. Logs of failed tries in `cfd/cases/mesh_try3/`.
- Fix attempt 2 for F (cause: the 0.05 mm rear-edge change, which F never needed: its arcs are on different circles anyway): F back to the 3.00 mm rear edge it meshed with in the second meshing. `RWS_EDGE_DIFF` now applies only to lens-sided sections (E, G).
- Fix attempt 3 for G (last; the brief's simplification): ridges reduced from 3 per face (Z 650, 830, 1010; 10 mm thick; 8 mm proud) to **2 per face (Z 700, 950), 14 mm thick, 10 mm proud**; start, end and 20 deg turn unchanged.
- E, H meshes unchanged (STEP checksums the same after the G, F rebuild).
- Chain 2 started: mesh G, F (1 layer), then solve E, G, H, F where a mesh exists.
- 2026-11-26, chain 2 result: **F meshed, 987,878 cells.** **G failed its third and last attempt**: "Front could not be closed" at X 2217, Y 560, Z 1359 (rear-wing flap 2) and "Failed to project front-edges" at X -590, Y 300, Z 151 (front-wing flap inner end). Both are the known wing-slot fragility (memory/notes: slot ends meeting planes), not at the ridges; the ridges change the global size field enough to tip it. **G is not run this round** (3-attempt rule). Logs: `cfd/cases/mesh_G_bl1.log`, `mesh_try2/`, `mesh_try3/`.
- Solving: E_bl1 started 12:09 (about 65 min), then H_bl1, then F_bl1 (chain 2). support_forces export for CP, CP_bl1 waits until the chain ends (one licence).
- Helper scripts written: `cfd/support_forces.py` (CP pylon force from face export; self-test PASS), `cfd/support_flow.py` (planes next to the support; self-test PASS).
- 2026-11-26 13:21: **E_bl1 done.** Force-converged (drift 0.00 %, band 0.56 % downforce / 0.14 % drag), mass imbalance 1.5e-7, y+ area-avg 84-147 (support 87), part forces sum to the total (exactly: total = sum of zone reports, includes car_rws). Against CP_bl1 (half car, N, 200-it means): total downforce 497.2 vs 477.2 (ClA 4.14 vs 3.98, **+4.2 %**, above the 2.2 % spread); drag 202.7 vs 200.1 (CdA +1.3 %, within the spread: not claimed). Where: rear wing 270.4 vs 249.5 (CP_bl1's includes its pylon), floor +1.7, body -2.9 (more lift), front wing +0.6. Support itself: -0.1 down / 0.8 drag (band 4.6 %). Front share 0.40 vs 0.43 (the extra load is at the rear). H_bl1 solving next, then F_bl1.
- 2026-11-26 14:33: **H_bl1 done.** Force-converged (drift 0.01/0.02 %, band 1.39/0.59 %), mass imbalance 5.2e-7, y+ 84-147 (support 86), parts sum to the total. Half car, N: downforce 491.1 (ClA 4.09: +2.9 % on CP_bl1, -1.2 % on E: H vs E within the spread), drag 203.2 (CdA 1.69, +0.3 % on E: within the spread). Support: -0.1 down / **2.8 drag (E 0.8)**, band 14 % (blunt base sheds). Rear wing 265.9 (E 270.4), body -45.6 (E -43.8), floor 50.8 (E 50.2). F_bl1 solving.
- 2026-11-26 15:49: **F_bl1 done.** Force-converged (drift 0.00 %, band 0.83/0.13 %), mass imbalance 7.2e-7, y+ 85-147 (support 87), parts sum to the total. Half car, N: downforce 498.5 (ClA 4.15, +0.3 % on E), drag 202.5 (CdA 1.69, -0.1 % on E). Support: 0.0 down / **0.41 drag (E 0.81, H 2.82)**. Rear wing 273.0 (E 270.4). Chain done. Next: step 10 (support_forces export on CP, CP_bl1, E_bl1, H_bl1, F_bl1), then support_flow pictures.
- 2026-11-26 16:00: **step 10 done.** `support_forces.py` export + sum on CP, CP_bl1, E_bl1, H_bl1, F_bl1: whole-zone face sums match Fluent's reports to 1e-11 on all five (shear sign +1). Pylon: CP -0.10 / 4.57 N, CP_bl1 -0.12 / 4.34 N (2,939 faces, 0.319 m2, matches the plate's exposed area). Supports: E -0.06 / 0.81, H -0.06 / 2.80, F -0.05 / 0.41 (same as the zone reports).
- **Step 12 done:** `cfd/support_flow.py` -> `media/cfd/supports/support_flow.png`, `cfd/results/support_flow.csv`; postprocess re-run (wake tables, cfd_results.md).
- **Step 13 done:** `media/cfd/supports/wing_supports_results.md` (table, findings, what I would build: F, what was not checked); log, README Future work, cfd README updated. **Round finished.** Next round (not started): front wing supports; G again with a mesh that survives (e.g. slot fixes) if wanted.

---

# Front-wing round: variants J, K, CPFF and a CP_bl1 repeat (started 2026-11-27)

**Resume rule as above.** The newest status line is at the bottom of "Front-wing status".

## How I read the brief (written 2026-11-27, before any run)

- **Base and reference.** Every run is CP with 1 prism layer, compared against **CP_bl1**. Same solver settings (`fluent_halfcar.py solve`, defaults: 1200 iterations, force stop), same meshing settings (`--scale 2`, `--set bl_layers=1`), same cell limit.
- **What the current front pylon is (checked in `build_front_wing`, matches the brief):** one flat 16 mm plate each side, Y 60-76 mm (centre 68), X -672 to -588 mm (72-93 % of the 400 mm main-element chord, so an 84 mm chord), bottom edge on the main element's middle line (Z 107 at the front, 128 at the back), top at Z 230. From X -650 back the top is inside the nose (nose underside at Z 188-215 there); **the front 22 mm (X -672 to -650) is ahead of the nose tip, so its top face at Z 230 is exposed**. The exposed height between the wing's upper surface (Z 121-132) and the nose is only about 60-100 mm, against about 650 mm on the rear. Counted in `car_fw`.
- **J and K:** only the front pylon's cross-section changes; the envelope above is kept (same X range, Y centre, 16 mm maximum thickness, same side outline, same nose and wing attachment). Built with the rear round's section function `rws_section` and its mesher-forced rules:
  - **J:** F's section: lens with a 5 mm round front edge (`RWS_NOSE_R`), rear edge cut square 3 mm.
  - **K:** E's section: lens, front edge 3 mm square, rear edge 3.05 mm (`RWS_EDGE_DIFF`, keeps the side faces split).
  - The rear keeps CP's flat pylon in J and K.
  - Own force zone `car_fws` (face size 12 mm as the wing). `car_fw` is then the wing without its support.
- **CPFF:** J or K on the front (whichever has the lower `car_fws` drag; if they are equal to the reported digits, J, the shape that won on the rear), plus F's rear supports (`car_rws`). Built after J and K are solved.
- **CP_bl1 repeat (second noise estimate):** Fluent Meshing has no random seed, so the "tiny mesh change" is **the curvature normal angle 17.5 deg instead of 18 deg** (`--set curvature_angle=17.5`), run **CP_bl1r**; geometry `fluid_CP.step` unchanged. This changes the surface mesh on every curved face, which is how the variants also move the mesh (the global size field), so it estimates the noise the comparison actually sees. It is slightly finer, so a small systematic part cannot be separated from the noise. Fallback if it does not mesh or goes over the limit: volume growth 1.33 instead of 1.35.
- **Measures for every run:** support drag (half car, N), ClA, CdA, L/D, front share, front-wing downforce on its own (J, K, CPFF: `car_fw` + `car_fws` and each alone; CP_bl1 and F_bl1: `car_fw`, and its pylon picked out by face export), wake q-ratio at 1, 2, 3 L. Differences in totals under 2.2 % are not claimed; the repeat gives a second spread.
- **Meshing failures:** up to 3 tries per variant: 3 mm square edges (already in), symmetry-face split, then one simplified section. Then stop on that variant.
- **Lap sim (only if CPFF solves):** row CPFF in `params/aero_variants.csv` (CFD only); `support_sensitivity.m` extended to compare CP_bl1, CPF and CPFF with the same 2.2 % band. CP and its row unchanged.
- **Not changed:** CP, A-D, E-H data, the CP row, SOLIDWORKS files. No .msh/.cas/.dat/.h5 outside `cfd/cases/`.

## Front-wing variants

| Run | Front section | Rear | Status | Cells |
|---|---|---|---|---|
| CP_bl1 | flat 16 mm plate | flat plate | reference, existing run | 918,527 |
| CP_bl1r | flat plate | flat plate | repeat; meshed on try 3, near-car box 39 mm instead of 40 (curvature 17.5 deg failed; volume growth 1.33 gave CP_bl1's mesh) | 917,716 |
| J_bl1 | lens, 5 mm round front edge | flat plate | solved, first mesh try | 921,687 |
| K_bl1 | lens, 3 mm square edges | flat plate | **not run**: 3 mesh tries failed, all away from the support | - |
| CPFF_bl1 | J (K did not mesh) | F | solved, mesh try 2 (symmetry face split at Z 1050) | 989,695 |

## Front-wing steps

- [x] F1. Front pylon checked against the brief (above).
- [x] F2. Code: `fw_support`, `build_fw_support`, zone `car_fws` in `cad/generate/cfd_variants.py`; `car_fws` in `cfd/fluent_halfcar.py` (wall, wing face size). CP's code path unchanged.
- [x] F3. Geometry J, K built: 19 of 19 checks pass. `car_fw` 30 -> 25 faces (CP's 5 pylon faces leave), `car_fws` 7 faces, body 122 -> 121 faces (CP's plate cuts a 207 mm2 sliver off the nose's lower corner face inboard of it, X -650 to -610, Y 50-60; the lens, narrower at the front, leaves that face whole), all other zones as CP. Shared domain/BOI STEP files restored (only STEP occurrence counters differed).
- [x] F4. Mesh J, K, CP_bl1r (K not meshed in 3 tries) (chain `cfd/cases/chain_JK.sh`, progress `chain_JK.out`).
- [x] F5. Solve J, CP_bl1r (K not run); per-solve checks (force convergence, mass balance, y+, parts sum to the total).
- [x] F6. CPFF: geometry, mesh, solve, checks.
- [x] F7. Face export: front pylon force of CP_bl1, CP_bl1r, F_bl1 (`support_forces.py`), checked against the zone reports.
- [x] F8. Flow picture near the front support (`support_flow.py --front`), wake table.
- [x] F9. Lap sim and balance: CP_bl1, CPF, CPFF (CPFF solved).
- [x] F10. Write-up: results file (front-wing section), this plan, log, README Future work.

## Front-wing status

- 2026-11-27: F1-F3 done. Chain started: mesh J, K, CP_bl1r, then solve each that meshed.
- 2026-11-27 10:06: **J meshed first try, 921,687 cells** (CP_bl1 918,527; min orthogonal quality 0.140 vs 0.144; support 2,073 surface faces). J_bl1 solving from 10:11.
- **K, mesh try 1 failed** (10:09): "Breakout detected / Front could not be closed" at X 2215, Y 264, Z 1359, the rear-wing flap 2 slot (the same place F failed in the rear round), not at the front support. Logs in `cfd/cases/mesh_front_try1/`. **Try 2:** symmetry face split at Z 1050 (`sym_split_z`, topology only, as B_AB); rebuilt, 11 of 11 checks.
- **CP_bl1r, mesh try 1 failed** (curvature 17.5 deg): "Breakout detected", then 26 self-intersections (no location given). **Try 2 = the planned fallback: volume growth 1.33 instead of 1.35** (`--set vol_growth=1.33`, curvature back to 18). This leaves the surface mesh as CP_bl1's, so it measures only the volume-mesh part of the noise.
- A second Fluent session cannot start while one runs (Student licence: 4 launch attempts refused at 10:13-10:16; J_bl1 carried on unaffected). Chain 2 (mesh K, CP_bl1r; solve both) starts when J_bl1 ends.
- 2026-11-27 11:15: **J_bl1 solved** (1200 it, force-converged: drift 0.005 / 0.001 %, band 0.71 / 0.31 %), mass imbalance 7.4e-7, y+ area-average 35 on the front support, 81-147 elsewhere.
- 11:17: **K try 2 failed** at rear flap 2 again (X 2216, Y 451, Z 1360). Logs `cfd/cases/mesh_front_try2/`.
- 11:21: **CP_bl1r try 2 (volume growth 1.33) gave a mesh IDENTICAL to CP_bl1**: 918,527 cells, same surface faces per zone, same orthogonal quality to 16 digits, same file size. The growth setting has no effect on this poly-hexcore mesh, so a solve would only repeat CP_bl1. Its solve was stopped before Fluent started (licence wait) and the mesh deleted. **Try 3 (the last):** near-car refinement box 39 mm instead of 40 (`--set boi_near=39`, 78 instead of 80 mm at scale 2).
- 11:24: **K try 3 (simplified "diamond" section: straight sides, same pointed 3 mm front edge, chord and thickness; no symmetry split) failed**: "Failed to project front-edges" at X -590, Y 300, Z 151, the front flap's inner end (the same failure as G's last try), not at the support. **K is not run (3-attempt rule).** Logs `cfd/cases/mesh_front_try3/`. The diamond definition stays in the code as the record of try 3.
- 11:28: **CP_bl1r meshed, 917,716 cells** (CP_bl1 918,527): surface faces differ in every zone (car_fw 59,300 vs 59,322, car_rw 70,371 vs 70,451, ground 23,126 vs 23,068), so the change reaches the surface mesh through the size field. Solving.
- **CPFF = J's front support (K did not mesh) + F's rear supports.** Built, 11 of 11 checks; its car_fws faces are identical to J's and its car_rws / car_rw faces to F's. Chain `cfd/cases/chain_CPFF.sh` (mesh CPFF, face exports of CP_bl1, F_bl1, CP_bl1r, J_bl1, solve CPFF, export CPFF) starts after CP_bl1r.
- 12:35: **CP_bl1r solved** (1200 it, force-converged), mass imbalance 9.9e-7, y+ area-average 82-147. ClA 3.941 (-0.9 % vs CP_bl1), CdA 1.655 (-0.7 %), front share 0.433 (+0.002): **second noise estimate about 0.9 % (ClA) / 0.7 % (CdA)**, inside CP's 2.2 %.
- 12:38: **CPFF mesh try 1 failed**: "Failed to project front-edges" at X -590, Y 300, Z 151, the front flap's inner end (as K try 3), not at a support. Log `cfd/cases/mesh_CPFF_bl1_try1.log`. **Try 2:** symmetry face split at Z 1050 (`sym_split_z`, topology only, as B_AB; the 3 mm square edges are already in). Rebuilt, 11 of 11 checks, shared STEP files restored.
- 12:40-12:44: face exports of `car_fw` (CP_bl1, F_bl1, CP_bl1r) and all zones of J_bl1 (`support_forces.py`): zone sums match Fluent's report to 3e-12. **CP's flat front pylon: 0.45 N drag, 0.04 N downforce (half car), 0.0164 m2 wetted** (hand check of the plate's exposed faces: about 0.0169 m2). J's support: 0.15 N drag, 0.03 N downforce, 0.0145 m2.
- 12:48: **CPFF try 2 meshed, 989,695 cells** (min orthogonal quality 0.101, CP_bl1 0.144). Solving.
- 14:01: **CPFF_bl1 solved** (1200 it, force-converged: drift 0.01 / 0.00 %, band 0.89 / 0.21 %), mass imbalance 7.3e-7, y+ area-average 35 on the front support, 87 on the rear supports, 84-148 elsewhere. All zone sums match Fluent to 1e-11 or better; the part forces add up to the total. ClA 4.133 (+3.9 % vs CP_bl1), CdA 1.684 (+1.0 %), front share 0.397; against CPF (F_bl1): ClA -0.5 %, CdA -0.2 %, front +0.004, all inside the spread.
- After the solve: postprocess (`--no-plots`; only rows added to the result tables, plus two `car_fws` columns in `cfd_summary.csv`; old rows unchanged), `support_flow.py --front CP_bl1 J_bl1 CPFF_bl1` (`media/cfd/supports/support_flow_front.png`), `support_table.py` (`cfd/results/support_table.csv`). Row CPFF in `params/aero_variants.csv` (CFD only), CPFF allowed in `read_aero_variants` / `car_from_params`, `support_sensitivity.m` run (`media/support_sensitivity.md`): CPFF - CPF inside the band everywhere. `run_all('test')`: 28 of 28 PASS.
- **Done.** Results: `media/cfd/supports/wing_supports_results.md`, section "Front-wing supports".
