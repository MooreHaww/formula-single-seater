# SolidWorks macros

All three are VBA modules saved as text (`.bas`) so they diff in git. **Status: untested, needs the app.** They were written without SolidWorks open, so expect to correct a method name or enum on the first run; the SolidWorks API Help (Help > API Help) has every call used here.

| Macro | Does | Output |
|---|---|---|
| `ImportAirfoil.bas` | Picks a `cad/airfoils/*.dat` file, asks for the chord in mm, inserts a 3D curve on the Front plane | Curve feature `Airfoil_<name>_c<chord>` in the active part |
| `ExportConfigsSTEP.bas` | Activates every configuration of the active part or assembly, rebuilds, saves STEP AP214 | `cfd/geometry/<doc>_<config>.STEP` plus `export_log.txt` with mass and CG per config |
| `SaveStandardViews.bas` | Saves iso, front, right, top, rear, bottom PNGs of the active document, white background | `media/views/<doc>_<config>_<view>.png` |
| `ImportFrameNodes.bas` | Draws one 3D-sketch line per tube from `cad/frame/frame_nodes.csv` and `frame_tubes.csv` | 3D sketch `FRAME_SKELETON` in the active part, ready for Weldments |

Review notes and the order to test them in: `docs/cad_playbook/macro_review.md`.

## Install once

1. In SolidWorks: Tools > Macro > New. Save as `cad/macros/<Name>.swp` (same folder as the `.bas`, the macros find the repo root from their own path).
2. The VBA editor opens. File > Import File... and pick the `.bas`. Remove the empty module the wizard made (right-click > Remove).
3. Save (Ctrl+S in the VBA editor) and close it.
4. Run with Tools > Macro > Run, or put the three on a toolbar via Tools > Customize > Commands > Macro.

The `.swp` files are binary and are ignored by `.gitignore`; the `.bas` text is the source of truth.

## Order of use

- Ring 0, Nov 18: `ImportAirfoil` on `symmetric.dat` (chord 300) for the practice wing element, then on `fw_main.dat`.
- Ring 2f: `ExportConfigsSTEP` on the CFD body part with configurations A to D.
- Every session: `SaveStandardViews` on whatever was worked on, then paste one picture into `docs/log.md`.
