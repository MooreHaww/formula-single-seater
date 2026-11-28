# Cornering balance study (variant FINAL, four-wheel steady-state model)

Written by `matlab/lapsim/cornering_balance_study.m`. Grip-limited corner speed from `cornering_balance.m`: lateral load transfer per axle (roll stiffness, roll centres, unsprung mass), tyre load sensitivity, limit set by the axle that reaches 100 % of its capacity first. `v_max` is capped by the power/drag top speed (147 km/h); `balance` = front-axle use minus rear-axle use at that speed, positive = understeer at the limit. `point-mass` is the old lap-sim answer (mu at the average wheel load, no transfer).

| R (m) | front weight | front aero | v grip (km/h) | v max (km/h) | lat g | limits | balance (%) | FO / FI / RO / RI (N) | point-mass (km/h) |
|---|---|---|---|---|---|---|---|---|---|
| 45 | 35.0 % | 0.35 (rear-heavy) | 115.1 | 115.1 | 2.31 | rear | -6.9 | 1542 / 383 / 3094 / 482 | 120.6 |
| 45 | 35.0 % | 0.40 (as filed) | 112.2 | 112.2 | 2.20 | rear | -14.6 | 1548 / 447 / 2932 / 449 | 120.6 |
| 45 | 35.0 % | 0.40 (target) | 112.0 | 112.0 | 2.19 | rear | -15.0 | 1549 / 450 / 2922 / 447 | 120.6 |
| 45 | 35.0 % | 0.55 (front-heavy) | 104.0 | 104.0 | 1.89 | rear | -32.5 | 1562 / 615 / 2497 / 363 | 120.6 |
| 45 | 42.3 % | 0.35 (rear-heavy) | 112.8 | 112.8 | 2.23 | front | +8.5 | 1740 / 367 / 2769 / 528 | 120.6 |
| 45 | 42.3 % | 0.40 (as filed) | 117.4 | 117.4 | 2.41 | front | +0.6 | 1895 / 407 / 2867 / 438 | 120.6 |
| 45 | 42.3 % | 0.40 (target) | 117.7 | 117.7 | 2.42 | front | +0.1 | 1906 / 410 / 2873 / 432 | 120.6 |
| 45 | 42.3 % | 0.55 (front-heavy) | 107.7 | 107.7 | 2.03 | rear | -21.9 | 1863 / 612 / 2377 / 335 | 120.6 |
| 45 | 47.0 % | 0.35 (rear-heavy) | 108.8 | 108.8 | 2.07 | front | +16.4 | 1812 / 375 / 2481 / 564 | 120.6 |
| 45 | 47.0 % | 0.40 (as filed) | 112.5 | 112.5 | 2.21 | front | +10.0 | 1947 / 410 / 2542 / 492 | 120.6 |
| 45 | 47.0 % | 0.40 (target) | 112.8 | 112.8 | 2.22 | front | +9.6 | 1956 / 412 / 2546 / 487 | 120.6 |
| 45 | 47.0 % | 0.55 (front-heavy) | 110.9 | 110.9 | 2.15 | rear | -14.3 | 2090 / 598 / 2311 / 320 | 120.6 |
| 100 | 35.0 % | 0.35 (rear-heavy) | 344.2 | 147.3 (power) | 1.71 | rear | -3.6 | 1673 / 819 / 3278 / 1351 | 147.3 |
| 100 | 35.0 % | 0.40 (as filed) | 300.8 | 147.3 (power) | 1.71 | rear | -9.5 | 1771 / 916 / 3180 / 1253 | 147.3 |
| 100 | 35.0 % | 0.40 (target) | 298.4 | 147.3 (power) | 1.71 | rear | -9.8 | 1777 / 922 / 3174 / 1247 | 147.3 |
| 100 | 35.0 % | 0.55 (front-heavy) | 215.9 | 147.3 (power) | 1.71 | rear | -27.4 | 2089 / 1234 / 2862 / 935 | 147.3 |
| 100 | 42.3 % | 0.35 (rear-heavy) | 279.9 | 147.3 (power) | 1.71 | front | +7.2 | 1881 / 827 / 3066 / 1347 | 147.3 |
| 100 | 42.3 % | 0.40 (as filed) | 342.6 | 147.3 (power) | 1.71 | front | +1.3 | 1978 / 925 / 2968 / 1249 | 147.3 |
| 100 | 42.3 % | 0.40 (target) | 347.6 | 147.3 (power) | 1.71 | front | +0.9 | 1984 / 931 / 2962 / 1243 | 147.3 |
| 100 | 42.3 % | 0.55 (front-heavy) | 244.3 | 147.3 (power) | 1.71 | rear | -17.0 | 2296 / 1242 / 2651 / 931 | 147.3 |
| 100 | 47.0 % | 0.35 (rear-heavy) | 242.9 | 147.3 (power) | 1.71 | front | +14.0 | 2017 / 831 / 2927 / 1345 | 147.3 |
| 100 | 47.0 % | 0.40 (as filed) | 281.9 | 147.3 (power) | 1.71 | front | +8.1 | 2115 / 929 / 2829 / 1248 | 147.3 |
| 100 | 47.0 % | 0.40 (target) | 284.8 | 147.3 (power) | 1.71 | front | +7.7 | 2121 / 935 / 2823 / 1241 | 147.3 |
| 100 | 47.0 % | 0.55 (front-heavy) | 274.2 | 147.3 (power) | 1.71 | rear | -10.3 | 2432 / 1247 / 2512 / 930 | 147.3 |

