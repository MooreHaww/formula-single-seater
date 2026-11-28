#!/usr/bin/env python3
"""Build the simple bodies of the Formula Single-Seater with build123d and
export one STEP file per part to cad/step/.

Run (no install needed, uv downloads build123d into a cache):
    uvx --from build123d python cad/generate/build_parts.py
or with any Python that has build123d:
    python cad/generate/build_parts.py [--only tyre,rim,...] [--out cad/step]

Everything is driven by params/car_params.txt (read with the same rules as
matlab/common/read_car_params.m: "name"= expression ' comment). Car axes:
X rearward from the front axle, Y to the right, Z up from the ground, mm.
Parts are built in car coordinates for the right-hand side where a side
matters, so they drop into the assembly with plane mates only.

Parts (feature order follows docs/cad_playbook/06..12):
  tyre_front, tyre_rear     solid of revolution with the ground flat
  rim_front, rim_rear        barrel, lips, centre disc with bore and 4 studs
  fw_main, fw_flap1, fw_flap2, fw_endplate_R/L     front wing, variant C angles
  rw_main, rw_flap1, rw_flap2, rw_endplate_R/L     rear wing, variant C angles
  floor_diffuser             flat floor + diffuser plate + 4 strakes (variant C)
  nose                       5-section loft, shelled 2 mm, open at the front hoop
  sidepod_R / sidepod_L      loft, shelled 2 mm, open on the inboard face;
                             must enclose the battery-structure box
                             y 320..540, z 60..320 between X 700 and 1220
The script prints which parts built, their bounding boxes and a mass guess,
and which were skipped with the error, then exits 0 (1 if nothing built).
"""
from __future__ import annotations

import argparse
import math
import re
import sys
import traceback
from pathlib import Path

try:
    from build123d import (
        Axis, Box, Compound, Cylinder, Ellipse, Face, Line, Plane, Polygon, Pos, RectangleRounded,
        Rot, Shell, Solid, Spline, Vector, Wire, export_step, extrude, loft, make_face, offset, revolve, mirror,
    )
except ImportError:  # pragma: no cover
    print("build123d is not installed. Run:  uvx --from build123d python cad/generate/build_parts.py")
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[2]
PARAMS = ROOT / "params" / "car_params.txt"
AIRFOILS = ROOT / "cad" / "airfoils"

# ---------------------------------------------------------------------------
# parameter file
# ---------------------------------------------------------------------------
_LINE = re.compile(r'^"([^"]+)"\s*=\s*(.*)$')
_REF = re.compile(r'"([^"]+)"')
_SAFE = re.compile(r'^[\d\s\.\+\-\*\/\^\(\)eEsqrtabs,]+$')


def read_car_params(file: Path = PARAMS) -> dict[str, float]:
    """Port of matlab/common/read_car_params.m (same comment and unit rules)."""
    raw: dict[str, str] = {}
    for line in file.read_text(encoding="utf-8", errors="replace").splitlines():
        s = line.strip()
        if not s or s.startswith("'"):
            continue
        m = _LINE.match(s)
        if not m:
            continue
        name, expr = m.group(1), m.group(2)
        out, inq = [], False
        for ch in expr:                      # strip the trailing ' comment
            if ch == '"':
                inq = not inq
            elif ch == "'" and not inq:
                break
            out.append(ch)
        expr = "".join(out).strip()
        expr = re.sub(r"(?<=\d)\s*(mm|deg)(?![A-Za-z_])", "", expr)
        raw[name] = expr
    p: dict[str, float] = {}
    pending = list(raw)
    for _ in range(50):
        still = []
        for name in pending:
            expr = raw[name]
            ok = True
            for ref in _REF.findall(expr):
                if ref in p:
                    expr = expr.replace(f'"{ref}"', f"({p[ref]!r})")
                else:
                    ok = False
            if not ok:
                still.append(name)
                continue
            if not _SAFE.match(expr):
                raise ValueError(f'cannot evaluate "{name}"= {raw[name]}')
            p[name] = float(eval(expr.replace("^", "**"), {"__builtins__": {}}, {"sqrt": math.sqrt, "abs": abs}))
        if not still:
            break
        if len(still) == len(pending):
            raise ValueError("unresolved references: " + ", ".join(still))
        pending = still
    return p


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def yz_plane(x: float) -> Plane:
    """Plane normal to X at station x; local u = +Y (right), local v = +Z (up)."""
    return Plane(origin=(x, 0, 0), x_dir=(0, 1, 0), z_dir=(1, 0, 0))


def section_rounded(x: float, width: float, height: float, radius: float, z_bottom: float, y_centre: float = 0.0) -> Face:
    """Rounded rectangle on the plane at X = x, bottom edge at z_bottom."""
    sk = yz_plane(x) * (Pos(y_centre, z_bottom + height / 2) * RectangleRounded(width, height, radius))
    return sk.faces()[0]


def section_ellipse(x: float, width: float, height: float, y_centre: float, z_centre: float) -> Face:
    sk = yz_plane(x) * (Pos(y_centre, z_centre) * Ellipse(width / 2, height / 2))
    return sk.faces()[0]


def read_airfoil(name: str) -> list[tuple[float, float]]:
    """Selig order (TE -> upper -> LE -> lower -> TE), x/c and y/c."""
    pts = []
    for line in (AIRFOILS / f"{name}.dat").read_text().splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2:
            try:
                pts.append((float(parts[0]), float(parts[1])))
            except ValueError:
                pass
    return pts


