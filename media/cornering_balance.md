# Cornering balance study (variant CP, four-wheel steady-state model)

Written by `matlab/lapsim/cornering_balance_study.m`. Grip-limited corner speed from `cornering_balance.m`: lateral load transfer per axle (roll stiffness, roll centres, unsprung mass), tyre load sensitivity, limit set by the axle that reaches 100 % of its capacity first. `v_max` is capped by the power/drag top speed (148 km/h); `balance` = front-axle use minus rear-axle use at that speed, positive = understeer at the limit. `point-mass` is the old lap-sim answer (mu at the average wheel load, no transfer).

| R (m) | front weight | front aero | v grip (km/h) | v max (km/h) | lat g | limits | balance (%) | FO / FI / RO / RI (N) | point-mass (km/h) |
|---|---|---|---|---|---|---|---|---|---|
| 45 | 35.0 % | 0.35 (rear-heavy) | 112.7 | 112.7 | 2.22 | rear | -6.9 | 1467 / 377 / 2938 / 486 | 117.7 |
| 45 | 35.0 % | 0.40 (target) | 110.0 | 110.0 | 2.11 | rear | -14.5 | 1476 / 439 / 2790 / 455 | 117.7 |
| 45 | 35.0 % | 0.43 (as filed) | 108.3 | 108.3 | 2.05 | rear | -18.9 | 1481 / 476 / 2699 / 436 | 117.7 |
| 45 | 35.0 % | 0.55 (front-heavy) | 102.7 | 102.7 | 1.85 | rear | -31.4 | 1498 / 592 / 2416 / 377 | 117.7 |
| 45 | 41.7 % | 0.35 (rear-heavy) | 111.4 | 111.4 | 2.17 | front | +6.9 | 1659 / 367 / 2674 / 516 | 117.7 |
| 45 | 41.7 % | 0.40 (target) | 114.7 | 114.7 | 2.30 | rear | -1.3 | 1782 / 411 / 2725 / 435 | 117.7 |
| 45 | 41.7 % | 0.43 (as filed) | 112.6 | 112.6 | 2.22 | rear | -6.7 | 1777 / 456 / 2619 / 413 | 117.7 |
| 45 | 41.7 % | 0.55 (front-heavy) | 105.9 | 105.9 | 1.96 | rear | -21.8 | 1761 / 593 / 2297 / 348 | 117.7 |
| 45 | 47.0 % | 0.35 (rear-heavy) | 107.2 | 107.2 | 2.01 | front | +15.5 | 1746 / 380 / 2375 / 551 | 117.7 |
| 45 | 47.0 % | 0.40 (target) | 110.8 | 110.8 | 2.15 | front | +9.0 | 1873 / 413 / 2427 / 480 | 117.7 |
| 45 | 47.0 % | 0.43 (as filed) | 113.4 | 113.4 | 2.25 | front | +4.0 | 1965 / 438 / 2465 / 427 | 117.7 |
| 45 | 47.0 % | 0.55 (front-heavy) | 109.0 | 109.0 | 2.08 | rear | -13.6 | 1996 / 583 / 2215 / 329 | 117.7 |
| 100 | 35.0 % | 0.35 (rear-heavy) | 306.7 | 148.1 (power) | 1.72 | rear | -3.7 | 1636 / 790 / 3205 / 1300 | 148.1 |
| 100 | 35.0 % | 0.40 (target) | 272.1 | 148.1 (power) | 1.72 | rear | -10.1 | 1735 / 888 / 3106 / 1201 | 148.1 |
| 100 | 35.0 % | 0.43 (as filed) | 253.6 | 148.1 (power) | 1.72 | rear | -14.1 | 1800 / 954 / 3041 / 1136 | 148.1 |
| 100 | 35.0 % | 0.55 (front-heavy) | 206.2 | 148.1 (power) | 1.72 | rear | -28.0 | 2031 / 1185 / 2810 / 905 | 148.1 |
| 100 | 41.7 % | 0.35 (rear-heavy) | 263.1 | 148.1 (power) | 1.72 | front | +6.5 | 1827 / 799 / 3010 / 1294 | 148.1 |
| 100 | 41.7 % | 0.40 (target) | 317.9 | 148.1 (power) | 1.72 | front | +0.1 | 1925 / 898 / 2911 / 1196 | 148.1 |
| 100 | 41.7 % | 0.43 (as filed) | 299.8 | 148.1 (power) | 1.72 | rear | -4.0 | 1991 / 963 / 2846 / 1130 | 148.1 |
| 100 | 41.7 % | 0.55 (front-heavy) | 227.5 | 148.1 (power) | 1.72 | rear | -18.2 | 2222 / 1194 / 2615 / 899 | 148.1 |
| 100 | 47.0 % | 0.35 (rear-heavy) | 229.0 | 148.1 (power) | 1.72 | front | +14.2 | 1978 / 805 / 2856 / 1291 | 148.1 |
| 100 | 47.0 % | 0.40 (target) | 262.3 | 148.1 (power) | 1.72 | front | +7.8 | 2076 / 904 / 2757 / 1192 | 148.1 |
| 100 | 47.0 % | 0.43 (as filed) | 291.3 | 148.1 (power) | 1.72 | front | +3.7 | 2142 / 969 / 2692 / 1127 | 148.1 |
| 100 | 47.0 % | 0.55 (front-heavy) | 253.7 | 148.1 (power) | 1.72 | rear | -10.5 | 2373 / 1200 / 2461 / 896 | 148.1 |

