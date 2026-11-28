# README statements made stale by FINAL as the default car (2026-11-28)

Since 2026-11-28 the default car is **FINAL** (`default_car()`: CP's bodywork and wings with the F rear and J front wing supports, aero row FINAL from CFD run FINAL_bl1), at the reconciled CG of `params/car_params.txt`: 302.56 kg (unchanged), CG with driver x 894.9 mm, z 319.9 mm, 42.26 % front (was 901.5 / 308.9 mm, 41.84 %). The lap sim, cornering balance, load cases, frame stress, accel, Simulink and lap films were re-run. The README text was **not** rewritten; this list is for that job.

Line numbers are those of `README.md` as committed in aa026147. "New" values are FINAL at the new CG unless the line says otherwise. Sources: `media/final_car_comparison.md` (old vs new, with the aero and CG effects separated and the noise bands), `media/lap_time_table.md`, `media/results_table.md`, `media/lap_as_built_BD.csv`, `media/cornering_balance.md`, `media/support_sensitivity.md`, `sim/stress/frame_fe_report.txt`, `media/showcase/lap_video_report.txt`.

**FINAL is a 1-prism-layer run (FINAL_bl1)**, so wherever the README sets FINAL beside CP, the fair aero reference is CP_bl1 (ClA 3.977, CdA 1.667, front 0.431), not the 2-layer CP row (3.892 / 1.661 / 0.433). The README's "old" values are CP's row at the v1.0.0 CG (311.3 mm); the comparison's "old" column is CP's row at the pre-reconciliation CG (308.9 mm). They differ by at most 0.01 s in lap time and 0.03 in the lowest factor of safety (2.62 vs 2.65).

## Results table and headline numbers

| Line | Statement | Old value | New value |
|---|---|---|---|
| 49 | `run_all('test')` comment | 27 self-tests | 29 self-tests (30 with the Simulink one; `default_car` and `final_car_comparison` added) |
| 56 | "as of" date of the results | 2026-11-25 | 2026-11-28 for the lap, balance, load, stress, accel and following rows |
| 60 | Mass row, last sentence | "The lap times and loads in this README were computed with the v1.0.0 CG and not re-run" | re-run on 2026-11-28 at the reconciled CG with FINAL (sentence to drop or reword) |
| 63 | Frame, lowest factor of safety | 2.62, bump case | 2.67, bump case (163 MPa, RRK-RT1_L). The bump case has no aero, so this is the CG effect only (+0.02 against 2.65 at the old CG) |
| 69 | Aero row: car and values | CP: ClA 3.89, CdA 1.66, L/D 2.34, 43 % front | FINAL (run FINAL_bl1, 1 layer): ClA 4.13, CdA 1.68, L/D 2.45, 40 % front (0.397). Against CP_bl1: ClA +3.9 % (beyond the 2.2 % spread), CdA +1.0 % (inside), front share -3.4 points (beyond) |
| 70 | Autocross, "as built (CP)" | 61.12 s point-mass, 62.12 s four-wheel | FINAL: 60.75 s point-mass, 61.46 s four-wheel |
| 71 | Fast circuit, "as built (CP)" | 82.97 s / 83.08 s | FINAL: 83.14 s / 83.16 s (slower than CP_bl1 by +0.15 / +0.09 s, inside the 0.51 s band: not claimed) |
| 72 | Wings worth A to C, autocross / fast circuit | 5.60 s / 1.63 s | 5.61 s / 1.63 s (A and C at the new CG) |
| 73 | Skidpad / 75 m / 0-100, "as built (CP)" | 4.89 s / 4.35 s; 3.47 s | FINAL: 4.88 s / 4.35 s; 0-100 km/h 3.46 s (`accel_test`: 75 m 4.348 s) |
| 74 | Simulink 75 m vs MATLAB (CP) | 4.3499 s vs 4.3499 s | FINAL: 4.3476 s vs 4.3476 s (difference -0.00 %) |
| 75 | Following one car length (CP) | 64 % (CP's wake); +2.14 s autocross, +1.21 s fast circuit | FINAL's own wake (run FINAL_bl1): 66 % (q-ratio 0.661); +2.14 s autocross, +1.15 s fast circuit |
| 76 | Cornering balance at 45 m (CP) | 112.9 km/h, rear axle at its limit first, balance -6.5 %; neutral at 39 % front aero against the 43 % CP has | FINAL: 117.4 km/h, **front axle at its limit first**, balance +0.6 % (nearly neutral); neutral at 40.0 % front aero against the 39.7 % FINAL has |

## Lap times, aero variants (lines 80-93)

The CG change moves every variant slightly (A to D included); FINAL is a new column.

| Line | Statement | Old value | New value |
|---|---|---|---|
| 82 | "CP is the car as built ... the reference everywhere else in the repo (load cases, stress cases, cornering balance, sensitivity)" | CP | FINAL is the car and the reference (`default_car()`); CP stays available by name as the comparison car |
| 86 | Table header | last column "**CP as built**" | add "**FINAL (the car)**"; CP becomes "CP (2-layer row)" |
| 88 | skidpad A / B / C / D / CP | 5.12 / 4.92 / 4.89 / 4.89 / 4.89 s | 5.12 / 4.92 / 4.89 / 4.89 / 4.89 s; FINAL 4.88 s |
| 89 | accel 75 m | 4.41 / 4.34 / 4.35 / 4.34 / 4.35 s | 4.43 / 4.35 / 4.36 / 4.36 / 4.36 s; FINAL 4.35 s |
| 90 | autocross | 66.59 / 61.72 / 60.99 / 60.90 / 61.12 s | 66.64 / 61.76 / 61.03 / 60.94 / 61.16 s; FINAL 60.75 s |
| 91 | fast circuit | 84.15 / 79.90 / 82.52 / 84.26 / 82.97 s | 84.15 / 79.90 / 82.52 / 84.26 / 82.97 s; FINAL 83.14 s |
| 93 | SOLIDWORKS bodywork cost against C | 0.13 s autocross, 0.45 s fast circuit | unchanged (0.13 / 0.45 s) |

## B, D and CP on the same bodywork (lines 95-119)

| Line | Statement | Old value | New value |
|---|---|---|---|
| 95 | Heading | B, D and CP | B, D, CP, CP_bl1 and FINAL (the table in `media/results_table.md` now has CP_bl1 and FINAL columns) |
| 104 | Skidpad / autocross / fast circuit: B, D, CP, B old, D old | 4.92 / 61.72 / 79.90; 4.89 / 60.90 / 84.26; 4.89 / 61.12 / 82.97; 4.92 / 61.64 / 79.79; 4.88 / 60.65 / 84.31 | 4.92 / 61.76 / 79.90; 4.89 / 60.94 / 84.26; 4.89 / 61.16 / 82.97; 4.92 / 61.68 / 79.79; 4.88 / 60.68 / 84.31. New: CP_bl1 4.89 / 61.04 / 82.99; FINAL 4.88 / 60.75 / 83.14 |
| 105 | Following penalty, autocross / fast circuit: B, D, CP, B old, D old | +1.69 / +1.14; +2.14 / +1.14; +2.14 / +1.21; +1.80 / +1.22; +2.21 / +1.09 | +1.70 / +1.14; +2.15 / +1.14; +2.15 / +1.21; +1.81 / +1.23; +2.21 / +1.09. New: CP_bl1 +2.13 / +1.21; FINAL +2.14 / +1.15 |
| 103 | Wake q-ratio at 1 / 2 / 3 L | CP 0.64 / 0.92 / 0.98 | unchanged for CP; FINAL (run FINAL_bl1) 0.66 at 1 L (2 and 3 L in `cfd/results/wake_cfd.csv`, not re-read here) |
| 110 | D's lead over CP (skidpad, autocross) | 0.01 s and 0.22 s | unchanged for CP (0.01 / 0.22 s); but FINAL (60.75 s) is now faster than D (60.94 s) on the autocross, so "D is fastest on the skidpad and autocross" no longer holds against the car |
| 114 | CP and D at 1 L: q-ratio, autocross penalty | 0.64 / 0.65, +2.14 s each | 0.64 / 0.65, +2.15 s each; FINAL 0.66, +2.14 s |
| 117 | "**CP is the chosen car.**" | CP | FINAL is the car (CP with the F and J supports) |

## Frame torsion diagonals (lines 121-131)

| Line | Statement | Old value | New value |
|---|---|---|---|
| 128 | Autocross, "as built (CP)", point-mass / four-wheel, before / after | 60.90 / 61.97 s, 61.12 / 62.12 s | FINAL: 60.53 / 61.30 s, 60.75 / 61.46 s |
| 129 | Fast circuit, before / after | 82.87 / 82.99 s, 82.97 / 83.08 s | FINAL: 83.07 / 83.08 s, 83.14 / 83.16 s |
| 131 | Cost of the added mass, autocross | +0.22 s | +0.23 s (FINAL) |
| 125 | Torsional stiffness 834 / 1476 Nm/deg | 834 / 1476 | unchanged: torsion does not depend on the mass positions (identical to the last bit at the old and new CG) |

## Media and film captions

| Line | Statement | Old value | New value |
|---|---|---|---|
| 157 | Build-up film caption | "The as-built car (CP) assembled stage by stage" | the film is of the CAD with the F and J supports (line 7 already says "the final car"): FINAL |
| 169 | Variants picture caption | "C (the chosen car's run, CP)" | the chosen car is FINAL; CP is C's wings on the as-built bodywork |
| 181 | Smoke film caption | "the chosen car, CP" | the chosen car is FINAL (the film still shows CP, labelled C) |
| 193 | Smoke C vs FINAL caption, last sentence | "The lap sim still uses CP until the CAD mass is updated." | the lap sim uses FINAL since 2026-11-28 (sentence to drop) |
| 205 | Lap films caption | "The as-built car (CP) round the autocross and the fast circuit" | FINAL; films remade 2026-11-28 (autocross 61.46 s, fast circuit 83.16 s four-wheel, 1.07 / 1.00 MB, git-ignored). The two embedded GitHub video links (lines 199, 202) still point at the CP films: re-upload needed |

## Assumptions and limits

| Line | Statement | Old value | New value |
|---|---|---|---|
| 213 | Tyres: grip -10 % / +10 % on the autocross | +3.8 s / -3.2 s | unchanged (+3.83 / -3.17 s, FINAL) |
| 213 | "The sign of the cornering balance (rear axle limits first)" | rear axle limits first | FINAL: front axle limits first at 45 and 100 m, nearly neutral (+0.6 / +1.3 %); the sign now hangs on 0.3 points of aero balance (0.397 against neutral 0.400) |
| 229 | Roll stiffness split | 38 % front | 39 % front (38.7 %; the springs are sized to 3.2 / 3.5 Hz at the new sprung masses: wheel rates 21.36 / 36.87 N/mm, was 21.10 / 37.18) |

## Wing supports sections

| Line | Statement | Old value | New value |
|---|---|---|---|
| 270 | "a sensitivity result for the next version, not the released car. CP stays the default aero car everywhere" | CP default | FINAL (= CPFF's geometry, run FINAL_bl1) is the default; the CPFF column of `media/support_sensitivity.md` is the car |
| 276 | CPF vs CP_bl1: skidpad, autocross; spread | -0.01 / -0.03 s, -0.32 / -0.61 s; 0.005 / 0.13 s | unchanged at two decimals (-0.011 / -0.027, -0.319 / -0.607 s; 0.005 / 0.13 s) |
| 277 | 45 m balance CP_bl1 to CPF; grip speed; band | -6.2 % to +0.4 %; 113.8 to 117.9 km/h; 1.5 points | -5.4 % to +1.4 %; 114.0 to 117.2 km/h; 1.6 points |
| 278 | CPF fast circuit, point-mass / four-wheel | +0.20 s / +0.13 s | +0.20 s / +0.14 s |
| 298 | CPFF vs CPF 45 m balance; band | -0.3 % vs +0.4 %, band 1.5 points | +0.6 % vs +1.4 %, band 1.6 points (CPFF now front-limited, as FINAL) |
| 299 | "Row `CPFF` ... is CFD only; CP stays the default" | CP default | FINAL is the default (row FINAL = CPFF's geometry) |

## Outside the README (not part of the README job, listed so they are not missed)

| File, line | Statement | Old value | New value |
|---|---|---|---|
| `docs/stress_frame.md` 140 | load set | "302.6 kg ... as-built aero, CP (ClA 3.89, 43 % front)" | 302.56 kg at the reconciled CG (319.9 mm), FINAL aero (ClA 4.13, 40 % front) |
| `docs/stress_frame.md` 144 | Cornering 1.6 g | 106 MPa, FoS 4.09, 1.15 mm at FS2_L_R | 110 MPa (RRK-RT1_R), FoS 3.95, 0.97 mm at FBT_R |
| `docs/stress_frame.md` 145 | Braking 1.5 g | 88 MPa, FoS 4.93, 0.47 mm | 95 MPa (RRK-RT1_L), FoS 4.56, 0.47 mm |
| `docs/stress_frame.md` 146 | Bump 3 g | 166 MPa, FoS 2.62, 0.35 mm | 163 MPa (RRK-RT1_L), FoS 2.67, 0.34 mm |
| `docs/stress_frame.md` 147 | Corner + brake | 106 MPa, FoS 4.10, 1.41 mm | 100 MPa (FS2_L-FH_L_R), FoS 4.35, 1.24 mm at FS2_L_R |