def airfoil_face(name: str, chord: float, aoa_deg: float, le_x: float, le_z: float) -> tuple[Face, dict]:
    """Closed airfoil section in the X-Z plane (y = 0), camber DOWN (downforce),
    rotated about the leading edge so a positive angle lifts the trailing edge.
    Returns the face and the LE/TE points and lowest z."""
    a = math.radians(aoa_deg)
    ca, sa = math.cos(a), math.sin(a)
    pts3 = []
    for xc, yc in read_airfoil(name):
        x, z = xc * chord, -yc * chord          # mirror in Z: camber points down
        xr, zr = x * ca - z * sa, x * sa + z * ca
        pts3.append((le_x + xr, 0.0, le_z + zr))
    # Selig files from make_airfoils.m start and end on the same TE point: drop the duplicate
    if math.dist(pts3[0], pts3[-1]) < 1e-6 * chord:
        pts3 = pts3[:-1]
    vecs = [Vector(*q) for q in pts3]
    try:                                  # closed spline through all points
        face = make_face(Wire([Spline(*vecs, vecs[0])]))
    except Exception:                     # noqa: BLE001  fall back to a 159-point polyline
        face = make_face(Polyline(*vecs, close=True))
    te = ((pts3[0][0] + pts3[-1][0]) / 2, (pts3[0][2] + pts3[-1][2]) / 2)
    info = {"le": (le_x, le_z), "te": te, "z_min": min(q[2] for q in pts3), "x_max": max(q[0] for q in pts3)}
    return face, info


# ---------------------------------------------------------------------------
# frame envelope: the body panels are sized from the real tube positions
# ---------------------------------------------------------------------------
TUBE_CLEAR = 10.0    # panel inner face to tube outer surface (room for brackets, frame tolerance)
SKIN = 2.0           # panel thickness
LINK_OD = 15.9       # suspension links (wishbones, tie rods, pushrods), tools/sw_harness/BuildSuspension.cs
LINK_CLEAR = 5.0     # slot edge to a moving link, all round


def frame_samples(step: float = 5.0) -> list[tuple[float, float, float, float]]:
    """Points along every tube axis of cad/frame/*.csv: (x, |y|, z, outer radius)."""
    import csv
    nodes = {}
    with open(ROOT / "cad" / "frame" / "frame_nodes.csv", newline="") as f:
        for r in csv.DictReader(f):
            if r["node"].startswith("#"):
                continue
            nodes[r["node"]] = (float(r["x_mm"]), float(r["y_mm"]), float(r["z_mm"]))
    pts = []
    with open(ROOT / "cad" / "frame" / "frame_tubes.csv", newline="") as f:
        for r in csv.DictReader(f):
            if r["tube"].startswith("#") or not r.get("node_b"):
                continue
            a, b = nodes[r["node_a"]], nodes[r["node_b"]]
            rad = float(r["od_mm"]) / 2
            L = math.dist(a, b); n = max(2, int(L / step) + 1)
            for k in range(n):
                t = k / (n - 1)
                x, y, z = (a[i] + t * (b[i] - a[i]) for i in range(3))
                pts.append((x, abs(y), z, rad))
    return pts


def section_from_frame(pts, x_lo: float, x_hi: float, r_max: float, y_max: float | None = None):
    """Rounded-rectangle section (width, height, corner R, bottom z) whose inner
    face keeps TUBE_CLEAR from every tube sample with x in [x_lo, x_hi] (and |y| <= y_max
    if given), the tube radius counted also along x (a tube end reaches r past its node).
    A ruled loft between two stations is linear, so each station is sized for
    the whole interval on both sides of it (see build_nose)."""
    sel = [(y, z, r) for (x, y, z, r) in pts if x_lo - r <= x <= x_hi + r and (y_max is None or y <= y_max)]
    if not sel:
        return None
    m = TUBE_CLEAR + SKIN
    hw = max(y + r for y, z, r in sel) + m
    zb = min(z - r for y, z, r in sel) - m
    zt = max(z + r for y, z, r in sel) + m
    R = r_max
    while R > 10:
        # the square corner of a joint (y + r, z +- r) must lie inside the section's inner
        # face shrunk by TUBE_CLEAR: in a corner zone, within R - m of the arc centre
        # (SolidWorks found the bulkhead corners 0.1 cm3 into a nose sized for round tubes)
        ok = True
        for y, z, r in sel:
            qy = y + r
            for qz, zc, upper in ((z + r, zt - R, True), (z - r, zb + R, False)):
                if qy > hw - R and (qz > zc if upper else qz < zc):
                    if math.hypot(qy - (hw - R), qz - zc) > R - m:
                        ok = False
        if ok:
            break
        R -= 5
    return 2 * hw, zt - zb, R, zb


def bbox_str(part) -> str:
    bb = part.bounding_box()
    return f"X {bb.min.X:7.1f}..{bb.max.X:7.1f}  Y {bb.min.Y:7.1f}..{bb.max.Y:7.1f}  Z {bb.min.Z:7.1f}..{bb.max.Z:7.1f}"


# ---------------------------------------------------------------------------
# parts
# ---------------------------------------------------------------------------
def build_tyre(p, x_axle: float, half_track: float):
    """Solid of revolution about the wheel axis with a flat below Z = 0."""
    r_bead, r_od, w = p["rim_diameter"] / 2, p["tyre_od"] / 2, p["tyre_width"]
    # profile in the plane containing the axis: local u = axial (Y), v = radial (Z)
    prof_plane = Plane(origin=(0, 0, 0), x_dir=(0, 1, 0), z_dir=(1, 0, 0))
    prof = (prof_plane * (Pos(0, (r_bead + r_od) / 2) * RectangleRounded(w, r_od - r_bead, 25))).faces()[0]
    tyre = revolve(prof, Axis.Y, 360)
    # hollow carcass 8 mm thick (a solid rubber ring would weigh 22 kg; a real 18x6-10 is about 4 kg)
    tc = 8.0
    inner = (prof_plane * (Pos(0, (r_bead + r_od - tc) / 2) * RectangleRounded(w - 2 * tc, r_od - tc - r_bead, 17))).faces()[0]
    tyre = tyre - revolve(inner, Axis.Y, 360)
    tyre = Pos(x_axle, half_track, p["tyre_rolling_radius"]) * tyre
    ground = Pos(x_axle, half_track, -500) * Box(1000, 1000, 1000)   # everything below Z = 0
    tyre = tyre - ground
    return tyre


