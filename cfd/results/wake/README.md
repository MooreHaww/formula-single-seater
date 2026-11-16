# Wake plane exports

Drop Fluent ASCII node exports here, one file per variant and plane, named `<variant>_<n>L.csv` (for example `C_0.5L.csv`, `C_1L.csv`, `C_2L.csv`, `C_3L.csv`). Required columns (any order, Fluent's own names): `x-coordinate, y-coordinate, z-coordinate, x-velocity, y-velocity, z-velocity, turb-kinetic-energy`.

`matlab/cfd/wake_postprocess.m` reads everything in this folder and writes `../wake_summary.csv` and `media/wake/*.png`.
