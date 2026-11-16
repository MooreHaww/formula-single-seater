# CAD playbook: index and conventions

One file per part, in build order. Each file gives the inputs (parameter names from `params/car_params.txt` or exact mm), the sketch planes, the feature order, the names to use, how the part mates, its configurations, the beginner mistakes that cost the most time, and an end-of-part check. Written for SolidWorks 2026 (Student Design Premium). Menu names were written from memory of the 2024 to 2025 interface; anything marked **verify** should be checked against the 2026 menus or the SolidWorks Help before trusting it.

| Order | File | Part | Ring |
|---|---|---|---|
| 1 | `01_master_layout.md` | `cad/layout/master_layout.SLDPRT` | 2a |
| 2 | `02_chassis.md` | `cad/chassis/chassis.SLDPRT` (weldment) | 2b |
| 3 | `03_wishbones.md` | `cad/suspension/wishbone_*.SLDPRT` | 2c |
| 4 | `04_upright.md` | `cad/suspension/upright_front.SLDPRT`, `_rear` | 2c |
| 5 | `05_hub.md` | `cad/suspension/hub.SLDPRT` | 2c |
| 6 | `06_wheel.md` | `cad/suspension/rim.SLDPRT`, `tyre.SLDPRT` | 2c |
| 7 | `07_nose.md` | `cad/body/nose.SLDPRT` | 2d |
| 8 | `08_sidepods.md` | `cad/body/sidepod.SLDPRT` | 2d |
| 9 | `09_floor_diffuser.md` | `cad/aero/floor_diffuser.SLDPRT` | 2d |
| 10 | `10_front_wing.md` | `cad/aero/fw_*.SLDPRT`, `front_wing.SLDASM` | 2d |
| 11 | `11_rear_wing.md` | `cad/aero/rw_*.SLDPRT`, `rear_wing.SLDASM` | 2d |
| 12 | `12_endplates.md` | `cad/aero/fw_endplate.SLDPRT`, `rw_endplate.SLDPRT` | 2d |
| 13 | `13_details.md` | seat, driver dummy, steering wheel, motor, battery, pushrods, rockers, springs | 2e |
| 14 | `14_cfd_body.md` | `cad/cfd_body/cfd_body.SLDPRT` | 2f |
| 15 | `15_assembly.md` | `cad/formula_single_seater.SLDASM`, configurations A to D | 2c to 2f |
| | `macro_review.md` | What to test first in the three macros | 0 |

## Conventions that every file assumes

**Coordinate frame.** The car frame is the master layout's frame and every part is built in it: **X rearward** from the front axle centre, **Y to the right**, **Z up** from the ground. The SolidWorks default planes map as: Front plane = XZ? No. To avoid confusion the master layout defines three named planes, `GROUND` (Z = 0), `CENTRE` (Y = 0) and `FRONT_AXLE` (X = 0), and every other part references those by name through the layout, never the default Front/Top/Right planes. In a new part, SolidWorks' Top plane is horizontal, so **sketch the ground on the Top plane, the centreline on the Right plane, and the axle plane on the Front plane**, then rename them (right-click the plane > Properties, or slow double-click the name) to GROUND, CENTRE, FRONT_AXLE. Check the orientation with View > Modify > View Orientation (space bar): looking at the Front plane you should see the car from the front, Z up, Y to the right. **verify**: SolidWorks' Front plane normal points toward -Y in its default frame; if the car ends up mirrored, flip the Y sign convention once in the master layout and nowhere else.

**Units.** Document units MMGS (Tools > Options > Document Properties > Units > MMGS). Angles in degrees. Every template below starts from a part saved as `cad/templates/car_part.prtdot` with MMGS, the three named planes and the equation file linked. Make that template first (File > Save As > Part Templates). **verify** the template folder appears under Tools > Options > System Options > File Locations > Document Templates.

**Parameters.** Every dimension that is in `params/car_params.txt` is typed as `="name"` in the dimension box, never as a number. Tools > Equations > Link to external file once per part, then the global variables appear in the dimension dialog's drop-down. If a parameter is missing, add it to the file (and to the MATLAB side if it matters there), do not invent a local one. Hardpoints are between the BEGIN/END markers and come from `matlab/suspension_geometry.m`.

**Naming.** Files: lower case, underscores, side suffix `_R`/`_L` only for parts that are not mirrored in the assembly (uprights and wishbones are mirrored, so one file each). Features inside a part: rename every feature to what it is (`Sketch_profile`, `Extrude_main`, `Fillet_leading_edge`), a feature tree of `Boss-Extrude7` costs you an hour in Ring 3. Sketches that hold hardpoints: `HP_<name>` with the point named after the parameter.

**Materials.** Steel 1020 for tubes (`tube_*`), 7075-T6 for uprights and hubs, 6061-T6 for wishbone inserts, carbon as "Custom, 1600 kg/m3, E 60 GPa" for wings and body (Material > Custom), aluminium 6061 for rims, rubber 1100 kg/m3 for tyres, block materials for motor (steel) and battery (set density so the mass equals `battery_mass`). Mass properties must land near `mass_car` at the end of Ring 2.

**Configurations.** Only the aero parts have configurations (A to D, named exactly `A`, `B`, `C`, `D`). Everything else has one configuration named `Default`. The top assembly's configurations A to D select the wing configurations and suppress the wings in A. Configure through the ConfigurationManager tab > right-click a feature or dimension > Configure Feature / Configure Dimension (the Modify Configurations table).

**Rebuild discipline.** Ctrl+B after every feature. If a feature turns yellow or red, fix it before the next one; errors stack. Save every 15 minutes (Ctrl+S) and keep the Design Binder empty. Never leave the master layout with an error, every part references it.

**Top-down references.** Parts reference the master layout by inserting it: in the part, Insert > Part > choose `master_layout.SLDPRT`, tick only "Reference geometry" and "Sketches" (not solids) and "Break link to original part" off. **verify** the dialog name ("Insert Part" PropertyManager) and that sketches of an inserted part can be used with Convert Entities. Fallback that always works: open the assembly, edit the part in context and use Convert Entities on the layout's sketches, which creates in-context references (the `->` suffix). In-context references are fine as long as the layout is the only thing referenced.

**Screenshots for the log.** Run `SaveStandardViews` on every part when it is done (`cad/macros/README.md`).

## Build-order dependency

```
master_layout
  ├── chassis (frame nodes from cad/frame/frame_nodes.csv via ImportFrameNodes macro)
  ├── wishbones, upright, hub, wheel  (hardpoints HP_* sketches)
  ├── nose, sidepods, floor_diffuser  (body section sketches)
  ├── front_wing, rear_wing, endplates (wing position sketches, angles per config)
  ├── details
  └── cfd_body  (Combine of the body-side solids, half cut, per config)
assembly: all of the above, mates to layout planes and HP points
```

## Time budget (plan: 34 h for Ring 2)

Master layout 3 h, chassis 6 h, suspension corner 6 h (then mirror and copy to the rear, 2 h), wheels 1 h, body 6 h, wings and endplates 4 h, details 3 h, CFD body 3 h. If the chassis passes 8 h, use the weldment fallback in `02_chassis.md`.
