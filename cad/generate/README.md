# cad/generate/

Python (build123d) generators for the simple bodies of the car. They read `params/car_params.txt` with the same rules as `matlab/common/read_car_params.m` and write one STEP file per part to `cad/step/`, in car coordinates (X rearward from the front axle, Y right, Z up, mm), so each file drops into the SolidWorks assembly with three plane mates and no repositioning.

| Script | Parts | Run |
|---|---|---|
| `build_parts.py` | tyre_front/rear, rim_front/rear, fw_main/flap1/flap2, fw_endplate_R/L, rw_main/flap1/flap2, rw_endplate_R/L, floor_diffuser, nose, sidepod_R/L (18 files) | `uvx --from build123d python cad/generate/build_parts.py` |

`uvx` (from the uv tool) downloads build123d into a cache on first use; with a Python that already has build123d 0.13 installed, `python cad/generate/build_parts.py` works too. Options: `--only tyre_front,nose` builds a subset, `--out <dir>` changes the output folder. The script prints each part's bounding box and a mass guess from its volume and an assumed density, then "N parts built, M skipped" with the error for every skip. Exit code 1 means nothing built.

## What the bodies are, and what they are not

These are the CFD-grade shapes of `docs/cad_playbook/06` to `12`, built with the playbook's feature order (revolve, extruded airfoil, loft, skin). They are meant to be imported (Insert > Features > Imported) or used as a size check against the native parts built by hand. They are not the native parametric SolidWorks parts: no configurations (variant C angles only), no equations, no fillets on the rim, solid wing elements (the playbook shells them to 2 mm for mass; the generated mass of a solid element is 7 to 34 kg and means nothing).

Decisions taken in the script that the playbook left open, all marked in the code:

- Tyre carcass 8 mm thick (a solid rubber ring would weigh 22 kg; the hollow one is 3.6 kg) with the ground flat below Z 0.
- Nose and sidepods are ruled lofts (straight between sections); a smooth loft of the nose sagged to Z 41 behind the bulkhead and would have hit the floor. The 2 mm skin is an outer loft minus an inner loft, open at the rear (nose) or inboard (sidepods), because build123d's shell operation failed on these shapes.
- Sidepod sections are 20 mm outside the battery-structure rails: the script intersects each pod with the box |Y| 320 to 540, Z 60 to 320, X 700 to 1220 and prints the overlap volume, which must be 0.
- Rear endplate top is 40 mm above the measured flap-2 trailing edge at configuration C (Z 1549), not the playbook's `rw_height + 320` (1470), which the stack overtops. The playbook had marked that height "verify".
- Diffuser strakes run from Z 165 at the axle to `diffuser_exit_height` 220 at the exit.

Untested in SolidWorks: the STEP files have not been opened in the 2026 app yet. First check on import: each part is one closed solid (Evaluate > Check), the tyre flat sits on Z 0, the front wing's lowest point is at Z 60.