def build_rim(p, x_axle: float, half_track: float):
    """Barrel with bead seats and lips, 4 mm wall, centre disc 6 mm at 40 mm
    outboard offset, bore D 64, four D 10.5 studs on PCD 100."""
    w = p["rim_width"]; r_seat = p["rim_diameter"] / 2; r_lip = r_seat + 13; r_barrel = r_seat - 7
    h = w / 2; t = 4.0
    outer = [(-h, r_seat), (-h, r_lip), (-h + 8, r_lip), (-h + 8, r_seat), (-h + 19, r_seat), (-h + 24, r_barrel),
             (h - 24, r_barrel), (h - 19, r_seat), (h - 8, r_seat), (h - 8, r_lip), (h, r_lip), (h, r_seat)]
    inner = [(u, v - t) for (u, v) in reversed(outer)]
    prof_plane = Plane(origin=(0, 0, 0), x_dir=(0, 1, 0), z_dir=(1, 0, 0))
    prof = (prof_plane * Polygon(*(outer + inner), align=None)).faces()[0]
    barrel = revolve(prof, Axis.Y, 360)
    disc = Rot(90, 0, 0) * Cylinder(r_barrel - t + 1, 6)          # axis along Y, 1 mm into the barrel wall
    disc = Pos(0, 40, 0) * disc                                    # offset 40 outboard (+Y for the right wheel)
    bore = Pos(0, 40, 0) * (Rot(90, 0, 0) * Cylinder(32, 10))
    disc = disc - bore
    for k in range(4):
        ang = math.radians(45 + 90 * k)
        stud = Pos(50 * math.cos(ang), 40, 50 * math.sin(ang)) * (Rot(90, 0, 0) * Cylinder(10.5 / 2, 10))
        disc = disc - stud
    rim = barrel + disc
    return Pos(x_axle, half_track, p["tyre_rolling_radius"]) * rim


def build_wing(p, prefix: str, variant: str = "C"):
    """Three elements of a wing stack at the variant's angles. Returns
    {name: solid} and the stack geometry. Positioned per the playbook:
    front: main LE at X -600, lowest point at Z fw_ground_clearance;
    rear: main LE at Z rw_height, flap-2 TE at X wheelbase + rear_overhang."""
    gap, overlap = p["wing_element_gap"], p["wing_element_overlap"]
    span = p[f"{prefix}_span"]
    names = [f"{prefix}_main", f"{prefix}_flap1", f"{prefix}_flap2"]
    chords = [p[f"{prefix}_main_chord"], p[f"{prefix}_flap1_chord"], p[f"{prefix}_flap2_chord"]]
    aoas = [p[f"{prefix}_main_aoa_{variant}"], p[f"{prefix}_flap1_aoa_{variant}"], p[f"{prefix}_flap2_aoa_{variant}"]]
    # first pass at LE (0, 0) to find the stack's extent
    faces, infos = [], []
    le = (0.0, 0.0)
    for name, c, a in zip(names, chords, aoas):
        f, info = airfoil_face(name, c, a, *le)
        faces.append(f); infos.append(info)
        le = (info["te"][0] - overlap, info["te"][1] + gap)
    if prefix == "fw":
        # main LE at fw_le_x, the value the CFD session (cfd_variants.py) and the aero estimate use;
        # at the playbook's -600 the flap stack runs through the front tyres
        dx = p.get("fw_le_x", -600.0)
        dz = p["fw_ground_clearance"] - infos[0]["z_min"]
    else:
        dx = p["wheelbase"] + p["rear_overhang"] - infos[-1]["x_max"]
        dz = p["rw_height"] - 0.0
    solids = {}
    le = (dx, dz)
    geo = {}
    y_in = p.get("fw_flap_inner_y", 0.0) if prefix == "fw" else 0.0
    for name, c, a in zip(names, chords, aoas):
        f, info = airfoil_face(name, c, a, *le)
        if prefix == "fw" and name != "fw_main" and y_in > 0:
            # front flaps only outboard of fw_flap_inner_y (as in the CFD geometry): under the
            # nose only the main element runs through. One part, two bodies (right and left).
            solids[name] = Compound([Pos(0, y_in, 0) * extrude(f, amount=span / 2 - y_in, dir=(0, 1, 0)),
                                     Pos(0, -y_in, 0) * extrude(f, amount=span / 2 - y_in, dir=(0, -1, 0))])
        else:
            solids[name] = extrude(f, amount=span / 2, both=True)
        geo[name] = info
        le = (info["te"][0] - overlap, info["te"][1] + gap)
    return solids, geo


