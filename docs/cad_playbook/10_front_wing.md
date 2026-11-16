# 10 Front wing (`cad/aero/fw_main.SLDPRT`, `fw_flap1.SLDPRT`, `fw_flap2.SLDPRT`, `cad/aero/front_wing.SLDASM`)

Three straight elements spanning `fw_span` 1600, each an extruded airfoil, plus endplates (`12_endplates.md`) and two mounting struts to the bulkhead. The element angles are the aero variant: B, C, D have their own angle sets, A has no wing.

## Inputs

`fw_span` 1600, `fw_main_chord` 400, `fw_flap1_chord` 220, `fw_flap2_chord` 160, `fw_ground_clearance` 60, `wing_element_gap` 14, `wing_element_overlap` 20, angles `fw_main_aoa_B/C/D`, `fw_flap1_aoa_*`, `fw_flap2_aoa_*`, `nose_overhang` 650. Airfoils: `cad/airfoils/fw_main.dat` (NACA 6412), `fw_flap1.dat` (8410), `fw_flap2.dat` (9409).

Position (from the layout's `FW_POSITION` sketch): main element leading edge at X = -600 (50 mm behind the nose tip so the wing does not stick out), lowest point of the main element at Z = `fw_ground_clearance` 60. Flap 1 leading edge sits `wing_element_overlap` 20 mm ahead of the main element's trailing edge in X and `wing_element_gap` 14 mm above it in Z (a slot gap); flap 2 the same relative to flap 1. Angles are measured from the ground line, positive nose-up at the trailing edge? **Convention**: angle of attack is positive when the trailing edge is **higher** than the leading edge for a downforce wing (the wing is upside down relative to an aircraft). The airfoil files are aircraft-style (camber up); the wing is **mirrored in Z** so the camber points down. Decide once in the FW_POSITION sketch and keep it.

## Feature order (fw_main; flaps identical with their own file and chord)

1. Template, insert the layout (sketches). The element is built in car coordinates for configuration C and rotated by configuration.
2. **Airfoil curve**: run `cad/macros/ImportAirfoil.bas` (untested) with `fw_main.dat` and chord 400. It makes a curve `Airfoil_fw_main_c400` on the Front plane (which in the template is FRONT_AXLE, the plane normal to X; **this is wrong for a wing**, whose section lies in the X-Z plane, i.e. on CENTRE). So either run the macro in a scratch part and copy the curve, or (simpler) use the `.sldcrv` file: Insert > Curve > Curve Through XYZ Points > Browse `cad/airfoils/fw_main.sldcrv`. The curve comes in with its X along the chord and its Y as the airfoil thickness direction, in the part's XY plane, which in the template is... **verify** which default plane the curve lands in and rotate the whole thing with Insert > Features > Move/Copy Body afterwards if needed. Cleanest alternative: draw the section sketch on CENTRE and use Convert Entities on the curve after inserting it as a 3D curve. Expect 20 minutes of fiddling here once; then the flaps are copies.
3. **Section sketch `profile`** on CENTRE: Convert Entities the curve, close the trailing edge with a short line, then Rotate Entities about the leading-edge point by `="fw_main_aoa_C"` (type the equation in the rotate dialog; **verify** that Rotate Entities accepts an equation: if not, add a construction chord line, dimension its angle to a horizontal construction line with the equation, and make the airfoil follow it with a Coincident on both ends). Mirror the profile in Z about the chord line if the camber points the wrong way (step 0 decision). Place the leading edge at (X -600, Z = 60 + the distance from the lowest point of the section to the LE, measured once and typed as a number, about 12 mm for a 400 chord 6412 at 6 deg).
4. Insert > Boss/Base > Extrude, Mid Plane, `="fw_span"` (1600). One body.
5. Material custom 1600 kg/m3, or shell 2 mm with no face removed if you want realistic mass (optional). Mass solid: about 7 kg; shelled: 1.5 kg. Use the shell.
6. **Configurations**: ConfigurationManager > add `B`, `C`, `D`. Configure Dimension on the angle: B `="fw_main_aoa_B"`, C `="fw_main_aoa_C"`, D `="fw_main_aoa_D"`. (Equations per configuration: in the Equations dialog each equation has a configuration drop-down; set "This configuration" when editing. **verify** the workflow in 2026.) Flap LE positions move with the main element's trailing edge, so in the flap parts the LE position is dimensioned to the main element's TE through the layout's FW_POSITION sketch, not typed.

## Front wing assembly

`front_wing.SLDASM`: insert fw_main, fw_flap1, fw_flap2, fw_endplate (x2, mirrored), two struts (D 20 tubes from the main element's top at Y +-150 to the bulkhead lower nodes at (-300, +-200, 80); make them as `fw_strut.SLDPRT`, a sweep along a line). All parts are in car coordinates, so every mate is three Coincident plane mates. Assembly configurations B, C, D select the part configurations.

## Beginner mistakes

- Extruding the airfoil from the wrong plane (profile on GROUND instead of CENTRE): the wing comes out as a vertical fin. The section is in the X-Z plane.
- Not closing the trailing edge: the extrude fails ("open contour"). The `.dat` ends 0.5 mm open on purpose for the macro; add the closing line.
- Angle sign: a flap at +48 deg that points the trailing edge down produces lift, not downforce. Check in the side view: for downforce the trailing edge of each element is higher than its leading edge and the slot gaps open rearward-up.
- Slot gap measured along X instead of normal to the surface: use the X overlap and Z gap as the parameters say; they are an approximation of a 2 to 3 % chord slot, fine for CFD at this mesh.
- Mid-plane extrude forgotten: a one-direction extrude puts the whole span on one side of the centreline.

## End-of-part check

- Side view at configuration C: main 6 deg, flap1 30 deg, flap2 48 deg; gaps 14 mm; lowest point Z 60.
- Span 1600 symmetric about CENTRE (Measure both tips to CENTRE = 800).
- Switch to B: angles change, nothing errors. Mass of the three elements together 3 to 5 kg shelled.
