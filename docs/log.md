# Build log

One entry per session. Newest at the bottom. Each entry: date, ring, what was done, what was checked, next step.


## Summary, 2026-11-25 (CFD session, evening): B and D on the as-built bodywork (B_AB, D_AB)

**How I read the brief:**
- "Exactly CP's settings" means CP's mesh sizes and solver settings. The two exceptions are written next to each result.
- D's fallback (b) is the 12° diffuser, used only after two option-(a) fixes failed.
- "Old B / old D" means the earlier runs on the simplified CFD bodywork.

**Before:**
- B and D in `params/aero_variants.csv` were on the older simplified CFD bodywork, so only CP was on the as-built bodywork.
- The pictures showed old B and D.

**After:**
- B_AB and D_AB are meshed, solved, checked, and feed rows B and D. CP stays the default.
- **D_AB's diffuser is 12°, not 14°.** 14° would not mesh on the as-built hull. D_AB also has 1 prism layer instead of 2 (cell limit), and CP_bl1 (CP with 1 layer) is its like-for-like partner.
- Lap sim section 6 ran (hand-checked), the docs are updated, and all tests pass. The pictures and films are re-made with B_AB and D_AB; the old ones are in `media/cfd/vis_old_simplified/` (git-ignored).

| | B_AB | D_AB (12°, 1 layer) | CP | CP_bl1 (1 layer) | B old | D old |
|---|---|---|---|---|---|---|
| cells | 953,238 | 1,002,218 | 1,007,086 | 918,527 | 900,187 | 1,042,343 |
| ClA / CdA | 3.36 / 1.32 | 4.03 / 1.76 | 3.89 / 1.66 | 3.98 / 1.67 | 3.43 / 1.29 | 4.20 / 1.77 |
| front share | 0.43 | 0.39 | 0.43 | 0.43 | 0.45 | 0.38 |
| q-ratio 1 / 2 / 3 L | 0.67 / 0.89 / 0.95 | 0.65 / 0.92 / 0.98 | 0.64 / 0.92 / 0.98 | 0.65 / 0.91 / 0.97 | 0.66 / 0.86 / 0.93 | 0.65 / 0.92 / 0.97 |
| autocross / fast circuit (s) | 61.72 / 79.90 | 60.90 / 84.26 | 61.12 / 82.97 | 60.99 / 82.98 | 61.64 / 79.79 | 60.65 / 84.31 |

**Caveats:**
- Steady RANS on a Student mesh: **only the ranking is trustworthy.**
- CP itself is unsteady (downforce band 2.5 %), and CP_bl1 differs from CP by +2.2 % ClA, which is larger than D_AB's lead over CP_bl1 (+1.3 %).

## Summary, 2026-11-25 (CFD session): the aerodynamics made visible: pictures, films, smoke tunnel, explore command

**Status: finished. No new solves, no commits.**
- **Films git-ignored** (your choice): `media/cfd/vis/*.mp4` and `*.gif` (about 92 MB), remade by `visualise.py all`. The 21 PNGs (15 MB) stay in git.
- **Files changed:**
  - new: `cfd/visualise.py`, `vis_common.py`, `vis_render.py`, `vis_smoke.py`, `explore.py`;
  - edited: `cfd/requirements.txt`, `cfd/README.md`, this log;
  - output: `media/cfd/vis/` (new).
- **Details:** in the entry at the bottom.

**Commands** (from the repository folder):

| What | Command |
|---|---|
| Everything | `.venv/Scripts/python cfd/visualise.py all` (about 8 min, 474 s measured; the first time also exports the Fluent results, about 2 min more) |
| Smoke film, C / D / A | `.venv/Scripts/python cfd/visualise.py smoke C` (or `D`, `A`) |
| Smoke side by side A-B-D | `.venv/Scripts/python cfd/visualise.py smoke ABD` |
| Orbit / wake sweep / build-up of one variant | `.venv/Scripts/python cfd/visualise.py anims C --only orbit` (`sweep`, `buildup`; any of A B C D) |
| A-B-C-D picture and film | `.venv/Scripts/python cfd/visualise.py compare` |
| Stills | `.venv/Scripts/python cfd/visualise.py stills C` |
| Explore in CFD-Post | `.venv/Scripts/python cfd/explore.py C`: car Cp, streamlines, wake planes at 1/2/3 L, symmetry speed and k planes to tick on |
| Explore in Fluent | `.venv/Scripts/python cfd/explore.py C --fluent`: case and data read, car Cp, symmetry speed and pathline objects defined |

**Installed** (pip into `.venv`, added to `cfd/requirements.txt`): pyvista 0.49.3, vtk 9.7.2, imageio 2.38.2, imageio-ffmpeg 0.8.1 (includes ffmpeg), pillow 13.0.0, and their dependencies.

**What was made.** For A, B, C (= run CP) and D:
- **Five stills each:**
  - surface Cp, top, side and underbody;
  - streamlines by speed;
  - Q-criterion vortices, two views;
  - wake slices at 1, 2 and 3 L, deficit and k;
  - the centre-plane speed.
- **Three films each:** orbit (10 s), wake-slice sweep (6 s), build-up (8.5 s).
- **Comparison:** `compare_ABCD` picture and film (downforce by part, underbody Cp, the wake).
- **Smoke tunnel:** films for C, D and A (18 s, 1.6 s of flow 11 times slower), and the A-B-D side by side.
- **Format:** every film is MP4 and GIF.
- **Scales and captions:**
  - the same colour scales everywhere;
  - every picture and frame carries a caption saying only the ranking of the variants is trustworthy;
  - the smoke films also say they show time-averaged streamlines of a steady RANS solution, not unsteady turbulence.

**Checks:**
- **Looked at:** every still and frame sheets of every film.
- **Self-test:** 9 of 9 PASS.
- **Hand sum:** downforce by part adds up to Fluent's total.
- **Against CFD-Post,** at 8 points:
  - within 0.04 m/s in the wake;
  - within 0.2 m/s near the car;
  - +0.5 m/s (4.5 %) in the 20 mm floor gap, where the 12.5 mm grid smooths.

**Not checked:** I did not open the two explore windows on your screen.
- CFD-Post: the same session file was rendered in batch for C and A.
- Fluent: case, data and graphics objects were tested without a window.

## Summary, 2026-11-25: RT1-RRK diagonal removed, m_frame = trimmed weldment 46.26 kg, everything regenerated

**Status: finished, nothing waits on you. No commits.**
- **Rebuild:** `python tools/sw_run.py rebuild`: all 26 steps PASS, with the 123-tube frame. CheckChassis afterwards with the new m_frame: PASS, budget line +0.0 %.
- **Tests:** MATLAB `run_all('test')` 27 of 27 PASS. The self-tests of the files changed after that also pass.
- **Solid cross-check:** `FrameAnalysis 4` re-run on 123 tubes: ALL PASS.
- **Details:** in the entry at the bottom.

**Stiffness without RT1-RRK.** 1476 Nm/deg in the beam model; the fused solid model gives 1470. That is 24 Nm/deg (1.6 %) under the 1500 target and above your 1450 stop line, so I carried on.
- **Nothing cheaper gets it back.** I re-ran the diagonal search without RT1-RRK. It now drops any candidate that meets a frame tube at under 10°. The lightest set reaching 1500 is the built set plus RRK-RT2, the twin diagonal behind the rocker mount: 1501 Nm/deg for +0.59 kg, 0.01 kg more than RT1-RRK. Its joints are at 12.3°; the frame already has 13° joints.
- **Not added.** Decided afterwards: the frame stays at 1476 Nm/deg.
- **Swapping in one other candidate instead:** FS1 plane 1480, RS2 plane 1471, sidepod floors 1541 Nm/deg (+1.17 kg).

**Before (2026-11-18, 124 tubes, m_frame 47.5) → after (123 tubes, m_frame 46.26):**

| | Before | After |
|---|---|---|
| Frame mass in the budget | 47.5 kg at x 841 / z 335 | **46.26 kg at x 832 / z 332** (trimmed weldment: 46.26 kg at 831.7 / 332.1) |
| Car without / with driver | 233.8 / 303.8 kg | **232.6 / 302.6 kg** |
| CG x / z, with driver | 903.3 / 312.0 mm | **902.0 / 311.3 mm** |
| Front weight share | 41.72 % | **41.81 %** |
| Torsion through the links (beam / solid) | 1503 / 1504 Nm/deg | **1476 / 1470 Nm/deg** |
| Torsion, couples at the nodes (beam / solid) | 1386 / 1374 Nm/deg | 1365 / 1350 Nm/deg |
| Lowest factor of safety (bump) | 2.68 (162 MPa) | **2.62 (166 MPa)**, RRK-RT1 |
| Autocross, CP (point-mass / four-wheel) | 61.16 / 62.17 s | **61.12 / 62.12 s** |
| Fast circuit, CP | 82.99 / 83.11 s | **82.97 / 83.08 s** |
| Skidpad / 75 m, CP | 4.90 / 4.35 s | 4.89 / 4.35 s |
| Cornering at R 45 m (CP, four-wheel) | 112.6 km/h, −6.7 %, rear limits | **112.9 km/h, −6.5 %, rear limits** |

- **Other stress cases:**
  - cornering 106 MPa, factor of safety 4.09 (was 109 / 3.99);
  - braking 88 MPa, 4.93 (was 86 / 5.07);
  - corner + brake 106 MPa, 4.10 (was 107 / 4.08).
  - All are above the 1.5 wanted.
- **Bump stress:** 166 MPa is what the frame carries with no diagonals at all. RT1-RRK was the only diagonal that unloaded the rocker-mount tube RRK-RT1.
- **Lap times:** −0.04 s on the autocross and −0.02 s on the fast circuit, from 1.2 kg less mass. The lap sim treats the chassis as rigid, so it shows nothing of the 27 Nm/deg lost.

## Summary, 2026-11-19 night: weldment tubes rebuilt full length, every tube end now meets its neighbour

> **Decision taken 2026-11-25 (summary above):** m_frame is now the trimmed weldment, 46.26 kg, with RT1-RRK removed.

**Status: finished. One decision waits on you (the m_frame value, below). No commits.**
- **Rebuild:** `python tools/sw_run.py rebuild`: all 26 steps PASS (00:33 to about 00:55).
- **Tests:** MATLAB `run_all('test')` 27 of 27 PASS before the rebuild. `read_car_params` has a new line-length check (re-run alone, PASS).
- **Details:** in the entry at the bottom.

**What was wrong.** CheckChassis now measures every trimmed tube end against its boundary tubes (`ClosestDistance`). 4 of the 196 ends did not touch:

| End | Gap |
|---|---|
| FS1_L-FS2_L_R at FS2_L_R | 10.9 mm |
| RS2_U-RT2_R at RS2_U_R | 9.0 mm |
| RS2_U-RT2_L at RS2_U_L | 9.0 mm |
| FS1_L-FS2_L_L at FS2_L_L | 8.6 mm |

- **Not the mitre cuts.** Mitre.cs only removes overhang past the node, 3 to 13 cm³ per cut.
- **The cause was BuildTubes.** SolidWorks refuses a branched sketch as one group, so each frame group was one structural member feature with one group per segment. Inside one such feature, SolidWorks cuts the groups against each other where they meet:
  - near-collinear neighbours were cut back past the node (FS2_L-FH_L, RS2_U-RT2), leaving the ends above floating;
  - run-through tubes lost 4 to 9 % of their steel.
- **Built alone, every tube runs node to node** (volume 1.000 of its centre-line tube).

**What was tried first.** At the open ends, weldment Trim/Extend features were tried in every form: trim with extension, coped and planar, either tube extended, end butt 1 and 2, and end miter. They closed only one end (RS2_U-RT2_R, by end miter). Each attempt costs a full joint recalculation. The connected-segment options of the structural member did not help either: none is refused outright, and coped and simple-without-protrusion cut more.

**The fix.**
- BuildTubes builds the sis, bulkhead, sidepod, front and rear groups as one feature per tube. TrimTubes then copes every joint from `frame_trims.csv`.
- Hoop and hoop_brace stay one feature each, because SolidWorks refuses 12 of their 22 segments on their own. Their ends all touch.

**Weldment before → after:**

| | Before | After |
|---|---|---|
| Trimmed weldment (CheckChassis) | 45.30 kg at x 840.3 / z 335.5 mm | **46.68 kg at x 837.9 / z 333.4 mm** |
| Coped CSV estimate (`frame_trimmed_mass`) | 46.9 kg at 840.7 / 335.3 | 46.81 kg at 839.3 / 335.0 (better search range for shallow joints) |
| Open trimmed ends | 4 | **0 of 196** (largest gap 0.000 mm) |
| Cut length against the centre-line sum | +2.1 % | −0.1 % |
| Trims made (TrimTubes) | 161, 35 not needed | 194, 2 not needed |
| Untrimmed weldment (BuildTubes) | 47.5 kg | 49.8 kg |

- The tubes that still have little steel left are real copes at shallow joints, for example RRK-RT1 (75 %), FS2_L-FS2_U (80 %) and RT1-RRK_diag (85 %, was 73 %).

**Decision for you: m_frame.**
- `car_params.txt` still says 47.5 kg, as you asked: "the mass SolidWorks reports for the trimmed weldment". It is now 46.68 kg, because 47.5 was the BuildTubes figure from before the copes.
- CheckChassis passes at −1.7 % and 3 mm, so nothing is broken.
- Setting 46.7 kg takes 0.8 kg off the car. Expect about −0.03 s on the autocross, going by the 1.8 kg step yesterday.
- It needs the same regeneration as yesterday: mass budget, laps, load and stress cases, README, and the 30-minute diagonal search.

**Still open (design, your call):** RT1-RRK_diag runs at 5.4° to both cross tubes it joins (RT1_cross at RT1_R, RRK_cross at RRK_L). The two crosses are only 60 mm apart, so the diagonal lies along them for about 270 mm at each end. It is buildable only as a long gouged joint. Without it, the beam model gives 1476 Nm/deg (−1.8 %) and 0.6 kg less.

## Summary, 2026-11-18 late: frame mass 47.5 kg from the weldment, CP is the as-built aero reference, everything downstream regenerated

> **Partly superseded by the summary above (2026-11-19):** the trimmed weldment is now 46.68 kg, not 45.3 kg, and every tube end touches its neighbour.

**Status: finished, nothing waits on you. No commits.**
- **Tests:** MATLAB `run_all('test')` 27 of 27 PASS (new: `frame_trimmed_mass`).
- **Rebuild:** `python tools/sw_run.py rebuild`: all 26 steps PASS, about 20 minutes, peak GDI 2,338. CheckChassis passes the new budget-line check (weldment 45.30 kg at x 840.3 / z 335.5 against the budget 47.5 kg at x 841 / z 335: −4.6 %, within 6 % and 10 mm).
- **Details:** in the entry at the bottom.

**Car mass, CG and lap times, before and after.** Before = frame 49.3 kg (centre-line tubes). After = frame 47.5 kg at x 841 / z 335 mm, brackets and welds still 6.4 kg on their own line.

| | Before | After |
|---|---|---|
| Car without / with driver | 235.6 / 305.6 kg | **233.8 / 303.8 kg** |
| CG x (behind the front axle) / z, with driver | 902.4 / 312.1 mm | **903.3 / 312.0 mm** |
| Front weight share | 41.78 % | **41.72 %** |

| Lap time (point-mass / four-wheel) | Before, C (the old reference) | Before, CP | **After, CP (as built, the new reference)** | After, C |
|---|---|---|---|---|
| Autocross | 61.09 / 62.21 s | 61.22 / 62.22 s | **61.16 / 62.17 s** | 61.03 / 62.16 s |
| Fast circuit | 82.58 / 82.78 s | 83.03 / 83.15 s | **82.99 / 83.11 s** | 82.54 / 82.74 s |
| Skidpad | 4.89 / 5.02 s | 4.90 / 5.02 s | **4.90 / 5.02 s** | 4.89 / 5.02 s |
| 75 m acceleration | 4.35 s | 4.35 s | **4.35 s** | 4.35 s |
| Cornering at R 45 m (four-wheel) | 112.3 km/h, −8.7 %, rear limits | 112.4 km/h, −6.5 % | **112.6 km/h, −6.7 %, rear limits** | 112.6 km/h, −8.9 % |

- **Effect of the 1.8 kg lighter frame alone:** −0.06 s on the autocross, −0.03 s on the fast circuit, +0.2 km/h at R 45 m.
- **Effect of the switch from C to CP (the bodywork):** +0.13 s on the autocross, +0.45 s on the fast circuit. This is what moves the README's headline lap times.
- **All variants, point-mass, after:** A 66.60 / 84.16, B 61.67 / 79.81, C 61.03 / 82.54, D 60.68 / 84.32, CP 61.16 / 82.99 s (autocross / fast circuit). The ranking is unchanged.
- **Following-car penalty (CP, its own wake, q 0.64):** +2.13 s autocross, +1.21 s fast circuit (C was +2.15 / +1.23).

**One thing to know about the 47.5 kg.** It is the mass BuildTubes reports for the weldment before the copes are trimmed. The trimmed weldment (chassis.SLDPRT after TrimTubes) reads **45.3 kg** in CheckChassis.
- My summary of the afternoon called 47.5 kg "the weldment" without saying this. That was imprecise.
- I used 47.5 kg as you asked, because two independent counts of the steel agree with it within 1 %:
  - the CSV tubes with each coped end cut back to its neighbour's outside: 46.9 kg (`matlab/cad/frame_trimmed_mass.m`);
  - the fused solid analysis frame: 47.0 kg.
- **Why the trimmed weldment is lighter:** a tube-by-tube comparison (`cad/chassis/chassis_tube_mass.csv`, new) shows SolidWorks' trimmed tubes are a median 8 mm shorter than the coped ones. A few tubes at shallow joints lose far more, e.g. RT1-RRK_diag: 438 mm of tube left against 602 mm coped. That fits the mitre-plane cut (`Mitre.cs`) removing tube beyond the cope.
- Whether those tubes now stop short of their neighbours in the CAD was not checked. It is listed under Next.
- **CG:** the two methods agree. Coped CSV: x 840.7, z 335.3 mm; SolidWorks trimmed weldment: x 840.3, z 335.5 mm. CheckChassis now compares both against `car_params.txt` (limits 6 % and 10 mm).

**What changed:**
- **Aero table** (`params/aero_variants.csv`):
  - row C is back on run C (ClA 3.98, CdA 1.63, front 0.45);
  - CP has its own row (ClA 3.89, CdA 1.66, front 0.43);
  - `car_from_params` defaults to CP, and load cases, stress cases, cornering balance, sensitivity, following car and media all use it;
  - A to D stay as the like-for-like comparison;
  - one line in `cfd/postprocess.py` (`TABLE_RUN`), so `--update-variants` writes C from run C and CP from run CP.
- **Stress** (frame_fe tube masses scaled to `m_frame`; stiffness unchanged at 1503 Nm/deg, now 31.6 Nm/deg per kg):
  - bump 162 MPa, FoS 2.68 (was 163 / 2.67);
  - corner + brake 107 MPa (was 108);
  - cornering 109 MPa and braking 86 MPa, unchanged.
- **Regenerated:** README results and lap tables, `docs/stress_frame.md`, `media/` tables and figures, `sim/stress/`.

## Summary, 2026-11-18 evening: CFD mesh checks, convergence, wake variant E, SolidWorks bodywork (CP)

**Status: finished, nothing waits on you. No commits.** Only `cfd/`, `cad/generate/cfd_variants.py`, `cad/step/cfd/`, `media/cfd/` and the docs named below were changed. `postprocess.py --selftest` PASS; MATLAB `run_all('test')` 26 of 26 PASS. Full entry at the bottom.

