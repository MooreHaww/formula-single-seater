#!/usr/bin/env python3
"""Pictures of the rear-wing supports E-H against CP's flat pylon (docs/wing_supports_plan.md).

    .venv/Scripts/python cad/generate/render_rw_supports.py

Writes media/cfd/supports/supports_sections.png (plan sections and G's side view) and
supports_3d.png (each support with the rear-wing main element and hull around it, from
halfcar_<V>.step, clipped to the support region). Geometry only, no CFD.
"""
from __future__ import annotations

import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cfd_variants as cv  # noqa: E402
from build123d import import_step  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "media" / "cfd" / "supports"
KINDS = {"E": "lens", "F": "round", "G": "ridges", "H": "flare"}
NAMES = {"CP": "CP: flat 16 mm plate", "E": "E: lens", "F": "F: rounded front edge", "G": "G: lens + ridges", "H": "H: flared blunt tail"}


def envelope(p):
    _, info = cv.build_rear_wing(p, "CP")
    xa, xb = info["pylon_x"]; pts = info["geo"]["rw_main"]["points"]
    return xa, xb, cv.mid_z_at(pts, xa), cv.mid_z_at(pts, xb)


def outline(solid, z):
    """Plan-view outline at height z: vertices of the slice, ordered by angle round the centre."""
    sl = solid & cv.box_between(-1e4, 1e4, -1e4, 1e4, z - 0.25, z + 0.25)
    v, _ = sl.tessellate(0.05, 0.05)
    a = np.array([(q.X, q.Y) for q in v])
    return a


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    p = cv.variant_params(cv.read_car_params(), "CP")
    xa, xb, za, zb = envelope(p)
    yc, t = p["rw_pylon_y"], p["rw_pylon_thickness"]
    sup = {k: cv.build_rw_support(p, kd, xa, xb, za, zb) for k, kd in KINDS.items()}
    sup["CP"] = cv.prism_xz([(xa, 300.0), (xb, 300.0), (xb, zb), (xa, za)], yc - t / 2, yc + t / 2)

    fig = plt.figure(figsize=(13, 8.5))
    gs = fig.add_gridspec(3, 2, width_ratios=[1.25, 1])
    ax = fig.add_subplot(gs[:, 0])
    off = 0.0
    for v, z, lab in [("CP", 760, ""), ("E", 760, ""), ("F", 760, ""), ("H", 760, ""), ("G", 760, " (between ridges)"), ("G", 655, " (through a ridge, Z 655)")]:
        a = outline(sup[v], z)
        c = a.mean(axis=0); ang = np.arctan2(a[:, 1] - c[1], (a[:, 0] - c[0]) / 20.0)
        a = a[np.argsort(ang)]; a = np.vstack([a, a[:1]])
        ax.fill(a[:, 0], a[:, 1] - yc + off, color="0.6", ec="k", lw=0.8)
        ax.text(xa - 8, off, NAMES[v] + lab, ha="right", va="center", fontsize=9)
        off -= 45.0
    ax.annotate("", xy=(xa + 60, 25), xytext=(xa, 25), arrowprops=dict(arrowstyle="->"))
    ax.text(xa + 65, 25, "air", va="center", fontsize=9)
    ax.set_aspect("equal"); ax.set_xlim(xa - 200, xb + 15); ax.set_ylim(off + 15, 40)
    ax.set_xlabel("X, mm (rearward)"); ax.set_yticks([])
    ax.set_title(f"Plan sections, true scale (chord {xb - xa:.0f} mm, 16 mm thick)", fontsize=10)
    # G side view: outline of the support and ridges, from the +Y side
    ax2 = fig.add_subplot(gs[:, 1])
    g = sup["G"]
    v, f = g.tessellate(0.5, 0.3)
    V = np.array([(q.X, q.Y, q.Z) for q in v]); F = np.array(f)
    out = V[F][:, :, 1].mean(axis=1) > yc + t / 2 + 0.5            # triangles standing out of the +Y face: the ridges
    from matplotlib.collections import PolyCollection
    ax2.add_collection(PolyCollection(V[F][~out][:, :, [0, 2]], facecolor="0.8", edgecolor="none"))
    ax2.add_collection(PolyCollection(V[F][out][:, :, [0, 2]], facecolor="tab:purple", edgecolor="none"))
    ax2.plot([xa, xb], [za, zb], "b-", lw=1); ax2.text(xa, za + 15, "rear-wing main element middle line", color="b", fontsize=8)
    ax2.set_aspect("equal"); ax2.set_xlim(xa - 20, xb + 20); ax2.set_ylim(280, 1200)
    ax2.set_title("G from the side: ridges (purple), horizontal at the front, 20 deg up at the back\n(bottom part sits inside the hull, top inside the wing)", fontsize=9)
    ax2.set_xlabel("X, mm"); ax2.set_ylabel("Z, mm")
    fig.suptitle("Rear-wing supports E-H (CFD geometry only, cad/generate/cfd_variants.py)", fontsize=11)
    fig.tight_layout(); fig.savefig(OUT / "supports_sections.png", dpi=120); plt.close(fig)

    # 3D close-ups from the variants' STEP files
    fig = plt.figure(figsize=(14, 4.2))
    clip = cv.box_between(xa - 150, xb + 250, 60, 260, 380, 1260)
    for k, vname in enumerate(["E", "F", "G", "H"]):
        car = sorted(import_step(str(ROOT / "cad" / "step" / "cfd" / f"halfcar_{vname}.step")).solids(), key=lambda s: -s.volume)[0]
        part = car & clip
        v, f = part.tessellate(0.6, 0.4)
        V = np.array([(q.X, q.Y, q.Z) for q in v]); T = V[np.array(f)]
        n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]); n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
        light = np.array([-0.4, 0.7, 0.6]); light /= np.linalg.norm(light)
        shade = 0.35 + 0.6 * np.abs(n @ light)
        ins = (np.abs(T[:, :, 1].mean(1) - yc) < 30) & (T[:, :, 2].mean(1) < 1120) & (T[:, :, 0].mean(1) > xa - 2) & (T[:, :, 0].mean(1) < xb + 2)
        col = np.where(ins[:, None], np.array([0.6, 0.15, 0.8]), np.array([0.75, 0.75, 0.78])) * shade[:, None]
        ax = fig.add_subplot(1, 4, k + 1, projection="3d")
        ax.add_collection3d(Poly3DCollection(T, facecolors=np.clip(col, 0, 1), edgecolor="none"))
        ax.set_xlim(xa - 150, xb + 250); ax.set_ylim(-50, 350); ax.set_zlim(380, 1260)
        ax.set_box_aspect((400, 400, 880)); ax.view_init(elev=12, azim=-125); ax.set_axis_off()
        ax.set_title(NAMES[vname], fontsize=9)
    fig.suptitle("Supports (purple) with the hull below and the rear-wing main element above, seen from behind and outboard", fontsize=10)
    fig.tight_layout(); fig.savefig(OUT / "supports_3d.png", dpi=110); plt.close(fig)
    print("wrote", OUT / "supports_sections.png", OUT / "supports_3d.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
