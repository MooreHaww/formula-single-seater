# Pre-CFD aero estimate (variants A to D)

Written by `matlab/aero/aero_estimate.m` from `params/car_params.txt` and the airfoil files in `cad/airfoils/`. **Every number is an ESTIMATE from handbook formulas with assumed coefficients; nothing is measured and no CFD result went into it (CFD results, when they exist: `media/cfd/cfd_results.md`).** Method and assumptions: `docs/aero_estimate.md`. The range is the root-sum-square of the one-at-a-time changes of the assumptions listed at the bottom.

## Totals

| Variant | ClA (m2) | range | CdA (m2) | range | L/D | on front axle (m2) | on rear axle (m2) | front share | range |
|---|---|---|---|---|---|---|---|---|---|
| A no wings | -0.10 | -0.29 to 0.10 | 0.53 | 0.43 to 0.67 | -0.2 | -0.17 | 0.06 | n/a | total near zero |
| B moderate wings | 3.23 | 2.43 to 3.84 | 1.15 | 0.91 to 1.40 | 2.8 | 1.68 | 1.54 | 0.52 | 0.37 to 0.67 |
| C max wings + diffuser | 4.40 | 3.33 to 5.22 | 1.44 | 1.09 to 1.76 | 3.0 | 2.11 | 2.29 | 0.48 | 0.34 to 0.63 |
| D wake-tuned | 4.59 | 3.51 to 5.38 | 1.52 | 1.14 to 1.83 | 3.0 | 1.95 | 2.63 | 0.43 | 0.28 to 0.59 |

Positive ClA is downforce. The axle loads include the pitching moment of the drag (drag at height z moves `CdA z / L` from the front axle to the rear), so they are what the tyres see. Balance target in the parameter file: 0.40 front (ESTIMATE/target).

## Components

**A no wings**

| Component | ClA (m2) | CdA (m2) | x of force (m) | z of drag (m) | on front axle (m2) |
|---|---|---|---|---|---|
| body | -0.100 | 0.366 | 0.80 | 0.35 | -0.131 |
| front wheels | -0.072 | 0.095 | 0.00 | 0.26 | -0.088 |
| rear wheels | -0.054 | 0.072 | 1.55 | 0.26 | -0.012 |
| floor | +0.126 | 0.002 | 0.74 | 0.04 | +0.065 |

**B moderate wings**

| Component | ClA (m2) | CdA (m2) | x of force (m) | z of drag (m) | on front axle (m2) |
|---|---|---|---|---|---|
| body | -0.100 | 0.366 | 0.80 | 0.35 | -0.131 |
| front wheels | -0.072 | 0.095 | 0.00 | 0.26 | -0.088 |
| rear wheels | -0.054 | 0.072 | 1.55 | 0.26 | -0.012 |
| floor | +0.126 | 0.002 | 0.74 | 0.04 | +0.065 |
| front wing | +1.730 | 0.239 | -0.69 | 0.21 | +2.472 |
| rear wing | +1.601 | 0.376 | 1.85 | 1.30 | -0.621 |

**C max wings + diffuser**

| Component | ClA (m2) | CdA (m2) | x of force (m) | z of drag (m) | on front axle (m2) |
|---|---|---|---|---|---|
| body | -0.100 | 0.366 | 0.80 | 0.35 | -0.131 |
| front wheels | -0.072 | 0.095 | 0.00 | 0.26 | -0.088 |
| rear wheels | -0.054 | 0.072 | 1.55 | 0.26 | -0.012 |
| floor + diffuser | +0.635 | 0.024 | 0.98 | 0.07 | +0.233 |
| front wing | +2.073 | 0.359 | -0.71 | 0.25 | +2.962 |
| rear wing | +1.916 | 0.528 | 1.87 | 1.34 | -0.855 |

**D wake-tuned**

| Component | ClA (m2) | CdA (m2) | x of force (m) | z of drag (m) | on front axle (m2) |
|---|---|---|---|---|---|
| body | -0.100 | 0.366 | 0.80 | 0.35 | -0.131 |
| front wheels | -0.072 | 0.095 | 0.00 | 0.26 | -0.088 |
| rear wheels | -0.054 | 0.072 | 1.55 | 0.26 | -0.012 |
| floor + diffuser | +0.536 | 0.023 | 0.99 | 0.07 | +0.194 |
| front wing | +2.073 | 0.359 | -0.71 | 0.25 | +2.962 |
| rear wing | +1.997 | 0.572 | 1.88 | 1.35 | -0.928 |
| beam wing | +0.208 | 0.014 | 1.77 | 0.60 | -0.035 |
| endplate strakes | +0.000 | 0.016 | 1.08 | 0.83 | -0.009 |