1. **Mesh sensitivity (C, and D for the ranking):**
   - **What was checked:** volume coarsening (`--scale 2.6`), a finer wake-window mesh, and 1 prism layer instead of 2. Results: ClA within 0.3 %, CdA within 2.4 %, front share within 0.01.
   - **Limits of the check:** `--scale` hardly changes the car surface (curvature sets it), and a coarser curvature angle breaks the wing slots. So the surface mesh could not be tested, and these numbers are a lower bound.
   - **y+:** median 31 to 42 on wings, floor and body, 70 to 76 on the wheels; 36 to 46 % of wing and floor faces sit in the buffer layer (5 to 30). The result is wall functions, not a resolved boundary layer.
   - **Ranking: survives.** Autocross is D < C < B, the fast circuit B < C < D, in every check. A swap would need a 5.5 % relative ClA error between C and D; the mesh moves that gap by 0.4 %. Absolute values keep the assumed ±20 % / ±15 % ranges (model error unmeasured).
2. **Convergence:**
   - **Fix:** the force stop never triggered because Fluent also waited for the residuals. Now the residuals are monitored only, and the run stops on downforce, drag and moment at 0.1 % over 100 iterations. The C checks stopped at about 400 iterations instead of 1500.
   - **C:** steady (band 0.04 %).
   - **B and D:** a stationary oscillation (0.13 to 0.16 %, means good to under 0.1 %). They run to the iteration cap.
   - **E and CP:** unsteady (bands 2.5 to 6 %, means good to about 1 %), marked NOT converged.
   - **Residuals:** continuity stalls at 6e-3 to 2e-2. Mass imbalance is 1e-7, so the stalled residual is the unsteady wakes, not an error.
3. **Wake and variant E:**
   - **New measurements:** TKE, deficit, vorticity and upwash in boxes at 1, 2 and 3 L, low (Z 0 to 0.5 m) and high (1.0 to 1.5 m): `cfd/results/wake_boxes.csv`.
   - **Variant E:** lower, wider rear wing; D's angles; 14° diffuser; blunt tail. Physics written before the run: `cfd/variant_E.md`.
   - **E result:** ClA 4.03 (+1.2 %), CdA +4.4 %.
   - **But the wake went up, not down.** At 1 L the centre is at Z 1.49 against 0.95 m. Low-window TKE is −24 %; high-window TKE is +28 % at 1 L and ×4 at 3 L.
   - **Why:** the lower wing sits right over the base wake and lifts it at once.
   - **Verdict:** failed on 2 of 3 criteria. A dirtier wake, but at the following car's rear-wing height.
4. **SolidWorks bodywork (CP):**
   - **Fits:** 1,007,086 cells, after rounding the nose corners to ≥ 40 mm and the pod corners to 25 mm. With the parts' radii the mesh had 1,153,899 cells.
   - **Also simplified:** pods closed, not open-bottomed (an open 2 mm shell cannot be meshed); bottoms 4 mm into the plate.
   - **Shape against the parts:** within 8 mm on the pods and about 12 mm at the nose corners (medians 2 to 4 mm).
   - **Effect against C:** ClA −2.3 %, CdA +1.8 %, front share 0.43 against 0.45. Lap time +0.13 s autocross, +0.44 s fast circuit.
   - **Unmeasured:** the effect of the radius simplification itself. Estimate: under 0.5 %, from the 0.001 m² frontal-area change.

**Lap sim now uses CP for variant C** (your choice, after the first version of this summary; superseded later the same night: row C is back on run C and CP has its own row as the as-built reference, see the summary above):
- **What changed:** `params/aero_variants.csv` row C is CP's numbers, ClA 3.89, CdA 1.66, front 0.43. `postprocess.py` maps row C to run CP (`TABLE_RUN`).
- **Lap times for C:** autocross 61.22 s (was 61.09), fast circuit 83.03 s (was 82.58). `media/results_table.md` was regenerated. Ranking unchanged: autocross D < C < B, fast circuit B < C < D.
- **Caveats:**
  - A, B and D are still on the older CFD bodywork, so C is compared with them on slightly different bodies.
  - CP is unsteady (mean good to about 1 %).
  - The following-car penalty still uses C's wake.
- **Tests:** MATLAB 26 of 26 PASS after the change.

## Summary, 2026-11-18 afternoon: solid cross-check of the frame torsion is valid and agrees with the beam model

**Status: finished, nothing waits on you. No commits.**
- The production CAD (chassis, layout, assembly) was not opened. Everything is in a separate part, `cad/analysis/frame_analysis.SLDPRT`.
- MATLAB `run_all('test')`: 26 of 26 PASS.
- `cfd/`, `cad/step/cfd/` and `cad/generate/cfd_variants.py` were not touched.
- Details are in the entry at the bottom and in `docs/stress_frame.md` (last section).

**Result: the solid model confirms frame_fe's torsional stiffness within 1 %.**

| Free-free torsion case | Solid, 5 mm mesh (1.87 M nodes) | Solid, 4 mm mesh (2.93 M nodes) | frame_fe (beam) |
|---|---|---|---|
| Wheel forces through the links (the headline) | 1509 Nm/deg | **1504 Nm/deg** | **1503 Nm/deg** |
| Couples at the 16 wishbone nodes | 1379 | 1374 | 1386 |

- **How the solid frame is built:** `swh FrameAnalysis` builds it from the same frame CSVs and trim plan as the chassis:
  - hollow tubes;
  - each trimmed end coped against its boundary tubes 1 mm into their wall;
  - untrimmed ends run OD/2 past the node;
  - all 124 tubes fused into one body (15 s);
  - a 40 mm cube imprinted around each loaded node, to give load faces.
- **Loads:** the exact frame_fe load sets, exported by frame_fe to `sim/stress/frame_torsion_loads.csv`. They go on as remote loads with distributed coupling on those faces.
- **Material and supports:** AISI 4130, free-free with inertia relief.
- **Twist:** measured the same way as frame_fe.
- **Checks:**
  - **Mesh:** 5 → 4 mm changes the result by 0.3 % or less. A 3 mm mesh failed with an undocumented mesh error 8 on the Student licence (cause not found).
  - **Overlap:** 0.5, 1.0 and 1.5 mm give identical results. The union is the same shape for any overlap inside the wall.
  - **Joints:** every one moves as one piece. The uz spread in each joint is 0.07–0.17 mm, which is the rigid rotation; the old weldment try had 50–160 mm.
  - **Loads:** they balance to zero.
- **What it says:**
  - The beam model's stiffness, and the 1500 Nm/deg diagonal decision made with it, hold.
  - The close agreement means two effects the beams ignore cancel on this frame: stiffer finite joints and softer local wall flexibility. That need not hold for other frames.
  - Neither model has real welds, brackets or tolerances, so a built frame will be softer than both by an unknown amount. Only a physical torsion test would settle it.
- **Not confirmed:**
  - **Stresses:** the solid's peaks (162 MPa and 668 MPa) sit inside the load cubes, where a whole link force enters. They change with the mesh and are not used. The frame stresses stay frame_fe's nominal beam values.
  - **Frame mass:** the solid has 47.0 kg of steel against the 49.3 kg in the mass budget, because centreline lengths double-count the joints. The weldment agrees with the solid (47.5 kg). The budget was not changed.
- **README and docs:** `README.md` (results row and limits) and `docs/stress_frame.md` now say this. `tools/README.md` has the new step and the API lessons.

## Summary, 2026-11-18: torsion diagonals, rear joint housings, media, README, low-GDI handling

**Status: finished, nothing waits on you. No commits.** `python tools/sw_run.py rebuild` passed all 26 steps (10:08 to 10:28) with no GDI warning. MATLAB `run_all('test')`: 26 of 26 PASS. `cfd/`, `cad/step/cfd/` and `cad/generate/cfd_variants.py` were not touched. Details are in the entry at the bottom.

1. **Frame diagonals: 834 → 1503 Nm/deg for +5.8 kg.**
   - **Search:** `matlab/stress/frame_diagonal_search.m` searched the subsets of 20 candidate diagonals in mass order (pruning sets that cannot reach the target), with `frame_fe.m` as the judge. Every set had to clear the driver, battery, motor and diff envelopes.
     - Floor only reaches at most 1161 Nm/deg.
     - Floor plus top reaches at most 1368 Nm/deg.
     - Reaching 1500 also needs the sidepod tops and the front bulkhead plane.
   - **Chosen set:** 10 tubes, 25.4×1.6.

   | | Before | After |
   |---|---|---|
   | Torsion (through the links) | 834 Nm/deg | **1503 Nm/deg** |
   | Frame | 43.5 kg | 49.3 kg |
   | Car without driver / CG height / front | 229.1 kg / 314 mm / 41.4 % | 235.6 kg / 312 mm / 41.8 % |
   | Autocross C, point-mass / four-wheel | 60.84 / 62.03 s | 61.09 / 62.21 s |
   | Fast circuit C, point-mass / four-wheel | 82.45 / 82.68 s | 82.58 / 82.78 s |

   - The lap sim has a rigid chassis, so it shows only the mass cost, not any gain from the stiffness.
   - **Stress cases after the change:** every case is at FoS 2.67 or more on yield. Worst: bump, 163 MPa. That rise comes from the rear pivots moving outboard (item 2), not from the diagonals: the same case without them gives 168 MPa.
   - **Clearances:** the frame clears the diff (11 mm), the suspension and the rim. No tube crosses another away from a node. Assembly interference: none.
2. **Rear joints: every margin is now at least 4 mm (was 0.9–1.0).**
   - **Assumption:** the housing radius is 12.5 mm, for an Aurora COM-5T spherical bearing (5/16 in bore, 19.05 mm OD) in a 3 mm-wall steel cup. Both the housing radius and the 3 mm minimum are now in `params/car_params.txt`.
   - **Rear margins:** lower 6.3, upper 4.0, pushrod 4.1 mm. The toe-link end is outside the rim window. SuspensionCheck in SolidWorks agrees.
   - **Rear kinematics:** camber gain −0.0433 deg/mm (was −0.0429), bump steer 0.021°, roll centre 79.4 mm (was 75.3), MR 0.773.
   - **Front:** unchanged.
   - **Bug fixed:** the optimiser's diff limit was relative, so it drifted with each re-run. It is now an absolute clearance penalty.
3. **Media and README, all made by scripts:**
   - `matlab/make_media.m`: the bump/steer GIF, the stress plots, and the mass and lap tables.
   - `SaveStandardViews` in the rebuild: six views each of the chassis, layout, assembly and suspension. Sketch points are now hidden in these views.
   - `README.md`: the project, the one-command rebuild, the results, and the assumptions and limits.
4. **Low-GDI dialog, now handled by the harness** (`tools/sw_run.py`, `tools/README.md`):
   - **Detection:** the watcher checks every 0.5 s. It answers the "critically low on GDI objects" warning with **No**, logs it, gives the step 20 s, then stops it. The step reports "STOPPED: SolidWorks low on GDI objects (answered No)", exit 4.
   - **Retry:** `rebuild` restarts SolidWorks and retries that step once.
   - **Prevention:**
     - `close-all` (closes without saving) after every SolidWorks step;
     - a SolidWorks restart before the layout, suspension, simulation and view groups;
     - the GDI/USER count and memory of SLDWORKS on each run-log line.
   - **Trend in rebuild 4:**

   | | GDI | USER |
   |---|---|---|
   | Old single session, peak | 9,688 (warning) | 7,789 |
   | Rebuild 4, BuildAssembly | 5,586 | 4,781 |
   | Rebuild 4, SuspensionAssembly (peak) | 5,819 | 5,238 |
   | After close-all | ~1,900 | ~2,200 |
   | After a restart | 1,100–2,000 | ~1,800 |

   Only the two assembly steps go above about 2,400. Each of them alone stays under 60 % of the 10,000 quota.
5. **Raising GDIProcessHandleQuota: not needed now, not changed.**
   - It would only add headroom; the cause was one long session building up objects, and that is fixed.
   - If you want it anyway, run this as administrator (it needs a reboot):
     `Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -Name GDIProcessHandleQuota -Value 15000 -Type DWord`
   - The maximum is 65,536, but all processes in a desktop session share one GDI pool, so very high values can make the whole desktop fail instead. Undo it by setting the value back to 10000.

**Warnings left (not failures):**
- **Rear lower wishbone vs pushrod:** 7–13 mm³ overlap at droop and static. This is the link tubes touching near their shared outer joint, a modelling simplification.
- **TrimTubes:** node overlaps of up to 333 mm³ at the main hoop top.
- **Motion study:** reaches only +23 mm (front) and +13 mm (rear) of bump. The ±30 mm check is SuspensionCheck's.
- **ChassisStatics:** the beam studies are still not loaded through the API ("No load").


## Summary, 2026-11-17 late night: rim-limited hardpoints, frame FE, solid cross-check, motion, CFD mismatch list

**Status: finished, nothing waits on you. No commits.** `python tools/sw_run.py rebuild` passes all 21 steps (23:16 to 23:38). MATLAB self-tests: 24 of 24 PASS. `cfd/`, `cad/step/cfd/` and `cad/generate/cfd_variants.py` were not touched. Details are in the entry at the bottom.

**Correction:** the rim is **10-inch** (`rim_diameter` 254 mm, Hoosier 18×6.0-10), not 13-inch as the previous summary said.

1. **Ball joints vs the rim: solved without changing the rim.** No 15-inch rim is needed.
   - **How:** the new `matlab/suspension_optimise.m` makes the rim barrel and the tyre hard limits, checked over ±30 mm travel and full steering lock. It holds camber gain, bump steer, roll centre and motion ratio.
   - **Result:** every outer joint is inside the barrel (smallest margin 1 mm at the rear upper joint). SuspensionCheck in SolidWorks agrees with MATLAB, and reports no clashes over travel.

   | | Camber gain, deg/mm | Bump steer, ° | RC, mm | MR |
   |---|---|---|---|---|
   | Front | −0.0391 (was −0.0393) | 0.010 | 59.9 (was 60) | 0.706 |
   | Rear | **−0.0429 (was −0.0477, 10 % less, still inside the −0.03..−0.06 band)** | 0.009 | 75.3 (was 69.4) | 0.772 |

   - **Steering finding:** the old front geometry was **anti-Ackermann**: outer wheel at 31.6° when the inner was at 28°. The new one gives 27.4 to 27.8° (between full Ackermann 20.6° and parallel 28°). Rack travel ±40 mm.
   - **Frame and bodywork followed:** the frame was regenerated with the new pickups (43.1 kg). The sidepod tail now stays 10 mm off the moved MH_M–RS1_U tube.

2. **Frame FE (MATLAB beam model):** `matlab/stress/frame_fe.m`. The write-up is `docs/stress_frame.md` (load cases, boundary conditions, results, hand-checked self-test).
   - **Torsion: 841 Nm/deg** (19.5 Nm/deg/kg). This is **soft**: typical FS frames are 1500 to 3000.
   - **Cause:** no bay has a diagonal in its floor or top plane.
   - **Fix, tested in the model only:** four floor diagonals give about **1250 Nm/deg for +2.7 kg**. The frame files were not changed; that is your call.
   - **Driving cases:** all are at FoS 3.5 or more on yield. Worst: bump, 123 MPa at the rear rocker mount. Largest pickup deflection 1.8 mm, front, in cornering.

3. **Solid cross-check in SOLIDWORKS Simulation: runs on Student, but the number is not valid.** `swh FrameSolid` meshes 1.46 M nodes and solves in about a minute.
   - **Problem:** the trimmed weldment tubes touch their neighbours only along lines, not across faces. Bonded contact leaves one or two tubes unjoined, a different set each run, and Combine and Boolean union fail for the same reason.
   - The step flags the result NOT VALID (44 Nm/deg against 763), so **the MATLAB result stands.**
   - **What would fix it:** an analysis-only solid frame with tube ends overlapping 1 to 2 mm.

4. **Motion bump sweep: not fixed.** Moving the motor to the wheel-centre point changed nothing: the sweep still reaches front +22.7 and rear +14.2 mm. The cause was not found, and it is not simple, so it was left as you allowed. The full ±30 mm sweep stays in SuspensionCheck.

5. **CFD vs parts list for the CFD session:**
   - **Files:** `docs/cfd_parts_mismatch.md` plus two CSVs, regenerated by `cad/generate/compare_cfd_parts.py` (read-only on the CFD files).
   - **Biggest gap:** the CFD body has a cockpit/engine cover behind the front hoop (up to Z 990) that no part has.
   - **Other differences:** the nose is 20 to 50 mm narrower in CFD; the sidepod sections differ by about 30 mm; the front flaps are 8 to 14 mm off from the widened slots; the floor matches.

**Also:** `sim/stress/load_cases.csv` as regenerated by the CFD session (CFD downforce) is what the frame FE now uses.

**Three biggest risks:**
1. **Frame stiffness rests on one beam model.** Nothing independent has checked it: the solid cross-check failed for a geometry reason. If the real frame is softer than 841, the roll-stiffness split in the lap sim is off.
2. **Rear joint margins are thin:** 1.0 mm at the rear upper joint, 0.9 mm at the toe link. Real ball-joint housings and the rim drawing must be checked before parts are made.
3. **The new rear geometry has 10 % less camber gain and a higher roll centre (75 mm, was 69).**
   - `cornering_balance_study` was re-run with the new roll centres: at R 45 m it gives 113.1 km/h and −9.4 % balance (was 113, −10 %). Its outputs in `media/cornering_balance.*` were rewritten.
   - Camber gain is not in the lap models, so its effect on grip is not checked.


## Summary, 2026-11-17 night: CFD of variants A to D done (aero session)

**Status: finished, nothing waits on you. No commits.** Details are in the entry "2026-11-17 (day), CFD/aero" at the bottom.

**Done:**
1. **Variant C now meshes.** The slots are 8 mm wider, the front flaps start at Y 300 (outboard of the nose), and there are smaller fixes, all listed in `cfd/geometry_notes.md`. The aero estimate was updated to match.
2. **Student limit measured:** 1,048,576 cells. Above that, Fluent Meshing exits without writing the mesh.
3. **All four variants meshed with the same settings:** A 272k, B 900k, C 955k, D 1,042k cells. D needed its own geometry fix (beam wing inside the pylon, thicker fins).
4. **All four solved,** 1500 iterations each, 4.5 h in total. Forces converged for B, C and D. A's downforce is near zero and swings slightly, so A is marked NOT converged.

   | | ClA | CdA | front share |
   |---|---|---|---|
   | A | -0.03 | 0.42 | n/a |
   | B | 3.43 | 1.29 | 0.45 |
   | C | 3.98 | 1.63 | 0.45 |
   | D | 4.20 | 1.77 | 0.38 |

5. **`cfd/postprocess.py`** writes the results table, plots and wake metrics (`media/cfd/cfd_results.md`) and puts the CFD rows into `params/aero_variants.csv`. The lap sim now runs on them, with a before/after table against the estimate in `media/results_table.md`.
6. **Lap sim:** with CFD drag, B (moderate wings) is fastest on the fast circuit (79.7 s against C 82.4 s and D 84.3 s), and D is fastest in autocross (60.5 s, C 60.8 s).
7. MATLAB self-tests 24 of 24 PASS.

**For the other session:**
- `sim/stress/load_cases.csv` was regenerated with the CFD downforce, because the old file made `frame_fe`'s self-test fail. Your stress results from before 21:45 used about 10 % more downforce on C.
- Your nose and sidepod differences against the CFD hull (top of this file) are noted, not built into the CFD geometry. The CFD would need re-meshing to take them, and the nose slots and open sidepods would add surface faces against a mesh that is already near the limit.

