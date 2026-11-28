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
  wing support to its mount tube ................. 0 (touching, no overlap:
      the rear supports sit on RT2_cross, SUPPORT_MOUNTS); to every other
      tube CLEAR_TUBE as a panel
Packaging envelopes (cad/step/env_*.step, made by envelopes.py) are checked
too, but their results are packaging findings, not rule failures: every
clash is numbered in cad/generate/packaging_report.txt and the exit code
does not change (they are space reservations, not designed parts):
  envelope to frame tube ......................... CLEAR_TUBE (as above and
      as the frame_layout.m driver and battery boxes)
  envelope to a tyre (same poses as above) ....... CLEAR_TYRE (a brake is
      inside its own wheel: checked against its own rim instead, CLEAR_RIM)
  envelope to a suspension link, upright or hub .. CLEAR_LINK (static; the
      SolidWorks members rebuilt from the hardpoints, ends cut back as
      BuildSuspension does)
  envelope to a body part or a rim ............... no overlap
  envelope to envelope ........................... no overlap
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
SUPPORT_MOUNTS = {"rw_support_R": {"RT2_cross"}, "rw_support_L": {"RT2_cross"}}   # tubes a support is mounted on (touch allowed)
# parts a support must touch (it carries them, or is carried by them): gap under 0.1 mm, no overlap
SUPPORT_TOUCH = {"rw_support_R": ["rw_main"], "rw_support_L": ["rw_main"],
                 "fw_support_R": ["fw_main", "nose"], "fw_support_L": ["fw_main", "nose"]}
CLEAR_TYRE = 25.0
TUBE_R = 12.7
CLEAR_LINK = 5.0        # envelope to a suspension member (static)
CLEAR_RIM = 5.0         # brake envelope to its own rim
LINK_R = 15.9 / 2       # wishbones, tie rods, pushrods (BuildSuspension LinkProfile 15.9 x 0.9)
UPRIGHT_R = 25.4 / 2    # upright and hub members


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


def suspension_members(p):
    """name -> solid: the BuildSuspension members (static) as cylinders between the hardpoints,
    ends cut back as BuildSuspension.Parts does (Cut a, b, ca, cb)."""
    import numpy as np
    out = {}

    def cyl(a, b, r, ca=0.0, cb=0.0):
        a, b = np.array(a, float), np.array(b, float)
        u = (b - a) / np.linalg.norm(b - a)
        a, b = a + ca * u, b - cb * u
        return Solid.make_cylinder(r, float(np.linalg.norm(b - a)), Plane(origin=tuple(a), z_dir=tuple(b - a)))

    for cn in ("FR", "FL", "RR", "RL"):
        ax = "f" if cn[0] == "F" else "r"
        s = 1 if cn[1] == "R" else -1

        def hp(n, ax=ax, s=s):
            return (p[f"{ax}_{n}_x"], s * p[f"{ax}_{n}_y"], p[f"{ax}_{n}_z"])
        tie = "tierod" if ax == "f" else "toelink"
        xw = 0.0 if ax == "f" else p["wheelbase"]
        ht = (p["track_front"] if ax == "f" else p["track_rear"]) / 2
        cam = math.radians(p["static_camber_front"] if ax == "f" else p["static_camber_rear"])
        wc = (xw, s * ht, p["tyre_rolling_radius"])
        axu = (0.0, s * math.cos(cam), -math.sin(cam))
        lo, up = hp("lwb_out"), hp("uwb_out")
        mid = tuple((lo[k] + up[k]) / 2 for k in range(3))
        out[f"{cn}_lwb"] = cyl(hp("lwb_in_fwd"), lo, LINK_R, 20, 15).fuse(cyl(hp("lwb_in_aft"), lo, LINK_R, 20, 15))
        out[f"{cn}_uwb"] = cyl(hp("uwb_in_fwd"), up, LINK_R, 20, 15).fuse(cyl(hp("uwb_in_aft"), up, LINK_R, 20, 15))
        out[f"{cn}_tie"] = cyl(hp(tie + "_in"), hp(tie + "_out"), LINK_R, 15, 15)
        out[f"{cn}_push"] = cyl(hp("pushrod_out"), hp("pushrod_in"), LINK_R, 15, 30)
        out[f"{cn}_upright"] = cyl(lo, up, UPRIGHT_R, 15, 15).fuse(cyl(mid, hp(tie + "_out"), UPRIGHT_R, 0, 15)).fuse(cyl(mid, wc, UPRIGHT_R))
        out[f"{cn}_hub"] = cyl(tuple(wc[k] - 10 * axu[k] for k in range(3)), tuple(wc[k] + 45 * axu[k] for k in range(3)), UPRIGHT_R)
    return out


