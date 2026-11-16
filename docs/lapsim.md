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

## Four-wheel cornering model (`cornering_balance.m`)

The point-mass model has one tyre load, `Fz/4`, so it cannot see weight transfer or which axle gives up first. `cornering_balance(car, R)` solves the steady corner on four wheels:

1. Lateral load transfer per axle, Milliken's three terms: spring part `ms ay (h_s - h_ra) k_axle / t`, geometric part `ms_axle ay h_rc / t`, unsprung part `mu_axle ay h_u / t`. Sprung CG height `h_s` comes from `cg_height` and the unsprung masses at wheel-centre height; `h_ra` is the roll axis under the sprung CG, interpolated between the roll-centre heights from `suspension_geometry` (60 / 69 mm static); `k_axle` is the roll stiffness split from the ride-frequency springs (`K = k_wheel t^2 / 2`), 38 % front with no anti-roll bar.
2. Downforce `0.5 rho ClA v^2` split by `aero_balance_front`, added as vertical load with no lateral transfer.
3. Wheel loads outer `= axle/2 + dFz`, inner `= axle/2 - dFz`, inner clamped at zero (lift). Tyre capacity `mu0 fz_ref^0.10 Fz^0.90` per wheel, summed per axle, so transferring load always loses grip.
4. Demand per axle `wd_front m ay` and `(1 - wd_front) m ay` (no yaw moment). The limit speed is the largest `v` where both axles meet demand; `balance_pct = 100 (use_front - use_rear)`, positive = front axle at its limit first = understeer.

`lapsim(car, track, struct('four_wheel', true))` uses it for the corner speed limit (the forward and backward passes still use the point-mass friction ellipse). `cornering_balance_study.m` sweeps front weight fraction and aero balance at 45 and 100 m, moves the driver with `mass_budget`'s `moves` option, and writes `media/cornering_balance.*`. Results in `docs/log.md` (fourth session).

Assumptions the four-wheel results rest on, none measured: `tyre_load_sensitivity` 0.10 (sets the size of every transfer effect; 0 removes the weight-distribution effect on speed except through aero mismatch), `tyre_mu_peak` 1.4, `cg_height` 314 mm (25 % of the mass is a GUESS), static roll-centre heights, spring-only roll stiffness, `aero_balance_front` 0.45 with no CFD.

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
| `cornering_balance` | symmetric car (50 % front, equal tracks and roll centres, split 0.5), R 50 m, no load sensitivity: transfer per axle equals the rigid-body `0.5 m ay h / t`, loads sum to `m g`, both axles at the limit together; tyre pair at 1000 / 500 N with exponent 0.10 | 26.207 m/s, 515.0 N each axle, 2943 N, balance 0; 2089.3 N (less than 2100) |
| `cornering_balance_study` | coarse grid: balance rises with front weight fraction and falls with front aero share at every radius; grip limit never above the point-mass limit | monotonic, 12 rows |

## Honesty limits

The default lap sim has no weight transfer; the four-wheel option adds steady-state transfer and axle balance to the corner limit only, with assumed tyre coefficients (see above), static roll centres and no anti-roll bars. No transient behaviour, no slip angles, no driver error, no tyre temperature. Lap times compare setups; a real car would be slower. The following-car penalty uses the CFD dynamic pressure ratio as a plain scale on ClA, which ignores the change in balance and in the wake's spanwise shape.
