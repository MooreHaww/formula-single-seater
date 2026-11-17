# Cornering balance study (variant C, four-wheel steady-state model)

Written by `matlab/lapsim/cornering_balance_study.m`. Grip-limited corner speed from `cornering_balance.m`: lateral load transfer per axle (roll stiffness, roll centres, unsprung mass), tyre load sensitivity, limit set by the axle that reaches 100 % of its capacity first. `v_max` is capped by the power/drag top speed (149 km/h); `balance` = front-axle use minus rear-axle use at that speed, positive = understeer at the limit. `point-mass` is the old lap-sim answer (mu at the average wheel load, no transfer).

| R (m) | front weight | front aero | v grip (km/h) | v max (km/h) | lat g | limits | balance (%) | FO / FI / RO / RI (N) | point-mass (km/h) |
|---|---|---|---|---|---|---|---|---|---|
| 45 | 35.0 % | 0.35 (rear-heavy) | 114.4 | 114.4 | 2.29 | rear | -6.8 | 1493 / 376 / 2980 / 492 | 119.7 |
| 45 | 35.0 % | 0.40 (target) | 111.5 | 111.5 | 2.17 | rear | -14.8 | 1500 / 441 / 2819 / 458 | 119.7 |
| 45 | 35.0 % | 0.45 (as filed) | 108.9 | 108.9 | 2.07 | rear | -21.1 | 1506 / 495 / 2682 / 429 | 119.7 |
| 45 | 35.0 % | 0.55 (front-heavy) | 103.7 | 103.7 | 1.88 | rear | -32.1 | 1516 / 599 / 2420 / 376 | 119.7 |
| 45 | 41.5 % | 0.35 (rear-heavy) | 113.1 | 113.1 | 2.23 | front | +6.9 | 1676 / 362 / 2721 / 525 | 119.7 |
| 45 | 41.5 % | 0.40 (target) | 116.4 | 116.4 | 2.37 | rear | -1.7 | 1802 / 410 / 2769 / 443 | 119.7 |
| 45 | 41.5 % | 0.45 (as filed) | 113.1 | 113.1 | 2.24 | rear | -9.4 | 1792 / 476 / 2610 / 410 | 119.7 |
| 45 | 41.5 % | 0.55 (front-heavy) | 106.9 | 106.9 | 2.00 | rear | -22.8 | 1773 / 599 / 2312 / 350 | 119.7 |
| 45 | 47.0 % | 0.35 (rear-heavy) | 108.4 | 108.4 | 2.05 | front | +16.2 | 1760 / 374 / 2395 / 565 | 119.7 |
| 45 | 47.0 % | 0.40 (target) | 112.2 | 112.2 | 2.20 | front | +9.4 | 1896 / 409 / 2453 / 491 | 119.7 |
| 45 | 47.0 % | 0.45 (as filed) | 116.2 | 116.2 | 2.36 | front | +2.0 | 2041 / 447 / 2515 / 412 | 119.7 |
| 45 | 47.0 % | 0.55 (front-heavy) | 110.4 | 110.4 | 2.13 | rear | -14.0 | 2026 / 586 / 2231 / 332 | 119.7 |
| 100 | 35.0 % | 0.35 (rear-heavy) | 331.1 | 148.8 (power) | 1.74 | rear | -3.7 | 1652 / 802 / 3226 / 1332 | 148.8 |
| 100 | 35.0 % | 0.40 (target) | 289.4 | 148.8 (power) | 1.74 | rear | -10.0 | 1754 / 904 / 3124 / 1230 | 148.8 |
| 100 | 35.0 % | 0.45 (as filed) | 259.2 | 148.8 (power) | 1.74 | rear | -15.7 | 1850 / 1000 / 3028 / 1134 | 148.8 |
| 100 | 35.0 % | 0.55 (front-heavy) | 212.8 | 148.8 (power) | 1.74 | rear | -27.9 | 2061 / 1210 / 2818 / 923 | 148.8 |
| 100 | 41.5 % | 0.35 (rear-heavy) | 280.5 | 148.8 (power) | 1.74 | front | +6.2 | 1834 / 809 / 3041 / 1328 | 148.8 |
| 100 | 41.5 % | 0.40 (target) | 348.4 | 148.8 (power) | 1.74 | rear | -0.3 | 1936 / 911 / 2939 / 1226 | 148.8 |
| 100 | 41.5 % | 0.45 (as filed) | 306.2 | 148.8 (power) | 1.74 | rear | -6.1 | 2032 / 1007 / 2843 / 1130 | 148.8 |
| 100 | 41.5 % | 0.55 (front-heavy) | 235.8 | 148.8 (power) | 1.74 | rear | -18.5 | 2242 / 1218 / 2632 / 920 | 148.8 |
| 100 | 47.0 % | 0.35 (rear-heavy) | 238.2 | 148.8 (power) | 1.74 | front | +14.3 | 1991 / 814 / 2880 / 1327 | 148.8 |
| 100 | 47.0 % | 0.40 (target) | 277.0 | 148.8 (power) | 1.74 | front | +7.8 | 2093 / 916 / 2778 / 1224 | 148.8 |
| 100 | 47.0 % | 0.45 (as filed) | 329.1 | 148.8 (power) | 1.74 | front | +2.0 | 2189 / 1012 / 2682 / 1129 | 148.8 |
| 100 | 47.0 % | 0.55 (front-heavy) | 267.3 | 148.8 (power) | 1.74 | rear | -10.5 | 2400 / 1223 / 2471 / 918 | 148.8 |

