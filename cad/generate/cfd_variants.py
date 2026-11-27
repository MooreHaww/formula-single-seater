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
    Box, Compound, Cylinder, GeomType, Line, Pos, Rot, Solid, Sphere, Spline, ThreePointArc, Vector, Vertex, Wire,
    export_step, extrude, fillet, import_step, loft, make_face,
)
from OCP.BRepCheck import BRepCheck_Analyzer  # noqa: E402
from OCP.BRep import BRep_Tool  # noqa: E402

OVER = 20.0          # overshoot across Y = 0 and below Z = 0 so the cuts are clean
PLINTH = 5.0         # height of the vertical step where a tyre meets the ground
ZONES = ["inlet", "outlet", "symmetry", "side", "top", "ground", "wheel_front", "wheel_rear",
         "car_body", "car_floor", "car_fw", "car_rw", "car_rws", "car_fws"]   # car_rws / car_fws: rear / front-wing supports (E-H, J, K, CPFF)
COLOURS = {"inlet": (0.2, 0.6, 1.0), "outlet": (1.0, 0.4, 0.2), "symmetry": (0.8, 0.8, 0.8), "side": (0.7, 0.7, 0.7),
           "top": (0.6, 0.6, 0.6), "ground": (0.4, 0.3, 0.2), "wheel_front": (0.1, 0.1, 0.1), "wheel_rear": (0.25, 0.25, 0.25),
           "car_body": (0.9, 0.1, 0.1), "car_floor": (0.5, 0.5, 0.1), "car_fw": (0.1, 0.7, 0.2), "car_rw": (0.1, 0.3, 0.9),
           "car_rws": (0.6, 0.1, 0.8), "car_fws": (0.1, 0.8, 0.7)}


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


# Derived variants: built from a base variant's parameters with overrides.
#   CP (2026-11-18): C with the SolidWorks bodywork of cad/generate/build_parts.py: nose
#                    sections from the frame, taller and longer sidepods, 10 mm floor plate.
#                    Simplifications against the parts: cfd/geometry_notes.md.
VARIANT_DEFS = {
    "A": {"base": "A"}, "B": {"base": "B"}, "C": {"base": "C"}, "D": {"base": "D"},
    "CP": {"base": "C", "body": "parts"},
    # B_AB, D_AB (2026-11-25): B's and D's aero packages (wing angles, D's endplate fins, beam
    # wing and 14 deg diffuser; B without diffuser, as variant B is defined) on CP's as-built
    # bodywork: the same hull, sidepods, 10 mm floor plate, wheels and corner radii as CP.
    # sym_split_z: the symmetry face is split along Z = this (mm), between the body top (990) and B's rear
    # wing at Y = 0 (1107), topology only (split_symmetry_face_z): B_AB's one-piece symmetry face failed to
    # project edges at the top flap's section. Tried before and did not help: sym_split_x [2600] (split
    # behind the car) and rw_imprint_y 40 (wing faces cut at Y 40; imprint_rw_y).
    "B_AB": {"base": "B", "body": "parts", "sym_split_z": 1050.0},
    # D_AB uses a 12 deg diffuser, NOT D's 14 deg (fallback (b), 2026-11-25): at 14 deg the roof grazes
    # CP's hull bottom (360 self-intersections). Tried and did not mesh: hull_fill_z 150 (hull outline
    # carried down onto the roof, hull_tail_fill), then that plus sym_split_z 1050; both failed to
    # project edges at the beam wing (Y = 0) and the rear wing at the endplate (Y = 625). Wings, beam
    # wing and fins are D's. Meshed with 1 prism layer (--set bl_layers=1) for the cell limit.
    "D_AB": {"base": "D", "body": "parts", "diffuser_angle": 12.0},
    # E-H (2026-11-26): rear-wing support designs, docs/wing_supports_plan.md. CP with its rear pylon (a flat
    # 16 mm plate) replaced by a support in the same envelope (same X range, Y centre, 16 mm maximum
    # thickness and side outline); its own force zone car_rws. Each differs from E by one thing:
    #   E lens (biconvex circular arcs, sharp front and back edges); F E's front edge rounded (RWS_NOSE_R);
    #   G E plus curved ridges on both faces (RWS_RIDGES); H E's rear half flared to a blunt base (RWS_FLARE_T).
    "E": {"base": "C", "body": "parts", "rw_support": "lens"},
    "F": {"base": "C", "body": "parts", "rw_support": "round"},
    "G": {"base": "C", "body": "parts", "rw_support": "ridges"},
    "H": {"base": "C", "body": "parts", "rw_support": "flare"},
    # J, K (2026-11-27): front-wing support designs, docs/wing_supports_plan.md (front-wing round). CP with only its
    # front pylon (a flat 16 mm plate each side, Y 60-76, 72-93 % of the main element's chord, from the element's
    # middle line up to Z 230 in the nose) replaced by a support in the same envelope; own force zone car_fws. The
    # rear keeps CP's flat pylon. J: the rear round's F section (lens, RWS_NOSE_R round front edge); K: E's (lens).
    "J": {"base": "C", "body": "parts", "fw_support": "round"},
    # K mesh try 1 failed at rear flap 2 ("front could not be closed", X 2215 Y 264 Z 1359, the known slot fragility);
    # try 2, symmetry face split at Z 1050 (topology only, as B_AB), failed at rear flap 2 again (X 2216 Y 451 Z 1360);
    # try 3 (the last, 2026-11-27): the simplified section "diamond" (straight sides, same pointed 3 mm front edge,
    # chord and 16 mm mid-chord thickness), without the symmetry split. It failed too ("failed to project front-edges"
    # at the front flap's inner end, X -590 Y 300 Z 151): K NOT RUN (3-attempt rule)
    "K": {"base": "C", "body": "parts", "fw_support": "diamond"},
    # CPFF: the front support of J or K with the lower support drag, plus F's rear supports. K did not mesh in 3
    # tries, so the front support is J's (2026-11-27). Mesh try 1 failed at the front flap's inner end ("failed to
    # project front-edges", X -590 Y 300 Z 151, as K try 3); try 2, symmetry face split at Z 1050 (topology only),
    # meshed: 989,695 cells
    "CPFF": {"base": "C", "body": "parts", "fw_support": "round", "rw_support": "round", "sym_split_z": 1050.0},
}