def build_endplate(p, prefix: str, geo: dict, side: int):
    """Flat 6 mm plate at the wing tip, extruded outward. Front: 850 x 350,
    bottom Z 30, leading edge 100 mm ahead of the main LE. Rear: 950 x 550,
    trailing edge at the stack TE, top at rw_height + 320."""
    t = 6.0
    if prefix == "fw":
        L, H = p["fw_endplate_length"], p["fw_endplate_height"]
        x0 = geo["fw_main"]["le"][0] - 100; z0 = 30.0
    else:
        L, H = p["rw_endplate_length"], p["rw_endplate_height"]
        x0 = p["wheelbase"] + p["rear_overhang"] - L
        z_top = max(geo["rw_flap2"]["te"][1] + 40, p["rw_height"] + 320)   # playbook: rw_height + 320, "verify": the C flap-2 TE is higher
        z0 = z_top - H
    y_in = side * p[f"{prefix}_span"] / 2
    # plate outline in the X-Z plane: rounded forward-top corner R 150, 45 deg cut at the lower-rear corner (100)
    r = 150.0; c = 100.0
    pts = [(x0, z0), (x0 + L - c, z0), (x0 + L, z0 + c), (x0 + L, z0 + H), (x0 + r, z0 + H)]
    arc = [(x0 + r - r * math.sin(math.radians(ang)), z0 + H - r + r * math.cos(math.radians(ang))) for ang in range(10, 91, 10)]
    pts += arc
    pts = [(x, 0.0, z) for (x, z) in pts]
    face = make_face(Wire([Line(Vector(*pts[i]), Vector(*pts[(i + 1) % len(pts)])) for i in range(len(pts))]))
    plate = extrude(face, amount=t, dir=(0, side, 0))
    return Pos(0, y_in, 0) * plate


def build_floor(p):
    """Flat floor (10 mm at ride_height_front) from floor_start to the rear
    axle, stepped in beside the rear tyres, plus the variant C diffuser plate
    and four strakes with their top at diffuser_exit_height at the exit."""
    # 2026-11-17 clearance rules (docs/log.md): raked from ride_height_front at the leading
    # edge to ride_height_rear at the rear axle; steps in to |y| 455 from X 1290 so the
    # rear tyre keeps 25 mm at full droop (the 470 / 1400 step touched it); strakes and
    # side fences hang UNDER the diffuser roof (above it they ran into the rear lower
    # cross tube RS2_L_cross). Same plan, rake and strake positions as cfd_variants.py.
    t = 10.0
    x_le, x_axle = p["floor_start_from_front_axle"], p["wheelbase"]
    z0, z1 = p["ride_height_front"], p.get("ride_height_rear", p["ride_height_front"])
    hw = p["floor_width"] / 2; hw_step = 455.0; x_step = 1290.0

    def xz_prism(pts, y0, y1):
        v = [Vector(x, 0.0, z) for (x, z) in pts]
        face = make_face(Wire([Line(v[i], v[(i + 1) % len(v)]) for i in range(len(v))]))
        return Pos(0, y0, 0) * extrude(face, amount=y1 - y0, dir=(0, 1, 0))
    raked = [(x_le, z0), (x_axle, z1), (x_axle, z1 + t), (x_le, z0 + t)]
    z_at = lambda x: z0 + (z1 - z0) * (x - x_le) / (x_axle - x_le)      # noqa: E731
    wide = [(x_le, z0), (x_step, z_at(x_step)), (x_step, z_at(x_step) + t), (x_le, z0 + t)]
    floor = xz_prism(wide, -hw, hw) + xz_prism(raked, -hw_step, hw_step)
    ang = math.radians(p["diffuser_angle_C"]); Ld = p["diffuser_length"]
    xe, ze = x_axle + Ld, z1 + Ld * math.tan(ang)
    roof = xz_prism([(x_axle, z1), (xe, ze), (xe, ze + t), (x_axle, z1 + t)], -hw_step, hw_step)
    fin = [(x_axle, z1), (xe, z1), (xe, ze + 1.0), (x_axle, z1 + 1.0)]      # 1 mm into the roof
    part = floor + roof
    for y in (150.0, 350.0):
        part = part + xz_prism(fin, y - 4, y + 4) + xz_prism(fin, -y - 4, -y + 4)
    part = part + xz_prism(fin, hw_step - 8, hw_step) + xz_prism(fin, -hw_step, -hw_step + 8)
    return part


def nose_sections(p):
    """The nose's outer sections (x, width, height, corner R, bottom z) and the X where it
    ends (see build_nose). Also used by the front wing supports, which stop on its skin."""
    x_end = p["front_hoop_x"] - 12.7 - TUBE_CLEAR
    secs = [  # x, width, height, corner R, bottom z
        (-p["nose_overhang"], 160, 80, 30, 200),
        (-450, 320, 180, 60, 160),
    ]
    pts = frame_samples()
    st = [-325.0, -230.0, -160.0, -80.0, 0.0, 80.0, 160.0, 280.0, 400.0, 520.0, x_end]
    for i, x in enumerate(st):
        lo = st[max(i - 1, 0)] if i > 0 else -340.0
        hi = st[min(i + 1, len(st) - 1)]
        w, h, R, zb = section_from_frame(pts, lo, hi, 90.0)
        secs.append((x, w, h, R, zb))
    return secs, x_end


