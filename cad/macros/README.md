# SolidWorks macros

**Since 2026-11-17 the frame, layout and assembly are built from the terminal, not from these macros.** `python tools/sw_run.py rebuild` drives SolidWorks 2026 over COM and runs every step with no VBA editor, no F5 and no message boxes. The build logic was ported to C# (`tools/sw_harness/*.cs`), which the script compiles against the installed interop DLLs. See `tools/README.md`. The `.bas` files below are kept as the reference the C# was ported from and for running one step by hand. Known bug in the `.bas` (fixed in the C# port): an API call that returns COM `1` for True makes `Not result` truthy in VBA. This is why `BuildLayout.bas` reported axes as refused and left planes "value only". Write `If result = False` instead of `If Not result` when using them.

All eight are VBA modules saved as text (`.bas`, CRLF) so they diff in git. They can live in one macro project (`cad/macros/repo_macros.swp`); run each as `<Module>.main`. **Status:** first versions of `SaveStandardViews` and `ImportFrameNodes` ran in SolidWorks 2026 SP2.1 Student after fixes; the fixed versions in this folder, and `ImportAirfoil` and `ExportConfigsSTEP`, are untested, need the app. Every enum and member name was checked against the installed 2026 type library. Details: `docs/cad_playbook/macro_review.md`, section "Tested in SolidWorks 2026".

| Macro | Does | Output |
|---|---|---|
| `ImportAirfoil.bas` | Picks a `cad/airfoils/*.dat` file, asks for the chord in mm, inserts a 3D curve on the Front plane | Curve feature `Airfoil_<name>_c<chord>` in the active part |
| `ExportConfigsSTEP.bas` | Activates every configuration of the active part or assembly, rebuilds, saves STEP AP214 | `cfd/geometry/<doc>_<config>.STEP` plus `export_log.txt` with mass and CG per config |
| `SaveStandardViews.bas` | Saves iso, front, right, top, rear, bottom PNGs of the active document, white background | `media/views/<doc>_<config>_<view>.png` |
| `ImportFrameNodes.bas` | Draws one 3D-sketch line per tube from `cad/frame/frame_nodes.csv` and `frame_tubes.csv` | One 3D sketch per tube group (`FRAME_hoop`, `FRAME_hoop_brace`, `FRAME_sis`, `FRAME_bulkhead`, `FRAME_sidepod`, `FRAME_front`, `FRAME_rear`), ready for one Structural Member each |
| `BuildTubes.bas` | Run after `ImportFrameNodes`. For each `FRAME_<group>` sketch it builds one Structural Member from that sketch's segments (`formula` / `tube_round`, size per group from `frame_tubes.csv`, end miter). Groups that fail are skipped or built segment by segment, with every failure listed. It then sets AISI 1020, updates the cut list, checks counts, length and mass against `frame_tubes.csv`, and saves. Third run in SolidWorks 2026: ALL PASS (114 bodies, 41.5 kg). | `SM_<group>` features, one PASS/FAIL message, saved part (`cad/chassis/chassis.SLDPRT` if it was unsaved), `cad/chassis/build_tubes_report.txt` |

| `TrimTubes.bas` | Run after `BuildTubes` (ALL PASS) on the saved chassis. Makes one Trim/Extend per node from `cad/frame/frame_trims.csv` (MATLAB `frame_trims`): the weaker tubes at a node are cut (coped) against the strongest one. Bodies are found by centroid, no selection needed. It checks first, skips and lists rows it cannot match, keeps existing `Trim_*`, and does not stop at a failure. Untested, needs the app. | `Trim_<node>` features, PASS/FAIL message (bodies stay 114, mass drops), saved part, `cad/chassis/trim_tubes_report.txt` |
| `BuildLayout.bas` | Run in an empty new part (or with nothing open). Builds the master layout from `car_params.txt`: renames the default planes GROUND / CENTRE / FRONT_AXLE, links the equation file, adds REAR_AXLE, MAIN_HOOP, FRONT_HOOP, WHEEL_CENTRE_HEIGHT (tied to their global variables), the two axle axes, and one named reference point `HP_<name>` per right-side hardpoint. Untested, needs the app. | `cad/layout/master_layout.SLDPRT`, `cad/layout/build_layout_report.txt` |
| `BuildAssembly.bas` | Run with nothing open. Imports the `cad/step` bodies to `cad/body/*.SLDPRT` once, builds or updates `cad/formula_single_seater.SLDASM`: layout fixed, chassis and bodies mated plane-to-plane to the layout, left tyres and rims as turned copies, then interference and mass. Untested, needs the app. | the assembly, `cad/build_assembly_report.txt` |

Review notes and the order to test them in: `docs/cad_playbook/macro_review.md`.

## Install once

1. In SolidWorks: Tools > Macro > New. Save as `cad/macros/<Name>.swp`. The macros find the repo root by walking up from the `.swp` folder until they find `params/car_params.txt`, so the `.swp` must be inside the repo; `cad/macros/` is the convention.
2. The VBA editor opens. File > Import File... and pick the `.bas`. Remove the empty module the wizard made (right-click > Remove).
3. Save (Ctrl+S in the VBA editor) and close it.
4. Run with Tools > Macro > Run and pick the `.swp` (not the `.bas`), or put them on a toolbar via Tools > Customize > Commands > Macro.
5. After a `.bas` changes: Tools > Macro > Edit on the `.swp`, remove the old module, File > Import File the new `.bas`, save.

The `.swp` files are binary and are ignored by `.gitignore`; the `.bas` text is the source of truth.

## Order of use

- Ring 0, Nov 18: `ImportAirfoil` on `symmetric.dat` (chord 300) for the practice wing element, then on `fw_main.dat`.
- Ring 2f: `ExportConfigsSTEP` on the CFD body part with configurations A to D.
- Every session: `SaveStandardViews` on whatever was worked on, then paste one picture into `docs/log.md`.
