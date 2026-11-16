# 03 Bracket by Extrude, Cut and Hole Wizard (45 min)

Goal: an L-shaped steel bracket (think of a brake caliper bracket bolted to the hub) using the three features you will use most: Extruded Boss, Extruded Cut and the Hole Wizard. Mass checked by hand.

## Geometry

- Base plate 100 x 50 x 6 mm.
- Flange standing up along one 50 mm edge: 50 wide, 40 tall overall (34 above the plate), 6 thick.
- Two M8 clearance holes in the plate, 60 mm apart, on the plate's centreline, symmetric about the middle.
- One D 20 through hole in the flange, centred.
- Material Plain Carbon Steel (7800 kg/m3 in the SolidWorks library; AISI 1020 is 7900). Use **Plain Carbon Steel** so the hand number below matches.

## Steps

1. New part, MMGS, save as `cad/practice/bracket.SLDPRT`.
2. **Plate**: sketch on the **Top Plane** (horizontal, so the plate lies flat). Sketch > **Center Rectangle** from the origin; dimension `100` x `50`. Fully Defined. Exit. Features > **Extruded Boss/Base**, Blind, `6`, direction upward (flip with the arrows icon if it goes down; it does not matter for the mass). Rename `Sketch_plate`, `Extrude_plate`.
3. **Flange**: click the plate's top face > Sketch. Ctrl+8. Draw a rectangle along one short edge: use Sketch > Corner Rectangle starting at a corner of the plate (it snaps) and dimension `6` wide (the flange thickness, inward from the edge) and `50` along the edge; or use **Convert Entities** on the short edge and offset it. Exit. **Extruded Boss/Base**, Blind, `34`, upward. Tick **Merge result** (default) so it is one body. Rename `Sketch_flange`, `Extrude_flange`.
4. **Flange hole**: click the flange's outer face > Sketch. Ctrl+8. Circle, diameter `20`, centre dimensioned `25` from the plate's side edge and `20` above the plate's top face? The flange is 40 tall overall: centre the hole at 17 mm above the plate top (plate 6 + 17 = 23 from the bottom; the flange top is at 40; that leaves 20 - 10 = 7 mm of material above the hole, fine for practice). Dimension: `25` from the side, `23` from the bottom face (select the bottom edge in the view, or dimension to the Top Plane via the tree flyout). Exit. Features > **Extruded Cut**, Through All. Rename `Cut_flange_hole`.
5. **Hole Wizard** (the M8 clearance holes): Features > **Hole Wizard**. In the PropertyManager:
   - Hole Type: **Hole** (the plain cylinder icon, not Counterbore, not Tap). Standard **ISO**. Type **Drill sizes**? No: Type **Screw Clearances**, Size **M8**, Fit **Normal** (gives D 9.0; Close gives 8.4, Loose 10). **verify** the exact diameters in your library; the hand check below assumes 9.0.
   - End Condition: Through All.
   - Click the **Positions** tab at the top of the PropertyManager. Click the plate's top face: you are now in a sketch placing points. Click twice roughly where the holes go, press Esc to stop placing, then dimension the two points like sketch points: `60` between them, each on the plate's long centreline (add a Horizontal relation between the two points, and dimension the first point `20` from the plate's end and `25` from the long edge). Tick.
   - Rename the feature `HW_M8_clearance`. Expand it in the tree: it has two sketches, the 3D hole sketch and the position sketch. Edit the position sketch (right-click > Edit Sketch) if the holes land in the wrong place.
6. **Fillet** the two inside corners where the flange meets the plate? Not for the mass check. Skip, or add Fillet R 3 on the four outer vertical edges of the plate and accept a slightly lower mass (-4 x (1 - pi/4) x 3^2 x 6 = -46 mm^3, negligible: 0.4 g).
7. Material: right-click Material > Edit Material > Steel > **Plain Carbon Steel**.
8. Ctrl+S.

## Expected result

Hand volume:

| Part | Volume |
|---|---|
| plate 100 x 50 x 6 | 30,000 mm^3 |
| flange 50 x 34 x 6 | 10,200 mm^3 |
| flange hole pi/4 x 20^2 x 6 | -1,885 mm^3 |
| two M8 clearance holes 2 x pi/4 x 9^2 x 6 | -763 mm^3 |
| total | 37,552 mm^3 |
| mass at 7800 kg/m3 | **0.293 kg** (293 g) |

## Check

- Mass Properties: 293 g (plus or minus 3 g). If it reads 285 g the flange hole is bigger or the fit was Loose; if 297 g, Close fit (8.4). Match the hand table to whatever your library gives and note it.
- Measure the two Hole Wizard holes centre to centre: 60.00.
- Evaluate > Check: one body.
- Section view (Heads-up toolbar > Section View, Front Plane) through a hole: the hole is cylindrical, no counterbore.

## Why Hole Wizard and not a circle cut

A Hole Wizard hole knows it is an M8 clearance hole: it carries the standard, the size and the fit, it shows up correctly in drawings and in Toolbox fasteners, and it can be re-sized by changing M8 to M10 in one dialog. In the car, every bolted joint (wishbone rod ends, rocker pivots, hub studs, wing mounts) uses it.