def kind(variant: str) -> str:
    """The base variant whose features (wings, diffuser, beam wing ...) a variant has."""
    return VARIANT_DEFS[variant]["base"]


def variant_params(p: dict, variant: str) -> dict:
    """Parameter dict for a derived variant: the base's *_<base> keys copied to
    *_<variant>, then the overrides."""
    d = VARIANT_DEFS[variant]
    if d["base"] == variant and len(d) == 1:
        return p
    q = dict(p)
    b = d["base"]
    for k, v in p.items():
        if k.endswith(f"_{b}"):
            q[k[: -len(b)] + variant] = v
    if "diffuser_angle" in d:
        q[f"diffuser_angle_{variant}"] = d["diffuser_angle"]
    q.update(d.get("set", {}))
    return q


VG_T = 10.0          # mm, thickness of the variant-D endplate fins (5 mm fins gave many tiny faces and a fragile surface mesh)
SLOT_EXTRA = 8.0     # mm added to wing_element_gap: the CAD's 14 mm leaves 5 to 8 mm between the surfaces, too thin to mesh inside the cell limit
RWS_EDGE_T = 3.0     # mm: E-H lens edges cut square this thick (knife edges: 31 self-intersections in the surface mesh, 2026-11-26)
RWS_EDGE_DIFF = 0.05 # mm: rear lens edge this much thicker than the front one (keeps the side faces split at mid-chord)
RWS_NOSE_R = 5.0     # mm: F's front-edge radius (E-H rear-wing supports, rws_section)
RWS_FLARE_T = 24.0   # mm: H's base thickness (E-H: 16 mm maximum)
# G's ridges: Z of each ridge's front end, start and end as chord fractions, rise angle at the back (deg;
# horizontal at the front), radial thickness, and the height out of each face at mid-chord (mm)
# first design 3 ridges (Z 650, 830, 1010), 10 mm thick, 8 mm proud: G failed to mesh twice; mesh attempt 3
# (2026-11-26) uses fewer, larger ridges: 2 ridges, 14 mm thick, 10 mm proud
RWS_RIDGES = {"z0": (700.0, 950.0), "u0": 0.20, "u1": 0.85, "angle": 20.0, "thick": 14.0, "height": 10.0}
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


def plate_top(p, x: float) -> float:
    """Top of the 10 mm floor plate of build_parts.build_floor at station x (raked)."""
    x0, xa = p["floor_start_from_front_axle"], p["wheelbase"]
    z0, z1 = p["ride_height_front"], p["ride_height_rear"]
    return z0 + (z1 - z0) * (x - x0) / (xa - x0) + PLATE_T


PLATE_T = 10.0       # mm, floor plate of the SolidWorks parts (variant CP)
CP_R_NOSE_MIN = 40.0 # mm: CP nose corner radius at least this (parts: 10..20 mm); cell budget, see docs/geometry_notes.md
CP_R_POD = 25.0      # mm: CP sidepod corner radius (parts: 6 mm); cell budget
SINK = 4.0           # mm: with the plate floor, hull and sidepod bottoms sit this far INTO the plate (a 1 mm gap as in the parts is unmeshable)


def body_sections_parts(p):
    """Hull sections with the SolidWorks nose (build_parts.build_nose): the two tip
    sections, then sections sized from the frame tubes (+10 mm clearance, 2 mm skin:
    the outer face), up to the front hoop; behind it the CFD cockpit sections.
    Differences to the parts, all so that no thin air gap is left for the mesher:
    the nose is solid (no skin, no 12 link slots, not open at the hoop); from the
    floor's leading edge back, every section's bottom is moved down into the
    floor plate (SINK), i.e. the floor is taken as closed against the chassis, and
    two sections are added (X 310 just behind the floor leading edge, X 1550 at the
    rear axle) so the ruled hull bottom follows the raked plate."""
    import build_parts as bp
    pts = bp.frame_samples()
    x_end = p["front_hoop_x"] - 12.7 - bp.TUBE_CLEAR
    secs = [(-p["nose_overhang"], 160, 80, 30, 200), (-450, 320, 180, 60, 160)]
    st = [-325.0, -230.0, -160.0, -80.0, 0.0, 80.0, 160.0, 280.0, 400.0, 520.0, x_end]
    for i, x in enumerate(st):
        lo = st[max(i - 1, 0)] if i > 0 else -340.0
        hi = st[min(i + 1, len(st) - 1)]
        w, h, R, zb = bp.section_from_frame(pts, lo, hi, 90.0)
        R = min(max(R, CP_R_NOSE_MIN), 0.45 * min(w, h))   # budget: small radii are refined by curvature
        secs.append((x, w, h, R, zb))
    cfd = {s_[0]: s_ for s_ in body_sections(p)}
    secs += [cfd[p["front_hoop_x"]], cfd[p["main_hoop_x"]], cfd[1600], cfd[1900]]
    # section at X 310 (shape of the X 280 one) and at the rear axle (between main hoop and 1600)
    s280 = next(s_ for s_ in secs if s_[0] == 280.0)
    secs.append((310.0,) + s280[1:])
    a, b = cfd[p["main_hoop_x"]], cfd[1600]
    t = (p["wheelbase"] - a[0]) / (b[0] - a[0])
    secs.append(tuple([float(p["wheelbase"])] + [a[k] + t * (b[k] - a[k]) for k in range(1, 5)]))
    secs.sort(key=lambda s_: s_[0])
    out = []
    x_lo, x_hi = p["floor_start_from_front_axle"] + 10.0 - 1e-6, p["wheelbase"] + 1e-6
    for (x, w, h, R, zb) in secs:
        if x_lo <= x <= x_hi:
            znew = plate_top(p, x) - SINK
            h, zb = h + (zb - znew), znew          # keep the top, move the bottom into the plate
        out.append((x, w, h, R, zb))
    return out


