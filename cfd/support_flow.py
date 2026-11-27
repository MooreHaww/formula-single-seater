#!/usr/bin/env python3
"""Picture and numbers of the air next to the rear-wing supports (docs/wing_supports_plan.md).

    .venv/Scripts/python cfd/support_flow.py CP E G H F        # runs to compare, the first is the reference
    .venv/Scripts/python cfd/support_flow.py --front CP_bl1 J_bl1 K_bl1 CPFF_bl1   # front-wing support
    .venv/Scripts/python cfd/support_flow.py --selftest

Reads the saved Fluent case + data with VTK (cfd/visualise.py read_case, no licence) and
samples two planes near the support (2 mm grid):
  - plan  : Z = 760 mm (mid-height of the exposed support), X 1600..2150, Y 80..230 mm,
            coloured by speed / U;
  - side  : Y = 172 mm, 14 mm outboard of the support's face (6 mm off G's ridge tips),
            X 1600..2300, Z 450..1250 mm, coloured by upwash w / U.
Numbers (cfd/results/support_flow.csv), from the side plane and a box behind the support:
  - upwash_side   : mean w/U on the side plane over the support's chord and exposed height
                    (X 1667..1895, Z 600..1100): how much the faces turn the air up;
  - upwash_behind : mean w/U in the box X 1900..2000, Y 120..180, Z 600..1100 (behind it);
  - deficit_behind: mean 1 - u/U in the same box (the support's own wake).
The picture is media/cfd/supports/support_flow.png. Steady RANS: only the ranking of the
variants is trustworthy.

--front (front-wing round, 2026-11-27): the same for the front-wing support (X -672..-588,
Y 60..76, exposed between the wing's upper surface, Z 121-132, and the nose, Z 188-215; its
front 22 mm is ahead of the nose tip, up to Z 230):
  - plan  : Z = 165 mm, X -720..-450, Y 20..130 mm;
  - side  : Y = 90 mm, 14 mm outboard of the support's face, X -720..-400, Z 60..260 mm;
  - upwash_side over X -672..-588, Z 135..185; box behind X -583..-533, Y 56..80, Z 140..175.
  Outputs media/cfd/supports/support_flow_front.png, cfd/results/support_flow_front.csv.
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "cfd"))
OUT_PNG = ROOT / "media" / "cfd" / "supports" / "support_flow.png"
OUT_CSV = ROOT / "cfd" / "results" / "support_flow.csv"
U_INF = 20.0
H = 0.002                                                           # m, sampling step
PLAN = {"z": 0.760, "x": (1.600, 2.150), "y": (0.080, 0.230)}
SIDE = {"y": 0.172, "x": (1.600, 2.300), "z": (0.450, 1.250)}
CHORD = (1.667, 1.895)
BOX = {"x": (1.900, 2.000), "y": (0.120, 0.180), "z": (0.600, 1.100)}
SIDE_ZBAND = (0.600, 1.100)                                         # m, side-plane band for upwash_side
TXT = {"what": "rear-wing support", "plan_z": "Z 760 mm", "side_y": "Y 172 mm", "fig": (6.8, (0.5, 1.9))}
FRONT = {"PLAN": {"z": 0.165, "x": (-0.720, -0.450), "y": (0.020, 0.130)},
         "SIDE": {"y": 0.090, "x": (-0.720, -0.400), "z": (0.060, 0.260)},
         "CHORD": (-0.672, -0.588), "BOX": {"x": (-0.583, -0.533), "y": (0.056, 0.080), "z": (0.140, 0.175)},
         "SIDE_ZBAND": (0.135, 0.185),
         "OUT_PNG": ROOT / "media" / "cfd" / "supports" / "support_flow_front.png",
         "OUT_CSV": ROOT / "cfd" / "results" / "support_flow_front.csv",
         "TXT": {"what": "front-wing support", "plan_z": "Z 165 mm", "side_y": "Y 90 mm", "fig": (5.6, (0.9, 1.0))}}


def grid_plane(axis_fixed: str, val: float, r1, r2):
    import pyvista as pv
    n1 = int(round((r1[1] - r1[0]) / H)) + 1; n2 = int(round((r2[1] - r2[0]) / H)) + 1
    if axis_fixed == "z":
        g = pv.ImageData(dimensions=(n1, n2, 1), spacing=(H, H, H), origin=(r1[0], r2[0], val))
    else:                                                          # y fixed: x, z
        g = pv.ImageData(dimensions=(n1, 1, n2), spacing=(H, H, H), origin=(r1[0], val, r2[0]))
    return g, (n1, n2)


def sample(ug, g, shape):
    s = g.sample(ug)
    valid = np.asarray(s["vtkValidPointMask"]).astype(bool)
    U = np.asarray(s["U"], dtype=float); U[~valid] = np.nan
    n1, n2 = shape
    return U.reshape(n2, n1, 3) if True else U, valid.reshape(n2, n1)


def box_stats(ug):
    import pyvista as pv
    nx = int(round((BOX["x"][1] - BOX["x"][0]) / 0.005)) + 1
    ny = int(round((BOX["y"][1] - BOX["y"][0]) / 0.005)) + 1
    nz = int(round((BOX["z"][1] - BOX["z"][0]) / 0.005)) + 1
    g = pv.ImageData(dimensions=(nx, ny, nz), spacing=(0.005,) * 3, origin=(BOX["x"][0], BOX["y"][0], BOX["z"][0]))
    s = g.sample(ug)
    v = np.asarray(s["vtkValidPointMask"]).astype(bool)
    U = np.asarray(s["U"], dtype=float)[v]
    return float(np.mean(U[:, 2]) / U_INF), float(np.mean(1.0 - U[:, 0] / U_INF)), int(v.sum())


def analyse(run: str):
    import visualise as vis
    ug = vis.read_case(run)
    gp, shp = grid_plane("z", PLAN["z"], PLAN["x"], PLAN["y"])
    Up, vp = sample(ug, gp, shp)
    gs, shs = grid_plane("y", SIDE["y"], SIDE["x"], SIDE["z"])
    Us, vs = sample(ug, gs, shs)
    xs = SIDE["x"][0] + H * np.arange(shs[0]); zs = SIDE["z"][0] + H * np.arange(shs[1])
    X, Z = np.meshgrid(xs, zs)
    m = (X >= CHORD[0]) & (X <= CHORD[1]) & (Z >= SIDE_ZBAND[0]) & (Z <= SIDE_ZBAND[1]) & vs
    up_side = float(np.nanmean(Us[..., 2][m]) / U_INF)
    up_b, def_b, nb = box_stats(ug)
    return {"run": run, "upwash_side": up_side, "upwash_behind": up_b, "deficit_behind": def_b, "box_points": nb,
            "_plan": np.linalg.norm(Up, axis=2) / U_INF, "_side": Us[..., 2] / U_INF}


def picture(res):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    n = len(res)
    fig, ax = plt.subplots(2, n, figsize=(3.4 * n + 1.2, TXT["fig"][0]), gridspec_kw={"height_ratios": list(TXT["fig"][1])}, constrained_layout=True)
    ax = np.atleast_2d(ax).reshape(2, n)
    for k, r in enumerate(res):
        a = ax[0, k]
        im1 = a.imshow(r["_plan"], origin="lower", extent=[1000 * PLAN["x"][0], 1000 * PLAN["x"][1], 1000 * PLAN["y"][0], 1000 * PLAN["y"][1]],
                       cmap="viridis", vmin=0.3, vmax=1.15, aspect="equal")
        a.set_title(f"{r['run']}: speed / U", fontsize=9); a.set_xlabel("X, mm", fontsize=8); a.tick_params(labelsize=7)
        if k == 0:
            a.set_ylabel("Y, mm", fontsize=8)
        b = ax[1, k]
        im2 = b.imshow(r["_side"], origin="lower", extent=[1000 * SIDE["x"][0], 1000 * SIDE["x"][1], 1000 * SIDE["z"][0], 1000 * SIDE["z"][1]],
                       cmap="RdBu_r", vmin=-0.25, vmax=0.25, aspect="equal")
        b.axvline(1000 * CHORD[0], color="k", lw=0.5, ls=":"); b.axvline(1000 * CHORD[1], color="k", lw=0.5, ls=":")
        b.set_title(f"{r['run']}: w / U at {TXT['side_y']}\nmean beside the support {r['upwash_side']:+.3f}", fontsize=9)
        b.set_xlabel("X, mm", fontsize=8); b.tick_params(labelsize=7)
        if k == 0:
            b.set_ylabel("Z, mm", fontsize=8)
    fig.colorbar(im1, ax=ax[0, :].tolist(), shrink=0.8, label="speed / U")
    fig.colorbar(im2, ax=ax[1, :].tolist(), shrink=0.6, label="w / U (red: up)")
    where = ("white at the top: the wing" if TXT["what"].startswith("rear") else "white: the wing below, the nose above")
    fig.suptitle(f"Air next to the {TXT['what']} (half car, 20 m/s). Steady RANS: only the ranking of the variants is trustworthy.\n"
                 f"Top: plan view at {TXT['plan_z']} (white: inside the support or the nose). Bottom: side view 14 mm outboard of the support (dotted: its chord; {where}).",
                 fontsize=9)
    OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT_PNG, dpi=115); plt.close(fig)


def selftest() -> int:
    """Uniform flow U = (20, 0, 2) on a small grid: upwash 0.1 and deficit 0 in the box."""
    import pyvista as pv
    g = pv.ImageData(dimensions=(40, 20, 60), spacing=(0.01, 0.01, 0.01), origin=(1.85, 0.10, 0.55)).cast_to_unstructured_grid()
    g.cell_data["U"] = np.tile([20.0, 0.0, 2.0], (g.n_cells, 1))
    up, de, n = box_stats(g)
    ok = abs(up - 0.1) < 1e-9 and abs(de) < 1e-9 and n > 0
    print(f"selftest uniform flow: upwash {up:.4f} (0.1), deficit {de:.4f} (0): {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


def main(argv) -> int:
    if "--selftest" in argv:
        return selftest()
    if "--front" in argv:
        globals().update(FRONT)
        argv = [a for a in argv if a != "--front"]
    runs = argv or ["CP", "E", "G", "H", "F"]
    res = []
    for r in runs:
        print("reading", r, flush=True)
        res.append(analyse(r))
    picture(res)
    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["run", "upwash_side", "upwash_behind", "deficit_behind", "box_points"])
        for r in res:
            w.writerow([r["run"], f"{r['upwash_side']:.4f}", f"{r['upwash_behind']:.4f}", f"{r['deficit_behind']:.4f}", r["box_points"]])
            print(f"{r['run']:8s} upwash side {r['upwash_side']:+.4f}  behind {r['upwash_behind']:+.4f}  deficit behind {r['deficit_behind']:.4f}")
    print("wrote", OUT_PNG, OUT_CSV)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
