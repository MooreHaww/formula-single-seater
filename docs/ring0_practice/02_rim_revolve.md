# 02 Rim by Revolve (60 min)

Goal: the car's 10 inch rim as a solid of revolution, with stud holes, in 6061, with a hand-checked mass. This file is kept and becomes `cad/suspension/rim.SLDPRT` after exercise 5 links it to the parameter file.

Numbers used (from `params/car_params.txt`): `rim_diameter` 254, `rim_width` 178. Hub interface (from `docs/cad_playbook/06_wheel.md`): centre bore 64, PCD 100, 4 x D 10.5 stud holes, mounting face 40 mm outboard of the wheel centre.

The practice profile is deliberately simplified (a plain barrel and a flat disc) so that the mass can be computed by hand. The real rim gets bead seats and a lip in Ring 2.

## Steps

1. **New part**, MMGS (exercise 1 section 4). Save as `cad/practice/rim.SLDPRT`.
2. **Sketch** on the **Front Plane**. (Front is XY; the revolve axis will be the sketch's vertical Y axis, so the wheel axis ends up along Y, which is the car's lateral direction. That is the convention the playbook wants: width along Y.)
3. Draw the **centreline** first: Sketch tab > Line drop-down > **Centerline**, from the origin straight up (hold the cursor until the vertical inference line shows) about 200 mm. Esc. Right-click it > nothing; it is already construction geometry.
4. Draw the **barrel**: a rectangle (Sketch > Corner Rectangle) to the right of the centreline, roughly 7 mm wide and 178 tall. It must not touch the centreline. Dimension it (Smart Dimension):
   - horizontal distance from the centreline to the outer edge: `127` (= 254 / 2, the rim radius),
   - horizontal distance from the centreline to the inner edge: `120`,
   - height: `178`,
   - vertical distance from the origin to the bottom edge: `89` (so the barrel is centred on the origin; the wheel centre is the origin).
5. Draw the **disc**: a second rectangle inside the barrel, from the inner barrel edge inward to the centre bore, 6 mm tall. Dimension: inner edge from the centreline `32` (centre bore 64 / 2), height `6`, and the position of its **outboard face**: `40` above the origin (the mounting face is 40 mm outboard of the wheel centre; "outboard" here is +Y, the top of the sketch). The disc's outer edge must coincide with the barrel's inner edge: drag it onto the barrel line until the coincident icon appears, or add a Coincident relation (select both lines with Ctrl, PropertyManager > Add Relations > Coincident). Trim the overlapping line between the two rectangles: Sketch > **Trim Entities** > Power trim, drag across the segment of the barrel's inner edge that lies inside the disc so that the profile is one closed loop. **verify**: Revolve also accepts two closed regions ("contours") if you prefer not to trim; select both in the Revolve dialog's Selected Contours box.
6. Status bar must say **Fully Defined**. If it says Under Defined, something is blue: usually the rectangle's position along Y. Add the missing dimension.
7. Exit the sketch. Rename it `Sketch_rim_profile`.
8. Features > **Revolved Boss/Base**. Axis of Revolution: click the centreline. Direction 1: Blind, `360`. Tick. Rename to `Revolve_rim`. Ctrl+7, F: a ring with a disc inside.
9. **Stud holes**: click the outboard face of the disc (the flat face facing +Y). Sketch. Ctrl+8 (Normal To). Draw a circle, dimension its diameter `10.5`; dimension its centre `50` from the origin along the vertical (PCD 100 / 2) and on the vertical centreline (add a Vertical relation between the circle centre and the origin: Ctrl-select both, Add Relations > Vertical). Exit. Features > **Extruded Cut**: Through All. Rename `Cut_stud_hole`.
10. Features > Linear Pattern drop-down > **Circular Pattern**. Pattern Axis: expand the tree in the graphics area (the small + at the top left) and pick `Revolve_rim`'s axis, or View > Hide/Show > Temporary Axes and click the axis through the centre. Equal spacing, `360`, instances `4`. Features to Pattern: `Cut_stud_hole`. Tick. Rename `Pattern_stud_holes`.
11. **Material**: right-click Material > Edit Material > Aluminium Alloys > **6061 Alloy** (2700 kg/m3) > Apply, Close.
12. Ctrl+S.

## Expected result

A ring 254 outer diameter, 240 inner, 178 wide, with a 6 mm disc whose outer face is 40 mm from the centre, a 64 mm bore and four 10.5 mm holes on a 100 mm circle.

Hand mass:

| Part | Volume |
|---|---|
| barrel: pi/4 x (254^2 - 240^2) x 178 | 966,870 mm^3 |
| disc: pi/4 x (240^2 - 64^2) x 6 | 252,132 mm^3 |
| four holes: 4 x pi/4 x 10.5^2 x 6 | -2,078 mm^3 |
| total | 1,216,924 mm^3 |
| mass at 2700 kg/m3 | **3.286 kg** |

## Check

- Evaluate > **Mass Properties**: mass 3286 g (plus or minus 5 g). Centre of mass: X 0, Z 0, Y a little positive (the disc is outboard): hand value Y = (252,132 - 2,078) x 37 / 1,216,924 = 7.6 mm (disc centroid at 40 - 3 = 37 mm).
- Evaluate > **Measure**: click the outboard disc face and the origin? Simpler: Measure the distance between the disc's two faces = 6, and between the outboard face and the Right Plane = 40.
- Evaluate > **Check**: one solid body, no errors.
- Tree reads: Sketch_rim_profile, Revolve_rim, Cut_stud_hole, Pattern_stud_holes, Material 6061.

## Mistakes this exercise is designed to make you meet

- Profile touching the centreline: Revolve makes a solid cylinder instead of a ring. The inner edge stays at 120 (barrel) and 32 (bore).
- Dimensioning to the sketch origin instead of to the centreline: works here because they coincide, but in the real rim the centreline will be the layout's wheel axis; get used to dimensioning radii from the centreline.
- Forgetting to centre the barrel on the origin (step 4, the `89`): the wheel centre is then not at the origin and every mate in exercise 4 is off by 89 mm.
