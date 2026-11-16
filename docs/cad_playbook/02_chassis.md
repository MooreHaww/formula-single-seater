# 02 Chassis (`cad/chassis/chassis.SLDPRT`, weldment)

A tubular spaceframe from the node and tube lists in `cad/frame/frame_nodes.csv` and `frame_tubes.csv` (98 tubes, 35 m, about 37 kg in steel before trimming), built with SolidWorks Weldments so that the Ring 4 torsion study can use a beam mesh.

## Inputs

`cad/frame/frame_nodes.csv` (42 nodes, car frame, mm), `cad/frame/frame_tubes.csv` (tube, node_a, node_b, group, od, wall), `tube_main_od` 25.4, `tube_main_wall` 2.4, `tube_secondary_wall` 1.6. Groups: `hoop` and `hoop_brace` use the main wall, `sis`, `bulkhead`, `front` and `rear` the secondary wall.

## Before you start: the tube profiles

Weldments need a profile library entry for each tube size. Tools > Options > System Options > File Locations > Weldment Profiles shows the folder (**verify** the path; typically `...\SOLIDWORKS 2026\lang\english\weldment profiles`). Create two profiles:

1. New part, sketch on Front plane: circle D 25.4 and circle D 20.6 (25.4 - 2 x 2.4), both centred on the origin. Save As type "Lib Feat Part (*.sldlfp)" named `25.4x2.4.sldlfp` in `<profiles>\iso\tube_round\` (make the folders; the three levels are Standard\Type\Size and the dialog lists them in that order). **verify**: you may need to select the sketch in the tree before Save As so that it becomes the library feature.
2. Same with inner circle D 22.2 for `25.4x1.6.sldlfp`.

## Feature order

1. New part from the template. Insert > Part > `master_layout.SLDPRT` with reference geometry and sketches only (`00_index.md`), or skip this if the macro-made skeleton is going to live in this part.
2. **Skeleton sketch.** Run `cad/macros/ImportFrameNodes.bas` (untested, needs the app) in this part: it reads the two CSVs and draws one 3D-sketch line per tube between the node coordinates, in a 3D sketch named `FRAME_SKELETON`. Lines are not dimensioned (no equations), which is deliberate: the frame follows the hardpoints through MATLAB regeneration of the CSV, not through SolidWorks equations. Without the macro: Insert > 3D Sketch, Line tool, type coordinates in the PropertyManager for each endpoint, Tab between fields. About 2 hours for 98 lines; group them and take breaks.
3. **Main hoop and front hoop first** (group `hoop`): Insert > Weldments > Structural Member. Standard iso, Type tube_round, Size 25.4x2.4. Select the hoop lines as one group (MH_L-MH_M, MH_M-MH_B, MH_B-MH_T, MH_T cross, and the mirrored legs). Tick "Apply corner treatment", end miter. Tick "Merge arc segment bodies" **verify** name. The bend at MH_B is a sharp corner in the skeleton; real hoops are bent with R 76 mm minimum. Add the bend radius with a Sketch Fillet on the skeleton line pair before creating the member, or accept the sharp corner for v1 and note it.
4. **Hoop braces** (`hoop_brace`): second Structural Member, same size, lines MH_T-RT2, MH_B-RT1, MH_T-RT1, FS2_U-FH_T, FH_T-MH_B. Corner treatment: end trim against the hoops happens in step 7.
5. **Side impact and bulkhead** (`sis`, `bulkhead`): 25.4x1.6.
6. **Front and rear boxes** (`front`, `rear`): 25.4x1.6, one Structural Member per group of up to about 20 lines (large groups get slow and the corner-treatment dialog becomes unmanageable).
7. **Trim.** Insert > Weldments > Trim/Extend. Trim the secondary tubes against the hoops and the main rails ("Bodies to be trimmed" = the group, "Trimming boundary" = the hoop bodies, tick "Allow extension"). Do this group by group; one big trim fails silently on tangent cases.
8. **Suspension pickup tabs**: skip in v1. The wishbone inboard points sit on the tube centreline nodes; the assembly mates to the layout's HP points, not to tabs.
9. **Weldment cut list**: Insert > Weldments > Weldment (if not already created automatically) gives the cut list in the tree. Right-click > Update. The cut list is your tube length table; check its total against `frame_tubes.csv` (35.4 m before trimming; after trimming a little less).
10. Material: Plain Carbon Steel or AISI 1020 on the whole part. Mass Properties: expect 34 to 38 kg.

## Naming

Structural members: `SM_hoops`, `SM_braces`, `SM_sis`, `SM_bulkhead`, `SM_front`, `SM_rear`. Trim features `Trim_<group>`.

## Mates in the assembly

The chassis is the fixed component? No: fix the master layout and mate the chassis to it with three coincident mates between the layout's GROUND, CENTRE, FRONT_AXLE planes and the chassis' own three planes. Everything then sits in the car frame.

## Configurations

`Default` only.

## Beginner mistakes

- Picking lines from two different sketches into one Structural Member: not allowed. All 98 lines in one 3D sketch.
- Lines that meet at a node but do not share the endpoint (two separate points 0.1 mm apart): the corner treatment refuses to miter and the beam mesh later shows a disconnected node. The macro shares endpoints by construction; by hand, snap to the existing endpoint (yellow coincident icon).
- Letting SolidWorks apply the profile with the wrong orientation on a bent group: irrelevant for round tubes, so ignore the "locate profile" option.
- Trimming everything against everything: creates hundreds of tiny bodies and a 10-minute rebuild. Trim secondary against primary only.
- Rebuild time: a 98-member weldment with corner treatment rebuilds in 10 to 30 s. Turn off "Verification on rebuild" (Tools > Options > Performance) and do not add cosmetic fillets.

## Fallback

If the weldment fights you past about 8 hours: model the hoops and braces as weldments (12 tubes) and the rest as a single lofted "tub" solid between the bulkhead, front hoop and main hoop sections (Insert > Boss/Base > Loft through three rectangles with 30 mm corner fillets, then Shell 3 mm). State it in `docs/log.md`. The torsion study then uses a solid mesh on the tub.

## End-of-part check

- Rebuild with zero errors; cut list updates; total cut length within 5 % of `frame_tubes.csv`.
- Tools > Evaluate > Check: one body per tube (no stray fragments).
- The frame outline matches `media/frame_layout.png` in side and top view.
- Mass between 30 and 40 kg.
- `SaveStandardViews` run; iso view into the log.
