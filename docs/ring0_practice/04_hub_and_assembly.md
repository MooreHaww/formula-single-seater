# 04 Hub, then the first assembly: rim + hub + bracket (60 min)

Goal: a hub that fits the rim's bore and bolt circle, with tapped holes for the bracket; then an assembly with the three parts mated the way the real wheel corner will be mated.

## Part A: hub (20 min)

Geometry (aligned with `docs/cad_playbook/05_hub.md`, simplified): flange D 130 x 10, spigot D 64 x 20 on the outboard side (fits the rim's 64 bore), body D 80 x 50 on the inboard side, four D 10.5 stud holes on PCD 100 through the flange, two M8 tapped holes 15 deep in the inboard end face of the body, 60 apart.

1. New part, MMGS, save `cad/practice/hub.SLDPRT`.
2. Sketch on the **Front Plane** (same plane as the rim, so the axis is Y again): a centreline up from the origin; the half-profile as one closed polyline to the right of it. Points, going round from the axis at the inboard end: (0, -60) is the body's inboard face on the axis... Easier: draw three rectangles side by side along the axis and dimension them, then Trim the shared edges, like the rim. Radii from the centreline: body `40` from Y = -60 to Y = -10, flange `65` from Y = -10 to Y = 0, spigot `32` from Y = 0 to Y = +20. The flange's outboard face is at Y = 0 (the wheel's mounting face): in the assembly it meets the rim's disc face, which sits at Y = +40 in the rim; the mate will handle the offset. Fully define. Exit. Rename `Sketch_hub_profile`.
3. **Revolve** 360 about the centreline. Rename `Revolve_hub`.
4. **Stud holes**: sketch on the flange's outboard face (the ring face at Y = 0 between R 32 and R 65): circle D `10.5` at `50` from the origin on the vertical. Extruded Cut, Blind `10` (through the flange only; Through All would also cut the body, which is fine too but then the hand mass changes). Circular Pattern x 4. Rename `Cut_stud_hole`, `Pattern_stud_holes`.
5. **Tapped holes**: Hole Wizard, Hole Type **Straight Tap**, Standard ISO, Type Tapped hole, Size **M8**, End Condition Blind, depth `15` (thread depth: let it follow; **verify** the dialog labels "Blind hole depth" and "Thread depth"). Tick "Cosmetic thread" with "With thread callout" so drawings show it (**verify** option names in 2026, where thread display may be under Document Properties > Drafting Standard > Annotations > Cosmetic Thread). Positions tab: click the body's inboard end face (the D 80 face at Y = -60); place two points; dimension them `30` either side of the origin on the horizontal (so 60 apart) and on the horizontal centreline (Horizontal relation to the origin). Tick. Rename `HW_M8_tapped`.
6. Material: Aluminium Alloys > **7075-T6 (SN)** (2810 kg/m3).
7. Ctrl+S.

Hand volume: body pi/4 x 80^2 x 50 = 251,327; flange pi/4 x 130^2 x 10 = 132,732; spigot pi/4 x 64^2 x 20 = 64,340; stud holes -4 x pi/4 x 10.5^2 x 10 = -3,464; tapped holes modelled at the tap drill D 6.8 x 15: -2 x pi/4 x 6.8^2 x 15 = -1,089. Total 443,846 mm^3 -> **1.247 kg** at 2810. (If Hole Wizard models the tapped hole at the nominal D 8, the mass is 3 g lower; either is fine.)

Check: Mass Properties 1.245 kg (plus or minus 10 g). Check: one body.

## Part B: the assembly (40 min)

1. File > New > **Assembly**. The **Begin Assembly** PropertyManager opens with a Browse button. Browse to `cad/practice/hub.SLDPRT`, Open, then click the green tick (**not** in the graphics area): the hub lands with its origin on the assembly origin and is **fixed** (`(f)` prefix in the tree). The first part should always be the one the others attach to; here the hub plays the role the upright plays in the real corner. Save as `cad/practice/wheel_corner.SLDASM`.
2. Assembly tab > **Insert Components** > Browse > `rim.SLDPRT` > click anywhere in the graphics area to drop it. It is free (`(-)` prefix). Same for `bracket.SLDPRT`.
3. Assembly tab > **Mate**. The Mate PropertyManager stays open while you add several mates. For each mate: select two faces, SolidWorks proposes the obvious mate type, tick to accept.
   - **Rim to hub, concentric**: click the rim's bore (the 64 mm cylindrical face) and the hub's spigot (the 64 mm cylindrical face). Proposed: Concentric. Tick. The rim jumps onto the axis.
   - **Rim to hub, coincident**: the rim's disc **inboard** face (the face of the 6 mm disc facing -Y, at Y = 34 in the rim's frame) and the hub flange's **outboard** face (Y = 0 in the hub's frame). Proposed: Coincident. Tick. If the rim ends up inside the hub pointing the wrong way, click the **Flip Mate Alignment** (Aligned / Anti-aligned) icon in the mate dialog. Rotate the view: the rim's disc now sits on the hub flange, spigot inside the bore. **verify** the alignment icon's 2026 name; it is the pair of arrows in the Standard Mates box.
   - **Rim to hub, one stud hole**: a stud hole in the rim concentric to a stud hole in the hub. Proposed: Concentric. Tick. The rim can no longer spin. (Real wheels are free to spin on the bearing; in the real assembly this third mate is left out on purpose for the Motion study and the hub rotates on the upright instead.)
   - **Bracket to hub**: one M8 clearance hole (bracket) concentric to one M8 tapped hole (hub); the bracket's plate **bottom face** coincident to the hub's inboard end face; the second clearance hole concentric to the second tapped hole. Three mates, the bracket is fully placed.
