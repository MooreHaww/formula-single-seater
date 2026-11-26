# Rear-wing supports F: lap-time and balance sensitivity (CP_bl1 vs CPF)

Written by `matlab/lapsim/support_sensitivity.m`. **A sensitivity result for the next version, not the released car**: the CAD has no wing supports and CP stays the default. Both cars come from runs meshed with 1 prism layer (CP_bl1, F_bl1); everything else (mass, tyres, roll centres, lap-sim settings) is the same. CP's own run-to-run aero spread is about 2.2 % in ClA; only the ranking of CFD variants is trustworthy. **Band** = the largest change in that result when CP_bl1's ClA or CdA is raised, or its front share lowered, by 2.2 % (one at a time); a difference inside the band is not claimed.

| car | ClA | CdA | front share |
|---|---|---|---|
| CP_bl1 | 3.977 | 1.667 | 0.431 |
| CPF | 4.154 | 1.688 | 0.393 |
| change | +4.5 % | +1.3 % | -0.038 |

| track | model | CP_bl1 (s) | CPF (s) | CPF - CP_bl1 (s) | 2.2 % band (s) | beyond the band |
|---|---|---|---|---|---|---|
| skidpad | point-mass | 4.889 | 4.878 | -0.011 | 0.005 | yes |
| skidpad | four-wheel | 5.009 | 4.982 | -0.027 | 0.005 | yes |
| autocross | point-mass | 60.998 | 60.681 | -0.317 | 0.131 | yes |
| autocross | four-wheel | 61.981 | 61.366 | -0.615 | 0.129 | yes |
| fast circuit | point-mass | 82.982 | 83.187 | +0.205 | 0.513 | no |
| fast circuit | four-wheel | 83.075 | 83.203 | +0.127 | 0.506 | no |

| car | R (m) | front aero | v grip (km/h) | v max (km/h) | limits | balance (%) | neutral front aero | balance 2.2 % band (points) |
|---|---|---|---|---|---|---|---|---|
| CP_bl1 | 45 | 0.431 | 113.8 | 113.8 | rear | -6.2 | 0.394 | 1.5 |
| CP_bl1 | 100 | 0.431 | 315.8 | 147.9 | rear | -3.6 | 0.406 | 1.2 |
| CPF | 45 | 0.393 | 117.9 | 117.9 | front | +0.4 | 0.395 | 1.5 |
| CPF | 100 | 0.393 | 348.0 | 147.2 | front | +1.1 | 0.407 | 1.2 |

Balance = front-axle use minus rear-axle use at the limit (positive = understeer). Weight distribution, CG, roll centres and tyres as filed for both cars.
