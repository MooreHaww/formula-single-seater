#!/usr/bin/env python3
"""Packaging envelopes: simple boxes, cylinders and a sphere for the parts of the car that
have a mass-budget line but no designed CAD part (2026-11-28). They are NOT designed parts:
each one only reserves the space and carries the mass of its budget line, so the SolidWorks
assembly can be checked for packaging clashes and gives a CG from geometry.

Called by build_parts.py (BuildBodies step); writes cad/step/env_*.step and
cad/generate/envelopes_mass.csv (part, budget line, mass, volume, centroid). BuildAssembly
imports every STEP and sets each env_ part's density to mass / volume from the CSV, so
SolidWorks' mass of the part equals the mass given here.

Masses: from params/car_params.txt. Where one budget line covers several things, the split is
the one written in that line's comment (for example m_cockpit: seat 1.0, steering 3.0); a split
the comment does not give is marked GUESS in ENVELOPES below and in the CSV. The envelopes
take mass from their budget lines, they add none: mass_car does not change.

Positions and sizes (car axes: X rearward from the front axle, Y right, Z up, mm):
  driver     legs box, torso box and helmet sphere exactly as matlab/cad/frame_layout.m
             envelopes() (the boxes the frame tubes were checked against at 10 mm, the helmet
             at 50 mm): hip at (driver_hip_x, driver_hip_z), seat back seat_back_angle from
             vertical, shoulder 560 mm up the seat back, helmet centre 200 mm further, r 150.
             The legs box is cut by the torso box and the helmet by the torso box, so the
             three do not overlap. Mass: mass_driver, split as the x_driver comment (legs 30 %),
             torso 43 / head with helmet 6 kg (GUESS split of the other 70 %).
  battery    two boxes from battery_* (as frame_layout.m and the sidepod clearance box)
  motor      cylinder motor_diameter x motor_length, axis Y, at (motor_x, 0, motor_z)
  diff       cylinder r 80, half-length 150, axis Y, on the rear axle (as frame_layout.m)
  ...        the rest: see each builder.
"""
from __future__ import annotations

import math

from build123d import Box, Face, Plane, Pos, Solid, Sphere, Vector, Wire, export_step, extrude

# name -> (budget line, mass kg, how the mass was taken from the line)
# the masses are filled from the parameters in masses(p); this table only names the lines
CORNERS = ("FR", "FL", "RR", "RL")


def masses(p):
    """name -> (budget line, kg, source). Sums per budget line are checked in selftest()."""
    m = {}
    md = p["mass_driver"]
    m["env_driver_legs"] = ("mass_driver", 0.30 * md, "ESTIMATE 30 % of mass_driver (x_driver comment: legs 30 %)")
    m["env_driver_torso"] = ("mass_driver", 0.70 * md - 6.0, "GUESS split of the other 70 %: torso and arms")
    m["env_driver_head"] = ("mass_driver", 6.0, "GUESS split of the other 70 %: head with helmet 6 kg")
    m["env_seat"] = ("m_cockpit", 1.0, "m_cockpit comment: seat 1.0")
    m["env_steering_wheel"] = ("m_cockpit", 1.0, "m_cockpit comment: wheel, column and rack 3.0; GUESS split wheel 1.0")
    m["env_steering_column"] = ("m_cockpit", 0.6, "GUESS split column 0.6")
    m["env_steering_rack"] = ("m_cockpit", 1.4, "GUESS split rack 1.4")
    for c in CORNERS:
        ax = "front" if c[0] == "F" else "rear"
        m[f"env_rocker_{c}"] = (f"m_susp_links_{ax}", 0.3, f"m_susp_links_{ax} comment: rocker 0.3 per corner")
        m[f"env_damper_{c}"] = (f"m_susp_links_{ax}", 0.6, f"m_susp_links_{ax} comment: damper 0.6 per corner")
        m[f"env_brake_{c}"] = (f"m_corners_{ax}", 1.8, f"m_corners_{ax} comment: brake 1.8 per corner (disc and caliper)")
    m["env_motor"] = ("m_motor", p["m_motor"], "the whole line")
    m["env_diff"] = ("m_chain_drive", 6.0, "m_chain_drive comment: diff with housing 6.0")
    m["env_chain"] = ("m_chain_drive", 2.3, "m_chain_drive comment: sprockets and chain 2.3")
    m["env_halfshaft_R"] = ("m_chain_drive", 1.0, "m_chain_drive comment: two halfshafts 2.0")
    m["env_halfshaft_L"] = ("m_chain_drive", 1.0, "m_chain_drive comment: two halfshafts 2.0")
    m["env_battery_R"] = ("m_battery", p["m_battery"] / 2, "half the line (two packs)")
    m["env_battery_L"] = ("m_battery", p["m_battery"] / 2, "half the line (two packs)")
    m["env_inverter"] = ("m_inverter_hv", p["m_inverter_hv"], "the whole line (inverter, contactors, fuses, HV cable)")
    m["env_lv_electronics"] = ("m_lv_electronics", p["m_lv_electronics"], "the whole line (dash, ECU, LV battery, loom)")
    return m


