# Variant E: a lower, more turbulent wake at C's downforce

**Written on 2026-11-18, before E was run.** The result is in the "Result" section at the bottom, added after the run. The prediction above it is left as it was written.

## Why D did not do it

D's extras were endplate fins, a beam wing and steeper rear-wing angles. They made small, strong vortices high on the car. At one car length behind the rear axle, D's wake centre sat even higher than C's: Z 1.38 m against 0.91 m. The turbulence intensity in the following car's window was 0.063, against 0.062 for C. At two lengths, the deficit in C's and D's windows had fallen to 0.04 to 0.05, because the wake had risen above the window (centre at Z 2.3 to 2.4 m).

The reason is a conservation law. A car with downforce F pushes air upwards at the same rate: the wake carries an upward momentum flux of F (Newton's third law, far-field momentum balance). For C at 20 m/s that is about 950 N. The upward momentum is carried by the trailing vortices of the downforce-producing elements. Between the two tip vortices of the rear wing the air moves up, and it carries the slow, turbulent air of the body and driver wake with it. Adding more vortices high up (D) just adds more lift-off.

## What can be changed

The total upward momentum cannot be avoided without losing downforce. Where it starts, and how concentrated it is, can be changed.

1. **Upwash rate.** A rear wing of load L and span b leaves a vortex pair with circulation G = L / (rho U b). The pair drifts upward, carrying the wake, at about w = G / (2 pi b) = L / (2 pi rho U b^2).
   - For C: L about 500 N (rear wing ClA 2.09), U 20 m/s, b 1.25 m, so w is about 2.1 m/s, a rise of about 0.3 m per car length from the vortex pair alone.
   - The near wake also rises because the flap jet leaves at a steep angle (12 deg upwash at 0.5 L).
   - A wider wing spreads the same load: w goes with 1/b^2.
2. **Starting height.** A lower rear wing starts its vortex pair and its flap jet lower. The whole wake that the pair lifts starts lower too.
3. **Turbulence at the following car's height.** A separated, bluff base sheds turbulence where it sits. A body cut off square (a Kamm-type blunt base) at the height of the following car's front wing and wheels puts turbulent, slow air there. Base suction just above the diffuser exit also helps the diffuser pull more air through (lower exit pressure), which adds floor downforce.
4. **Downforce kept low down.** Floor downforce is generated close to the ground, and its upwash starts at the diffuser exit, at Z 0.2 m instead of 1.2 m.

## Variant E (C with these changes)

| Change | E | C | Expected effect |
|---|---|---|---|
| Rear wing height (main element leading edge) | 950 mm | 1150 mm | wake starts 200 mm lower; the wing sits closer to the roll-hoop and helmet wake: less rear-wing load (my guess: 5 to 15 % less) |
| Rear wing span | 1330 mm (to the rear tyres' outer faces) | 1250 mm | b^2 up 13 %: upwash rate down about 12 % at equal load; 6 % more wing area |
| Rear wing angles | D's (11 / 34 / 56 deg) | 9 / 32 / 52 deg | about 5 % more rear-wing load (D's rear wing ClA 2.20 against C's 2.09): offsets part of the height loss |
| Diffuser angle | 14 deg (as D) | 12 deg | more floor downforce (D's floor ClA 0.49 against C's 0.40, partly from its beam wing) |
| Body tail | cut square at X 1745 (blunt base, about 0.44 m wide, Z 0.10 to 0.49 m); **moved to X 1700 before the run**, because at 1745 the cut left sliver faces against the diffuser and the surface mesh failed (`cfd/geometry_notes.md`) | tapers to X 1900 | turbulent base wake at the following car's front wing and wheel height; base suction over the diffuser exit; more drag (base drag, my estimate +0.03 to +0.05 m2 CdA) |

The front wing, floor plan, wheels and sidepods are as C. Cell budget: wing surface about 6 % larger, body surface slightly smaller. E should mesh at about C's size (955,009 cells), under the 1,048,576 limit with room for the wake-window refinement.

**Prediction:**
- ClA within about 10 % of C. The constraint "at least C's downforce" is the uncertain part: the lower rear wing loses load in the hoop wake, and the diffuser, base suction, wider span and D angles have to make that up.
- CdA higher than C by 0.05 to 0.15 m2.
- At 1 L, the wake centre is lower than C's (0.91 m) by 0.2 to 0.4 m.
- In the low window (Z 0 to 0.6 m), turbulence kinetic energy and velocity deficit are higher than C's at 1 L and 2 L.

**Success** means all three of these, compared with C on the same mesh settings:
1. ClA_E >= ClA_C.
2. More TKE and deficit in the following car's window at 1 and 2 L.
3. A lower wake centre.

## Result

(added after the run, 2026-11-18. Two meshes: E, 964,025 cells, against C, 955,009; and E_w, 1,046,660 cells, against C_w, 1,037,523. The `_w` meshes add 50 mm cells in three boxes at 1, 2 and 3 car lengths behind the rear axle, with about 2,000 nodes per window region against 300.)

**Verdict: E did not do what it was meant to do.** It kept C's downforce, but its wake is higher than C's, not lower. In the following car's low window it has less turbulence and less velocity deficit than C. Of the three success criteria, only the first is met.

### Forces (full car, 20 m/s, mean of the last 200 iterations)

| Run | ClA | CdA | front share | force band (last 200 it) | lap sim autocross / fast circuit (s) |
|---|---|---|---|---|---|
| C | 3.98 | 1.63 | 0.45 | 0.04 % | 61.09 / 82.58 |
| E | 4.03 (+1.2 %) | 1.71 (+4.4 %) | 0.45 | 3.1 % | 61.07 / 83.56 |
| E_w | 4.05 (+1.6 %) | 1.72 (+5.2 %) | 0.45 | 5.5 % | 61.04 / 83.72 |

- **Unsteady.** E's forces swing by 3 to 6 % between iterations, against 0.04 % for C. It never met the force stop and ran the full 1200 iterations. The blunt base sheds vortices, so a steady solver cannot settle on one answer. The means drift by only 0.2 % (E) and 0.7 % (E_w) between the last two 200-iteration windows, so the mean ClA is good to about 1 %. The wake planes and boxes are single snapshots of an unsteady flow, uncertain by about 10 % (E and E_w differ by that much).
- **Where the downforce comes from (half car, N, E against C):**
  - front wing: 239 against 241;
  - rear wing: 249 against 251;
  - floor: 50 against 48;
  - body: −40 against −46 (less lift).
  - The lower rear wing did not lose load: the hoop wake cost nothing measurable. Together with D's angles and the wider span, it gives the same rear-wing load as C. The steeper diffuser added only 2 N. The rest of the gain is less body lift from the cut tail.
- **Drag:** +4 to 5 %, about half of the +0.05 to 0.15 m² predicted. The blunt base costs less than I estimated.

### Wake (window boxes; low = Z 0 to 0.5 m, the following car's front wing and wheels; high = Z 1.0 to 1.5 m, its rear wing)

| Metric | box | C_w | E_w | change |
|---|---|---|---|---|
| wake centre height (minimum total pressure), Z m | 0.5 L | 0.15 | 0.47 | higher |
| | 1 L | 0.95 | 1.49 | higher |
| upwash at 0.5 L (window mean) | | 11.8 deg | 14.6 deg | steeper |
| TKE (m²/s²), low | 1 L | 1.50 | 1.15 | −24 % |
| | 2 L | 0.21 | 0.16 | −25 % |
| velocity deficit, low | 1 L | 0.115 | 0.103 | −11 % |
| | 2 L | 0.026 | 0.020 | −24 % |
| TKE, high | 1 L | 3.92 | 5.02 | +28 % |
| | 2 L | 1.98 | 2.94 | +48 % |
| | 3 L | 0.74 | 2.92 | ×4 |
| velocity deficit, high | 1 L | 0.27 | 0.26 | −4 % |
| | 2 L | 0.09 | 0.16 | +78 % |
| | 3 L | 0.034 | 0.134 | ×4 |
| mean abs. x-vorticity (1/s), high | 1 L | 6.2 | 17.6 | ×2.8 |

The same comparison on the standard meshes (E against C) gives the same signs: low-window TKE at 1 L 1.22 against 1.44, deficit 0.108 against 0.124; wake centre at 1 L Z 1.28 against 0.91 m.

### Why the prediction was wrong

The prediction assumed a lower wing starts the lift-off lower. It does start lower, but it also sits much closer to the slow, low air it is meant to leave behind:
- The rear wing's upwash and the suction under its main element act most strongly near the wing.
- With the wing 200 mm lower, and the body ending 200 mm earlier in a blunt base directly beneath and ahead of it, the base and diffuser wake is drawn up into the wing's flow at once.
- At 0.5 L, E's wake centre is already at Z 0.47 m against 0.15 m for C, and the upwash is 3 degrees steeper.
- C's wing, 200 mm higher, leaves more of the low body wake on the ground.

The upward momentum is still about equal to the downforce (the conservation argument holds, and E has slightly more downforce). What changed is which air it lifts. E lifts the low turbulent air, and its stronger, more concentrated tip vortices (x-vorticity ×2.8) keep that air turbulent much longer: ×4 TKE at 3 L.

So E made the wake **more turbulent and more persistent, but at the following car's rear-wing height (Z 1.0 to 1.5 m), not at its front-wing height.** For a following car, the front wing and floor in the low window matter most, and there E is cleaner than C.

### What I would try next (not run)

The low window needs turbulent air that the rear wing does not lift:
- keep the rear wing high (as C) and put the turbulence generator low and far from it, e.g. a blunt base at floor level with C's wing;
- or a diffuser with strong vortex-generating strakes that shed outward and down, under the wing's upwash zone.

The evidence from A (no wings: low-window TKE 2.8 at 1 L, double C's) says the most direct lever is less upwash behind the car. That is less rear-wing load, which conflicts with "at least C's downforce" unless the floor takes the load.
