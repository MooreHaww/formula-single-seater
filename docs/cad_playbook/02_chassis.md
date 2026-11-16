# 02 Chassis (`cad/chassis/chassis.SLDPRT`, weldment)

A tubular spaceframe from the node and tube lists in `cad/frame/frame_nodes.csv` and `frame_tubes.csv` (114 tubes, 41.5 m, about 43 kg in steel before trimming, of which 18 tubes and 6 kg are the two sidepod battery boxes), built with SolidWorks Weldments so that the Ring 4 torsion study can use a beam mesh.

## Inputs

`cad/frame/frame_nodes.csv` (50 nodes, car frame, mm), `cad/frame/frame_tubes.csv` (tube, node_a, node_b, group, od, wall), `tube_main_od` 25.4, `tube_main_wall` 2.4, `tube_secondary_wall` 1.6. Groups: `hoop` and `hoop_brace` use the main wall, `sis`, `sidepod`, `bulkhead`, `front` and `rear` the secondary wall.

## Before you start: the tube profiles

Weldments need a profile library entry for each tube size. **Done (2026-11-16, by hand):** the two profiles live in the repo at `cad/weldment_profiles/formula/tube_round/` (`25.4x2.4.sldlfp`, `25.4x1.6.sldlfp`), and the folder `cad/weldment_profiles` is registered in Tools > Options > System Options > File Locations > Weldment Profiles. In the Structural Member PropertyManager that shows up as Standard `formula`, Type `tube_round`, Size `25.4x2.4` or `25.4x1.6`.

On a new PC: add `<repo>\cad\weldment_profiles` to the same File Locations list. To make another size: new part, sketch on Front plane, two concentric circles on the origin (outer D, inner D - 2 x wall), select the sketch, Save As "Lib Feat Part (*.sldlfp)" into `cad/weldment_profiles/formula/tube_round/`.

## Feature order

1. New part from the template. Insert > Part > `master_layout.SLDPRT` with reference geometry and sketches only (`00_index.md`), or skip this if the macro-made skeleton is going to live in this part.
2. **Skeleton sketches.** Run the `ImportFrameNodes` macro in this part (Tools > Macro > Run, pick `cad/macros/ImportFrameNodes.swp`; see `cad/macros/README.md` to make the `.swp` once). It reads the two CSVs and draws one 3D sketch per tube group, each holding only that group's lines:

   | Sketch | Lines | Profile | Structural Member |
   |---|---|---|---|
   | `FRAME_hoop` | 12 | 25.4x2.4 | `SM_hoop` |
   | `FRAME_hoop_brace` | 10 | 25.4x2.4 | `SM_hoop_brace` |
   | `FRAME_sis` | 7 | 25.4x1.6 | `SM_sis` |
   | `FRAME_bulkhead` | 4 | 25.4x1.6 | `SM_bulkhead` |
   | `FRAME_sidepod` | 18 | 25.4x1.6 | `SM_sidepod` |
   | `FRAME_front` | 32 | 25.4x1.6 | `SM_front` |
   | `FRAME_rear` | 31 | 25.4x1.6 | `SM_rear` |

   The final message lists the line count per sketch (114 in total); compare it with this table. Lines that meet at a node share one sketch point within a sketch (this worked in the 2026 test with the old single-sketch macro). Lines are not dimensioned (no equations), which is deliberate: the frame follows the hardpoints through MATLAB regeneration of the CSV, not through SolidWorks equations. To regenerate, delete the seven `FRAME_*` sketches (and the members built on them) first; the macro refuses to run while a `FRAME_*` feature exists. The macro was tested in its first, single-sketch form only; the per-group version is untested, needs the app.
