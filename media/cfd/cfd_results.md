# CFD results (Ansys Fluent, half car)

Written by `cfd/postprocess.py`. **What these numbers mean:** one mesh per variant, sized to stay under the Ansys Student cell limit, steady RANS (k-omega SST), no mesh-independence or y+ study, no comparison with a test. The absolute ClA, CdA and balance can be off by tens of percent; **only the ranking of the variants (same meshing settings, same solver settings) is the trustworthy output.** Runs marked *not converged* have forces still moving by more than 1 % between the last two averaging windows or oscillating more than 2 %.

## All runs

| run | cells | iter | ClA (m2) | CdA (m2) | L/D | front axle share | DF drift / band % | drag drift / band % | force-converged |
|---|---|---|---|---|---|---|---|---|---|
| A | 271,859 | 1500 | -0.03 | 0.42 | -0.07 | n/a | 0.01 / 12.47 | 0.01 / 0.95 | NO |
| A_probe | 292,828 | 25 | 0.03 | 0.42 | 0.07 | n/a | 5.94 / 9.41 | 1.82 / 0.60 | NO |
| B | 900,187 | 1500 | 3.43 | 1.29 | 2.65 | 0.45 | 0.01 / 0.15 | 0.00 / 0.10 | yes |
| C | 955,009 | 1500 | 3.98 | 1.63 | 2.44 | 0.45 | 0.00 / 0.04 | 0.00 / 0.05 | yes |
| D | 1,042,343 | 1500 | 4.20 | 1.77 | 2.37 | 0.38 | 0.00 / 0.13 | 0.00 / 0.05 | yes |

## Final run per variant against the pre-CFD estimate

| variant | run | CFD ClA | estimate ClA (range) | CFD CdA | estimate CdA (range) | CFD front share | estimate front share |
|---|---|---|---|---|---|---|---|
| A | A | -0.03 | -0.10 (-0.29 to 0.10) | 0.42 | 0.53 (0.43 to 0.67) | n/a | n/a |
| B | B | 3.43 | 3.23 (2.43 to 3.84) | 1.29 | 1.15 (0.91 to 1.40) | 0.45 | 0.52 |
| C | C | 3.98 | 4.40 (3.33 to 5.22) | 1.63 | 1.44 (1.09 to 1.76) | 0.45 | 0.48 |
| D | D | 4.20 | 4.59 (3.51 to 5.38) | 1.77 | 1.52 (1.14 to 1.83) | 0.38 | 0.43 |

Ranking by downforce (CFD): D (4.20) > C (3.98) > B (3.43) > A (-0.03);  by drag: D (1.77) > C (1.63) > B (1.29) > A (0.42).

## Components (full car, final runs)

| variant | ClA_car_body / CdA_car_body | ClA_car_floor / CdA_car_floor | ClA_car_fw / CdA_car_fw | ClA_car_rw / CdA_car_rw | ClA_wheels / CdA_wheels |
|---|---|---|---|---|---|
| A | -0.42 / 0.25 | 0.47 / 0.05 | nan / nan | nan / nan | -0.08 / 0.12 |
| B | -0.36 / 0.31 | 0.35 / 0.05 | 1.65 / 0.31 | 1.90 / 0.51 | -0.12 / 0.12 |
| C | -0.39 / 0.28 | 0.40 / 0.06 | 2.00 / 0.49 | 2.09 / 0.71 | -0.12 / 0.10 |
| D | -0.34 / 0.28 | 0.49 / 0.07 | 1.97 / 0.49 | 2.20 / 0.82 | -0.12 / 0.11 |

## Wake planes

Area-weighted on a 10 mm grid; window = following car's frontal window (1.4 m wide, 1.2 m high). `wake CdA` is the momentum deficit integral without the pressure term, a rough check against the drag.