4. Close the Mate dialog (tick or Esc). The tree's **Mates** folder lists six mates; rename them if you like (`Concentric_rim_spigot`, ...). Every component now reads without `(-)`, except: the Status bar may still show "Under Defined" if the rim's third mate was skipped; that is expected.
5. Evaluate > **Interference Detection** > Calculate: expect **no interference** (the spigot is 64 in a 64 bore: SolidWorks reports coincident faces, not interference; if the bracket's flange pokes into the hub body, that is a real interference and tells you the bracket orientation is wrong: flip it with the alignment icon on the coincident mate).
6. Evaluate > **Mass Properties** on the whole assembly: sum of the three parts, 3.286 + 1.247 + 0.293 = **4.826 kg**.
7. Drag the rim with the left button: it should not move (fully mated). Suppress the third rim mate (right-click > Suppress): now it spins when dragged. Unsuppress.
8. Ctrl+S. Then File > **Pack and Go** (**verify**: under File in 2026, or Tools > Pack and Go in older versions) just to see it: it is how you hand a whole assembly with its parts to someone else; cancel it.

## Expected result

Rim on hub, bracket bolted to the back of the hub, 4.83 kg, no interference, six mates, every component fully defined.

## Check

- Mass Properties of the assembly: 4826 g (plus or minus 20 g).
- Interference Detection: 0 interferences.
- Measure: rim's outboard disc face to hub flange outboard face = 6.00 (the disc thickness), spigot end inside the rim.
- Rotate to Ctrl+1 (Front): you see the ring from the side, hub axis horizontal across the screen? No: the axis is Y, which is vertical in the Front view. Ctrl+5 (Top) looks down the axis: four stud holes line up.

## Lessons for the real car

The real corner uses the same three kinds of mate (Concentric on a cylinder, Coincident on a face, Concentric on a hole), but between the **upright** and the layout's hardpoints, and the rim is mated to the hub which is mated to the upright. Mates to faces break when a face is removed by a later edit; mates to **reference geometry** (planes, axes, reference points) survive, which is why the playbook mates to the master layout's named planes and `HP_*` points wherever it can.