## Aero balance target

`aero_balance_target` = 0.40 in `params/car_params.txt` (ESTIMATE/target, not a result). The neutral share is the front aero fraction at which both axles reach their grip limit together at the file's weight distribution (41.7 % front); it moves with the assumed tyre load sensitivity, CG height and roll stiffness split.

| R (m) | neutral front aero | as filed | v grip (km/h) | balance (%) | target | v grip (km/h) | balance (%) |
|---|---|---|---|---|---|---|---|
| 45 | 0.393 | 0.43 | 112.6 | -6.7 | 0.40 | 114.7 | -1.3 |
| 100 | 0.405 | 0.43 | 299.8 | -4.0 | 0.40 | 317.9 | +0.1 |

Lap time with the four-wheel corner limit, front aero share as filed against the target:

| track | as filed (s) | target (s) | change (s) |
|---|---|---|---|
| autocross | 62.19 | 61.88 | -0.30 |
| fast_circuit | 83.12 | 82.99 | -0.13 |

## Driver 100 mm forward (mass_budget moves, CG height follows)

| case | R (m) | front weight | CG z (mm) | v grip (km/h) | v max (km/h) | limits | balance (%) |
|---|---|---|---|---|---|---|---|
| as filed | 45 | 41.7 % | 312 | 112.6 | 112.6 | rear | -6.7 |
| as filed | 100 | 41.7 % | 312 | 299.8 | 148.1 (power) | rear | -4.0 |
| driver forward | 45 | 43.2 % | 312 | 113.8 | 113.8 | rear | -3.7 |
| driver forward | 100 | 43.2 % | 312 | 314.5 | 148.1 (power) | rear | -1.8 |

## Lap times with the four-wheel corner limit (`lapsim` option `four_wheel`)

| case | track | point-mass (s) | four-wheel (s) | cost (s) |
|---|---|---|---|---|
| as filed | autocross | 61.16 | 62.19 | +1.03 |
| as filed | fast_circuit | 82.99 | 83.12 | +0.12 |
| driver forward | autocross | 61.29 | 62.13 | +0.85 |
| driver forward | fast_circuit | 83.00 | 83.04 | +0.04 |

## Assumptions these numbers depend on

- tyre: mu_peak 1.40 at 750 N, load sensitivity exponent 0.10 (file starting values, no tyre data)
- cg_height 312 mm from the mass budget (24 % of the mass is a GUESS)
- roll-centre heights 60 / 79 mm (suspension_geometry static), held fixed with roll
- roll stiffness split 38 % front from ride frequencies 3.2 / 3.5 Hz; no anti-roll bars, tyre stiffness ignored
- aero: ClA 3.89, CdA 1.66, balance 0.43 front as filed, target 0.40 (ESTIMATE/target), no CFD yet; downforce adds load without lateral transfer
- steady state only: no yaw moment, no slip angles, no camber, no transient, no driver
- unsprung mass 22.2 kg per axle at wheel-centre height (all GUESS lines)