| run | plane (L) | centre deficit | centre y, z (m) | width (m) | height (m) | window deficit | q-ratio | TI | upwash (deg) | wake CdA | nodes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 0.5 | 0.62 | 0.05, 0.29 | 1.04 | 0.89 | 0.20 | 0.68 | 0.065 | -1.5 | 0.36 | 1219 |
| A | 1 | 0.45 | 0.00, 0.07 | 0.98 | 0.49 | 0.15 | 0.74 | 0.053 | -0.4 | 0.38 | 757 |
| A | 2 | 0.36 | 0.00, 0.08 | 1.18 | 0.55 | 0.13 | 0.77 | 0.041 | -0.1 | 0.33 | 744 |
| A | 3 | 0.31 | 0.00, 0.08 | 1.24 | 0.62 | 0.12 | 0.78 | 0.036 | -0.0 | 0.31 | 735 |
| A_probe | 0.5 | 0.65 | 0.02, 0.31 | 0.96 | 0.90 | 0.21 | 0.66 | 0.068 | -1.3 | 0.34 | 1043 |
| A_probe | 1 | 0.49 | 0.00, 0.07 | 1.04 | 0.52 | 0.16 | 0.72 | 0.053 | -0.4 | 0.38 | 668 |
| A_probe | 2 | 0.41 | 0.00, 0.06 | 0.64 | 0.56 | 0.13 | 0.76 | 0.039 | -0.0 | 0.33 | 630 |
| A_probe | 3 | 0.32 | 0.00, 0.08 | 0.90 | 0.66 | 0.12 | 0.78 | 0.033 | 0.0 | 0.30 | 647 |
| B | 0.5 | 0.75 | 0.00, 0.32 | 0.50 | 1.56 | 0.27 | 0.59 | 0.069 | 10.9 | 0.38 | 1201 |
| B | 1 | 0.55 | 0.00, 0.08 | 0.36 | 1.96 | 0.20 | 0.66 | 0.056 | 7.4 | 0.72 | 770 |
| B | 2 | 0.30 | 0.00, 1.93 | 0.72 | 2.22 | 0.07 | 0.86 | 0.032 | 5.6 | 0.78 | 722 |
| B | 3 | 0.20 | 0.09, 2.50 | 1.82 | 1.01 | 0.03 | 0.93 | 0.021 | 3.5 | 0.59 | 745 |
| C | 0.5 | 0.70 | 0.10, 0.07 | 0.60 | 1.75 | 0.32 | 0.49 | 0.082 | 11.8 | 0.49 | 1222 |
| C | 1 | 0.56 | 0.00, 0.91 | 0.74 | 2.01 | 0.22 | 0.64 | 0.062 | 7.7 | 0.83 | 742 |
| C | 2 | 0.39 | 0.01, 2.31 | 1.84 | 1.32 | 0.05 | 0.91 | 0.029 | 5.1 | 0.93 | 753 |
| C | 3 | 0.21 | 0.99, 2.30 | 2.66 | 1.06 | 0.02 | 0.96 | 0.018 | 3.2 | 0.74 | 743 |
| D | 0.5 | 0.79 | 0.00, 0.88 | 0.94 | 1.75 | 0.36 | 0.47 | 0.078 | 11.9 | 0.42 | 1205 |
| D | 1 | 0.64 | 0.00, 1.38 | 0.68 | 1.81 | 0.21 | 0.65 | 0.063 | 8.7 | 0.86 | 763 |
| D | 2 | 0.35 | 0.00, 2.40 | 2.08 | 1.31 | 0.04 | 0.92 | 0.027 | 4.9 | 0.98 | 740 |
| D | 3 | 0.25 | 0.98, 1.82 | 2.80 | 1.10 | 0.01 | 0.97 | 0.016 | 3.0 | 0.79 | 749 |

params/aero_variants.csv updated from CFD for: A, B, C, D.

Plots: `media/cfd/cfd_forces.png`, `media/cfd/cfd_convergence.png`, `media/cfd/cfd_wake.png`, `media/cfd/wake_<run>.png`.
