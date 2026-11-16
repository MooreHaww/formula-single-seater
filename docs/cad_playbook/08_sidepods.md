# 08 Sidepods and cockpit skin (`cad/body/sidepod.SLDPRT`, `cad/body/cockpit_skin.SLDPRT`)

The body between the front hoop and the rear axle: a cockpit skin that closes the frame and two sidepods (one part, mirrored) that hold the battery cooling (block) and shape the flow onto the floor. The electric car has no radiators to feed; the sidepods are kept slim.

## Inputs

Front hoop at X = 650 (section 640 x 540 from the nose), main hoop at X = `main_hoop_x` 1250 (hoop width 620 at the base, top at `main_hoop_height` 980), side-impact tubes at Z 80 and 350 at Y +-290 to 310, floor width `floor_width` 1100, wheels: front tyre inner face at Y = 600 - 90 = 510 (X -90 to 90), rear tyre inner face at Y = 575 - 90 = 485 (X 1460 to 1640). Sidepod envelope: X 700 to 1400, Y from the frame (310) to 540, Z 60 to 330.

## Cockpit skin: feature order

1. Template, insert the layout. Sections at X = 650 (the nose's last section, converted), X = 950 (rounded rectangle 660 x 560, bottom 60, top cut flat at Z 620), X = 1250 (660 x 600 following the main hoop legs, bottom 60). Loft with the top spline and bottom line as guides, start constraint "Tangent to face"? Not across parts; use "Normal to profile" at both ends and accept a small crease at X = 650, or (better) make the nose and the cockpit skin one part with eight sections. **Decision for v1: one part `body_main.SLDPRT` from the nose tip to X = 1250 (nose + cockpit), and the sidepods separate.** Rename `07_nose.md`'s file accordingly; the sections table extends with the two above.
2. Cockpit opening: Cut-Extrude from a plane at Z 700, rounded rectangle from X 650 to 1350 (`cockpit_opening_length` 700) x 400 wide, corner R 100, through all downward. The driver gets in through it; the rules template is 350 x 300 at the front, so this is generous.
3. Shell 2 mm, remove the rear face at X = 1250.
4. Rear closure: the engine cover equivalent, a loft from the X = 1250 section down to a 300 x 200 section at X = 1900 (behind the motor at `motor_x` 1850), top following the main hoop braces (top spline from Z 980 at X 1250 to Z 320 at X 1900). This encloses the battery and motor. Make it the same part: profiles X 1250 and 1900, guide splines, loft, shell 2 mm with no removed face, then Combine (Insert > Features > Combine, Add) with the forward skin. If Combine fails on the shared face, keep the rear cover as its own part `rear_cover.SLDPRT`.

## Sidepod: feature order (right side)

1. Sections on planes parallel to FRONT_AXLE: X = 700 (leading edge, an ellipse 60 wide x 180 high, centred Y 420, Z 170), X = 900 (rounded rectangle Y 320 to 540, Z 70 to 330, R 40), X = 1200 (same), X = 1400 (trailing, Y 330 to 480, Z 70 to 250, R 30; it must clear the rear tyre inner face at Y 485 ahead of X 1460).
2. Loft, guides: a top spline on a plane at Y = 430 and the outer side spline on GROUND.
3. Inlet: Cut-Extrude a 40 x 120 rounded slot at the leading edge, 150 mm deep, for the battery-cooling duct (block). Optional.
4. Shell 2 mm, remove the inboard face (the body side), so the pod is a skin that meets the main body.
5. Material custom 1600 kg/m3. Mass about 1 kg each.

## Mates

Named planes to the layout. Left sidepod: Mirror Components about CENTRE in the assembly.

## Configurations

`Default`.

## Beginner mistakes

- Sidepod wider than the tyre inner face: the rear tyre at full steering (none at the rear) and the front tyre at lock (28 deg) sweep a volume; the front tyre at lock reaches X 0 +- 250 and Y up to 700, well ahead of the pod at X 700. Check with the WHEELS sketch anyway.
- Shelling a loft with a tight corner radius (R 30) at 2 mm: fine. At R under 5 it fails.
- Forgetting the floor: the body bottom is at Z 60; the floor (`09_floor_diffuser.md`) is a separate flat part at Z 50 to 60 that the pods sit on. Do not model the floor into the pods.

## End-of-part check

- Interference Detection between body_main, sidepods, chassis and wheels (assembly, Tools > Evaluate > Interference Detection): none except the skin-to-tube contacts you accept (the skin passes 10 mm outside the tubes; if it touches, enlarge the section).
- Mass: body_main 3 to 4 kg, sidepods 1 kg each.
- Zebra stripes smooth along the loft.
