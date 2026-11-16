# sim/motion/ (Ring 3)

SolidWorks Motion study exports go here. `matlab/suspension_plots.m` reads two files:

| File | Corner |
|---|---|
| `front_bump.csv` | front, 30 mm bump to 30 mm droop |
| `rear_bump.csv` | rear, same |

Required columns (header row, any order):

```
wheel_travel_mm,camber_deg,toe_deg,track_change_mm,spring_length_mm
```

- `wheel_travel_mm`: positive = bump (wheel up relative to the chassis).
- `camber_deg`: negative = top of the wheel leans inward. Expect a negative slope in bump.
- `toe_deg`: positive = toe-in.
- `track_change_mm`: lateral movement of the contact patch, positive = outward.
- `spring_length_mm`: length between the spring seats.

## Getting the CSV out of SolidWorks Motion

1. In the motion study, add one Result plot per quantity (Results and Plots > Displacement/Velocity/Acceleration > Angular Displacement for camber and toe between the upright and the chassis plane, Linear Displacement for travel, track and spring length).
2. Right-click each plot > Export CSV. SolidWorks writes `time, value` pairs.
3. Combine the five exports into one CSV with the column names above (Excel, or `matlab/suspension_plots.m` can be adapted: see the `synthetic_data` function for the exact table shape). The time column is not needed because the linear motor moves the wheel at constant speed, so travel is linear in time; keep `wheel_travel_mm` as the first column anyway.

Until the files exist the script runs on synthetic data and says so in every figure title.

Also planned here: `steering_sweep.csv` (rack travel, inner wheel angle, outer wheel angle) for the Ackermann check, and the GIF of one corner moving (goes to `media/`).
