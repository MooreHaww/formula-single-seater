# README audit, 2026-11-25

**How I read the brief.**
- This is a read-only audit of `README.md` as it stood on 2026-11-25 evening, after the RT1-RRK removal and the m_frame change (46.26 kg).
- Line numbers refer to that version.
- Nothing in the README was changed; the fixes are proposals for later.
- Checked against `docs/log.md`, `media/results_table.md`, `media/mass_table.md`, `media/lap_time_table.md`, `sim/stress/*_report.txt`, `media/views/` and `tools/sw_run.py`.
- **Aero numbers:** every one is marked **pending the CFD session**. The CFD session is still changing them, so none was judged right or wrong here.
- **Severity:** **High** means a reader is misled about what was done. **Medium** means a stale or unsupported number. **Low** means wording.

## (a) Out of date after the diagonal removal and the m_frame change

The frame, mass, stiffness, stress and lap-time rows were updated with the 2026-11-25 regeneration, and they match `media/results_table.md`, `media/mass_table.md` and `media/lap_time_table.md`.

| Line | Text now | Problem | Proposed fix | Severity |
|---|---|---|---|---|
| 34 | `run_all('test')  % 24 self-tests` | There are 27 self-tests (`run_all('test')`: 27 of 27 PASS, 2026-11-25). | "27 self-tests" | Medium |
| 117 | "... and the fused analysis frame" (`media/views/frame_analysis_*`) | The frame_analysis views are dated 2026-11-18. They show the 124-tube frame with RT1-RRK. `FrameAnalysis 4` was re-run today on 123 tubes, but its views were not re-saved. | Re-save the frame_analysis views (a SolidWorks step: wait until Fluent is done), or say the picture is the 124-tube frame. | Medium |
| 144 | "Going from a 5 mm to a 4 mm mesh changes this by 0.3 %" | The mesh study was done on the 124-tube frame (2026-11-18). Only a 4 mm mesh was run on 123 tubes. | "... (mesh study on the 2026-11-18 frame with RT1-RRK)" | Low |
| 147 | "24 % of the mass is a placeholder" | `mass_budget` now reports 25 % (74.3 kg GUESS of 302.6 kg with driver). | "25 %" | Low |
| 47 | "834 without the 9 torsion diagonals" | 7 are `_diag` tubes and 2 are the sidepod-top diagonals, so the 9 counts tubes, not diagonal positions. Elsewhere the repo says "9 tubes". | "834 without the 9 diagonal tubes" | Low |
| 104 | "Frame tubes (trimmed-weldment mass; centre-line 43.5 / 48.7 kg) — 41.4 kg / 46.3 kg" | Correct, but 46.3 is rounded while line 46 says 46.26 kg. | Use 46.26 in both places. | Low |
| 54–61, 65–97, 133–137 | aero, lap-time, following-car and cornering-balance numbers | **pending the CFD session** | — | — |

## (b) Claims with no figure, file or test behind them

