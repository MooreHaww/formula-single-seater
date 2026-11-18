# Cornering balance study (variant C, four-wheel steady-state model)

Written by `matlab/lapsim/cornering_balance_study.m`. Grip-limited corner speed from `cornering_balance.m`: lateral load transfer per axle (roll stiffness, roll centres, unsprung mass), tyre load sensitivity, limit set by the axle that reaches 100 % of its capacity first. `v_max` is capped by the power/drag top speed (149 km/h); `balance` = front-axle use minus rear-axle use at that speed, positive = understeer at the limit. `point-mass` is the old lap-sim answer (mu at the average wheel load, no transfer).

| R (m) | front weight | front aero | v grip (km/h) | v max (km/h) | lat g | limits | balance (%) | FO / FI / RO / RI (N) | point-mass (km/h) |
|---|---|---|---|---|---|---|---|---|---|
| 45 | 35.0 % | 0.35 (rear-heavy) | 113.3 | 113.3 | 2.24 | rear | -6.9 | 1493 / 385 / 2990 / 497 | 118.4 |
| 45 | 35.0 % | 0.40 (target) | 110.5 | 110.5 | 2.13 | rear | -14.6 | 1502 / 448 / 2835 / 464 | 118.4 |
| 45 | 35.0 % | 0.45 (as filed) | 108.0 | 108.0 | 2.04 | rear | -20.8 | 1509 / 502 / 2702 / 436 | 118.4 |
| 45 | 35.0 % | 0.55 (front-heavy) | 103.1 | 103.1 | 1.86 | rear | -31.7 | 1522 / 605 / 2447 / 383 | 118.4 |
| 45 | 41.8 % | 0.35 (rear-heavy) | 111.8 | 111.8 | 2.19 | front | +7.2 | 1686 / 374 / 2716 / 529 | 118.4 |
| 45 | 41.8 % | 0.40 (target) | 115.4 | 115.4 | 2.33 | rear | -1.1 | 1817 / 418 / 2775 / 445 | 118.4 |
| 45 | 41.8 % | 0.45 (as filed) | 112.3 | 112.3 | 2.21 | rear | -8.7 | 1809 / 484 / 2620 / 413 | 118.4 |
| 45 | 41.8 % | 0.55 (front-heavy) | 106.3 | 106.3 | 1.97 | rear | -21.9 | 1792 / 606 / 2329 / 354 | 118.4 |
| 45 | 47.0 % | 0.35 (rear-heavy) | 107.6 | 107.6 | 2.02 | front | +15.8 | 1771 / 386 / 2413 / 564 | 118.4 |
| 45 | 47.0 % | 0.40 (target) | 111.3 | 111.3 | 2.16 | front | +9.1 | 1902 / 421 / 2468 / 491 | 118.4 |
| 45 | 47.0 % | 0.45 (as filed) | 115.1 | 115.1 | 2.31 | front | +1.8 | 2042 / 459 / 2526 / 413 | 118.4 |
| 45 | 47.0 % | 0.55 (front-heavy) | 109.5 | 109.5 | 2.10 | rear | -13.8 | 2030 / 596 / 2249 / 335 | 118.4 |
| 100 | 35.0 % | 0.35 (rear-heavy) | 315.5 | 148.8 (power) | 1.74 | rear | -3.7 | 1669 / 809 / 3269 / 1333 | 148.8 |
| 100 | 35.0 % | 0.40 (target) | 278.4 | 148.8 (power) | 1.74 | rear | -10.1 | 1771 / 911 / 3167 / 1231 | 148.8 |
| 100 | 35.0 % | 0.45 (as filed) | 251.1 | 148.8 (power) | 1.74 | rear | -15.9 | 1867 / 1007 / 3071 / 1135 | 148.8 |
| 100 | 35.0 % | 0.55 (front-heavy) | 208.6 | 148.8 (power) | 1.74 | rear | -28.1 | 2078 / 1217 / 2861 / 925 | 148.8 |
| 100 | 41.8 % | 0.35 (rear-heavy) | 267.9 | 148.8 (power) | 1.74 | front | +6.7 | 1864 / 818 / 3071 / 1329 | 148.8 |
| 100 | 41.8 % | 0.40 (target) | 326.3 | 148.8 (power) | 1.74 | front | +0.2 | 1966 / 920 / 2969 / 1227 | 148.8 |
| 100 | 41.8 % | 0.45 (as filed) | 296.4 | 148.8 (power) | 1.74 | rear | -5.7 | 2062 / 1016 / 2873 / 1131 | 148.8 |
| 100 | 41.8 % | 0.55 (front-heavy) | 231.2 | 148.8 (power) | 1.74 | rear | -18.2 | 2272 / 1226 / 2662 / 920 | 148.8 |
| 100 | 47.0 % | 0.35 (rear-heavy) | 232.4 | 148.8 (power) | 1.74 | front | +14.3 | 2015 / 823 / 2916 / 1326 | 148.8 |
| 100 | 47.0 % | 0.40 (target) | 267.7 | 148.8 (power) | 1.74 | front | +7.9 | 2117 / 925 / 2814 / 1224 | 148.8 |
| 100 | 47.0 % | 0.45 (as filed) | 314.3 | 148.8 (power) | 1.74 | front | +2.0 | 2213 / 1021 / 2718 / 1128 | 148.8 |
| 100 | 47.0 % | 0.55 (front-heavy) | 258.6 | 148.8 (power) | 1.74 | rear | -10.6 | 2423 / 1232 / 2508 / 918 | 148.8 |

