# 02a The whole frame from an empty part, in 3 steps

The short version of `02_chassis.md` steps 1 to 3 and 9 to 10. Status: `ImportFrameNodes` has run in SolidWorks 2026 (single-sketch version); the per-group version and `BuildTubes` are untested, need the app.

**Once per PC (already done on the main PC, 2026-11-16):**
- The weldment profile folder `<repo>\cad\weldment_profiles` is listed in Tools > Options > System Options > File Locations > Weldment Profiles.
- The macro project `cad/macros/repo_macros.swp` holds the modules (at least `ImportFrameNodes` and `BuildTubes`). To add or refresh a module: Tools > Macro > Edit on the `.swp`, remove the old module, File > Import File with the `.bas`, Debug > Compile VBAProject, save (`cad/macros/README.md`).

**Only if the hardpoints changed:** run `frame_layout` in MATLAB to rewrite `cad/frame/*.csv`.

## The 3 steps

1. **Empty part.** File > New > Part with the project template (mm). Saving is optional: if it is still unsaved at the end, step 3 saves it as `cad/chassis/chassis.SLDPRT`. That only works if no file with that name exists yet; otherwise save it under your own name first.
2. **Skeleton.** Tools > Macro > Run > `repo_macros.swp`, pick `ImportFrameNodes.main`. Expect seven 3D sketches, `FRAME_hoop` ... `FRAME_rear`, with 114 lines in total. The message lists the count per sketch.
3. **Tubes.** Tools > Macro > Run > `repo_macros.swp`, pick `BuildTubes.main`. It builds seven Structural Members (`SM_<group>`), sets AISI 1020, updates the cut list and saves. Expect "ALL PASS" in the final message:

| Check | Expected |
|---|---|
| tubes per group | 12 / 10 / 7 / 4 / 18 / 32 / 31 (read from `frame_tubes.csv`) |
| cut-list bodies | 114 |
| total cut length | within 5 % of 41.48 m |
| mass | 38 to 46 kg |
| material | AISI 1020 |

It does not stop at the first problem. A group that fails a check (sketch missing or out of date with the CSV, profile missing) is skipped. A group SolidWorks refuses is tried segment by segment, and every segment that fails even alone is listed with its tube id, nodes and length. Whatever can be built is built and saved, and every failure is in the final message and in `cad/chassis/build_tubes_report.txt`. It changes nothing only if no group at all can be built. Fix the cause and run step 3 again: members that already exist are kept.

**Next:** the trim (`02_chassis.md` step 7).
