# 01 Master layout (`cad/layout/master_layout.SLDPRT`)

The one part everything references. It holds no solid bodies: only planes, axes, points and sketches. If a number changes in `car_params.txt`, this part moves and the rest of the car follows.

**By macro (untested, needs the app):** `cad/macros/BuildLayout.bas` does steps 1 to 4 and the hardpoint points of steps 3 to 5 in one click. Open a new empty part, run `BuildLayout.main`. It saves `cad/layout/master_layout.SLDPRT` and writes `cad/layout/build_layout_report.txt`. Steps 6 to 10 (envelope and layout sketches, wing positions, A to D configurations) are scriptable but not in v1; nothing in the assembly depends on them. The hardpoint points are placed by value, so after `suspension_geometry` changes them, build a fresh layout.

**Plane mapping used by every macro.** The frame CSVs and the build123d STEP parts use car coordinates directly as SolidWorks coordinates (X rearward, Y right, Z up). In that case GROUND (Z = 0) is the default **Front** plane, CENTRE (Y = 0) is **Top**, and FRONT_AXLE (X = 0) is **Right**. This replaces the "Top = ground" advice in `00_index.md`. The car then looks down from above in SolidWorks' "Front" view; that is cosmetic.

## Inputs (all from `car_params.txt`)

`wheelbase`, `track_front`, `track_rear`, `tyre_od`, `tyre_width`, `tyre_rolling_radius`, `ride_height_front`, `ride_height_rear`, `nose_overhang`, `rear_overhang`, `overall_length`, `main_hoop_x`, `main_hoop_height`, `front_hoop_x`, `front_hoop_height`, `driver_hip_x`, `driver_hip_z`, `seat_back_angle`, `battery_*`, `motor_*`, the hardpoint block `f_*` and `r_*`, the wing block `fw_*`, `rw_*`, the floor block.

## Feature order