| Line | Claim | What is missing | Proposed fix | Severity |
|---|---|---|---|---|
| 21 | "runs the motion study and the frame beam studies" | `sim/stress/chassis_statics_report.txt` shows all three SolidWorks beam studies (torsion, braking, cornering) **set up but NOT solved**: "No load or prescribed displacement is defined". There are no SolidWorks results on the production weldment. | "sets up the frame beam studies in SolidWorks Simulation (they do not solve yet; frame results come from the MATLAB beam model and the separate fused-solid check)" | **High** |
| 11 | "With SolidWorks 2026 (Student is enough) and Python 3 installed" | `tools/sw_run.py` also needs the .NET SDK: it compiles the C# harness with the Roslyn `csc.dll` under `C:\Program Files\dotnet\sdk` and stops without it. | Add ".NET SDK" to the requirements. | **High** (rebuild fails on a clean machine) |
| 46 | "123 tubes of 25.4 mm **4130**" | The SolidWorks weldment is built in **AISI 1020** (BuildTubes report, CheckChassis). frame_fe and FrameAnalysis use 4130 normalised. The README does not say which one the car is, or that the CAD mass uses 1020's density (7900 kg/m³). | State one material. If 4130 is intended, note the CAD material is 1020 and the difference (density nearly equal, yield 435 MPa vs about 350 MPa for 1020). | **High** (the factor of safety 2.62 is against 4130 yield) |
| 46 | "46.26 kg as the trimmed SOLIDWORKS weldment" | The source column names `params/car_params.txt` and `frame_trimmed_mass.m`. The measurement is CheckChassis (`cad/chassis/check_chassis_report.txt`). | Add `cad/chassis/check_chassis_report.txt` to the source. | Low |
| 5 | "the wings are larger than the FS rules allow" | No figure or file shows the rule check (which rule, by how much). | Cite the rule and the dimension, or drop the comparison. | Medium |
| 49–52 | camber gain, bump steer, roll centres, motion ratios | The source is `matlab/suspension_geometry.m`, but no generated table or report file holds these values. Not re-checked in this audit. | Point at a written output (e.g. a `media/` table) or add one. | Medium |
| 53 | "4.0 mm (rear upper joint)" | Backed by `suspension_optimise` (self-test prints joint margins 6.3 / 3.98 / NaN / 4.06 mm). It holds only for the assumed 12.5 mm housing; see (c). | — | — |
| 93–96 | "D is fastest on the skidpad and autocross" | **pending the CFD session.** The log's own caveat: CP_bl1 differs from CP by +2.2 % ClA, larger than D_AB's lead over CP_bl1 (+1.3 %). D vs CP is not a robust ranking. | Keep the ranking only where the margin exceeds the measured mesh/layer effect. | Medium (pending) |
| 117 | `media/views/*_iso.png` "and the other five views" | `media/views/` also holds `unsaved_Default_*.png` (2026-11-16, tracked in git, 5 files with a `_right` view). They are stray. | Delete them or ignore them (needs your OK). | Low |
| 133 | "no mesh-independence or y+ study" | Out of date the other way. The log (2026-11-18 evening) records a mesh-sensitivity check on C and D, and y+ medians 31–42 (wings, floor, body) and 70–76 (wheels). The README undersells it. **pending the CFD session** | Summarise the check: ClA within 0.3 %, CdA 2.4 %, surface mesh untested, wall functions. | Medium (pending) |
| 54 | "unsteady, mean good to about 1 %" next to "steady RANS" (lines 80, 133) | It reads as a contradiction. The meaning is that the steady solver did not settle and the force oscillates; the log gives CP's band as 2.5 %. **pending the CFD session** | "steady RANS that does not settle; the force mean is used (band 2.5 %)" | Medium (pending) |

## (c) Assumptions and limits to add or tighten

| Topic | README now | Proposed wording (not applied) |
|---|---|---|
| Rigid chassis in the lap sim | Line 151: "The chassis is rigid in both." | Add: "The frame stiffness (1476 Nm/deg) and its loss without RT1-RRK do not enter any lap time; the lap sim only sees the frame's mass." |
| Tyre μ 1.40 and load sensitivity 0.10 | Line 131 covers it, with the ±10 % grip effect. | Tighten: "Every lap time, the cornering balance and the load cases depend on these two numbers. The cornering balance sign (rear limits first) has not been checked against a different load sensitivity." Also flag that the load cases (`load_cases.csv`) use the same μ. |
| Bearing housing 12.5 mm | Lines 53 and 155 state it. | Tighten line 53: "4.0 mm margin, valid only for the assumed 12.5 mm housing radius; a bigger rod end reduces it one-for-one." |
| Steady RANS only for ranking | Lines 80 and 133. **pending the CFD session** | Keep, and add that the ranking itself is not robust where two variants are within the measured layer and mesh effect (D vs CP). |
| No physical test | Line 146 says it for torsion only. | Add a general line at the top of the section: "Nothing in this repository has been built or tested physically. Every number is from a model." |
| SolidWorks Simulation not solved on the production weldment | Not stated anywhere. Line 21 implies the opposite. | Add under "Frame stiffness and stress": "The SolidWorks Simulation beam studies on the production weldment (ChassisStatics) are set up but do not solve ('No load or prescribed displacement is defined'). The only SolidWorks results are on the separate fused-solid analysis frame, for torsion only." |
| Frame material | Not stated as an assumption. | "The CAD weldment is AISI 1020; the stress model and the solid check use 4130 normalised (yield 435 MPa). The factors of safety are for 4130." |
| Frame below target | Line 47 says 1.6 % under 1500. | Add to limits: "The frame is 24 Nm/deg under its own 1500 Nm/deg target, by decision (2026-11-25)." |
| Brackets and welds | Line 147 mentions guesses generally. | Name it: "6.4 kg for brackets and welds is a guess (about 13 % of the centre-line frame) and is not drawn." |

## Not checked in this audit

- The suspension rows (49–52) against a fresh `suspension_geometry` run.
- The motion-study numbers (line 156: +23 / +14 mm).
- The overlap volumes (line 157).
- Every aero, lap and following-car number (pending the CFD session).
- `tools/README.md` and `docs/stress_frame.md` (only `README.md` was audited).
