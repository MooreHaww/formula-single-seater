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
- **The front wing's supports:** out of scope in this round; CP's front flat pylon stays in every run. Done in the next round: see the front-wing section below.
- **2 prism layers:** E, F and H were run with 1 layer only. CP vs CP_bl1 suggests the layer count moves ClA by about 2 %.
- **Truly sharp edges:** the edges are 3 mm square, because sharp edges did not mesh.
- **Other support positions, chords or thicknesses.** The envelope is CP's pylon.
- **Yaw or crosswind, and unsteady flow:** only steady RANS. H's support force is unsteady (band 14 %).
- **Mesh independence near the support.** The support faces use the wing's 12 mm face size; there was no refinement study. y+ is about 87 on the supports (wall functions).
- **Lap time and cornering balance with the new forces:** `params/aero_variants.csv` was not changed (CP data untouched), and the lap sim was not run.
- **Structure:** stiffness, strength, flutter of a 16 mm lens over 650 mm, and attachment to the frame and the wing.
- **The SOLIDWORKS model:** this round is CFD only, so there is no CAD of the supports.
- **The CP comparison point is a snapshot:** CP's pylon force is from the saved last iteration, not a 200-iteration mean. For CP_bl1 the zone's snapshot and mean differ by under 0.1 %, so the pylon value should be close.

---

# Front-wing supports J, K and CPFF: CFD results (2026-11-27)

Plan, interpretation of the brief and the step-by-step record: `docs/wing_supports_plan.md` (section "Front-wing round").

**Read this first.**
- Same method as the rear round: half-car steady RANS (k-omega SST), Student mesh, 1 prism layer, CP's solver settings. **Only the ranking is trustworthy.**
- **One run per variant is a weak result.** A difference in total ClA or CdA smaller than CP's 2.2 % spread is not claimed. A repeat of CP_bl1 with a tiny mesh change (below) moved ClA by 0.9 % and CdA by 0.7 %: a second, smaller estimate of the same noise.
- The force on the support itself is the least noisy measure.

## What was compared

