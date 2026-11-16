# 09 Floor and diffuser (`cad/aero/floor_diffuser.SLDPRT`)

One flat plate with a rising rear section. Variants: the floor is on all configurations; the diffuser angle changes between C and D and the diffuser is absent (flat floor ending at the rear axle) in A and B.

## Inputs

`floor_width` 1100, `floor_start_from_front_axle` 300, `diffuser_length` 600, `diffuser_angle_C` 12, `diffuser_angle_D` 14, `diffuser_exit_height` 220, `ride_height_front` 35, `ride_height_rear` 50, `wheelbase` 1550, rear tyre inner faces at Y +-485 (X 1460 to 1640). Thickness 10 mm (sandwich panel).

## Feature order

1. Template, insert the layout.
2. **Sketch `plan`** on GROUND: the floor outline, right half then Mirror Entities. Leading edge at X = `="floor_start_from_front_axle"` (300), straight sides at Y = `="floor_width"/2` (550) from X 300 to X 1400, then a step inboard to Y 470 from X 1400 to X 1700 (clearing the rear tyres at Y 485 with 15 mm), trailing edge at X = `="wheelbase" + "diffuser_length"/2`? No: the diffuser starts at the rear axle and is `diffuser_length` long, so the floor plan runs to X = `="wheelbase" + "diffuser_length"` = 2150. The step at X 1400 to 1700 is where the tyres are; the floor is narrower there.
3. Extrude 10 mm upward from GROUND offset `="ride_height_front"` (35): Insert > Boss/Base > Extrude, "Offset from surface"? Simpler: sketch on a plane `FLOOR_PLANE` offset 35 from GROUND and extrude 10 up. The real floor rakes from 35 at the front to 50 at the rear axle (rake 0.55 deg); v1 keeps it flat at 35 and notes the rake as a v2 item in `docs/ideas.md`. **verify** with the CFD body that the flat floor at 35 does not intersect the rear tyre flats (tyres are at Z 0 to 457; the floor is a plate at Z 35 to 45 outside the tyre footprints by the step, so fine).
4. **Diffuser**: sketch on CENTRE a profile: from the floor's rear top edge at X 1550 (the rear axle) a line rising at `="diffuser_angle_C"` for `diffuser_length` 600 in X, closing back down to the floor plane. Cut-Extrude? No: the diffuser is a separate thin body: Extrude the diffuser plate profile (a 10 mm thick inclined plate from X 1550 to 2150, rising 600 x tan 12 = 128 mm) "Mid plane" across `floor_width` minus the tyre step (940 wide), then Cut the flat floor region under it (the flat floor ends at X 1550 in C and D). Order: step 3 extrudes the flat floor only to X 1550 in configurations C/D (Configure Dimension on the plan's trailing-edge X) and to X 1550 as well in A/B (a flat floor to the axle, no diffuser). So: flat floor always ends at X 1550; the diffuser plate exists in C and D only.
5. **Diffuser strakes**: two vertical fences per side, 120 mm high, 10 mm thick, at Y +-150 and +-350, along the diffuser length. Extrude from the diffuser top face. Cosmetic in CFD at this mesh size; include anyway (they define the variant).
6. **Diffuser exit height check**: at X 2150 the top of the diffuser plate is at Z 35 + 10 + 128 = 173 for 12 deg and 185 for 14 deg; `diffuser_exit_height` 220 is the height of the fences' top at the exit; dimension the fence height so the top is at 220.
7. Material custom sandwich 400 kg/m3 (10 mm thick): mass about 5 kg.

## Configurations

`A`, `B`: diffuser plate and strakes suppressed. `C`: angle `diffuser_angle_C`. `D`: angle `diffuser_angle_D`. Configure Feature (suppress) and Configure Dimension (angle) from the ConfigurationManager.

## Mates

Named planes to the layout.

## Beginner mistakes

- A diffuser angle dimension that references the floor plane: the angle must be from the GROUND direction (horizontal), so dimension the inclined line to a horizontal construction line.
- Forgetting that configurations in a part are independent of the assembly's: the assembly's configuration C must "use" the part's configuration C (right-click the part in the assembly > Component Properties > Referenced configuration, or the Configure Component table). `15_assembly.md` covers it.
- Extruding the floor from GROUND at Z 0: the tyres' contact flats are also at Z 0 and the floor would touch the ground. The floor sits at ride height.

## End-of-part check

- Four configurations rebuild; in A the part is a flat plate ending at X 1550; in D the diffuser top reaches Z 185 at X 2150.
- No interference with the rear tyres (the step keeps 15 mm).
- Mass 4 to 6 kg.
