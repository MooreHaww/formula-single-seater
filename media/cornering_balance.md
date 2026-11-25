# Cornering balance study (variant CP, four-wheel steady-state model)

Written by `matlab/lapsim/cornering_balance_study.m`. Grip-limited corner speed from `cornering_balance.m`: lateral load transfer per axle (roll stiffness, roll centres, unsprung mass), tyre load sensitivity, limit set by the axle that reaches 100 % of its capacity first. `v_max` is capped by the power/drag top speed (148 km/h); `balance` = front-axle use minus rear-axle use at that speed, positive = understeer at the limit. `point-mass` is the old lap-sim answer (mu at the average wheel load, no transfer).

| R (m) | front weight | front aero | v grip (km/h) | v max (km/h) | lat g | limits | balance (%) | FO / FI / RO / RI (N) | point-mass (km/h) |
|---|---|---|---|---|---|---|---|---|---|
| 45 | 35.0 % | 0.35 (rear-heavy) | 112.9 | 112.9 | 2.23 | rear | -6.9 | 1464 / 378 / 2933 / 488 | 117.9 |
| 45 | 35.0 % | 0.40 (target) | 110.1 | 110.1 | 2.12 | rear | -14.5 | 1474 / 439 / 2784 / 456 | 117.9 |
| 45 | 35.0 % | 0.43 (as filed) | 108.4 | 108.4 | 2.05 | rear | -18.9 | 1479 / 477 / 2693 / 437 | 117.9 |
| 45 | 35.0 % | 0.55 (front-heavy) | 102.9 | 102.9 | 1.85 | rear | -31.4 | 1495 / 593 / 2409 / 378 | 117.9 |
| 45 | 41.8 % | 0.35 (rear-heavy) | 111.5 | 111.5 | 2.17 | front | +7.1 | 1657 / 368 / 2664 / 519 | 117.9 |
| 45 | 41.8 % | 0.40 (target) | 115.0 | 115.0 | 2.31 | rear | -1.1 | 1784 / 411 / 2721 / 437 | 117.9 |
| 45 | 41.8 % | 0.43 (as filed) | 112.9 | 112.9 | 2.23 | rear | -6.5 | 1778 / 456 / 2614 / 415 | 117.9 |
| 45 | 41.8 % | 0.55 (front-heavy) | 106.0 | 106.0 | 1.97 | rear | -21.7 | 1761 / 594 / 2290 / 349 | 117.9 |
| 45 | 47.0 % | 0.35 (rear-heavy) | 107.4 | 107.4 | 2.02 | front | +15.6 | 1742 / 380 / 2370 / 553 | 117.9 |
| 45 | 47.0 % | 0.40 (target) | 111.0 | 111.0 | 2.15 | front | +9.0 | 1869 / 414 / 2423 / 482 | 117.9 |
| 45 | 47.0 % | 0.43 (as filed) | 113.5 | 113.5 | 2.25 | front | +4.1 | 1962 / 439 / 2461 / 429 | 117.9 |
| 45 | 47.0 % | 0.55 (front-heavy) | 109.2 | 109.2 | 2.08 | rear | -13.7 | 1993 / 584 / 2210 / 330 | 117.9 |
| 100 | 35.0 % | 0.35 (rear-heavy) | 309.1 | 148.1 (power) | 1.72 | rear | -3.7 | 1631 / 790 / 3195 / 1302 | 148.1 |
| 100 | 35.0 % | 0.40 (target) | 273.8 | 148.1 (power) | 1.72 | rear | -10.1 | 1730 / 889 / 3096 / 1203 | 148.1 |
| 100 | 35.0 % | 0.43 (as filed) | 255.0 | 148.1 (power) | 1.72 | rear | -14.1 | 1795 / 954 / 3031 / 1138 | 148.1 |
| 100 | 35.0 % | 0.55 (front-heavy) | 206.9 | 148.1 (power) | 1.72 | rear | -27.9 | 2026 / 1185 / 2800 / 907 | 148.1 |
| 100 | 41.8 % | 0.35 (rear-heavy) | 263.9 | 148.1 (power) | 1.72 | front | +6.6 | 1824 / 800 / 2999 / 1296 | 148.1 |
| 100 | 41.8 % | 0.40 (target) | 319.2 | 148.1 (power) | 1.72 | front | +0.2 | 1922 / 899 / 2900 / 1197 | 148.1 |
| 100 | 41.8 % | 0.43 (as filed) | 302.8 | 148.1 (power) | 1.72 | rear | -3.9 | 1987 / 964 / 2835 / 1132 | 148.1 |
| 100 | 41.8 % | 0.55 (front-heavy) | 228.8 | 148.1 (power) | 1.72 | rear | -18.0 | 2219 / 1195 / 2604 / 901 | 148.1 |
| 100 | 47.0 % | 0.35 (rear-heavy) | 229.9 | 148.1 (power) | 1.72 | front | +14.2 | 1971 / 806 / 2848 / 1293 | 148.1 |
| 100 | 47.0 % | 0.40 (target) | 263.8 | 148.1 (power) | 1.72 | front | +7.8 | 2070 / 905 / 2749 / 1194 | 148.1 |
| 100 | 47.0 % | 0.43 (as filed) | 293.4 | 148.1 (power) | 1.72 | front | +3.7 | 2135 / 970 / 2684 / 1129 | 148.1 |
| 100 | 47.0 % | 0.55 (front-heavy) | 255.1 | 148.1 (power) | 1.72 | rear | -10.5 | 2366 / 1201 / 2453 / 898 | 148.1 |