def build_nose(p):
    """Ruled loft through the five playbook sections with a 2 mm skin made
    by subtracting an inner loft that pokes through the front-hoop face
    (open at the back). A smooth loft sagged to Z 41 behind the bulkhead
    and offset() with an opening failed on the creased solid."""
    t = SKIN
    # 2026-11-17 clearance rules (docs/log.md): ahead of the bulkhead the two tip sections
    # of cfd_variants.py (underside raised to clear the front wing's main element);
    # from the bulkhead back, every section is sized from the real tube positions so the
    # inner face keeps TUBE_CLEAR (10 mm) from every tube (the playbook sections cut through
    # the front suspension pickups, FBT and the upper frame line). The nose ends
    # TUBE_CLEAR + tube radius ahead of the front hoop plane, where the hoop's sideways
    # tubes leave the frame.
    secs, x_end = nose_sections(p)
    outer = loft([section_rounded(*s) for s in secs], ruled=True)
    inner_secs = [(x, w - 2 * t, h - 2 * t, max(r - t, 2.0), zb + t) for (x, w, h, r, zb) in secs]
    inner_secs[-1] = (inner_secs[-1][0] + 5.0,) + inner_secs[-1][1:]     # 5 mm past the last section: open there
    inner_secs[0] = (inner_secs[0][0] + t,) + inner_secs[0][1:]           # keep a 2 mm wall at the tip
    inner = loft([section_rounded(*s) for s in inner_secs], ruled=True)
    nose = outer - inner
    # slots where the front suspension links pass through the skin (their pivots are on frame
    # brackets inside the nose): every link swept over the wheel travel, the tie rod also over
    # the rack travel, LINK_CLEAR all round
    cut = suspension_sweep(p, "f")
    nose = nose.cut(*cut)
    return nose, (f"2 mm skin, sections from the frame (+{TUBE_CLEAR:.0f} mm), open at X {x_end:.0f}, "
                  f"{len(cut)} link slots cut (+{LINK_CLEAR:.0f} mm)")


def circle_points(a, b, r: float, n: int = 16):
    """n points on the circle of radius r around the line a-b, at a and at b (mm)."""
    import numpy as np
    a, b = np.array(a, float), np.array(b, float)
    d = (b - a) / np.linalg.norm(b - a)
    u = np.cross(d, [0.0, 0.0, 1.0])
    if np.linalg.norm(u) < 1e-6:
        u = np.cross(d, [0.0, 1.0, 0.0])
    u /= np.linalg.norm(u)
    v = np.cross(d, u)
    r = r / math.cos(math.pi / n)            # polygon circumscribes the circle
    ang = np.linspace(0, 2 * math.pi, n, endpoint=False)
    ring = np.outer(np.cos(ang), u) + np.outer(np.sin(ang), v)
    return np.vstack([a + r * ring, b + r * ring])


def hull_solid(points):
    """Convex hull of a point cloud as a polyhedral solid (scipy Qhull, triangles)."""
    from scipy.spatial import ConvexHull
    h = ConvexHull(points)
    faces = []
    for simplex, eq in zip(h.simplices, h.equations):
        tri = [h.points[i] for i in simplex]
        n = Vector(*(tri[1] - tri[0])).cross(Vector(*(tri[2] - tri[0])))
        if n.dot(Vector(*eq[:3])) < 0:          # outward normals
            tri = [tri[0], tri[2], tri[1]]
        faces.append(Face(Wire.make_polygon([Vector(*q) for q in tri], close=True)))
    return Solid(Shell(faces))


def suspension_sweep(p, axle: str) -> list:
    """Cylinders covering every position of the axle's links (both sides) over the wheel
    travel: each link from its fixed inboard point to its outboard joint moved up and down
    by the travel + 5 mm (the outer joints move with the wheel to within a few mm, which
    the clearance covers); the tie rod's inboard end also over +/- steer_rack_travel."""
    r = LINK_OD / 2 + LINK_CLEAR
    bump, droop = p.get("wheel_travel_bump", 30) + 5, p.get("wheel_travel_droop", 30) + 5
    tie = "tierod" if axle == "f" else "toelink"
    pt = lambda n: (p[f"{axle}_{n}_x"], p[f"{axle}_{n}_y"], p[f"{axle}_{n}_z"])
    links = [("lwb_in_fwd", "lwb_out"), ("lwb_in_aft", "lwb_out"), ("uwb_in_fwd", "uwb_out"), ("uwb_in_aft", "uwb_out"),
             (f"{tie}_in", f"{tie}_out"), ("pushrod_in", "pushrod_out")]
    rack = p.get("steer_rack_travel", 40) if axle == "f" else 0.0
    import numpy as np
    out = []
    for side in (1, -1):
        for a, b in links:
            ia, ob = pt(a), pt(b)
            shifts = [-rack, rack] if a.startswith(tie) and rack else [0.0]
            cloud = []
            for dy in shifts:
                for t in (-droop, bump):
                    i2 = (ia[0], side * ia[1] + dy, ia[2])
                    o2 = (ob[0], side * ob[1], ob[2] + t)
                    cloud.append(circle_points(i2, o2, r))
            # one convex solid per link: the hull of its extreme positions (the joint path between
            # the extremes is within a few mm of a straight line; LINK_CLEAR covers it)
            out.append(hull_solid(np.vstack(cloud)))
    return out


