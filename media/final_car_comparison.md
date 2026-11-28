# The final car (FINAL) against the previous default (CP)

Written by `matlab/lapsim/final_car_comparison.m` on 2026-11-28. **FINAL is the default car since 2026-11-28** (`default_car()`): CP's bodywork and wings with the F rear and J front wing supports, aero row FINAL (CFD run FINAL_bl1). Every result here is a model (quasi-steady lap sim, rigid chassis, assumed tyres, steady RANS aero): use the differences to compare, not as predictions.

| car | aero row | mass with driver | front weight | CG x / z (mm, with driver) |
|---|---|---|---|---|
| old (the previous default) | CP (2 prism layers): ClA 3.892, CdA 1.661, front 0.433 | 302.56 kg | 41.84 % | 901.5 / 308.9 |
| CP at the new CG | CP (2 layers) | 302.56 kg | 42.26 % | 894.9 / 319.9 |
| CP_bl1 at the new CG | CP_bl1 (1 layer, in memory): ClA 3.977, CdA 1.667, front 0.431 | same | same | same |
| **FINAL** (the car) | FINAL (1 layer, run FINAL_bl1): ClA 4.133, CdA 1.684, front 0.397 | same | same | same |

**How the change splits.** CG effect = CP at the new CG minus old (the 2026-11-28 mass-budget reconciliation moved the CG; the mass is unchanged). Supports' mass effect = 0: the four supports (1.73 kg) were taken off the wing lines, so the total is the same 302.56 kg, and their position is already in the old CG (308.9 mm; 311.3 mm before the supports had lines). Layer term = CP_bl1 minus CP (CP's 1-layer run against its 2-layer run; it is also CP's own 2.2 % spread). **Aero effect = FINAL minus CP_bl1**: FINAL is a 1-layer run, so CP_bl1, not the 2-layer CP row, is its fair aero reference. Total = FINAL minus old = CG + layer + aero.

**Noise.** Band = the largest change of that result when CP_bl1's ClA or CdA is raised, or its front share lowered, by 2.2 % (CP vs CP_bl1) or 0.9 % (CP_bl1 vs its repeat), one at a time. An aero effect inside the 2.2 % band is not claimed; "0.9" marks one that is beyond the repeat noise only. The CG effect is not aero noise, but it rests on the CG estimate (24 % of the mass is a GUESS).