## Wing detail

| Variant | Wing | Cl ideal (thin airfoil) | Cl 2D used | capped | AR | AR eff | 3D factor | ground gain | installation | CL (planform) | S (m2) | CDi | cd profile |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| B | front | 3.76 | 3.11 | no | 2.16 | 3.06 | 0.572 | 1.40 | 0.85 | 1.46 | 1.184 | 0.165 | 0.031 |
| B | rear | 4.07 | 3.37 | no | 1.52 | 2.80 | 0.546 | 1.00 | 0.85 | 1.56 | 1.025 | 0.308 | 0.049 |
| C | front | 4.73 | 3.73 | no | 2.16 | 3.06 | 0.572 | 1.40 | 0.85 | 1.75 | 1.184 | 0.259 | 0.039 |
| C | rear | 5.06 | 4.03 | no | 1.52 | 2.80 | 0.546 | 1.00 | 0.85 | 1.87 | 1.025 | 0.442 | 0.064 |
| D | front | 4.73 | 3.73 | no | 2.16 | 3.06 | 0.572 | 1.40 | 0.85 | 1.75 | 1.184 | 0.259 | 0.039 |
| D | rear | 5.40 | 4.20 | yes | 1.52 | 2.80 | 0.546 | 1.00 | 0.85 | 1.95 | 1.025 | 0.480 | 0.068 |

Zero-lift angles from the airfoil files (thin-airfoil theory, deg): fw_main -6.35, fw_flap1 -8.42, fw_flap2 -9.44, rw_main -6.39, rw_flap1 -8.42, rw_flap2 -9.44, symmetric 0.00.

## Underbody

| Variant | diffuser angle (deg) | area ratio | recovery efficiency | throat Cp | mean Cp | ClA (m2) | CdA (m2) |
|---|---|---|---|---|---|---|---|
| A | 0 | 1.22 | 0.50 | -0.34 | -0.15 | 0.126 | 0.002 |
| B | 0 | 1.22 | 0.50 | -0.34 | -0.15 | 0.126 | 0.002 |
| C | 12 | 4.33 | 0.44 | -0.92 | -0.55 | 0.635 | 0.024 |
| D | 14 | 4.87 | 0.38 | -0.76 | -0.47 | 0.536 | 0.023 |

## Trim to the balance target

Front-flap change (both flaps, same angle) at which the estimate reaches the 0.40 front target. A design hint, not a result.

| Variant | flap change (deg) | ClA before | ClA after | CdA after | front share before | after |
|---|---|---|---|---|---|---|
| B | -12.2 | 3.23 | 2.84 | 1.06 | 0.52 | 0.40 |
| C | -13.3 | 4.40 | 4.05 | 1.34 | 0.48 | 0.40 |
| D | -5.5 | 4.59 | 4.47 | 1.48 | 0.43 | 0.40 |

## Wake estimate

Method: momentum-integral Gaussian wake with a ground image and a constant spreading parameter; wake centre lifted by the rear wing's trailing vortex pair. Planes are n car lengths (2.95 m) behind the rear axle, as in `cfd/fluent_halfcar_setup.md`. Window = the following car's frontal window (1.4 m wide, 1.2 m high). **Lowest-confidence numbers in this file**: the spreading parameter is known only to a factor of about two, and the model has no wheel wakes, no vortex structure and no unsteadiness.