## Aero balance target

`aero_balance_target` = 0.40 in `params/car_params.txt` (ESTIMATE/target, not a result). The neutral share is the front aero fraction at which both axles reach their grip limit together at the file's weight distribution (41.8 % front); it moves with the assumed tyre load sensitivity, CG height and roll stiffness split.

| R (m) | neutral front aero | as filed | v grip (km/h) | balance (%) | target | v grip (km/h) | balance (%) |
|---|---|---|---|---|---|---|---|
| 45 | 0.394 | 0.45 | 112.3 | -8.7 | 0.40 | 115.4 | -1.1 |
| 100 | 0.406 | 0.45 | 296.4 | -5.7 | 0.40 | 326.3 | +0.2 |

Lap time with the four-wheel corner limit, front aero share as filed against the target:

| track | as filed (s) | target (s) | change (s) |
|---|---|---|---|
| autocross | 62.23 | 61.79 | -0.44 |
| fast_circuit | 82.78 | 82.56 | -0.22 |

## Driver 100 mm forward (mass_budget moves, CG height follows)

| case | R (m) | front weight | CG z (mm) | v grip (km/h) | v max (km/h) | limits | balance (%) |
|---|---|---|---|---|---|---|---|
| as filed | 45 | 41.8 % | 312 | 112.3 | 112.3 | rear | -8.7 |
| as filed | 100 | 41.8 % | 312 | 296.4 | 148.8 (power) | rear | -5.7 |
| driver forward | 45 | 43.3 % | 312 | 113.5 | 113.5 | rear | -5.9 |
| driver forward | 100 | 43.3 % | 312 | 310.6 | 148.8 (power) | rear | -3.5 |

## Lap times with the four-wheel corner limit (`lapsim` option `four_wheel`)

| case | track | point-mass (s) | four-wheel (s) | cost (s) |
|---|---|---|---|---|
| as filed | autocross | 61.09 | 62.23 | +1.14 |
| as filed | fast_circuit | 82.58 | 82.78 | +0.20 |
| driver forward | autocross | 61.22 | 62.18 | +0.96 |
| driver forward | fast_circuit | 82.59 | 82.69 | +0.10 |

## Assumptions these numbers depend on

- tyre: mu_peak 1.40 at 750 N, load sensitivity exponent 0.10 (file starting values, no tyre data)
- cg_height 312 mm from the mass budget (24 % of the mass is a GUESS)
- roll-centre heights 60 / 79 mm (suspension_geometry static), held fixed with roll
- roll stiffness split 38 % front from ride frequencies 3.2 / 3.5 Hz; no anti-roll bars, tyre stiffness ignored
- aero: ClA 3.98, CdA 1.63, balance 0.45 front as filed, target 0.40 (ESTIMATE/target), no CFD yet; downforce adds load without lateral transfer
- steady state only: no yaw moment, no slip angles, no camber, no transient, no driver
- unsprung mass 22.2 kg per axle at wheel-centre height (all GUESS lines)
