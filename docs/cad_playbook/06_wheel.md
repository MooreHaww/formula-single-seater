# 06 Wheel (`cad/suspension/rim.SLDPRT`, `cad/suspension/tyre.SLDPRT`)

The rim is the Ring 0 practice part, kept. The tyre is a simple solid of revolution with a flat contact patch so the CFD body meshes.

## Inputs

`rim_diameter` 254, `rim_width` 178, `tyre_od` 457, `tyre_width` 180, `tyre_rolling_radius` 222 (used for the flat), hub flange: PCD 100, 4 holes D 10.5, centre bore 64, offset 40.

## Rim: feature order

1. Template. The rim is built in its own local frame? No: like everything else, in car coordinates for the **front right** wheel, so that the same mates work everywhere. The wheel axis is the layout's wheel axis; the part can still be reused on all four corners because the mates place it.
2. **Sketch `rim_profile`** on a plane containing the wheel axis: half-section of a 10 inch rim: bead seats at R 127 (`="rim_diameter"/2`), outer lip R 140 x 8 wide, barrel R 120 between the seats, width `="rim_width"`, centre disc 6 mm thick at the offset position (40 mm outboard of the wheel centre), centre bore R 32.
3. Revolve 360 about the axis.
4. **Stud holes**: 4 x D 10.5 on PCD 100 through the centre disc, Circular Pattern.
5. **Spokes** (the practice part had a plain disc; keep it plain for CFD but cut 5 spoke windows for looks in a second configuration `spoked`): Cut-Extrude a rounded slot, Circular Pattern 5.
6. Material 6061-T6, mass 2.0 to 2.8 kg.

## Tyre: feature order

1. **Sketch `tyre_profile`** on the same kind of plane: half-section, a rounded rectangle from R 127 (bead) to R `="tyre_od"/2` (228.5), width `="tyre_width"`, shoulder radius 25, centred on the wheel centre.
2. Revolve 360.
3. **Flat**: Cut-Extrude a box below Z = 0 (the ground plane in car coordinates), i.e. remove everything under GROUND. The loaded tyre is then `tyre_rolling_radius` tall (228.5 - 6.5 = 222 **verify** that `tyre_od/2 - tyre_rolling_radius` gives the flat you want; the parameter file has 457/2 - 222 = 6.5 mm). The flat is what stops the CFD mesh from failing at a tangent contact.
4. Material custom "Rubber", density 1100 kg/m3. Mass about 3.5 kg.

## Mates

Rim: centre bore Concentric to the hub spigot, mounting face Coincident to the hub flange, one hole Concentric to a stud hole. Tyre: bead cylinder Concentric to the rim bead seat, mid-plane Coincident to the rim mid-plane (make a `MID` plane in both). The tyre's flat must stay on the ground: because the tyre is mated to the rim, which is on the hub, which is on the upright, the flat follows the suspension; in the Motion study the wheel is driven vertically so the flat is meaningless there, which is fine. In the CFD body the tyres are replaced by their static position anyway (`14_cfd_body.md`).

## Configurations

Rim: `Default` (plain disc) and `spoked`. Tyre: `Default`.

## Beginner mistakes

- Revolving the tyre with the profile touching the axis: it is a ring, keep the inner edge at the bead radius.
- Making the tyre OD from the rolling radius: the OD is unloaded (457); the rolling radius (222) is the loaded height and only sets the flat.
- Building the rim with width along the wrong axis: width is along the wheel axis (Y for the right-hand wheel), so the revolve profile's width direction is parallel to the axis.

## End-of-part check

- Tyre: Measure from the flat to the wheel axis = 222.
- Rim: mounting face 40 mm outboard of the wheel centre; Mass Properties 2 to 3 kg.
- Tools > Evaluate > Check: one body each.
