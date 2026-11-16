# Ring report template

Filled in at the end of each ring from the check results and pasted to the overseeing chat. Keep the lines; replace the angle-bracket fields. Numbers come from `run_all.m` output or the study reports, never from memory.

```
RING <n> REPORT: <ring name> (Formula Single-Seater, #7)
Status: done / done with cuts / blocked
Dates: <start> to <end>, about <h> hours (plan: <h>)
Exists now: <files and folders added>
Checks: <each check: pass/fail + the number>
Headline number(s): <e.g. torsional stiffness 1,850 Nm/deg>
Cut or changed vs plan: <items, one line each>
Known limits: <what not to trust>
Next ring: <name>, starts <date>
Needs a decision from you: <none / question>
```

## Checks per ring (from the work plan, with the agreed changes)

**Ring 0, Learning ramp**
- Screenshot of the practice assembly with rim, hub and bracket mated.
- Changing one number in the linked text file and pressing Rebuild changes the part (yes/no).
- The 0 to 100 km/h time printed by `accel_test.m`.
- Fluent smoke test ran and gave a drag number (yes/no, and the number).

**Ring 1, Concept and parameters**
- `params/car_params.txt` opens in MATLAB with `read_car_params` and prints a table.
- Layout sketch shows driver, motor, battery and wheels inside the wheelbase with no overlaps.

**Ring 2, CAD**
- Assembly rebuilds with zero errors (screenshot of a clean feature tree).
- Interference Detection shows no clashes apart from accepted ones.
- Changing wheelbase by 50 mm in the text file rebuilds the whole car without errors.
- Mass and CG height from Mass Properties (written back into `car_params.txt`).
- Each CFD body passes Check as a single closed solid.

**Ring 3, Motion**
- Motion study solves the full travel with no redundant-constraint failure.
- Camber gain front and rear (number and sign: inward at the top in bump).
- Bump steer over the full travel.
- Motion ratio front and rear.

**Ring 4, Stress**
- Upright minimum factor of safety (target above 2 against yield) and where the peak sits.
- Peak stress at both mesh sizes.
- Chassis torsional stiffness in Nm/deg and chassis mass.

**Ring 5, CFD**
- Each run's residuals and force monitors flattened out (screenshot).
- ClA and CdA for A, B, C.
- Change in C's numbers between the two mesh sizes, in percent.
- Dynamic pressure ratio at one car length for A and C.

**Ring 6, Lap time**
- Skidpad and acceleration times match the hand calculation within 2 % (the self-tests in `lapsim.m` and `accel_test.m`).
- `run_all.m` runs clean from a fresh MATLAB session.
- Lap times for A, B, C on both tracks.
- Seconds gained by wings on each track, and seconds lost when following.
- Added: maximum speed through fixed-radius corners per variant against downforce (`media/cornering_speed_vs_downforce.png`), including the fast circuit's high-speed corners.
- Simulink 6b 75 m time agrees with `accel_test.m` within 1 %.

**Ring 7, Release**
- README renders on GitHub with images loading.
- Fresh clone opens and runs.
- Release page shows three assets.
- Headline lap time in the README matches `run_all.m` output exactly.
