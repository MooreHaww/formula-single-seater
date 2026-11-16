# Concept (Ring 1 draft)

Status: draft written before Ring 1. The layout sketch and the rules check against the current Formula Student rules are still to do; everything else here is the agreed starting point.

## Decisions

| Decision | Choice |
|---|---|
| CFD tool | Ansys Student (Fluent) primary, SimScale backup |
| CFD geometry | Half car with a symmetry plane, under 1,000,000 cells |
| Powertrain | Rear electric motor, 80 kW cap, single-stage reduction 3.5:1 |
| Rules | Formula Student proportions; wings deliberately larger than the rules allow (stated in the README) |
| Chassis | Tubular spaceframe, SolidWorks Weldments, 25.4 mm tube |
| Parameters | One file, `params/car_params.txt`, read by SolidWorks (equations) and MATLAB |

## Starting values (confirm in Ring 1)

| Parameter | Value |
|---|---|
| Wheelbase | 1550 mm |
| Track front / rear | 1200 / 1150 mm |
| Wheels | 10 inch rims, 457 mm tyre OD, 222 mm rolling radius |
| Mass car / driver | 229 / 70 kg (rolled up from the mass budget in the parameter file; a quarter of it is still a guess) |
| Weight distribution | 41 % front (computed from the budget with the battery in two sidepod packs and the motor in the bay behind the main hoop; the earlier single block behind the hoop with the motor behind the axle gave 35 %) |
| CG height | 314 mm (computed from the budget) |
| Motor | 80 kW, 230 Nm, 6500 rpm |
| Tyre | mu 1.4 at 750 N per tyre, falling as (750/Fz)^0.10 |
| Aero estimates ClA / CdA (m2) | A 0.2 / 0.7, B 2.8 / 1.1, C 4.0 / 1.45, D 3.8 / 1.5, 45 % front |

All of these are in `params/car_params.txt`, which is the source; this table is a copy for reading.

## Aero variants (Ring 5)

Same body, only the aero changes, so results compare cleanly.

| Variant | What it is | Answers |
|---|---|---|
| A | Body and wheels, no wings | Baseline drag |
| B | Wings at moderate angle | Efficient setup |
| C | Wings at maximum angle plus diffuser | Maximum downforce |
| D (optional) | C with endplates and rear wing tuned for the wake | How much dirtier can the wake get, and what it costs |

Wing angles per variant are the `*_aoa_B/C/D` entries in the parameter file and become SolidWorks configurations of the wing assemblies.

## Deliberately simplified

- No fasteners, wiring, brake internals; block motor and battery; simplified tyre shape.
- CFD body: no frame tubes or suspension links, closed wheels, half car.
- Lap sim: point mass, no weight transfer, no transients, perfect driver.
- Stress: static linear only, no fatigue, welds, bolts or bearings.
- CFD: steady RANS (k-omega SST), under 1,000,000 cells, wall functions.

## What the car is for

Priorities, in order: maximum downforce, then a wake measured honestly behind it. The two pull the same way: big high-angle wings throw air upward and leave a large wake. A floor-and-diffuser car would be cleaner behind; this one is not trying to be.

## What this car is not

Formula Student cars run alone on tight tracks at 50 to 60 km/h average, where aero matters less than one would hope. That is why the lap sim has both an FS-style autocross and a fast circuit. With 80 kW and the drag of variant C the car is power-limited at about 155 km/h, so on the fast circuit the wings earn their keep in the 45 to 80 m corners and pay for themselves on the straights; the sweep plot shows the trade.

## To do in Ring 1

- Layout sketch (SolidWorks 2D, side and top): driver, motor, battery, wheels inside the wheelbase with no overlaps. Screenshot into this file.
- Check the starting values against the current FS rules (wheelbase minimum, track ratio, cockpit template) and note any that are off and why we keep them.
- Confirm the motor and battery block sizes against a real unit (for example Emrax 208/228 class) before the chassis is drawn around them.