**Untested / not done:**
- No mesh-sensitivity run (`--scale 2.6 --tag coarse` on C, about 1.5 h).
- No y+ check (needs the Fluent GUI on `cfd/cases/halfcar_C.cas.h5`).
- Residuals fell only 1 to 2 orders.
- The force-based stop never triggered.

**First thing tomorrow:** open `media/cfd/cfd_results.md` and `media/cfd/cfd_convergence.png`, then run the C mesh check (`.venv/Scripts/python cfd/fluent_halfcar.py all C --scale 2.6 --tag coarse`).

**Three biggest risks:**
1. **Only the ranking is trustworthy.** There are 2 prism layers (wall functions), coarse body surfaces, one mesh per variant, and no mesh study. Absolute ClA, CdA and balance can be off by tens of percent, and the lap-time differences between B, C and D (1 to 4 s) are of the same order as that uncertainty.
2. **Balance:** B and C are front-heavy (0.45 against the 0.40 target), and only D is near it. Any setup decision on flap angles should wait for the mesh check.
3. **Mesh fragility:** the slots and trailing edges break the surface mesh at small changes, and D sits 0.6 % under the cell limit. Any geometry change (the other session's nose and sidepods, flap angles) may need another round of geometry fixes. The far wake (2 to 3 lengths) is the weakest result.


## Summary, 2026-11-17 evening: bodywork clashes, tube overlaps, suspension, Motion and Simulation

**Status: finished, nothing waits on you.** `python tools/sw_run.py rebuild` now runs **21 steps, all PASS, in 20 minutes** (20:00 to 20:21). The first step restarts SolidWorks itself. No commits. `cfd/`, `cad/step/cfd/` and `cad/generate/cfd_variants.py` were not touched.

**For the CFD session (disagreements, reported, not changed; details in the entry at the bottom):**
1. **Nose:** the parts' nose is bigger than the CFD hull: ±293 mm wide at the front bulkhead tubes, against about ±263 mm, and its top is at Z 696, against 600. The parts' nose wraps the real frame with 10 mm clearance, and now has 12 slots where the front suspension links pass through. The CFD hull has neither.
2. **Sidepods:**
   - The top is at Z 372 here, against 342 in CFD.
   - The full section runs over X 624..1276, against 660..1240.
   - The tail ends at X 1301, against 1295.
   - The inner face is at |y| 333, against 300.
   - The pod is open at the bottom here, solid in CFD.
   - The frame tube SP2_U would stick out of the CFD pod.
3. **Floor:** a 10 mm plate here, a solid floor in CFD. The diffuser roof is 10 mm thick here, 12 in CFD.
4. **Wings:** positions and sizes agree. CFD adds to the same wings: 8 mm wider slots, trailing edges cut at 97 % chord, endplates moved 20 mm, and pylons.

**Done:**
1. **Bodywork clashes fixed** in `cad/generate/build_parts.py`. Assembly interference went from 290 cm³ to **none** (BuildAssembly), and the independent clearance check (BuildBodies) passes. The rules are below.
2. **Tube overlaps at the 10 joints:**
   - The trim plan has a simple rule: the stronger wall runs through, then the straighter tube, and every other tube is coped against all tubes that rank above it. The plan has 174 rows.
   - Tube ends that reached more than 15 mm past their node are now mitred.
   - Chassis 39.70 kg (was 41.46 before trimming).
   - Two mirrored pairs still overlap by 322 mm³ each: MH_B-MH_T / MH_T-RT2 at MH_T. That is under 3 g each, left as a CheckChassis warning.
3. **Suspension corners:**
   - 24 parts (lower and upper wishbones, upright, hub, tie rod or toe link, pushrod) built from the layout hardpoints and mated into the assembly; the wheels follow the uprights.
   - SolidWorks matches `suspension_geometry.m`: camber gain F −0.0393 / R −0.0477 deg/mm, bump steer F 0.011 / R 0.006 deg, roll centre F 60.0 / R 69.4 mm (MATLAB 69.0), motion ratio F 0.707 / R 0.773.
   - Report: `cad/suspension/suspension_report.txt`.
4. **Motion study "Bump sweep"** (Animation, one linear motor per upright):
   - Front camber gain −0.0388 deg/mm, against −0.0393 from MATLAB.
   - The wheels reach −30 / +22 mm at the front and −30 / +20 mm at the rear: the motor's own point moves 60 mm, but the upright turns in camber, so the wheel centre moves less. That is a WARN; the full ±30 sweep is SuspensionCheck's.
   - Report: `cad/suspension/suspension_motion_report.txt`.
5. **Simulation studies "Torsion", "Braking", "Cornering":** set up, loaded, meshed and run through the API, but **not solved**. This is an API limit on this install, and the reasons are in the next list.

**Design findings for you (warnings, not changed):**
- **Outer ball joints do not fit inside the 13-inch rim:**
  - FR upper ball joint at radius 121 mm from the spindle, RR upper at 140 mm, RR toe link at 121 mm. Each needs radius + 12 mm (joint housing) to stay within the barrel's 116 mm inner radius.
  - That is where every remaining suspension clash comes from: rim against RR upper wishbone 1300 to 1435 mm³, rim against rear upright 483, and smaller ones at the front.
  - Moving only those points ruins the kinematics. Tried in MATLAB: camber gain F −0.027 / R −0.012 deg/mm, bump steer 0.54 / 1.01°, roll centre 44 / 24 mm.
  - So the hardpoints need a new optimisation run in `suspension_geometry.m` with a rim-package constraint, or a 15-inch rim. Not done: it is a design decision.
- **Roll camber:** at 1° of roll the outer front wheel is at −0.92°, the inner at −2.10°. Rear outer −0.48°, inner −1.53°.

**What could not be done through the API (SolidWorks 2026 SP2.1 Student), and what was tried:**
- **Simulation loads on the beam frame.** The weldment is meshed as 110 beams. Loads and fixtures on a beam model go on its joints, and the API hands out no joint objects (`CWJoints` can only recalculate them). Tried at one node (`python tools/sw_run.py ChassisStatics probe`):
  - AddForce2 with every selection type on the node's sketch point, the nearest tube vertex (11 mm off), and the tube body. The sketch point is accepted as a plain point load, but the solver then reports "No load or prescribed displacement is defined": the load never reaches the joint.
  - AddRestraint refuses all three entities.
  - Selecting a joint the way the UI does (`SelectByID2` type "SIMULATION") hung SolidWorks for 30 min. I killed and restarted it; nothing was lost, because only throwaway changes were open.
  - Torsion was rebuilt as a balanced pair of couples with inertia relief so that it needs no fixture. It still fails only on the loads.
  - The studies are kept with their forces in `chassis.SLDPRT`. The link forces at every pickup are in `sim/stress/chassis_statics_report.txt`.
  - Two ways it would work: someone picks the joints in each study, about a minute per study; or the frame is modelled as solids, with forces on tube faces (not tried: the 0.9 to 1.6 mm walls need a very fine mesh).
- **Motion study, two API quirks:**
  - Keys on mate distances never become timeline keys.
  - Once a motion study has been deleted from an assembly, every motor is refused in that assembly, even after save and reopen. Every combination of location, direction and study type was tried. The step therefore reuses an existing study and never deletes a driven one; in the fresh assembly a rebuild makes, the motors are accepted.

**Rules I decided (applied in `build_parts.py`, `check_clearances.py`, `BuildSuspension.cs`, `frame_trims.m`, `Mitre.cs`):**
- Body panel to frame tube outer surface **≥ 10 mm**: room for brackets and for the tolerance of a hand-welded frame. Panels are 2 mm skin.
- Any part to a tyre **≥ 25 mm**: at static, at full bump (+30) and full droop (−30), and for the fronts also at full steering lock (±28°). This covers tyre growth, camber change and flex.
- Body to a moving suspension link: a slot of link radius (15.9 mm OD) **+ 5 mm** all round, swept over the travel ±35 mm. The tie rod's inner end is also swept over the rack travel of ±40 mm.
- Parts may touch each other but not overlap. Endplates hold the wings and the floor carries the sidepods.
- **Tube joints:**
  - The thicker wall runs through.
  - On equal walls, the tube that runs straight through the node (within 18°) runs through.
  - Then the group order, then the longer tube.
  - Each lower-ranked tube is coped against all higher-ranked tubes at the node, except collinear ones (within 3°).
  - A tube end that reaches more than 15 mm past its node is cut on the bisector plane with its most in-line neighbour.
- **Suspension package:**
  - Outer ball joint centre + 12 mm housing must fit within the rim barrel's inner radius (rim diameter / 2 − 11 mm).
  - A link touching the chassis within 40 mm of its inner pivot counts as the bracket, not a clash.

**Harness changes:**
- New steps: `restart-sw`, `SuspensionParts`, `SuspensionAssembly`, `SuspensionCheck`, `SuspensionMotion`, `ChassisStatics`. Diagnostics: `mitre`, `makeprofile`, `ChassisStatics probe`.
- `restart-sw` is the first step of `rebuild`. After several rebuilds in one session SolidWorks reached 7 GB and 14,700 handles, and then failed to open freshly written parts, with no error code.
- Solver files go to `sim/stress/results/` (git-ignored).

## Morning summary, 2026-11-17: the CAD rebuild runs from one command (superseded by the summary above)

**Run this, with SolidWorks open (nothing to click):**

```
python tools/sw_run.py rebuild
```

It takes about 10 minutes. It closes every open document without saving, moves the old chassis, layout and assembly to `old/` folders (nothing is deleted), and builds everything again.

**Runs with no manual action (all PASS in the full rebuild, attempts 2 and 3 below):**
- new chassis part
- ImportFrameNodes
- BuildTubes
- TrimTubes (48 trims, 4 rows none needed, 2 stubs deleted, 114 bodies, 41.46 to 40.79 kg)
- TrimTubes again (changes nothing)
- CheckChassis
- new layout part
- BuildLayout (axes, equations and equation-driven planes fixed; checked again after closing and reopening)
- DrivenTest (wheelbase +50 and main hoop +20 on a copy: the planes follow)
- BuildAssembly (24 components, 19 parts mated, saved)
- SaveStandardViews for the chassis, layout and assembly (now in car axes)

Each step writes its report file, and every run adds one line to `cad/harness_runs.log`. One step alone: `python tools/sw_run.py BuildLayout`, and so on (list in `tools/README.md`). The VBA editor, module imports and F5 are no longer needed. The `.bas` files are kept for reference only.

**Nothing fails. Two warnings are design questions for you, not harness faults:**
1. **Tube overlaps after trimming** (CheckChassis WARN): 20 tube pairs (10 joints, mirrored) still overlap by more than 200 mm³, about 0.08 kg in all. In each pair both tubes are marked "trimmed" in `frame_trims.csv`, so neither is cut against the other. Largest: FS2_L-FH_L / FH_L-MH_L at FH_L (1135 mm³), and MH_B-MH_T / MH_T-RT2 at MH_T (1058 mm³; most likely the spike visible above the main hoop top in `media/views/chassis_Default_As_Machined_side.png`, not yet confirmed). The fix belongs in `matlab/cad/frame_trims.m`: choose which tube runs through at those nodes. It matters for the Ring 4 stress model.
2. **Bodies clash with the frame and wheels** (BuildAssembly WARN): 18 component pairs, 290 cm³ in all, listed in `cad/build_assembly_report.txt`. The biggest: the front-wing main element inside the nose (87 cm³), front-wing flap 1 inside each front tyre (43 cm³ each), the nose skin crossed by front tubes in 48 places (38 cm³), and the sidepods into the rear tyres (9 cm³ each). These are geometry fixes in `cad/generate/build_parts.py`. The car's mass in the assembly (155 kg) counts the imported STEP bodies at SolidWorks' default density, because they have no material.

**If something stops it:** the step is reported as NEEDS A PERSON (exit 3), with the text of the SolidWorks dialog that stayed open for 90 s. Nothing like that happened tonight.

## Machine

Read on 2026-11-16 from PowerShell (`Get-CimInstance Win32_Processor / Win32_ComputerSystem / Win32_VideoController`, `nvidia-smi`):

| Item | Value |
|---|---|
| CPU | AMD Ryzen 7 9800X3D, 8 cores / 8 threads reported (SMT appears off), 4.7 GHz max, 96 MB 3D V-Cache |
| RAM | 32 GB (31.1 GB usable) |
| GPU | NVIDIA GeForce RTX 5070, 12 GB, driver 621.01 (WMI reports 4 GB because of its 32-bit field; nvidia-smi gives 12,227 MiB). Plus the Ryzen's integrated Radeon. |
| OS | Windows 11 Pro 24H2+, build 26300 |

What that means for the plan: Fluent in Ansys Student uses at most 4 cores regardless, so the 8-core CPU is not the bottleneck; a 900,000-cell steady RANS case is 1 to 2 hours per run and 4 to 6 GB of RAM. SolidWorks Simulation and Motion are single-threaded for most of their work and benefit from the high clock. The GPU is for RealView, Visualize renders and nothing in the simulations.

## Software

| Tool | Version | Checked |
|---|---|---|
| SolidWorks Design Premium for Students 2026 | Simulation and Motion add-ins on (no Flow Simulation) | 2026-11-16, by the owner |
| MATLAB R2026a Update 5 | Simulink, Simscape, Simscape Driveline, Simscape Multibody, Vehicle Dynamics Blockset. No other toolboxes (so no Optimization, Curve Fitting or Aerospace functions in the scripts). | 2026-11-16, `ver` via the MATLAB MCP tool |
| Ansys Student (Fluent) | to be installed | |
| SimScale | backup, free plan | |

## Entries

### 2026-11-16, Ring 0 start, repo skeleton and all scripts written up front

- Repo structure created: `params/`, `cad/`, `matlab/`, `sim/`, `cfd/`, `docs/`, `media/`.
- `params/car_params.txt` written (178 entries, SolidWorks equation format) with the Ring 1 starting values; `matlab/common/read_car_params.m` reads it and prints a table.
- Airfoil files generated (NACA 4-digit, `cad/airfoils/`), three SolidWorks macros written as `.bas` text (untested, need the app).
- MATLAB: `accel_test.m`, lap simulator with four tracks, cornering-speed-vs-downforce plot, aero sweep, following-car penalty, sensitivity, `load_cases.m`, `suspension_plots.m`, `aero_plots.m`, `wake_postprocess.m`, Simulink 6b builder, `run_all.m`. Every script has a self-test with a hand-checkable answer; 14 of 14 pass.
- Simulink 6b model reproduces the MATLAB 75 m time to within 0.01 %.
- CFD guide and journal written (untested, need Ansys).
- Not done: nothing in SolidWorks yet (rim, bracket, practice assembly are the owner's first-day work). No commits yet.
- Next: first-day checklist steps 1, 5, 6 (Ansys download, rim, bracket), then MATLAB Onramp.

### 2026-11-16 (second session), pre-CAD engineering and build playbook

- `matlab/suspension_geometry.m`: 3D double-wishbone kinematics (Newton solve of the upright pose) giving camber gain, bump steer, roll centre, motion ratio, KPI, caster, scrub, trail. Hardpoints tuned by grid search and written into `params/car_params.txt` (between the BEGIN/END markers) and `params/suspension_hardpoints.txt`. Results, front / rear: camber gain -0.039 / -0.048 deg/mm, bump steer 0.011 / 0.006 deg over +-30 mm, roll centre 60 / 69 mm static (10 to 128 mm migration in parallel travel), motion ratio 0.71 / 0.77, KPI 6.0 / 5.7 deg, caster 4.7 / 3.7 deg, scrub 19 / 17 mm.
- `matlab/cad/frame_layout.m`: 42 nodes, 98 tubes, 35.4 m, 37.3 kg of 25.4 mm steel tube, written to `cad/frame/frame_nodes.csv` and `frame_tubes.csv`, with a clearance check against driver legs, torso, helmet, battery, motor and diff. Packaging changes it forced: battery 180 x 510 x 370 mm behind the main hoop (34 L, marginal for 6 kWh; sidepod packs listed as the v2 alternative), rear forward pickups moved to X 1485, motor behind the rear box at X 1850 with a 300 mm chain drive, main hoop raised to 980, driver hip at X 850 with a 40 deg seat back.
- `docs/cad_playbook/`: 16 files, one per part in build order, plus `macro_review.md`.
- Macros: three small fixes applied (guarded preference calls, title-line parsing, empty-file guard), `ImportFrameNodes.bas` added. All four still untested.
- Self-tests now 16 (14 + suspension_geometry + frame_layout).

### 2026-11-16 (third session), mass budget, Ring 0 practice guide, Ansys quickstart

- **Mass and CG budget** in `params/car_params.txt`: 20 itemised lines (`m_<item>`, `x_<item>`, `z_<item>`) each flagged CALC / CATALOGUE / ESTIMATE / GUESS in its comment; `mass_car`, `cg_x_from_front_axle`, `cg_height`, `weight_dist_front` and the unsprung masses are now expressions over those lines, so SolidWorks and MATLAB roll them up identically. `matlab/mass_budget.m` (self-test 17) prints the table, checks the file's expressions against the item list, writes `media/mass_budget.md` and `.png`.
- Roll-up: **222.2 kg without driver, 292.2 kg with** (was 230 / 300 guessed). CG x 1004 mm from the front axle, **35.2 % front** (was 47 % guessed), CG height 326 mm (was 300). Only the frame (37.3 kg, CALC) and the motor (12.3 kg, Emrax 228 class, CATALOGUE) have anything behind them; 170 kg is ESTIMATE, 73 kg (25 %) is GUESS. The 35 % front is a consequence of the layout chosen in session 2 (45 kg battery behind the main hoop at X 1370, motor behind the rear axle at X 1850, chain drive and diff on the axle): it is a real finding, not a typo. Options if it is to be moved toward 45 %: sidepod battery packs (the v2 alternative already noted), motor ahead of the axle, driver further forward.
- Headline lap times moved (variant C): 75 m 4.50 -> 4.14 s, 0-100 km/h 3.68 -> 3.12 s, skidpad 4.88 -> 4.87 s, autocross 61.27 -> 60.03 s (-1.24 s), fast circuit 79.79 -> 79.56 s (-0.23 s). Attribution by rerunning with only the mass changed: the 8 kg saving alone is worth 0.26 s on the autocross and 0.16 s on the fast circuit; the rest (1.0 s autocross, 0.36 s on the 75 m) is the rear weight bias feeding the point-mass model's rear-axle traction. The lap sim has no weight transfer, so the handling cost of a 35 % front car (understeer, front tyre load) does not show; treat the gain as the model flattering the layout, not as a reason to keep it.
- Load cases rerun with the new mass and CG (`sim/stress/load_cases.csv`): rear static wheel load 928 N, front 505 N; worst cornering wheel 2246 N lateral.
- Self-tests that assumed 230 + 70 kg now pin those numbers themselves (`car_from_params`, `load_cases`); every other test already overrode the mass. `lap_experiments` sensitivity header in `results_table.md` had a stray format specifier (`-10 %` printed as garbage), fixed.
- `docs/ring0_practice/`: 11 files, exercises 1 to 10 plus the index: orientation, rim (Revolve), bracket (Extrude, Cut, Hole Wizard), hub and the first assembly, equations linked to `car_params.txt` and the project template, airfoil import, mini weldment frame, the 30-minute macro test order, a one-page vocabulary, MATLAB first hour. Every exercise has a hand-computed expected mass and a check. Unsure 2026 names are marked verify (about 30 of them).
- `cfd/ansys_quickstart.md`: Student 2026 R1 install notes and limits, then a quasi-2D NACA 0012 smoke test (wing element from exercise 6, 5 degrees, 20 m/s, 250,000 to 450,000 cells) with the expected Cl 0.45 to 0.60, Cd 0.012 to 0.030, Cp min about -1.9, and a bad-result table. Untested, needs the app.
- `docs/concept.md` starting-values table updated to the rolled-up numbers. `media/README.md` lists the new figure.
- Self-tests now 17 of 17; full `run_all` 51 s.
- Not done: nothing in SolidWorks or Ansys yet; the practice guide and the quickstart are to be corrected by the owner on first use. No commits.
- Next: Ring 0 exercises 1 to 4 (one sitting), Ansys download in the background, then the macro test and the CFD smoke test.

### 2026-11-16 (third session, part 2), battery moved to the sidepods, motor into the bay

- Options were costed with `mass_budget(struct('moves', {{item, x, z; ...}}))` (new option, covered by the self-test): packs in the sidepods between the hoops alone 39.4 % front; motor and inverter into the bay behind the main hoop alone 37.3 %; both 41.5 %; both plus the driver hip 100 mm forward 43.0 %; packs ahead of the front hoop plus motor forward 44.0 % (rejected: the battery would sit beside the driver's shins outside the primary structure). Chosen: packs in the sidepods plus motor and inverter in the bay.
- `params/car_params.txt`: battery is now two packs 530 x 165 x 190 (33 L, marginal for 6 kWh as before), front face X 690, inner face Y 335, bottom Z 105, new `battery_y_inner` (0 would mean one central pack); motor at (1340, 0, 270) in the bay behind the main hoop, chain centre distance 215 mm (20 mm between the motor body and the diff housing); inverter above the motor at (1380, 500). `x_battery`, `z_battery`, `x_motor`, `z_motor` are expressions of the layout parameters now.
- `frame_layout.m`: sidepod battery structure (group `sidepod`, nodes SP1 in the front hoop plane and SP2 in the main hoop plane, outer rails at y +-525, z 80 and 320; 9 tubes per side) added when `battery_y_inner` > 0; the battery envelope becomes two boxes. Frame: 50 nodes, **116 tubes, 41.9 m, 43.3 kg** (was 42 / 98 / 35.4 m / 37.3 kg), sidepod tubes 6.1 kg, all clearances 12 mm or more (battery boxes 12 mm to the rails, motor 30 mm to the rear box cross tube). `m_frame` 43.3, `x_frame` 866, `z_frame` 349 (CALC); `mass_budget.m` now warns when those drift from `frame_tubes.csv`.
- Result: **228.7 kg car, 298.7 kg with driver, CG x 908 mm, 41.4 % front, CG height 314 mm** (was 222.2 / 292.2 / 1004 / 35.2 % / 326). The 6.5 kg of extra frame and bracket mass is the price.
- Headlines (variant C): 75 m 4.31 s (the 35 % front layout gave 4.14, the old guessed 47 % layout 4.50), 0-100 km/h 3.39 s, skidpad 4.88 s, autocross 60.71 s (60.03 / 61.27), fast circuit 79.73 s (79.56 / 79.79). The point-mass model only sees less rear traction and 6.5 kg more; the handling benefit of 41 % front is outside what it can show. Load cases rerun: front static wheel load 606 N, rear 859 N.
- Docs updated: `docs/cad_playbook/02_chassis.md` (sidepod structural members, 116 lines, 40 to 45 kg), `13_details.md` (two battery packs, motor in the bay, inverter block, 215 mm chain), `docs/concept.md`, README limits line.
- 17 of 17 self-tests, full `run_all` 51 s. No commits.
- Open: the sidepod bodywork section (`08_sidepods.md`) must clear y +-540 and z 320 between X 700 and 1220; the cooling radiator was assumed in the sidepods and now competes with the packs (4 kg, GUESS, left at X 1000); the main-hoop braces still run to RT1/RT2 over the motor bay, so the inverter block (300 x 200 x 100 at Z 500) needs an Interference Detection check in Ring 2.

### 2026-11-16 (fourth session), weight transfer in the corner limit, SolidWorks MCP review, build123d bodies

- **Four-wheel steady-state cornering model** `matlab/lapsim/cornering_balance.m` (self-test 18): lateral load transfer per axle from the roll-stiffness, roll-centre and unsprung terms, roll-centre heights from `suspension_geometry` (60 / 69 mm), roll stiffness split from the ride-frequency springs (38 % front, no anti-roll bars), downforce by `aero_balance_front`, tyre capacity `mu0 fz_ref^0.10 Fz^0.90` per wheel, limit set by the axle that reaches 100 % use first, `balance_pct` = front use minus rear use (positive = understeer at the limit). `lapsim` got the option `four_wheel` (corner limit from this model; the passes stay point-mass). `cornering_balance_study.m` (self-test 19) sweeps front weight fraction and aero balance at 45 and 100 m and writes `media/cornering_balance.png`, `.csv`, `.md`. Assumptions are listed in the figure title, the markdown and `docs/lapsim.md`.
- **Results, variant C, R 45 m, aero 45 % front as filed** (grip-limited corner speed, which axle limits, balance): 35 % front 108.8 km/h rear -21.5 %; **41.4 % front 113.0 km/h rear -9.9 %**; 47 % front 116.5 km/h front +1.6 %. Point-mass model: 119.8 km/h for all three. At 41.4 % front: aero 35 % front 113.2 km/h front +6.9 %; aero 55 % front 106.9 km/h rear -22.8 %. **R 100 m is power-limited** for every case (154.6 km/h top speed; the grip limit alone would be 236 to 335 km/h), balance ordering the same as at 45 m. The lap cost of load transfer (four-wheel corner limit vs point-mass, as filed): autocross +1.26 s (60.71 to 61.96), fast circuit +0.36 s.
- **What drives the balance:** in a steady corner the axle whose downforce share is below its weight share gives up first, so with 58.6 % of the weight on the rear and only 55 % of the downforce, the rear limits. The roll stiffness split barely moves it (38 to 65 % front: -9.9 to -6.0 %). With the aero balance trimmed to match the weight distribution (aero_front = wd_front) the three weight fractions come within 2 km/h of each other (35 % 114.5, 41.4 % 115.5, 47 % 116.4 km/h); aero_front 0.40 makes the 41.4 % car neutral at 45 m (116.5 km/h, -1.7 %), and the four-wheel autocross time goes from 61.96 to 61.57 s with aero 0.41.
- **Driver 100 mm forward** (`mass_budget` moves, hip 850 to 750): 42.9 % front, CG height unchanged, 45 m speed 113.0 to 114.2 km/h, balance -9.9 to -7.0 %, autocross -0.06 s, fast circuit -0.15 s (four-wheel). With the aero trimmed to match, the gain is 0.2 km/h. **Decision input: 41.4 % front is acceptable; moving the driver is not worth the cockpit change. Trim the balance with the wings (rear wing angle up or front flap down, towards 40 % front aero) and keep a front anti-roll bar as the fine control.** Layout not changed.
- **What depends on assumed numbers:** every speed scales with `tyre_mu_peak` 1.4; the size of the weight-distribution effect scales with `tyre_load_sensitivity` 0.10 (exponent 0 to 0.20: 41.4 % front gives 123.5 to 106.1 km/h, the 35-to-47 % spread 6 to 8 km/h, ordering unchanged); the sign of the balance depends on `aero_balance_front` 0.45, which no CFD has confirmed; roll centres are static and the roll stiffness has no bar and no tyre stiffness; `cg_height` 314 mm is 25 % GUESS by mass (280 to 350 mm moves the 45 m speed by 1.3 km/h). The conclusions that survive all of these: the rear limits at 41.4 % with 45 % front aero; aero balance is a stronger lever than 100 mm of driver; 100 m corners are power-limited for this car.
- **SolidWorks MCP review** (read-only, nothing installed): `docs/solidworks_mcp_review.md` covers alisamsam, haunchen, lildebil0, vespo92 and the run-and-verify server (ladla90077-web). Recommendation: none for Rings 0 to 2; lildebil0 is the candidate later with its VBA and reflective-call tools removed; alisamsam (`execute_python`, committed API key) and vespo92 (tools that change macro security settings) not on this machine.
- **build123d bodies**: `cad/generate/build_parts.py` builds 18 parts from `car_params.txt` and writes `cad/step/*.step` in car coordinates: tyres (hollow 8 mm carcass with the ground flat, 3.6 kg), rims (2.1 kg), front and rear wing elements at the C angles (main LE -600 / lowest point Z 60; rear stack TE at X 2300, main LE Z 1150), four endplates (rear top raised to Z 1549 because the C flap-2 TE at 1509 overtops the playbook's 1470), floor with the 12 deg diffuser and four strakes, nose (ruled loft, 2 mm skin, open at the front hoop), sidepods (2 mm skin, open inboard; the battery-structure box |y| 320 to 540, z 60 to 320, X 700 to 1220 checked by intersection: 0 mm3 overlap). All 18 built, none skipped; run with `uvx --from build123d python cad/generate/build_parts.py` (built here with build123d 0.13 in a throwaway venv). Untested in SolidWorks: not opened in the app yet.
- Self-tests now 19 of 19 (`run_all` full pass). Docs: `docs/lapsim.md` (model, tests, limits), `cad/README.md`, `cad/generate/README.md`, `media/README.md`. No commits.
- Open: the aero balance trim is a wing-angle decision for Ring 5 (CFD gives the real `aero_balance_front`); a front anti-roll bar parameter is not in `car_params.txt` yet; the STEP bodies need the single-solid Check on import.

### 2026-11-16 (fifth session), first SolidWorks test, macro fixes

- **First real test** on SOLIDWORKS Design Premium for Students 2026 SP2.1 (by the owner): the Student edition runs VBA macros; the STEP import of `cad/step/tyre_front` gives one solid with no faulty faces. `SaveStandardViews` ran after two lines were commented out (`swColorsBackgroundAppearance_PlainWhite` compile error, `ViewDisplayShadedWithEdges` error 438). `ImportFrameNodes` drew 116 lines with shared end points once the CSVs were converted to CRLF by hand; `FeatureManager.FeatureByPositionReverse` failed with 438 and the rename hit the Origin.
- **Weldment profiles made by hand** in `cad/weldment_profiles/formula/tube_round/` (`25.4x2.4.sldlfp`, `25.4x1.6.sldlfp`), with `cad/weldment_profiles` registered in System Options > File Locations > Weldment Profiles (Standard `formula`, Type `tube_round` in the Structural Member dialog).
- **Macro fixes** (names checked by reflection against the installed 2026 `SolidWorks.Interop.swconst.dll` / `sldworks.dll`; the online API Help could not be read): `SaveStandardViews` uses `ModelView.DisplayMode = swViewDisplayMode_ShadedWithEdges` (5) and `swColorsBackgroundAppearance_Plain` (0) with a white viewport colour, restoring the user's settings afterwards. `ImportFrameNodes` reads files whole (LF or CRLF), names sketches through `SketchManager.ActiveSketch`, and makes one 3D sketch per group (`FRAME_hoop` 12, `FRAME_hoop_brace` 10, `FRAME_sis` 7, `FRAME_bulkhead` 4, `FRAME_sidepod` 18, `FRAME_front` 32, `FRAME_rear` 33 lines). Audit of the other two: `ImportAirfoil` had the same `FeatureByPositionReverse` and `Line Input` patterns (fixed); `ExportConfigsSTEP` referenced `swStepExportGeometry`, not in 2026, a guaranteed compile error (removed). `BuildAssembly.bas` does not exist. All four find the repo root by walking up to `params/car_params.txt` and are saved with CRLF.
- `matlab/cad/frame_layout.m` writes the CSVs with explicit CRLF (new `write_csvs`, self-test checks the bytes); CSVs regenerated (content unchanged, 116 tubes, 43.3 kg). `.gitattributes`: `*.csv text eol=crlf`.
- Docs: `docs/cad_playbook/02_chassis.md` (profiles done, steps 2 to 6 for the per-group sketches: hide the others, box select, Structural Member, rename `SM_<group>`), `docs/cad_playbook/macro_review.md` (section "Tested in SolidWorks 2026", how to run a macro), `cad/macros/README.md`.
- Untested, needs the app: all four fixed macros. No commits.
- **Second macro test:** `ImportAirfoil` failed to compile ("Expected Function or variable"). The cause is that `IModelDoc2.InsertCurveFileBegin` returns nothing and was assigned to `ok`; `IPartDoc` has no `InsertCurveFile*` members, so the calls stay on `ModelDoc2` and Begin is now a statement. Every API call in the four macros was then checked against the exact interface of its variable from the installed 2026 interop DLL: member exists, no Sub used as a value, writable properties, argument counts. That was 76 uses, and no other problem was found (details in `docs/cad_playbook/macro_review.md`, "Second test"). Still untested in the app.
- **`cad/macros/BuildTubes.bas`** (new, untested, needs the app): the one-click frame build after `ImportFrameNodes`. Per `FRAME_<group>` sketch it builds one Structural Member from that sketch's segments, using `CreateStructuralMemberGroup` and `InsertStructuralWeldment5` (falls back to `InsertStructuralWeldment4`): `formula` / `tube_round`, size per group from `frame_tubes.csv`, end miter, named `SM_<group>`. If SolidWorks refuses a branched network as one group, it retries with one group per segment. It then sets AISI 1020 (in the installed material database, 7900 kg/m3), updates the cut list, prints PASS/FAIL for tubes per group (12/10/7/4/18/32/33), bodies (116), cut length (within 5 % of 41.88 m) and mass (38 to 46 kg), and saves (an unsaved part becomes `cad/chassis/chassis.SLDPRT`). Reason: in 2026 the Structural Member command shows all sketches during selection, so box selects caught other groups. All 136 API member uses in the five macros pass the per-interface check. New `docs/cad_playbook/02a_frame_in_3_steps.md`; `02_chassis.md` steps 3, 9 and 10 updated.
- **Scripting check for the remaining CAD steps:** the installed 2026 API covers all of them. Trim is `InsertWeldmentTrimFeature2`; master layout is `InsertRefPlane`, `InsertReferencePoint` and `InsertCoordinateSystem`; assembly is `AddComponent5` and `AddMate5`; Motion is `swmotionstudy.dll`, starting from `GetMotionStudyManager`; Simulation is `cosworks.dll` (`CreateNewStudy3`, `AddForce3`, `AddRestraint`, `RunAnalysis`, `GetMinMaxStress`). Motion and Simulation need their add-ins loaded and their type libraries referenced in the macro project.
- **BuildTubes first run, bug fixed:** with no `FRAME_*` sketches it inserted a Weldment feature before stopping, and a rerun added `Weldment1` (`PartDoc.IsWeldment` stayed False). The macro now checks all seven groups (sketch, segments, CSV size, profile file) before changing anything and stops with "Nothing was changed". It inserts the Weldment feature only after that, and only if none exists: `IsWeldment`, type name `WeldmentFeature`, or a feature named `Weldment`/`Weldment<n>`. The member build itself is still untested in the app.
- **BuildTubes second run:** 6 of 7 groups built (each with one group per segment; SolidWorks refuses a branched network as one group, with no message). Rear was refused because of a duplicate rail: `RT1-RT2_L/R` (200 mm) overlaid `RRK-RT1` + `RRK-RT2`, since the rocker mount RRK lies on that line. Removed `RT1-RT2` from `frame_layout.m`. Frame now 114 tubes (rear 31), 41.48 m, 42.97 kg, centroid x 860 / z 348; `car_params.txt` `m_frame` 43.0 and the frame and bracket centroids updated; car 228.4 kg, 41.5 % front. New `topology_check` in `frame_layout` (self-test pins a 3-finding toy case and a clean frame). `run_all` 19/19. BuildTubes now reads the expected counts from the CSV, skips stale or failing groups instead of stopping, builds a refused group segment by segment and lists every failed segment (tube id, nodes, length), saves what works, and writes `cad/chassis/build_tubes_report.txt`. Untested in the app.
- **BuildTubes third run: ALL PASS** (owner's test). 7 groups 12/10/7/4/18/32/31, 114 bodies, 81 cut-list items, cut length 42.57 m (+2.6 % on 41.48 m), AISI 1020, **SolidWorks mass 41.5 kg** vs `m_frame` 43.0 (CSV 42.97 kg at 7850 kg/m3 = 43.24 kg at 7900). The 1.7 kg gap is most likely the node overlaps removed by the simple cut between members; the +2.6 % length is the cut-list measuring the longest extent of angled ends, not extra steel. `m_frame` left at 43.0 until the trimmed mass is known.
- **Trim plan and macro:** `matlab/cad/frame_trims.m` (self-test 17 of 20) writes `cad/frame/frame_trims.csv`: one row per node, boundary = the strongest tube there (wall, then group order hoop > hoop_brace > bulkhead > sis > front > rear > sidepod, then length) plus a straight-on partner of the same group, all other tube ends trimmed; 50 rows, 172 ends. `cad/macros/TrimTubes.bas` (untested, needs the app) executes it with `InsertWeldmentTrimFeature2` (end trim, coped cut, planar fallback), matching bodies to tubes by centroid and box (unique within 25 mm; nearest tube midpoints are 60 mm apart), check first, carry on past failures, report `cad/chassis/trim_tubes_report.txt`. Checker: 203 member uses in six macros, no problems. `run_all` 20/20. Docs: 02_chassis step 7, 02a step 4, macro_review, macros README. No commits.

### 2026-11-17, master layout and assembly macros

- **Scripting check for the rest of the CAD work:** every remaining step can be scripted through the 2026 API (table in `docs/cad_playbook/macro_review.md`). Motion and Simulation also need their add-ins loaded and their type libraries referenced.
- **`cad/macros/BuildLayout.bas`** (untested, needs the app) builds `cad/layout/master_layout.SLDPRT` from `car_params.txt`:
  - default planes renamed: GROUND = Front, CENTRE = Top, FRONT_AXLE = Right. This is the car-coordinate mapping the frame and STEP parts already use, and it corrects `00_index.md`;
  - equation file linked;
  - REAR_AXLE, MAIN_HOOP, FRONT_HOOP and WHEEL_CENTRE_HEIGHT, each checked by its real position and tied to its global variable;
  - FRONT_AXLE_AXIS and REAR_AXLE_AXIS;
  - `HP_front_right` and `HP_rear_right` 3D sketches with a named reference point `HP_<name>` for every f_* / r_* hardpoint.
  - Layout sketches and configurations come later.
- **`cad/macros/BuildAssembly.bas`** (untested, needs the app) builds `cad/formula_single_seater.SLDASM`:
  - STEP bodies imported once to `cad/body/*.SLDPRT`;
  - layout fixed;
  - chassis and bodies mated plane-to-plane to the layout, or fixed if a mate is refused;
  - left tyres and rims as 180-degree turned copies;
  - interference list, partial mass and CG, save, `cad/build_assembly_report.txt`.
  - Suspension corners, wing sub-assemblies and configurations come once those parts exist.
- **Checks:** 326 member uses in eight macros and 67 enum uses, no problems. No commits.
- **TrimTubes first run (owner):** 30 of 50 trims made; bodies 114 before and after; mass 41.46 to 41.30 kg; saved. The 20 failed rows all involved 17 bodies that were already unmatched before any trim: their centroids are on the tube axis but shifted 19 to 42 mm along it, because BuildTubes' simple cut lengthens one tube at a node and shortens the other.
  - Matching is now by distance to the tube's centreline segment (12 mm or less, next tube at least 8 mm further). On the real centroids: 0.3 to 4.1 mm own tube, 54 mm or more to the next.
  - Re-run guard: the macro stops if trim features exist that are not named `Trim_*`.
  - The structural members lost their `SM_` names in SolidWorks (now "25.4x2.4 (1)" and so on). TrimTubes does not touch them. BuildTubes now also finds an existing member as a child of its `FRAME_<group>` sketch, so a re-run no longer builds the tubes twice.
  - Untested in the app. No commits.

- **TrimTubes second run (owner):** the old module ran (old report format and old scores), most likely because the import added `TrimTubes1` next to the old `TrimTubes`. 16 of the first run's 30 trims had lost their `Trim_` names and were applied a second time (mass +0.00 kg). The part now has 46 trim features. v3 adds a version stamp, a done record per row (custom property `TrimDone_<node>`), a guard that stops when there are more trim features than known-done rows, and a full tube/body distance table in the report. Recommended: a diagnostic run on the current part, then a clean rebuild (ImportFrameNodes, BuildTubes, TrimTubes v3). Untested in the app. No commits.
- **Clean rebuild and TrimTubes v3 (owner):** ImportFrameNodes 114, BuildTubes ALL PASS, TrimTubes 50 of 50 made, mass 41.46 to 41.05 kg, but 116 bodies against 114. No row has a boundary that touches the trimmed tube away from the node end, so the likely cause is overrun tube ends left as stubs beyond the boundary (BuildTubes' simple cut overruns up to about 80 mm). TrimTubes v4: body count after every trim (names the splitting trim), stub cleanup with one Delete/Keep Body feature (strict size and position rules; anything else is listed, not deleted), cleanup also on a re-run where all rows are done, body check = 114. Untested in the app. No commits.

### 2026-11-17 (overnight), terminal harness: the CAD builds without the VBA editor

The owner asked for a harness: one command that drives SolidWorks 2026 from the terminal, handles documents and message boxes itself, and rebuilds everything with checks after every step.

- **Approach:** the macros were ported to C# (`tools/sw_harness/*.cs`). `tools/sw_run.py` compiles them with the .NET SDK's Roslyn compiler against the installed interop DLLs and runs them out of process over COM. Nothing new is installed. Python with pywin32 was tried first and dropped: late binding turns argument-less methods into properties, `makepy` fails on the SolidWorks type library, and typed object arrays cannot be passed. VBA cannot run without the editor and a `.swp` built by hand. Reasons in `tools/README.md`.
- **Dialogs:** the API calls are silent (`OpenDoc6` and `SaveAs3` with the Silent options). A watcher logs the text of every SolidWorks dialog box. A box open for 90 s stops the step as NEEDS A PERSON. Only progress boxes appeared ("Open Progress", "Calculating interferences").
- **Findings, by step:**
  - **BuildTubes:** every structural member was refused at first. An `object[]` handed to `StructuralMemberGroup.Segments` is dropped silently (it reads back null). `SketchSegment[]` and `StructuralMemberGroup[]` work. After that: ALL PASS, 114 bodies, 42.57 m, 41.5 kg.
  - **TrimTubes:**
    - `InsertWeldmentTrimFeature2` returns a feature even when it is in error (code 1). Such a feature cuts nothing and is skipped by the `FirstFeature` walk, but `FeatureByName` finds it. The v3 chassis built by hand had only 24 good trims of 50.
    - The cause is one tube in the row that its structural member had already shaped against the boundary (0 mm³ overlap).
    - Fix: check the error, delete the bad feature, try each tube alone, and make the row from the tubes that work. A row with nothing to cut is recorded as "none needed" (the 4 SP rows). A tube left out that still overlaps gets a second trim against the boundary plus the tubes it runs into (`Trim_MH_L_R_2`).
    - `Body2` handles go stale after every delete or rebuild, so bodies are re-matched by centroid before every call (this was the cause of `RPC_E_SERVERFAULT`).
    - The 2 stubs are the overrun of FH_M-MH_M beyond the main hoop, measured at 600 to 660 mm along a 600 mm tube. They are deleted.
  - **BuildLayout:**
    - The "axis refused" and "value only" planes came from `If Not result` on a COM True that came back as `1` (VBA's `Not 1` is truthy).
    - `EquationMgr.Add3` returns -1 for every form; `Add2` works.
    - SolidWorks silently drops equation lines longer than about 500 characters. 3 equation lines did not load. The two CG lines were 754 and 765 characters long, and a 442-character line loads. After the split, every line loads. **`params/car_params.txt` changed:** each of the two long CG lines is now split into two partial sums (`cg_x_moment_1/2`, `cg_z_moment_1/2`), with a comment explaining why. MATLAB reads 266 names, 0 values changed (mass_car 228.40, cg_x 907.50, cg_h 313.65, wd 0.4145; `mass_budget` file check agrees).
    - The layout is checked again after it is closed and reopened, and `car_params.txt` is byte-compared before and after (SolidWorks does not write it).
    - Incident, repaired at once: one of my patch scripts truncated `car_params.txt`. It was restored from the copy taken before the step and checked byte for byte. Patch scripts now build and check the whole text before they open the file for writing.
  - **SaveStandardViews:** the car is modelled Z up (GROUND = Front plane), so SolidWorks' "Top" view showed the car upside down from the side, and its iso view lay the car on its side. The views are now set in car axes (iso from front-left above, front, side, top, rear, bottom) and read back to check. `ModelView.Orientation3` stores screen right, screen up and the direction toward the viewer as the columns of its 3x3.
  - **BuildAssembly:** the 18 STEP bodies are imported to `cad/body/*.SLDPRT` (again whenever a STEP file is newer than its part), 19 parts are mated to GROUND/CENTRE/FRONT_AXLE, and 4 left-wheel copies are added. A second run adds nothing. Interference is reported per component pair as a warning (see the summary at the top).
- **Rebuild attempts (`python tools/sw_run.py rebuild`):**
  1. 12:12: stopped at the first TrimTubes, 48 of 50 rows. RS1_U_L/R: each of the three tubes that work trims cleanly alone, but the three together gave a trim in error. The same rows had passed in the run before, so SolidWorks is not fully repeatable here. Fix: when the kept tubes error together, the row is grown one tube at a time and stays error-free; a tube that does not fit gets its own `Trim_<node>_<k>`.
  2. 12:18: **all 15 steps PASS** in 11 minutes (RS1_U went through the normal path this time, so the new fallback was not exercised).
  3. 12:29: **all 15 steps PASS** in 10 minutes. The new fallback was used at RS1_U_R: of the three tubes that trim alone, two went into one trim, and the third (MH_M-RS1_U_R) then errored on its own with 0 mm³ of overlap with the boundary, so it needs no cut. A second TrimTubes run changed nothing, as in attempt 2.
- Docs: `tools/README.md` (new), `cad/macros/README.md` and `docs/cad_playbook/02a_frame_in_3_steps.md` (point to the harness), `docs/cad_playbook/macro_review.md` (the `Not 1` bug is still in `ImportAirfoil.bas` line 90 and `BuildTubes.bas` line 193; the `.bas` files were not changed). `.gitignore`: `tools/sw_harness/bin/` (compiled exe and copied SolidWorks DLLs).
- Files kept: the hand-built v3 chassis is `cad/chassis/old/chassis_20261117_082013.SLDPRT` and the v1 layout is `cad/layout/old/master_layout_20261117_085039.SLDPRT`. Copies made by my own test runs were removed. Each `rebuild` moves one copy each of the chassis, layout and assembly into the `old/` folders; clear them when you like.
- Not touched: `cfd/`, `cad/step/cfd/`. No commits.

### 2026-11-17 (day), CFD/aero: estimate, half-car geometry, Fluent meshes and runs for A to D

Brief: aero balance target, pre-CFD aero model, CFD geometry, scripted Fluent setup, lap-sim link; then (second brief) fix the variant C surface mesh, mesh all variants under the Student limit, run them, post-process, and say plainly that only the ranking is trustworthy. Not touched: `cad/macros/*`, `tools/`, `cad/chassis/*`, `matlab/cad/frame_layout.m`, `m_frame`. No commits.

- **Balance target:** `aero_balance_target` = 0.40 front in `params/car_params.txt` (ESTIMATE/target: the cornering study finds the neutral front aero share at 0.39 to 0.40 at R 45 m with 41.5 % front weight; it rests on mu 1.4 and load sensitivity 0.10). The lap sim (`opts.aero_front = 'target'`) and the cornering study read it.
- **Variant table:** `params/aero_variants.csv` (ClA, CdA, front share, range, source) is what the lap sim reads (`car_from_params` default). `aero_estimate(struct('write_variants', true))` writes the estimate rows and never overwrites rows whose source starts with CFD; `cfd/postprocess.py --update-variants` writes CFD rows. `params/aero_variants_estimate.csv` keeps the estimate for the before/after table (`lap_experiments` section 5, `media/results_table.md`).
- **Pre-CFD estimate** (`matlab/aero/aero_estimate.m`, `docs/aero_estimate.md`), all ESTIMATES: ClA A -0.10, B 3.23, C 4.40, D 4.59 m2; CdA 0.53 / 1.15 / 1.44 / 1.52; front share B 0.52, C 0.48, D 0.43. B and C are front-heavy against the 0.40 target; reaching it needs the front flaps about 12 to 13 deg flatter (C: ClA 4.40 -> 4.05). Interpretation I took: the front wing sits at `fw_le_x` -960 mm (the playbook's -600 puts the flaps through the front tyres) and its flaps start at `fw_flap_inner_y` 300 mm (outboard of the nose); both are new parameters marked ESTIMATE.
- **CFD geometry** (`cad/generate/cfd_variants.py`, `cfd/geometry_notes.md`): half car, all checks pass (35 of 35). Changes made to get Fluent to mesh it, each recorded in the notes: slots 8 mm wider than `wing_element_gap`, trailing edges cut at 97 % chord, nose tip raised, rear endplate 20 mm back, floor top Z 75 and a filler on the diffuser roof (sliver faces at Y = 0, found as a second `symmetry` face in `faces_C.csv`), and for D the beam wing moved inside the pylon chord (`beam_x_le` 1800 -> 1690) and 10 mm endplate fins.
- **Student limit measured:** Fluent Meshing refused a 1,393,684-cell mesh: "can only be used with meshes containing less than 1048576 cells or 1048576 unmeshed faces", and exited without writing it. So the limit is 1,048,576 cells.
- **Mesh settings** (same for all variants, `cfd/fluent_halfcar_setup.md`): wing faces 12 mm and minimum 2.5 mm cannot change (coarser wings or a larger minimum break the slots: "breakout detected", self-intersections); cells follow the surface faces (about 4.8 per face), not the refinement boxes, and the volume growth rate had no effect. What fits: non-wing sizes x2 and **2 prism layers**. Cells: A 271,859, B 900,187, C 955,009, D 1,042,343 (0.6 % under). Eleven other settings were tried on D before its geometry was changed; a 3 mm minimum trailing-edge thickness made things worse and is off (`TE_MIN_MM` = 0).
- **Consequence of 2 prism layers:** wall functions, y+ roughly 30 to 150 (not checked yet), separation on the flaps and in the diffuser less reliable. With the coarse non-wing surfaces this is the main reason only the ranking is trusted.
- **Solver:** about 3 s per iteration at 1 M cells on 4 cores; 1500 iterations is about 75 minutes per variant.
- **Post-processing** (`cfd/postprocess.py`, self-test PASS with hand values: ClA 4.1667 for 1000 N at 20 m/s, front share 0.50 from the pitching moment, uniform-wake deficit 0.2 / q-ratio 0.64 / TI 0.10 / upwash 7.13 deg, Gaussian wake read back): averages the last 200 iterations, doubles to the full car, front axle load = DF - M / wheelbase, force-convergence flag (drift < 1 % between the last two windows, band < 2 %), wake planes interpolated onto a 10 mm grid (area weighted, unlike the node average in `matlab/cfd/wake_postprocess.m`).
- **Git:** `.gitignore` now also ignores `cfd/**/*.dat`, `*.h5`, `*.cdat`, `*.cxa`, `fluent*.trn`, `*.pmdb` (Fluent's CAD cache next to the STEP files), `*.prev.*`, `.venv/`, `__pycache__/`; `cfd/cases/` and `*.log` were already ignored. Not `*.dat` everywhere: the airfoils in `cad/airfoils/` are `.dat` files. Stray logs moved into `cfd/cases/`. `cfd/requirements.txt` lists the venv packages.
- MATLAB self-tests 22 of 22 PASS after the changes.
- **Runs** (17:09 to 21:39, 1500 iterations each, `cfd/fluent_halfcar_setup.md` "What has run"). Full car, from `media/cfd/cfd_results.md`:

  | | ClA | CdA | L/D | front share | forces |
  |---|---|---|---|---|---|
  | A | -0.03 | 0.42 | - | n/a | NOT converged by the 2 % band test (downforce near zero swings by ClA +-0.006); drag converged |
  | B | 3.43 | 1.29 | 2.65 | 0.45 | converged |
  | C | 3.98 | 1.63 | 2.44 | 0.45 | converged |
  | D | 4.20 | 1.77 | 2.37 | 0.38 | converged |

  Every value is inside the pre-CFD estimate's range, with the same ranking. The estimate was about 10 % high on downforce for C and D, 12 to 16 % low on drag, and 0.03 to 0.07 too far forward on balance. Components for C: front wing ClA 2.00, rear wing 2.09, floor 0.40, body -0.39 (lift), wheels -0.12. Residuals fell only 1.2 to 2.2 orders (forces flat from about iteration 200). Fluent accepted the force-based stop but it never triggered (cause not found), so every run took the full count. B and D each needed a second launch attempt (gRPC "Connection refused").
- **Wake** at 1 car length, following-car window: q-ratio A 0.74, B 0.66, C 0.64, D 0.65 (estimate 0.72 / 0.56 / 0.52 / 0.54); turbulence intensity C 0.062, D 0.063. D's beam wing and fins lift the wake centre (Z 1.38 m against 0.91 for C) but do not make the window flow measurably more turbulent. Far planes have about 750 mesh nodes per half plane: comparison only.
- **Post-processing fixes after the real runs:**
  - Near-zero downforce: the convergence band is measured against at least ClA 0.1 m2 (self-test case added).
  - The "estimate" column now reads `params/aero_variants_estimate.csv`; it had shown the CFD rows.
  - Estimate front share n/a for A.
  - Wake plots on common axes.
  - `aero_plots` front balance NaN for |ClA| < 0.5.
  - `lap_experiments` takes the following-car q-ratio from `cfd/results/wake_cfd.csv`. It is now 0.64 from CFD (was an assumed 0.70); penalty autocross +2.20 s, fast circuit +1.26 s.
- **Variant table:** `postprocess.py --update-variants --force` wrote CFD rows for A to D. `--force` matters only for A. A keeps the estimate's front share, because a share of a near-zero total means nothing.
- **Lap sim with CFD aero** (point mass, `media/results_table.md`): autocross A 66.51, B 61.48, C 60.83, D 60.48 s; fast circuit A 84.12, **B 79.71**, C 82.44, D 84.25 s. Against the estimate, C and D lose 3 to 4 s on the fast circuit (more drag, less downforce), so the moderate wing B is the best there and D only in autocross.
- **Load cases regenerated:** `sim/stress/load_cases.csv` (`matlab/load_cases.m`, variant C downforce). The new CFD ClA made `frame_fe`'s self-test FAIL: braking left a vertical acceleration of 1.41 m/s2, because the old file still had the estimate's downforce. With the file regenerated, all cases balance to 0.1 %. `frame_fe.m` itself was not touched. Stress studies run on the old file used about 10 % more downforce on C.
- MATLAB self-tests **24 of 24 PASS** at the end; `postprocess.py --selftest` PASS.

### 2026-11-17 (evening), bodywork clashes, tube overlaps, suspension corners, Motion and Simulation through the harness

Brief:
1. Fix the bodywork clashes, without changing the wings the CFD session uses.
2. Decide the tube overlaps at the 10 joints.
3. Build the suspension corners and check the geometry.
4. Set up the Motion and Simulation studies through the harness, keeping `rebuild` one command.

The summary and the rules are at the top of this file. Not touched: `cfd/`, `cad/step/cfd/`, `cad/generate/cfd_variants.py`. No commits.

- **Bodies** (`cad/generate/build_parts.py`, checked by `check_clearances.py` and by SolidWorks interference in BuildAssembly):
  - **Nose:** sections are taken from the real frame plus 10 mm. It is open at the front hoop. 12 slots are cut where the front links pass. Each slot is the convex hull of the link's extreme positions (scipy ConvexHull to a polyhedral solid), which took the build from 9.5 min with 240 swept cylinders to 4 s.
  - **Sidepods:** they clear the tubes outboard of |y| 300 by 10 mm, are open inboard and at the bottom, and are 25 mm clear of the rear tyre over travel.
  - **Floor:** raked from the front to the rear ride height, stepped in to |y| 455 from X 1290 for the rear tyre at droop. Strakes hang under the diffuser roof.
  - **Front wing:** its main element leading edge is at `fw_le_x`, the value the CFD session already uses. At the playbook's −600 the flaps ran through the front tyres.
  - Result: interference none (was 290 cm³ in 18 pairs). Clearance check ALL PASS.
- **Trim plan** (`matlab/cad/frame_trims.m`, self-test PASS with S checked against H1+H2+Q):
  - 174 rows at 50 nodes.
  - TrimTubes made 136 trims, 38 needed none, and 22 mitre cuts on its pre- and post-pass. The second run changes nothing.
  - New `tools/sw_harness/Mitre.cs`. The cut plane is built from 3 sketch points with selection marks 0/1/2, because a line-and-point plane was refused. The cut is InsertCutSurface, since a weldment trim with a plane gave error 1.
  - CheckChassis: 444 node pairs. Largest overlap 322 mm³, in 2 pairs above 200 mm³ (was 20 pairs, largest 1135).
- **Suspension** (`BuildSuspension.cs`):
  - The parts are drawn in car coordinates and inserted at the origin.
  - Wishbone pivots and the tie-rod inner end sit on the layout's `HP_` / `HPL_` points; the other joints are point-to-point mates.
  - The pushrod slides through `pushrod_in`: there is no rocker in the params yet.
  - A `Drive_<corner>` distance mate holds the wheel-centre height. The tyre and rim are locked to the hub.
  - 60 mates, 0 errors, left and right mirror within 0.0000°.
  - The sweep runs −30..+30 mm in 5 mm steps.
  - The new tube profile `15.9x0.9` was made by `makeprofile`, a copy of 25.4x1.6 with its two dimensions changed.
- **Motion** (`SuspensionMotion.cs`):
  - Animation study with an oscillating linear motor per upright, on the A_SPIN axis along GROUND. The Drive mates are suppressed in the study only.
  - Found by trial:
    - An oscillating motor moves as A(1 − cos 2πft), so the study starts at full droop.
    - Poses must be read along the timeline in order, after `Stop()`; reads after `Calculate` while it plays, or after big time jumps, were out of order.
    - `ActivateMotionStudy("Model")` returns to the model, so the static pose can be restored.
    - Calibrating A per corner (`ModifyDefinition`) works, but at A ≈ 35 mm the animation stops short at the top on some corners, so one fixed A is used.
  - Run twice (create, then reuse): the same timeline to 0.1 mm.
- **Simulation** (`ChassisStatics.cs`):
  - The add-in is reached through `GetAddInObject("SldWorks.Simulation")`; `cosworks.dll` is not at the documented path, but the object is there.
  - Three static beam studies are made (110 beams, 12,256 elements); the link forces come from six-link statics per upright, with zero residual.
  - The runs end with "No load" (see the top). Solver output is in `sim/stress/results/`; older solver files were moved to `cad/chassis/old/sim_results/`.
- **Rebuild attempts:**
  1. 18:22: stopped at SuspensionMotion. My check assumed a sine motion, and the reads were out of order.
  2. 18:48: stopped at SuspensionAssembly. AddComponent5 refused 2 RL parts; a retry was added.
  3. 19:06: the same step, 5 RL parts refused. OpenDoc6 returned nothing, with no error code, in a SolidWorks that had run several rebuilds (7 GB, 14,700 handles). Fixed with the new first step, `restart-sw`.
  4. 19:25: stopped at SuspensionMotion (sign and stroke checks).
  5. **20:00: all 21 steps PASS in 20 min.** A second SuspensionMotion run on the saved study passes with the same numbers.
- SolidWorks crashed or hung three times in this work:
  - `GetMotionStudyNames` (RPC disconnect);
  - `SetTime` on a deleted study;
  - `SelectByID2("SIMULATION")`.
  
  Each was restarted. Only unsaved throwaway changes were lost, and none of these calls is used any more.
- Docs: `tools/README.md` (steps and outcomes), this log. `.gitignore`: `sim/stress/results/`, `cad/chassis/old/sim_results/`.


## 2026-11-17 (late night), Ring 3/4: rim-limited hardpoints, frame FE, solid cross-check, motion, CFD mismatch list

**Asked:** fit the ball joints to the rim through a hardpoint optimisation, keeping the kinematic targets (15-inch rims only as a fallback); a MATLAB beam FE of the frame, cross-checked on solids in SolidWorks; the bump sweep to the full ±30 mm if simple; the CFD-vs-parts list in a form the CFD session can read.

**Hardpoints** (`matlab/suspension_optimise.m`, new):
- **Method:** `fminsearch` with penalties (no Optimization Toolbox), several starts, rounded to 0.5 mm. 15 design variables per axle: the outer joints, the tie-rod points, the inner pivots' heights and lateral positions, and the pushrod outer height.
- **Hard limits:**
  - outer joints: joint centre plus 12 mm housing inside the barrel (radius 116 mm);
  - links: at least 3 mm from the rim and the tyre (10 mm from the tyre is a soft goal);
  - checked at −30, 0 and +30 mm travel and at full lock both ways.
- **Held:**
  - camber gain within 0.005 deg/mm;
  - bump steer under 0.1°;
  - roll centre within 10 mm;
  - motion ratio within 0.03;
  - caster and KPI bands;
  - the rack travel to full lock;
  - the outer wheel between full Ackermann and parallel steer.
- Written to `params/car_params.txt` through `suspension_geometry.m`. The self-test checks a hand case, flags the old rear upper joint (radius 140), and checks that the new set fits.
- **Frame:** regenerated (`frame_layout`, `frame_trims`, `load_cases`): 50 nodes, 114 tubes, 43.1 kg. The RS1_U pivot drop is limited to keep the cross tube 11 mm from the diff.
- **Bodywork:** `build_parts.py` keeps the sidepod tail's inner face at |y| 334 (it stepped in to 310 and came within 6.5 mm of MH_M–RS1_U).
- **SolidWorks:** the rebuild passes all 21 steps. SuspensionCheck reports joints inside the rim, no clashes over travel, and agreement with MATLAB on camber gain, bump steer, roll centre and motion ratio.

**Frame FE:**
- `matlab/stress/frame_fe.m` (new) and `docs/stress_frame.md`. Results are in the summary above.
- What-if option `extra_tubes` (model only).
- Added to `run_all` (self-tests 24 of 24).

**Solid cross-check:**
- `tools/sw_harness/FrameSolid.cs` (new; `case "framesolid"` in `Program.cs`; not in the rebuild).
- Four runs, all mesh and solve. The joint check finds unjoined tubes every time: around FH_M_R/MH_M_R, then RS1_L, then MH_T.
- `--check-only` shows 356 of 444 node pairs touching and one connected group. `--fuse` unites only 32 of 114 tubes; `--combine` is refused.
- Conclusion: line contact at the coped ends. The result is flagged NOT VALID and the MATLAB result is kept.
- **Harness changes:**
  - `sw_run.py` no longer treats SolidWorks' progress pop-up (the "Title | Description | Button1 …" template) as a question. It stopped the first run after 90 s, mid-solve.
  - FrameSolid gets a 90-minute timeout.
- **Once:** SolidWorks, locked busy on that abandoned run, was ended by process. Nothing unsaved was lost except the throwaway copy.

**Motion:**
- The linear motor is now located at P_WC (SolidWorks takes it), but the reach is unchanged (front +22.7, rear +14.2 mm).
- Left as a WARN with a corrected explanation. Not fixed.

**CFD mismatch:** `docs/cfd_parts_mismatch.md`, `.csv` and `docs/cfd_parts_sections.csv`, from `cad/generate/compare_cfd_parts.py`.

**Checked:**
- rebuild 21 of 21 PASS;
- `run_all('test')` 24 of 24;
- `frame_fe` and `suspension_optimise` self-tests;
- clearance check (all rules pass after the sidepod change).

**Next:**
- Decide on frame floor diagonals (about +50 % torsion for 2.7 kg).
- Then, if wanted, an analysis-only overlapped solid frame for a valid SolidWorks cross-check.
- Check the real ball-joint housing size against the 1 mm rear margin.

## 2026-11-18, Ring 3/4/7: torsion diagonals, rear joint housings, media, README

**Rear joint margin:**
- `params/car_params.txt`: added `joint_housing_radius` 12.5 mm and `joint_rim_margin_min` 3 mm.
  - The housing assumption is an Aurora COM-5T spherical bearing (5/16 in bore, 0.750 in = 19.05 mm OD, motion.com datasheet) in a steel cup with a 3 mm wall.
  - Tie-rod and toe-link ends are taken the same size.
- `suspension_optimise.m` (`package_report`) uses both params. Self-test: 12.5 mm housing, 3 mm wanted, gives margin 3.5 at radius 100 (ok) and 2.5 at radius 101 (flagged).
- **Diff limit bug fixed.** The rear upper-pivot "−14 mm" limit was relative to the current hardpoints, so it drifted on each re-run. The first re-run put RS1_U_cross 6.1 mm from the diff. It is now an absolute penalty, `diff_clearance` (the four rear inner-pivot cross tubes ≥ 11 mm from the diff envelope while optimising), and the result must be ≥ 10 mm to count as feasible.
- **Result** (rear rewritten; the front moved ≤ 0.5 mm in the optimiser, so it was not applied):
  - joint margins: lower 6.3, upper 4.0, pushrod 4.1 mm; the toe-link end now sits inboard of the barrel;
  - camber gain −0.0433 (was −0.0429) deg/mm;
  - bump steer 0.021°;
  - RC 79.4 (was 75.3) mm, span 97 mm;
  - MR 0.773, KPI 10.0°, caster 4.4°, scrub 24 mm, trail 19.6 mm;
  - diff clearance 11.3 mm.
- The rear inner pivots moved outboard: upper to |y| 350, lower to 299.5.
- `BuildSuspension.cs` SuspensionCheck reads the same two params; its rim window counts the housing radius.

**Frame diagonals:**
- `matlab/stress/frame_diagonal_search.m` (new) writes `sim/stress/frame_diagonals.txt`; the results are in `docs/stress_frame.md`.
- 834 → **1503 Nm/deg**, 43.5 → 49.3 kg, ten tubes.
- `frame_layout.m` has a new `'D:'` tube type: one diagonal from a right node to a left node.
- `frame_fe.m` has new options: `torsion_only` (0.1 s per solve, for searches) and `drop_tubes` (name patterns).
- The torsion antisymmetry self-test now runs on the frame without the single diagonals, which make the frame asymmetric on purpose.
- All tube pairs were checked for crossings away from their nodes: none.
- Mass budget: `m_frame` 49.3 at x 838, z 335; `m_brackets_welds` 6.4 (was 5.5, kept at 13 % of the frame). The car is 235.6 kg, 305.6 kg with the driver, 41.8 % front, CG 312 mm.
- Regenerated:
  - `frame_layout`, `frame_trims` (196 trims), `load_cases` (306 kg);
  - `lap_experiments` (media/lap_times.csv, results_table.md);
  - `frame_fe` (report and frame_fe.png);
  - `cornering_balance_study`: R 45 m 112.3 km/h, −8.7 % balance, rear limits.

**Media and README:**
- `matlab/make_media.m` (new) writes:
  - `media/suspension_bump_steer.gif` (109 frames);
  - `frame_stress_cases.png`, `frame_torsion_diagonals.png`, `frame_stress_bump.png`;
  - `mass_table.md`, `lap_time_table.md`.
- `SaveStandardViews` has new options `--show <prefixes>` and `--name <label>`. The rebuild has a 22nd step that saves the suspension views (corners and chassis only, the rest hidden for the pictures and shown again).
- `README.md` was rewritten: project, one-command rebuild, results, assumptions and limits.

**Harness:**
- BuildTubes and CheckChassis compared the mass with a fixed 38 to 46 kg. They now take 0.85 to 1.05 × the CSV mass, because the frame is heavier now.
- `build_parts.py`: the sidepod's open inboard edge now keeps 10 mm from MH_M-RS1_U, which moved outboard with the rear pivots. Before, the gap was 6.7 mm and BuildBodies stopped the second rebuild. The edge is now at |y| 342.

**Checked:**
- `run_all('test')` 26 of 26 PASS, including the two new self-tests.
- Simulink 75 m: 4.3518 s, the same as MATLAB.

**Low-GDI handling (after SolidWorks showed "running critically low on GDI objects" at about 10:00 in rebuild 3; you answered No):**
- `tools/sw_run.py`:
  - **Detection:** the watcher polls every 0.5 s (was 2 s). A dialog whose text contains "low on GDI objects" gets &No clicked (BM_CLICK), is logged with the GDI count, and the step is stopped after 20 s with exit 4.
  - **Retry:** `rebuild` restarts SolidWorks and retries the step once.
  - **Prevention:** `close-all` after each SolidWorks step; `restart-sw` before the layout, suspension, simulation and view groups (6 restarts per rebuild).
  - **Logging:** GetGuiResources (GDI, USER, peak) and the memory of SLDWORKS go on each log line.
- **SaveStandardViews:**
  - Sketches and points are hidden for the pictures (the document's Hide All Types, restored after). Before this, the frame nodes and hardpoints were drawn and pulled the zoom-to-fit.
  - `--keep-sketches` keeps them for the master layout.
- **Rebuild 4, 10:08–10:28:** all 26 steps PASS, no GDI dialog.
  - Peak GDI 5,819 (SuspensionAssembly), BuildAssembly 5,586; other steps 1,100–2,400.
  - SuspensionCheck: the housing rule passes, with the rear margins as above.
  - Assembly: no interference.
  - WARNs: rear lwb/pushrod overlap 7–13 mm³ (new), TrimTubes node overlaps of up to 333 mm³, motion bump reach +22.7/+13.0 mm, ChassisStatics "No load".
- `media/views/unsaved_Default_*.png` are left over from a 2026-11-16 test and are not made by the rebuild. They were left in place.

**Next:**
- A solid-model check of the frame torsion, which needs joints that are bonded properly.
- An anti-roll bar.
- Tyre data, to replace the assumed friction.

## 2026-11-18 (afternoon), Ring 4: valid solid cross-check of the frame torsion

**Asked:** make the SOLIDWORKS Simulation torsion cross-check valid without touching the production CAD, compare it with frame_fe (1503 Nm/deg), and say honestly what it shows.

**Done:**
- `tools/sw_harness/FrameAnalysis.cs` (new; step `FrameAnalysis [sizes] [--overlap mm] [--tag t] [--build-only] [--results]`, long timeout in `sw_run.py`):
  - **Part:** builds `cad/analysis/frame_analysis.SLDPRT` from `frame_nodes.csv`, `frame_tubes.csv` and `frame_trims.csv` as temporary bodies:
    - hollow tubes, coped against their trim boundaries 1 mm into the wall;
    - untrimmed ends run OD/2 past the node;
    - fused (BFS union over shared nodes);
    - 40 mm load cubes imprinted at the 20 loaded nodes;
    - an earlier part is moved to `cad/analysis/old/`, which is git-ignored.
  - **Studies:** "Torsion nodes" and "Torsion links": static, AISI 4130, inertia relief, remote loads (direct, distributed) on the cube faces.
  - **Twist:** from `GetDisplacementForEntities` on the faces at the 16 wishbone nodes.
  - **Peak stress:** from the solver's `.OUT` file, located with one `GetNodeLocation` call.
- `matlab/stress/frame_fe.m`: writes `sim/stress/frame_torsion_loads.csv`, holding both free-free torsion cases as point loads plus the 16 wishbone nodes with their twist pairing, frame_fe's torque, twist and stiffness. `torsion_measures` now keeps F, and the links case keeps its 24 pickup forces. No numbers changed.
- **Docs:**
  - `docs/stress_frame.md`: new last section with the method, the results, the mesh and overlap studies, the checks, and what it says. The Limits bullet and header were updated.
  - `README.md`: the results row, the "assumptions and limits" frame bullet, the layout and media lines.
  - `tools/README.md`: step row, FrameSolid marked superseded, and API lessons.
- **Kept:** the old `FrameSolid` step and its report, as the record of why the weldment cannot be used.

**Results** (`sim/stress/frame_analysis_report.txt` for 4 mm; `frame_analysis_mesh_study.txt` for 5/4/3 mm; `frame_analysis_ov05_report.txt` and `_ov15_report.txt`):
- **Solid model:** one body, 124 tubes, 47.0 kg of steel (−4.6 % against centreline tubes).
- **Links case:** 1509 (5 mm) / **1504 (4 mm)** against 1503 Nm/deg.
- **Nodes case:** 1379 / 1374 against 1386 Nm/deg.
- **3 mm mesh:** error 8 in both studies after about 250 s. Not in `swsStudyMeshError_e` (0–7); not investigated further.
- **Overlap 0.5 / 1.0 / 1.5 mm:** 1379 / 1509 in every case, volume within 0.1 cm³.
- **Joints:** uz spread in each 40 mm cube 0.07–0.17 mm; left/right antisymmetric within 2 %. The front/rear twist split differs from frame_fe by a common rigid rotation of about 0.04°, from the different inertia-relief masses; it cancels in the stiffness.
- **Peak stress:** 162 MPa (nodes) and 668 MPa (links) at 4 mm, both inside a load cube 17 mm from a pickup node. These are load-introduction artefacts, not frame stresses, and are not used.

**Harness lessons** (also in `tools/README.md`):
- **Reading results:**
  - `GetTranslationalDisplacement`'s second argument is a plane, not entities.
  - Reading all 1.9 M nodes kept SolidWorks busy for over 20 minutes; per-face reads take seconds.
  - A failed mesh discards the study's earlier results, which is why the 4 mm studies were solved again.
- **Temporary bodies:**
  - `ImprintingFaces` needs `Face2[]` arrays.
  - Run `Operations2` on copies.
- **Timing:** the 5 mm solves took about 2.5 min each, 4 mm about 3.5 min, with GDI under 2,400.

**Not done:**
- **Stress:** no stress comparison. The solid peaks are at the load patches; a fair one would need bracket-like load introduction.
- **Rebuild:** `FrameAnalysis` is not in `rebuild`. It adds about 12 minutes, and the CSVs it reads come from MATLAB, not from SolidWorks.

**Next:**
- **Physical check:** a torsion test of the real frame, the only check of welds and brackets.
- **Optional mass fix:** if the mass budget should match the solid and the weldment, set `m_frame` to about 47.3 kg. Not changed without your call.


## 2026-11-18 (evening), Ring 5: CFD mesh checks, convergence, wake variant E, bodywork CP

**Done:**
- **`cfd/fluent_halfcar.py`:**
  - force-only stop (`set_convergence`);
  - wake-window boxes (`--boi win`, `--win-size`);
  - `post_run`: wake planes with TKE and vorticity, box planes at 1, 2 and 3 L, y+ per wall, mass imbalance;
  - actions `post` and `cont`;
  - any variant with a faces CSV.
- **`cad/generate/cfd_variants.py`:**
  - variants E and CP, the floor plate, a clearance check, the window boxes;
  - E's tail cut at X 1700, not 1745 (sliver faces against the diffuser broke the surface mesh);
  - CP corner radii `CP_R_NOSE_MIN` 40 mm and `CP_R_POD` 25 mm, for the cell limit.
- **`cfd/postprocess.py`:** joins continuation histories; writes `wake_boxes.csv`, `yplus.csv` and `cfd_checks.csv`; new md sections.
- **Runs:** E, E_w, C_w, C_coarse, C_num, C_bl1, D_bl1, CP.
  - C_curv and D_curv (curvature 24 deg, and 21 deg on C) failed the surface mesh at the wing slots.
  - C_w at 40 mm windows was over the limit (1,055,706); at 50 mm it fits.

**Checked:**
- geometry checks 11 of 11 for E and CP;
- postprocess self-test PASS;
- MATLAB 26 of 26 PASS;
- lap times recomputed by hand for each check run (MATLAB, not written to `media/results_table.md`, because A to D are unchanged).

**Decisions:**
- Sidepods in CP are closed at the bottom, although the parts are open-bottomed. An open 2 mm shell cannot be meshed under the limit; flow inside the pod is not modelled.
- `docs/cfd_parts_mismatch.csv` (the other session's file) is left as it was; CP's comparison is in `docs/cfd_parts_mismatch_CP.csv`.
- E and CP were not put into `params/aero_variants.csv`: neither is force-converged, and the brief did not ask for the lap sim to change.

**Next:**
- If the parts bodywork is final, rerun B and D on it and replace the variant table.
- For a low dirty-air wake, keep the rear wing high and add turbulence low and away from it (ideas in `cfd/variant_E.md`).

## 2026-11-18 (late), Ring 2/4/6: frame mass from the weldment, CP as the as-built aero, regenerated

**Asked:**
- set `m_frame` to the SOLIDWORKS weldment's 47.5 kg, with brackets and welds kept on their own line;
- recompute the frame CG from the CSV tube geometry with the same correction;
- make CFD run CP the as-built aero reference in the lap sim, with B, C and D as the like-for-like comparison;
- regenerate everything downstream, then a full rebuild.

**Frame mass and CG:**
- **New `matlab/cad/frame_trimmed_mass.m`:**
  - **What it does:** cuts each trimmed tube end (from `frame_trims.csv`) back to where its wall leaves the boundary tubes. It samples the wall with 72 lines at the mid-wall radius, each boundary a solid cylinder of its outside radius running away from the node, and takes the mean exit distance.
  - **Self-test:** a square cope on a straight rail against the elliptic-integral hand value, 9.07 mm.
  - **Real frame:** 196 trimmed ends, mean retreat 12.3 mm, largest 48 mm. 46.93 kg at 7850 kg/m³ (49.29 kg on centre-lines), centroid x 840.7, y −0.4, z 335.3 mm (838.2 / 334.8 before).
- **`params/car_params.txt`:**
  - `m_frame` 47.5 (the weldment, 2.4 % above the coped CSV estimate; the weldment uses AISI 1020 at 7900 kg/m³, the CSV 7850);
  - `x_frame` 841, `z_frame` 335 (the coped centroid);
  - `m_brackets_welds` stays 6.4 kg, moved with the frame centroid to x 841.
- **`mass_budget.m` check:** the frame line is now compared with the coped CSV mass and centroid (warns beyond 1.5 kg or 15 mm), not the centre-line sum.
- **CheckChassis:**
  - now writes `cad/chassis/chassis_tube_mass.csv` (volume and centroid per tube);
  - compares the weldment's mass and centre of mass with the budget line (limits 6 % and 10 mm).
- **Finding:** the trimmed weldment is 45.30 kg at x 840.3, z 335.5 mm.
  - The 47.5 kg is BuildTubes' figure, before TrimTubes.
  - Per tube, the trimmed bodies are a median 8 mm shorter than the coped estimate; mean −15 mm, range −163 to +12 mm.
  - **Shortest against the cope:** RT1-RRK_diag, RRK_cross, FS2_L-FH_L_R, SP1_L-SP2_U_L/R, FH_M-FH_T_L/R and FS2_U-FH_M_L.
  - **Cause:** these are shallow joints, where `Mitre.cs` cuts the extension by the mitre plane, which can take tube from inside the cope as well.
  - **Kept at 47.5 kg as asked.** The coped geometry (46.9) and the solid analysis frame (47.0) both agree with it.

**Aero reference:**
- **`params/aero_variants.csv`:**
  - row C restored to run C (it held CP's numbers since this evening's CFD session);
  - new row CP;
  - notes as `postprocess.py` writes them.
- **`read_aero_variants`:** accepts CP and requires it in the repo table.
- **`car_from_params`:**
  - accepts CP and defaults to it;
  - CP falls back to C's row or C's parameter guesses where a table has no CP;
  - the self-test covers all three.
- **CP is now the default in:** `load_cases`, `frame_fe`, `cornering_balance_study` (the report header now names the variant), and the `make_media` lap table.
- **`lap_experiments`:**
  - runs A, B, C, D and CP;
  - uses CP for the sweep, the following-car penalty (CP's own wake from `wake_cfd.csv`, q 0.637) and the sensitivity;
  - the results table has a CP column.
- **`cfd/postprocess.py`:** `TABLE_RUN = {}`, so `--update-variants` maps every row to its own run. This was the only change in `cfd/`; the CFD session had finished.

**Stress:**
- **`frame_fe`:** scales the beam tube masses to `m_frame` (factor 0.9638; the same factor for what-if frames) and reports both masses.
- **Inertia relief:** now finds the case accelerations to 0.1 % (cornering 15.70 against 15.59 m/s² before, when the beams carried 1.8 kg more than the budget).
- **Results:**

  | Case | Peak, MPa | FoS on yield | Before |
  |---|---|---|---|
  | Torsion | 1503 Nm/deg, 197 MPa | — | unchanged |
  | Cornering | 109 | 3.99 | 109 / 3.98 |
  | Braking | 86 | 5.07 | 86 / 5.08 |
  | Bump | 162 | 2.68 | 163 / 2.67 |
  | Corner + brake | 107 | 4.08 | 108 / 4.02 |

- **Diagonal search, rerun (30 min):** same chosen set. Frame 47.50 kg (+5.56).

**Regenerated:**
- `sim/stress/load_cases.csv`, `frame_fe_report.txt`, `frame_torsion_loads.csv`, `frame_diagonals.txt`;
- `media/mass_budget.md` and `.png`, `mass_table.md`, `lap_time_table.md`, `results_table.md`, `lap_times.csv`, `lap_aero_before_after.csv`, `cornering_balance.md` and `_table.csv`;
- the speed, contour and sensitivity figures, and the frame stress figures;
- `README.md` results, lap and diagonal tables;
- `docs/stress_frame.md`.
- **Not regenerated:** the suspension GIF (no mass input) and `cornering_speed_table.csv` (run_all full only, which writes `cfd/results`).

**Before / after numbers:** in the summary at the top.

**Rebuild:** all 26 steps PASS, about 20 minutes, peak GDI 2,338, exit 0. CheckChassis: budget frame line PASS. The warning about three tube pairs overlapping at shared nodes (largest 333 mm³) is as before.

**Next:**
- **Mitre cuts at shallow joints:** check whether the trimmed weldment's tubes (RT1-RRK_diag and the others above) still reach their neighbours. If not, limit the mitre cut to the extension beyond the cope.
- **Brackets and welds:** the 6.4 kg allowance is still a guess (13 % of the centre-line frame). Weigh it once the tabs are drawn.

## 2026-11-19 (night), Ring 2: open tube ends at near-collinear joints, BuildTubes one feature per tube

**Asked:** check whether the trimmed weldment's tubes at shallow joints still reach their neighbours, and fix the CAD if ends float.

**Checks added:**
- **CheckChassis:**
  - every trimmed end (tube, node) of `frame_trims.csv` must touch at least one of its boundary tubes, measured by `ModelDoc2.ClosestDistance` on the bodies, with a face-pair fallback (limit 0.05 mm);
  - writes `cad/chassis/chassis_tube_mass.csv` (volume and centroid per tube);
  - prints the 12 tubes with the least steel left against their centre-line volume;
  - the budget frame-line check from the evening.
- **TrimTubes step 2d:** any end still open after the trims and mitres gets an end-miter `Close_<tube>_<node>`. It is kept only if the result has no error, 124 bodies, a gap of 0.05 mm or less and a mass change under 0.1 kg; otherwise it is deleted.
  - Trim with extension (coped and planar, either tube extended) and end butt 1 and 2 never closed one of these ends, so they are no longer tried.
  - The mass check allows the closing features' mass. Its range is now 0.85 to 1.05 of the CSV mass, as in BuildTubes and CheckChassis (a fixed 38 to 46 kg before).
  - It is not needed since the fix below. It stays as a guard.
- **`sw_run.py`:** TrimTubes gets 3,600 s. One run with seven closing attempts per end hit the 1,800 s limit. Nothing was saved and the chassis was left as it was.

**Finding:** 4 of 196 ends open (table in the summary at the top). Volumes compared on one-feature-per-tube builds:
- **FS2_L:** FS1_L-FS2_L runs to its node, but the near-collinear FS2_L-FH_L was cut back 11.4 mm past the node by the structural member. No trim row cuts it there.
- **RS2_U:** the boundary RS2_L-RS2_U ends at the node, but RS2_U-RT2 (17° off line) was cut back 9.2 mm by the member.
- **Corner treatment was never on.** Every group was built "one group per segment". Inside one structural member feature, SolidWorks still cuts the groups against each other where they meet.
- **Connected-segment option** (`InsertStructuralWeldment5`): 0 is refused; CopedCut lets SolidWorks cope (worst tube 0.68 of its length); SimpleCut without protrusion cuts more. None leaves the joints to the plan.
- **One feature per tube:** every tube 1.000 of its centre-line volume. Hoop and hoop_brace refuse 3 of 12 and 9 of 10 segments as features of their own, with no message; all of them end at FH_T, MH_B or MH_T.

**Changed:**
- `tools/sw_harness/BuildTubes.cs`: `PER_TUBE` groups (sis, bulkhead, sidepod, front, rear) built one feature per tube.
- `tools/sw_harness/TrimTubes.cs`: step 2d, the mass range, the end-gap helpers and the CheckChassis additions.
- `tools/sw_run.py`: the TrimTubes timeout.
- `params/car_params.txt`: comments only, value unchanged. The first m_frame comment was 588 characters, and SolidWorks did not load that line or the six that use it (BuildLayout FAIL, rebuild stopped). Lines of 483 characters load. The comment is now 395 characters, and the `read_car_params` self-test fails on any line over 500.
- `matlab/cad/frame_trimmed_mass.m`: the wall-line search reaches far enough for the shallowest joints (`2.2 R / sin(angle)`, up to 1,500 mm). Result 46.81 kg; largest retreat 93 mm.
- `tools/README.md`: BuildTubes, TrimTubes and CheckChassis rows.

**Checked:**
- **Rebuild:** all 26 steps PASS.
  - BuildTubes 49.8 kg, cut length 49.27 m.
  - TrimTubes 194 trims, 2 not needed, 255 s; the second run changes nothing.
  - CheckChassis ALL PASS, one warning: two tube pairs overlap at MH_T by 333 mm³; the third pair, at MH_L, is gone.
  - ChassisStatics unchanged in kind: the three beam studies are set up and not solved, as before.
  - Views saved.
- **MATLAB:** `run_all('test')` 27 of 27 PASS.
- **Not affected:** `FrameAnalysis` (1504 Nm/deg) builds its solid from the frame CSVs, not from the weldment.
- **Backup:** the chassis before this work is in `cad/chassis/old/` (each `new-chassis` moves the previous file there).

**Next:**
- **m_frame:** 47.5 or the trimmed weldment's 46.7 kg (your call; regeneration as on 2026-11-18).
- **RT1-RRK_diag:** keep the 5.4° gouged joint, move it, or drop it (1476 Nm/deg without it).
- **Brackets and welds:** the 6.4 kg allowance is still a guess.

## 2026-11-25, Ring 2/6: RT1-RRK_diag removed, m_frame set to the trimmed weldment, full regeneration

**Asked:**
- remove RT1-RRK_diag (5.4° joint);
- re-run the diagonal check (does 1476 Nm/deg clear 1500; if not, by how much, and does another diagonal make it up at less cost);
- rebuild, set m_frame to the trimmed weldment mass, regenerate everything once, and report before and after;
- stop if the stiffness drops under 1450 Nm/deg.

**Diagonal check:**
- **`frame_diagonal_search.m`:** new joint-angle rule. A candidate meeting a frame tube (diagonals excluded) at under 10° is dropped, with the reason in the report. `joint_angle` has a hand check in the self-test (30° candidate against a straight rail).
- **Shallowest joint per candidate:**
  - F0 19.1°, F1 32.1°, F3 43.1°, F4 21.6°;
  - T0 22.8°, T1 26.4°, T5 5.4° (dropped), T6 12.3°;
  - B0 36.9°, B1 13.9°, B5 14.4°;
  - P0 19.5°, P1 19.7°.
- **Search result** (836 subsets, `sim/stress/frame_diagonals.txt`):
  - floor + top best 1354 Nm/deg (was 1368);
  - every candidate 1571 Nm/deg;
  - F1 and T1 are still needed in every set;
  - lightest set reaching 1500: F1 T1 F0 F3 F4 T0 T6 B0 P1, 1501 Nm/deg, +5.57 kg, i.e. the built set with T6 (RRK-RT2) in place of T5. Not added.
- **Built set (9 tubes, 7 `_diag` plus the two sidepod tops):** 1476 Nm/deg, −1.6 % against the target, above the 1450 stop.

**Changed:**
- `matlab/cad/frame_layout.m`: the RT1-D:RRK row removed, with the reason. Frame CSVs regenerated: 123 tubes, 48.68 kg centre-line. `frame_trims.csv`: 194 rows.
- `params/car_params.txt`:
  - `m_frame` 46.26 (CheckChassis trimmed weldment);
  - `x_frame` / `z_frame` 832 / 332 (weldment 831.7 / 332.1, coped CSV 833.0 / 333.8);
  - brackets and welds moved with the frame to 832 / 332, still 6.4 kg.
  - All lines are under 500 characters.
- `matlab/make_media.m`: the torsion-family chart no longer counts T5. The lap table's diagonal count and stiffness are computed instead of hard-coded ("10 diagonals", "834 to 1503").
- **Regenerated:**
  - `sim/stress/` (load cases, frame_fe report, diagonals, frame analysis);
  - `media/` (mass budget, lap and results tables, cornering balance, stress and torsion figures, GIF);
  - `README.md` results, variant and diagonal tables;
  - `docs/stress_frame.md`.

**Checked:**
- **Rebuild:** all 26 steps PASS.
  - BuildTubes 123 bodies.
  - TrimTubes 192 trims, 2 not needed; the second run changes nothing.
  - CheckChassis: 46.26 kg; all 194 trimmed ends touch (largest gap 0.000 mm); the MH_T overlap warning is as before.
  - ChassisStatics: studies set up, not solved, as before.
  - Views saved.
- **FrameAnalysis 4:**
  - solid 46.57 kg of steel, 2.90 M nodes;
  - links 1470 against frame_fe 1476 Nm/deg (−0.4 %);
  - nodes 1350 against 1365 (−1.1 %).
- **MATLAB:** `run_all('test')` 27 of 27; afterwards make_media, frame_diagonal_search, read_car_params and mass_budget self-tests PASS. The Simulink model was left as its self-test leaves it (variant C).

**Numbers before and after:** in the summary at the top.

**Next:**
- **1500 Nm/deg:** decided 2026-11-25: the frame stays at 1476 Nm/deg, RRK-RT2 not added.
- **Brackets and welds:** the 6.4 kg allowance is still a guess.

## 2026-11-25, Ring 5: the aerodynamics made visible (pictures, films, smoke tunnel, explore command)

**Brief (user, pasted):** use the existing results only, no new solves. For C (as-built bodywork CP), D, B and A, make:
- surface pressure (top, side, underbody);
- streamlines coloured by speed;
- vorticity iso-surfaces;
- wake slices at 1, 2 and 3 car lengths (deficit and TKE);
- the symmetry-plane field.

Also wanted: common colour scales; MP4 and GIF films (orbit, wake sweep, build-up); an A-B-C-D side by side; one regenerate command and one explore command; a smoke tunnel for C, D and A plus an A-B-D side by side; captions on everything; every image checked; no commits.

**Interpretations (mine):**
- **Rendering engine.** The brief says "PyFluent or the Ansys post-processing that works on this install", and allows PyVista or ParaView for the smoke.
  - I rendered everything with PyVista. It reads the Fluent `.cas.h5`/`.dat.h5` directly with VTK 9.7's `vtkFLUENTCFFReader`, so no Fluent licence is needed.
  - Reason: identical cameras, colour scales, captions and frame-by-frame films for four variants are scriptable and repeatable there.
  - CFD-Post (which works here) is used for the explore command.
  - The two readers were cross-checked at 8 points (below).
- **Location.** Output goes to `media/cfd/vis/`, a subfolder of the `media/cfd/` the brief named.
- **Variant C** is run CP, labelled as such in every picture. A, B and D have the older CFD bodywork.
- **"Side by side" for the smoke** is three rows one above the other, so the 11 m long wakes line up and stay readable.

**Installed** (pip, into `.venv`, now in `cfd/requirements.txt`):
- pyvista 0.49.3, vtk 9.7.2, imageio 2.38.2, imageio-ffmpeg 0.8.1 (brings its own ffmpeg), pillow 13.0.0;
- pulled in by them: scooby, pooch, rich, cyclopts and small helpers.

**How it works:**
- **`visualise.py export`** reads each case and data file once and writes `cfd/cases/vis/<run>/` (git-ignored, about 260 MB per run, about 2 min for all four in parallel). It holds:
  - the car and wheel surface, with the values of the wall-adjacent cell (first prism layer);
  - two resampled grids, from cell values averaged to the nodes:
    - 12.5 mm around the car: X −1.3..3.4, Y 0..0.95, Z 0..1.8 m;
    - 30 mm to 3.2 car lengths: X −1.3..11.2, Y 0..1.6, Z 0..2.8 m;
  - zero velocity inside solids, a validity mask, and vorticity and Q from the grids.
- **Common scales:**

  | Quantity | Range | Colours |
  |---|---|---|
  | Cp | −3..+1 | white at 0 |
  | speed/U | 0..1.4 | turbo |
  | deficit 1 − u/U | 0..0.6 | magma |
  | k | 0..8 m²/s² | viridis |
  | ωx | ±200 1/s | coolwarm |

- **Wake slices** sit at X 4.50, 7.45 and 10.40 m (rear axle + n × 2.95 m), with the following car's low and high windows of `wake_boxes.csv` drawn on.
- **Streamlines** (216 per half car, mirrored) are traced on the fine grid and continued on the wake grid from where they leave it.
- **Vortices** are Q iso-surfaces: 4000 1/s² on the fine grid and 667 on the wake grid, blanked within 2 cells of a wall (otherwise the zero velocity inside the car makes false sheets).
- **Smoke:**
  - 100 seeds per half car: a 7 × 9 grid 1.25 m ahead of the car, plus 37 next to the front-wing tips, the front and rear wheels, the rear-wing endplates and under the floor (positions measured from the car surfaces).
  - Particles are released every 0.02 s with a random phase per seed (mirror pairs equal). Each is moved along its streamline by integration time and drawn as a 0.009 s streak coloured by speed.
  - 1.6 s of flow in 18 s of film (11 times slower).
- **Forces by part** (comparison) come from Fluent's `forces.out` (mean of the last 200 iterations, × 2 for the full car). Columns are found by header name, because A has no wing columns.

**Output, `media/cfd/vis/` (55 files, 111 MB):**

| Files | What | Size |
|---|---|---|
| `A_surface_cp`, `_streamlines`, `_vortices`, `_wake_slices`, `_symmetry` .png | stills of A | 2.3 MB |
| `A_orbit` .mp4 / .gif | orbit around the streamlines, 10 s | 4.9 / 3.5 MB |
| `A_sweep` .mp4 / .gif | wake slice from the rear wing to 3 L, 6 s | 0.1 / 1.2 MB |
| `A_buildup` .mp4 / .gif | streamlines appearing front to back, 8.5 s | 0.1 / 1.6 MB |
| `B_surface_cp`, `_streamlines`, `_vortices`, `_wake_slices`, `_symmetry` .png | stills of B | 3.5 MB |
| `B_orbit` .mp4 / .gif | orbit around the streamlines, 10 s | 5.5 / 3.9 MB |
| `B_sweep` .mp4 / .gif | wake slice from the rear wing to 3 L, 6 s | 0.2 / 1.6 MB |
| `B_buildup` .mp4 / .gif | streamlines appearing front to back, 8.5 s | 0.2 / 1.7 MB |
| `C_surface_cp`, `_streamlines`, `_vortices`, `_wake_slices`, `_symmetry` .png | stills of C | 3.7 MB |
| `C_orbit` .mp4 / .gif | orbit around the streamlines, 10 s | 5.7 / 4.0 MB |
| `C_sweep` .mp4 / .gif | wake slice from the rear wing to 3 L, 6 s | 0.2 / 1.7 MB |
| `C_buildup` .mp4 / .gif | streamlines appearing front to back, 8.5 s | 0.2 / 1.7 MB |
| `D_surface_cp`, `_streamlines`, `_vortices`, `_wake_slices`, `_symmetry` .png | stills of D | 3.7 MB |
| `D_orbit` .mp4 / .gif | orbit around the streamlines, 10 s | 6.0 / 4.1 MB |
| `D_sweep` .mp4 / .gif | wake slice from the rear wing to 3 L, 6 s | 0.2 / 1.7 MB |
| `D_buildup` .mp4 / .gif | streamlines appearing front to back, 8.5 s | 0.2 / 1.6 MB |
| `compare_ABCD` .png / .mp4 / .gif | A-B-C-D: underbody and top Cp, downforce by part, wake at 1 L; film with the wake slice moving back | 2.0 / 0.5 / 5.1 MB |
| `smoke_C` .mp4 / .gif | smoke tunnel C, camera swinging front to rear three-quarter, 18 s | 6.1 / 3.6 MB |
| `smoke_D` .mp4 / .gif | smoke tunnel D, 18 s | 6.1 / 3.6 MB |
| `smoke_A` .mp4 / .gif | smoke tunnel A, 18 s | 3.5 / 3.3 MB |
| `smoke_ABD` .mp4 / .gif | smoke tunnel A, B, D in rows, same seeds, camera and time, 18 s | 7.2 / 4.8 MB |

**Checks:**
- **Self-test:** `visualise.py --selftest` 9 of 9 PASS:
  - Cp of −480 Pa = −2;
  - slices at 4.50 and 10.40 m;
  - ωx of a 3 rad/s solid-body rotation = 6;
  - smoke particles on a straight 20 m/s line: released at 0, 0.25 and 0.5 s, at t = 0.6 s their heads are at X 2, 7 and 12 m, and a 0.05 s tail is 1 m long.
  - My first hand value said 2 particles; I had forgotten the release at 0.5 s. The code was right and the test was corrected.
- **Hand sum:** downforce by part adds up to Fluent's total in all four runs. A −7 N, B 823, CP 934 (= ClA 3.892 × 240 Pa), D 1008 N.
- **Cross-check against CFD-Post** (Ansys's own reader and interpolation, run CP), u and k at 8 points:
  - wake points within 0.04 m/s and 0.05 m²/s²;
  - near the car within 0.2 m/s;
  - except in the 20 mm floor gap (X 1.0, Z 0.02 m), where the 12.5 mm grid gives 11.50 against 11.00 m/s (+4.5 %).
  - The underbody speeds in the pictures are therefore a little smoothed.
- **Looked at, every one:**
  - all 20 stills;
  - frame sheets of every film (6 frames of each C film; 4 of each other film, of the comparison video, of the 4 smoke films);
  - the CFD-Post check pictures for C and A.
- **Found and fixed while looking:**
  - Cp colours all pink (white was at −1);
  - clipped colour-bar labels;
  - one colour bar per wake row;
  - fake Q sheets on walls;
  - near grid too low for the rear wing (re-exported to Z 1.8 m);
  - diffuser vortices hidden (low view added);
  - smoke too dense at first (326 streaks every 16 cm became a solid blanket);
  - side-by-side camera cutting the front wings and the upwash;
  - comparison crashed on A (no wing columns);
  - white margins in the first sweep frames (near grid only; now the wake grid underneath);
  - comparison title descenders clipped;
  - orbit film 28 MB (CRF encoding now, 5 to 6 MB).
- **Full regeneration:** `visualise.py all` run end to end at the finish: exit 0, about 8 min (474 s measured) with no errors in the log.

**What the pictures show** (pictures of existing results; the heights below were measured on the 30 mm grid for this entry):
- **Upwash.** Behind B, C and D the wake rises, the reaction to the downforce.
  - Deficit-weighted centre height of the wake (half plane, deficit > 0.15):

    | Variant | at 1 L | at 3 L |
    |---|---|---|
    | A | 0.25 m | 0.26 m |
    | B | 1.02 m | 2.56 m (near the grid top at 2.8 m, may be cut) |
    | C | 1.23 m | 2.16 m |
    | D | 1.30 m | 2.02 m |

  - A's wake stays at the ground and flat.
- **Following car's rear-wing window at 1 L** (`wake_boxes.csv`):
  - CP has the most TKE: 5.9 m²/s² against 4.6 for D and 2.1 for B. In the pictures this shows as one lobe on each side, from the rear-wing tip vortices.
  - D has the largest deficit: 0.34 against 0.32 for CP. Its core sits higher, with its peak at Z 1.38 m against 1.17 m for C.
- **Vortex pairs.**
  - B, C and D: each sheds a rear-wing tip vortex pair that runs to the end of the wake grid, and front-wing tip and wheel vortices along the sidepods.
  - A: only weak wheel and floor-edge vortices.
- **Under the floor.** The air leaving the floor and diffuser is the slowest stream (blue in the smoke films), low behind the car.
- **Body lift.** The body makes about 80 to 100 N of lift in every variant. The wings carry the downforce: front 466 N, rear 492 N, floor 96 N in CP.

**Caveats:**
- Steady RANS (k-omega SST) on a Student mesh of about 1 M cells. The films show time-averaged streamlines, not unsteady turbulence (CP and E are themselves unsteady, mean good to about 1 %).
- Surface Cp is the first-cell value; the 3D fields are resampled (see the cross-check above).
- The Q levels differ between the two grids, so the pictures show where vortices are, not how strong.
- Only the ranking of the variants is trustworthy. Every picture says so.

**Explore command** (`cfd/explore.py`):
- **CFD-Post (default):** the session file was tested in CFD-Post batch (`--test`) for C and A; the pictures were checked. I did not open the CFD-Post window itself on your screen; it uses the same session file with `-session` instead of `-batch`.
- **Fluent (`--fluent`):** tested without a window. It reads D's case and data and defines `car_cp`, `symmetry_speed` and `pathlines`.
  - The first launch attempt failed with `LaunchFluentError` and left no process; the retry worked.
  - In the window, open the other graphics objects from the tree.

**Not done / next:**
- **Films git-ignored** (user's choice after this entry): `.gitignore` now has `media/cfd/vis/*.mp4` and `*.gif`. Only the 21 PNGs (15 MB) go into git.
- **The explore windows** have not been opened on screen by me (see above).

## 2026-11-25 (CFD session), Ring 5: B and D re-solved on the as-built bodywork (B_AB, D_AB)

**Reading taken (user away, no questions):**
- **B_AB and D_AB** = variant B's and D's complete aero packages on CP's as-built bodywork, which is the same hull, sidepods, 10 mm floor plate, wheels and corner radii as CP.
  - Each package keeps its own wing angles.
  - D also keeps its endplate fins, beam wing and 14° diffuser.
  - B has no diffuser, because that is how variant B is defined.
  - Built by `cad/generate/cfd_variants.py` with `{"base": "B"/"D", "body": "parts"}`, exactly as CP is `{"base": "C", "body": "parts"}`.
- **Why B keeps "no diffuser":** taking "only wing settings" literally would give B C's diffuser. Then B_AB would no longer be variant B, and the old-B to B_AB comparison would mix bodywork with a diffuser change.
- **Solver and mesh:** the same command as CP, `cfd/fluent_halfcar.py all <V>` with the defaults: scale 2.0, the same sizes, 2 prism layers, k-omega SST, 20 m/s, moving ground, rotating wheels, the force-based stop and a 1200-iteration cap.
- **Cell budget:** B_AB should fit (estimate CP + (B − C) ≈ 0.95 M). D_AB may not (estimate ≈ 1.09 M); if not, see the steps below.

**Progress:**
- **Step 1 (geometry), done:** `cfd_variants.py --only B_AB,D_AB` built both variants; 19 of 19 checks passed (new entries in `VARIANT_DEFS`).
- **Step 2 (meshes), BLOCKED, first attempt failed for both:**
  - **D_AB:** Fluent Meshing failed with "Breakout detected" and 360 self-intersections; no cells were made (`cfd/cases/mesh_D_AB.log`).
    - Its sliver faces are the same ones that meshed fine in old D and CP.
    - Suspect: D's 14° diffuser on CP's 10 mm floor plate (CP has 12°, old D had the floor block).
    - A test copy with a 12° diffuser (`DX12`) is built in the session scratchpad, not in the repo. It has not been meshed yet.
  - **B_AB:** "The surface meshing was not successful" (`cfd/cases/all_B_AB.log`). Not diagnosed yet.
  - Under the job's rule, each variant has one failure so far. A second failure for the same reason stops that variant.
- **Prepared, not yet run:**
  - `cfd/postprocess.py`: rows B and D will come from runs B_AB and D_AB (`TABLE_RUN`) and get an as-built note.
  - `params/aero_variants_simplified_BD.csv`: the old B and D rows, saved.
  - `matlab/lapsim/lap_experiments.m`: new section 6 for B, D, CP, old B and old D. It covers point-mass and four-wheel lap times on skidpad, autocross and the fast circuit, and the following-car penalty from each variant's own wake.
  - `cfd/fluent_halfcar.py`: optional `CFD_GEO_DIR` and `CFD_RESULTS_DIR` overrides for test meshes. Without them nothing changes.
- **Not done:** solves, checks, comparison, `aero_variants.csv` update, lap-sim run, docs, tests and pictures. The session stopped at the usage limit.

### 2026-11-25 (resumed): B_AB and D_AB meshing fixes

**Reading taken:** the user's resume brief.
- Fixes must keep each wing package exactly as defined. Topology-only or junction changes come first; a smaller D diffuser angle is the last resort and would be named in every table and caption.
- Test copies live in the session scratchpad (`CFD_GEO_DIR` / `CFD_RESULTS_DIR`).
- At most 3 more fix attempts per variant.

**B_AB:**
- **Attempt 1 (cause):** CAD tessellation "Breakout detected", then "Failed to project front-edges onto face (1985.7, 0, 1210) mm": B's rear wing section on the symmetry plane, 0.2 m above the body.
  - B's rear wing faces are identical to old B's (which meshed). The refinement-box files differ only in their STEP header lines.
  - What changed is the one-piece symmetry face, which now carries CP's hull section as well. The same fragility is documented for C and old D ("rear flap on Y = 0").
- **Fix (attempt 2):** `split_symmetry_face` in `cfd_variants.py`, with `VARIANT_DEFS["B_AB"]["sym_split_x"] = [2600]`.
  - A line at X 2600 mm splits the symmetry face. That is behind the car (car ends at X 2320) and crosses nothing.
  - Topology only: same plane, same holes, same zone name; the wetted-area and zone checks pass (11 of 11).
- **B_AB attempt 2 (symmetry face split at X 2600):** failed, same error at the same point (log `cfd/cases/all_B_AB_try2.log`). The split is removed from B_AB's definition; the function `split_symmetry_face` stays, unused.
- **Diagnosis:** old B's own geometry, re-meshed today as scratch copy BX with the current driver, meshes at exactly 900,187 cells, as on 2026-11-17. So the failure comes from B's rear wing combined with CP's bodywork, not from the driver. The failing face is the leading edge of B's top flap (face 50) at Y = 0.
- **B_AB attempt 3:** `imprint_rw_y` cuts the rear-wing faces along Y = 40 mm (`rw_imprint_y`). Topology only: 3 wing faces and 1 body face split, surface unchanged, 11 of 11 checks pass.

**D_AB:**
- **Diagnosis:** the scratch copy DX12 (D_AB with a 12° diffuser) meshes, so the 14° roof is the cause. At 14° the hull's rounded bottom corner grazes the roof top: hull 99.7 mm against roof 99.4 mm at Y 200, X 1700. At 12° the gap there is 5.8 mm.
- **Cell budget:** DX12 has 1,100,486 cells, 52k over the limit.
  - D's fins and beam wing add 16k rear-wing faces to CP's finer body; old D was on a body with 7.5k fewer faces.
  - No D-only simplification removes about 11k faces without changing D's package.
- **D_AB attempt 2:**
  - **Junction fix (option a):** `hull_tail_fill` (`hull_fill_z = 150`). The hull outline at Z 150 is carried straight down onto the diffuser roof, from the rear axle (X 1550) to the body end (X 1900).
    - It fills only the closed pocket between the roof top and the hull bottom.
    - D's wings, fins, beam wing and 14° diffuser underside are unchanged; 11 of 11 checks pass.
  - **Cell budget:** one prism layer (`--set bl_layers=1`) instead of CP's two. Solver settings are unchanged.
    - Measured cost of this change on the old bodywork: D_bl1 against D gave ClA −0.2 %, CdA −1.0 %, front share 0.38 to 0.40; C_bl1 against C gave ClA +0.3 %, CdA −1.8 %.
    - To be fair to the comparison, CP is also re-solved with one layer (CP_bl1), so D_AB has a like-for-like partner.
- **D_AB attempt 2 result:** the self-intersections are gone (the hull fill works). The surface mesh then failed to project edges at two other spots (`cfd/cases/all_D_AB_try2.log`):
  - the beam wing's leading edge at Y = 0 (1695, 0, 595 mm);
  - the rear wing at the endplate plane (2040, 625, 1249 mm).
  This is the same wing-meets-plane fragility as B_AB, and it is next to be fixed.
- **B_AB attempt 3 result:** failed, same error at the same point (`cfd/cases/all_B_AB_try3.log`). `rw_imprint_y` is removed from B_AB's definition; the function stays, unused.
- **B_AB attempt 4 (last):** `split_symmetry_face_z` (`sym_split_z = 1050`). A line at Z 1050 mm, from inlet to outlet, splits the symmetry face between the body's top at Y = 0 (990 mm) and B's rear wing at Y = 0 (from 1107 mm). The wing sections now sit on their own symmetry face, apart from CP's hull section. Topology only; 11 of 11 checks pass.
- **B_AB attempt 4 result: meshed and solved** (`cfd/cases/all_B_AB.log`):
  - 953,238 cells, under the 1,048,576 limit. CP's sizes, 2 prism layers, CP's solver settings, 1200 iterations.
  - Force-converged by the project rule: drift 0.02 / 0.01 %, band 1.93 / 1.10 % (downforce / drag; the limit is 2 %).
  - Mass imbalance 2.0e-06 of the inlet flow.
  - y+ area averages 72 (front wing) to 126 (rear wheels); max 394 (body), min under 1 at sharp edges and stagnation points. Same range as CP.
  - Hand check of `forces.out` (mean of the last 200 iterations, times 2): parts sum to the total (806.6 N against 806.6 N, drag 317.6 N against 317.6 N). ClA × q = 3.361 × 240 Pa = 806.6 N, which matches.
  - ClA 3.36, CdA 1.32, front share 0.43. Old B: 3.43 / 1.29 / 0.45. Steady RANS on a Student mesh: only the ranking is trustworthy.

**D_AB attempt 3:** same cause as B_AB (wing sections sharing the one-piece symmetry face with CP's hull section), so the same fix: `sym_split_z = 1050`, on top of the hull fill and 1 prism layer.
- The beam wing at Y = 0 (Z 587 to 640) stays on the lower face with the hull, 7 mm above the hull top at X 1690. Old D had the same 7 mm gap and meshed, so the gap alone is not the cause.
- The rear wing sections (Z 1117 to 1539) go on the upper face.
- **D_AB attempt 3 result:** failed (`cfd/cases/all_D_AB_try3.log`). The two projection failures are the same, at the same coordinates (beam wing at Y = 0; rear wing at the endplate plane, Y = 625), plus a changing third one ("Front could not be closed" near the front wheel). Splitting the symmetry face does not reach them, and the Y = 625 one is not on the symmetry plane. The `sym_split_z` is removed from D_AB.
- **Fix-preference (a) is exhausted** (two junction/topology fixes tried). Per the brief, **attempt 4 (last) is fallback (b): D_AB with a 12° diffuser instead of D's 14°.**
  - The only geometry change is the diffuser angle. The wings, beam wing and fins are D's, with no hull fill.
  - The scratch copy DX12 (the same geometry) already passed the surface and volume mesh today, at 1,100,486 cells with 2 layers.
  - With 1 prism layer it should be about 1.0 M cells: old D_bl1 had 93k fewer cells than D.
  - Every table, README text and caption must then say: **D's diffuser is 12° in D_AB, not 14°**.
- **D_AB attempt 4 result: meshed and solved** (`cfd/cases/all_D_AB.log`). **D's diffuser is 12° in D_AB, not 14°.**
  - 1,002,218 cells with 1 prism layer, under the limit. CP's other sizes and CP's solver settings, 1200 iterations.
  - Force-converged: drift 0.00 / 0.01 %, band 1.04 / 0.25 %.
  - Mass imbalance 8.4e-07 of the inlet flow.
  - y+ area averages 76 (rear wing) to 147 (front wheels); max 386 (body), min 0.2 at edges. Averages run higher than B_AB because there is only 1 layer.
  - Hand check: parts sum to the total (966.9 N, drag 422.4 N). ClA × q = 4.029 × 240 = 966.9 N, which matches.
  - ClA 4.03, CdA 1.76, front share 0.39. Old D: 4.20 / 1.77 / 0.38. Only the ranking is trustworthy.
  - The 14° attempts (hull fill; hull fill plus symmetry split) stay in the code as options, unused.
- **CP_bl1** (CP with 1 prism layer, `--tag _bl1`): running, as D_AB's like-for-like partner.

### 2026-11-25 (resumed): steps 5 and 6
- **Variant table:** `postprocess.py --update-variants` was run.
  - `params/aero_variants.csv` rows B and D are now B_AB (3.361 / 1.323 / 0.426) and D_AB (4.029 / 1.760 / 0.387). The note on the D row says the diffuser is 12°, not 14°, and that D_AB has 1 prism layer (`RUN_NOTE`).
  - CP stays the default and is unchanged (3.892 / 1.661 / 0.433). It is still marked not force-converged (band 2.46 %), as before.
- **Lap sim section 6** (`lap_experiments.m`) ran for the first time. It writes `media/lap_as_built_BD.csv` and a section in `media/results_table.md`.
- **Hand check:** D's skidpad lap of 4.8862 s.
  - The point-mass car holds a steady circle where the rear axle's grip left after cornering just covers drag and rolling resistance:
    - mu = 1.4 (750 / (Fz / 4))^0.1;
    - Fz = m g + 0.5 rho ClA v²;
    - sqrt(Fmax² − (m v² / R)²) × rear share = 0.5 rho CdA v² + crr Fz;
    - m 302.56 kg, R 9.125 m, ClA 4.029, CdA 1.760, front weight 0.418, front aero 0.387, crr 0.015.
  - Bisection gives v = 11.7339 m/s, so 57.334 / 11.7339 = 4.8862 s. The lap sim gives 4.8862 s.
  - Without the drag term the hand speed would be 11.751 m/s (4.879 s), so the drag-and-traction coupling is worth 0.15 %.
- **Tests:** MATLAB `run_all('test')` passes 27 of 27; `postprocess.py --selftest` passes; `visualise.py --selftest` passes.
- **Docs:** README (variant table, new section "B, D and CP on the same as-built bodywork", aero assumption), `cfd/README.md`, `cfd/geometry_notes.md`, and the header of `media/cfd/cfd_results.md` (from `postprocess.py`).
- **Step 7 started:**
  - The old B and D stills and films, `compare_ABCD.*`, `smoke_D.*` and `smoke_ABD.*` (all of which show old B or D) are moved to `media/cfd/vis_old_simplified/`, which is git-ignored. The tracked PNGs therefore show as deleted in git until the new ones are written.
  - `visualise.py` maps B to run B_AB and D to run D_AB. Every caption now starts with "B, C and D are on the same as-built bodywork (D's diffuser is 12 degrees here, not 14); A is on the older CFD bodywork."
- **Step 7 done:** `visualise.py all` ran in 681 s (`cfd/cases/vis_all_AB.log`) and wrote 55 files to `media/cfd/vis/`.
  - Every MP4 is under 10 MB; the largest are smoke_ABD at 7.2 MB and smoke_C / smoke_D at 6.2 MB. No re-encode was needed.
  - All 20 stills and `compare_ABCD.png` were checked by eye, plus a 5-frame sheet of every one of the 16 films. All show the right run label ("run B_AB", "run D_AB, diffuser 12° not 14°"), the bodywork caption, and no blank or broken frames.
- **CP_bl1:** CP with 1 prism layer. The tag was given as `_bl1` and came out as `CP__bl1`; all its files were renamed to CP_bl1 like C_bl1 and D_bl1, and the first copy of the run folder (identical) was moved to the session scratchpad, not deleted.
  - 918,527 cells, force-converged (band 0.62 / 0.13 %), mass imbalance 4.3e-07.
  - Hand check: parts 954.4 N = total; ClA × q = 3.977 × 240 = 954.4 N.
  - ClA 3.98, CdA 1.67, front 0.43: +2.2 % ClA and +0.4 % CdA against CP. The C and D layer checks moved ClA by under 0.3 %, but CP is unsteady (its own band is 2.5 %), so most of this difference is likely CP's unsteadiness, not the layer count.
  - Lap sim with CP_bl1's aero: skidpad 4.889 s, autocross 60.99 s, fast circuit 82.98 s (point-mass).
- **Like for like with 1 layer, D_AB against CP_bl1:** ClA +1.3 %, CdA +5.6 %, autocross −0.09 s, fast circuit +1.28 s. The downforce gain is inside CP's own unsteadiness.
- **Not done / not checked:** see the final answer of this session.
