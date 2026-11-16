# 02a The whole frame from an empty part, in 3 steps

The short version of `02_chassis.md` steps 1 to 3 and 9 to 10. Status: `ImportFrameNodes` has run in SolidWorks 2026 (single-sketch version); the per-group version and `BuildTubes` are untested, need the app.

**Once per PC (already done on the main PC, 2026-11-16):**
- The weldment profile folder `<repo>\cad\weldment_profiles` is listed in Tools > Options > System Options > File Locations > Weldment Profiles.
- The two macro projects exist: `cad/macros/ImportFrameNodes.swp` and `cad/macros/BuildTubes.swp`. To make one: Tools > Macro > New, then File > Import File with the `.bas` in the VBA editor (`cad/macros/README.md`).

**Only if the hardpoints changed:** run `frame_layout` in MATLAB to rewrite `cad/frame/*.csv`.

## The 3 steps

1. **Empty part.** File > New > Part with the project template (mm). Saving is optional: if it is still unsaved at the end, step 3 saves it as `cad/chassis/chassis.SLDPRT`. That only works if no file with that name exists yet; otherwise save it under your own name first.
2. **Skeleton.** Tools > Macro > Run > `ImportFrameNodes.swp`. Expect seven 3D sketches, `FRAME_hoop` ... `FRAME_rear`, with 116 lines in total. The message lists the count per sketch.
3. **Tubes.** Tools > Macro > Run > `BuildTubes.swp`. It builds seven Structural Members (`SM_<group>`), sets AISI 1020, updates the cut list and saves. Expect "ALL PASS" in the final message:

| Check | Expected |
|---|---|
| tubes per group | 12 / 10 / 7 / 4 / 18 / 32 / 33 |
| cut-list bodies | 116 |
| total cut length | within 5 % of 41.88 m |
| mass | 38 to 46 kg |
| material | AISI 1020 |

If it stops, the message names the group and SolidWorks' reason, and nothing has been saved. Fix the cause and run step 3 again: members that already exist are kept.

**Next:** the trim (`02_chassis.md` step 7).