1. **Template and planes.** New part from `car_part.prtdot`. Confirm the three named planes GROUND, CENTRE, FRONT_AXLE (see `00_index.md`). Add: `REAR_AXLE` (Insert > Reference Geometry > Plane, offset from FRONT_AXLE by `="wheelbase"`, direction rearward), `MAIN_HOOP` (offset `="main_hoop_x"`), `FRONT_HOOP` (`="front_hoop_x"`), `FW_LE` (front wing leading edge plane, offset `=-("nose_overhang" - 50)`), `RW_LE` (`="wheelbase" + "rear_overhang" - "rw_main_chord" - "rw_flap1_chord" - "rw_flap2_chord" + 2*"wing_element_overlap"`, **verify** the sign of the overlap in your wing stack).
2. **Axes.** Insert > Reference Geometry > Axis: `FRONT_AXLE_AXIS` = intersection of FRONT_AXLE and the plane at Z = `tyre_rolling_radius` (make a plane `WHEEL_CENTRE_HEIGHT` offset from GROUND by `="tyre_rolling_radius"` first). Same for `REAR_AXLE_AXIS`.
3. **Sketch `HP_front_right`** on GROUND? No: hardpoints are 3D. Insert > 3D Sketch. Place a sketch point for each of the 10 front hardpoints (`f_lwb_in_fwd`, `f_lwb_in_aft`, `f_lwb_out`, `f_uwb_in_fwd`, `f_uwb_in_aft`, `f_uwb_out`, `f_tierod_in`, `f_tierod_out`, `f_pushrod_out`, `f_pushrod_in`) and fully define each with three Smart Dimensions to the three named planes, typed as `="f_lwb_in_fwd_x"` etc. (dimension from the plane, not from the origin, so the sign is unambiguous; a negative X value means ahead of the front axle). Add construction lines between inboard pairs (pivot axes) and from each inboard pair to its outer point (the wishbone legs); these lines are what the wishbone parts convert. Name the points by right-click > Properties? **verify**: sketch points cannot be named in SolidWorks; instead keep a consistent order and document it in a sketch note, or use Insert > Reference Geometry > Point on each sketch point and name the reference points. Reference points are selectable in mates by name, which pays off in the assembly. Do that: 10 named reference points `HP_f_lwb_in_fwd` ... `HP_f_pushrod_in`.
4. **Sketch `HP_rear_right`**: same with the `r_*` hardpoints (10 points including `r_toelink_in/out`).
5. **Mirror the hardpoints**: Insert > Reference Geometry > Point cannot mirror; instead draw the left points in the same 3D sketches with `=-"f_lwb_in_fwd_y"` dimensions (negative Y). Yes, 40 points by hand; about 40 minutes, done once. Alternative: mirror the whole suspension sub-assembly about CENTRE later (Insert > Mirror Components in the assembly), which needs only right-side points here. Take the alternative; add left points only if a mate needs them.
6. **Sketch `WHEELS`** (3D sketch): four circles of diameter `="tyre_od"` in planes parallel to CENTRE at Y = `+-"track_front"/2` and `+-"track_rear"/2`, centred on the axle axes. Plus rectangles for the tyre width in the top view. These are the packaging envelopes for the body, not geometry to build from.
7. **Sketch `SIDE_LAYOUT`** on CENTRE: ground line, wheel circles, driver stick figure (hip point at `("driver_hip_x", "driver_hip_z")`, thigh 450 forward and 100 up to the knee, shin down to the heel at Z = 150 ahead at X = 250, torso 560 at `seat_back_angle` from vertical, helmet circle R 150 centred 200 beyond the shoulder along the torso line), main hoop line to `main_hoop_height`, front hoop line, battery rectangle (`battery_x_front`, `battery_z_bottom`, `battery_length`, `battery_height`), motor circle (`motor_x`, `motor_z`, D `motor_diameter`), diff circle (X `wheelbase`, Z `tyre_rolling_radius`, R 80), nose tip at X = `-"nose_overhang"`, rear wing TE at X = `"wheelbase" + "rear_overhang"`. This is the Ring 1 layout sketch; screenshot it into `docs/concept.md`.
8. **Sketch `TOP_LAYOUT`** on GROUND: centreline, wheel rectangles, frame outline from `cad/frame/frame_nodes.csv` (lower rail nodes), battery rectangle `battery_width`, cockpit opening `cockpit_opening_length` x `cockpit_opening_width` starting at `front_hoop_x`.
9. **Sketch `BODY_SECTIONS`**: five sketches on planes offset from FRONT_AXLE at X = -500, 0, 500, 1000, 1500 holding the body cross-section (a rounded rectangle or a spline) that the nose and sidepods loft between. Sizes in `07_nose.md` and `08_sidepods.md`. These live here so the body, floor and CFD body share one skin definition.
10. **Sketch `FW_POSITION`** on CENTRE and **`RW_POSITION`** on CENTRE: the chord lines of the three elements of each wing with their angles `="fw_main_aoa_C"` etc. (configurations A to D set which angle set is active: Configure Dimension on the three angle dimensions). Element LE positions: main LE at the wing plane, flaps staggered by `wing_element_overlap` in X and `wing_element_gap` in Z (see `10_front_wing.md`).
11. **Frame skeleton**: run `cad/macros/ImportFrameNodes.bas` (untested) with this part open: it creates a 3D sketch `FRAME_SKELETON` with one line per tube from `cad/frame/frame_tubes.csv`. If the macro fails, draw the skeleton by hand in `02_chassis.md` instead; nothing else depends on it being here.

## Configurations

`Default` plus `A`, `B`, `C`, `D` that only change the wing angle dimensions in `FW_POSITION` and `RW_POSITION` (and suppress both sketches in `A`).

## Beginner mistakes

- Dimensioning a 3D sketch point "to the origin" instead of to the named planes: the dimension appears to work and then flips sign on rebuild. Always three dimensions, each to a plane.
- Forgetting to link the equation file before typing `="wheelbase"`: SolidWorks silently creates a local global variable with that name and the part stops following the file. Check Tools > Equations shows the file path at the top.
- Editing a hardpoint value here instead of in `car_params.txt`: the MATLAB results and the CAD diverge. The block is generated; change it in `suspension_geometry.m`.
- Leaving a sketch under-defined (blue entities): it moves on rebuild when something else changes. Every sketch here is fully defined (black) before you leave it.

## End-of-part check

- Tools > Equations lists the linked file and no local overrides (every global variable shows "linked").
- Change `wheelbase` to 1600 in the text file, Rebuild: REAR_AXLE and the rear hardpoints move 50 mm; nothing turns yellow. Change it back.
- Feature tree: GROUND, CENTRE, FRONT_AXLE, REAR_AXLE, MAIN_HOOP, FRONT_HOOP, WHEEL_CENTRE_HEIGHT, FW_LE, RW_LE, two axes, HP_front_right, HP_rear_right, 20 named reference points, WHEELS, SIDE_LAYOUT, TOP_LAYOUT, BODY_SECTIONS (5), FW_POSITION, RW_POSITION, FRAME_SKELETON. No solid bodies.
- Screenshot of SIDE_LAYOUT with driver, motor, battery and wheels, no overlaps, into `docs/concept.md`.