def box(x0, x1, y0, y1, z0, z1):
    # built in place (no location): a located box (Pos * Box) exports as a two-product STEP, which
    # SolidWorks imports without taking the document density (2026-11-28)
    return Solid.make_box(x1 - x0, y1 - y0, z1 - z0, Plane(origin=(x0, y0, z0)))


def cyl_between(a, b, r):
    a, b = Vector(*a), Vector(*b)
    d = b - a
    return Solid.make_cylinder(r, d.length, Plane(origin=a, z_dir=d))


def cyl_y(x, z, r, y0, y1):
    return cyl_between((x, y0, z), (x, y1, z), r)


def driver_geometry(p):
    """frame_layout.m envelopes(): returns dict of the raw boxes / sphere (before the cuts) and the points."""
    a = math.radians(p["seat_back_angle"])
    hip = (p["driver_hip_x"], p["driver_hip_z"])
    sh = (hip[0] + 560 * math.sin(a), hip[1] + 560 * math.cos(a))
    legs = (200.0, hip[0], -190.0, 190.0, 150.0, 430.0)
    torso = (min(hip[0], sh[0]) - 60, min(max(hip[0], sh[0]) + 60, p["main_hoop_x"]), -230.0, 230.0, hip[1] - 60, sh[1] + 40)
    helmet = (sh[0] + 200 * math.sin(a), 0.0, sh[1] + 200 * math.cos(a), 150.0)
    return {"hip": hip, "shoulder": sh, "legs": legs, "torso": torso, "helmet": helmet}


