#!/usr/bin/env python3
"""Clearance check of the build123d bodies against the frame tubes, the
tyres over their travel and steering, and each other. Independent of
SolidWorks (BuildAssembly's interference check confirms it in the app).

Run:  .venv/Scripts/python cad/generate/check_clearances.py [--step cad/step]
Writes cad/generate/clearance_report.txt and exits 1 if any rule fails.

Rules (the minimum gap between two surfaces, mm; overlap = negative):
  body panel to frame tube outer surface ......... CLEAR_TUBE  (panels are
      bonded/bolted on brackets; 10 mm leaves room for the brackets and the
      tolerance of a hand-welded frame)
  any part to a tyre, wheel at static, full bump
      and full droop, front also at full steering
      lock both ways .............................. CLEAR_TYRE  (tyre growth,
      camber change and flex under load)
  part to part (not tyre) ........................ 0 (touching allowed:
      endplates hold the wing elements, the floor carries the sidepods)
The frame tubes come from cad/frame/frame_nodes.csv and frame_tubes.csv
(25.4 mm OD), plus a cube of side 2r at every node for the trimmed joint's square
corners (cylinders alone missed the bulkhead corners SolidWorks found). The tyre envelope is the build_parts tyre solid moved up by
wheel_travel_bump, down by wheel_travel_droop and turned by
steer_max_wheel_angle about the vertical axis through the wheel centre.
Parts are read from the STEP files when --step is given (what SolidWorks
imports), otherwise rebuilt from build_parts.
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_parts as bp  # noqa: E402
from build123d import Axis, Plane, Pos, Rot, Solid, import_step  # noqa: E402

CLEAR_TUBE = 10.0
CLEAR_TYRE = 25.0
TUBE_R = 12.7


def frame_tubes():
    nodes = {}
    with open(bp.ROOT / "cad" / "frame" / "frame_nodes.csv", newline="") as f:
        for r in csv.DictReader(f):
            nodes[r["node"]] = (float(r["x_mm"]), float(r["y_mm"]), float(r["z_mm"]))
    tubes = []
    with open(bp.ROOT / "cad" / "frame" / "frame_tubes.csv", newline="") as f:
        for r in csv.DictReader(f):
            if r["tube"].startswith("#") or not r.get("node_b"):
                continue
            a, b = nodes[r["node_a"]], nodes[r["node_b"]]
            d = tuple(b[i] - a[i] for i in range(3)); L = math.sqrt(sum(c * c for c in d))
            cyl = Solid.make_cylinder(float(r["od_mm"]) / 2, L, Plane(origin=a, z_dir=d))
            tubes.append((r["tube"], cyl))
    # joints: tubes trimmed square to each other leave square corners (a 2r cube at the node)
    from build123d import Box
    for n, c in nodes.items():
        tubes.append((f"joint {n}", Pos(*c) * Box(2 * TUBE_R, 2 * TUBE_R, 2 * TUBE_R)))
    return tubes


def tyre_envelopes(p):
    """name -> list of (pose label, solid)."""
    out = {}
    for name, x, ht, front in (("tyre_front", 0.0, p["track_front"] / 2, True), ("tyre_rear", p["wheelbase"], p["track_rear"] / 2, False)):
        poses = []
        for side, tag in ((1, "R"), (-1, "L")):
            base = bp.build_tyre(p, x, ht)
            if side < 0:
                base = base.mirror(Plane.XZ)
            poses.append((f"{tag} static", base))
            poses.append((f"{tag} bump +{p['wheel_travel_bump']:.0f}", Pos(0, 0, p["wheel_travel_bump"]) * base))
            poses.append((f"{tag} droop -{p['wheel_travel_droop']:.0f}", Pos(0, 0, -p["wheel_travel_droop"]) * base))
            if front:
                c = (x, side * ht, 0)
                for s in (1, -1):
                    ang = s * p["steer_max_wheel_angle"]
                    poses.append((f"{tag} steer {ang:+.0f} deg", base.rotate(Axis(c, (0, 0, 1)), ang)))
                    poses.append((f"{tag} steer {ang:+.0f} deg + bump", Pos(0, 0, p["wheel_travel_bump"]) * base.rotate(Axis(c, (0, 0, 1)), ang)))
        out[name] = poses
    return out


def gap(a, b, limit):
    """Minimum gap a-b in mm (negative = overlap depth unknown, reported as
    -volume in mm3 / 1000 with the volume), None if the boxes are further than limit."""
    ba, bb = a.bounding_box(), b.bounding_box()
    if (ba.min.X > bb.max.X + limit or bb.min.X > ba.max.X + limit or ba.min.Y > bb.max.Y + limit or
            bb.min.Y > ba.max.Y + limit or ba.min.Z > bb.max.Z + limit or bb.min.Z > ba.max.Z + limit):
        return None, 0.0
    try:
        v = (a & b).volume
    except Exception:  # noqa: BLE001
        v = 0.0
    if v > 1.0:
        return 0.0, v
    return a.distance_to(b), 0.0


def load_parts(p, step_dir: Path | None):
    names = ["fw_main", "fw_flap1", "fw_flap2", "fw_endplate_R", "fw_endplate_L", "rw_main", "rw_flap1", "rw_flap2",
             "rw_endplate_R", "rw_endplate_L", "floor_diffuser", "nose", "sidepod_R", "sidepod_L", "rim_front", "rim_rear"]
    parts = {}
    for n in names:
        f = step_dir / f"{n}.step" if step_dir else None
        if f and f.exists():
            parts[n] = import_step(str(f))
    return parts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--step", default=str(bp.ROOT / "cad" / "step"))
    ap.add_argument("--out", default=str(bp.ROOT / "cad" / "generate" / "clearance_report.txt"))
    args = ap.parse_args()
    p = bp.read_car_params()
    parts = load_parts(p, Path(args.step))
    tubes = frame_tubes()
    tyres = tyre_envelopes(p)
    lines, fails = [], []

    def rule(ok, txt):
        lines.append(("PASS  " if ok else "FAIL  ") + txt)
        if not ok:
            fails.append(txt)

    body = [n for n in parts if not n.startswith("rim")]
    # 1. body parts against the frame
    for n in body:
        worst = None; bad = []
        for tn, t in tubes:
            g, v = gap(parts[n], t, CLEAR_TUBE)
            if g is None:
                continue
            if worst is None or g < worst[0]:
                worst = (g, tn)
            if g < CLEAR_TUBE:
                bad.append(f"{tn} {('overlap ' + format(v, '.0f') + ' mm3') if v > 0 else format(g, '.1f') + ' mm'}")
        if worst is None:
            rule(True, f"{n} vs frame: no tube within {CLEAR_TUBE:.0f} mm")
        else:
            rule(not bad, f"{n} vs frame: closest {worst[1]} {worst[0]:.1f} mm (rule >= {CLEAR_TUBE:.0f})" + (f"; too close: {'; '.join(bad)}" if bad else ""))
    # 2. every part against the tyre envelopes
    for tname, poses in tyres.items():
        for n in body:
            worst = None
            for pose, s in poses:
                g, v = gap(parts[n], s, CLEAR_TYRE)
                if g is not None and (worst is None or g < worst[0]):
                    worst = (g, pose, v)
            if worst is None:
                continue
            txt = f"{n} vs {tname}: closest {worst[0]:.1f} mm at {worst[1]}" + (f" (overlap {worst[2]:.0f} mm3)" if worst[2] > 0 else "")
            rule(worst[0] >= CLEAR_TYRE, txt + f" (rule >= {CLEAR_TYRE:.0f})")
    # 3. parts against each other (no overlap)
    for i, a in enumerate(body):
        for b in body[i + 1:]:
            g, v = gap(parts[a], parts[b], 0.0)
            if g is not None and v > 1.0:
                rule(False, f"{a} / {b}: overlap {v:.0f} mm3")
    head = "ALL PASS" if not fails else f"{len(fails)} RULE(S) FAILED"
    txt = (f"{head}   clearance check, parts from {args.step}\n"
           f"rules: body to frame tube >= {CLEAR_TUBE:.0f} mm; anything to a tyre (static, bump +{p['wheel_travel_bump']:.0f}, droop -{p['wheel_travel_droop']:.0f}, "
           f"front steer +-{p['steer_max_wheel_angle']:.0f} deg) >= {CLEAR_TYRE:.0f} mm; parts must not overlap each other\n\n" + "\n".join(lines) + "\n")
    Path(args.out).write_text(txt, encoding="utf-8")
    print(txt)
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