def sidepod_parts(p):
    """Outer surface of build_parts.build_sidepod as a solid (the parts' pod is a 2 mm
    shell open inboard and at the bottom; here it is closed, its inboard face moved to
    Y 300 into the hull and its bottom SINK into the floor plate, raked with it)."""
    import build_parts as bp
    t, TC = bp.SKIN, bp.TUBE_CLEAR
    m = TC + t
    y_in = 310.0 + 12.7 + TC
    x_tail = p["main_hoop_x"] + 12.7 + TC + 3.0 + 25.0
    behind = [q for q in bp.frame_samples() if p["main_hoop_x"] + 13.0 < q[0] <= x_tail + 5.0 and 0.0 < q[1] < 360.0]
    if behind:
        y_in = max(y_in, max(y + r for (x, y, z, r) in behind) + TC)
    pts = [q for q in bp.frame_samples() if q[1] >= y_in and 600.0 <= q[0] <= 1300.0]
    y_out = max(562.0, max(y + r for (x, y, z, r) in pts) + m)
    z_top = max(342.0, max(z + r for (x, y, z, r) in pts) + m + 1.0)
    x_full0 = p["front_hoop_x"] - 12.7 - TC - 3.0
    x_full1 = p["main_hoop_x"] + 12.7 + TC + 3.0
    yi = 300.0                                                          # into the hull (parts: open at y_in)
    zb0, zb1, zbt = (plate_top(p, x) - SINK for x in (x_full0, x_full1, x_full1 + 25))
    tail_top = 70.0 + 180.0
    pod = loft([section_ellipse(x_full0 - 100, 60, 180, 440, 200),
                section_rounded(x_full0, y_out - yi, z_top - zb0, CP_R_POD, zb0, (yi + y_out) / 2),
                section_rounded(x_full1, y_out - yi, z_top - zb1, CP_R_POD, zb1, (yi + y_out) / 2),
                section_rounded(x_full1 + 25, 430 - yi, tail_top - zbt, 30, zbt, (yi + 430) / 2)], ruled=True)
    info = {"y_in_parts": round(y_in, 1), "y_in_cfd": yi, "y_out": y_out, "z_top": round(z_top, 1), "x_full": (x_full0, x_full1),
            "tail_x": x_full1 + 25}
    return pod, info


def build_body(p, variant: str = "C"):
    """Chassis envelope, closed cockpit, driver (torso and helmet), roll-hoop
    fairing, sidepod with the battery pack inside. Variant CP: the SolidWorks
    nose and sidepods (body_sections_parts, sidepod_parts)."""
    d = VARIANT_DEFS[variant]
    parts_body = d.get("body") == "parts"
    hull = loft([section_rounded(*s) for s in (body_sections_parts(p) if parts_body else body_sections(p))], ruled=True)
    xd = 1120.0                                             # driver's head, between the hoops
    torso = Pos(xd, 0, 680) * Cylinder(130, 240)            # Z 560 .. 800
    helmet = Pos(xd, 0, 800) * Sphere(140)
    hoop = loft([section_rounded(1200, 240, p["main_hoop_height"] + 10 - 560, 60, 560),
                 section_rounded(1750, 120, 100, 30, 440)], ruled=True)
    # sidepod: solid, 20 mm into the hull so the union is clean; tail ends ahead of the rear tyre
    if parts_body:
        pod, _ = sidepod_parts(p)
    else:
        y_in, y_out, z_bot, z_top = 300.0, 562.0, 50.0, 342.0
        yc, w, h = (y_in + y_out) / 2, y_out - y_in, z_top - z_bot
        pod = loft([section_ellipse(560, 60, 180, 440, 200),
                    section_rounded(660, w, h, 25, z_bot, yc),
                    section_rounded(1240, w, h, 25, z_bot, yc),
                    section_rounded(1295, 120, 180, 30, 70, 370)], ruled=True)
    body = fuse_all({"hull": hull, "torso": torso, "helmet": helmet, "hoop fairing": hoop, "sidepod": pod}, "body")
    return body


def floor_dims(p):
    return {"x0": p["floor_start_from_front_axle"], "xa": p["wheelbase"], "hw": p["floor_width"] / 2,
            "hw_rear": 455.0, "x_step": 1290.0, "z0": p["ride_height_front"], "z1": p["ride_height_rear"], "z_top": 75.0}


def build_floor(p, variant: str):
    """(see below; variant CP: a PLATE_T plate instead of the block up to Z 75)"""
    if VARIANT_DEFS[variant].get("body") == "parts":
        return build_floor_plate(p, variant)
    return build_floor_block(p, variant)


def diffuser_parts(p, variant: str, d: dict, parts: dict):
    ang = math.radians(p[f"diffuser_angle_{variant}"]); Ld = p["diffuser_length"]
    xa, z1, t = d["xa"], d["z1"], 12.0
    xe, ze = xa + Ld, z1 + Ld * math.tan(ang)
    parts["diffuser roof"] = prism_xz([(xa, z1), (xe, ze), (xe, ze + t), (xa, z1 + t)], -OVER, d["hw_rear"])
    # filler on top of the roof start: the roof top (Z 62 at the axle) is below the
    # hull bottom (Z 60-70 rising) for ~40 mm, leaving a sliver gap at Y = 0
    parts["roof filler"] = prism_xz([(xa - 5, z1 + 5), (xa + 70, z1 + 5), (xa + 70, z1 + 30), (xa - 5, z1 + 30)], -OVER, 200.0)
    fin = [(xa, z1), (xe, z1), (xe, ze + 1.0), (xa, z1 + 1.0)]     # 1 mm into the roof
    for k, y in enumerate((150.0, 350.0)):
        parts[f"strake {k + 1}"] = prism_xz(fin, y - 4, y + 4)
    parts["side fence"] = prism_xz(fin, d["hw_rear"] - 8, d["hw_rear"])
    return {"diffuser": True, "angle_deg": p[f"diffuser_angle_{variant}"], "x_exit": xe, "z_exit": ze}