## Aero balance target

`aero_balance_target` = 0.40 in `params/car_params.txt` (ESTIMATE/target, not a result). The neutral share is the front aero fraction at which both axles reach their grip limit together at the file's weight distribution (42.3 % front); it moves with the assumed tyre load sensitivity, CG height and roll stiffness split.

| R (m) | neutral front aero | as filed | v grip (km/h) | balance (%) | target | v grip (km/h) | balance (%) |
|---|---|---|---|---|---|---|---|
| 45 | 0.400 | 0.40 | 117.4 | +0.6 | 0.40 | 117.7 | +0.1 |
| 100 | 0.412 | 0.40 | 342.6 | +1.3 | 0.40 | 347.6 | +0.9 |

Lap time with the four-wheel corner limit, front aero share as filed against the target:

| track | as filed (s) | target (s) | change (s) |
|---|---|---|---|
| autocross | 61.48 | 61.51 | +0.03 |
| fast_circuit | 83.16 | 83.15 | -0.00 |

## Driver 100 mm forward (mass_budget moves, CG height follows)

| case | R (m) | front weight | CG z (mm) | v grip (km/h) | v max (km/h) | limits | balance (%) |
|---|---|---|---|---|---|---|---|
| as filed | 45 | 42.3 % | 320 | 117.4 | 117.4 | front | +0.6 |
| as filed | 100 | 42.3 % | 320 | 342.6 | 147.3 (power) | front | +1.3 |
| driver forward | 45 | 43.8 % | 320 | 115.7 | 115.7 | front | +3.8 |
| driver forward | 100 | 43.8 % | 320 | 319.2 | 147.3 (power) | front | +3.4 |

## Lap times with the four-wheel corner limit (`lapsim` option `four_wheel`)

| case | track | point-mass (s) | four-wheel (s) | cost (s) |
|---|---|---|---|---|
| as filed | autocross | 60.75 | 61.48 | +0.73 |
| as filed | fast_circuit | 83.14 | 83.16 | +0.02 |
| driver forward | autocross | 60.88 | 61.55 | +0.67 |
| driver forward | fast_circuit | 83.14 | 83.22 | +0.08 |

## Assumptions these numbers depend on

- tyre: mu_peak 1.40 at 750 N, load sensitivity exponent 0.10 (file starting values, no tyre data)
- cg_height 320 mm from the mass budget (24 % of the mass is a GUESS)
- roll-centre heights 60 / 79 mm (suspension_geometry static), held fixed with roll
- roll stiffness split 39 % front from ride frequencies 3.2 / 3.5 Hz; no anti-roll bars, tyre stiffness ignored
- aero (CFD FINAL_bl1 (Fluent half car, 989695 cells, force-converged)): ClA 4.133, CdA 1.684, balance 0.397 front as filed, target 0.40 (ESTIMATE/target); downforce adds load without lateral transfer
- steady state only: no yaw moment, no slip angles, no camber, no transient, no driver
- unsprung mass 22.2 kg per axle at wheel-centre height (all GUESS lines)
