# 05 Hub (`cad/suspension/hub.SLDPRT`)

The rotating part between the upright bearings and the rim. One part for all four corners; the rear hub has a splined bore for the halfshaft, which v1 ignores (same file, the bore is a plain hole).

## Inputs

Bearing: 7206 pair, 30 mm journal, bearing centre at the wheel centre. Rim: 4 x M10 studs on a 100 mm PCD (`rim_pcd`, add 100 to `car_params.txt` if you want it linked), centre bore 64 mm, flange face 40 mm outboard of the wheel centre (`rim_offset`, add 40). All along the wheel axis.

## Feature order

1. Template, insert the layout, convert the wheel axis line (or redraw it by equations) into sketch `axis`.
2. **Sketch `profile`** on a plane that contains the wheel axis (plane through the axis and the CENTRE plane normal: Insert > Reference Geometry > Plane, first reference the axis line, second reference the GROUND plane with "Parallel"? Simpler: plane through the axis line and a point on it displaced in Z). Draw the half-section as a closed polyline: journal D 30 x 36 long centred on the wheel centre, shoulder D 36, flange D 120 x 10 thick at 40 mm outboard, centre spigot D 64 x 8 proud of the flange, inboard a D 40 x 20 stub.
3. Insert > Boss/Base > Revolve about the axis, 360.
4. **Stud holes**: sketch on the flange outboard face, a circle D 10.5 at R 50, Circular Pattern 4 (Insert > Pattern/Mirror > Circular Pattern, axis = the wheel axis). Cut-Extrude through the flange.
5. **Bore**: D 20 through, for the halfshaft on the rear (plain in v1).
6. Chamfers 1 mm on the journal ends.
7. Material 7075-T6. Mass about 0.35 kg.

## Mates

Journal Concentric to the upright bearing bore (this is the revolute joint the wheel spins on); flange plane Coincident to a plane through the wheel centre offset 40 (make that offset plane in the hub, not the upright). Rim: centre bore Concentric to the spigot, rim mounting face Coincident to the flange face, one stud hole Concentric to a rim hole to clock it.

## Configurations

`Default`.

## Beginner mistakes

- Revolving a profile that crosses the axis: the revolve fails with "self-intersecting". Keep the profile on one side of the axis line and use the axis line as a centreline (construction) entity.
- Putting the flange on the wrong side: the flange face is outboard (toward +Y on the right side); the rim bolts to it from outside.
- Forgetting mid-plane symmetry: the bearing centre must be the wheel centre, otherwise the upright's bore and the hub's journal are offset and the rim ends up 20 mm out.

## End-of-part check

- The flange face is 40 mm outboard of the wheel centre (Measure).
- Four stud holes on a 100 PCD (Measure between opposite holes = 100).
- Revolve is one body; mass under 0.5 kg.