def hull_tail_fill(p, body, variant: str, h: float):
    """D_AB (2026-11-25): the hull outline at height h carried straight down onto the diffuser
    roof, from the rear axle to the body end. With D's 14 deg roof under CP's hull the hull's
    rounded bottom corner grazes the roof top (0.3 mm at Y 200, X 1700) and the surface mesh
    failed with self-intersections; the fill turns that graze into a clean corner. It changes
    only the closed pocket between the roof top and the hull bottom, not the wings or the
    diffuser's underside (angle, strakes, fence)."""
    d = floor_dims(p)
    ang = math.radians(p[f"diffuser_angle_{variant}"]); Ld = p["diffuser_length"]
    xa, z1 = d["xa"], d["z1"]; xe, ze = xa + Ld, z1 + Ld * math.tan(ang)
    slab = body & box_between(xa, xe, -OVER, d["hw_rear"], h - 1.0, h)
    foot = sorted(one_solid(slab, "hull slab").faces(), key=lambda f: f.center().Z)[0]     # bottom face, Z = h - 1
    column = extrude(foot, amount=h, dir=(0, 0, -1))
    above_roof = prism_xz([(xa, z1 + 6.0), (xe, ze + 6.0), (xe, h), (xa, h)], -OVER, d["hw_rear"])   # roof mid-thickness up
    return one_solid(column & above_roof, "hull tail fill")


def build_floor_plate(p, variant: str):
    """Variant CP: the floor of build_parts.build_floor, a PLATE_T thick raked plate
    (wide to X 1290, then stepped in to |y| 455 to the rear axle), plus the diffuser."""
    d = floor_dims(p)
    side = [(d["x0"], d["z0"]), (d["xa"], d["z1"]), (d["xa"], d["z1"] + PLATE_T), (d["x0"], d["z0"] + PLATE_T)]
    wide = prism_xz(side, -OVER, d["hw"]) & box_between(d["x0"] - 1, d["x_step"], -OVER - 1, d["hw"] + 1, 0, 100)
    narrow = prism_xz(side, -OVER, d["hw_rear"])
    parts = {"floor": wide + narrow}
    info = {"diffuser": False, "plate_mm": PLATE_T}
    if kind(variant) in ("C", "D"):
        info.update(diffuser_parts(p, variant, d, parts))
    return fuse_all(parts, "floor"), info


def build_floor_block(p, variant: str):
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
    if kind(variant) in ("C", "D"):
        info = diffuser_parts(p, variant, d, parts)
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


FWP_Y = (60.0, 76.0)    # mm: CP's front pylon, Y extent (16 mm plate, centre 68)
FWP_Z_TOP = 230.0       # mm: top of CP's front pylon (inside the nose from X -650 back; ahead of the nose tip it is exposed)


def build_front_wing(p, variant: str):
    solids, geo = wing_stack(p, "fw", variant)
    ep, epi = endplate(p, "fw", geo)
    # pylon from the nose down into the rear of the main element (bottom edge on the section's middle line)
    m = geo["fw_main"]; pts = m["points"]
    xa = m["le"][0] + 0.72 * m["chord"]; xb = m["le"][0] + 0.93 * m["chord"]
    pyl = prism_xz([(xa, mid_z_at(pts, xa)), (xb, mid_z_at(pts, xb)), (xb, FWP_Z_TOP), (xa, FWP_Z_TOP)], *FWP_Y)
    parts = {"endplate": ep}; parts.update(solids)          # the endplate is what joins the three elements
    if kind(variant) == "D":
        parts.update({f"fw {k}": v for k, v in strakes(p, epi, p["vg_count_fw"]).items()})
    wing = fuse_all(parts, "front wing")
    info = {"geo": geo, "endplate": epi, "pylon_x": (xa, xb), "no_pylon": wing}
    sk = VARIANT_DEFS.get(variant, {}).get("fw_support")
    if sk:                                   # J, K, CPFF: the support replaces the pylon and is returned on its own (zone car_fws)
        info["support"] = build_fw_support(sk, xa, xb, mid_z_at(pts, xa), mid_z_at(pts, xb), RWS_EDGE_T)
        info["support_kind"] = sk
        pyl = None
    return wing, pyl, info


def build_rear_wing(p, variant: str):
    solids, geo = wing_stack(p, "rw", variant)
    ep, epi = endplate(p, "rw", geo)
    m = geo["rw_main"]; pts = m["points"]
    yc, t = p["rw_pylon_y"], p["rw_pylon_thickness"]
    xa = m["le"][0] + 60.0; xb = min(xa + p["rw_pylon_chord"], 1895.0)
    pyl = prism_xz([(xa, 300.0), (xb, 300.0), (xb, mid_z_at(pts, xb)), (xa, mid_z_at(pts, xa))], yc - t / 2, yc + t / 2)
    parts = {"endplate": ep}; parts.update(solids)
    info = {"geo": geo, "endplate": epi, "pylon_x": (xa, xb)}
    info["no_pylon"] = fuse_all(dict(parts), "rear wing without pylon")      # for the wing-to-body clearance check
    sk = VARIANT_DEFS.get(variant, {}).get("rw_support")
    if sk:                                   # E-H: the support replaces the pylon and is returned on its own (zone car_rws)
        info["support"] = build_rw_support(p, sk, xa, xb, mid_z_at(pts, xa), mid_z_at(pts, xb), RWS_EDGE_T)
        info["support_kind"] = sk
    else:
        parts["pylon"] = pyl
    if kind(variant) == "D":
        parts.update({f"rw {k}": v for k, v in strakes(p, epi, p["vg_count_rw"]).items()})
        f, binfo = airfoil_face_cfd("rw_flap1", p["beam_chord"], p["beam_aoa_D"], p["beam_x_le"], p["beam_z_le"])
        binfo.pop("points")
        parts["beam wing"] = Pos(0, -OVER, 0) * extrude(f, amount=p["beam_span"] / 2 + OVER, dir=(0, 1, 0))
        info["beam"] = binfo
    return fuse_all(parts, "rear wing"), info