| result | unit | old (CP, old CG) | CP, new CG | CP_bl1, new CG | **FINAL** | CG effect | layer term | **aero effect** | total | band 2.2 % / 0.9 % | aero beyond |
|---|---|---|---|---|---|---|---|---|---|---|---|
| car mass with driver | kg | 302.56 | 302.56 | 302.56 | **302.56** | +0.00 | +0.00 | **+0.00** | +0.00 | 0.00 / 0.00 | - |
| front weight share | % | 41.84 | 42.26 | 42.26 | **42.26** | +0.43 | +0.00 | **+0.00** | +0.43 | 0.00 / 0.00 | - |
| CG height | mm | 308.9 | 319.9 | 319.9 | **319.9** | +11.0 | +0.0 | **+0.0** | +11.0 | 0.0 / 0.0 | - |
| ClA | m2 | 3.892 | 3.892 | 3.977 | **4.133** | +0.000 | +0.085 | **+0.156** | +0.241 | 0.087 / 0.036 | **2.2** |
| CdA | m2 | 1.661 | 1.661 | 1.667 | **1.684** | +0.000 | +0.006 | **+0.017** | +0.023 | 0.037 / 0.015 | 0.9 only |
| front aero share | - | 0.433 | 0.433 | 0.431 | **0.397** | +0.000 | -0.002 | **-0.034** | -0.036 | 0.009 / 0.004 | **2.2** |
| skidpad, point-mass | s | 4.894 | 4.894 | 4.889 | **4.880** | +0.000 | -0.005 | **-0.009** | -0.014 | 0.005 / 0.002 | **2.2** |
| skidpad, four-wheel | s | 5.013 | 5.016 | 5.010 | **4.986** | +0.003 | -0.006 | **-0.024** | -0.026 | 0.005 / 0.002 | **2.2** |
| accel 75m, point-mass | s | 4.351 | 4.365 | 4.362 | **4.349** | +0.013 | -0.003 | **-0.013** | -0.003 | 0.003 / 0.001 | **2.2** |
| accel 75m, four-wheel | s | 4.351 | 4.365 | 4.362 | **4.349** | +0.013 | -0.003 | **-0.013** | -0.003 | 0.003 / 0.001 | **2.2** |
| autocross, point-mass | s | 61.128 | 61.165 | 61.037 | **60.754** | +0.037 | -0.128 | **-0.283** | -0.373 | 0.132 / 0.054 | **2.2** |
| autocross, four-wheel | s | 62.108 | 62.155 | 62.012 | **61.462** | +0.047 | -0.143 | **-0.550** | -0.646 | 0.130 / 0.053 | **2.2** |
| fast circuit, point-mass | s | 82.972 | 82.975 | 82.985 | **83.139** | +0.003 | +0.011 | **+0.154** | +0.167 | 0.513 / 0.211 | no |
| fast circuit, four-wheel | s | 83.076 | 83.068 | 83.065 | **83.156** | -0.008 | -0.003 | **+0.091** | +0.080 | 0.506 / 0.208 | no |
| 0-100 km/h (accel_test) | s | 3.473 | 3.492 | 3.486 | **3.460** | +0.020 | -0.006 | **-0.026** | -0.013 | 0.009 / 0.004 | **2.2** |
| 75 m (accel_test) | s | 4.351 | 4.364 | 4.361 | **4.348** | +0.013 | -0.003 | **-0.013** | -0.003 | 0.003 / 0.001 | **2.2** |
| grip speed at 45 m | km/h | 112.9 | 113.1 | 114.0 | **117.4** | +0.1 | +0.9 | **+3.4** | +4.5 | 0.8 / 0.3 | **2.2** |
| corner speed at 45 m (power cap) | km/h | 112.9 | 113.1 | 114.0 | **117.4** | +0.1 | +0.9 | **+3.4** | +4.5 | 0.8 / 0.3 | **2.2** |
| balance at 45 m (front use - rear use) | points | -6.42 | -5.67 | -5.38 | **0.63** | +0.75 | +0.29 | **+6.01** | +7.05 | 1.56 / 0.63 | **2.2** |
| neutral front aero share at 45 m | - | 0.394 | 0.399 | 0.400 | **0.400** | +0.005 | +0.000 | **+0.001** | +0.006 | 0.000 / 0.000 | **2.2** |
| grip speed at 100 m | km/h | 303.3 | 306.4 | 319.9 | **342.6** | +3.1 | +13.5 | **+22.7** | +39.2 | 13.0 / 5.2 | **2.2** |
| corner speed at 100 m (power cap) | km/h | 148.1 | 148.1 | 147.9 | **147.3** | +0.0 | -0.2 | **-0.5** | -0.7 | 1.0 / 0.4 | 0.9 only |
| balance at 100 m (front use - rear use) | points | -3.85 | -3.24 | -2.96 | **1.26** | +0.61 | +0.28 | **+4.22** | +5.11 | 1.16 / 0.47 | **2.2** |
| neutral front aero share at 100 m | - | 0.407 | 0.411 | 0.411 | **0.412** | +0.005 | +0.000 | **+0.000** | +0.005 | 0.000 / 0.000 | **2.2** |
| front wheel rate for 3.2 Hz | N/mm | 21.10 | 21.36 | 21.36 | **21.36** | +0.26 | +0.00 | **+0.00** | +0.26 | 0.00 / 0.00 | - |
| rear wheel rate for 3.5 Hz | N/mm | 37.18 | 36.87 | 36.87 | **36.87** | -0.31 | +0.00 | **+0.00** | -0.31 | 0.00 / 0.00 | - |
| front ride frequency with the old springs | Hz | 3.200 | 3.180 | 3.180 | **3.180** | -0.020 | +0.000 | **+0.000** | -0.020 | 0.000 / 0.000 | - |
| rear ride frequency with the old springs | Hz | 3.500 | 3.515 | 3.515 | **3.515** | +0.015 | +0.000 | **+0.000** | +0.015 | 0.000 / 0.000 | - |
| roll stiffness split, front | % | 38.19 | 38.68 | 38.68 | **38.68** | +0.49 | +0.00 | **+0.00** | +0.49 | 0.00 / 0.00 | - |
| largest wheel load, cornering | N | 2013 | 2029 | 2040 | **2099** | +16 | +11 | **+58** | +86 | 11 / 5 | **2.2** |
| largest wheel load, braking | N | 1795 | 1817 | 1829 | **1797** | +22 | +12 | **-32** | +3 | 16 / 7 | **2.2** |
| largest wheel load, bump | N | 2589 | 2571 | 2571 | **2571** | -19 | +0 | **+0** | -19 | 0 / 0 | - |
| largest wheel load, corner+brake | N | 1730 | 1771 | 1775 | **1749** | +42 | +4 | **-26** | +20 | 10 / 4 | **2.2** |
| frame, lowest factor of safety (4130 yield) | - | 2.652 | 2.672 | 2.672 | **2.672** | +0.020 | +0.000 | **+0.000** | +0.020 | 0.000 / 0.000 | - |
| frame FoS, cornering | - | 4.151 | 4.110 | 4.080 | **3.954** | -0.041 | -0.031 | **-0.126** | -0.197 | 0.026 / 0.011 | **2.2** |
| frame FoS, braking | - | 4.949 | 5.034 | 4.936 | **4.560** | +0.085 | -0.098 | **-0.376** | -0.388 | 0.082 / 0.034 | **2.2** |
| frame FoS, bump | - | 2.652 | 2.672 | 2.672 | **2.672** | +0.020 | +0.000 | **+0.000** | +0.020 | 0.000 / 0.000 | - |
| frame FoS, corner+brake | - | 4.274 | 4.211 | 4.227 | **4.352** | -0.064 | +0.016 | **+0.124** | +0.077 | 0.028 / 0.011 | **2.2** |
| frame torsional stiffness (through the links) | Nm/deg | 1476.3 | 1476.3 | 1476.3 | **1476.3** | +0.0 | +0.0 | **+0.0** | +0.0 | 0.0 / 0.0 | - |
| own-wake q-ratio at 1 L | - | 0.637 | 0.637 | 0.649 | **0.661** | +0.000 | +0.011 | **+0.012** | +0.023 | 0.000 / 0.000 | **2.2** |
| following penalty, autocross | s | 2.143 | 2.149 | 2.126 | **2.141** | +0.006 | -0.023 | **+0.015** | -0.002 | 0.044 / 0.018 | no |
| following penalty, fast circuit | s | 1.215 | 1.215 | 1.206 | **1.149** | +0.000 | -0.009 | **-0.057** | -0.066 | 0.013 / 0.012 | **2.2** |

