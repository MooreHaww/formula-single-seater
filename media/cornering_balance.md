# Cornering balance study (variant C, four-wheel steady-state model)

Written by `matlab/lapsim/cornering_balance_study.m`. Grip-limited corner speed from `cornering_balance.m`: lateral load transfer per axle (roll stiffness, roll centres, unsprung mass), tyre load sensitivity, limit set by the axle that reaches 100 % of its capacity first. `v_max` is capped by the power/drag top speed (148 km/h); `balance` = front-axle use minus rear-axle use at that speed, positive = understeer at the limit. `point-mass` is the old lap-sim answer (mu at the average wheel load, no transfer).

| R (m) | front weight | front aero | v grip (km/h) | v max (km/h) | lat g | limits | balance (%) | FO / FI / RO / RI (N) | point-mass (km/h) |
|---|---|---|---|---|---|---|---|---|---|
| 45 | 35.0 % | 0.35 (rear-heavy) | 127.8 | 127.8 | 2.85 | rear | -6.7 | 1897 / 489 / 3761 / 672 | 134.9 |
| 45 | 35.0 % | 0.40 (target) | 122.8 | 122.8 | 2.64 | rear | -16.6 | 1881 / 581 / 3456 / 603 | 134.9 |
| 45 | 35.0 % | 0.49 (as filed) | 115.3 | 115.3 | 2.32 | rear | -29.4 | 1855 / 709 / 3023 / 508 | 134.9 |
| 45 | 35.0 % | 0.55 (front-heavy) | 110.4 | 110.4 | 2.13 | rear | -36.6 | 1837 / 786 / 2759 / 452 | 134.9 |
| 45 | 41.5 % | 0.35 (rear-heavy) | 123.7 | 123.7 | 2.68 | front | +9.5 | 2040 / 451 / 3351 / 735 | 134.9 |
| 45 | 41.5 % | 0.40 (target) | 130.9 | 130.9 | 2.99 | rear | -0.9 | 2312 / 534 / 3544 / 619 | 134.9 |
| 45 | 41.5 % | 0.49 (as filed) | 121.2 | 121.2 | 2.57 | rear | -17.3 | 2219 / 695 / 3011 / 502 | 134.9 |
| 45 | 41.5 % | 0.55 (front-heavy) | 115.1 | 115.1 | 2.32 | rear | -26.5 | 2162 / 787 / 2698 / 436 | 134.9 |
| 45 | 47.0 % | 0.35 (rear-heavy) | 116.6 | 116.6 | 2.38 | front | +20.0 | 2064 / 445 / 2880 / 776 | 134.9 |
| 45 | 47.0 % | 0.40 (target) | 122.7 | 122.7 | 2.63 | front | +12.1 | 2303 / 509 / 3018 / 687 | 134.9 |
| 45 | 47.0 % | 0.49 (as filed) | 128.2 | 128.2 | 2.87 | rear | -5.2 | 2619 / 661 / 3055 / 510 | 134.9 |
| 45 | 47.0 % | 0.55 (front-heavy) | 120.5 | 120.5 | 2.54 | rear | -16.6 | 2505 / 775 / 2679 / 430 | 134.9 |
| 100 | 35.0 % | 0.35 (rear-heavy) | 540.0 | 147.5 (power) | 1.71 | rear | -3.1 | 1842 / 998 / 3563 / 1711 | 147.5 |
| 100 | 35.0 % | 0.40 (target) | 508.3 | 147.5 (power) | 1.71 | rear | -9.1 | 1971 / 1127 / 3433 / 1581 | 147.5 |
| 100 | 35.0 % | 0.49 (as filed) | 345.3 | 147.5 (power) | 1.71 | rear | -18.8 | 2194 / 1350 / 3210 / 1358 | 147.5 |
| 100 | 35.0 % | 0.55 (front-heavy) | 276.7 | 147.5 (power) | 1.71 | rear | -25.9 | 2360 / 1516 / 3044 / 1192 | 147.5 |
| 100 | 41.5 % | 0.35 (rear-heavy) | 462.6 | 147.5 (power) | 1.71 | front | +6.0 | 2022 / 1006 / 3379 / 1706 | 147.5 |
| 100 | 41.5 % | 0.40 (target) | 540.0 | 147.5 (power) | 1.71 | rear | -0.1 | 2152 / 1136 / 3249 / 1576 | 147.5 |
| 100 | 41.5 % | 0.49 (as filed) | 454.7 | 147.5 (power) | 1.71 | rear | -9.9 | 2375 / 1359 / 3026 / 1353 | 147.5 |
| 100 | 41.5 % | 0.55 (front-heavy) | 334.8 | 147.5 (power) | 1.71 | rear | -17.2 | 2541 / 1525 / 2860 / 1187 | 147.5 |
| 100 | 47.0 % | 0.35 (rear-heavy) | 335.8 | 147.5 (power) | 1.71 | front | +13.6 | 2179 / 1012 / 3219 / 1703 | 147.5 |
| 100 | 47.0 % | 0.40 (target) | 453.9 | 147.5 (power) | 1.71 | front | +7.5 | 2308 / 1142 / 3089 / 1573 | 147.5 |
| 100 | 47.0 % | 0.49 (as filed) | 540.0 | 147.5 (power) | 1.71 | rear | -2.5 | 2531 / 1365 / 2866 / 1350 | 147.5 |
| 100 | 47.0 % | 0.55 (front-heavy) | 428.7 | 147.5 (power) | 1.71 | rear | -9.8 | 2697 / 1531 / 2700 / 1185 | 147.5 |