| Variant | plane (L) | centre deficit | range | width FWHM (m) | range | centre height (m) | window deficit | range | window q-ratio | range | TI at centre | upwash (deg) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 0.5 | 0.40 | 0.30 to 0.59 | 0.86 | 0.72 to 0.99 | 0.32 | 0.19 | 0.15 to 0.24 | 0.69 | 0.62 to 0.74 | 0.12 | 0.0 |
| A | 1 | 0.25 | 0.18 to 0.35 | 1.04 | 0.88 to 1.22 | 0.32 | 0.16 | 0.12 to 0.19 | 0.72 | 0.66 to 0.77 | 0.07 | 0.0 |
| A | 2 | 0.16 | 0.11 to 0.23 | 1.27 | 1.05 to 1.51 | 0.32 | 0.13 | 0.10 to 0.16 | 0.76 | 0.71 to 0.81 | 0.05 | 0.0 |
| A | 3 | 0.12 | 0.09 to 0.18 | 1.43 | 1.17 to 1.71 | 0.32 | 0.12 | 0.09 to 0.15 | 0.78 | 0.73 to 0.83 | 0.04 | 0.0 |
| B | 0.5 | 0.61 | 0.47 to 0.82 | 1.09 | 0.96 to 1.23 | 0.63 | 0.38 | 0.30 to 0.48 | 0.40 | 0.29 to 0.50 | 0.18 | 2.8 |
| B | 1 | 0.34 | 0.25 to 0.45 | 1.35 | 1.16 to 1.55 | 0.71 | 0.26 | 0.21 to 0.32 | 0.56 | 0.47 to 0.63 | 0.10 | 3.1 |
| B | 2 | 0.21 | 0.15 to 0.29 | 1.65 | 1.39 to 1.94 | 0.87 | 0.18 | 0.13 to 0.22 | 0.68 | 0.60 to 0.76 | 0.06 | 3.5 |
| B | 3 | 0.16 | 0.11 to 0.23 | 1.87 | 1.54 to 2.20 | 1.06 | 0.13 | 0.08 to 0.18 | 0.75 | 0.68 to 0.84 | 0.05 | 3.7 |
| C | 0.5 | 0.63 | 0.48 to 0.82 | 1.22 | 1.05 to 1.37 | 0.69 | 0.43 | 0.34 to 0.55 | 0.34 | 0.23 to 0.45 | 0.19 | 3.6 |
| C | 1 | 0.35 | 0.27 to 0.47 | 1.48 | 1.26 to 1.69 | 0.78 | 0.28 | 0.22 to 0.36 | 0.52 | 0.42 to 0.60 | 0.11 | 3.9 |
| C | 2 | 0.22 | 0.16 to 0.31 | 1.80 | 1.50 to 2.11 | 1.00 | 0.19 | 0.13 to 0.24 | 0.66 | 0.57 to 0.76 | 0.07 | 4.4 |
| C | 3 | 0.17 | 0.12 to 0.24 | 2.03 | 1.67 to 2.39 | 1.23 | 0.13 | 0.07 to 0.19 | 0.75 | 0.66 to 0.86 | 0.05 | 4.7 |
| D | 0.5 | 0.60 | 0.46 to 0.82 | 1.26 | 1.09 to 1.42 | 0.71 | 0.43 | 0.33 to 0.55 | 0.34 | 0.22 to 0.45 | 0.18 | 4.2 |
| D | 1 | 0.32 | 0.24 to 0.44 | 1.57 | 1.32 to 1.81 | 0.83 | 0.27 | 0.21 to 0.34 | 0.54 | 0.44 to 0.63 | 0.10 | 4.6 |
| D | 2 | 0.20 | 0.14 to 0.29 | 1.94 | 1.59 to 2.29 | 1.08 | 0.17 | 0.11 to 0.22 | 0.69 | 0.60 to 0.79 | 0.06 | 5.2 |
| D | 3 | 0.15 | 0.10 to 0.22 | 2.19 | 1.77 to 2.61 | 1.36 | 0.11 | 0.06 to 0.17 | 0.78 | 0.69 to 0.89 | 0.05 | 5.5 |

## Assumptions and what each one moves (variant C)