def packaging(p, envs, parts, tubes, tyres, members):
    """Numbered packaging findings for the envelopes. Returns (lines, number of clashes)."""
    lines, n = [], 0

    def clash(txt):
        nonlocal n
        n += 1
        lines.append(f"CLASH {n:2d}  {txt}")

    def ok(txt):
        lines.append(f"ok        {txt}")

    def fmt(g, v):
        return f"overlap {v:.0f} mm3" if v > 1.0 else f"gap {g:.1f} mm"

    names = list(envs)
    for e in names:
        E = envs[e]
        # frame tubes and joints
        bad, worst = [], None
        for tn, t in tubes:
            g, v = gap(E, t, CLEAR_TUBE)
            if g is None:
                continue
            if worst is None or g < worst[0]:
                worst = (g, tn)
            if g < CLEAR_TUBE:
                bad.append((v, g, tn))
        if bad:
            bad.sort(key=lambda b: (-b[0], b[1]))
            clash(f"{e} vs frame: " + "; ".join(f"{tn} {fmt(g, v)}" for v, g, tn in bad) + f" (rule >= {CLEAR_TUBE:.0f} mm)")
        else:
            ok(f"{e} vs frame: " + (f"closest {worst[1]} {worst[0]:.1f} mm" if worst else f"no tube within {CLEAR_TUBE:.0f} mm"))
        # tyres; a brake turns with its own wheel, so it is checked against its own rim instead
        own = None
        if e.startswith("env_brake_"):
            cn = e[-2:]
            own = ("tyre_front" if cn[0] == "F" else "tyre_rear", cn[1])
            rim = parts.get("rim_front" if cn[0] == "F" else "rim_rear")
            if rim is not None:
                r = rim if cn[1] == "R" else rim.mirror(Plane.XZ)
                g, v = gap(E, r, CLEAR_RIM)
                g = float("inf") if g is None else g
                (ok if g >= CLEAR_RIM and v <= 1.0 else clash)(f"{e} vs its own rim: {fmt(g, v)} (rule >= {CLEAR_RIM:.0f} mm)")
        for tname, poses in tyres.items():
            worst = None
            for pose, sol in poses:
                if own and tname == own[0] and pose.startswith(own[1] + " "):
                    continue
                g, v = gap(E, sol, CLEAR_TYRE)
                if g is not None and (worst is None or g < worst[0]):
                    worst = (g, pose, v)
            if worst is None:
                continue
            (ok if worst[0] >= CLEAR_TYRE else clash)(f"{e} vs {tname}: closest {fmt(worst[0], worst[2])} at {worst[1]} (rule >= {CLEAR_TYRE:.0f} mm)")
        # suspension members (static)
        for mn, M in members.items():
            g, v = gap(E, M, CLEAR_LINK)
            if g is None:
                continue
            (ok if g >= CLEAR_LINK and v <= 1.0 else clash)(f"{e} vs {mn}: {fmt(g, v)} (rule >= {CLEAR_LINK:.0f} mm, static)")
        # body parts and rims: no overlap
        for bn, B in parts.items():
            if bn.startswith("rim") and e.startswith("env_brake_"):
                continue
            for tag, Bs in ((("", B),) if not bn.startswith("rim") else (("R", B), ("L", B.mirror(Plane.XZ)))):
                g, v = gap(E, Bs, 0.0)
                if g is not None and v > 1.0:
                    clash(f"{e} vs {bn}{(' ' + tag) if tag else ''}: overlap {v:.0f} mm3 (rule: no overlap)")
    # envelope against envelope
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            g, v = gap(envs[a], envs[b], 0.0)
            if g is not None and v > 1.0:
                clash(f"{a} vs {b}: overlap {v:.0f} mm3 (rule: no overlap between envelopes)")
    return lines, n


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
             "rw_endplate_R", "rw_endplate_L", "floor_diffuser", "nose", "sidepod_R", "sidepod_L", "rim_front", "rim_rear",
             "rw_support_R", "rw_support_L", "fw_support_R", "fw_support_L"]
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
            if tn in SUPPORT_MOUNTS.get(n, ()):
                # a support sits on its mount tube: it must touch (gap under 0.1 mm) without overlapping
                rule(v <= 1.0 and g < 0.1, f"{n} on its mount tube {tn}: gap {g:.2f} mm, overlap {v:.1f} mm3 (rule: touching, no overlap)")
                continue
            if worst is None or g < worst[0]:
                worst = (g, tn)
            if g < CLEAR_TUBE:
                bad.append(f"{tn} {('overlap ' + format(v, '.0f') + ' mm3') if v > 0 else format(g, '.1f') + ' mm'}")
        if worst is None:
            rule(True, f"{n} vs frame: no {'other ' if n in SUPPORT_MOUNTS else ''}tube within {CLEAR_TUBE:.0f} mm")
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
    # 3. supports touch what they hold and what holds them
    for n, others in SUPPORT_TOUCH.items():
        for o in others:
            if n in parts and o in parts:
                g, v = gap(parts[n], parts[o], 1.0)
                g = float("inf") if g is None else g
                rule(g < 0.1 and v <= 1.0, f"{n} touches {o}: gap {g:.2f} mm, overlap {v:.1f} mm3 (rule: touching, no overlap)")
    # 4. parts against each other (no overlap)
    for i, a in enumerate(body):
        for b in body[i + 1:]:
            g, v = gap(parts[a], parts[b], 0.0)
            if g is not None and v > 1.0:
                rule(False, f"{a} / {b}: overlap {v:.0f} mm3")
    # 5. packaging envelopes: findings, not rule failures (see the docstring)
    envs = {f.stem: import_step(str(f)) for f in sorted(Path(args.step).glob("env_*.step"))}
    if envs:
        from envelopes import masses
        order = list(masses(p))
        envs = {k: envs[k] for k in sorted(envs, key=lambda k: order.index(k) if k in order else 999)}
        plines, nclash = packaging(p, envs, parts, tubes, tyres, suspension_members(p))
        ptxt = (f"PACKAGING: {nclash} clash(es) for {len(envs)} envelopes   (envelopes are space reservations, not designed parts; "
                f"a clash is a finding for docs/buildup_audit.md, not a rule failure)\n"
                f"rules: frame tube >= {CLEAR_TUBE:.0f} mm; tyre (static, bump, droop, steer) >= {CLEAR_TYRE:.0f} mm; brake to its own rim >= {CLEAR_RIM:.0f} mm; "
                f"suspension member (static) >= {CLEAR_LINK:.0f} mm; body part, rim, other envelope: no overlap\n\n" + "\n".join(plines) + "\n")
        Path(args.out).with_name("packaging_report.txt").write_text(ptxt, encoding="utf-8")
        lines.append(f"INFO  packaging: {nclash} clash(es) for {len(envs)} envelopes, listed in packaging_report.txt (findings, not rule failures)")
        print(ptxt)
    head = "ALL PASS" if not fails else f"{len(fails)} RULE(S) FAILED"
    txt = (f"{head}   clearance check, parts from {args.step}\n"
           f"rules: body to frame tube >= {CLEAR_TUBE:.0f} mm; anything to a tyre (static, bump +{p['wheel_travel_bump']:.0f}, droop -{p['wheel_travel_droop']:.0f}, "
           f"front steer +-{p['steer_max_wheel_angle']:.0f} deg) >= {CLEAR_TYRE:.0f} mm; parts must not overlap each other\n\n" + "\n".join(lines) + "\n")
    Path(args.out).write_text(txt, encoding="utf-8")
    print(txt)
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
