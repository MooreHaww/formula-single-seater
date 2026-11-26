# README update: notes (2026-11-25, evening)

Nothing was committed. One change is staged in the index: `git rm --cached pyfluent_watchdog.err`, so the new ignore rule takes effect. The file stays on disk. The CAD was not changed.

## How I read the brief

- **"Every fix in the audit that is not an aero number."** I applied the audit's (a), (b) and (c) proposals, using your five decisions where you gave one.
  - The audit's CFD wording items (y+ / mesh-check statement, "unsteady, mean good to 1 %", ranking robustness) are claims, not numbers. I applied them, with every figure taken from `media/cfd/cfd_results.md`.
- **"Anything else the audit says a clean machine would need."** The audit names only the .NET SDK. Reading `tools/sw_run.py` shows one more: the rebuild's BuildBodies step stops without a Python that has build123d (`.venv` or `uvx`). I added that too.
- **Material.** I did not rebuild. The README now states 1020 in the CAD, 4130 in the stress model and the solid check, and that the safety factor is against 4130's yield. 1020's yield of about 350 MPa is the audit's figure (the SolidWorks library value), not re-read from a file.
- **frame_analysis views.** One harness command regenerates them: `python tools/sw_run.py SaveStandardViews cad\analysis\frame_analysis.SLDPRT`. I ran it in a fresh SolidWorks (`restart-sw`, the step, `close-all`): ALL PASS, 6 views. The part it reads is dated 2026-11-25 10:52, the FrameAnalysis 4 run on 123 tubes. The README says the views were re-saved from the 123-tube part.
- **"Showcase section after the results summary."** It goes after the whole Results section (its table, sub-tables and Media), just before "Assumptions and limits". That keeps the results' sub-sections together.
- **"Suspension (existing GIF)".** The existing `media/suspension_bump_steer.gif` is embedded under that heading, with no VIDEO placeholder, because there is no suspension MP4. I moved that embed from the Media list to Showcase; the Media table still lists the file.
- **"Future-work list".** The README had none, so I added a short "Future work" section. The rear-wing item is first. The other four are open items the README already states as limits.
- **CFD wing mounting.** `cfd/geometry_notes.md` itself does not mention rear-wing supports. The geometry script it describes, `cad/generate/cfd_variants.py` (`build_rear_wing`), does add them: one flat pylon each side, 16 mm thick, 260 mm chord, at Y ±150 mm, from Z 300 mm up into the main element. They are fused to the car and counted in the `car_rw` force zone (log 2026-11-18: "CFD adds ... pylons"). So the README says the aero results include this idealised pylon's drag and interference, not a designed mount's. They do not "include no support".
- **Which runs the CFD films show.** `cfd/visualise.py` labels them: C = run CP, B = B_AB, D = D_AB. The captions say so.

## Aero numbers checked

Every aero number in the README was checked against `media/cfd/cfd_results.md`, `media/results_table.md`, `params/aero_variants.csv`, `media/lap_as_built_BD.csv` and the unrounded `cfd/results/cfd_summary.csv`.

**Two differed, now fixed:**
- D old L/D: 2.38 → **2.37** (4.19957 / 1.76847 = 2.3747; cfd_results.md 2.37).
- B old following penalty on the fast circuit: +1.23 → **+1.22 s** (1.22498 in `lap_as_built_BD.csv`).

**One statement changed:** CP "unsteady, mean good to about 1 %" now reads "does not settle: the downforce oscillates in a 2.5 % band and its mean is used". The source is cfd_results.md: CP NOT force-converged, downforce band 2.46 %. The "about 1 %" is still in the CSV's note column and was left there.

**Matching (unchanged):**
- ClA / CdA / L/D / front share for CP, B_AB, D_AB and B old.
- Wake q-ratios at 1/2/3 L (all five columns).
- All point-mass lap times.
- Following penalties (except the one above).
- Wings worth 5.60 / 1.63 s.
- Bodywork cost 0.13 / 0.45 s, ClA −2.3 %, CdA +1.6 % (unrounded: −2.32 %, +1.60 %).
- D_AB vs CP_bl1 +1.3 % (4.029 / 3.9768).
- CP_bl1 vs CP +2.2 %.
- B −2 %, D −4 %.
- Cornering balance 112.9 km/h, −6.5 %, neutral 0.394.
- Skidpad / 75 m / 0–100 for CP. `accel_test('CP')` re-run: 3.471 s and 4.3499 s.
- The new mesh-check figures (C_coarse −0.3/−0.1, C_bl1 +0.1/−2.4, C_w −0.1/−0.1, y+ medians 28–54 car, 70–98 wheels).

## .gitignore

- Un-ignored exactly two GIFs: `!media/cfd/vis/compare_ABCD.gif` and `!media/showcase/car_buildup.gif`.
  - Checked with `git check-ignore`: those two are trackable.
  - smoke_C.gif, compare_ABCD.mp4, car_buildup.mp4, lap_autocross.gif and A_orbit.gif are still ignored.
- Added `pyfluent_watchdog.err`. It was already tracked, so it was also removed from the index (`git rm --cached`, staged, not committed).
- compare_ABCD.gif is 5.1 MB, and it will now go into git.

## Audit items not applied

| Audit item | Why not |
|---|---|
| (b) lines 49–52, suspension values need a written output | No file holds them. Making one means running `suspension_geometry`, which rewrites the hardpoint block of `params/car_params.txt`. That is out of scope, and the values were not re-checked. |
| (b) line 117, stray `media/views/unsaved_Default_*.png` | The audit says they are tracked in git; they are not. `media/views/` is git-ignored, so they never reach the repo. Deleting untracked files is permanent, so they were left (as `docs/log.md` line 926 already decided). |
| (b) line 5, cite the FS rule | No rule text is in the repo. I did not cite a rule from memory. The sentence now says no rule check was made and gives the rear wing's height (about 1.55 m, `cfd/geometry_notes.md`). |

## Found while doing this (not in the audit)

- **`media/views/` is git-ignored.** The README's assembly iso picture (`media/views/formula_single_seater_Default_iso.png`) is therefore not in the repository and will not show on GitHub. Not changed: you only asked for the two GIFs to be un-ignored.
