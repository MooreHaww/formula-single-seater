# 13 Details (seat, driver dummy, steering wheel, motor and battery blocks, rockers, pushrods, springs)

Block models whose only jobs are packaging checks, mass properties and looking right in the renders. Nothing here is simulated except that the springs' free length and the rocker geometry feed the Ring 3 motion ratio.

## Inputs

`driver_hip_x` 850, `driver_hip_z` 180, `seat_back_angle` 40, `main_hoop_x` 1250, `battery_x_front` 690, `battery_length` 530, `battery_width` 165, `battery_height` 190, `battery_z_bottom` 105, `battery_y_inner` 335, `battery_mass` 45 (both packs together), `motor_x` 1340, `motor_z` 270, `motor_diameter` 230, `motor_length` 110, `wheelbase` 1550, pushrod hardpoints `*_pushrod_in/out`, `rocker_ratio_*` 1.0, motion ratios from `suspension_geometry` (front 0.706, rear 0.773), spring rates 49.8 and 56.3 N/mm, wheel travel +-30 (so spring travel +-21 front, +-23 rear).

## Parts and recipes

**`seat.SLDPRT`** (`cad/details/`): on CENTRE sketch an L: seat pan from X 600 to 850 at Z 150 (slightly below the hip point so the hip sits on it), back from the hip up at `seat_back_angle` for 600 mm, both 5 mm thick as a thin-feature extrude, Mid Plane 420 wide. Fillet the corner R 60. Material custom 1600. 1 kg.

**`driver_dummy.SLDPRT`**: the FS "Percy" 95th percentile template made of three circles and lines (rules figure: 300 mm circle for the hips, 200 mm circle for the shoulders, 300 mm circle for the head, 490 mm between hips and shoulders, 280 mm shoulders to head centre; **verify** against the current FS rules figure before trusting these). Build as revolved/extruded volumes: hips cylinder D 300 x 400 wide centred at (850, 0, 230), torso box 490 long along the seat back angle, 400 wide, 200 thick, shoulders cylinder D 200, neck, head sphere D 300, thighs two boxes 120 x 120 x 450 forward from the hips, shins down to the pedal face at X 250. Mass set by density to 70 kg (`mass_driver`): compute the volume with Mass Properties, then set density = 70 kg / volume in Material > Custom. Not pretty; it is a packaging template.

**`steering_wheel.SLDPRT`**: D 250 ring, 30 mm section, revolve; hub D 60; centre at X 560 (**verify** reach: about 290 mm ahead of the hip point and 350 above it), Z 530, tilted 20 deg from vertical. 0.3 kg.

**`motor.SLDPRT`**: cylinder D `motor_diameter` x `motor_length` along Y, centred at (`motor_x`, 0, `motor_z`), which is the bay behind the main hoop and ahead of the rear suspension box (third-session layout; it was behind the rear axle before); a D 40 x 40 shaft stub on the -Y side; a sprocket D 90 x 12 on the shaft. Material steel, density set so the mass equals `m_motor` (12.3 kg, Emrax 228 class). Block. The inverter is a second block 300 x 200 x 100 at (1380, 0, 500) above the motor, density for `m_inverter_hv`.

**`diff.SLDPRT`**: cylinder D 160 x 300 wide along Y at (`wheelbase`, 0, `tyre_rolling_radius`) with a sprocket D 260 x 12 on the -Y side aligned with the motor sprocket (chain centre distance 215 mm: sqrt(210^2 + 48^2) from the motor axis to the axle line; 20 mm between the motor body and the diff housing). Halfshafts D 25 from the diff to the hubs (two `halfshaft.SLDPRT`, a cylinder along the wheel axis, length from Y 150 to 485). 6 kg + 1 kg each.

**`battery_pack.SLDPRT`** (two instances, mirrored): box `battery_length` x `battery_width` x `battery_height` with its front face at `battery_x_front`, inner face at `battery_y_inner` from the centreline, bottom at `battery_z_bottom`; corner fillets R 10, two lifting lugs. Density set so each pack is `battery_mass` / 2 (22.5 kg). They sit inside the sidepod tube boxes of the chassis (`02_chassis.md` step 5b) with 12 mm to every tube; mirror the right pack about CENTRE in the assembly. The sidepod bodywork (`08_sidepods.md`) wraps around them, so its section at X 700 to 1220 must clear y = +-540 and z = 320.

**`rocker_front.SLDPRT`, `rocker_rear.SLDPRT`**: a triangular plate 8 mm thick with three holes: pivot at the frame node (FBT for the front: (0, 280, 430); RRK for the rear: (1550, 290, 470)), pushrod hole at `*_pushrod_in`, spring hole 80 mm from the pivot on the far side (1:1 ratio means pushrod and spring arms are equal: pushrod arm = distance from pivot to `pushrod_in`, measure it, about 40 mm front; make the spring arm the same). The spring then runs from the rocker to a frame node (front: FS1_U cross tube midpoint (-130, 0, 305); rear: RT1 cross midpoint (1490, 0, 470)) across the car, which is the usual FS layout. Pivot axis along X for both.

**`spring_damper.SLDPRT`**: a cylinder D 36 body 150 long with a D 12 rod 80 long and a coil spring (helix: Insert > Curve > Helix/Spiral, pitch 12, 10 turns, D 50, swept circle D 6). Eye-to-eye length 230 at ride height (**verify** that this matches the rocker-to-frame distance; dimension the rocker's spring arm so it does). Spring rate is a label, not geometry: put `49.8 N/mm` in the part's custom properties.

**Pushrods**: in `03_wishbones.md`.

## Mates

Blocks: three named planes to the layout. Rocker: pivot hole Concentric to an axis through the node along X (make a reference axis in the layout), plate mid-plane Coincident to a plane through the node; this leaves the rotation free. Spring: eyes Concentric sphere-sphere (model D 16 spherical pockets at both ends like the wishbones), so the Motion study can treat it as a two-force member and the spring force is added as a Motion "Spring" element between the two eyes.

## Configurations

`Default` everywhere.

## Beginner mistakes

- Giving the blocks their real material (steel motor at 230 x 110 is 36 kg): set density for the target mass instead.
- Placing the battery as one block behind the main hoop out of habit: that layout gave 35 % front weight; the packs are in the sidepods now and the bay behind the hoop holds the motor and inverter.
- Rocker geometry drawn in the wrong plane: the pushrod comes up from the outboard point to the rocker; the rocker plane contains the pushrod direction and the spring direction (roughly the Y-Z plane at the node's X). Sketch on a plane parallel to FRONT_AXLE through the node.
- Spring free length that does not match the rocker-to-frame distance: the Motion study starts with a preloaded or slack spring and the ride height jumps. Measure, then set.

## End-of-part check

- Assembly Mass Properties with all details: `mass_car` within 15 % of 230 kg without the driver, and 300 kg with the dummy. Write the result back into `car_params.txt` (`mass_car`, `cg_height`, `cg_x_from_front_axle`) and note it in `docs/log.md`.
- SIDE_LAYOUT envelopes vs the solids: driver dummy inside the body, helmet under the hoop-to-brace line, motor and battery not touching tubes (Interference Detection).