3. **Structural Members with the `BuildTubes` macro** (preferred; untested, needs the app). The 2026 test showed that the Structural Member command shows every sketch while it is selecting, so a box select picks up lines of other groups even with the other sketches hidden. Save the part, then Tools > Macro > Run > `cad/macros/BuildTubes.swp`. For each `FRAME_<group>` sketch it:
   - takes the sketch's own segments (no selection involved);
   - creates one Structural Member with Standard `formula`, Type `tube_round` and the size read per group from `frame_tubes.csv` (25.4x2.4 for `hoop` and `hoop_brace`, 25.4x1.6 for the rest), with end miter;
   - names it `SM_<group>`.

   It inserts the Weldment feature first if the part does not have one. Then, in the same run, it:
   - sets the material to AISI 1020 (SOLIDWORKS Materials, 7900 kg/m³; Plain Carbon Steel if AISI 1020 doesn't take);
   - updates the cut list;
   - saves the part. An unsaved part becomes `cad/chassis/chassis.SLDPRT`; if that file already exists the macro stops before changing anything.

   The final message has a PASS/FAIL line for each check:
   - tubes per group, against the counts in `frame_tubes.csv` (12 / 10 / 7 / 4 / 18 / 32 / 31), with the mode used:
     - **one group:** miters between all segments of the sketch;
     - **one group per segment:** used when SolidWorks refused a branched network in a single group. This is valid, but nothing is mitered; the trim in step 7 does the joints.
   - cut-list bodies: 114;
   - total cut length: within 5 % of the 41.48 m in `frame_tubes.csv`;
   - mass: 38 to 46 kg;
   - material set.

   The macro does not stop at the first problem:
   - a group that fails a check (sketch missing, sketch segment count differs from the CSV, profile missing) is skipped;
   - a group SolidWorks refuses as one feature is tried segment by segment (`SM_<group>_<tube id>` features), and every segment refused even alone is listed with its tube id, nodes and length;
   - everything that works is built and saved; every failure is in the final message and in `cad/chassis/build_tubes_report.txt` (the message box shows about 1000 characters);
   - it changes nothing only if no group can be built at all.

   Members that already exist are kept, so after fixing the cause just run it again; delete any `SM_<group>_*` single-segment features of a group first. To redo a group, delete its `SM_<group>` and rerun. The short version of steps 1 to 3 is `02a_frame_in_3_steps.md`.

   **By hand (fallback only), the old routine** (start with `hoop`, then the order of the table):
   1. In the FeatureManager tree, hide every `FRAME_*` sketch except the one you are working on (right-click > Hide; Ctrl-select several and hide them together). In 2026 the command still shows hidden sketches during selection, so pick lines one by one or check the selection list for strays.
   2. Insert > Weldments > Structural Member. Standard `formula`, Type `tube_round`, Size from the table.
   3. With the Group box active in the PropertyManager, drag a selection box around the whole car in a side or iso view: every line of the visible sketch goes into the group. Check the selection count against the table.
   4. Tick "Apply corner treatment", end miter (end trim for the braces, the trim against the hoops happens in step 7). OK.
   5. Rename the new feature `SM_<group>` (slow double-click on it, or F2).
   6. Show the next sketch, hide this one, repeat.
4. **Hoop notes.** The bend at MH_B is a sharp corner in the skeleton; real hoops are bent with R 76 mm minimum. Add the bend radius with a Sketch Fillet on the line pair in `FRAME_hoop` before creating the member, or accept the sharp corner for v1 and note it.
5. **Sidepod battery boxes** (`FRAME_sidepod`, nodes `SP1_*` in the front hoop plane and `SP2_*` in the main hoop plane, outer rails at y = +-525): both sides in one member (18 lines). The battery packs (`battery_*` in the parameter file, 530 x 165 x 190 each) sit inside with 12 mm to every tube; the Ring 2 check is Interference Detection between the pack blocks and the chassis.
6. **Front and rear boxes** (`FRAME_front` 32 lines, `FRAME_rear` 31): one member each. If the corner-treatment dialog becomes slow, split the box select into two members (left half, right half: `SM_front_a`, `SM_front_b`); a member can take lines from one sketch only, which the per-group sketches guarantee.
7. **Trim (macro `TrimTubes`, untested, needs the app).** Run `TrimTubes.main` on the saved chassis part. It works through `cad/frame/frame_trims.csv` (written by `frame_trims` in MATLAB, part of `run_all`): one Trim/Extend feature per node, `Trim_<node>`, 50 in all, 172 tube ends. At each node the boundary is the strongest tube there (2.4 wall first, then hoop > hoop_brace > bulkhead > sis > front > rear > sidepod, then the longer one), plus its same-group partner if that runs straight on; every other tube ending there is cut against the boundary with a coped cut (planar end trim if the coped one is refused). Bodies are matched to tubes by centroid and bounding box (each within 25 mm, unique), so the macro needs no selection. It checks everything first; a row it cannot match is skipped and listed, existing `Trim_*` features are kept, failures do not stop the others. Final message and `cad/chassis/trim_tubes_report.txt`: PASS/FAIL per row, bodies before and after (must stay 114), mass before and after (must not rise, 38 to 46 kg), cut length, saved. By hand (fallback): Insert > Weldments > Trim/Extend, End trim, coped cut, one node at a time with the CSV row as the guide.
8. **Suspension pickup tabs**: skip in v1. The wishbone inboard points sit on the tube centreline nodes; the assembly mates to the layout's HP points, not to tabs.
9. **Weldment cut list**: done by `BuildTubes` (update plus a total-length check against `frame_tubes.csv`, 41.5 m before trimming). `TrimTubes` updates it again after the trim and reports the new cut length. The first build gave 42.57 m (+2.6 %): the cut-list LENGTH of a tube with an angled or pointed end is its longest extent, so the extra is a measuring effect, not extra steel; the mass is the number for the budget.
10. **Material and mass**: done by `BuildTubes` (AISI 1020, mass checked against 38 to 46 kg). By hand: right-click Material > Edit Material > SOLIDWORKS Materials > Steel > AISI 1020.

## Naming

Skeleton sketches `FRAME_<group>` (made by the macro), structural members `SM_<group>`: `SM_hoop`, `SM_hoop_brace`, `SM_sis`, `SM_bulkhead`, `SM_sidepod`, `SM_front`, `SM_rear`. Trim features `Trim_<node>` (one per node, made by `TrimTubes`).

## Mates in the assembly

The chassis is the fixed component? No: fix the master layout and mate the chassis to it with three coincident mates between the layout's GROUND, CENTRE, FRONT_AXLE planes and the chassis' own three planes. Everything then sits in the car frame.

## Configurations

`Default` only.

## Beginner mistakes

- Picking lines from two different sketches into one Structural Member: not allowed. That is why `ImportFrameNodes` makes one sketch per group and `BuildTubes` builds each member from one sketch's segments; a box select in the command can still catch lines from other sketches in 2026.
- Lines that meet at a node but do not share the endpoint (two separate points 0.1 mm apart): the corner treatment refuses to miter and the beam mesh later shows a disconnected node. Within one `FRAME_*` sketch the macro shares endpoints; between groups the members meet at the same coordinates and the trim in step 7 joins them. By hand, snap to the existing endpoint (yellow coincident icon).
- Letting SolidWorks apply the profile with the wrong orientation on a bent group: irrelevant for round tubes, so ignore the "locate profile" option.
- Trimming everything against everything: creates hundreds of tiny bodies and a 10-minute rebuild. Trim secondary against primary only.
- Rebuild time: a 114-member weldment with corner treatment rebuilds in 10 to 30 s. Turn off "Verification on rebuild" (Tools > Options > Performance) and do not add cosmetic fillets.

## Fallback

If the weldment fights you past about 8 hours: model the hoops and braces as weldments (12 tubes) and the rest as a single lofted "tub" solid between the bulkhead, front hoop and main hoop sections (Insert > Boss/Base > Loft through three rectangles with 30 mm corner fillets, then Shell 3 mm). State it in `docs/log.md`. The torsion study then uses a solid mesh on the tub.

## End-of-part check

- Rebuild with zero errors; cut list updates; total cut length within 5 % of `frame_tubes.csv`.
- Tools > Evaluate > Check: one body per tube (no stray fragments).
- The frame outline matches `media/frame_layout.png` in side and top view.
- Mass between 38 and 46 kg.
- `SaveStandardViews` run; iso view into the log.
