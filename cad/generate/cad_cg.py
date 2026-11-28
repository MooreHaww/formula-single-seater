#!/usr/bin/env python3
"""CG of the car from the CAD geometry, against the mass-budget CG (2026-11-28).

Run:  .venv/Scripts/python cad/generate/cad_cg.py [--step cad/step]     (BuildBodies runs it)
      .venv/Scripts/python cad/generate/cad_cg.py --selftest
Writes cad/generate/cad_cg_report.txt. It reports; it changes nothing (neither the budget nor
the CAD), and it always exits 0 unless it cannot run.

Every budget line keeps its mass (params/car_params.txt). Only its position changes, to the
centre of the CAD bodies that stand for it:
  - packaging envelopes (envelopes_mass.csv): the envelope centroids with their masses;
  - STEP bodies (wings, floor, nose, sidepods, tyres, rims): volume centroids, the line's mass
    shared by volume where one line covers several bodies;
  - suspension members: the BuildSuspension members rebuilt from the hardpoints
    (check_clearances.suspension_members), with the per-corner masses of the budget comment;
  - frame and wing supports: the line's own position is already from the CAD (CALC);
  - what has no CAD body (brackets, harness, pedal box, cooling, hydraulics, fasteners, hub,
    upright and bearings) stays at the budget position, and the report says so.
Only X (from the front axle) and Z (from the ground) are compared; the budget has no Y.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

LINES = ["m_frame", "m_brackets_welds", "m_battery", "m_motor", "m_inverter_hv", "m_lv_electronics", "m_chain_drive",
         "m_corners_front", "m_corners_rear", "m_susp_links_front", "m_susp_links_rear", "m_front_wing", "m_rear_wing",
         "m_floor_diffuser", "m_bodywork", "m_cockpit", "m_brake_hydraulics", "m_cooling", "m_fasteners_misc",
         "m_fw_supports", "m_rw_supports", "mass_driver"]
# per-corner split written in the m_corners_* comment (kg); brake is the envelope
CORNER_SPLIT = {"tyre": 4.1, "rim": 2.5, "hub": 1.0, "upright": 1.2, "brake": 1.8, "bearings": 0.5}
# per-corner split written in the m_susp_links_* comment (kg); rocker and damper are envelopes
LINK_SPLIT = {"wishbones": 0.8, "pushrod": 0.2, "rocker": 0.3, "damper": 0.6, "tie": 0.2}


def pos_of(p, line):
    if line == "mass_driver":
        return p["x_driver"], p["z_driver"]
    k = line[2:]
    return p["x_" + k], p["z_" + k]


def combine(items):
    """items: (mass, x, z) -> (mass, x, z)."""
    m = sum(i[0] for i in items)
    return m, sum(i[0] * i[1] for i in items) / m, sum(i[0] * i[2] for i in items) / m


def cad_positions(p, step_dir: Path, gen_dir: Path):
    """line -> (x, z, source text, list of (mass, x, z) used)."""
    from build123d import import_step
    env = {}
    with open(gen_dir / "envelopes_mass.csv", newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            env.setdefault(r["budget_line"], []).append((float(r["mass_kg"]), float(r["x_mm"]), float(r["z_mm"]), r["part"]))
    cen = {}

    def step_c(name):
        if name not in cen:
            s = import_step(str(step_dir / f"{name}.step"))
            c = s.center()
            cen[name] = (s.volume, c.X, c.Z)
        return cen[name]

    def by_volume(mass, names):
        vols = [step_c(n) for n in names]
        V = sum(v[0] for v in vols)
        return [(mass * v[0] / V, v[1], v[2]) for v in vols]

    out = {}
    for line in LINES:
        m = p[line]
        xb, zb = pos_of(p, line)
        items, src = [], ""
        if line in ("m_frame", "m_fw_supports", "m_rw_supports"):
            items, src = [(m, xb, zb)], "CAD already (CALC line)"
        elif line in ("m_battery", "m_motor", "m_inverter_hv", "m_lv_electronics", "m_chain_drive", "mass_driver"):
            items = [(e[0], e[1], e[2]) for e in env[line]]
            src = "envelopes " + ", ".join(e[3][4:] for e in env[line])
        elif line in ("m_corners_front", "m_corners_rear"):
            ax = line.split("_")[-1]
            xw = 0.0 if ax == "front" else p["wheelbase"]
            t, r = step_c("tyre_" + ax), step_c("rim_" + ax)
            for _ in range(2):          # R and L: same X and Z
                items += [(CORNER_SPLIT["tyre"], t[1], t[2]), (CORNER_SPLIT["rim"], r[1], r[2]),
                          (CORNER_SPLIT["hub"] + CORNER_SPLIT["upright"] + CORNER_SPLIT["bearings"], xw, p["tyre_rolling_radius"])]
            items += [(e[0], e[1], e[2]) for e in env[line]]
            src = "tyre, rim STEP; brake envelopes; hub, upright, bearings at the wheel centre"
        elif line in ("m_susp_links_front", "m_susp_links_rear"):
            from check_clearances import suspension_members
            mem = suspension_members(p)
            for cn in (("FR", "FL") if line.endswith("front") else ("RR", "RL")):
                for part, kg in (("lwb", LINK_SPLIT["wishbones"] / 2), ("uwb", LINK_SPLIT["wishbones"] / 2),
                                 ("push", LINK_SPLIT["pushrod"]), ("tie", LINK_SPLIT["tie"])):
                    c = mem[f"{cn}_{part}"].center()
                    items.append((kg, c.X, c.Z))
            items += [(e[0], e[1], e[2]) for e in env[line]]
            src = "wishbones, pushrods, tie rods from the hardpoints; rocker and damper envelopes"
        elif line in ("m_front_wing", "m_rear_wing"):
            pre = "fw" if line == "m_front_wing" else "rw"
            items = by_volume(m, [f"{pre}_main", f"{pre}_flap1", f"{pre}_flap2", f"{pre}_endplate_R", f"{pre}_endplate_L"])
            src = "STEP elements and endplates, by volume"
        elif line == "m_floor_diffuser":
            items, src = by_volume(m, ["floor_diffuser"]), "STEP"
        elif line == "m_bodywork":
            items, src = by_volume(m, ["nose", "sidepod_R", "sidepod_L"]), "STEP nose and sidepods, by volume (cockpit surround and fasteners not modelled)"
        elif line == "m_cockpit":
            items = [(e[0], e[1], e[2]) for e in env[line]]
            rest = m - sum(i[0] for i in items)
            items.append((rest, xb, zb))
            src = "envelopes seat and steering (%.1f kg); harness, pedal box, firewall, headrest (%.1f kg) at the budget position" % (m - rest, rest)
        else:
            items, src = [(m, xb, zb)], "not in the CAD: budget position"
        mm = sum(i[0] for i in items)
        if abs(mm - m) > 1e-3:          # every line keeps its mass: the pieces must add up to it
            raise ValueError(f"{line}: CAD items add up to {mm:.3f} kg, the line is {m:.3f} kg")
        _, x, z = combine(items)
        out[line] = (x, z, src, items)
    return out


def report(p, cad, out_path: Path):
    rows = []
    for line in LINES:
        m = p[line]
        xb, zb = pos_of(p, line)
        x, z, src, _ = cad[line]
        rows.append((line, m, xb, zb, x, z, src))

    def cg(rs, which):
        items = [(r[1], r[2], r[3]) if which == "b" else (r[1], r[4], r[5]) for r in rs]
        return combine(items)
    car = [r for r in rows if r[0] != "mass_driver"]
    mb, xb_, zb_ = cg(rows, "b")
    mc, xc_, zc_ = cg(rows, "c")
    mb0, xb0, zb0 = cg(car, "b")
    mc0, xc0, zc0 = cg(car, "c")
    L = p["wheelbase"]
    t = ["CAD CG against the mass-budget CG   (cad/generate/cad_cg.py; nothing was changed in either)",
         "",
         "masses: the budget lines (params/car_params.txt); positions: budget line vs the CAD bodies that stand for it",
         "",
         "%-20s %8s  %8s %8s  %8s %8s  %7s %7s  %s" % ("line", "kg", "x budg", "z budg", "x CAD", "z CAD", "dx", "dz", "CAD source")]
    for r in rows:
        t.append("%-20s %8.3f  %8.0f %8.0f  %8.0f %8.0f  %+7.0f %+7.0f  %s" % (r[0], r[1], r[2], r[3], r[4], r[5], r[4] - r[2], r[5] - r[3], r[6]))
    t += ["",
          "car without driver: %.2f kg   budget CG x %.1f, z %.1f   CAD CG x %.1f, z %.1f   (CAD - budget: x %+.1f, z %+.1f mm)" % (mb0, xb0, zb0, xc0, zc0, xc0 - xb0, zc0 - zb0),
          "car with driver:    %.2f kg   budget CG x %.1f, z %.1f   CAD CG x %.1f, z %.1f   (CAD - budget: x %+.1f, z %+.1f mm)" % (mb, xb_, zb_, xc_, zc_, xc_ - xb_, zc_ - zb_),
          "front axle share (with driver): budget %.2f %%, CAD %.2f %%" % (100 * (1 - xb_ / L), 100 * (1 - xc_ / L)),
          "budget CG from car_params.txt (cg_x_from_front_axle, cg_height): x %.1f, z %.1f" % (p["cg_x_from_front_axle"], p["cg_height"]),
          ""]
    txt = "\n".join(t) + "\n"
    out_path.write_text(txt, encoding="utf-8")
    print(txt)
    return (xb_, zb_, xc_, zc_)


def selftest():
    # two point masses by hand: 1 kg at (0, 0) and 3 kg at (100, 40) -> 4 kg at (75, 30)
    m, x, z = combine([(1, 0, 0), (3, 100, 40)])
    ok = (m, round(x, 9), round(z, 9)) == (4, 75.0, 30.0)
    # the comment splits add up to the lines: corners 11.1 per corner, links 2.1 per corner
    ok = ok and abs(sum(CORNER_SPLIT.values()) - 11.1) < 1e-9 and abs(sum(LINK_SPLIT.values()) - 2.1) < 1e-9
    print("cad_cg self-test: %s (4 kg at (%.1f, %.1f), hand (75, 30); corner %.1f kg, link %.1f kg per corner)"
          % ("PASS" if ok else "FAIL", x, z, sum(CORNER_SPLIT.values()), sum(LINK_SPLIT.values())))
    return 0 if ok else 1


def main():
    import build_parts as bp
    ap = argparse.ArgumentParser()
    ap.add_argument("--step", default=str(bp.ROOT / "cad" / "step"))
    ap.add_argument("--selftest", action="store_true")
    args, _ = ap.parse_known_args()
    if args.selftest:
        return selftest()
    p = bp.read_car_params()
    gen = bp.ROOT / "cad" / "generate"
    cad = cad_positions(p, Path(args.step), gen)
    report(p, cad, gen / "cad_cg_report.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
