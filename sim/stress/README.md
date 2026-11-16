# sim/stress/ (Ring 4)

| File | What |
|---|---|
| `load_cases.csv` | Written by `matlab/load_cases.m`: per-wheel Fx, Fy, Fz at the contact patch and the hub moments for static, cornering, braking, bump and combined cases. |
| `upright_*.docx` / `*.html` | SolidWorks Simulation study reports (Simulation > Report). Keep the two mesh sizes. |
| `chassis_torsion.*` | Beam-mesh torsion study report: rear suspension points fixed, equal and opposite vertical forces at the front suspension points. Stiffness = (F x track) / twist angle, in Nm/deg. |

## Applying a load case in SolidWorks Simulation

Upright study: fixture = the two wishbone ball-joint faces (fixed geometry) and the tie-rod joint (fixed in its axis only if you want it honest); load = the wheel-bearing seat with the remote load option, applied at the contact patch position (`-tyre_rolling_radius` below the hub) using the Fx, Fy, Fz of the worst row in `load_cases.csv` for that case. Material 7075-T6 (yield about 500 MPa) or 6061-T6 (about 275 MPa) as you choose; state it in `docs/stress.md`.

Mesh check: run at the default mesh and once at half the element size. Report the peak von Mises away from the fixtures at both sizes; if they differ by more than about 10 %, refine once more and say so.

Honesty limits: static linear only. No fatigue, no welds, no bolts, no bearings. Peaks at sharp corners and at fixtures are artefacts and are labelled as such.
