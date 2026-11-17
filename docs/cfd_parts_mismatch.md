# CFD geometry vs the bodywork parts (for the CFD session)

**What this is:** where the CFD half-car (`cad/step/cfd/halfcar_C.step`, from `cfd_variants.py`) differs from the bodywork parts that SOLIDWORKS builds (`cad/step/*.step`, from `build_parts.py`, after the rim-limited hardpoints of 2026-11-17).

**Nothing in `cfd/`, `cad/step/cfd/` or `cfd_variants.py` was changed.** Reconciling the two is a decision held until the CFD results are in.

## Files

- **Data:**
  - `docs/cfd_parts_mismatch.csv`: one row per part;
  - `docs/cfd_parts_sections.csv`: body outline every 50 mm in x.
- **Regenerate:** `.venv\Scripts\python.exe cad\generate\compare_cfd_parts.py C`. Pass another variant letter to compare against B or D. The script only reads `cad/step/cfd/`.
- **Method:**
  - Both surfaces are tessellated at 0.5 mm and sampled about every 4 mm.
  - "Part → CFD" is the distance from each point of the part's surface to the nearest CFD surface: how far the part is from where the CFD model puts a wall.
  - "CFD → parts" is the reverse, from CFD surface near the part to the nearest of all parts: CFD surface that no part has.
  - Right half only (Y ≥ 0), like the CFD model. A 2 mm shell part has two skins and the CFD body one, so up to about 2 mm counts as the same.
- **Coordinates:** mm. X rearward from the front axle, Y right, Z up from the ground.

## Per part (variant C)

| Group | Part | Part → CFD median / p95 / max, mm | Share of part > 5 mm off | Worst part point (x, y, z) | CFD → parts median / p95 / max, mm | Worst CFD point (x, y, z) |
|---|---|---|---|---|---|---|
| nose | nose (incl. cockpit surround to x 627) | 21.9 / 97.4 / 128.9 | 79 % | (520, 308, 695) | 17.5 / 82.8 / 313.6 | (657, 0, 379) |
| sidepods | sidepod_R | 30.2 / 37.5 / 49.1 | 85 % | (624, 558, 372) | 5.4 / 31.5 / 102.2 | (1330, 306, 160) |
| floor | floor_diffuser | 0.4 / 10.1 / 17.0 | 19 % | (1605, 149, 72) | 1.9 / 42.8 / 166.6 | (719, 0, 217) |
| front wing | fw_main | 1.2 / 3.0 / 12.0 | 4 % | (−562, 748, 136) | 1.1 / 8.0 / 43.6 | (−672, 76, 165) |
| front wing | fw_flap1 | 8.2 / 12.9 / 16.1 | 70 % | (−392, 304, 260) | 1.7 / 12.4 / 18.2 | (−428, 600, 283) |
| front wing | fw_flap2 | 14.3 / 18.0 / 18.7 | 94 % | (−325, 339, 349) | 10.0 / 18.0 / 18.2 | (−341, 766, 371) |
| front wing | fw_endplate_R | 0.0 / 1.6 / 6.0 | 1 % | (−540, 800, 164) | 0.9 / 1.9 / 18.2 | (−339, 772, 374) |
| rear wing | rw_main | 4.3 / 18.6 / 19.5 | 44 % | (1587, 541, 1149) | 2.4 / 16.5 / 67.5 | (1895, 158, 1085) |
| rear wing | rw_flap1 | 2.4 / 7.3 / 7.6 | 17 % | (2012, 541, 1234) | 2.3 / 8.6 / 12.0 | (2090, 0, 1261) |
| rear wing | rw_flap2 | 1.9 / 6.0 / 6.4 | 20 % | (2197, 541, 1375) | 1.6 / 5.2 / 20.0 | (2320, 631, 1479) |
| rear wing | rw_endplate_R | 0.9 / 15.8 / 20.1 | 8 % | (1350, 625, 1154) | 1.1 / 3.8 / 20.0 | (2320, 631, 1479) |

## What differs, in words

### Nose (x −300 to 250)

- **Width:** the parts' nose is 20 to 50 mm wider. Half-width is 267 to 305 mm in the parts against 230 to 288 in CFD.
- **Height:** the CFD nose is 15 to 90 mm taller. Its top is z 421 to 544 against 388 to 491 for the parts.
- **Underside:** the CFD nose goes down to z 60 all along. The parts' nose underside rises from z 55 at x −300 to z 124 at the front axle, then falls back to 92 at x 250.

### Cockpit surround (x 300 to 627, part of `nose.step`)

- The widths agree (550).
- The parts rise to z 695 at the front hoop, where the CFD body tops out at z 593. The worst part point is (520, 308, 695).

### Behind the front hoop (x 650 to 1400): the biggest gap

- **The CFD body has a cockpit/engine cover that no part has.** Its top is z 600 to 610 over the cockpit, z 880 to 990 at the main hoop (x 1000 to 1250), and it tapers to z 830 at x 1400, at up to y 455.
- No part exists above the sidepods (z 372) there.
- The worst CFD → parts point, (657, 0, 379) at 314 mm, is this body on the centre plane.
- Either a cover part has to be made, or the CFD cover is taken as the target for one.

### Sidepods

- **Plan and side outline agree:** outer y 562 in both, x 650 to 1300.
- **Section shape differs by about 30 mm all over** (median 30 mm). The part's leading top outer corner is (624, 558, 372); the CFD sidepod starts at x 650 with a different top.
- The CFD tail continues inboard to x 1330 at y 306, z 160, where the part ends at x 1301.
- **Changed this session:** the part's tail section now stays at |y| 334 inboard (it used to step in to 310). This keeps 10 mm from the MH_M–RS1_U tube after RS1_U moved out to |y| 320 with the new rear hardpoints. Outer shape unchanged.

### Floor and diffuser

- They agree closely: median 0.4 mm.
- The worst part point, 17 mm at (1605, 149, 72), is at the diffuser kick-up.
- The large CFD → parts values (up to 167 mm at (719, 0, 217)) are the CFD body's underside near the floor, not the floor itself.

### Front wing

- The main plane and endplate agree (median ≤ 1.2 mm).
- The flaps are 8 mm (flap 1) and 14 mm (flap 2) off. This is consistent with what `cfd/geometry_notes.md` records for meshing:
  - slots widened by 8 mm beyond `wing_element_gap`;
  - trailing edges cut at 97 % chord.
- Each widening moves the next element down the stack, so flap 2 moves about twice as far as flap 1.

### Rear wing

- Flaps 1 and 2 agree to about 2 mm.
- The main plane's leading edge is about 20 mm off at (1587, 541, 1149): the CFD LE is at x 1607 for C.
- The endplate's front edge, 20 mm at x 1350, matches "rear endplate 20 mm back" in the CFD notes.

## Not compared

- **Wheels:** both use the same tyre size.
- **Variants B and D:** run the script with `B` or `D`. D also moves the rear wing beam and adds endplate fins.
- **The frame and suspension:** not in the CFD model.