def build_sidepod(p, side: int):
    """Right (side = +1) or left sidepod: a ruled loft whose cavity encloses the
    battery structure box |y| 320..540, z 60..320 from X 700 to 1220, with a
    tapered leading cap ahead of it and a taper to the rear-tyre inner face.
    The 2 mm skin is made by subtracting an inner loft (offset() with an
    opening gave an invalid solid on this shape)."""
    t = SKIN
    # 2026-11-17 clearance rules (docs/log.md): the full section runs from TUBE_CLEAR + tube
    # radius ahead of the front hoop plane to the same behind the main hoop plane, and its
    # skin keeps TUBE_CLEAR from every tube outboard of |y| 300 (the hoop-to-sidepod tubes
    # FH_M-SP1_U and MH_M-SP2_U rise to Z 350 at their inboard end and went through the old
    # top at 342). The tail ends 25 mm or more ahead of the rear tyre at full bump.
    # The pod is bonded onto the floor: the floor is its bottom (open there), its lower
    # edge 1 mm above the floor top. Its open inboard face is TUBE_CLEAR outboard of the
    # hoop tubes (|y| 310), so only tubes outboard of that size the pod.
    m = TUBE_CLEAR + t
    y_in = 310.0 + 12.7 + TUBE_CLEAR
    # behind the main hoop, the rear-box top rail MH_M-RS1_U runs outboard towards the rear
    # upper pivots (|y| 350 since 2026-11-18): the open inboard edge of the pod's rear end and
    # tail keeps TUBE_CLEAR from it (it was 6.7 mm with the fixed y_in)
    x_tail = p["main_hoop_x"] + 12.7 + TUBE_CLEAR + 3.0 + 25.0
    behind = [q for q in frame_samples() if p["main_hoop_x"] + 13.0 < q[0] <= x_tail + 5.0 and 0.0 < q[1] < 360.0]
    if behind:
        y_in = max(y_in, max(y + r for (x, y, z, r) in behind) + TUBE_CLEAR)
    pts =[q for q in frame_samples() if q[1] >= y_in and 600.0 <= q[0] <= 1300.0]
    y_out = max(562.0, max(y + r for (x, y, z, r) in pts) + m)
    z0, z1 = p["ride_height_front"], p.get("ride_height_rear", p["ride_height_front"])
    x_le = p["floor_start_from_front_axle"]
    floor_top = max(z0 + (z1 - z0) * (x - x_le) / (p["wheelbase"] - x_le) for x in (600.0, 1300.0)) + 10.0
    z_bot = floor_top + 1.0
    z_top = max(342.0, max(z + r for (x, y, z, r) in pts) + m + 1.0)   # +1: the inboard top corner is the closest point
    x_full0 = p["front_hoop_x"] - 12.7 - TUBE_CLEAR - 3.0
    x_full1 = p["main_hoop_x"] + 12.7 + TUBE_CLEAR + 3.0

    def sections(dy_in, dy_out, dz_bot, dz_top):
        yi, yo = y_in + dy_in, y_out - dy_out
        zb, zt = z_bot + dz_bot, z_top - dz_top
        yc = side * (yi + yo) / 2; w = yo - yi; h = zt - zb
        return [
            section_ellipse(x_full0 - 100, 60 - 2 * dy_out, 180 - 2 * dz_top, side * 440, 200),
            section_rounded(x_full0, w, h, 6 - dy_out / 2, zb, yc),      # R 6: with the bottom open, a larger
            section_rounded(x_full1, w, h, 6 - dy_out / 2, zb, yc),      # corner lifts the wall's edge off the floor
            # tail: inboard edge stays at y_in (stepping in to |y| 310 brought the taper within
            # 6.5 mm of MH_M-RS1_U once RS1_U moved out to |y| 320, 2026-11-17), outboard at 430
            section_rounded(x_full1 + 25, 430 - y_in - dy_in - dy_out, 180 - dz_bot - dz_top, 30 - dy_out, 70 + dz_bot, side * ((y_in + dy_in) + (430 - y_in - dy_in - dy_out) / 2)),
        ]
    outer = loft(sections(0, 0, 0, 0), ruled=True)
    inner = loft(sections(-5.0, t, -5.0, t), ruled=True)  # pokes 5 mm through the inboard face and the bottom: open there
    shell = outer - inner
    note = f"2 mm skin, open inboard (y {y_in:.0f}) and at the bottom (sits on the floor at Z {z_bot:.0f}), top Z {z_top:.0f}"
    # clearance check: the structure box must lie entirely in the cavity
    box = Pos(960, side * 430, 190) * Box(520, 220, 260)   # X 700..1220, |Y| 320..540, Z 60..320
    clash = (shell & box).volume
    return shell, note, clash


# ---------------------------------------------------------------------------
# wing supports (2026-11-28): the CFD winners, rear F and front J (variant CPFF of
# cad/generate/cfd_variants.py; media/cfd/supports/wing_supports_results.md). The section
# is the CFD's own (cfd_variants.rws_section "round": lens, 5 mm round front edge, rear
# edge cut square 3 mm, 16 mm thick at mid-chord), at the CFD's X, Y and chord.
# Where the CFD support runs INTO a body (wing element, nose, hull) it is cut here at that
# body's surface, so the SolidWorks parts touch instead of overlapping:
#   rear: top on the main element's underside (CFD: up to its middle line, fused);
#         bottom saddled on the frame's rear top cross tube RT2_cross (node RT2, the
#         "rear top / wing mount" node). The CFD support starts at Z 300 inside its
#         idealised motor-cover hull, which the parts do not have; at Z 300 it would run
#         through RS2_U_cross, so the CAD support stops on RT2_cross at Z 470 instead.
#   front: bottom on the main element's upper surface, top on the nose's outer skin
#         (CFD: to Z 230 inside the solid CFD nose); the front 22 mm ahead of the nose tip
#         keeps the CFD's flat top at Z 230.
# Material: CFRP skin SUPPORT_SKIN thick (quasi-isotropic carbon/epoxy, RHO_CFRP) over a
# closed-cell PMI foam core (Rohacell 51 class, RHO_CORE). Not structurally designed:
# no load, stiffness or flutter check, no mount hardware (bolts, inserts, clamps).
SUPPORT_SKIN = 1.5      # mm
RHO_CFRP = 1600e-9      # kg/mm3
RHO_CORE = 52e-9        # kg/mm3
SUPPORT_VARIANT = "CPFF"  # the CFD variant with both supports (J front, F rear)


def frame_node(name: str):
    import csv
    with open(ROOT / "cad" / "frame" / "frame_nodes.csv", newline="") as f:
        for r in csv.DictReader(f):
            if r["node"] == name:
                return float(r["x_mm"]), float(r["y_mm"]), float(r["z_mm"])
    raise KeyError(name)