| Assumption | nominal | low | high | what | ClA change low / high | CdA change low / high | front share change low / high |
|---|---|---|---|---|---|---|---|
| `kappa_slope` | 0.9 | 0.8 | 1 | section lift slope as a fraction of 2 pi (viscous loss) | -0.23 / +0.07 | -0.10 / +0.03 | +0.003 / +0.029 |
| `eta_flap_scale` | 1 | 0.8 | 1.15 | scale on the slotted-flap effectiveness curve eta(deflection) | -0.49 / +0.27 | -0.20 / +0.11 | +0.008 / +0.016 |
| `clmax_scale` | 1 | 0.85 | 1.15 | scale on the 2D maximum Cl caps 1.6 / 3.0 / 4.2 (1, 2, 3 elements, developed chord) | -0.30 / +0.00 | -0.13 / +0.00 | +0.042 / +0.000 |
| `endplate_k` | 1.9 | 1 | 2.2 | Hoerner endplate factor: AR_eff = AR (1 + k h/b) | -0.41 / +0.12 | -0.02 / +0.00 | +0.009 / -0.001 |
| `oswald_e` | 0.9 | 0.75 | 1 | span efficiency in the induced drag | +0.00 / +0.00 | +0.15 / -0.08 | -0.020 / +0.010 |
| `kge_max` | 1.4 | 1.15 | 1.7 | front wing ground-effect gain on CL at h/c 0.08 (decays with e-folding 0.25 in h/c) | -0.37 / +0.44 | -0.10 / +0.14 | -0.086 / +0.085 |
| `inst_front` | 0.85 | 0.7 | 0.95 | front wing installation factor (tyres behind the tips, nose above the main element; the missing centre flaps are modelled, not in this factor) | -0.37 / +0.24 | -0.10 / +0.08 | -0.085 / +0.049 |
| `inst_rear` | 0.85 | 0.7 | 0.95 | rear wing installation factor (hoop and driver ahead, front-wing upwash) | -0.34 / +0.23 | -0.15 / +0.11 | +0.088 / -0.055 |
| `cd_profile_scale` | 1 | 0.6 | 1.6 | scale on the wing profile drag 0.015 + 0.003 Cl2d^2 | +0.00 / +0.00 | -0.04 / +0.07 | +0.006 / -0.009 |
| `xcp_frac` | 0.4 | 0.3 | 0.5 | wing centre of pressure as a fraction of the stack length from the main leading edge | +0.00 / +0.00 | +0.00 / +0.00 | +0.039 / -0.039 |
| `eta_diff` | 0.5 | 0.3 | 0.65 | underbody pressure-recovery efficiency (to 10 deg diffuser angle) | -0.29 / +0.38 | -0.01 / +0.01 | +0.005 / -0.006 |
| `eta_diff_slope` | 0.03 | 0 | 0.06 | loss of recovery efficiency per degree of diffuser angle above 10 deg | +0.13 / -0.11 | +0.00 / -0.00 | -0.002 / +0.002 |
| `k3d_floor` | 0.6 | 0.4 | 0.8 | underbody three-dimensional factor (side inflow, edge leakage) | -0.21 / +0.21 | -0.01 / +0.01 | +0.006 / -0.005 |
| `cp_exit` | -0.12 | -0.25 | 0 | pressure coefficient at the underbody exit (car base pressure) | +0.21 / -0.19 | +0.01 / -0.01 | -0.009 / +0.009 |
| `body_ClA` | -0.1 | -0.25 | 0.05 | body upper-surface force as ClA in m2 (negative = lift) | -0.15 / +0.15 | +0.00 / +0.00 | -0.000 / +0.000 |
| `cd_body` | 0.6 | 0.45 | 0.8 | body drag coefficient on its own frontal area (open cockpit, driver, hoop, suspension links) | +0.00 / +0.00 | -0.09 / +0.12 | +0.005 / -0.006 |
| `A_body` | 0.61 | 0.55 | 0.67 | body frontal area in m2 without wheels and wings: 2 x 0.306 m2 measured on the half-car CFD body of variant A (cad/step/cfd/cfd_geometry.json); the range covers the missing suspension links and the simplified shape | +0.00 / +0.00 | -0.04 / +0.04 | +0.002 / -0.002 |
| `cd_wheel` | 0.58 | 0.45 | 0.75 | isolated rotating wheel drag coefficient on tyre frontal area | +0.00 / +0.00 | -0.04 / +0.05 | +0.001 / -0.002 |
| `cl_wheel` | 0.44 | 0.25 | 0.6 | isolated rotating wheel lift coefficient on tyre frontal area | +0.05 / -0.05 | +0.00 / +0.00 | +0.001 / -0.001 |
| `rear_wheel_factor` | 0.75 | 0.5 | 1 | rear wheel force as a fraction of the front (runs in its wake) | +0.02 / -0.02 | -0.02 / +0.02 | -0.001 / +0.001 |
| `beam_inst` | 0.6 | 0.4 | 0.8 | beam wing installation factor, variant D (under the main wing, behind the tyres) | +0.00 / +0.00 | +0.00 / +0.00 | +0.000 / +0.000 |
| `wake_S` | 0.2 | 0.1 | 0.35 | wake spreading parameter S = (U/dU) d r_half/dx | +0.00 / +0.00 | +0.00 / +0.00 | +0.000 / +0.000 |
| `wake_d0` | 0.8 | 0.6 | 0.95 | centre velocity deficit at the end of the near wake | +0.00 / +0.00 | +0.00 / +0.00 | +0.000 / +0.000 |
| `wake_x_close` | 0.5 | 0.3 | 1 | length of the near wake behind the rear end of the car, m | +0.00 / +0.00 | +0.00 / +0.00 | +0.000 / +0.000 |
| `wake_rise_factor` | 0.6 | 0.3 | 1 | fraction of the ideal vortex-pair rise rate that the wake centre follows (roll-up, decay and wheel wakes not modelled) | +0.00 / +0.00 | +0.00 / +0.00 | +0.000 / +0.000 |
| `wake_S_mult_D` | 1.25 | 1 | 1.6 | variant D: spreading multiplier for the strakes and free beam-wing tips (not derived) | +0.00 / +0.00 | +0.00 / +0.00 | +0.000 / +0.000 |
| `wake_ti_ratio` | 0.3 | 0.2 | 0.45 | turbulence intensity as a fraction of the centre deficit | +0.00 / +0.00 | +0.00 / +0.00 | +0.000 / +0.000 |
