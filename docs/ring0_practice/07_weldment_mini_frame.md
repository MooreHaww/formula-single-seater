# 07 Mini 3D-sketch weldment frame (90 min)

Goal: a 400 x 300 x 250 mm box of 25.4 x 1.6 steel tube with one diagonal, built the way the chassis will be built: 3D sketch of centrelines, a weldment profile, Structural Member, corner treatment, cut list. The chassis in `docs/cad_playbook/02_chassis.md` is the same with 98 lines instead of 13.

## Part A: the tube profile (20 min, once)

Weldments pick the tube section from a library of profile sketches. The library has round tubes in inches and some ISO sizes but not 25.4 x 1.6; make it.

1. Tools > Options > System Options > File Locations > show folders for **Weldment Profiles**. Note the folder (typically `C:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\lang\english\weldment profiles`, **verify** for 2026; the Student edition may put it under `...\SOLIDWORKS Student Edition\...`). You can add the repo's own folder instead: Add > `cad/templates/weldment_profiles/`, which keeps the profiles in git. Do that.
2. Inside that folder make the three-level structure the Structural Member dialog expects: `iso\tube_round\` (Standard \ Type \ files). The size is the file name.
3. New part (MMGS). Sketch on the **Front Plane**: a circle D `25.4` and a circle D `22.2` (25.4 - 2 x 1.6), both centred on the origin. Fully defined. Exit the sketch.
4. **Select the sketch in the tree**, then File > Save As > Save as type **Lib Feat Part (*.sldlfp)** > `cad/templates/weldment_profiles/iso/tube_round/25.4x1.6.sldlfp`. **verify**: selecting the sketch before Save As is what turns it into the library feature (the tree then shows an "L" on the sketch icon). If the Structural Member dialog later does not list the size, open the `.sldlfp`, right-click the sketch > **Add to Library**, save again.
5. Repeat with inner D `20.6` for `25.4x2.4.sldlfp` (the hoops' wall), 5 minutes.

## Part B: the 3D sketch (25 min)

1. New part from the car template (or MMGS). Save `cad/practice/mini_frame.SLDPRT`.
2. Sketch tab > Sketch drop-down > **3D Sketch** (or Insert > 3D Sketch). The graphics area shows a small XYZ triad at the cursor. Press **Tab** to cycle the sketching plane (XY, YZ, ZX): the triad changes; the status bar shows which plane you are on.
3. **Bottom rectangle** on the ground plane: with the Line tool, click near the origin and draw four lines in a loop. Lines snap to the current plane; use Tab to stay on XY (if your template's GROUND is the Top plane, the ground plane is **ZX** in 3D-sketch terms, **verify**: Tab to the plane whose triad lies flat).
   The reliable way to get exact coordinates: draw the four lines roughly, then select each endpoint and type its X, Y, Z in the PropertyManager's **Parameters** box (the point's coordinates appear when you click a point). Set the corners to (0, 0, 0), (400, 0, 0), (400, 0, 300), (0, 0, 300) with Y up (the second number) if Y is vertical in this part, else (0, 0, 0), (400, 0, 0), (400, 300, 0), (0, 300, 0) with Z up. The exact axis does not matter for the exercise; it matters for the chassis, whose CSV is in car coordinates (x rearward, y right, z up), see `cad/frame/frame_nodes.csv`.
   Alternatively Smart Dimension the lines: `400`, `300`, and dimension the first corner to the origin: `0` is not accepted, so drag the first corner onto the origin until the coincident icon shows.
4. **Four uprights**: from each corner, a line straight up `250`. Hold the line vertical: press Tab until the triad plane contains the vertical axis, and watch for the vertical inference line. Dimension each to 250, or type the top point's coordinates.
5. **Top rectangle**: join the four top points with four lines. Click exactly on the existing endpoints (the yellow/orange coincident symbol must appear); otherwise you get two points 0.1 mm apart, which is the single most common weldment failure (the corner treatment refuses and the beam mesh later has a loose node).
6. **One diagonal** from (0, 0, 0) to (400, 250, 0) (or the Z-up equivalent), in one side face.
7. Status bar: Fully Defined would need every point positioned; with coordinates typed, everything is black. Twelve edges plus one diagonal = 13 lines. Exit the 3D sketch. Rename it `FRAME_SKELETON`.

## Part C: Structural Members (30 min)

1. Right-click a CommandManager tab > tick **Weldments** to show the tab.
2. Weldments > **Structural Member**. Standard: `iso`, Type: `tube_round`, Size: `25.4x1.6` (from Part A; if the lists are empty the File Locations entry did not take, re-check it and restart SolidWorks).
3. **Group 1**: click the four bottom lines. Apply corner treatment: ticked, **End Miter**. The preview shows four mitred tubes. Click **New Group**.
4. **Group 2**: the four uprights. Corner treatment is between members of a group; the uprights do not touch each other, so no corner treatment here, but at their ends they overlap the bottom and top tubes, which is handled by Trim later. New Group.
5. **Group 3**: the four top lines, End Miter. New Group.
6. **Group 4**: the diagonal. Tick.
   **verify** the limit "a group's segments must be connected end to end or parallel"; if SolidWorks refuses a group, split it. Rename the feature `SM_box`. The tree also gets a **Cut list** folder and a `Weldment` feature.
7. **Trim/Extend**: Weldments > **Trim/Extend**. Corner type: End Trim. Bodies to be trimmed: the four uprights. Trimming boundary: Bodies, pick the four bottom tubes and the four top tubes. Tick "Allow extension". Tick. The uprights now stop at the surfaces of the rails instead of passing through them. Repeat for the diagonal against its two end tubes. Rename `Trim_uprights`, `Trim_diagonal`.
8. **Cut list**: right-click the Cut list folder > **Update**. Expand it: items grouped by identical length. Right-click > Properties shows LENGTH per item (**verify** property name `LENGTH`, set by the profile's library feature).
9. Material: Steel > **Plain Carbon Steel** (7800) or AISI 1020 (7900). `frame_layout.m` uses 7850; use Plain Carbon Steel and accept a 0.6 % difference.
10. Ctrl+S.

## Expected result

A box frame of 13 tubes. Centreline lengths: bottom 2 x (400 + 300) = 1400, top 1400, uprights 4 x 250 = 1000, diagonal sqrt(400^2 + 250^2) = 471.7; total **4,271.7 mm** before trimming. Tube section area pi/4 x (25.4^2 - 22.2^2) = 119.6 mm^2, so 0.0120 kg per 100 mm... as a number: 119.6 mm^2 x 4,271.7 mm = 510,900 mm^3 -> **3.99 kg at 7800** before the trims; the mitres and end trims remove a few percent, expect **3.7 to 4.0 kg**.

## Check

- Cut list: 13 bodies (or fewer rows, since equal lengths group: 400 x 4, 300 x 4, 250 x 4, 471.7 x 1 -> 4 rows). The LENGTH of the uprights after trimming is 250 - 25.4 = 224.6 (they sit between two 25.4 tubes, **verify** whether the cut list reports the trimmed or the centreline length).
- Mass Properties 3.7 to 4.0 kg.
- Evaluate > Check: 13 bodies, no errors. (A weldment part is **multibody** on purpose: one body per tube; this is the exception to the "one body" rule.)
- Section View through a corner: the mitre is a clean 45 degree joint with no overlap.
- Save, then in the FeatureManager right-click `FRAME_SKELETON` > Edit Sketch, drag one top corner 50 mm sideways, exit: the tubes follow, the cut list updates after a right-click > Update. Undo.

## What the chassis adds on top of this

98 lines from `cad/frame/frame_tubes.csv` placed by the `ImportFrameNodes` macro (exercise 8) instead of by hand; six groups by tube role; two wall thicknesses; a bend radius on the hoops; trimming group by group. The habits that matter are all here: shared endpoints, small groups, trim secondary against primary, update the cut list, compare its total length with the CSV.