Limiting axle at 45 / 100 m: old rear / rear; CP rear / rear; CP_bl1 rear / rear; FINAL front / front.
Lowest factor of safety in the case: old bump; CP bump; CP_bl1 bump; FINAL bump.

Notes. The point-mass lap sim has no load transfer: it sees the CG only through the static rear weight share in its traction limit (`long_forces`), so its CG effect is small. The four-wheel model, the 0-100 / 75 m traction limit (with load transfer), the balance, the loads and the stress see the CG height as well. Ride: the model sizes the springs for the target frequencies (3.2 / 3.5 Hz) at the current sprung masses, so the frequencies stay at target and the spring rates and roll split move; "with the old springs" is what the springs sized for the old CG would give. Frame torsional stiffness is a property of the tubes: the torsion case is a self-balanced couple, so the lumped masses do not enter it (the CG effect on it is checked to be zero). Grip speed = the speed at which the tyres saturate on that radius, ignoring power; at 100 m it is above the car's top speed (downforce grows with speed as fast as the grip needed), so the 100 m corner is power-capped and "corner speed (power cap)" is the one that counts. Roll centres: the balance rows use the kinematic static values from `suspension_geometry` (as `cornering_balance_study`); the four-wheel lap times use the lap sim's defaults (as `lap_experiments`). Following penalty: the same car one length behind, its downforce times the q-ratio of its own CFD wake at 1 car length (old and CP: run CP; CP_bl1: run CP_bl1; FINAL: run FINAL_bl1).
