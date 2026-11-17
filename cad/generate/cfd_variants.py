#!/usr/bin/env python3
"""Half-car CFD geometry for the aero variants A, B, C, D, built with build123d.

Run (project venv, see cfd/requirements.txt):
    .venv/Scripts/python cad/generate/cfd_variants.py [--only A,C] [--out cad/step/cfd]

Writes to cad/step/cfd/ (all in car coordinates, mm, Y >= 0 half, see
cfd/geometry_notes.md):
    halfcar_<V>.step   three labelled solids: car (body, floor, wings: stationary
                       walls), wheel_front, wheel_rear (rotating walls)
    fluid_<V>.step     ONE solid: the air (domain box minus the half car and the
                       wheels). This is what Fluent Meshing imports. Every face
                       carries its zone name (inlet, outlet, symmetry, side, top,
                       ground, wheel_front, wheel_rear, car_body, car_floor,
                       car_fw, car_rw) as a STEP face name and a colour.
    faces_<V>.csv      one row per face of the fluid solid: zone, area, centre,
                       bounding box. The Fluent driver uses it to name zones if
                       the STEP names do not survive the import.
    domain.step        the plain domain box
    boi_near.step, boi_wake.step, boi_boxes.step   refinement boxes (bodies of influence), singly and both in one file
    cfd_geometry.json  the numbers the Fluent scripts need (domain, wheel
                       centres and radius, wake planes, areas, zone names)
    check_report.txt   the checks below, per body

Checks on every body (the script exits 1 if any fails): exactly one solid, one
closed shell (no inner voids), BRepCheck valid (no faulty faces), every edge
shared by exactly two faces, expected bounding box, and the same again after
reading the STEP file back.

Geometry is SIMPLIFIED on purpose (no suspension links, no cockpit opening,
closed wheels, solid wings). Decisions that differ from cad/generate/build_parts.py
are listed in cfd/geometry_notes.md; the main one: the front wing is moved
forward to fw_le_x because at X -600 its flaps run through the front tyres.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_parts import ROOT, read_airfoil, read_car_params, section_ellipse, section_rounded  # noqa: E402

from build123d import (  # noqa: E402
    Box, Compound, Cylinder, GeomType, Line, Pos, Rot, Solid, Sphere, Spline, Vector, Vertex, Wire,
    export_step, extrude, fillet, import_step, loft, make_face,
)
from OCP.BRepCheck import BRepCheck_Analyzer  # noqa: E402
from OCP.BRep import BRep_Tool  # noqa: E402

OVER = 20.0          # overshoot across Y = 0 and below Z = 0 so the cuts are clean
PLINTH = 5.0         # height of the vertical step where a tyre meets the ground
ZONES = ["inlet", "outlet", "symmetry", "side", "top", "ground", "wheel_front", "wheel_rear",
         "car_body", "car_floor", "car_fw", "car_rw"]
COLOURS = {"inlet": (0.2, 0.6, 1.0), "outlet": (1.0, 0.4, 0.2), "symmetry": (0.8, 0.8, 0.8), "side": (0.7, 0.7, 0.7),
           "top": (0.6, 0.6, 0.6), "ground": (0.4, 0.3, 0.2), "wheel_front": (0.1, 0.1, 0.1), "wheel_rear": (0.25, 0.25, 0.25),
           "car_body": (0.9, 0.1, 0.1), "car_floor": (0.5, 0.5, 0.1), "car_fw": (0.1, 0.7, 0.2), "car_rw": (0.1, 0.3, 0.9)}


# ---------------------------------------------------------------------------
# small geometry helpers
# ---------------------------------------------------------------------------
def prism_xz(pts, y0: float, y1: float):
    """Polygon given in the X-Z plane, extruded from Y = y0 to Y = y1."""
    v = [Vector(x, 0.0, z) for (x, z) in pts]
    face = make_face(Wire([Line(v[i], v[(i + 1) % len(v)]) for i in range(len(v))]))
    return Pos(0, y0, 0) * extrude(face, amount=y1 - y0, dir=(0, 1, 0))


def box_between(x0, x1, y0, y1, z0, z1):
    return Pos((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2) * Box(x1 - x0, y1 - y0, z1 - z0)


def airfoil_points(name: str, chord: float, aoa_deg: float, le_x: float, le_z: float):
    """The same transform as build_parts.airfoil_face, as (x, z) points."""
    a = math.radians(aoa_deg)
    ca, sa = math.cos(a), math.sin(a)
    out = []
    for xc, yc in read_airfoil(name):
        x, z = xc * chord, -yc * chord
        out.append((le_x + x * ca - z * sa, le_z + x * sa + z * ca))
    return out


VG_T = 10.0          # mm, thickness of the variant-D endplate fins (5 mm fins gave many tiny faces and a fragile surface mesh)
SLOT_EXTRA = 8.0     # mm added to wing_element_gap: the CAD's 14 mm leaves 5 to 8 mm between the surfaces, too thin to mesh inside the cell limit
TE_CUT = 0.97        # wing sections are cut at this chord fraction at most: a blunt trailing edge instead of a knife edge
TE_MIN_MM = 0.0      # (0 = off) ... or further forward, where the section is this thick: thinner edges (1.1 to 1.8 mm at 0.97 c on the flaps)
                     # are below the 2.5 mm minimum mesh size. Tried at 3.0 on 2026-11-17: the surface mesh of D then failed in
                     # three places instead of one, so it is off; the thin edges are left to the mesher


def airfoil_face_cfd(name: str, chord: float, aoa_deg: float, le_x: float, le_z: float):
    """Wing section for CFD: the airfoil of cad/airfoils cut at TE_CUT of the
    chord (or further forward, to a TE_MIN_MM thick edge), as ONE open spline from the upper trailing edge round the nose to
    the lower trailing edge plus a straight closing line. build_parts.airfoil_face
    closes a single spline through the sharp trailing edge, which Fluent's
    surface mesher fails on ("duplicate front edge" at the cusp).
    Returns the face and the same info dict as build_parts.airfoil_face (with
    the cut section's own trailing edge and extent)."""
    raw = read_airfoil(name)
    i_le = min(range(len(raw)), key=lambda i: raw[i][0])
    upper, lower = raw[: i_le + 1], raw[i_le:]              # TE -> LE and LE -> TE

    def y_at(side, x):
        for (x0, y0), (x1, y1) in zip(side, side[1:]):
            if min(x0, x1) <= x <= max(x0, x1) and x0 != x1:
                return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        raise ValueError(x)
    xcut = TE_CUT
    while xcut > 0.8 and abs(y_at(upper, xcut) - y_at(lower, xcut)) * chord < TE_MIN_MM:
        xcut -= 0.0025

    def cut(side, rising):
        out = []
        seq = side if rising else side[::-1]                # work LE -> TE
        for (x0, y0), (x1, y1) in zip(seq, seq[1:]):
            if x0 <= xcut:
                out.append((x0, y0))
            if x0 < xcut <= x1:
                t = (xcut - x0) / (x1 - x0)
                out.append((xcut, y0 + t * (y1 - y0)))
                break
        return out if rising else out[::-1]
    up, lo = cut(upper, False), cut(lower, True)            # TE -> LE, LE -> TE
    pts = up + lo[1:]
    a = math.radians(aoa_deg); ca, sa = math.cos(a), math.sin(a)
    xz = []
    for xc, yc in pts:
        x, z = xc * chord, -yc * chord                      # camber down
        xz.append((le_x + x * ca - z * sa, le_z + x * sa + z * ca))
    vecs = [Vector(x, 0.0, z) for x, z in xz]
    face = make_face(Wire([Spline(*vecs), Line(vecs[-1], vecs[0])]))
    te = ((xz[0][0] + xz[-1][0]) / 2, (xz[0][1] + xz[-1][1]) / 2)
    info = {"le": (le_x, le_z), "te": te, "z_min": min(q[1] for q in xz), "x_max": max(q[0] for q in xz),
            "te_thickness": math.dist(xz[0], xz[-1]), "points": xz}
    return face, info


def mid_z_at(points, x: float) -> float:
    """Height of the middle of an airfoil section at station x (mean of the
    upper and lower surface crossings of the closed polyline)."""
    zs = []
    n = len(points)
    for i in range(n):
        (x0, z0), (x1, z1) = points[i], points[(i + 1) % n]
        if (x0 - x) * (x1 - x) <= 0 and x0 != x1:
            zs.append(z0 + (z1 - z0) * (x - x0) / (x1 - x0))
    if len(zs) < 2:
        raise ValueError(f"station x = {x:.1f} is outside the section")
    return (min(zs) + max(zs)) / 2


def one_solid(shape, what: str) -> Solid:
    s = shape.solids()
    if len(s) != 1:
        raise RuntimeError(f"{what}: expected one solid, got {len(s)} (volumes {[round(q.volume) for q in s]})")
    return s[0]


def fuse_all(parts: dict, what: str) -> Solid:
    """Union in the given order; every part must touch what is already there."""
    names = list(parts)
    acc = parts[names[0]]
    for n in names[1:]:
        acc = acc + parts[n]
        k = len(acc.solids())
        if k != 1:
            raise RuntimeError(f"{what}: after adding '{n}' the result has {k} solids; '{n}' does not overlap the rest")
    return one_solid(acc, what)


# ---------------------------------------------------------------------------
# parts of the half car (each built for Y >= -OVER; cut at Y = 0 at the end)
# ---------------------------------------------------------------------------
def body_sections(p):
    """x, width, height, corner radius, bottom z. The first five follow the nose
    of build_parts.py (underside of the first two raised, see the comments);
    then the cockpit to the main hoop and the motor cover."""
    return [
        (-p["nose_overhang"], 160, 80, 30, 200),      # nose tip raised (playbook: 120 high from Z 160) to clear the front wing's main element by 50 mm
        (-450, 320, 180, 60, 160),                    # playbook: 240 high from Z 100; the top line is unchanged
        (-300, 460, 360, 60, 60),
        (150, 560, 470, 80, 60),
        (p["front_hoop_x"], 640, 540, 90, 60),
        (p["main_hoop_x"], 640, 560, 90, 60),
        (1600, 520, 480, 80, 70),
        (1900, 360, 295, 60, 125),
    ]


def build_body(p):
    """Chassis envelope, closed cockpit, driver (torso and helmet), roll-hoop
    fairing, sidepod with the battery pack inside."""
    hull = loft([section_rounded(*s) for s in body_sections(p)], ruled=True)
    xd = 1120.0                                             # driver's head, between the hoops
    torso = Pos(xd, 0, 680) * Cylinder(130, 240)            # Z 560 .. 800
    helmet = Pos(xd, 0, 800) * Sphere(140)
    hoop = loft([section_rounded(1200, 240, p["main_hoop_height"] + 10 - 560, 60, 560),
                 section_rounded(1750, 120, 100, 30, 440)], ruled=True)
    # sidepod: solid, 20 mm into the hull so the union is clean; tail ends ahead of the rear tyre
    y_in, y_out, z_bot, z_top = 300.0, 562.0, 50.0, 342.0
    yc, w, h = (y_in + y_out) / 2, y_out - y_in, z_top - z_bot
    pod = loft([section_ellipse(560, 60, 180, 440, 200),
                section_rounded(660, w, h, 25, z_bot, yc),
                section_rounded(1240, w, h, 25, z_bot, yc),
                section_rounded(1295, 120, 180, 30, 70, 370)], ruled=True)
    return fuse_all({"hull": hull, "torso": torso, "helmet": helmet, "hoop fairing": hoop, "sidepod": pod}, "body")


def floor_dims(p):
    return {"x0": p["floor_start_from_front_axle"], "xa": p["wheelbase"], "hw": p["floor_width"] / 2,
            "hw_rear": 455.0, "x_step": 1290.0, "z0": p["ride_height_front"], "z1": p["ride_height_rear"], "z_top": 75.0}


def build_floor(p, variant: str):
    """Raked floor (underside ride_height_front at the leading edge to
    ride_height_rear at the rear axle, top flat at Z 75 so it overlaps the hull bottom (60-70)
    and the sidepod without slivers). C and D add the diffuser roof (12 mm
    plate), two strakes and a side fence under it."""
    d = floor_dims(p)
    side = [(d["x0"], d["z0"]), (d["xa"], d["z1"]), (d["xa"], d["z_top"]), (d["x0"], d["z_top"])]
    wide = prism_xz(side, -OVER, d["hw"]) & box_between(d["x0"] - 1, d["x_step"], -OVER - 1, d["hw"] + 1, 0, 100)
    narrow = prism_xz(side, -OVER, d["hw_rear"])
    parts = {"floor": wide + narrow}
    info = {"diffuser": False}
    if variant in ("C", "D"):
        ang = math.radians(p[f"diffuser_angle_{variant}"]); Ld = p["diffuser_length"]
        xa, z1, t = d["xa"], d["z1"], 12.0
        xe, ze = xa + Ld, z1 + Ld * math.tan(ang)
        roof = prism_xz([(xa, z1), (xe, ze), (xe, ze + t), (xa, z1 + t)], -OVER, d["hw_rear"])
        parts["diffuser roof"] = roof
        # filler on top of the roof start: the roof top (Z 62 at the axle) is below the
        # hull bottom (Z 60-70 rising) for ~40 mm, leaving a sliver gap at Y = 0
        parts["roof filler"] = prism_xz([(xa - 5, z1 + 5), (xa + 70, z1 + 5), (xa + 70, z1 + 30), (xa - 5, z1 + 30)], -OVER, 200.0)
        fin = [(xa, z1), (xe, z1), (xe, ze + 1.0), (xa, z1 + 1.0)]     # 1 mm into the roof
        for k, y in enumerate((150.0, 350.0)):
            parts[f"strake {k + 1}"] = prism_xz(fin, y - 4, y + 4)
        parts["side fence"] = prism_xz(fin, d["hw_rear"] - 8, d["hw_rear"])
        info = {"diffuser": True, "angle_deg": p[f"diffuser_angle_{variant}"], "x_exit": xe, "z_exit": ze}
    return fuse_all(parts, "floor"), info


def wing_stack(p, prefix: str, variant: str):
    """Element solids of one wing (half span, Y -OVER .. span/2 + 2) and the
    section geometry. Same chain as build_parts.build_wing; the front wing's
    leading edge is at fw_le_x instead of -600."""
    gap, overlap = p["wing_element_gap"] + SLOT_EXTRA, p["wing_element_overlap"]
    half = p[f"{prefix}_span"] / 2
    # front flaps start outboard of the nose (fw_flap_inner_y); the main element runs through under it
    y_start = {n_: -OVER for n_ in (f"{prefix}_main", f"{prefix}_flap1", f"{prefix}_flap2")}
    if prefix == "fw":
        y_start["fw_flap1"] = y_start["fw_flap2"] = p["fw_flap_inner_y"]
    names = [f"{prefix}_main", f"{prefix}_flap1", f"{prefix}_flap2"]
    chords = [p[f"{prefix}_main_chord"], p[f"{prefix}_flap1_chord"], p[f"{prefix}_flap2_chord"]]
    aoas = [p[f"{prefix}_main_aoa_{variant}"], p[f"{prefix}_flap1_aoa_{variant}"], p[f"{prefix}_flap2_aoa_{variant}"]]
    infos, le = [], (0.0, 0.0)
    for n, c, a in zip(names, chords, aoas):
        _, info = airfoil_face_cfd(n, c, a, *le)
        infos.append(info); le = (info["te"][0] - overlap, info["te"][1] + gap)
    if prefix == "fw":
        dx, dz = p["fw_le_x"], p["fw_ground_clearance"] - infos[0]["z_min"]
    else:
        dx, dz = p["wheelbase"] + p["rear_overhang"] - infos[-1]["x_max"], p["rw_height"]
    solids, geo, le = {}, {}, (dx, dz)
    for n, c, a in zip(names, chords, aoas):
        f, info = airfoil_face_cfd(n, c, a, *le)
        solids[n] = Pos(0, y_start[n], 0) * extrude(f, amount=half + 2 - y_start[n], dir=(0, 1, 0))
        info["chord"] = c; info["aoa"] = a
        geo[n] = info
        le = (info["te"][0] - overlap, info["te"][1] + gap)
    return solids, geo


def endplate(p, prefix: str, geo: dict):
    """6 mm plate on the wing tip, outline as build_parts.build_endplate."""
    t = 6.0
    if prefix == "fw":
        L, H = p["fw_endplate_length"], p["fw_endplate_height"]
        x0, z0 = geo["fw_main"]["le"][0] - 100, 30.0
    else:
        L, H = p["rw_endplate_length"], p["rw_endplate_height"]
        x0 = p["wheelbase"] + p["rear_overhang"] - L + 20.0     # 20 mm past the flap trailing edge: a TE lying exactly in the plate's rear face leaves a degenerate edge
        z0 = max(geo["rw_flap2"]["te"][1] + 40, p["rw_height"] + 320) - H
    r, c = 150.0, 100.0
    pts = [(x0, z0), (x0 + L - c, z0), (x0 + L, z0 + c), (x0 + L, z0 + H), (x0 + r, z0 + H)]
    pts += [(x0 + r - r * math.sin(math.radians(a)), z0 + H - r + r * math.cos(math.radians(a))) for a in range(10, 91, 10)]
    y_in = p[f"{prefix}_span"] / 2
    return prism_xz(pts, y_in, y_in + t), {"x0": x0, "z0": z0, "L": L, "H": H, "y_in": y_in, "t": t}


def strakes(p, ep: dict, count: int):
    """Variant D: inclined fins on the outer face of an endplate (vortex
    generators). vg_length x VG_T (10 mm), standing vg_height out of the plate,
    leading edge down by vg_angle."""
    out = {}
    L, hgt, ang = p["vg_length"], p["vg_height"], p["vg_angle"]
    y0 = ep["y_in"] + ep["t"] - 2.0
    xc = ep["x0"] + 0.55 * ep["L"]
    for k in range(int(count)):
        zc = ep["z0"] + ep["H"] * (k + 1) / (count + 1)
        fin = Pos(0, y0 + (hgt + 2) / 2, 0) * Box(L, hgt + 2, VG_T)
        out[f"strake {k + 1}"] = Pos(xc, 0, zc) * (Rot(0, ang, 0) * fin)   # +ang about Y: leading (low X) edge goes down
    return out


def build_front_wing(p, variant: str):
    solids, geo = wing_stack(p, "fw", variant)
    ep, epi = endplate(p, "fw", geo)
    # pylon from the nose down into the rear of the main element (bottom edge on the section's middle line)
    m = geo["fw_main"]; pts = m["points"]
    xa = m["le"][0] + 0.72 * m["chord"]; xb = m["le"][0] + 0.93 * m["chord"]
    pyl = prism_xz([(xa, mid_z_at(pts, xa)), (xb, mid_z_at(pts, xb)), (xb, 230.0), (xa, 230.0)], 60.0, 76.0)
    parts = {"endplate": ep}; parts.update(solids)          # the endplate is what joins the three elements
    if variant == "D":
        parts.update({f"fw {k}": v for k, v in strakes(p, epi, p["vg_count_fw"]).items()})
    wing = fuse_all(parts, "front wing")
    return wing, pyl, {"geo": geo, "endplate": epi, "pylon_x": (xa, xb)}


def build_rear_wing(p, variant: str):
    solids, geo = wing_stack(p, "rw", variant)
    ep, epi = endplate(p, "rw", geo)
    m = geo["rw_main"]; pts = m["points"]
    yc, t = p["rw_pylon_y"], p["rw_pylon_thickness"]
    xa = m["le"][0] + 60.0; xb = min(xa + p["rw_pylon_chord"], 1895.0)
    pyl = prism_xz([(xa, 300.0), (xb, 300.0), (xb, mid_z_at(pts, xb)), (xa, mid_z_at(pts, xa))], yc - t / 2, yc + t / 2)
    parts = {"endplate": ep}; parts.update(solids); parts["pylon"] = pyl
    info = {"geo": geo, "endplate": epi, "pylon_x": (xa, xb)}
    if variant == "D":
        parts.update({f"rw {k}": v for k, v in strakes(p, epi, p["vg_count_rw"]).items()})
        f, binfo = airfoil_face_cfd("rw_flap1", p["beam_chord"], p["beam_aoa_D"], p["beam_x_le"], p["beam_z_le"])
        binfo.pop("points")
        parts["beam wing"] = Pos(0, -OVER, 0) * extrude(f, amount=p["beam_span"] / 2 + OVER, dir=(0, 1, 0))
        info["beam"] = binfo
    return fuse_all(parts, "rear wing"), info


def build_wheel(p, x_axle: float, half_track: float):
    """Closed wheel: a disc of the tyre's outer diameter and width with 25 mm
    shoulders, sitting at the loaded radius so it sinks (OD/2 - loaded radius)
    into the ground, plus a plinth: the section at Z = PLINTH carried straight
    down, so the tyre meets the ground in a 5 mm vertical step instead of a
    knife-edge wedge that cannot be meshed. Extends to Z = -OVER."""
    r, w, rl = p["tyre_od"] / 2, p["tyre_width"], p["tyre_rolling_radius"]
    disc = Rot(90, 0, 0) * Cylinder(r, w)
    disc = fillet(disc.edges().filter_by(GeomType.CIRCLE), radius=25.0)
    tyre = Pos(x_axle, half_track, rl) * disc
    foot = tyre & box_between(x_axle - r, x_axle + r, half_track - w, half_track + w, -OVER - 10, PLINTH)
    top = sorted(foot.faces(), key=lambda f: f.center().Z)[-1]            # the cut face at Z = PLINTH
    plinth = extrude(top, amount=PLINTH + OVER, dir=(0, 0, -1))
    wheel = one_solid(tyre + plinth, "wheel")
    bb = top.bounding_box()
    patch = {"length": bb.max.X - bb.min.X, "width": bb.max.Y - bb.min.Y, "area_mm2": top.area}
    return wheel, patch


def above_ground(shape):
    return shape & box_between(-1e5, 1e5, -1e5, 1e5, 0.0, 1e5)


def right_half(shape):
    return shape & box_between(-1e5, 1e5, 0.0, 1e5, -1e5, 1e5)


# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------
def check_solid(shape, name: str, expect_bbox=None, tol=1.0) -> dict:
    """One solid, one closed shell, BRepCheck valid, every edge on exactly two faces."""
    res = {"name": name, "ok": True, "problems": []}
    solids = shape.solids()
    res["solids"] = len(solids)
    if len(solids) != 1:
        res["ok"] = False; res["problems"].append(f"{len(solids)} solids")
        return res
    s = solids[0]
    shells = s.shells()
    res["shells"] = len(shells); res["faces"] = len(s.faces()); res["volume_m3"] = s.volume * 1e-9
    if len(shells) != 1:
        res["ok"] = False; res["problems"].append(f"{len(shells)} shells (inner void)")
    ana = BRepCheck_Analyzer(s.wrapped)
    res["valid"] = bool(ana.IsValid())
    if not res["valid"]:
        bad = sum(1 for f in s.faces() if not BRepCheck_Analyzer(f.wrapped).IsValid())
        res["ok"] = False; res["problems"].append(f"BRepCheck invalid ({bad} faulty faces)")
    # every edge must belong to exactly two faces; a seam edge of a closed
    # surface (cylinder, sphere) belongs to one face twice; degenerated edges
    # (sphere poles) do not count
    count, seam = {}, set()
    for f in s.faces():
        for e in f.edges():
            if BRep_Tool.Degenerated_s(e.wrapped):
                continue
            count[e] = count.get(e, 0) + 1
            if BRep_Tool.IsClosed_s(e.wrapped, f.wrapped):
                seam.add(e)
    odd = sum(1 for e, n in count.items() if n != 2 and not (e in seam and n == 1))
    res["open_or_nonmanifold_edges"] = odd
    if odd:
        res["ok"] = False; res["problems"].append(f"{odd} edges not shared by exactly two faces")
    bb = s.bounding_box()
    res["bbox"] = [round(v, 2) for v in (bb.min.X, bb.max.X, bb.min.Y, bb.max.Y, bb.min.Z, bb.max.Z)]
    if expect_bbox is not None:
        for got, want, lab in zip(res["bbox"], expect_bbox, ("Xmin", "Xmax", "Ymin", "Ymax", "Zmin", "Zmax")):
            if want is not None and abs(got - want) > tol:
                res["ok"] = False; res["problems"].append(f"{lab} {got} expected {want}")
    return res


def frontal_area(solids, pixel=2.0) -> float:
    """Projected area on the Y-Z plane in m2, by rasterising the tessellation."""
    import numpy as np
    tris = []
    for s in solids:
        verts, faces = s.tessellate(0.5, 0.3)
        v = np.array([(q.Y, q.Z) for q in verts]); f = np.array(faces)
        if len(f):
            tris.append(v[f])
    t = np.concatenate(tris)
    lo = t.reshape(-1, 2).min(axis=0); hi = t.reshape(-1, 2).max(axis=0)
    ny, nz = int((hi[0] - lo[0]) / pixel) + 2, int((hi[1] - lo[1]) / pixel) + 2
    img = np.zeros((ny, nz), dtype=bool)
    for a, b, c in t:
        mn = np.floor((np.minimum(np.minimum(a, b), c) - lo) / pixel).astype(int)
        mx = np.ceil((np.maximum(np.maximum(a, b), c) - lo) / pixel).astype(int) + 1
        if mx[0] <= mn[0] or mx[1] <= mn[1]:
            continue
        ys = lo[0] + (np.arange(mn[0], mx[0]) + 0.5) * pixel; zs = lo[1] + (np.arange(mn[1], mx[1]) + 0.5) * pixel
        Y, Z = np.meshgrid(ys, zs, indexing="ij")
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l1 = ((b[1] - c[1]) * (Y - c[0]) + (c[0] - b[0]) * (Z - c[1])) / d
        l2 = ((c[1] - a[1]) * (Y - c[0]) + (a[0] - c[0]) * (Z - c[1])) / d
        inside = (l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)
        img[mn[0]:mx[0], mn[1]:mx[1]] |= inside[: img[mn[0]:mx[0], mn[1]:mx[1]].shape[0], : img[mn[0]:mx[0], mn[1]:mx[1]].shape[1]]
    return float(img.sum()) * pixel * pixel * 1e-6


# ---------------------------------------------------------------------------
# fluid solid, face zones, STEP with face names
# ---------------------------------------------------------------------------
def domain_bounds(p, car_x, car_w, car_h):
    """Ahead 3 car lengths, behind 8, above 4 car heights, side 4 car widths."""
    L = car_x[1] - car_x[0]
    return {"xmin": round(car_x[0] - 3 * L, -1), "xmax": round(car_x[1] + 8 * L, -1), "ymin": 0.0,
            "ymax": round(4 * car_w, -1), "zmin": 0.0, "zmax": round(4 * car_h, -1), "car_length": L, "car_width": car_w, "car_height": car_h}


def classify_faces(fluid: Solid, dom: dict, comps: dict, wheel_boxes: dict):
    """Zone name for every face of the fluid solid."""
    rows = []
    eps = 0.05
    for i, f in enumerate(fluid.faces()):
        bb = f.bounding_box()
        b = (bb.min.X, bb.max.X, bb.min.Y, bb.max.Y, bb.min.Z, bb.max.Z)
        zone = None
        flat = lambda lo, hi, v: abs(lo - v) < eps and abs(hi - v) < eps  # noqa: E731
        if flat(b[0], b[1], dom["xmin"]): zone = "inlet"
        elif flat(b[0], b[1], dom["xmax"]): zone = "outlet"
        elif flat(b[2], b[3], dom["ymax"]): zone = "side"
        elif flat(b[4], b[5], dom["zmax"]): zone = "top"
        elif flat(b[2], b[3], 0.0): zone = "symmetry"
        elif flat(b[4], b[5], 0.0): zone = "ground"
        if zone is None:
            for wn, wb in wheel_boxes.items():
                if all(b[2 * k] >= wb[2 * k] - 1 and b[2 * k + 1] <= wb[2 * k + 1] + 1 for k in range(3)):
                    zone = wn
        if zone is None:
            # the component whose surface carries every edge midpoint of this face
            pts = [e @ 0.5 for e in f.edges()]
            best, best_d = None, 1e9
            for cn, cs in comps.items():
                d = max(Vertex(q.X, q.Y, q.Z).distance_to(cs) for q in pts)
                if d < best_d:
                    best, best_d = cn, d
            zone = best
            if best_d > 0.5:
                raise RuntimeError(f"face {i}: no component within 0.5 mm (nearest {best} at {best_d:.2f} mm)")
        c = f.center()
        rows.append({"face": i, "zone": zone, "area_m2": f.area * 1e-6, "cx_m": c.X / 1000, "cy_m": c.Y / 1000, "cz_m": c.Z / 1000,
                     "xmin_m": b[0] / 1000, "xmax_m": b[1] / 1000, "ymin_m": b[2] / 1000, "ymax_m": b[3] / 1000, "zmin_m": b[4] / 1000, "zmax_m": b[5] / 1000})
    return rows


def export_named_step(solid: Solid, rows, path: Path, label: str):
    """STEP (AP214) of one solid with a name and a colour on every face."""
    from OCP.IFSelect import IFSelect_RetDone
    from OCP.Interface import Interface_Static
    from OCP.Quantity import Quantity_Color, Quantity_TOC_RGB
    from OCP.STEPCAFControl import STEPCAFControl_Writer
    from OCP.STEPControl import STEPControl_AsIs
    from OCP.TCollection import TCollection_ExtendedString
    from OCP.TDataStd import TDataStd_Name
    from OCP.TDocStd import TDocStd_Document
    from OCP.XCAFApp import XCAFApp_Application
    from OCP.XCAFDoc import XCAFDoc_ColorSurf, XCAFDoc_DocumentTool

    doc = TDocStd_Document(TCollection_ExtendedString("XmlOcaf"))
    XCAFApp_Application.GetApplication_s().InitDocument(doc)
    st = XCAFDoc_DocumentTool.ShapeTool_s(doc.Main())
    ct = XCAFDoc_DocumentTool.ColorTool_s(doc.Main())
    # deep copy: faces that share one underlying shape (the two flat sides of a
    # wheel disc) would otherwise get a single label and one of them no name
    from OCP.BRepBuilderAPI import BRepBuilderAPI_Copy
    orig = solid
    solid = Solid(BRepBuilderAPI_Copy(orig.wrapped, True).Shape())
    for fa, fb in zip(orig.faces(), solid.faces()):
        if abs(fa.area - fb.area) > 1e-6 * max(fa.area, 1.0) or (fa.center() - fb.center()).length > 1e-6:
            raise RuntimeError("face order changed in the copy; names would land on the wrong faces")
    lab = st.AddShape(solid.wrapped, False)
    TDataStd_Name.Set_s(lab, TCollection_ExtendedString(label))
    for f, r in zip(solid.faces(), rows):
        sub = st.AddSubShape(lab, f.wrapped)
        TDataStd_Name.Set_s(sub, TCollection_ExtendedString(r["zone"]))
        ct.SetColor(sub, Quantity_Color(*COLOURS[r["zone"]], Quantity_TOC_RGB), XCAFDoc_ColorSurf)
    w = STEPCAFControl_Writer()                      # creating the writer first initialises the STEP parameters set below
    Interface_Static.SetIVal_s("write.stepcaf.subshapes.name", 1)
    Interface_Static.SetCVal_s("write.step.schema", "AP214IS")
    Interface_Static.SetCVal_s("write.step.unit", "MM")
    w.SetNameMode(True); w.SetColorMode(True)
    if not w.Transfer(doc, STEPControl_AsIs):
        raise RuntimeError("STEP transfer failed")
    if w.Write(str(path)) != IFSelect_RetDone:
        raise RuntimeError(f"STEP write failed: {path}")
    # The writer leaves the odd face unnamed (seen on one flat side of each
    # wheel disc). The faces are written in the order of solid.faces(): check
    # that against every name that did get written, then fill in the blanks.
    import re
    txt = path.read_text()
    pat = re.compile(r"ADVANCED_FACE\('([^']*)'")
    found = pat.findall(txt)
    if len(found) != len(rows):
        raise RuntimeError(f"{path.name}: {len(found)} faces in the STEP text, {len(rows)} expected")
    for i, (nm, r) in enumerate(zip(found, rows)):
        if nm and nm != r["zone"]:
            raise RuntimeError(f"{path.name}: face {i} is named {nm} in the STEP text but should be {r['zone']}; face order is not the expected one")
    it = iter(rows)
    txt = pat.sub(lambda m: "ADVANCED_FACE('" + next(it)["zone"] + "'", txt)
    path.write_text(txt)
    return sum(1 for nm in found if not nm)


# ---------------------------------------------------------------------------
def build_variant(p, variant: str, out: Path, log, dom_fixed=None):
    t0 = time.time()
    L = p["wheelbase"]
    body = build_body(p)
    floor, finfo = build_floor(p, variant)
    comps = {"car_body": body, "car_floor": floor}
    parts = {"body": body, "floor": floor}
    winfo = {}
    if variant != "A":
        fw, fw_pylon, fwi = build_front_wing(p, variant)
        rw, rwi = build_rear_wing(p, variant)
        fw = one_solid(fw + fw_pylon, "front wing + pylon")
        comps.update({"car_fw": fw, "car_rw": rw}); parts.update({"front wing": fw, "rear wing": rw})
        winfo = {"fw": fwi, "rw": rwi}
    car_over = fuse_all(parts, f"car {variant}")
    wf_over, patch_f = build_wheel(p, 0.0, p["track_front"] / 2)
    wr_over, patch_r = build_wheel(p, L, p["track_rear"] / 2)
    for nm, w in (("front", wf_over), ("rear", wr_over)):
        common = car_over & w
        clash = 0.0 if common is None else sum(q.volume for q in common.solids())
        if clash > 1e-3:
            raise RuntimeError(f"variant {variant}: the car overlaps the {nm} wheel by {clash:.0f} mm3")
        gapmm = car_over.distance_to(w)
        log(f"  clearance car to {nm} wheel: {gapmm:.1f} mm")
        if gapmm < 15.0:
            raise RuntimeError(f"variant {variant}: only {gapmm:.1f} mm between the car and the {nm} wheel (needs 15 for the mesh)")
    car = one_solid(right_half(above_ground(car_over)), "half car")
    wf = one_solid(above_ground(wf_over), "front wheel"); wr = one_solid(above_ground(wr_over), "rear wheel")

    bb = car.bounding_box()
    r, wt = p["tyre_od"] / 2, p["tyre_width"]
    x_lo, x_hi = min(bb.min.X, -r), max(bb.max.X, L + r)
    w_car = 2 * max(bb.max.Y, p["track_front"] / 2 + wt / 2); h_car = bb.max.Z
    dom = dom_fixed or domain_bounds(p, (x_lo, x_hi), w_car, h_car)
    box = box_between(dom["xmin"], dom["xmax"], 0.0, dom["ymax"], 0.0, dom["zmax"])
    fluid = one_solid(box - car_over - wf_over - wr_over, f"fluid {variant}")

    wheel_boxes = {}
    for nm, w in (("wheel_front", wf), ("wheel_rear", wr)):
        b = w.bounding_box(); wheel_boxes[nm] = (b.min.X, b.max.X, b.min.Y, b.max.Y, b.min.Z, b.max.Z)
    rows = classify_faces(fluid, dom, comps, wheel_boxes)

    # wetted areas: the car and wheel faces of the fluid solid must add up to the
    # bodies' own surfaces without their cut faces (Y = 0 for the car, Z = 0 for
    # the wheels). Volumes are not compared: the box is 1.6e12 mm3 and the
    # integration error on it is larger than the car's small features.
    def wet(body, axis):
        tot = 0.0
        for f in body.faces():
            bbf = f.bounding_box()
            lo, hi = (bbf.min.Y, bbf.max.Y) if axis == "y" else (bbf.min.Z, bbf.max.Z)
            if not (abs(lo) < 1e-3 and abs(hi) < 1e-3):
                tot += f.area
        return tot
    wet_expect = {"car": wet(car, "y"), "wheel_front": wet(wf, "z"), "wheel_rear": wet(wr, "z")}
    wet_got = {"car": sum(r_["area_m2"] for r_ in rows if r_["zone"].startswith("car")) * 1e6,
               "wheel_front": sum(r_["area_m2"] for r_ in rows if r_["zone"] == "wheel_front") * 1e6,
               "wheel_rear": sum(r_["area_m2"] for r_ in rows if r_["zone"] == "wheel_rear") * 1e6}

    # ---- checks -----------------------------------------------------------
    results = []
    exp_car = (None, None, 0.0, None, None, None)
    results.append(check_solid(car, f"halfcar_{variant}: car", exp_car))
    results.append(check_solid(wf, f"halfcar_{variant}: wheel_front", (-r, r, p["track_front"] / 2 - wt / 2, p["track_front"] / 2 + wt / 2, 0.0, p["tyre_rolling_radius"] + r)))
    results.append(check_solid(wr, f"halfcar_{variant}: wheel_rear", (L - r, L + r, p["track_rear"] / 2 - wt / 2, p["track_rear"] / 2 + wt / 2, 0.0, p["tyre_rolling_radius"] + r)))
    results.append(check_solid(fluid, f"fluid_{variant}", (dom["xmin"], dom["xmax"], 0.0, dom["ymax"], 0.0, dom["zmax"])))
    for k in wet_expect:
        if abs(wet_got[k] - wet_expect[k]) > 1e-5 * wet_expect[k] + 1.0:
            results[-1]["ok"] = False; results[-1]["problems"].append(f"wetted area of {k}: {wet_got[k]:.0f} mm2 in the fluid, {wet_expect[k]:.0f} on the body")
    results[-1]["wetted_check_mm2"] = {k: (round(wet_got[k]), round(wet_expect[k])) for k in wet_expect}
    zones = sorted({r_["zone"] for r_ in rows})
    need = [z for z in ZONES if not (variant == "A" and z in ("car_fw", "car_rw"))]
    if sorted(need) != zones:
        results[-1]["ok"] = False; results[-1]["problems"].append(f"zones {zones}, expected {sorted(need)}")

    # ---- export, then read back and check again ---------------------------
    car.label, wf.label, wr.label = "car", "wheel_front", "wheel_rear"
    asm = Compound(label=f"halfcar_{variant}", children=[car, wf, wr])
    f_car = out / f"halfcar_{variant}.step"; f_fluid = out / f"fluid_{variant}.step"
    export_step(asm, str(f_car))
    n_filled = export_named_step(fluid, rows, f_fluid, "fluid")
    log(f"  fluid_{variant}.step: {len(rows)} faces named ({n_filled} filled in after writing)")
    back = import_step(str(f_car)).solids()
    if len(back) != 3:
        results.append({"name": f"halfcar_{variant}.step read back", "ok": False, "problems": [f"{len(back)} solids, expected 3"]})
    else:
        for s_, ref, nm in zip(sorted(back, key=lambda q: -q.volume), sorted([car, wf, wr], key=lambda q: -q.volume), ("car", "wheel", "wheel")):
            rr = check_solid(s_, f"halfcar_{variant}.step read back: {nm}")
            if abs(s_.volume - ref.volume) > 1e-6 * ref.volume + 1.0:
                rr["ok"] = False; rr["problems"].append(f"volume changed by {s_.volume - ref.volume:.1f} mm3")
            results.append(rr)
    fb = import_step(str(f_fluid))
    rr = check_solid(fb, f"fluid_{variant}.step read back", (dom["xmin"], dom["xmax"], 0.0, dom["ymax"], 0.0, dom["zmax"]))
    if rr.get("solids") == 1 and abs(fb.solids()[0].volume - fluid.volume) > 5e-6 * fluid.volume:
        rr["ok"] = False; rr["problems"].append("volume changed on read back")
    if rr.get("faces") != len(rows):
        rr["ok"] = False; rr["problems"].append(f"{rr.get('faces')} faces after read back, {len(rows)} written")
    txt = f_fluid.read_text(errors="replace")
    named = {z: txt.count(f"ADVANCED_FACE('{z}'") for z in zones}
    rr["face_names_in_step"] = named
    if sum(named.values()) != len(rows):
        rr["ok"] = False; rr["problems"].append(f"{sum(named.values())} named faces in the STEP text, {len(rows)} faces")
    results.append(rr)

    with open(out / f"faces_{variant}.csv", "w", newline="") as fh:
        wtr = csv.DictWriter(fh, fieldnames=list(rows[0]))
        wtr.writeheader()
        for r_ in rows:
            wtr.writerow({k: (f"{v:.6f}" if isinstance(v, float) else v) for k, v in r_.items()})

    # ---- numbers ---------------------------------------------------------
    area = {z: sum(r_["area_m2"] for r_ in rows if r_["zone"] == z) for z in zones}
    a_car = frontal_area([car]); a_all = frontal_area([car, wf, wr]); a_wheels = frontal_area([wf, wr])
    summary = {
        "variant": variant, "seconds": round(time.time() - t0, 1),
        "car_bbox_mm": results[0]["bbox"], "car_volume_m3": round(car.volume * 1e-9, 4),
        "frontal_area_half_m2": {"car": round(a_car, 4), "wheels": round(a_wheels, 4), "all": round(a_all, 4)},
        "frontal_area_full_m2": round(2 * a_all, 4),
        "wetted_area_half_m2": {z: round(a, 4) for z, a in area.items() if z.startswith(("car", "wheel"))},
        "faces": {z: sum(1 for r_ in rows if r_["zone"] == z) for z in zones}, "n_faces": len(rows),
        "contact_patch_mm": {"front": {k: round(v, 1) for k, v in patch_f.items()}, "rear": {k: round(v, 1) for k, v in patch_r.items()}},
        "floor": finfo, "domain_mm": dom,
    }
    if winfo:
        summary["front_wing"] = {"le_x": winfo["fw"]["geo"]["fw_main"]["le"][0], "le_z": round(winfo["fw"]["geo"]["fw_main"]["le"][1], 1),
                                 "te_x": round(winfo["fw"]["geo"]["fw_flap2"]["x_max"], 1), "te_z": round(winfo["fw"]["geo"]["fw_flap2"]["te"][1], 1),
                                 "z_min": round(winfo["fw"]["geo"]["fw_main"]["z_min"], 1)}
        summary["rear_wing"] = {"le_x": round(winfo["rw"]["geo"]["rw_main"]["le"][0], 1), "le_z": winfo["rw"]["geo"]["rw_main"]["le"][1],
                                "te_x": round(winfo["rw"]["geo"]["rw_flap2"]["x_max"], 1), "te_z": round(winfo["rw"]["geo"]["rw_flap2"]["te"][1], 1),
                                "endplate_top_z": round(winfo["rw"]["endplate"]["z0"] + winfo["rw"]["endplate"]["H"], 1)}
    return results, summary, dom


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "cad" / "step" / "cfd"))
    ap.add_argument("--only", default="", help="comma list of variants, e.g. A,C")
    args = ap.parse_args()
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    only = [s.strip().upper() for s in args.only.split(",") if s.strip()] or ["A", "B", "C", "D"]
    p = read_car_params()
    lines = []

    def log(s=""):
        print(s, flush=True); lines.append(s)

    log(f"cfd_variants: params {Path('params/car_params.txt')}, output {out}")
    # one domain for every variant, sized on the largest car (C: wings, longest and tallest)
    r, L = p["tyre_od"] / 2, p["wheelbase"]
    car_x = (p["fw_le_x"] - 100.0, L + p["rear_overhang"] + 20.0)   # front endplate nose to the back of the rear endplate
    car_w = p["fw_span"] + 12.0                                      # outside of the front endplates
    car_h = 1549.0 if "rw_height" not in p else None
    all_results, summaries, ok = [], {}, True
    dom = None
    order = [v for v in ("C", "D", "B", "A") if v in only]           # C first: it fixes the domain height
    for v in order:
        log(f"\nvariant {v}")
        try:
            if dom is None and v != "C":
                # domain must not depend on which variants are built: size it from C's rear endplate top
                _, geo = wing_stack(p, "rw", "C")
                top = max(geo["rw_flap2"]["te"][1] + 40, p["rw_height"] + 320)
                dom = domain_bounds(p, car_x, car_w, top)
            elif dom is None:
                _, geo = wing_stack(p, "rw", "C")
                top = max(geo["rw_flap2"]["te"][1] + 40, p["rw_height"] + 320)
                dom = domain_bounds(p, car_x, car_w, top)
            results, summary, _ = build_variant(p, v, out, log, dom)
        except Exception as e:  # noqa: BLE001
            import traceback
            log(f"  FAILED to build variant {v}: {type(e).__name__}: {e}")
            traceback.print_exc()
            ok = False
            continue
        summaries[v] = summary
        for r_ in results:
            all_results.append(r_)
            ok = ok and r_["ok"]
            extra = "" if r_["ok"] else "  <-- " + "; ".join(r_["problems"])
            log(f"  {'PASS' if r_['ok'] else 'FAIL'}  {r_['name']:38s} solids {r_.get('solids', '?')} shells {r_.get('shells', '?')} faces {r_.get('faces', '?'):>4} "
                f"valid {r_.get('valid', '?')} bad edges {r_.get('open_or_nonmanifold_edges', '?')} bbox {r_.get('bbox', '')}{extra}")
        s = summary
        log(f"  frontal area, half: car {s['frontal_area_half_m2']['car']:.3f} m2, with wheels {s['frontal_area_half_m2']['all']:.3f} m2 -> full car {s['frontal_area_full_m2']:.3f} m2")
        log(f"  fluid faces by zone: {s['faces']}")
        log(f"  contact patch front {s['contact_patch_mm']['front']}, rear {s['contact_patch_mm']['rear']}")
        log(f"  built in {s['seconds']} s")

    # ---- domain box and refinement boxes --------------------------------------
    if dom is not None:
        box = box_between(dom["xmin"], dom["xmax"], 0.0, dom["ymax"], 0.0, dom["zmax"])
        box.label = "domain"
        export_step(box, str(out / "domain.step"))
        r_ = check_solid(import_step(str(out / "domain.step")), "domain.step read back", (dom["xmin"], dom["xmax"], 0.0, dom["ymax"], 0.0, dom["zmax"]))
        all_results.append(r_); ok = ok and r_["ok"]
        log(f"\n  {'PASS' if r_['ok'] else 'FAIL'}  domain.step  bbox {r_.get('bbox')}  {'; '.join(r_['problems'])}")
        Lw = p["overall_length"]
        boi = {"boi_near": (car_x[0] - 300.0, L + p["rear_overhang"] + 900.0, 0.0, 1100.0, 0.0, 1800.0),
               "boi_wake": (L + p["rear_overhang"] + 900.0, L + 3 * Lw + 300.0, 0.0, 1400.0, 0.0, 2200.0)}
        for nm, b in boi.items():
            s_ = box_between(*b); s_.label = nm
            export_step(s_, str(out / f"{nm}.step"))
            r_ = check_solid(import_step(str(out / f"{nm}.step")), f"{nm}.step read back", b)
            all_results.append(r_); ok = ok and r_["ok"]
            log(f"  {'PASS' if r_['ok'] else 'FAIL'}  {nm}.step  bbox {r_.get('bbox')}  {'; '.join(r_['problems'])}")
        both = Compound(label="boi_boxes", children=[box_between(*b) for b in boi.values()])
        for ch, nm in zip(both.children, boi):
            ch.label = nm
        export_step(both, str(out / "boi_boxes.step"))                 # both boxes in one file: the Fluent driver imports this one
        n_back = len(import_step(str(out / "boi_boxes.step")).solids())
        log(f"  {'PASS' if n_back == 2 else 'FAIL'}  boi_boxes.step  {n_back} solids")
        ok = ok and n_back == 2
        planes = [0.5, 1.0, 2.0, 3.0]
        meta = {
            "units": "m unless the key says mm", "frame": "X rearward (flow direction) from the front axle, Y right from the centre plane, Z up from the ground",
            "half_model": "Y >= 0, symmetry plane Y = 0; every force from the model is half the car",
            "domain_m": {k: dom[k] / 1000 for k in ("xmin", "xmax", "ymin", "ymax", "zmin", "zmax")},
            "domain_rule": {"car_length_m": dom["car_length"] / 1000, "car_width_m": dom["car_width"] / 1000, "car_height_m": dom["car_height"] / 1000,
                            "ahead_lengths": 3, "behind_lengths": 8, "above_heights": 4, "side_widths": 4},
            "boi_m": {k: [v / 1000 for v in b] for k, b in boi.items()},
            "wheelbase_m": L / 1000,
            "wheels": {"radius_unloaded_m": r / 1000, "radius_loaded_m": p["tyre_rolling_radius"] / 1000, "width_m": p["tyre_width"] / 1000,
                       "front_centre_m": [0.0, p["track_front"] / 2000, p["tyre_rolling_radius"] / 1000],
                       "rear_centre_m": [L / 1000, p["track_rear"] / 2000, p["tyre_rolling_radius"] / 1000],
                       "axis": [0, -1, 0], "omega_rule": "omega = speed / radius_loaded_m about the axis (0, -1, 0) through the wheel centre: the bottom of the tyre then moves in +X with the ground"},
            "wake_planes": {"car_length_m": Lw / 1000, "lengths_behind_rear_axle": planes, "x_m": [round(L / 1000 + n * Lw / 1000, 4) for n in planes],
                            "window_half_width_m": p["wake_window_width"] / 2, "window_height_m": p["wake_window_height"]},
            "zones": ZONES, "reference": {"area_m2": p["frontal_area"], "length_m": L / 1000, "density": p["air_density"], "speed": p["cfd_speed"]},
            "variants": summaries,
        }
        (out / "cfd_geometry.json").write_text(json.dumps(meta, indent=1))
        log("  cfd_geometry.json written")

    log(f"\n{sum(1 for r_ in all_results if r_['ok'])} of {len(all_results)} checks passed; variants built: {', '.join(summaries) or 'none'}")
    (out / "check_report.txt").write_text("\n".join(lines) + "\n")
    return 0 if ok and summaries else 1


if __name__ == "__main__":
    sys.exit(main())