def build_all(p):
    """name -> (solid, note)."""
    out = {}
    L, rr = p["wheelbase"], p["tyre_rolling_radius"]
    # ---- driver
    g = driver_geometry(p)
    torso = box(*g["torso"])
    legs = box(*g["legs"]) - torso
    hx, hy, hz, hr = g["helmet"]
    head = (Pos(hx, hy, hz) * Sphere(hr)) - torso
    out["env_driver_torso"] = (torso, "box x %.0f..%.0f, y +-230, z %.0f..%.0f (frame_layout.m)" % (g["torso"][0], g["torso"][1], g["torso"][4], g["torso"][5]))
    out["env_driver_legs"] = (legs, "box x 200..%.0f, y +-190, z 150..430, minus the torso box (frame_layout.m)" % g["legs"][1])
    out["env_driver_head"] = (head, "sphere r 150 at (%.0f, 0, %.0f), minus the torso box (frame_layout.m)" % (hx, hz))
    # ---- seat: 20 mm pan under the torso and thighs, 15 mm back behind the torso box (main hoop plane)
    t0 = g["torso"]
    pan = box(600.0, t0[1], -200.0, 200.0, t0[4] - 20.0, t0[4])
    back = box(t0[1], t0[1] + 15.0, -200.0, 200.0, t0[4] - 20.0, 600.0)        # top below the helmet sphere
    out["env_seat"] = (pan + back, "pan x 600..%.0f z %.0f..%.0f, back x %.0f..%.0f z up to 600, y +-200" % (t0[1], t0[4] - 20, t0[4], t0[1], t0[1] + 15))
    # ---- steering: rack on the tie-rod inner points, column from the pinion to the wheel,
    # wheel 260 mm across just behind the front hoop, its top below the front-hoop top (FS rule)
    tx, ty, tz = p["f_tierod_in_x"], p["f_tierod_in_y"], p["f_tierod_in_z"]
    rack = cyl_y(tx, tz, 20.0, -(ty - 45.0), ty - 45.0)
    out["env_steering_rack"] = (rack, "cylinder r 20 along Y, y +-%.0f (tie-rod inner points at +-%.0f: 45 mm left for the rack bar), x %.0f, z %.1f" % (ty - 45, ty, tx, tz))
    pin = (tx, 0.0, tz + 20.0)
    wc = (p["front_hoop_x"] - 50.0, 0.0, 480.0)
    d = Vector(*wc) - Vector(*pin)
    u = d.normalized()
    col = cyl_between(Vector(*pin) + u * 25, (wc[0] - 15 * u.X, 0.0, wc[2] - 15 * u.Z), 15.0)   # starts 25 mm up the column, clear of the rack
    out["env_steering_column"] = (col, "cylinder r 15 from the pinion (%.0f, 0, %.0f) to the wheel hub (%.0f, 0, %.0f)" % (pin[0], pin[2], wc[0], wc[2]))
    wheel = Solid.make_cylinder(130.0, 30.0, Plane(origin=Vector(*wc) - u * 15, z_dir=u))
    out["env_steering_wheel"] = (wheel, "disc d 260 x 30 at (%.0f, 0, %.0f), square to the column (%.1f deg up)" % (wc[0], wc[2], math.degrees(math.atan2(u.Z, u.X))))
    # ---- rockers and dampers (per corner)
    for c in CORNERS:
        s = 1 if c[1] == "R" else -1
        if c[0] == "F":
            piv = (0.0, 280.0, 430.0)          # frame node FBT_R
            name_piv = "FBT"
            pr = (p["f_pushrod_in_x"], p["f_pushrod_in_y"], p["f_pushrod_in_z"])
        else:
            piv = (1550.0, 290.0, 470.0)       # frame node RRK_R
            name_piv = "RRK"
            pr = (p["r_pushrod_in_x"], p["r_pushrod_in_y"], p["r_pushrod_in_z"])
        rk = Solid.make_cylinder(40.0, 20.0, Plane(origin=(piv[0] - 10.0, s * piv[1], piv[2]), z_dir=(1, 0, 0)))
        dpr = math.dist(piv, pr)
        out[f"env_rocker_{c}"] = (rk, "disc r 40 x 20, axis X, on the rocker mount node %s_%s (%.0f, %+.0f, %.0f); takes the pushrod end %.0f mm away" % (name_piv, c[1], piv[0], s * piv[1], piv[2], dpr))
        zd = piv[2] + 48.0                  # damper above the rocker mount cross tube, 10 mm clear (12.7 + 10 + 25)
        y_out, y_in = piv[1] - 40.0, piv[1] - 240.0
        dm = cyl_y(piv[0], zd, 25.0, s * y_in, s * y_out)
        out[f"env_damper_{c}"] = (dm, "spring/damper cylinder d 50, 200 long, along Y from y %+.0f to %+.0f at x %.0f, z %.0f (inner anchor not designed)" % (s * y_out, s * y_in, piv[0], zd))
        # brake: disc r 50..95 x 6 in the wheel's centre plane, caliper behind the wheel centre (radial 55..100, +-40, 40 wide)
        xw = 0.0 if c[0] == "F" else L
        ht = (p["track_front"] if c[0] == "F" else p["track_rear"]) / 2
        disc = cyl_y(xw, rr, 95.0, s * ht - 3.0, s * ht + 3.0) - cyl_y(xw, rr, 50.0, s * ht - 4.0, s * ht + 4.0)
        cal = box(xw + 55.0, xw + 100.0, s * ht - 20.0, s * ht + 20.0, rr - 40.0, rr + 40.0)
        out[f"env_brake_{c}"] = (disc + cal, "disc d 190 (bore 100) x 6 at y %+.0f, caliper box 45 x 40 x 80 behind the wheel centre (%.0f, %.0f)" % (s * ht, xw, rr))
    # ---- powertrain
    out["env_motor"] = (cyl_y(p["motor_x"], p["motor_z"], p["motor_diameter"] / 2, -p["motor_length"] / 2, p["motor_length"] / 2),
                        "cylinder d %.0f x %.0f, axis Y, at (%.0f, 0, %.0f) (frame_layout.m)" % (p["motor_diameter"], p["motor_length"], p["motor_x"], p["motor_z"]))
    out["env_diff"] = (cyl_y(L, rr, 80.0, -150.0, 150.0), "cylinder r 80, y +-150, on the rear axle (%.0f, %.0f) (frame_layout.m)" % (L, rr))
    # chain: the hull of the two sprockets (motor r 45, diff r 100), 20 mm wide, just right of the diff
    from scipy.spatial import ConvexHull
    pts2 = []
    for (cx, cz, r) in ((p["motor_x"], p["motor_z"], 45.0), (L, rr, 100.0)):
        for k in range(48):
            a = 2 * math.pi * k / 48
            pts2.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    hull = ConvexHull(pts2)
    ring = [Vector(pts2[i][0], 155.0, pts2[i][1]) for i in hull.vertices]
    chain = extrude(Face(Wire.make_polygon(ring, close=True)), amount=20.0, dir=(0, 1, 0))
    out["env_chain"] = (chain, "hull of the sprockets (motor r 45 at x %.0f, diff r 100 at x %.0f), y 155..175 (the motor ends at y %.0f: shaft extension implied)" % (p["motor_x"], L, p["motor_length"] / 2))
    out["env_halfshaft_R"] = (cyl_y(L, rr, 15.0, 175.0, 470.0), "cylinder r 15 along Y, y 175..470 at the axle")
    out["env_halfshaft_L"] = (cyl_y(L, rr, 15.0, -470.0, -150.0), "cylinder r 15 along Y, y -470..-150 at the axle")
    # ---- battery packs (frame_layout.m)
    bx0, bx1 = p["battery_x_front"], p["battery_x_front"] + p["battery_length"]
    bz0, bz1 = p["battery_z_bottom"], p["battery_z_bottom"] + p["battery_height"]
    yi, yo = p["battery_y_inner"], p["battery_y_inner"] + p["battery_width"]
    out["env_battery_R"] = (box(bx0, bx1, yi, yo, bz0, bz1), "box x %.0f..%.0f, y %.0f..%.0f, z %.0f..%.0f (battery_*)" % (bx0, bx1, yi, yo, bz0, bz1))
    out["env_battery_L"] = (box(bx0, bx1, -yo, -yi, bz0, bz1), "mirror of R")
    # ---- electronics, centred on their budget positions
    xi, zi = p["x_inverter_hv"], p["z_inverter_hv"]
    out["env_inverter"] = (box(xi - 85, xi + 85, -140, 140, zi - 60, zi + 60), "box 170 x 280 x 120 centred at the budget position (%.0f, 0, %.0f)" % (xi, zi))
    xl, zl = p["x_lv_electronics"], p["z_lv_electronics"]
    out["env_lv_electronics"] = (box(xl - 60, xl + 60, -150, 150, zl - 30, zl + 30), "box 120 x 300 x 60 centred at the budget position (%.0f, 0, %.0f)" % (xl, zl))
    return out