## Aero balance target

`aero_balance_target` = 0.40 in `params/car_params.txt` (ESTIMATE/target, not a result). The neutral share is the front aero fraction at which both axles reach their grip limit together at the file's weight distribution (41.5 % front); it moves with the assumed tyre load sensitivity, CG height and roll stiffness split.

| R (m) | neutral front aero | as filed | v grip (km/h) | balance (%) | target | v grip (km/h) | balance (%) |
|---|---|---|---|---|---|---|---|
| 45 | 0.391 | 0.45 | 113.1 | -9.4 | 0.40 | 116.4 | -1.7 |
| 100 | 0.403 | 0.45 | 306.2 | -6.1 | 0.40 | 348.4 | -0.3 |

Lap time with the four-wheel corner limit, front aero share as filed against the target:

| track | as filed (s) | target (s) | change (s) |
|---|---|---|---|
| autocross | 62.02 | 61.57 | -0.45 |
| fast_circuit | 82.65 | 82.43 | -0.23 |

## Driver 100 mm forward (mass_budget moves, CG height follows)

| case | R (m) | front weight | CG z (mm) | v grip (km/h) | v max (km/h) | limits | balance (%) |
|---|---|---|---|---|---|---|---|
| as filed | 45 | 41.5 % | 314 | 113.1 | 113.1 | rear | -9.4 |
| as filed | 100 | 41.5 % | 314 | 306.2 | 148.8 (power) | rear | -6.1 |
| driver forward | 45 | 43.0 % | 314 | 114.4 | 114.4 | rear | -6.5 |
| driver forward | 100 | 43.0 % | 314 | 322.1 | 148.8 (power) | rear | -3.9 |

## Lap times with the four-wheel corner limit (`lapsim` option `four_wheel`)

| case | track | point-mass (s) | four-wheel (s) | cost (s) |
|---|---|---|---|---|
| as filed | autocross | 60.83 | 62.02 | +1.19 |
| as filed | fast_circuit | 82.44 | 82.65 | +0.21 |
| driver forward | autocross | 60.96 | 61.96 | +1.00 |
| driver forward | fast_circuit | 82.45 | 82.55 | +0.10 |

## Assumptions these numbers depend on

- tyre: mu_peak 1.40 at 750 N, load sensitivity exponent 0.10 (file starting values, no tyre data)
- cg_height 314 mm from the mass budget (25 % of the mass is a GUESS)
- roll-centre heights 60 / 75 mm (suspension_geometry static), held fixed with roll
- roll stiffness split 38 % front from ride frequencies 3.2 / 3.5 Hz; no anti-roll bars, tyre stiffness ignored
- aero: ClA 3.98, CdA 1.63, balance 0.45 front as filed, target 0.40 (ESTIMATE/target), no CFD yet; downforce adds load without lateral transfer
- steady state only: no yaw moment, no slip angles, no camber, no transient, no driver
- unsprung mass 22.2 kg per axle at wheel-centre height (all GUESS lines)
