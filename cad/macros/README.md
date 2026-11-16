# SolidWorks macros

All four are VBA modules saved as text (`.bas`, CRLF) so they diff in git. **Status:** first versions of `SaveStandardViews` and `ImportFrameNodes` ran in SolidWorks 2026 SP2.1 Student after fixes; the fixed versions in this folder, and `ImportAirfoil` and `ExportConfigsSTEP`, are untested, need the app. Every enum and member name was checked against the installed 2026 type library. Details: `docs/cad_playbook/macro_review.md`, section "Tested in SolidWorks 2026".

| Macro | Does | Output |
|---|---|---|
| `ImportAirfoil.bas` | Picks a `cad/airfoils/*.dat` file, asks for the chord in mm, inserts a 3D curve on the Front plane | Curve feature `Airfoil_<name>_c<chord>` in the active part |
| `ExportConfigsSTEP.bas` | Activates every configuration of the active part or assembly, rebuilds, saves STEP AP214 | `cfd/geometry/<doc>_<config>.STEP` plus `export_log.txt` with mass and CG per config |
| `SaveStandardViews.bas` | Saves iso, front, right, top, rear, bottom PNGs of the active document, white background | `media/views/<doc>_<config>_<view>.png` |
| `ImportFrameNodes.bas` | Draws one 3D-sketch line per tube from `cad/frame/frame_nodes.csv` and `frame_tubes.csv` One 3D sketch per tube group (`FRAME_hoop`, `FRAME_hoop_brace`, `FRAME_sis`, `FRAME_bulkhead`, `FRAME_sidepod`, `FRAME_front`, `FRAME_rear`), ready for one Structural Member each |

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
