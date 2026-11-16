# 14 CFD body (`cad/cfd_body/cfd_body.SLDPRT`)

One watertight half-car solid per aero variant, built from the body, floor, wings, endplates and closed wheels, without the frame, suspension links, driver or interior. This is what `cfd/fluent_halfcar_setup.md` expects: a single closed solid, Y >= 0 half, in car coordinates, mm.

## Inputs

Everything from `07` to `12` plus the tyres and rims from `06`. The frame, wishbones, uprights, pushrods, rockers, springs, seat and dummy are excluded; the cockpit opening is **closed** with a flat lid at Z 620 (a driver's helmet is omitted in v1; add a helmet bump in v2).

## Method: multibody part by Insert > Part, then Combine

1. New part `cfd_body.SLDPRT` from the template. Insert > Part for each of: `body_main` (nose + cockpit + rear cover), `sidepod` (right only), `floor_diffuser`, `fw_main`, `fw_flap1`, `fw_flap2`, `fw_endplate` (right), `rw_main`, `rw_flap1`, `rw_flap2`, `rw_endplate` (right), `rw_pylon` (right), `tyre` x2 (front right, rear right), `rim` x2. In the Insert Part dialog tick "Solid bodies", untick everything else, and **tick "Link to original"** so that a change in a source part flows here. **verify**: inserted parts keep their configuration; choose the configuration in the Insert Part PropertyManager (there is a configuration drop-down) and later Configure the inserted feature per configuration of this part (right-click the inserted part feature > Configure Feature lets you change the referenced configuration per configuration; **verify** in 2026, otherwise insert each variant's wing set separately and suppress by configuration).
2. **Wheel closure**: the rims are inserted plain (configuration `Default`, no spokes). Add a Cut-Extrude? No: add a D 254 x 180 cylinder body at each wheel position (Extrude from the layout's wheel-axis plane, mid-plane `tyre_width`) so the rim barrel is a solid drum. Insert the tyres in their static position (the part files are built in car coordinates at ride height, so they are already right).
3. **Cockpit lid**: Extrude a plate from a sketch on a plane at Z 620: the cockpit opening outline grown by 10 mm, 10 mm thick downward, merge with the body.
4. **Gap filling**: the slot gaps between wing elements stay (they are the aero). The gaps between sidepod and body, wing struts and body, pylons and wing must be zero or overlapping; where an inserted body only touches another face, Combine creates a non-manifold edge. Enlarge the pylons and struts by 1 mm into their neighbours (Move/Copy Body or a small Extrude) so every pair overlaps.
5. **Combine**: Insert > Features > Combine, operation Add, select all bodies. If it fails, Combine in groups (body + sidepod + floor first, then each wing stack, then everything) and read the error: it names the pair that does not overlap.
6. **Half cut**: Cut-Extrude a huge rectangle from CENTRE, direction -Y, "Through all". Keeps Y >= 0.
7. **Ground check**: the tyre flats are at Z 0; nothing else may touch Z 0 (the front endplate bottom is at Z 30). Section view at Z 1 (View > Display > Section View) shows only the two tyre flats.
8. **Check**: Tools > Evaluate > Check, tick "Strict solid/surface check" and "Open surfaces": must report 1 solid body, no open surfaces, no short edges under 0.5 mm (tick "Short edges" with 0.5). Short edges come from the airfoil trailing edges (the 0.5 mm closing line is on purpose; the Fluent mesh sizing handles 0.5 mm; if Check complains, set the short-edge threshold to 0.3).
9. **Configurations**: `A` (wings, pylons, endplates and diffuser suppressed; the floor stays), `B`, `C`, `D` (the inserted wing features referencing the matching source configurations; diffuser angle follows the floor part's configuration).
10. Export: run `cad/macros/ExportConfigsSTEP.bas` (untested): `cfd/geometry/cfd_body_A.STEP` ... `_D.STEP` plus `export_log.txt` with mass and CG per configuration (the CG here is of the aero body only; the car's CG comes from the full assembly).

## Beginner mistakes

- Inserting the left-hand parts too and then cutting: fine, but doubles the Combine time. Insert right-hand only.
- Combine failing on "zero-thickness geometry": two bodies that share a face exactly (the sidepod's inner face on the body skin). Make one of them 1 mm bigger.
- Shelled bodies in the CFD body: the body skin, pods and wings are shelled in their own parts for mass; for the CFD body use the **solid** version (insert the part with the shell feature suppressed via a `solid` configuration in the source part, or Combine before shelling). Add a configuration `solid` to `body_main`, `sidepod`, each wing element and the endplates in which the Shell is suppressed; insert those here. A hollow shell in CFD creates an internal fluid region and Fluent Meshing will ask which region is the fluid.
- Forgetting the rim drum: a rim with a hollow barrel is an open cavity; the Watertight workflow then fails to find a closed fluid region.
- Export in metres: SolidWorks exports in the document units (mm). Fluent Meshing is told mm at import; do not scale in SolidWorks.

## End-of-part check (this is the Ring 2 "CFD body passes Check" item)

- Check: 1 solid, 0 open surfaces, 0 short edges under 0.3 mm, in every configuration A to D.
- Section at Z 1: only tyre flats. Section at Y 0.5: the symmetry face is flat and complete.
- Mass Properties volume per configuration listed in `export_log.txt`; A smallest, D largest.
- STEP files open again in SolidWorks (File > Open the STEP, Import Diagnostics shows no faulty faces).
