# Lap simulation (Ring 6) assumptions

## Model

Point mass, quasi-steady, the standard first lap simulator:

1. Track = list of straights and constant-radius arcs (`matlab/lapsim/tracks/*.csv`), sampled every 0.5 m.
2. Corner speed limit at every sample from `m v^2 / R = mu(Fz) Fz` with `Fz = m g + 0.5 rho ClA v^2`, capped by the top speed where drive force equals drag plus rolling resistance.
3. Forward pass: accelerate with the longitudinal grip left after the lateral demand (friction ellipse) on the rear axle, limited by power, motor torque and rpm, minus drag and rolling resistance.
4. Backward pass: brake with all four wheels' remaining grip plus drag. Speed profile = minimum of both.
5. Closed tracks are flying laps; open tracks start from rest.

All forces come from `matlab/common/long_forces.m`, which is also what `accel_test.m` and the Simulink 6b model use, so the three agree by construction.

Tyre: `mu = mu_peak (Fz_ref / Fz_tyre)^0.10`, so grip per newton falls as load rises. Everything else (rolling resistance, drag) is in `params/car_params.txt`.

## Tracks

| Track | Length | Type | Why |
|---|---|---|---|
| skidpad | 57.3 m circle, R 9.125 m | closed | hand check: `v = sqrt(mu g R)` |
| accel_75m | 75 m straight | open, standing start | hand check: `t = sqrt(2 s / a)` |
| autocross | 1144 m, slaloms R 9, hairpins R 8 to 9, sweepers R 25 to 40, straights up to 70 m | open, standing start | FS home ground |
| fast_circuit | 3345 m, straights 300 to 800 m, corners R 45 to 200 m | closed, flying lap | where downforce pays off |

Fast circuit closure, by hand: with main straight A, legs B (south), C (west), D (back straight), E (north) and the arc displacements of the fixed corner sequence (R120 right 90, R60 right 90, R200 left 60 then right 60, R45 right 180, R80 left 90, R110 right 90) the loop closes when `C + D = A - 96.4 m` and `E = B + 100 m`. Chosen A = 800, B = 300, C = 300, D = 403.6, E = 400. `make_tracks.m` checks the end point numerically (error under 0.01 m).

## Self-tests (hand-checkable)

| Script | Check | Hand value |
|---|---|---|
| `long_forces` | net drive force at 10 m/s, no aero | 0.53 x 4120.2 - 44.1 = 2139.6 N |
| `accel_test` | traction-limited 0-100 and 75 m | 3.816 s, 4.540 s |
| `lapsim` | skidpad flying lap, 75 m, corner entry | 5.122 s, 4.540 s, 11.19 m/s |
| `cornering_speed_vs_downforce` | R 50 m, no aero / ClA 4 | 26.20 / 39.51 m/s |
| `run_accel_simulink` | same car in Simulink | 4.540 s within 0.5 % |

## Honesty limits

No weight transfer, no transient behaviour, no driver error, no tyre temperature. Lap times compare setups; a real car would be slower. The following-car penalty uses the CFD dynamic pressure ratio as a plain scale on ClA, which ignores the change in balance and in the wake's spanwise shape.