# ---------------------------------------------------------------------------
# rear-wing supports, variants E-H (docs/wing_supports_plan.md)
def _arc_radius(h, half_len):
    """Radius of the circle with its top (zero slope) at height h, through height 0 half_len away."""
    return (half_len ** 2 + h ** 2) / (2 * h)


def rws_section(kind_: str, xa: float, xb: float, yc: float, t: float, e: float = 0.0):
    """Plan-view section (X-Y plane, Z = 0) of a support from X xa to xb, centred on Y yc,
    t thick at mid-chord. diamond (K's simplified try): straight sides, full thickness at mid-chord.
    lens: two circular arcs, sharp front and back edges. round: the
    rear half as lens; the front edge is a circle of RWS_NOSE_R tangent to a front arc that
    still reaches full thickness with zero slope at mid-chord (chord kept). flare: the front
    half as lens, the rear half curving outwards to a flat base RWS_FLARE_T wide at xb.
    e > 0: the lens edges are cut square, e thick, at xa and xb (the arcs are re-fitted so the
    chord and the mid-chord thickness stay); e = 0: knife edges."""
    c, h, xm = xb - xa, t / 2, (xa + xb) / 2
    V = lambda x, y: Vector(x, y, 0.0)                                    # noqa: E731
    R = _arc_radius(h - e / 2, c / 2)
    yl = lambda x: math.sqrt(max(R * R - (x - xm) ** 2, 0.0)) - (R - h)  # noqa: E731  lens half-thickness (e / 2 at xa, xb)
    # the rear arcs end RWS_EDGE_DIFF thicker than the front ones, so front and rear arcs lie on different
    # circles: on one circle the boolean merged each side into one face from edge to edge, and E's surface
    # mesh failed ("Breakout detected" in the CAD tessellation, 2026-11-26)
    er = e + RWS_EDGE_DIFF if e > 0 and kind_ in ("lens", "ridges") else e      # F, H: arcs already on different circles
    Rr = _arc_radius(h - er / 2, c / 2)
    ylr = lambda x: math.sqrt(max(Rr * Rr - (x - xm) ** 2, 0.0)) - (Rr - h)  # noqa: E731
    q1, q3 = xm + c / 4, xm - c / 4
    rear_up = ThreePointArc(V(xm, yc + h), V(q1, yc + ylr(q1)), V(xb, yc + er / 2))
    rear_lo = ThreePointArc(V(xb, yc - er / 2), V(q1, yc - ylr(q1)), V(xm, yc - h))
    front_up = ThreePointArc(V(xa, yc + e / 2), V(q3, yc + yl(q3)), V(xm, yc + h))
    front_lo = ThreePointArc(V(xm, yc - h), V(q3, yc - yl(q3)), V(xa, yc - e / 2))
    rear = [rear_up] + ([Line(V(xb, yc + er / 2), V(xb, yc - er / 2))] if e > 0 else []) + [rear_lo]
    front_close = [Line(V(xa, yc - e / 2), V(xa, yc + e / 2))] if e > 0 else []
    if kind_ == "diamond":                                                # K's simplified section: straight sides (four planes)
        edges = [Line(V(xa, yc + e / 2), V(xm, yc + h)), Line(V(xm, yc + h), V(xb, yc + e / 2)), Line(V(xb, yc + e / 2), V(xb, yc - e / 2)),
                 Line(V(xb, yc - e / 2), V(xm, yc - h)), Line(V(xm, yc - h), V(xa, yc - e / 2))] + front_close
    elif kind_ in ("lens", "ridges"):
        edges = [front_up] + rear + [front_lo] + front_close
    elif kind_ == "round":
        r = RWS_NOSE_R
        # front arc: radius Rf, top (zero slope) at (xm, h), centre (xm, h - Rf); nose circle: radius r,
        # centre (xa + r, 0), nose at xa. Internal tangency, |centres| = Rf - r, gives
        # Rf = (D^2 + h^2 - r^2) / (2 (h - r)) with D = xm - xa - r (needs r < h)
        D = xm - xa - r
        Rf = (D * D + h * h - r * r) / (2 * (h - r))
        xn = xa + r                                                        # nose circle centre on the axis
        cx, cy = xm, h - Rf                                                # upper front arc centre (y measured from yc)
        dist = math.hypot(xn - cx, cy)
        if abs(dist - (Rf - r)) > 0.05:
            raise RuntimeError(f"round nose: tangency off by {dist - (Rf - r):.3f} mm")
        ux, uy = (xn - cx) / dist, -cy / dist
        tx, ty = xn + r * ux, r * uy                                       # tangent point, upper side
        xmid = (tx + xm) / 2
        ymid = math.sqrt(Rf * Rf - (xmid - cx) ** 2) + cy
        f_up = ThreePointArc(V(tx, yc + ty), V(xmid, yc + ymid), V(xm, yc + h))
        f_lo = ThreePointArc(V(xm, yc - h), V(xmid, yc - ymid), V(tx, yc - ty))
        nose = ThreePointArc(V(tx, yc - ty), V(xa, yc), V(tx, yc + ty))
        edges = [nose, f_up] + rear + [f_lo]
    elif kind_ == "flare":
        hb = RWS_FLARE_T / 2
        Rr = ((c / 2) ** 2 + (hb - h) ** 2) / (2 * (hb - h))                # centre above: y = h + Rr - sqrt(Rr^2 - (x - xm)^2)
        yr = lambda x: h + Rr - math.sqrt(Rr * Rr - (x - xm) ** 2)         # noqa: E731
        f_up = ThreePointArc(V(xm, yc + h), V(q1, yc + yr(q1)), V(xb, yc + hb))
        base = Line(V(xb, yc + hb), V(xb, yc - hb))
        f_lo = ThreePointArc(V(xb, yc - hb), V(q1, yc - yr(q1)), V(xm, yc - h))
        edges = [front_up, f_up, base, f_lo, front_lo] + front_close
    else:
        raise ValueError(kind_)
    return make_face(Wire(edges))