def write(p, out_dir, csv_path, log=print):
    """Build, export, write the CSV. Returns the rows."""
    parts = build_all(p)
    ms = masses(p)
    rows = []
    for name, (s, note) in parts.items():
        sol = s.solids()
        if len(sol) != 1:
            raise RuntimeError(f"{name}: expected one solid, got {len(sol)}")
        s = sol[0]
        line, kg, src = ms[name]
        c = tuple(s.center())
        export_step(s, str(out_dir / f"{name}.step"))
        rows.append((name, line, kg, s.volume, c, src, note))
        log(f"  built   {name:20s} {kg:6.2f} kg ({line})  centroid ({c[0]:.0f}, {c[1]:.0f}, {c[2]:.0f})  {note}")
    head = "part,budget_line,mass_kg,volume_mm3,x_mm,y_mm,z_mm,mass_source"
    txt = [head] + [f"{r[0]},{r[1]},{r[2]:.4f},{r[3]:.0f},{r[4][0]:.1f},{r[4][1]:.1f},{r[4][2]:.1f},\"{r[5]}\"" for r in rows]
    csv_path.write_text("\n".join(txt) + "\n", encoding="utf-8")
    return rows


def selftest():
    """Hand-checkable: the helmet centre and the per-line mass sums."""
    p = {"seat_back_angle": 40.0, "driver_hip_x": 850.0, "driver_hip_z": 180.0, "main_hoop_x": 1250.0, "mass_driver": 70.0,
         "m_motor": 12.3, "m_battery": 45.0, "m_inverter_hv": 10.0, "m_lv_electronics": 3.0}
    g = driver_geometry(p)
    # shoulder = hip + 560 (sin 40, cos 40) = (850 + 359.96, 180 + 428.98); helmet + 200 (sin 40, cos 40): (1338.5, 762.2)
    ok = abs(g["shoulder"][0] - 1209.96) < 0.05 and abs(g["helmet"][0] - 1338.52) < 0.05 and abs(g["helmet"][2] - 762.19) < 0.05
    # torso box: x 850 - 60 = 790 .. min(1209.96 + 60, 1250) = 1250, z 120 .. 648.98
    ok = ok and g["torso"][0] == 790 and g["torso"][1] == 1250 and abs(g["torso"][5] - 648.98) < 0.05
    sums = {}
    for line, kg, _ in masses(p).values():
        sums[line] = sums.get(line, 0) + kg
    # driver 21 + 43 + 6 = 70; cockpit seat 1 + steering 3 = 4.0 of 9.5; chain drive 6 + 2.3 + 2 = 10.3 (the whole line)
    want = {"mass_driver": 70.0, "m_cockpit": 4.0, "m_chain_drive": 10.3, "m_susp_links_front": 1.8, "m_susp_links_rear": 1.8,
            "m_corners_front": 3.6, "m_corners_rear": 3.6, "m_motor": 12.3, "m_battery": 45.0, "m_inverter_hv": 10.0, "m_lv_electronics": 3.0}
    ok = ok and all(abs(sums[k] - v) < 1e-9 for k, v in want.items()) and set(sums) == set(want)
    print("envelopes self-test: %s (helmet (%.1f, %.1f), per-line sums %s)" % ("PASS" if ok else "FAIL", g["helmet"][0], g["helmet"][2],
                                                                            ", ".join(f"{k} {v:.1f}" for k, v in sorted(sums.items()))))
    return 0 if ok else 1


if __name__ == "__main__":
    import sys
    sys.exit(selftest())
