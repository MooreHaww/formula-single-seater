# Cornering balance study (variant C, four-wheel steady-state model)

Written by `matlab/lapsim/cornering_balance_study.m`. Grip-limited corner speed from `cornering_balance.m`: lateral load transfer per axle (roll stiffness, roll centres, unsprung mass), tyre load sensitivity, limit set by the axle that reaches 100 % of its capacity first. `v_max` is capped by the power/drag top speed (155 km/h); `balance` = front-axle use minus rear-axle use at that speed, positive = understeer at the limit. `point-mass` is the old lap-sim answer (mu at the average wheel load, no transfer).

| R (m) | front weight | front aero | v grip (km/h) | v max (km/h) | lat g | limits | balance (%) | FO / FI / RO / RI (N) | point-mass (km/h) |
|---|---|---|---|---|---|---|---|---|---|
| 45 | 35.0 % | 0.35 (rear-heavy) | 114.6 | 114.6 | 2.30 | rear | -6.8 | 1504 / 372 / 2983 / 500 | 119.9 |
| 45 | 35.0 % | 0.45 (as filed) | 108.8 | 108.8 | 2.07 | rear | -21.5 | 1517 / 495 / 2675 / 434 | 119.9 |
| 45 | 35.0 % | 0.55 (front-heavy) | 103.8 | 103.8 | 1.88 | rear | -32.1 | 1526 / 597 / 2420 / 381 | 119.9 |
| 45 | 41.5 % | 0.35 (rear-heavy) | 113.1 | 113.1 | 2.24 | front | +7.0 | 1686 / 357 / 2721 / 534 | 119.9 |
| 45 | 41.5 % | 0.45 (as filed) | 113.1 | 113.1 | 2.24 | rear | -9.8 | 1804 / 476 / 2602 / 416 | 119.9 |
| 45 | 41.5 % | 0.55 (front-heavy) | 107.0 | 107.0 | 2.00 | rear | -22.8 | 1784 / 596 / 2311 / 356 | 119.9 |
| 45 | 47.0 % | 0.35 (rear-heavy) | 108.4 | 108.4 | 2.05 | front | +16.3 | 1769 / 369 / 2393 / 573 | 119.9 |
| 45 | 47.0 % | 0.45 (as filed) | 116.5 | 116.5 | 2.37 | front | +1.6 | 2063 / 445 / 2519 / 416 | 119.9 |
| 45 | 47.0 % | 0.55 (front-heavy) | 110.6 | 110.6 | 2.14 | rear | -14.0 | 2038 / 582 / 2231 / 339 | 119.9 |
| 100 | 35.0 % | 0.35 (rear-heavy) | 333.8 | 154.6 (power) | 1.88 | rear | -3.8 | 1750 / 823 / 3406 / 1373 | 154.6 |
| 100 | 35.0 % | 0.45 (as filed) | 258.9 | 154.6 (power) | 1.88 | rear | -17.1 | 1971 / 1044 / 3185 / 1151 | 154.6 |
| 100 | 35.0 % | 0.55 (front-heavy) | 213.5 | 154.6 (power) | 1.88 | rear | -29.7 | 2192 / 1266 / 2964 / 930 | 154.6 |
| 100 | 41.5 % | 0.35 (rear-heavy) | 281.8 | 154.6 (power) | 1.88 | front | +6.7 | 1939 / 823 / 3213 / 1377 | 154.6 |
| 100 | 41.5 % | 0.45 (as filed) | 305.7 | 154.6 (power) | 1.88 | rear | -6.8 | 2160 / 1044 / 2992 / 1155 | 154.6 |
| 100 | 41.5 % | 0.55 (front-heavy) | 236.8 | 154.6 (power) | 1.88 | rear | -19.8 | 2381 / 1266 / 2771 / 934 | 154.6 |
| 100 | 47.0 % | 0.35 (rear-heavy) | 239.0 | 154.6 (power) | 1.88 | front | +15.4 | 2103 / 822 / 3046 / 1382 | 154.6 |
| 100 | 47.0 % | 0.45 (as filed) | 335.3 | 154.6 (power) | 1.88 | front | +1.8 | 2324 / 1043 / 2825 / 1160 | 154.6 |
| 100 | 47.0 % | 0.55 (front-heavy) | 268.9 | 154.6 (power) | 1.88 | rear | -11.2 | 2545 / 1264 / 2603 / 939 | 154.6 |

## Driver 100 mm forward (mass_budget moves, CG height follows)

| case | R (m) | front weight | CG z (mm) | v grip (km/h) | v max (km/h) | limits | balance (%) |
|---|---|---|---|---|---|---|---|
| as filed | 45 | 41.5 % | 314 | 113.1 | 113.1 | rear | -9.8 |
| as filed | 100 | 41.5 % | 314 | 305.7 | 154.6 (power) | rear | -6.8 |
| driver forward | 45 | 43.0 % | 314 | 114.3 | 114.3 | rear | -6.9 |
| driver forward | 100 | 43.0 % | 314 | 321.4 | 154.6 (power) | rear | -4.5 |

## Lap times with the four-wheel corner limit (`lapsim` option `four_wheel`)

| case | track | point-mass (s) | four-wheel (s) | cost (s) |
|---|---|---|---|---|
| as filed | autocross | 60.70 | 61.95 | +1.25 |
| as filed | fast_circuit | 79.73 | 80.08 | +0.35 |
| driver forward | autocross | 60.83 | 61.89 | +1.06 |
| driver forward | fast_circuit | 79.73 | 79.93 | +0.20 |

## Assumptions these numbers depend on

- tyre: mu_peak 1.40 at 750 N, load sensitivity exponent 0.10 (file starting values, no tyre data)
- cg_height 314 mm from the mass budget (25 % of the mass is a GUESS)
- roll-centre heights 60 / 69 mm (suspension_geometry static), held fixed with roll
- roll stiffness split 38 % front from ride frequencies 3.2 / 3.5 Hz; no anti-roll bars, tyre stiffness ignored
- aero: ClA 4.0, CdA 1.45, balance 0.45 front, no CFD yet; downforce adds load without lateral transfer
- steady state only: no yaw moment, no slip angles, no camber, no transient, no driver
- unsprung mass 22.2 kg per axle at wheel-centre height (all GUESS lines)
