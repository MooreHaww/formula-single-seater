# CFD geometry: half car, variants A to D, E and CP

Built by `cad/generate/cfd_variants.py` (build123d 0.13 in the project venv) from `params/car_params.txt` and the airfoil files in `cad/airfoils/`. One command rebuilds everything and checks it:

```bash
.venv/Scripts/python cad/generate/cfd_variants.py
```

Optional pictures: `.venv/Scripts/python cad/generate/render_cfd_views.py` writes `media/cfd/halfcar_<V>_views.png`.

## Frame and files

- X rearward (flow direction) from the front axle, Y right from the centre plane, Z up from the ground. STEP files are in mm; `cfd_geometry.json` is in m.
- Half model: Y >= 0, symmetry plane Y = 0. Every force from Fluent is half the car (`cfd/postprocess.py` doubles them).
- `cad/step/cfd/`:
  - `halfcar_<V>.step`: three solids (car, front wheel, rear wheel), for looking at.
  - `fluid_<V>.step`: the air as one solid (domain minus car and wheels), the file Fluent meshes.
  - `faces_<V>.csv`: every face of the fluid solid with its zone name and bounding box. Fluent's STEP reader drops the names, so `cfd/fluent_halfcar.py` names the zones by matching bounding boxes against this file.
  - `boi_boxes.step`: the two refinement boxes (near car, wake). `domain.step`, `boi_near.step`, `boi_wake.step` are the same boxes alone.
  - `cfd_geometry.json`: domain, refinement boxes, wheel centres and spin rule, wake-plane positions, reference area, per-variant areas and checks.
  - `check_report.txt`: the result of every check below.

## Zones

`inlet`, `outlet`, `symmetry` (Y = 0), `side`, `top`, `ground` (moving), `wheel_front`, `wheel_rear` (rotating walls), `car_body`, `car_floor`, `car_fw`, `car_rw` (stationary walls). The front wing, rear wing and floor are separate zones, so each has its own force report.

## Domain

Car length 3.38 m (front-wing leading edge to rear-wing endplate), width 1.61 m, height 1.55 m (variant C). Domain 3 lengths ahead, 8 behind, 4 heights above, 4 widths to the side: X -11.2 to 29.36 m, Y 0 to 6.45 m, Z 0 to 6.2 m. Blockage of the full-car frontal area against the full domain cross-section (12.9 x 6.2 m): about 1.6 % for D.

Wake planes at 0.5, 1, 2 and 3 car lengths behind the rear axle, using `overall_length` 2.95 m from the parameters (X 3.03, 4.50, 7.45, 10.40 m). Following-car window: 1.4 m wide, 1.2 m high.

## Checks (all variants, last run 35 of 35 PASS)

Each body: one solid, one shell, OCCT BRepCheck valid, every edge shared by exactly two faces (no open or non-manifold edges), bounding box printed, wetted area by zone instead of the volume (the volume integral of the large fluid solid is not reliable). Each STEP file is read back and checked again. Frontal area (full car): A 0.75, B 1.20, C 1.31, D 1.42 m2.

## Simplifications and decisions (each is an interpretation I took)

| What | Why |
|---|---|
| Front-wing leading edge at X -960 mm (`fw_le_x`) instead of -600 | at -600 the flaps run through the front tyres |
| Front flaps start at Y 300 mm (`fw_flap_inner_y`), main element runs through to the centre | the flaps cut through the nose; Fluent's surface mesher failed there ("breakout detected") |
| Slots between wing elements 8 mm wider than `wing_element_gap` (`SLOT_EXTRA`) | the 5 to 17 mm slots failed the surface mesh (duplicate front edge, failed projection). Wider slots change the flap loading; the aero estimate places the elements with the same gap but has no gap term in its flap effectiveness |
| Trailing edges cut at 97 % chord (blunt, about 1 to 2 mm) | a sharp trailing edge gave a "duplicate front edge" error |
| Nose tip raised (first two hull sections) | to clear the front-wing main element by 50 mm |
| Rear endplate 20 mm further back | the flap trailing edge lay in the endplate face (degenerate edge) |
| Floor top at Z 75 (was 62) and a filler block on the diffuser roof start (C, D) | the floor and diffuser tops left sliver faces against the hull bottom (Z 60 to 70) at Y = 0 |
| Variant D: beam wing leading edge at X 1690 (`beam_x_le`, was 1800), fully inside the rear pylon's chord (1683 to 1895) | its leading edge cut the pylon face and the surface mesh failed there |
| Variant D: endplate fins (vortex generators) 10 mm thick (`VG_T`, was 5) | thin fins added many tiny faces; D then meshed at 1,042,343 cells with the common settings |
| Trailing edges left at 97 % chord (1.1 to 4.6 mm thick), although thinner than the 2.5 mm minimum mesh size | a version cut to a 3 mm minimum thickness (`TE_MIN_MM`) failed in more places, so it is off |
| Tyres: filleted disc on a 5 mm plinth to the ground | a line contact is unmeshable; the plinth gives a contact patch of 143 x 172 mm |
| Variant E (2026-11-18): C with D's rear-wing angles, rear wing at Z 950 (C 1150) and 1330 mm span (C 1250), diffuser 14 deg, body cut square at X 1700 (blunt base) | the wake test in `cfd/variant_E.md`. The cut was planned at X 1745; there the hull bottom grazed the diffuser side wall (slivers of 2 to 3 mm by 14 mm at Y 154 to 168, Z 91 to 98) and the surface mesh failed with 22 self-intersections. X 1700 is the nearest position without slivers (1720, 1770 and 1800 all had them) |
| Variant CP (2026-11-18): C with the SolidWorks nose and sidepods and a 10 mm floor plate (`body_sections_parts`, `sidepod_parts`, `build_floor_plate`) | task 4, bodywork reconciled to the parts. Differences to the parts: nose solid (no skin, no link slots, closed at the hoop); hull and pod bottoms 4 mm into the plate (`SINK`; the parts' 1 mm gap is unmeshable); pod closed inboard at Y 300 and at the bottom (the parts' pods are open-bottomed shells: an open bottom would give the solver a 2 mm skin with flow inside, not meshable here) |
| Variant CP corner radii: nose corners at least 40 mm (`CP_R_NOSE_MIN`; parts 10 to 20 mm), pod corners 25 mm (`CP_R_POD`; parts 6 mm) | cell budget: with the parts' radii the curvature sizing put 65,000 faces on the body (C: 28,000) and the mesh had 1,153,899 cells, over the 1,048,576 limit. The larger radii change the frontal area by 0.001 m2 (1.341 to 1.340) |
| No suspension links, no mirrors, no radiator flow, closed cockpit, solid sidepods | out of scope for the variant comparison; all variants share these simplifications |

The ranking of the variants is what this geometry is for. The absolute forces depend on these simplifications.
