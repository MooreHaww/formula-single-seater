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
        Rot, Spline, Vector, Wire, export_step, extrude, loft, make_face, offset, revolve, mirror,
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
        dx = -600.0 - 0.0
        dz = p["fw_ground_clearance"] - infos[0]["z_min"]
    else:
        dx = p["wheelbase"] + p["rear_overhang"] - infos[-1]["x_max"]
        dz = p["rw_height"] - 0.0
    solids = {}
    le = (dx, dz)
    geo = {}
    for name, c, a in zip(names, chords, aoas):
        f, info = airfoil_face(name, c, a, *le)
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
    z0 = p["ride_height_front"]; t = 10.0
    x_le, x_axle = p["floor_start_from_front_axle"], p["wheelbase"]
    hw = p["floor_width"] / 2; hw_step = 470.0; x_step = 1400.0
    plan = [(x_le, -hw), (x_step, -hw), (x_step, -hw_step), (x_axle, -hw_step), (x_axle, hw_step), (x_step, hw_step), (x_step, hw), (x_le, hw)]
    plan_face = (Plane(origin=(0, 0, z0)) * Polygon(*plan, align=None)).faces()[0]
    floor = extrude(plan_face, amount=t)
    # diffuser plate: inclined 10 mm plate from the rear axle, 940 wide
    ang = math.radians(p[f"diffuser_angle_C"]); Ld = p["diffuser_length"]
    rise = Ld * math.tan(ang)
    prof = [(x_axle, 0, z0), (x_axle + Ld, 0, z0 + rise), (x_axle + Ld, 0, z0 + rise + t), (x_axle, 0, z0 + t)]
    pf = make_face(Wire([Line(Vector(*prof[i]), Vector(*prof[(i + 1) % 4])) for i in range(4)]))
    plate = extrude(pf, amount=hw_step, both=True)
    # strakes: between the plate top and a line from z0 + t + 120 at the axle to diffuser_exit_height at the exit
    z_exit = p["diffuser_exit_height"]
    sp = [(x_axle, 0, z0 + t - 1), (x_axle + Ld, 0, z0 + rise + t - 1), (x_axle + Ld, 0, z_exit), (x_axle, 0, z0 + t + 120)]
    sf = make_face(Wire([Line(Vector(*sp[i]), Vector(*sp[(i + 1) % 4])) for i in range(4)]))
    strake = extrude(sf, amount=5, both=True)
    part = floor + plate
    for y in (-350, -150, 150, 350):
        part = part + Pos(0, y, 0) * strake
    return part


def build_nose(p):
    """Ruled loft through the five playbook sections with a 2 mm skin made
    by subtracting an inner loft that pokes through the front-hoop face
    (open at the back). A smooth loft sagged to Z 41 behind the bulkhead
    and offset() with an opening failed on the creased solid."""
    t = 2.0
    secs = [  # x, width, height, corner R, bottom z
        (-p["nose_overhang"], 160, 120, 40, 160),
        (-450, 320, 240, 60, 100),
        (-300, 460, 360, 60, 60),
        (150, 560, 470, 80, 60),
        (p["front_hoop_x"], 640, 540, 90, 60),
    ]
    outer = loft([section_rounded(*s) for s in secs], ruled=True)
    inner_secs = [(x, w - 2 * t, h - 2 * t, r - t, zb + t) for (x, w, h, r, zb) in secs]
    inner_secs[-1] = (inner_secs[-1][0] + 5.0,) + inner_secs[-1][1:]     # 5 mm past the hoop plane: open there
    inner_secs[0] = (inner_secs[0][0] + t,) + inner_secs[0][1:]           # keep a 2 mm wall at the tip
    inner = loft([section_rounded(*s) for s in inner_secs], ruled=True)
    return outer - inner, "2 mm skin (outer loft minus inner loft), open at X 650"


def build_sidepod(p, side: int):
    """Right (side = +1) or left sidepod: a ruled loft whose cavity encloses the
    battery structure box |y| 320..540, z 60..320 from X 700 to 1220, with a
    tapered leading cap ahead of it and a taper to the rear-tyre inner face.
    The 2 mm skin is made by subtracting an inner loft (offset() with an
    opening gave an invalid solid on this shape)."""
    t = 2.0
    y_in, y_out = 320.0, 562.0           # skin inner face at 560: 20 mm outside the structure rails
    z_bot, z_top = 50.0, 342.0           # skin inner faces at 52 and 340

    def sections(dy_in, dy_out, dz_bot, dz_top):
        yi, yo = y_in + dy_in, y_out - dy_out
        zb, zt = z_bot + dz_bot, z_top - dz_top
        yc = side * (yi + yo) / 2; w = yo - yi; h = zt - zb
        return [
            section_ellipse(560, 60 - 2 * dy_out, 180 - 2 * dz_top, side * 440, 200),
            section_rounded(660, w, h, 25 - dy_out, zb, yc),
            section_rounded(1240, w, h, 25 - dy_out, zb, yc),
            section_rounded(1400, 150 - dy_in - dy_out, 180 - dz_bot - dz_top, 30 - dy_out, 70 + dz_bot, side * ((330 + dy_in) + (150 - dy_in - dy_out) / 2)),
        ]
    outer = loft(sections(0, 0, 0, 0), ruled=True)
    inner = loft(sections(-5.0, t, t, t), ruled=True)     # pokes 5 mm through the inboard face: open there
    shell = outer - inner
    note = "2 mm skin (outer loft minus inner loft), open inboard"
    # clearance check: the structure box must lie entirely in the cavity
    box = Pos(960, side * 430, 190) * Box(520, 220, 260)   # X 700..1220, |Y| 320..540, Z 60..320
    clash = (shell & box).volume
    return shell, note, clash


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

    print(f"\n{len(built)} parts built, {len(skipped)} skipped")
    for name, err in skipped:
        print(f"  skipped {name}: {err}")
    return 0 if built else 1


if __name__ == "__main__":
    sys.exit(main())