def support_mass(solid):
    """Sandwich mass and its centre: skin = wetted area x SUPPORT_SKIN at RHO_CFRP (centre
    of the skin at the area centroid), core = the rest of the volume at RHO_CORE (at the
    volume centroid). Returns (mass kg, (x, y, z) mm, skin kg, core kg)."""
    faces = solid.faces()
    area = sum(f.area for f in faces)
    ca = [sum(f.area * tuple(f.center())[k] for f in faces) / area for k in range(3)]
    cv_ = tuple(solid.center())
    m_skin = area * SUPPORT_SKIN * RHO_CFRP
    m_core = max(solid.volume - area * SUPPORT_SKIN, 0.0) * RHO_CORE
    m = m_skin + m_core
    cg = tuple((m_skin * ca[k] + m_core * cv_[k]) / m for k in range(3))
    return m, cg, m_skin, m_core


def _one(shape, what):
    s = shape.solids()
    if len(s) != 1:
        raise RuntimeError(f"{what}: expected one solid, got {len(s)} (volumes {[round(q.volume) for q in s]})")
    return s[0]


def build_rw_support(p, side: int):
    """Rear-wing support F, right (side = +1) or left (-1). See the block comment above."""
    import cfd_variants as cv
    q = cv.variant_params(p, SUPPORT_VARIANT)
    kind_ = cv.VARIANT_DEFS[SUPPORT_VARIANT]["rw_support"]
    _, geo_cfd = cv.wing_stack(q, "rw", "C")
    # the CFD's X range (main-element LE + 60 to X 1895 at most): the CFD rear wing sits 19 mm
    # further back than this one (its flap trailing edges are cut at 0.97 c), so the support
    # keeps the CFD's absolute X, which still lies under this main element
    xa = geo_cfd["rw_main"]["le"][0] + 60.0
    xb = min(xa + p["rw_pylon_chord"], 1895.0)
    yc, t = p["rw_pylon_y"], p["rw_pylon_thickness"]
    solids, geo = build_wing(p, "rw")
    m = geo["rw_main"]
    pts = cv.airfoil_points("rw_main", p["rw_main_chord"], p["rw_main_aoa_C"], *m["le"])
    za, zb_ = cv.mid_z_at(pts, xa), cv.mid_z_at(pts, xb)
    rt = frame_node("RT2_R")
    z_bot = rt[2]                                                     # tube centre line: the support saddles its upper half
    sec = extrude(cv.rws_section(kind_, xa, xb, yc, t, cv.RWS_EDGE_T), amount=2000.0, dir=(0, 0, 1))
    slope = (zb_ - za) / (xb - xa)
    xa_, xb_ = xa - 10.0, xb + 10.0
    v = [Vector(x, 0.0, z) for x, z in [(xa_, z_bot), (xb_, z_bot), (xb_, zb_ + slope * 10.0), (xa_, za - slope * 10.0)]]
    side_face = make_face(Wire([Line(v[i], v[(i + 1) % 4]) for i in range(4)]))
    outline = Pos(0, yc - 40.0, 0) * extrude(side_face, amount=80.0, dir=(0, 1, 0))
    sup = _one(sec & outline, "rear support")
    tube = Solid.make_cylinder(12.7, 2 * abs(rt[1]) + 40.0, Plane(origin=(rt[0], -abs(rt[1]) - 20.0, rt[2]), z_dir=(0, 1, 0)))
    sup = _one(sup - solids["rw_main"] - tube, "rear support cut by the main element and RT2_cross")
    if side < 0:
        sup = sup.mirror(Plane.XZ)
    info = {"x": (xa, xb), "y": side * yc, "z_bot": z_bot, "z_top": (za, zb_), "kind": kind_}
    return sup, info


def build_fw_support(p, side: int):
    """Front-wing support J, right (side = +1) or left (-1). See the block comment above."""
    import cfd_variants as cv
    kind_ = cv.VARIANT_DEFS[SUPPORT_VARIANT]["fw_support"]
    solids, geo = build_wing(p, "fw")
    m = geo["fw_main"]
    c = p["fw_main_chord"]
    xa, xb = m["le"][0] + 0.72 * c, m["le"][0] + 0.93 * c                # as cfd_variants.build_front_wing
    yc, t = (cv.FWP_Y[0] + cv.FWP_Y[1]) / 2, cv.FWP_Y[1] - cv.FWP_Y[0]
    pts = cv.airfoil_points("fw_main", c, p["fw_main_aoa_C"], *m["le"])
    za, zb_ = cv.mid_z_at(pts, xa), cv.mid_z_at(pts, xb)
    sec = extrude(cv.rws_section(kind_, xa, xb, yc, t, cv.RWS_EDGE_T), amount=2000.0, dir=(0, 0, 1))
    slope = (zb_ - za) / (xb - xa)
    xa_, xb_ = xa - 10.0, xb + 10.0
    v = [Vector(x, 0.0, z) for x, z in [(xa_, za - slope * 10.0), (xb_, zb_ + slope * 10.0), (xb_, cv.FWP_Z_TOP), (xa_, cv.FWP_Z_TOP)]]
    side_face = make_face(Wire([Line(v[i], v[(i + 1) % 4]) for i in range(4)]))
    outline = Pos(0, yc - 40.0, 0) * extrude(side_face, amount=80.0, dir=(0, 1, 0))
    sup = _one(sec & outline, "front support")
    secs, _ = nose_sections(p)
    nose_outer = loft([section_rounded(*s) for s in secs], ruled=True)
    sup = _one(sup - solids["fw_main"] - nose_outer, "front support cut by the main element and the nose")
    if side < 0:
        sup = sup.mirror(Plane.XZ)
    info = {"x": (xa, xb), "y": side * yc, "z_bot": (za, zb_), "z_top": cv.FWP_Z_TOP, "kind": kind_}
    return sup, info


# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "cad" / "step"))
    ap.add_argument("--only", default="", help="comma list of part names to build")
    args = ap.parse_args()
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    only = {s.strip() for s in args.only.split(",") if s.strip()}
    p = read_car_params()
    built, skipped = [], []
    densities = {"tyre": 1100e-9, "rim": 2700e-9, "fw": 1600e-9, "rw": 1600e-9, "floor": 400e-9, "nose": 1600e-9, "sidepod": 1600e-9}

    def emit(name: str, part, note: str = ""):
        export_step(part, str(out / f"{name}.step"))
        key = name.split("_")[0]
        mass = part.volume * densities.get(key, 1600e-9)
        built.append((name, bbox_str(part), mass, note))
        print(f"  built   {name:14s} {bbox_str(part)}  ~{mass:5.2f} kg  {note}")

    def attempt(name: str, fn):
        if only and name not in only:
            return
        try:
            fn()
        except Exception as e:  # noqa: BLE001
            skipped.append((name, f"{type(e).__name__}: {e}"))
            print(f"  SKIPPED {name:14s} {type(e).__name__}: {e}")
            traceback.print_exc(limit=2)

    print(f"build_parts: params {PARAMS.relative_to(ROOT)}, output {out}")
    attempt("tyre_front", lambda: emit("tyre_front", build_tyre(p, 0, p["track_front"] / 2)))
    attempt("tyre_rear", lambda: emit("tyre_rear", build_tyre(p, p["wheelbase"], p["track_rear"] / 2)))
    attempt("rim_front", lambda: emit("rim_front", build_rim(p, 0, p["track_front"] / 2)))
    attempt("rim_rear", lambda: emit("rim_rear", build_rim(p, p["wheelbase"], p["track_rear"] / 2)))
    for prefix in ("fw", "rw"):
        def wing(prefix=prefix):
            solids, geo = build_wing(p, prefix)
            for name, s in solids.items():
                emit(name, s, f"LE ({geo[name]['le'][0]:.0f}, {geo[name]['le'][1]:.0f}) TE ({geo[name]['te'][0]:.0f}, {geo[name]['te'][1]:.0f})")
            for side, tag in ((1, "R"), (-1, "L")):
                attempt(f"{prefix}_endplate_{tag}", lambda side=side, tag=tag: emit(f"{prefix}_endplate_{tag}", build_endplate(p, prefix, geo, side)))
        attempt(f"{prefix}_main", wing)
    attempt("floor_diffuser", lambda: emit("floor_diffuser", build_floor(p)))

    def nose():
        s, note = build_nose(p); emit("nose", s, note)
    attempt("nose", nose)
    for side, tag in ((1, "R"), (-1, "L")):
        def pod(side=side, tag=tag):
            s, note, clash = build_sidepod(p, side)
            emit(f"sidepod_{tag}", s, f"{note}; structure box overlap {clash:.0f} mm3 (0 = clears y {side * 540:+.0f}, z 320, X 700..1220)")
        attempt(f"sidepod_{tag}", pod)

    # wing supports: STEP bodies like the rest (BuildAssembly imports and mates them), plus
    # their sandwich mass and centre in cad/generate/supports_mass.csv (the budget lines
    # m_fw_supports / m_rw_supports in params/car_params.txt come from it)
    mass_rows = []
    for wing, fn in (("rw", build_rw_support), ("fw", build_fw_support)):
        for side, tag in ((1, "R"), (-1, "L")):
            def sup(wing=wing, fn=fn, side=side, tag=tag):
                s, info = fn(p, side)
                mkg, cg, ms, mc = support_mass(s)
                bb = s.bounding_box()
                mass_rows.append((f"{wing}_support_{tag}", s.volume, sum(f.area for f in s.faces()), ms, mc, mkg, *cg))
                export_step(s, str(out / f"{wing}_support_{tag}.step"))
                built.append((f"{wing}_support_{tag}", bbox_str(s), mkg, info["kind"]))
                print(f"  built   {wing + '_support_' + tag:14s} {bbox_str(s)}  {mkg:5.3f} kg (CFRP {SUPPORT_SKIN} mm skin + foam core)  "
                      f"section {info['kind']}, X {info['x'][0]:.1f}..{info['x'][1]:.1f}, Y {info['y']:+.0f}, Z {bb.min.Z:.1f}..{bb.max.Z:.1f}")
            attempt(f"{wing}_support_{tag}", sup)
    if mass_rows:
        lines = ["part,volume_mm3,area_mm2,skin_kg,core_kg,mass_kg,x_mm,y_mm,z_mm"]
        lines += [f"{r[0]},{r[1]:.0f},{r[2]:.0f},{r[3]:.4f},{r[4]:.4f},{r[5]:.4f},{r[6]:.1f},{r[7]:.1f},{r[8]:.1f}" for r in mass_rows]
        (ROOT / "cad" / "generate" / "supports_mass.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # packaging envelopes (2026-11-28): space reservations with their budget mass, not designed
    # parts; envelopes.py writes cad/step/env_*.step and cad/generate/envelopes_mass.csv
    def envs():
        import envelopes
        rows = envelopes.write(p, out, ROOT / "cad" / "generate" / "envelopes_mass.csv")
        for r in rows:
            built.append((r[0], "", r[2], "envelope"))
    if not only or "envelopes" in only:
        attempt("envelopes", envs)

    print(f"\n{len(built)} parts built, {len(skipped)} skipped")
    for name, err in skipped:
        print(f"  skipped {name}: {err}")
    return 0 if built else 1


if __name__ == "__main__":
    sys.exit(main())
