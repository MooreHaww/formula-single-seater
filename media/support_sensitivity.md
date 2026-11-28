# Wing supports: lap-time and balance sensitivity (CP_bl1 vs CPF vs CPFF vs CPG)

Written by `matlab/lapsim/support_sensitivity.m` on 2026-11-28, at the current mass and CG of `params/car_params.txt`. Written as a sensitivity study; since 2026-11-28 the CAD has the F and J supports and **FINAL (= CPFF's geometry, run FINAL_bl1) is the default car**, so the CPFF column is the car. CPF = CP with the F rear-wing supports; CPFF = CPF plus the front-wing supports of the front-wing round; CPG = CP with the ridged G rear-wing supports (run G_bl1ta, also mesh fix A); all CFD only. All cars come from runs meshed with 1 prism layer (CP_bl1, F_bl1, CPFF_bl1, G_bl1ta); everything else (mass, tyres, roll centres, lap-sim settings) is the same. CP's own run-to-run aero spread is about 2.2 % in ClA; only the ranking of CFD variants is trustworthy. **Band** = the largest change in that result when CP_bl1's ClA or CdA is raised, or its front share lowered, by 2.2 % (one at a time); a difference inside the band is not claimed.

| car | ClA | CdA | front share | ClA vs CP_bl1 | CdA vs CP_bl1 | front share vs CP_bl1 |
|---|---|---|---|---|---|---|
| CP_bl1 | 3.977 | 1.667 | 0.431 | +0.0 % | +0.0 % | +0.000 |
| CPF | 4.154 | 1.688 | 0.393 | +4.5 % | +1.3 % | -0.038 |
| CPFF | 4.133 | 1.684 | 0.397 | +3.9 % | +1.0 % | -0.034 |
| CPG | 4.131 | 1.695 | 0.399 | +3.9 % | +1.7 % | -0.032 |

| track | model | CP_bl1 (s) | CPF (s) | CPFF (s) | CPG (s) | CPF - CP_bl1 (s) | CPFF - CP_bl1 (s) | CPG - CP_bl1 (s) | 2.2 % band (s) |
|---|---|---|---|---|---|---|---|---|---|
| skidpad | point-mass | 4.889 | 4.878 | 4.880 | 4.880 | -0.011 (beyond) | -0.009 (beyond) | -0.009 (beyond) | 0.005 |
| skidpad | four-wheel | 5.010 | 4.983 | 4.986 | 4.987 | -0.027 (beyond) | -0.024 (beyond) | -0.023 (beyond) | 0.005 |
| autocross | point-mass | 61.037 | 60.718 | 60.754 | 60.767 | -0.319 (beyond) | -0.283 (beyond) | -0.270 (beyond) | 0.132 |
| autocross | four-wheel | 62.012 | 61.405 | 61.462 | 61.487 | -0.607 (beyond) | -0.550 (beyond) | -0.525 (beyond) | 0.130 |
| fast circuit | point-mass | 82.985 | 83.189 | 83.139 | 83.299 | +0.203 (inside) | +0.154 (inside) | +0.314 (inside) | 0.513 |
| fast circuit | four-wheel | 83.065 | 83.208 | 83.156 | 83.315 | +0.143 (inside) | +0.091 (inside) | +0.250 (inside) | 0.506 |

CPFF - CPF (what the front supports add to the rear ones), s: skidpad point-mass +0.001 (inside); skidpad four-wheel +0.003 (inside); autocross point-mass +0.036 (inside); autocross four-wheel +0.057 (inside); fast circuit point-mass -0.049 (inside); fast circuit four-wheel -0.052 (inside); band as above.

| car | R (m) | front aero | v grip (km/h) | v max (km/h) | limits | balance (%) | neutral front aero | balance 2.2 % band (points) |
|---|---|---|---|---|---|---|---|---|
| CP_bl1 | 45 | 0.431 | 114.0 | 114.0 | rear | -5.4 | 0.400 | 1.6 |
| CP_bl1 | 100 | 0.431 | 319.9 | 147.9 | rear | -3.0 | 0.411 | 1.2 |
| CPF | 45 | 0.393 | 117.2 | 117.2 | front | +1.4 | 0.401 | 1.6 |
| CPF | 100 | 0.393 | 339.3 | 147.2 | front | +1.8 | 0.412 | 1.2 |
| CPFF | 45 | 0.397 | 117.4 | 117.4 | front | +0.6 | 0.400 | 1.6 |
| CPFF | 100 | 0.397 | 342.6 | 147.3 | front | +1.3 | 0.412 | 1.2 |
| CPG | 45 | 0.399 | 117.6 | 117.6 | front | +0.3 | 0.400 | 1.6 |
| CPG | 100 | 0.399 | 345.6 | 147.0 | front | +1.0 | 0.412 | 1.2 |

Balance = front-axle use minus rear-axle use at the limit (positive = understeer). Weight distribution, CG, roll centres and tyres as filed for all cars.
