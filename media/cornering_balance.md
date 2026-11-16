# Cornering balance study (variant C, four-wheel steady-state model)

Written by `matlab/lapsim/cornering_balance_study.m`. Grip-limited corner speed from `cornering_balance.m`: lateral load transfer per axle (roll stiffness, roll centres, unsprung mass), tyre load sensitivity, limit set by the axle that reaches 100 % of its capacity first. `v_max` is capped by the power/drag top speed (155 km/h); `balance` = front-axle use minus rear-axle use at that speed, positive = understeer at the limit. `point-mass` is the old lap-sim answer (mu at the average wheel load, no transfer).

| R (m) | front weight | front aero | v grip (km/h) | v max (km/h) | lat g | limits | balance (%) | FO / FI / RO / RI (N) | point-mass (km/h) |
|---|---|---|---|---|---|---|---|---|---|
| 45 | 35.0 % | 0.35 (rear-heavy) | 114.5 | 114.5 | 2.29 | rear | -6.8 | 1504 / 372 / 2985 / 499 | 119.8 |
| 45 | 35.0 % | 0.45 (as filed) | 108.8 | 108.8 | 2.07 | rear | -21.5 | 1517 / 495 / 2677 / 434 | 119.8 |
| 45 | 35.0 % | 0.55 (front-heavy) | 103.8 | 103.8 | 1.88 | rear | -32.1 | 1526 / 596 / 2421 / 381 | 119.8 |
| 45 | 41.4 % | 0.35 (rear-heavy) | 113.2 | 113.2 | 2.24 | front | +6.8 | 1686 / 357 / 2726 / 533 | 119.8 |
| 45 | 41.4 % | 0.45 (as filed) | 113.0 | 113.0 | 2.23 | rear | -10.0 | 1802 / 476 / 2603 / 415 | 119.8 |
| 45 | 41.4 % | 0.55 (front-heavy) | 106.9 | 106.9 | 2.00 | rear | -22.8 | 1782 / 595 / 2314 / 356 | 119.8 |
| 45 | 47.0 % | 0.35 (rear-heavy) | 108.4 | 108.4 | 2.05 | front | +16.3 | 1770 / 368 / 2394 / 573 | 119.8 |
| 45 | 47.0 % | 0.45 (as filed) | 116.5 | 116.5 | 2.37 | front | +1.6 | 2064 / 444 / 2520 / 416 | 119.8 |
| 45 | 47.0 % | 0.55 (front-heavy) | 110.5 | 110.5 | 2.13 | rear | -14.0 | 2039 / 582 / 2232 / 339 | 119.8 |
| 100 | 35.0 % | 0.35 (rear-heavy) | 333.1 | 154.6 (power) | 1.88 | rear | -3.8 | 1751 / 823 / 3409 / 1372 | 154.6 |
| 100 | 35.0 % | 0.45 (as filed) | 258.5 | 154.6 (power) | 1.88 | rear | -17.1 | 1972 / 1044 / 3188 / 1151 | 154.6 |
| 100 | 35.0 % | 0.55 (front-heavy) | 213.3 | 154.6 (power) | 1.88 | rear | -29.7 | 2194 / 1265 / 2966 / 929 | 154.6 |
| 100 | 41.4 % | 0.35 (rear-heavy) | 282.0 | 154.6 (power) | 1.88 | front | +6.6 | 1939 / 823 / 3217 / 1376 | 154.6 |
| 100 | 41.4 % | 0.45 (as filed) | 304.5 | 154.6 (power) | 1.88 | rear | -6.9 | 2160 / 1044 / 2996 / 1155 | 154.6 |
| 100 | 41.4 % | 0.55 (front-heavy) | 236.3 | 154.6 (power) | 1.88 | rear | -19.8 | 2381 / 1265 / 2775 / 934 | 154.6 |
| 100 | 47.0 % | 0.35 (rear-heavy) | 238.7 | 154.6 (power) | 1.88 | front | +15.4 | 2104 / 821 / 3048 / 1381 | 154.6 |
| 100 | 47.0 % | 0.45 (as filed) | 334.6 | 154.6 (power) | 1.88 | front | +1.8 | 2326 / 1043 / 2827 / 1160 | 154.6 |
| 100 | 47.0 % | 0.55 (front-heavy) | 268.5 | 154.6 (power) | 1.88 | rear | -11.2 | 2547 / 1264 / 2606 / 939 | 154.6 |

## Driver 100 mm forward (mass_budget moves, CG height follows)

| case | R (m) | front weight | CG z (mm) | v grip (km/h) | v max (km/h) | limits | balance (%) |
|---|---|---|---|---|---|---|---|
| as filed | 45 | 41.4 % | 314 | 113.0 | 113.0 | rear | -10.0 |
| as filed | 100 | 41.4 % | 314 | 304.5 | 154.6 (power) | rear | -6.9 |
| driver forward | 45 | 42.9 % | 314 | 114.2 | 114.2 | rear | -7.0 |
| driver forward | 100 | 42.9 % | 314 | 320.1 | 154.6 (power) | rear | -4.6 |

## Lap times with the four-wheel corner limit (`lapsim` option `four_wheel`)

| case | track | point-mass (s) | four-wheel (s) | cost (s) |
|---|---|---|---|---|
| as filed | autocross | 60.71 | 61.96 | +1.25 |
| as filed | fast_circuit | 79.73 | 80.09 | +0.36 |
| driver forward | autocross | 60.84 | 61.90 | +1.07 |
| driver forward | fast_circuit | 79.74 | 79.94 | +0.20 |

## Assumptions these numbers depend on

- tyre: mu_peak 1.40 at 750 N, load sensitivity exponent 0.10 (file starting values, no tyre data)
- cg_height 314 mm from the mass budget (25 % of the mass is a GUESS)
- roll-centre heights 60 / 69 mm (suspension_geometry static), held fixed with roll
- roll stiffness split 38 % front from ride frequencies 3.2 / 3.5 Hz; no anti-roll bars, tyre stiffness ignored
- aero: ClA 4.0, CdA 1.45, balance 0.45 front, no CFD yet; downforce adds load without lateral transfer
- steady state only: no yaw moment, no slip angles, no camber, no transient, no driver
- unsprung mass 22.2 kg per axle at wheel-centre height (all GUESS lines)