## Aero balance target

`aero_balance_target` = 0.40 in `params/car_params.txt` (ESTIMATE/target, not a result). The neutral share is the front aero fraction at which both axles reach their grip limit together at the file's weight distribution (41.8 % front); it moves with the assumed tyre load sensitivity, CG height and roll stiffness split.

| R (m) | neutral front aero | as filed | v grip (km/h) | balance (%) | target | v grip (km/h) | balance (%) |
|---|---|---|---|---|---|---|---|
| 45 | 0.394 | 0.43 | 112.9 | -6.5 | 0.40 | 115.0 | -1.1 |
| 100 | 0.406 | 0.43 | 302.8 | -3.9 | 0.40 | 319.2 | +0.2 |

Lap time with the four-wheel corner limit, front aero share as filed against the target:

| track | as filed (s) | target (s) | change (s) |
|---|---|---|---|
| autocross | 62.14 | 61.84 | -0.30 |
| fast_circuit | 83.08 | 82.97 | -0.12 |

## Driver 100 mm forward (mass_budget moves, CG height follows)

| case | R (m) | front weight | CG z (mm) | v grip (km/h) | v max (km/h) | limits | balance (%) |
|---|---|---|---|---|---|---|---|
| as filed | 45 | 41.8 % | 311 | 112.9 | 112.9 | rear | -6.5 |
| as filed | 100 | 41.8 % | 311 | 302.8 | 148.1 (power) | rear | -3.9 |
| driver forward | 45 | 43.3 % | 311 | 114.1 | 114.1 | rear | -3.5 |
| driver forward | 100 | 43.3 % | 311 | 318.0 | 148.1 (power) | rear | -1.7 |

## Lap times with the four-wheel corner limit (`lapsim` option `four_wheel`)

| case | track | point-mass (s) | four-wheel (s) | cost (s) |
|---|---|---|---|---|
| as filed | autocross | 61.12 | 62.14 | +1.02 |
| as filed | fast_circuit | 82.97 | 83.08 | +0.11 |
| driver forward | autocross | 61.26 | 62.09 | +0.83 |
| driver forward | fast_circuit | 82.98 | 83.01 | +0.03 |

## Assumptions these numbers depend on

- tyre: mu_peak 1.40 at 750 N, load sensitivity exponent 0.10 (file starting values, no tyre data)
- cg_height 311 mm from the mass budget (25 % of the mass is a GUESS)
- roll-centre heights 60 / 79 mm (suspension_geometry static), held fixed with roll
- roll stiffness split 38 % front from ride frequencies 3.2 / 3.5 Hz; no anti-roll bars, tyre stiffness ignored
- aero: ClA 3.89, CdA 1.66, balance 0.43 front as filed, target 0.40 (ESTIMATE/target), no CFD yet; downforce adds load without lateral transfer
- steady state only: no yaw moment, no slip angles, no camber, no transient, no driver
- unsprung mass 22.2 kg per axle at wheel-centre height (all GUESS lines)
