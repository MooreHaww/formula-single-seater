# Ring 0 practice guide: SolidWorks and MATLAB from zero

For someone who has never opened SolidWorks or MATLAB. Every exercise mirrors a real part of the car, so nothing here is thrown away: the rim becomes `cad/suspension/rim.SLDPRT`, the equations exercise is how every part is linked to `params/car_params.txt`, the mini frame is the chassis technique in miniature.

Written for SolidWorks Design Premium for Students 2026 and MATLAB R2026a from memory of the 2024 to 2025 interfaces. SolidWorks 2025 and 2026 changed the look of the user interface (icons, a lighter default theme, some reorganised menus). Anything marked **verify** is a menu name, dialog name or behaviour I am not sure survived into 2026 unchanged: check it in the SolidWorks Help (the `?` button top right, or F1 inside a command) before trusting it, and correct this file when you find the 2026 name.

## Order and time

| # | File | What you build | Technique | Time |
|---|---|---|---|---|
| 1 | `01_solidworks_orientation.md` | nothing; a tour | the interface, mouse, shortcuts, saving | 45 min |
| 2 | `02_rim_revolve.md` | a 10 inch rim | Sketch, Smart Dimension, Revolve, Circular Pattern, Material, Mass Properties | 60 min |
| 3 | `03_bracket_extrude_cut_holewizard.md` | a caliper bracket | Extrude, Extruded Cut, Hole Wizard, Fillet | 45 min |
| 4 | `04_hub_and_assembly.md` | a hub, then rim + hub + bracket assembled | Hole Wizard tapped holes, Insert Component, Concentric and Coincident mates, Interference Detection | 60 min |
| 5 | `05_equations_and_car_params.md` | the rim driven by the parameter file | Global variables, Equations, Link to external file, Rebuild | 45 min |
| 6 | `06_airfoil_import.md` | a 500 mm wing element | Curve Through XYZ Points, Convert Entities, Extrude, custom material | 45 min |
| 7 | `07_weldment_mini_frame.md` | a 13-tube box frame | 3D Sketch, weldment profile, Structural Member, cut list | 90 min |
| 8 | `08_macro_test_30min.md` | the four repo macros run once | Tools > Macro, VBA editor, imports | 30 min |
| 9 | `09_solidworks_vocabulary.md` | a one-page cheat sheet | read it once, keep it open | 10 min |
| 10 | `10_matlab_first_hour.md` | the repo's self-tests run, one script of your own | MATLAB desktop, paths, scripts, structs, plots | 60 min |

About eight hours in all. Do 1 to 4 in one sitting if you can; 5 to 7 in a second; 8 and 10 whenever the apps are open. The Ring 0 check in the work plan is: rim, bracket and a mated assembly exist, a MATLAB script of your own runs, and the CFD smoke test (`cfd/ansys_quickstart.md`) has produced a lift and drag number.

## Rules that save hours

- **Save into the repo**: practice parts go in `cad/practice/`. Name files in lower case with underscores (`rim.SLDPRT`, `bracket.SLDPRT`). SolidWorks part and assembly files are tracked by git LFS (`.gitattributes` already lists them).
- **Units MMGS** before the first sketch (exercise 1 shows where). Every number in this project is mm, degrees, kg.
- **Fully define every sketch** (all lines black, "Fully Defined" in the status bar at the bottom right). Blue lines move when you least expect it.
- **Rename features** as you go (slow double-click the name in the tree, or F2): `Sketch_profile`, `Revolve_rim`, not `Sketch1`, `Revolve1`.
- **Ctrl+S every 15 minutes.** SolidWorks does not autosave by default; Tools > Options > System Options > Backup/Recover sets an auto-recover interval, set it to 10 minutes on day one (**verify** the page name).
- **Rebuild (Ctrl+B) after every feature.** If something turns yellow or red, fix it before adding the next feature.
- **One body per part** unless told otherwise: Tools > Evaluate > Check reports it.

## Where the exercises come from

| Exercise part | Real part | Playbook file |
|---|---|---|
| rim | `cad/suspension/rim.SLDPRT` | `docs/cad_playbook/06_wheel.md` |
| bracket, hub | `cad/suspension/hub.SLDPRT`, upright tabs | `05_hub.md`, `04_upright.md` |
| equations | every part | `00_index.md` (Parameters) |
| airfoil | wing elements | `10_front_wing.md`, `11_rear_wing.md` |
| mini frame | chassis | `02_chassis.md` |
| macros | all | `docs/cad_playbook/macro_review.md` |
