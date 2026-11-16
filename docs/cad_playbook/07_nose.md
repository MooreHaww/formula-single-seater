# 07 Nose (`cad/body/nose.SLDPRT`)

A lofted shell from the nose tip to the front bulkhead and on to the front hoop. Carbon look, 2 mm thick. It is the hardest surface on the car, so it is deliberately a loft through four simple sections, not a sculpted surface.

## Inputs

`nose_overhang` 650 (tip at X = -650), front bulkhead at X = -300 (400 wide x 300 high, tube centres at Y +-200, Z 80 and 380), front hoop at X = `front_hoop_x` 650, cockpit opening from X = 650 (`cockpit_opening_length` 700, `cockpit_opening_width` 400), driver legs envelope (Y +-190, Z 150 to 430 from X = 200). The layout's `BODY_SECTIONS` sketches hold the sections; build them there first (`01_master_layout.md` step 9) and convert them here.

## Sections (each a closed sketch on a plane parallel to FRONT_AXLE)

| X (mm) | Shape | Size (W x H, mm) | Bottom Z |
|---|---|---|---|
| -650 (tip) | rounded rectangle, corner R 40 | 160 x 120 | 160 |
| -450 | rounded rectangle, R 60 | 320 x 240 | 100 |
| -300 (bulkhead) | rounded rectangle, R 60 | 460 x 360 | 60 |
| 150 | rounded rectangle, R 80 | 560 x 470 | 60 |
| 650 (front hoop) | rounded rectangle, R 90, top cut flat at Z 600 | 640 x 540 | 60 |

Heights are to the top; the bulkhead section wraps the 400 x 300 tube rectangle with 30 mm of clearance. The impact attenuator (not modelled) would sit between -650 and -300.

## Feature order

1. Template, insert the layout (sketches). Five sketches `S_tip`, `S_450`, `S_bulkhead`, `S_150`, `S_hoop` by Convert Entities from `BODY_SECTIONS` (or redraw, dimensions above; use centreline symmetry: draw the right half and Mirror Entities in the sketch so the section stays symmetric).
2. **Guide curves**: on CENTRE a spline for the top line through the section tops and a straight line for the bottom; on GROUND a spline for the side (max half-width) line. Three guides.
3. Insert > Boss/Base > Loft: profiles in order tip to hoop, guide curves the three splines, Start/End constraints "Normal to profile" at the tip (gives a rounded nose), "None" at the hoop. Tick "Merge tangent faces". Thin feature off (solid loft).
4. **Cockpit opening**: Cut-Extrude from GROUND? No: sketch on a plane at Z = 600 (parallel to GROUND): a rounded rectangle `cockpit_opening_length` x `cockpit_opening_width` from X = `front_hoop_x` rearward, corner R 100; Cut-Extrude "Through all" downward to Z 150 (depth 450). This opens the top between the hoops; the nose part ends at the front hoop plane, so the cut only takes the last 50 mm here and the sidepod part takes the rest. Simpler: make the nose end at X = 650 and have no cockpit cut here at all. Do that.
5. **Shell**: Insert > Features > Shell, thickness 2 mm, remove the rear face (the X = 650 section) so the nose is a hollow skin open at the back.
6. **Front wing mounts**: two pylons? Not in the nose: the front wing mounts to the bulkhead with two struts (`10_front_wing.md`). Skip.
7. Appearance: carbon fibre (Appearances > Composites) for renders, material custom 1600 kg/m3. Mass about 2 kg.

## Mates

Coincident: the nose's three named planes to the layout's. The nose is already in position.

## Configurations

`Default`.

## Beginner mistakes

- Loft twisting: the profiles' start points (the small green dot) must line up. If the loft looks twisted, right-click the profile handle and drag it to the top-centre point of each section, or add the top-line guide curve first.
- Guide curve not touching the profiles: a guide must pierce every section (use Pierce relations in the sketch; if the spline does not pass through a section's top point, add a Pierce or coincidence to it).
- Shelling after adding fillets with radius smaller than the thickness: the shell fails. Shell first, fillets never (the loft is already smooth).
- Lofting from a tip point: SolidWorks can loft to a point, but the tangency is poor; a 160 x 120 end section is better.

## End-of-part check

- Loft rebuilds, no "zebra stripes" discontinuity at the sections (View > Display > Zebra Stripes).
- Shell gives one body; Check reports no open edges except the rear face.
- Section at X = -300 clears the bulkhead tubes by 30 mm (Measure).
- Mass 1.5 to 2.5 kg.