def rws_ridges(xa: float, xb: float, yc: float, t: float, e: float = 0.0):
    """G's ridges: bands along a circular arc in the X-Z plane (horizontal at the front,
    rising RWS_RIDGES['angle'] at the back), through the support, trimmed to a lens of the
    same chord and t + 2 * height thickness: each stands out of both faces by
    height * (lens half-thickness there / at mid-chord)."""
    g = RWS_RIDGES
    c = xb - xa
    x0, x1 = xa + g["u0"] * c, xa + g["u1"] * c
    a = math.radians(g["angle"])
    Rp = (x1 - x0) / math.sin(a)                                          # path radius
    V = lambda x, z: Vector(x, 0.0, z)                                     # noqa: E731
    big = extrude(rws_section("lens", xa, xb, yc, t + 2 * g["height"], e), amount=2000.0, dir=(0, 0, 1))
    out = []
    for z0 in g["z0"]:
        cz = z0 + Rp                                                      # path centre (x0, cz): the path leaves (x0, z0) horizontally
        o, i = [[(x0 + rr * math.sin(a * k / 2), cz - rr * math.cos(a * k / 2)) for k in (0, 1, 2)]
                for rr in (Rp + g["thick"] / 2, Rp - g["thick"] / 2)]
        w = Wire([ThreePointArc(V(*o[0]), V(*o[1]), V(*o[2])), Line(V(*o[2]), V(*i[2])),
                  ThreePointArc(V(*i[2]), V(*i[1]), V(*i[0])), Line(V(*i[0]), V(*o[0]))])
        band = Pos(0, yc - t - 2 * g["height"], 0) * extrude(make_face(w), amount=2 * t + 4 * g["height"], dir=(0, 1, 0))
        out.append(one_solid(band & big, "ridge"))
    return out


def build_rw_support(p, kind_: str, xa: float, xb: float, z_top_a: float, z_top_b: float, e: float = 0.0):
    """One rear-wing support (half model) in CP's pylon envelope: rws_section from X xa to
    xb at Y rw_pylon_y, rw_pylon_thickness thick, extruded in Z and cut to CP's side outline
    (bottom Z 300 inside the hull, top on the main element's middle line)."""
    yc, t = p["rw_pylon_y"], p["rw_pylon_thickness"]
    sec = extrude(rws_section(kind_, xa, xb, yc, t, e), amount=2000.0, dir=(0, 0, 1))
    slope = (z_top_b - z_top_a) / (xb - xa)
    xa_, xb_ = xa - 10.0, xb + 10.0                                       # outline a little longer: no coplanar faces at xa, xb
    side = prism_xz([(xa_, 300.0), (xb_, 300.0), (xb_, z_top_b + slope * 10.0), (xa_, z_top_a - slope * 10.0)],
                    yc - 40.0, yc + 40.0)
    sup = one_solid(sec & side, f"support {kind_}")
    if kind_ == "ridges":
        sup = fuse_all({"support": sup, **{f"ridge {k + 1}": r_ for k, r_ in enumerate(rws_ridges(xa, xb, yc, t, e))}},
                       "support with ridges")
    return sup


def build_fw_support(kind_: str, xa: float, xb: float, z_bot_a: float, z_bot_b: float, e: float = 0.0):
    """One front-wing support (half model) in CP's front-pylon envelope: rws_section (the rear
    round's sections) from X xa to xb, centred on Y 68, 16 mm thick at mid-chord, extruded in Z
    and cut to CP's front-pylon side outline (bottom on the main element's middle line, top Z 230)."""
    yc, t = (FWP_Y[0] + FWP_Y[1]) / 2, FWP_Y[1] - FWP_Y[0]
    sec = extrude(rws_section(kind_, xa, xb, yc, t, e), amount=2000.0, dir=(0, 0, 1))
    slope = (z_bot_b - z_bot_a) / (xb - xa)
    xa_, xb_ = xa - 10.0, xb + 10.0                                       # outline a little longer: no coplanar faces at xa, xb
    side = prism_xz([(xa_, z_bot_a - slope * 10.0), (xb_, z_bot_b + slope * 10.0), (xb_, FWP_Z_TOP), (xa_, FWP_Z_TOP)],
                    yc - 40.0, yc + 40.0)
    return one_solid(sec & side, f"front support {kind_}")


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


