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
