# Wing supports: lap-time and balance sensitivity (CP_bl1 vs CPF vs CPFF)

Written by `matlab/lapsim/support_sensitivity.m`. **A sensitivity result for the next version, not the released car**: the CAD has no wing supports and CP stays the default. CPF = CP with the F rear-wing supports; CPFF = CPF plus the front-wing supports of the front-wing round (both CFD only). All cars come from runs meshed with 1 prism layer (CP_bl1, F_bl1, CPFF_bl1); everything else (mass, tyres, roll centres, lap-sim settings) is the same. CP's own run-to-run aero spread is about 2.2 % in ClA; only the ranking of CFD variants is trustworthy. **Band** = the largest change in that result when CP_bl1's ClA or CdA is raised, or its front share lowered, by 2.2 % (one at a time); a difference inside the band is not claimed.

| car | ClA | CdA | front share | ClA vs CP_bl1 | CdA vs CP_bl1 | front share vs CP_bl1 |
|---|---|---|---|---|---|---|
| CP_bl1 | 3.977 | 1.667 | 0.431 | +0.0 % | +0.0 % | +0.000 |
| CPF | 4.154 | 1.688 | 0.393 | +4.5 % | +1.3 % | -0.038 |
| CPFF | 4.133 | 1.684 | 0.397 | +3.9 % | +1.0 % | -0.034 |

| track | model | CP_bl1 (s) | CPF (s) | CPFF (s) | CPF - CP_bl1 (s) | CPFF - CP_bl1 (s) | 2.2 % band (s) |
|---|---|---|---|---|---|---|---|
| skidpad | point-mass | 4.889 | 4.878 | 4.879 | -0.011 (beyond) | -0.009 (beyond) | 0.005 |
| skidpad | four-wheel | 5.009 | 4.982 | 4.985 | -0.027 (beyond) | -0.024 (beyond) | 0.005 |
| autocross | point-mass | 60.998 | 60.681 | 60.716 | -0.317 (beyond) | -0.281 (beyond) | 0.131 |
| autocross | four-wheel | 61.981 | 61.366 | 61.432 | -0.615 (beyond) | -0.549 (beyond) | 0.129 |
| fast circuit | point-mass | 82.982 | 83.187 | 83.138 | +0.205 (inside) | +0.156 (inside) | 0.513 |
| fast circuit | four-wheel | 83.075 | 83.203 | 83.152 | +0.127 (inside) | +0.076 (inside) | 0.506 |

CPFF - CPF (what the front supports add to the rear ones), s: skidpad point-mass +0.001 (inside); skidpad four-wheel +0.003 (inside); autocross point-mass +0.036 (inside); autocross four-wheel +0.066 (inside); fast circuit point-mass -0.049 (inside); fast circuit four-wheel -0.051 (inside); band as above.

| car | R (m) | front aero | v grip (km/h) | v max (km/h) | limits | balance (%) | neutral front aero | balance 2.2 % band (points) |
|---|---|---|---|---|---|---|---|---|
| CP_bl1 | 45 | 0.431 | 113.8 | 113.8 | rear | -6.2 | 0.394 | 1.5 |
| CP_bl1 | 100 | 0.431 | 315.8 | 147.9 | rear | -3.6 | 0.406 | 1.2 |
| CPF | 45 | 0.393 | 117.9 | 117.9 | front | +0.4 | 0.395 | 1.5 |
| CPF | 100 | 0.393 | 348.0 | 147.2 | front | +1.1 | 0.407 | 1.2 |
| CPFF | 45 | 0.397 | 117.8 | 117.8 | rear | -0.3 | 0.395 | 1.5 |
| CPFF | 100 | 0.397 | 351.5 | 147.3 | front | +0.6 | 0.407 | 1.2 |

Balance = front-axle use minus rear-axle use at the limit (positive = understeer). Weight distribution, CG, roll centres and tyres as filed for all cars.