def imprint_rw_y(fluid: Solid, y0: float, rw_box) -> Solid:
    """Imprint the section with the plane Y = y0 on every fluid face inside rw_box (the rear
    wing's bounding box) that crosses that plane. Topology only (each face is cut in two, the
    surface is unchanged): it changes how Fluent tessellates the wing faces next to the
    symmetry plane. Used for B_AB, whose surface mesh failed to project edges onto the top
    flap at Y = 0 (2026-11-25)."""
    from OCP.BRepAlgoAPI import BRepAlgoAPI_Section
    from OCP.BRepFeat import BRepFeat_SplitShape
    from OCP.TopAbs import TopAbs_EDGE
    from OCP.TopExp import TopExp_Explorer
    from OCP.TopoDS import TopoDS
    from OCP.gp import gp_Dir, gp_Pln, gp_Pnt
    pln = gp_Pln(gp_Pnt(0, y0, 0), gp_Dir(0, 1, 0))
    sp = BRepFeat_SplitShape(fluid.wrapped)
    n = 0
    for f in fluid.faces():
        b = f.bounding_box()
        if not (b.min.Y < y0 < b.max.Y and b.min.X >= rw_box[0] - 1 and b.max.X <= rw_box[1] + 1 and b.min.Z >= rw_box[2] - 1):
            continue
        sec = BRepAlgoAPI_Section(f.wrapped, pln, True)
        ex = TopExp_Explorer(sec.Shape(), TopAbs_EDGE)
        while ex.More():
            sp.Add(TopoDS.Edge(ex.Current()), f.wrapped); n += 1
            ex.Next()
    sp.Build()
    if not sp.IsDone() or n == 0:
        raise RuntimeError(f"imprint at Y {y0}: failed ({n} edges)")
    return one_solid(Compound(sp.Shape()), "fluid (imprinted)")


def split_symmetry_face_z(fluid: Solid, z: float, dom: dict) -> Solid:
    """Imprint the line Z = z (inlet to outlet) on the symmetry face Y = 0, in a band where no
    car part touches Y = 0 (checked: the line must not cross any hole). Topology only. B_AB
    (2026-11-25): its rear-wing sections at Y = 0 get their own symmetry face, apart from
    CP's hull section, after the one-piece face failed to mesh at the top flap."""
    from OCP.BRepBuilderAPI import BRepBuilderAPI_MakeEdge
    from OCP.BRepFeat import BRepFeat_SplitShape
    from OCP.gp import gp_Pnt
    sym = [f for f in fluid.faces() if abs(f.bounding_box().min.Y) < 1e-6 and abs(f.bounding_box().max.Y) < 1e-6]
    if len(sym) != 1:
        raise RuntimeError(f"symmetry split at Z {z}: {len(sym)} symmetry faces, expected 1")
    for e in sym[0].edges():
        b = e.bounding_box()
        if b.min.Z - 1.0 < z < b.max.Z + 1.0 and b.min.X > dom["xmin"] + 1 and b.max.X < dom["xmax"] - 1:
            raise RuntimeError(f"symmetry split at Z {z} would cross a car edge at X {b.min.X:.0f}..{b.max.X:.0f}")
    e = BRepBuilderAPI_MakeEdge(gp_Pnt(dom["xmin"], 0, z), gp_Pnt(dom["xmax"], 0, z)).Edge()
    sp = BRepFeat_SplitShape(fluid.wrapped); sp.Add(e, sym[0].wrapped); sp.Build()
    if not sp.IsDone():
        raise RuntimeError(f"symmetry split at Z {z} failed")
    return one_solid(Compound(sp.Shape()), "fluid (split at Z)")