## Aero balance target

`aero_balance_target` = 0.40 in `params/car_params.txt` (ESTIMATE/target, not a result). The neutral share is the front aero fraction at which both axles reach their grip limit together at the file's weight distribution (41.5 % front); it moves with the assumed tyre load sensitivity, CG height and roll stiffness split.

| R (m) | neutral front aero | as filed | v grip (km/h) | balance (%) | target | v grip (km/h) | balance (%) |
|---|---|---|---|---|---|---|---|
| 45 | 0.396 | 0.49 | 121.2 | -17.3 | 0.40 | 130.9 | -0.9 |
| 100 | 0.404 | 0.49 | 454.7 | -9.9 | 0.40 | 540.0 | -0.1 |

Lap time with the four-wheel corner limit, front aero share as filed against the target:

| track | as filed (s) | target (s) | change (s) |
|---|---|---|---|
| autocross | 60.83 | 59.79 | -1.04 |
| fast_circuit | 82.81 | 82.38 | -0.43 |

## Driver 100 mm forward (mass_budget moves, CG height follows)

| case | R (m) | front weight | CG z (mm) | v grip (km/h) | v max (km/h) | limits | balance (%) |
|---|---|---|---|---|---|---|---|
| as filed | 45 | 41.5 % | 314 | 121.2 | 121.2 | rear | -17.3 |
| as filed | 100 | 41.5 % | 314 | 454.7 | 147.5 (power) | rear | -9.9 |
| driver forward | 45 | 43.0 % | 314 | 122.9 | 122.9 | rear | -14.2 |
| driver forward | 100 | 43.0 % | 314 | 494.2 | 147.5 (power) | rear | -7.9 |

## Lap times with the four-wheel corner limit (`lapsim` option `four_wheel`)

| case | track | point-mass (s) | four-wheel (s) | cost (s) |
|---|---|---|---|---|
| as filed | autocross | 59.19 | 60.83 | +1.64 |
| as filed | fast_circuit | 82.40 | 82.81 | +0.41 |
| driver forward | autocross | 59.32 | 60.73 | +1.42 |
| driver forward | fast_circuit | 82.41 | 82.72 | +0.32 |

## Assumptions these numbers depend on

- tyre: mu_peak 1.40 at 750 N, load sensitivity exponent 0.10 (file starting values, no tyre data)
- cg_height 314 mm from the mass budget (25 % of the mass is a GUESS)
- roll-centre heights 60 / 69 mm (suspension_geometry static), held fixed with roll
- roll stiffness split 38 % front from ride frequencies 3.2 / 3.5 Hz; no anti-roll bars, tyre stiffness ignored
- aero: ClA 5.15, CdA 1.66, balance 0.49 front as filed, target 0.40 (ESTIMATE/target), no CFD yet; downforce adds load without lateral transfer
- steady state only: no yaw moment, no slip angles, no camber, no transient, no driver
- unsprung mass 22.2 kg per axle at wheel-centre height (all GUESS lines)
