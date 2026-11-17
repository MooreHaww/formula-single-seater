# Pre-CFD aero estimate: method, assumptions, how to use it

`matlab/aero/aero_estimate.m` gives ClA, CdA, the front/rear split and a wake estimate for variants A to D from handbook formulas, before any CFD. **Everything in it is an ESTIMATE.** Each assumed coefficient is a named entry with a low and a high value, and the quoted range of every result is the root-sum-square of the one-at-a-time changes.

```matlab
aero_estimate                                  % tables and figures to media/
aero_estimate(struct('write_variants', true))  % also write params/aero_variants.csv (the lap sim's aero table)
aero_estimate('--selftest')
```

Results: `media/aero_estimate.md` (totals, components, wing detail, underbody, trim, wake, assumptions with their effect), `media/aero_estimate_table.csv`, `media/aero_estimate_wake.csv`, `media/aero_estimate.png`, `media/aero_estimate_wake.png`.

## Variants

| | Wings | Underbody | Extras |
|---|---|---|---|
| A | none | flat raked floor | |
| B | three-element front and rear, moderate angles | flat floor | |
| C | maximum angles | floor with 12 deg diffuser, strakes, fence | |
| D | as C, rear at higher angle | 14 deg diffuser | wide beam wing, endplate strakes (vortex generators), open wheel wake: built to make the wake turbulent |

Geometry from `params/car_params.txt`; airfoil camber lines from `cad/airfoils/*.dat`. The front-wing leading edge is at `fw_le_x` = -960 mm and the front flaps start at `fw_flap_inner_y` = 300 mm, as in the CFD geometry (`cfd/geometry_notes.md`).

## Method (short; the full description is the header of the .m file)

1. **Wings:** zero-lift angle of each section from thin-airfoil theory on its camber line; the three-element stack as one thin airfoil (Glauert flap theory, flap effectiveness tau); real-flow corrections: section slope `kappa_slope` x 2 pi, an empirical slotted-flap effectiveness falling with deflection, a cap on the 2D maximum Cl by element count. Finite span by the Helmbold low-aspect-ratio formula with Hoerner's endplate correction. Front wing in ground effect: an empirical gain on CL decaying with height/chord, and McCormick's induced-drag factor. Front flaps only outboard of `fw_flap_inner_y` (strip sum). Installation factors for the tyres, nose, hoop and driver.
2. **Underbody:** one-dimensional channel between floor and moving ground, continuity for the speed, pressure recovery to the exit pressure with efficiency `eta_diff`, a three-dimensional factor `k3d_floor`.
3. **Body and wheels:** body Cd on the body frontal area measured on the CFD geometry; isolated rotating-wheel coefficients; rear wheels reduced.
4. **Front/rear split:** moments about the contact patches, including the drag's pitching moment (a high rear wing's drag loads the rear axle).
5. **Wake:** momentum-integral Gaussian wake with a ground image, constant spreading parameter, wake centre lifted by the rear wing's vortex pair. Lowest-confidence output.

Self-test (hand values): parabolic camber zero-lift angle -0.08 rad, tau(0.5) 0.8183, Helmbold factor at AR 2 0.4142, McCormick factor 0.5, channel throat Cp -3, wake CdA 2.2619 m2, split 0.70, NACA 6412 zero-lift angle -6.35 deg, ranking A < B < C.

## Results (2026-11-17, all ESTIMATES)

| Variant | ClA (m2) | range | CdA (m2) | range | front share | range |
|---|---|---|---|---|---|---|
| A | -0.10 | -0.29 to 0.10 | 0.53 | 0.43 to 0.67 | n/a (total near zero) | |
| B | 3.23 | 2.43 to 3.84 | 1.15 | 0.91 to 1.40 | 0.52 | 0.37 to 0.67 |
| C | 4.40 | 3.33 to 5.22 | 1.44 | 1.09 to 1.76 | 0.48 | 0.34 to 0.63 |
| D | 4.59 | 3.51 to 5.38 | 1.52 | 1.14 to 1.83 | 0.43 | 0.28 to 0.59 |

The balance target (`aero_balance_target` = 0.40 front, from the cornering balance study) needs the front flaps about 12 deg flatter on B and C (ClA C 4.40 -> 4.05) and 5.5 deg on D. The biggest single uncertainties: the front-wing ground-effect gain and installation factor (each moves the front share by +-0.09), the rear installation factor, and the slotted-flap effectiveness.

Wake, 1 car length behind the rear axle: q-ratio in the following car's window (the share of downforce left for it, to first order) A 0.72, B 0.56, C 0.52, D 0.54. The model cannot tell D's deliberately turbulent wake from C's beyond an assumed spreading multiplier; that is a question for the CFD wake planes.

## Where the estimate stands against CFD

`media/cfd/cfd_results.md` shows the Fluent runs next to these ranges. First runs (2026-11-17):

| Variant | ClA CFD / estimate | CdA CFD / estimate | front share CFD / estimate |
|---|---|---|---|
| A | -0.03 / -0.10 | 0.42 / 0.53 | n/a |
| B | 3.43 / 3.23 | 1.29 / 1.15 | 0.45 / 0.52 |
| C | 3.98 / 4.40 | 1.63 / 1.44 | 0.45 / 0.48 |
| D | 4.20 / 4.59 | 1.77 / 1.52 | 0.38 / 0.43 |

Every CFD value lies inside the estimate's range, and the ranking is the same (A < B < C < D in downforce and in drag). The pattern of the differences: the estimate is high on downforce for the high-angle variants (C, D by about 10 %) and low on drag for all winged variants (by 12 to 16 %), and it puts the balance 0.03 to 0.07 further forward. So the estimate's flap effectiveness at large deflection is probably optimistic and its induced and pressure drag of the wings low. CFD says D is the only variant near the 0.40 front target. The CFD is not a validation either. The CFD is not a validation either (one mesh per variant at the Student cell limit, no test): use the two together for the **ranking** and the direction of changes, not for absolute numbers. Once `cfd/postprocess.py --update-variants` has written CFD rows into `params/aero_variants.csv`, `aero_estimate` leaves those rows alone and keeps its own numbers in `params/aero_variants_estimate.csv` for the before/after table.