def split_symmetry_face(fluid: Solid, xs, dom: dict) -> Solid:
    """Imprint straight lines X = x (ground to top) on the symmetry face Y = 0, where they
    cross no car part. Topology only: the zone is the same plane with the same holes, but
    Fluent tessellates and meshes each piece on its own. Used for B_AB, whose single
    symmetry face failed the surface mesh at the rear-wing section (2026-11-25)."""
    from OCP.BRepBuilderAPI import BRepBuilderAPI_MakeEdge
    from OCP.BRepFeat import BRepFeat_SplitShape
    from OCP.gp import gp_Pnt
    for x in xs:
        sym = [f for f in fluid.faces() if abs(f.bounding_box().min.Y) < 1e-6 and abs(f.bounding_box().max.Y) < 1e-6
               and f.bounding_box().min.X - 1 < x < f.bounding_box().max.X + 1]
        if len(sym) != 1:
            raise RuntimeError(f"symmetry split at X {x}: {len(sym)} faces found, expected 1")
        e = BRepBuilderAPI_MakeEdge(gp_Pnt(x, 0, dom["zmin"]), gp_Pnt(x, 0, dom["zmax"])).Edge()
        sp = BRepFeat_SplitShape(fluid.wrapped)
        sp.Add(e, sym[0].wrapped)
        sp.Build()
        if not sp.IsDone():
            raise RuntimeError(f"symmetry split at X {x} failed")
        fluid = one_solid(Compound(sp.Shape()), "fluid (split)")
    return fluid


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
    p = variant_params(p, variant)
    L = p["wheelbase"]
    body = build_body(p, variant)
    if VARIANT_DEFS[variant].get("hull_fill_z"):
        body = one_solid(body + hull_tail_fill(p, body, variant, VARIANT_DEFS[variant]["hull_fill_z"]), "body + tail fill")
    floor, finfo = build_floor(p, variant)
    comps = {"car_body": body, "car_floor": floor}
    parts = {"body": body, "floor": floor}
    winfo = {}
    if kind(variant) != "A":
        fw, fw_pylon, fwi = build_front_wing(p, variant)
        rw, rwi = build_rear_wing(p, variant)
        # wings (without their pylons) must clear the body and floor: the mesher needs room
        bf = body + floor
        for nm, w in (("front wing", fwi.pop("no_pylon")), ("rear wing", rwi.pop("no_pylon"))):
            gapmm = bf.distance_to(w)
            log(f"  clearance body+floor to {nm} (no pylon): {gapmm:.1f} mm")
            if gapmm < 15.0:
                raise RuntimeError(f"variant {variant}: only {gapmm:.1f} mm between the body and the {nm}")
        if "support" in fwi:                                   # J, K, CPFF: front-wing support, its own zone; joins the nose before the wing
            fsup = fwi.pop("support")
            comps["car_fws"] = fsup; parts["front wing support"] = fsup
        else:
            fw = one_solid(fw + fw_pylon, "front wing + pylon")
        comps.update({"car_fw": fw, "car_rw": rw}); parts["front wing"] = fw
        if "support" in rwi:                                   # E-H: rear-wing support, its own zone; joins the body before the wing
            sup = rwi.pop("support")
            comps["car_rws"] = sup; parts["rear wing support"] = sup
        parts["rear wing"] = rw
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
    if VARIANT_DEFS[variant].get("sym_split_x"):
        fluid = split_symmetry_face(fluid, VARIANT_DEFS[variant]["sym_split_x"], dom)
    if VARIANT_DEFS[variant].get("sym_split_z"):
        fluid = split_symmetry_face_z(fluid, VARIANT_DEFS[variant]["sym_split_z"], dom)
    if VARIANT_DEFS[variant].get("rw_imprint_y") and "car_rw" in comps:
        rb = comps["car_rw"].bounding_box()
        fluid = imprint_rw_y(fluid, VARIANT_DEFS[variant]["rw_imprint_y"], (rb.min.X, rb.max.X, rb.min.Z))

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
    need = [z for z in ZONES if not (kind(variant) == "A" and z in ("car_fw", "car_rw"))
            and not (z == "car_rws" and not VARIANT_DEFS[variant].get("rw_support"))
            and not (z == "car_fws" and not VARIANT_DEFS[variant].get("fw_support"))]
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
    bad = [v for v in only if v not in VARIANT_DEFS]
    if bad:
        sys.exit(f"unknown variant(s) {bad}; known: {list(VARIANT_DEFS)}")
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
    order = [v for v in ("C", "D", "B", "A") if v in only] + [v for v in only if v not in "ABCD"]   # C first: it fixes the domain height
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
        # wake-window boxes (fluent_halfcar.py --boi win): the following car's window region
        # around 1, 2 and 3 car lengths behind the rear axle, 0.7 m deep, Y 0..0.9, Z 0..1.6 m
        win = {}
        for n in (1, 2, 3):
            xc = L + n * p["overall_length"]
            win[f"boi_w{n}"] = (xc - 350.0, xc + 350.0, 0.0, 900.0, 0.0, 1600.0)
        allb = dict(boi); allb.update(win)
        comp = Compound(label="boi_boxes_win", children=[box_between(*b) for b in allb.values()])
        for ch, nm in zip(comp.children, allb):
            ch.label = nm
        export_step(comp, str(out / "boi_boxes_win.step"))
        n_back = len(import_step(str(out / "boi_boxes_win.step")).solids())
        log(f"  {'PASS' if n_back == 5 else 'FAIL'}  boi_boxes_win.step  {n_back} solids")
        ok = ok and n_back == 5
        planes = [0.5, 1.0, 2.0, 3.0]
        meta = {
            "units": "m unless the key says mm", "frame": "X rearward (flow direction) from the front axle, Y right from the centre plane, Z up from the ground",
            "half_model": "Y >= 0, symmetry plane Y = 0; every force from the model is half the car",
            "domain_m": {k: dom[k] / 1000 for k in ("xmin", "xmax", "ymin", "ymax", "zmin", "zmax")},
            "domain_rule": {"car_length_m": dom["car_length"] / 1000, "car_width_m": dom["car_width"] / 1000, "car_height_m": dom["car_height"] / 1000,
                            "ahead_lengths": 3, "behind_lengths": 8, "above_heights": 4, "side_widths": 4},
            "boi_m": {k: [v / 1000 for v in b] for k, b in allb.items()},
            "wheelbase_m": L / 1000,
            "wheels": {"radius_unloaded_m": r / 1000, "radius_loaded_m": p["tyre_rolling_radius"] / 1000, "width_m": p["tyre_width"] / 1000,
                       "front_centre_m": [0.0, p["track_front"] / 2000, p["tyre_rolling_radius"] / 1000],
                       "rear_centre_m": [L / 1000, p["track_rear"] / 2000, p["tyre_rolling_radius"] / 1000],
                       "axis": [0, -1, 0], "omega_rule": "omega = speed / radius_loaded_m about the axis (0, -1, 0) through the wheel centre: the bottom of the tyre then moves in +X with the ground"},
            "wake_planes": {"car_length_m": Lw / 1000, "lengths_behind_rear_axle": planes, "x_m": [round(L / 1000 + n * Lw / 1000, 4) for n in planes],
                            "window_half_width_m": p["wake_window_width"] / 2, "window_height_m": p["wake_window_height"]},
            "zones": ZONES, "reference": {"area_m2": p["frontal_area"], "length_m": L / 1000, "density": p["air_density"], "speed": p["cfd_speed"]},
            "variants": summaries,
            "variant_defs": VARIANT_DEFS,
        }
        old = out / "cfd_geometry.json"
        if old.is_file():                                              # keep the variants not rebuilt this time
            prev = json.loads(old.read_text()).get("variants", {})
            meta["variants"] = {**{k: v for k, v in prev.items() if k not in summaries}, **summaries}
        (out / "cfd_geometry.json").write_text(json.dumps(meta, indent=1))
        log(f"  cfd_geometry.json written (variants {sorted(meta['variants'])})")

    log(f"\n{sum(1 for r_ in all_results if r_['ok'])} of {len(all_results)} checks passed; variants built: {', '.join(summaries) or 'none'}")
    rep_name = "check_report.txt" if set(only) >= set("ABCD") else f"check_report_{'_'.join(only)}.txt"
    (out / rep_name).write_text("\n".join(lines) + "\n")
    return 0 if ok and summaries else 1


if __name__ == "__main__":
    sys.exit(main())