**How I read the brief:**
- **CP's front pylon** is where the brief says:
  - one flat 16 mm plate each side of the nose, Y 60-76 mm;
  - 84 mm chord (X -672 to -588, 72-93 % of the main element's chord);
  - from the main element's middle line up into the nose (top at Z 230 mm).
  - Only 60-100 mm of it is exposed between the wing and the nose, against about 650 mm for the rear pylon.
- **J and K change only the plate's cross-section.**
  - The envelope is kept: X range, Y centre, 16 mm maximum thickness, side outline, and the attachment to the wing and the nose.
  - The rear keeps CP's flat pylon.
- **Force zones.** The supports get their own force zone (`car_fws`), so `car_fw` is the wing alone.
  - For CP_bl1, CP_bl1r and F_bl1, the flat front pylon was picked out of `car_fw` by the per-face export (`cfd/support_forces.py`).
  - Each zone sum matches Fluent's own report to 1e-11 or better.

| Run | Front support | Rear support | Cells | Status |
|---|---|---|---|---|
| CP_bl1 | CP's flat 16 mm plate | CP's flat plate | 918,527 | reference (existing run) |
| CP_bl1r | flat plate | flat plate | 917,716 | repeat of CP_bl1, near-car refinement box 39 mm instead of 40 |
| J_bl1 | lens, 5 mm round front edge (F's section) | flat plate | 921,687 | solved |
| K_bl1 | lens, 3 mm square front edge (E's section) | flat plate | - | **not run**: failed to mesh in 3 tries |
| F_bl1 (= CPF) | flat plate | F | 987,878 | existing run, for comparison |
| CPFF_bl1 | J (K did not mesh) | F | 989,695 | solved |

**K's three mesh failures** were all away from the support, at the model's known fragile spots:
1. Try 1: the rear-wing flap 2 slot (X 2215, Y 264, Z 1359).
2. Try 2, with the symmetry face split at Z 1050: the same slot (X 2216, Y 451, Z 1360).
3. Try 3, with a simplified "diamond" section (straight sides; same pointed edge, chord and thickness): the front flap's inner end (X -590, Y 300, Z 151).

**CPFF uses J** because K was not run. CPFF itself failed once at the same front-flap spot. It meshed on the second try, with the symmetry face split at Z 1050 (topology only; it does not move the car).

**The CP_bl1 repeat.** Fluent Meshing has no random seed, so the "tiny mesh change" had to be a setting:
- Curvature angle 17.5 deg instead of 18: did not mesh (self-intersections).
- Volume growth 1.33 instead of 1.35: gave a mesh **identical** to CP_bl1's (same cells and faces). Not solved.
- Near-car refinement box size 39 mm instead of 40 (78 instead of 80 mm at scale 2): meshed. The surface faces differ in every zone, so this changes the mesh through the size field, as the variants do.

## Results (full car unless marked; 20 m/s)

| | CP_bl1 (flat front, flat rear) | CP_bl1r (repeat) | J_bl1 (J front, flat rear) | F_bl1 / CPF (flat front, F rear) | CPFF_bl1 (J front, F rear) |
|---|---|---|---|---|---|
| **Front support, half car (N): downforce / drag** | 0.04 / 0.45 | 0.04 / 0.45 | 0.03 / **0.15** | 0.03 / 0.45 | 0.03 / **0.15** |
| Front support drag vs CP_bl1's front pylon | 1 | 1.00 | **0.34** | 1.00 | **0.33** |
| Rear support, half car (N): downforce / drag | -0.12 / 4.34 | -0.12 / 4.31 | -0.10 / 4.30 | -0.05 / 0.41 | -0.05 / 0.43 |
| Front-wing downforce with its support (N) | 470.5 | 468.8 (-0.4 %) | 468.1 (-0.5 %) | 470.3 (-0.1 %) | 471.3 (+0.2 %) |
| Rear wing without its support, half car (N) | 249.6 | 248.4 | 246.1 | 273.0 | 271.7 |
| ClA (m²) | 3.977 | 3.941 (-0.9 %) | 3.931 (-1.2 %) | 4.154 (**+4.5 %**) | 4.133 (**+3.9 %**) |
| CdA (m²) | 1.667 | 1.655 (-0.7 %) | 1.650 (-1.0 %) | 1.687 (+1.2 %) | 1.684 (+1.0 %) |
| L/D | 2.385 | 2.381 | 2.382 | 2.462 | 2.454 |
| Front share of the aero load | 0.431 | 0.433 | 0.435 | 0.393 | 0.397 |
| Wake q-ratio in the follower's window, 1 / 2 / 3 L | 0.65 / 0.91 / 0.97 | 0.65 / 0.91 / 0.97 | 0.64 / 0.91 / 0.97 | 0.66 / 0.92 / 0.97 | 0.66 / 0.91 / 0.97 |
| Upwash w/U beside the front support (mean, 14 mm outboard) | +0.019 | - | +0.011 | - | +0.010 |
| Mean 1 - u/U in a box just behind the front support | 0.37 | - | 0.10 | - | 0.10 |

**Beyond CP's 2.2 % spread:**
- Only the ClA of F_bl1 (+4.5 %) and of CPFF_bl1 (+3.9 %) against CP_bl1. Both come from the rear supports.
- Every other total difference in the table is inside the spread. That includes every difference between J and CP_bl1, and between CPFF and CPF (ClA -0.5 %, CdA -0.2 %, front share +0.004).

Where the numbers come from:
- **Front support, J_bl1 and CPFF_bl1:** zone `car_fws` (200-iteration mean).
- **Flat pylon (CP_bl1, CP_bl1r, F_bl1):** from the face export, a snapshot of the saved iteration.
  - Its wetted area is 0.0164 m² per side.
  - A hand estimate of the plate's exposed faces gives about 0.0169 m².
- **Totals and front share:** `cfd/postprocess.py`.
- **Table:** `cfd/support_table.py`, written to `cfd/results/support_table.csv`.
- **Wake:** `cfd/results/wake_cfd.csv`.
- **Last two rows:** `cfd/results/support_flow_front.csv`.
- **Picture:** `support_flow_front.png`.

## What was found

1. **The front pylon is a small part.**
   - CP's flat plate costs 0.45 N of drag per half car, against 4.3 N for the rear plate.
   - Across the whole car it is about 0.9 N out of 400 N of drag (0.2 %).
2. **J's lens section cuts the front support's drag by two thirds**, from 0.45 N to 0.15 N (half car), in J_bl1 and again in CPFF_bl1.
   - The flat plate's flow separates at its square front corners and leaves a slow wake behind it (mean 1 - u/U 0.37 just behind it).
   - Behind J's lens the flow stays attached and the wake is thin (0.10). See `support_flow_front.png`.
3. **Unlike at the rear, the front wing does not gain from it.**
   - The front wing's downforce changes by -0.5 % (J) and +0.2 % (CPFF). The repeat alone moves it by 0.4 %, so this is noise.
   - The plate is exposed for only 60-100 mm, and its separated wake runs into the nose rather than the wing. So it does not spoil the wing as the rear plate does.
4. **The totals do not change measurably.**
   - J vs CP_bl1: ClA -1.2 %, CdA -1.0 %, front share +0.004. All are inside the 2.2 % spread and close to the repeat's own change (-0.9 % / -0.7 %).
   - The 0.6 N of drag saved (full car) is 0.15 % of the total, far below what one run can resolve.
5. **CPFF behaves like CPF.**
   - The rear F supports give their known gain again: ClA +3.9 % over CP_bl1 (beyond the spread), with the balance moving rearward (front share 0.397).
   - The front supports add nothing measurable on top (CPFF vs CPF: ClA -0.5 %, CdA -0.2 %).
6. **The wake behind the car is unchanged.** The follower's window q-ratio moves by 0.01 at most, as in the rear round.
7. **Lap time and balance** (`media/support_sensitivity.md`, same 2.2 % band as for CPF):
   - **CPFF against CP_bl1:**
     - faster on the skidpad (-0.009 s point-mass / -0.024 s four-wheel) and the autocross (-0.28 s / -0.55 s), beyond the band, as CPF was;
     - the fast circuit is +0.16 / +0.08 s, inside the band.
   - **CPFF against CPF:** inside the band on every track (largest +0.066 s, autocross four-wheel, band 0.13 s).
   - **Cornering balance at 45 m:** CP_bl1 -6.2 %, CPF +0.4 %, CPFF -0.3 % (band 1.5 points). CPF and CPFF are both near neutral and cannot be told apart.

## What I would build

- **Front: J's section (lens, 5 mm round front edge)**, in CP's pylon envelope: 84 mm chord, 16 mm thick, one each side of the nose.
  - Choose it because its own drag is one third of the plate's, not for a measured effect on the car. On the totals and the lap time it cannot be told apart from the flat plate.
  - If a flat plate is much easier to make at the front, it costs about 0.6 N of drag at 20 m/s (full car), which this model cannot even resolve.
  - A rounded or chamfered front edge on the plate would probably recover most of J's gain, but that was not run.
- **Rear: F stays the recommendation** from the rear round. That is where the measurable gain is.

## What was NOT checked

- **K (pointed lens) was not run.** It failed to mesh 3 times, at the wing slots and the front flap's inner end, not at the support. So J vs K is untested. On the rear, E and F were within each other's noise on totals.
- **One run per variant**, steady RANS. The two noise estimates (CP vs CP_bl1, 2.2 %; CP_bl1 vs CP_bl1r, 0.9 %) come from one pair each.
- **CP_bl1r is not a pure noise test.** Its refinement box is 1 mm smaller, so a small systematic part (a slightly finer mesh near the car) cannot be separated from the noise.
- **Mesh independence near the front support:**
  - face size 12 mm, as the wing; no refinement study;
  - y+ on the front support is about 35 (wall functions);
  - CPFF's minimum orthogonal quality is 0.101 (CP_bl1 0.144).
- **The symmetry split in CPFF** (topology only) was not used on CPF, so CPFF vs CPF also has that small difference in the mesh.
- **The flat pylon's force is a snapshot** of the saved iteration, not a 200-iteration mean. For CP_bl1's front-wing zone, the snapshot and the mean differ by 0.15 %.
- **Other front designs:** rounded or chamfered flat plates, and other chords, thicknesses or positions.
- **Yaw, crosswind, unsteady flow, 2 prism layers.**
- **Structure.** The front supports carry the front wing (about 470 N of downforce at 20 m/s, plus its mass). Their stiffness, strength and attachment to the nose and the frame are not designed.
- **The SOLIDWORKS model and v1.0.0 have no supports**: this is CFD only.
  - CPFF is a CFD-only row in `params/aero_variants.csv`.
  - CP stays the default car, and its data are unchanged.
