"""Compare the CFD half-car (cad/step/cfd/halfcar_<V>.step, written by cfd_variants.py)
with the bodywork parts (cad/step/*.step, written by build_parts.py), part by part.

Read-only on cad/step/cfd/. Writes docs/cfd_parts_mismatch.csv and prints a table.
Run:  .venv\\Scripts\\python.exe cad\\generate\\compare_cfd_parts.py [variant, default C]

The CFD car is one closed solid (body, floor and wings merged) while most parts are 2 mm
shells, so volumes cannot be compared. Surfaces can: both are tessellated finely (0.5 mm
chord) and, for each part (right half, Y >= 0, like the CFD model):
  part -> CFD   distance from each point of the part's surface to the nearest point of the
                CFD surface: median, 95th percentile, max, the share farther than 5 mm, and
                where the max is (that part of the part has no CFD surface near it).
  CFD -> part   the same from the CFD surface points inside the part's bounding box (grown
                by 30 mm) to the part: CFD surface there that the part does not have.
A shell part has two skins 2 mm apart and the CFD body only one, so 2 mm is "the same".
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree
from build123d import import_step

ROOT = Path(__file__).resolve().parents[2]
GROW = 30.0
TOL = 0.5
PARTS = ["nose", "sidepod_R", "floor_diffuser", "fw_main", "fw_flap1", "fw_flap2", "fw_endplate_R",
         "rw_main", "rw_flap1", "rw_flap2", "rw_endplate_R"]
GROUP = {"nose": "nose", "sidepod_R": "sidepods", "floor_diffuser": "floor"}


def surface_points(shape, step=4.0) -> np.ndarray:
    """Points on every face: tessellation vertices plus points spread over each triangle
    so that no point is more than about `step` mm from the next."""
    pts = []
    for f in shape.faces():
        verts, tris = f.tessellate(TOL, 0.2)
        v = np.array([[p.X, p.Y, p.Z] for p in verts])
        if len(v) == 0:
            continue
        pts.append(v)
        for a, b, c in tris:
            A, B, C = v[a], v[b], v[c]
            n = int(max(np.linalg.norm(B - A), np.linalg.norm(C - A), np.linalg.norm(C - B)) / step)
            if n < 1:
                continue
            for i in range(n + 1):
                for j in range(n + 1 - i):
                    u, w = i / n, j / n
                    pts.append((A + u * (B - A) + w * (C - A))[None, :])
    return np.vstack(pts)


def stats(d: np.ndarray, p: np.ndarray):
    k = int(np.argmax(d))
    return (float(np.median(d)), float(np.percentile(d, 95)), float(d[k]), float((d > 5.0).mean() * 100), p[k])


def main(variant: str = "C") -> int:
    cfd = import_step(str(ROOT / "cad" / "step" / "cfd" / f"halfcar_{variant}.step"))
    b = cfd.bounding_box()
    scale = 1000.0 if (b.max.X - b.min.X) < 20 else 1.0
    car = max(cfd.solids(), key=lambda s: s.volume)               # the car; the other solids are the wheels
    cp = surface_points(car) * scale
    tree_cfd = cKDTree(cp)
    print(f"CFD variant {variant}: car solid {len(car.faces())} faces, {len(cp)} surface points (scale {scale:g})")
    rows = []
    allp = {}
    for name in PARTS:
        pp = surface_points(import_step(str(ROOT / "cad" / "step" / f"{name}.step")))
        allp[name] = pp[pp[:, 1] >= 0.0]
    tree_parts = cKDTree(np.vstack(list(allp.values())))     # CFD -> parts: against every part, not only this one
    for name in PARTS:
        pp = allp[name]
        d_pc, _ = tree_cfd.query(pp)
        lo, hi = pp.min(axis=0) - GROW, pp.max(axis=0) + GROW
        sel = np.all((cp >= lo) & (cp <= hi), axis=1)
        cw = cp[sel]
        d_cp, _ = tree_parts.query(cw) if len(cw) else (np.zeros(1), None)
        a = stats(d_pc, pp)
        c = stats(d_cp, cw) if len(cw) else (0, 0, 0, 0, np.zeros(3))
        group = GROUP.get(name, "front wing" if name.startswith("fw") else "rear wing")
        rows.append({
            "group": group, "part": name, "cfd_variant": variant,
            "part_bbox_mm": "X %.0f..%.0f Y %.0f..%.0f Z %.0f..%.0f" % (pp[:, 0].min(), pp[:, 0].max(), pp[:, 1].min(), pp[:, 1].max(), pp[:, 2].min(), pp[:, 2].max()),
            "part_to_cfd_median_mm": round(a[0], 1), "part_to_cfd_p95_mm": round(a[1], 1), "part_to_cfd_max_mm": round(a[2], 1),
            "part_share_off_by_5mm_pct": round(a[3], 0), "part_worst_at_mm": "(%.0f, %.0f, %.0f)" % tuple(a[4]),
            "cfd_to_part_median_mm": round(c[0], 1), "cfd_to_part_p95_mm": round(c[1], 1), "cfd_to_part_max_mm": round(c[2], 1),
            "cfd_share_off_by_5mm_pct": round(c[3], 0), "cfd_worst_at_mm": "(%.0f, %.0f, %.0f)" % tuple(c[4]),
        })
        r = rows[-1]
        print(f"{name:15s} part->CFD med {a[0]:6.1f} p95 {a[1]:6.1f} max {a[2]:6.1f} mm, {a[3]:3.0f} % > 5 mm, worst at {r['part_worst_at_mm']:20s} | "
              f"CFD->part med {c[0]:6.1f} p95 {c[1]:6.1f} max {c[2]:6.1f} mm, {c[3]:3.0f} % > 5 mm, worst at {r['cfd_worst_at_mm']}")
    out = ROOT / "docs" / "cfd_parts_mismatch.csv"
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {out}")
    # sections: at each x station, the outline of the CFD body and of the body parts (right
    # half), from the surface points within 3 mm of the station, in the body band (Y <= 570,
    # Z <= 1000; the wings and endplates are left out, they are compared part by part above)
    allpts = np.vstack([allp[n] for n in ("nose", "sidepod_R", "floor_diffuser")])
    cpb = cp[(cp[:, 1] <= 570.0) & (cp[:, 2] <= 1000.0)]
    srows = []
    for x in range(-300, 1401, 50):
        c = cpb[np.abs(cpb[:, 0] - x) < 3.0]
        q = allpts[np.abs(allpts[:, 0] - x) < 3.0]
        def ext(a):
            if len(a) == 0:
                return [float("nan")] * 4
            return [a[:, 1].max(), a[:, 2].min(), a[:, 2].max(), float(len(a))]
        ec, eq = ext(c), ext(q)
        srows.append({"x_mm": x, "cfd_y_max": round(ec[0], 0), "parts_y_max": round(eq[0], 0),
                      "cfd_z_min": round(ec[1], 0), "parts_z_min": round(eq[1], 0),
                      "cfd_z_max": round(ec[2], 0), "parts_z_max": round(eq[2], 0)})
    out2 = ROOT / "docs" / "cfd_parts_sections.csv"
    with open(out2, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(srows[0].keys()))
        w.writeheader()
        w.writerows(srows)
    print(f"wrote {out2}")
    for r in srows:
        print("  x %5d  y_max cfd %5s parts %5s   z %5s..%5s cfd, %5s..%5s parts" % (r["x_mm"], r["cfd_y_max"], r["parts_y_max"], r["cfd_z_min"], r["cfd_z_max"], r["parts_z_min"], r["parts_z_max"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "C"))
