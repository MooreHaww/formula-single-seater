# Rear-wing supports E-H: CFD results (2026-11-26)

Plan, interpretation of the brief and the step-by-step record: `docs/wing_supports_plan.md`.

**Read this first.**
- These are half-car steady RANS results (k-omega SST) on a Student mesh. **Only the ranking is trustworthy.**
- CP's own run-to-run spread is about 2.2 % (CP vs CP_bl1, ClA). Differences in total ClA or CdA smaller than that are not claimed.
- The force on the support itself is less noisy and is the main measure.

## What was compared

Every run is the as-built car CP (C's wings on the SOLIDWORKS bodywork), solved with CP's solver settings (1200 iterations, force stop) and **1 prism layer**.
- F at 2 layers came out at 1,080,650 cells, over the 1,048,576 limit, so the 1-layer run **CP_bl1** is the reference.
- Only the rear wing's support changes. The front wing keeps CP's flat pylon.
- Two supports per car (one in the half model), each in the same envelope as CP's rear pylon:
  - chord 228 mm (X 1667 to 1895);
  - centred 150 mm from the centreline;
  - 16 mm thick at most;
  - running from inside the hull tail up into the main element (about 650 mm exposed).

| Run | Support section | Cells |
|---|---|---|
| CP_bl1 | CP's idealised flat 16 mm plate, square edges | 918,527 |
| E_bl1 | lens: two circular arcs, edges cut square 3 mm thick | 977,893 |
| F_bl1 | E with a rounded front edge (5 mm radius); rear half as E | 987,878 |
| H_bl1 | E's front half; rear half flared to a flat blunt base 24 mm wide | 945,815 |
| G | E with curved ridges: **not run**, it failed to mesh in 3 attempts | - |

The geometry is drawn in `supports_sections.png` and `supports_3d.png`.

**Changes forced by the mesher** (all four variants share them, so each still differs from E by one thing):
- **Edges.** The lens edges are 3 mm square instead of knife-sharp, because the knife edges gave self-intersecting surface meshes.
- **E's and G's rear edge** is 3.05 mm. This keeps each side as two faces: as one face, E's CAD tessellation broke.
- **G** was simplified to 2 ridges per face (14 mm thick, 10 mm proud) and still failed.
  - The last two G failures were at the rear-wing flap slots (X 2027 and 2217 mm) and the front-flap inner end, not at the ridges.
  - This is the known slot fragility of this model.

## Results (full car unless marked; 20 m/s)

| | CP_bl1 (flat plate) | E_bl1 (lens) | F_bl1 (lens, round front) | H_bl1 (lens, flared blunt tail) |
|---|---|---|---|---|
| **Support force, half car (N): downforce / drag** | -0.12 / 4.34 | -0.06 / 0.81 | -0.05 / 0.41 | -0.06 / 2.80 |
| Support drag vs CP_bl1's pylon | 1 | 0.19 | 0.09 | 0.65 |
| Rear wing without its support, half car (N): downforce / drag | 249.6 / 81.3 | 270.4 / 85.8 | 273.0 / 86.3 | 265.9 / 84.6 |
| ClA (m²) | 3.98 | 4.14 (+4.2 %) | 4.15 (+4.4 %) | 4.09 (+2.9 %) |
| CdA (m²) | 1.67 | 1.69 (+1.3 %, not claimed) | 1.69 (+1.2 %, not claimed) | 1.69 (+1.6 %, not claimed) |
| L/D | 2.39 | 2.45 | 2.46 | 2.42 |
| Front share of the aero load | 0.43 | 0.40 | 0.39 | 0.41 |
| Wake q-ratio in the follower's window, 1 / 2 / 3 L | 0.65 / 0.91 / 0.97 | 0.66 / 0.92 / 0.97 | 0.66 / 0.92 / 0.97 | 0.66 / 0.92 / 0.97 |
| Upwash in the follower's high window at 1 L (deg) | 18.0 | 19.2 | 19.3 | 19.2 |
| TKE in the follower's high window at 1 L (m²/s²) | 6.27 | 6.86 | 6.75 | 6.25 |
| Upwash w/U beside the support (mean, 14 mm outboard) | +0.021 | +0.035 | +0.033 | +0.027 |
| Mean 1 - u/U in a box just behind the support | 0.23 | -0.02 | -0.06 | 0.18 |

Where the numbers come from:
- **Support force:** the `car_rws` zone for E, F and H.
- **CP_bl1's pylon:** picked out of its rear-wing zone by summing per-face pressure and shear from the saved solution (`cfd/support_forces.py`). The same sum over the whole zone matches Fluent's own report to 1e-11 on all five runs.
- **CP (2 layers):** its pylon gives -0.10 / 4.57 N, the same picture.
- **Rear wing without its support:** for CP_bl1, the wing zone minus the pylon.
- **Wake:** `cfd/results/wake_cfd.csv` and `wake_boxes.csv`.
- **The last two rows:** `cfd/results/support_flow.csv`.
- **Picture of the air near the supports:** `support_flow.png`.

## What was found

1. **The section shape matters, through the wing more than through the support.**
   - The flat plate's square front edge separates: in `support_flow.png` there is a broad slow region along its inboard face for the whole chord. The lens sections stay attached, with a thin wake.
   - The support's own drag falls from 4.3 N (half car) to 0.8 N for E and 0.4 N for F.
   - The larger effect is on the wing above it:
     - with any lens support, the rear wing (without the support) carries 7 to 9 % more downforce (+16 to +23 N per half car);
     - total ClA rises 2.9 to 4.4 % over CP_bl1;
     - for E and F this is about twice CP's 2.2 % spread.
   - The likely mechanism: the plate's separated wake runs up into the junction with the main element and spoils its suction side there.
   - **So CP's own ClA probably carries a penalty of about 4 % from its idealised flat pylon.**
2. **Total drag does not separate the variants.** CdA is 1.2 to 1.6 % above CP_bl1 for all three, within the spread. For E and F, the support saves 3.5 to 3.9 N of drag (half car) and the more heavily loaded wing adds 4.5 to 5.0 N. For H, the support saves 1.5 N and the wing adds 3.3 N. The savings and the extra wing drag roughly cancel.
3. **None of the supports makes downforce itself:** about 0 N on every support. G, the one design meant to, could not be meshed, so the ridge idea is untested.
4. **E vs F vs H on totals:** within 1.5 % of each other in ClA and 0.4 % in CdA, so they cannot be ranked on totals. On the support force alone:
   - **F has the lowest drag** (0.41 N, half of E);
   - **H costs 3.5 times E's support drag** (2.8 N) and gives no measurable downforce or wake gain in return.
   - H's blunt tail also makes the support's force unsteady (band 14 %, against 4.5 % for E and F).
5. **Balance moves rearward:** the front share falls from 0.43 to 0.39-0.41 because the extra load is on the rear wing. The repo's cornering study puts the neutral car at 0.39 front, so this moves CP towards neutral. **Not run through the lap sim or the balance study.**
6. **Dirty air (our goal) is unchanged within what this mesh resolves.**
   - The follower's window q-ratio moves by 0.01 at most, below the roughly 10 % snapshot uncertainty of the wake numbers.
   - The lens supports raise the upwash in the follower's high window at 1 L by about 1 degree, which fits their extra downforce.

## What I would build

**F: a lens-section support with a rounded front edge**, two per wing, in the envelope tested:
- 228 mm chord, 16 mm thick at mid-chord, at 150 mm from the centreline;
- 5 mm leading-edge radius;
- trailing edge 3 mm or thinner.

Why F:
- It had the lowest support drag (0.41 N half car, 9 % of the flat plate's).
- It gives the same wing-downforce gain as E.
- A rounded front edge is the usual choice for tolerance to yawed flow, but yaw was not simulated here.

Notes:
- E is equally good on totals. Choose E only if a sharp edge is easier to make.
- Do not build H.
- Do not build G unless it can first be meshed and shown to help (a later round).

## What was NOT checked

- **G (ridged support):** not meshed, so not solved. The ridge idea (downforce on the support, more upwash) is untested.
- **The front wing's supports:** out of scope. CP's front flat pylon stays in every run.
- **2 prism layers:** E, F and H were run with 1 layer only. CP vs CP_bl1 suggests the layer count moves ClA by about 2 %.
- **Truly sharp edges:** the edges are 3 mm square, because sharp edges did not mesh.
- **Other support positions, chords or thicknesses.** The envelope is CP's pylon.
- **Yaw or crosswind, and unsteady flow:** only steady RANS. H's support force is unsteady (band 14 %).
- **Mesh independence near the support.** The support faces use the wing's 12 mm face size; there was no refinement study. y+ is about 87 on the supports (wall functions).
- **Lap time and cornering balance with the new forces:** `params/aero_variants.csv` was not changed (CP data untouched), and the lap sim was not run.
- **Structure:** stiffness, strength, flutter of a 16 mm lens over 650 mm, and attachment to the frame and the wing.
- **The SOLIDWORKS model:** this round is CFD only, so there is no CAD of the supports.
- **The CP comparison point is a snapshot:** CP's pylon force is from the saved last iteration, not a 200-iteration mean. For CP_bl1 the zone's snapshot and mean differ by under 0.1 %, so the pylon value should be close.
