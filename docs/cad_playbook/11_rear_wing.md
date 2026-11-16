# 11 Rear wing (`cad/aero/rw_main.SLDPRT`, `rw_flap1.SLDPRT`, `rw_flap2.SLDPRT`, `cad/aero/rear_wing.SLDASM`)

Same construction as the front wing with the rear chords and angles, mounted high on two swan-neck pylons to the rear box top nodes (RT1/RT2, Z 470).

## Inputs

`rw_span` 1250, `rw_main_chord` 450, `rw_flap1_chord` 240, `rw_flap2_chord` 170, `rw_height` 1150 (ground to the main element leading edge), `wing_element_gap` 14, `wing_element_overlap` 20, angles `rw_main_aoa_B/C/D` (6/9/11), `rw_flap1_aoa_*` (24/32/34), `rw_flap2_aoa_*` (40/52/56), `rear_overhang` 750, `wheelbase` 1550. Airfoils `rw_main.dat` (NACA 6414, thicker for the spar), `rw_flap1.dat`, `rw_flap2.dat`.

Position: the stack's trailing edge (flap 2 TE at configuration C) at X = `wheelbase + rear_overhang` = 2300. The layout's `RW_POSITION` sketch places the main element LE so that this holds at C; B and D move the TE by a few mm, which is fine. Main LE at about X = 2300 - (450 + 240 + 170 - 2 x 20) x cos(angles) = roughly X 1520. **verify** against the sketch; the wing then sits above the rear axle and the motor, which is what you want for balance.

## Feature order

1. Same as `10_front_wing.md` steps 1 to 6 with the rear chords. The main element gets a spar: a D 25 hole along the span at 30 % chord (Cut-Extrude a circle through all), which the pylons pass through.
2. **Pylons** (`rw_pylon.SLDPRT`, one file mirrored): a swan neck from the rear top node RT1 (1490, 290, 470) to RT2 (1690, 290, 470) up to the main element's spar at Z about 1200, Y 290. Sketch on a plane at Y = 290: a 40 mm wide profile that follows the upper surface clearance (swan neck goes over the top of the element and attaches to the spar from above so the underside stays clean). Extrude 8 mm mid-plane. Keep it simple: a tapered plate from the two nodes to the spar.
3. Endplates: `12_endplates.md`.

## Rear wing assembly

`rear_wing.SLDASM`: three elements, two endplates, two pylons. Configurations B, C, D. In A the whole sub-assembly is suppressed by the top assembly.

## Beginner mistakes

- Rear wing too far back for the overhang: the TE at 2300 is the end of the car; the endplates (950 long) extend forward from there, not backward.
- Pylon through the flaps: the pylons attach to the main element only; the flaps are held by the endplates. Check the side view.
- Forgetting the rear wing height is to the LE, not the TE: `rw_height` 1150 is the LE of the main element. The main hoop top is at 980; the wing stays above the driver's helmet line.

## End-of-part check

- Side view, configuration C: angles 9/32/52, TE at X 2300, LE at Z 1150.
- Span 1250 symmetric.
- Pylons reach the RT nodes exactly (Measure the pylon base to `HP`-style points: the frame nodes are in `frame_nodes.csv`, RT1_R = (1490, 290, 470), RT2_R = (1690, 290, 470)).
- Mass of the rear wing sub-assembly 4 to 6 kg shelled.
