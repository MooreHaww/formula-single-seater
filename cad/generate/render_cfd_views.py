#!/usr/bin/env python3
"""Side, top and front pictures of the half-car CFD bodies, for a quick look
without opening a CAD program.

    .venv/Scripts/python cad/generate/render_cfd_views.py [--dir cad/step/cfd] [--out media/cfd]

Reads halfcar_<V>.step, tessellates the three solids and draws flat-shaded
orthographic views (painter's algorithm) to media/cfd/halfcar_<V>_views.png.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from build123d import import_step
from matplotlib.collections import PolyCollection

ROOT = Path(__file__).resolve().parents[2]
BASE = {0: (0.80, 0.15, 0.15), 1: (0.2, 0.2, 0.2), 2: (0.2, 0.2, 0.2)}      # car, wheels (solids sorted by volume)


def triangles(step: Path):
    solids = sorted(import_step(str(step)).solids(), key=lambda s: -s.volume)
    out = []
    for k, s in enumerate(solids):
        verts, faces = s.tessellate(0.5, 0.3)
        v = np.array([(q.X, q.Y, q.Z) for q in verts]); f = np.array(faces)
        out.append((v[f], BASE.get(k, (0.5, 0.5, 0.5))))
    return out


def draw(ax, tris, a, b, depth, sign, title):
    """Project on axes (a, b); 'depth' axis sorted so the nearest is drawn last."""
    polys, cols, key = [], [], []
    light = np.array([0.3, -0.5, 0.8]); light = light / np.linalg.norm(light)
    for t, base in tris:
        n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
        ln = np.linalg.norm(n, axis=1); ln[ln == 0] = 1
        shade = 0.45 + 0.55 * np.abs((n / ln[:, None]) @ light)
        polys.append(t[:, :, [a, b]]); cols.append(np.outer(shade, base)); key.append(sign * t[:, :, depth].mean(axis=1))
    polys = np.concatenate(polys); cols = np.concatenate(cols); key = np.concatenate(key)
    order = np.argsort(key)
    ax.add_collection(PolyCollection(polys[order], facecolors=np.clip(cols[order], 0, 1), edgecolors="none"))
    ax.autoscale(); ax.set_aspect("equal"); ax.set_title(title, fontsize=9); ax.grid(True, lw=0.3)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=str(ROOT / "cad" / "step" / "cfd"))
    ap.add_argument("--out", default=str(ROOT / "media" / "cfd"))
    args = ap.parse_args()
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    n = 0
    for step in sorted(Path(args.dir).glob("halfcar_*.step")):
        tris = triangles(step)
        fig, axs = plt.subplots(3, 1, figsize=(11, 13), gridspec_kw={"height_ratios": [1.6, 0.9, 1.6]})
        draw(axs[0], tris, 0, 2, 1, 1, f"{step.stem}: side view from the right (X rearward, Z up), mm")
        draw(axs[1], tris, 0, 1, 2, 1, "top view (Y = 0 is the symmetry plane)")
        draw(axs[2], tris, 1, 2, 0, -1, "front view (looking rearward)")
        fig.tight_layout()
        fig.savefig(out / f"{step.stem}_views.png", dpi=110); plt.close(fig)
        print("wrote", out / f"{step.stem}_views.png"); n += 1
    return 0 if n else 1


if __name__ == "__main__":
    sys.exit(main())
