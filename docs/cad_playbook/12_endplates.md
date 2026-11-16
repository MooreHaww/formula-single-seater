# 12 Endplates (`cad/aero/fw_endplate.SLDPRT`, `rw_endplate.SLDPRT`)

Flat plates at each wing tip. On variant D the rear endplate gets a louvred top edge and a rearward extension that the plan calls "tuned for the wake" (the idea: more upwash and a stronger tip vortex, which makes the wake dirtier and the measurement more interesting).

## Inputs

Front: `fw_endplate_height` 350, `fw_endplate_length` 850, position Y = +-800 (`fw_span/2`), bottom at Z 30 (below the main element's lowest point of 60 so it works as a skirt), leading edge 100 mm ahead of the main element LE. Rear: `rw_endplate_height` 550, `rw_endplate_length` 950, Y = +-625, top at Z = `rw_height` + 320 (clears the flap 2 TE at configuration D by about 40 mm; **verify** by measuring), trailing edge at X 2300. Thickness 6 mm.

## Feature order (rear endplate, right side)

1. Template, insert the layout (the RW_POSITION sketch, so the plate can be sized to the elements).
2. **Sketch `plate`** on a plane parallel to CENTRE at Y = `="rw_span"/2`: a rectangle `rw_endplate_length` x `rw_endplate_height`, trailing edge at X 2300, top at the Z above, then round the forward-top corner R 150 and cut the lower-rear corner at 45 deg (100 mm) so it looks like a wing endplate rather than a plank.
3. Extrude 6 mm outward (away from the centreline).
4. **Variant D features**: three louvre slots 150 x 15 at the top edge, 30 mm apart, angled 30 deg (Cut-Extrude), and a 120 mm rearward extension of the top edge (a second sketch, extrude, merge). Suppressed in B and C.
5. Material custom 1600 kg/m3. Mass about 1.3 kg.

Front endplate: same recipe with the front sizes, Y = +-800, extrude outward, a foot plate 80 mm wide at the bottom turned inward (a second extrude from a sketch on GROUND offset 30) in all configurations. No variant features on the front plate.

## Configurations

`B`, `C` (identical plate), `D` (louvres and extension on the rear plate). Front plate: `Default`.

## Mates

Named planes to the layout. The elements pass through the plate (the plate is extruded outward from the tip plane, so the element tips are coincident with the plate's inner face; no mate needed beyond the three planes).

## Beginner mistakes

- Extruding inward: the plate then overlaps the element tips and the Combine for the CFD body creates a sliver. Extrude outward only.
- Endplate not reaching the ground-side of the front wing: the front plate's bottom at Z 30 is below the element; this is intentional (skirt). Do not "fix" it to Z 60.
- Louvres cut through the element: the slots are in the top 60 mm of the plate, above the flap 2 TE. Check the side view at configuration D.

## End-of-part check

- The plate's inner face is at Y = span/2 exactly (Measure to CENTRE: 625 rear, 800 front).
- Configuration D rebuilds with the louvres; B and C without.
- Mass 1 to 1.5 kg.
