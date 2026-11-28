#!/usr/bin/env python3
"""Pictures and films of the wing-support study (docs/wing_supports_plan.md), from the saved
Fluent results (no new solves, no Fluent licence: VTK's Fluent CFF reader, as cfd/visualise.py).

    .venv/Scripts/python cfd/vis_supports.py export            # local grids around the supports (cache)
    .venv/Scripts/python cfd/vis_supports.py films             # rear and front support smoke films, README GIF
    .venv/Scripts/python cfd/vis_supports.py wake              # CP_bl1 vs CPFF wake film (compare_ABCD style)
    .venv/Scripts/python cfd/vis_supports.py all
    .venv/Scripts/python cfd/vis_supports.py --selftest

export: per run, cfd/cases/vis/<run>/ (git-ignored):
    sup_rear.vti   4 mm grid around the rear support  (X 1.50..2.45, Y 0.06..0.30, Z 0.50..1.42 m)
    sup_front.vti  2 mm grid around the front support (X -0.78..-0.36, Y 0.004..0.16, Z 0.04..0.30 m)
    sup_car.vtp    the car and wheel walls (Cp, speed of the wall-adjacent cell)
  sampled linearly inside each Fluent cell from the cell values averaged to the nodes (as
  visualise.resample). The 12.5 mm grid of visualise.py is too coarse for a 16 mm support.
films: media/cfd/supports/supports_rear.mp4 (CP_bl1, E, F, H), supports_front.mp4 (CP_bl1, J),
    each a side view (car cut 50 mm outboard of the support) above a top view (car cut just above
    a horizontal section through the support), same camera, seeds and colour scale for every run;
    media/cfd/supports/supports_compare.gif (README; the rear film, smaller).
wake: media/cfd/supports/wake_CP_bl1_CPFF.mp4 (+ .gif, git-ignored): underbody Cp and a wake
    slice moving back from the rear wing, as visualise.py's compare_ABCD film.

Steady RANS (k-omega SST), half car, Student mesh, 1 prism layer: the smoke is animated
streamlines of a steady solution, not unsteady turbulence. Only the ranking is trustworthy.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from visualise import CACHE, U_INF, car_surface, log, read_case  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "media" / "cfd" / "supports"

# local grids: origin, spacing, upper corner (m)
SUP_GRIDS = {
    "rear": ((1.50, 0.060, 0.50), 0.004, (2.45, 0.300, 1.42)),
    "front": ((-0.78, 0.004, 0.04), 0.002, (-0.36, 0.160, 0.30)),
}
REAR_RUNS = {"CP_bl1": "CP_bl1: flat 16 mm plate (CP's pylon)", "E_bl1": "E: lens, 3 mm square edges",
             "F_bl1": "F: lens, 5 mm round front edge", "H_bl1": "H: lens, flared 24 mm blunt tail"}
FRONT_RUNS = {"CP_bl1": "CP_bl1: flat 16 mm plate (CP's pylon)", "J_bl1": "J: lens, 5 mm round front edge"}
ALL_RUNS = ("CP_bl1", "E_bl1", "F_bl1", "H_bl1", "J_bl1", "CPFF_bl1")


def sample_grid(ugp, spec):
    import pyvista as pv
    (ox, oy, oz), h, (ux, uy, uz) = spec
    dims = (int(round((ux - ox) / h)) + 1, int(round((uy - oy) / h)) + 1, int(round((uz - oz) / h)) + 1)
    g = pv.ImageData(dimensions=dims, spacing=(h, h, h), origin=(ox, oy, oz))
    s = g.sample(ugp)
    valid = np.asarray(s["vtkValidPointMask"]).astype(bool)
    out = pv.ImageData(dimensions=dims, spacing=(h, h, h), origin=(ox, oy, oz))
    U = np.asarray(s["U"], dtype=np.float32)
    U[~valid] = 0.0
    out.point_data["U"] = U
    out.point_data["valid"] = valid.astype(np.uint8)
    return out


def export_run(run: str, force: bool = False) -> str:
    d = CACHE / run
    files = [d / "sup_rear.vti", d / "sup_front.vti", d / "sup_car.vtp"]
    if not force and all(f.exists() for f in files):
        return f"{run}: cached"
    d.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    ug = read_case(run)
    car_surface(ug).save(d / "sup_car.vtp")
    ugp = ug.cell_data_to_point_data()
    for name, spec in SUP_GRIDS.items():
        sample_grid(ugp, spec).save(d / f"sup_{name}.vti")
    (d / "sup_info.json").write_text(json.dumps({"run": run, "cells": ug.n_cells, "grids": SUP_GRIDS,
                                                 "made": time.strftime("%Y-%m-%d %H:%M"),
                                                 "source": f"cfd/cases/halfcar_{run}.cas.h5 + .dat.h5"}, indent=1))
    return f"{run}: exported in {time.time() - t0:.0f} s"


def step_export(runs, force=False, workers=3):
    log("export support grids", list(runs))
    with ProcessPoolExecutor(max_workers=min(workers, len(runs))) as ex:
        for msg in ex.map(export_run, runs, [force] * len(runs)):
            log(" ", msg)


# ---------------------------------------------------------------------------- films
# Views. Exposed supports (car surface of F_bl1): rear Z 0.50 (hull top) to 1.11 m (main element), X 1.667-1.895,
# Y 0.142-0.158; front Z 0.13 (wing) to 0.19 m (nose), X -0.672..-0.588, Y 0.060-0.076.
# side: camera on +Y, car cut away outboard of clip_y; top: camera above, only the slab of car between the two Z
# of "slab" drawn (on the dark background), with the section outline at the seeds' middle height in white.
VIEWS = {
    "rear": {"grid": "rear", "t_film": 0.20, "dt": 0.0025, "tail": 0.0015,
             "side": {"clip_y": 0.20, "focal": (1.95, 0.15, 0.85), "scale": 0.40, "size": (440, 440),
                      "seeds": [(1.60, y, z) for y in (0.150, 0.161, 0.168) for z in np.arange(0.54, 1.09, 0.045)]},
             "top": {"slab": (0.70, 0.86), "z_cut": 0.80, "focal": (1.85, 0.150, 0.80), "scale": 0.109, "size": (440, 190),
                     "seeds": [(1.60, y, z) for z in (0.78, 0.80, 0.82) for y in np.arange(0.110, 0.1905, 0.005)]}},
    "front": {"grid": "front", "t_film": 0.08, "dt": 0.0010, "tail": 0.0007,
              "side": {"clip_y": 0.105, "focal": (-0.57, 0.068, 0.165), "scale": 0.11, "size": (600, 400),
                       "seeds": [(-0.72, y, z) for y in (0.068, 0.079, 0.086) for z in np.arange(0.135, 0.1905, 0.008)]},
              "top": {"slab": (0.150, 0.178), "z_cut": 0.165, "focal": (-0.59, 0.068, 0.165), "scale": 0.044, "size": (600, 190),
                      "seeds": [(-0.72, y, z) for z in (0.160, 0.165, 0.170) for y in np.arange(0.030, 0.1105, 0.004)]}},
}
BG = (0.05, 0.05, 0.07)
CAR = (0.80, 0.80, 0.82)
FRAMES = 288                    # 12 s at 24 fps


def load_grid(run, which):
    import pyvista as pv
    return pv.read(CACHE / run / f"sup_{which}.vti"), pv.read(CACHE / run / "sup_car.vtp")


def valid(grid, pts):
    """Seeds whose 8 surrounding grid nodes are all in the fluid (as vis_smoke.valid_seeds)."""
    (ox, oy, oz), h = grid.origin, grid.spacing[0]
    nx, ny, nz = grid.dimensions
    val = np.asarray(grid["valid"]).reshape((nz, ny, nx))
    keep = []
    for p in pts:
        i, j, k = int((p[0] - ox) // h), int((p[1] - oy) // h), int((p[2] - oz) // h)
        keep.append(0 <= i < nx - 1 and 0 <= j < ny - 1 and 0 <= k < nz - 1 and val[k:k + 2, j:j + 2, i:i + 2].min() > 0)
    return np.asarray(pts)[np.array(keep, dtype=bool)]


def lines_for(grid, seeds, dt):
    """Streamlines on the local grid -> [(P, T, speed/U, release phase)] for vis_smoke.particles."""
    from vis_common import _trace
    lines = []
    for P, T in _trace(grid, valid(grid, seeds), max_length=3.0):
        seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
        spd = np.r_[seg / np.maximum(np.diff(T), 1e-9), 0.0]
        spd[-1] = spd[-2] if len(spd) > 1 else 0.0
        lines.append((P, T, spd / U_INF))
    ph = np.random.default_rng(7).uniform(0.0, dt, len(lines))
    return [(P, T, s, f) for (P, T, s), f in zip(lines, ph)]


def view_plotter(car, view, kind):
    from vis_render import plotter
    p = plotter(view["size"], bg=BG)
    if kind == "side":
        cut = car.clip(normal="y", origin=(0, view["clip_y"], 0), invert=True)
        pos = np.array(view["focal"]) + np.array([0.0, 3.0, 0.0]); up = (0, 0, 1)
    else:
        z0, z1 = view["slab"]
        cut = car.clip_box((-50.0, 50.0, -50.0, 50.0, z0, z1), invert=False)
        pos = np.array(view["focal"]) + np.array([0.0, 0.0, 3.0]); up = (0, 1, 0)
        sec = car.slice(normal="z", origin=(0, 0, view["z_cut"]))
        if sec.n_points:
            p.add_mesh(sec.translate((0, 0, z1 - view["z_cut"] + 0.01)), color="white", line_width=3, lighting=False)
    if cut.n_points:
        p.add_mesh(cut, color=CAR, smooth_shading=False, ambient=0.35, diffuse=0.75, specular=0.2)
    p.enable_parallel_projection()
    p.camera.position, p.camera.focal_point, p.camera.up = tuple(pos), view["focal"], up
    p.camera.parallel_scale = view["scale"]
    return p


def support_film(which: str, runs: dict, stem: Path, gif_width=None, gif_every=4):
    """Columns = runs; each column a side view above a top view; same seeds, camera, colour
    scale and flow time everywhere."""
    from PIL import Image, ImageDraw
    from vis_common import Movie, colorbar_strip, font, frame_with_text
    from vis_smoke import draw, particles
    V = VIEWS[which]
    log(f"support film {which}: {list(runs)}")
    cols = []
    for run, title in runs.items():
        grid, car = load_grid(run, V["grid"])
        col = {"title": title}
        for kind in ("side", "top"):
            col[kind] = {"p": view_plotter(car, V[kind], kind), "lines": lines_for(grid, V[kind]["seeds"], V["dt"]),
                         "actor": None}
        log(f"   {run}: {len(col['side']['lines'])} side lines, {len(col['top']['lines'])} top lines")
        cols.append(col)
    ws, hs = V["side"]["size"]; wt, ht = V["top"]["size"]
    head, gap = 34, 6
    W = len(cols) * ws + (len(cols) - 1) * gap
    H = head + hs + gap + ht
    mv = Movie(stem, fps=24, gif_width=gif_width or W // 2, gif_every=gif_every, crf=28)
    bar = colorbar_strip("speed", "speed / free stream (20 m/s)", W, dark=True)
    ts = np.linspace(0.0, V["t_film"], FRAMES)
    slow = (FRAMES / 24.0) / V["t_film"]
    f_lab = font(19, bold=True); f_small = font(14)
    what = "rear-wing support" if which == "rear" else "front-wing support"
    for t in ts:
        panel = Image.new("RGB", (W, H), (60, 60, 66))
        for n, col in enumerate(cols):
            x0 = n * (ws + gap)
            ImageDraw.Draw(panel).rectangle([x0, 0, x0 + ws, head], fill=(20, 20, 24))
            ImageDraw.Draw(panel).text((x0 + 10, 6), col["title"], fill=(235, 235, 235), font=f_lab)
            for kind, y0 in (("side", head), ("top", head + hs + gap)):
                c = col[kind]
                c["actor"] = draw(c["p"], particles(c["lines"], t, dt=V["dt"], tail=V["tail"]), c["actor"], width=2.6)
                c["p"].render()
                im = Image.fromarray(c["p"].screenshot(return_img=True))
                lab = "side view, car cut away outboard of the support" if kind == "side" else "top view, car cut to a thin slice at the section"
                ImageDraw.Draw(im).text((8, 6), lab, fill=(200, 200, 200), font=f_small)
                panel.paste(im, (x0, y0))
        mv.add(frame_with_text(panel, f"Air past the {what}: same seeds, camera and colour scale in every column   "
                                      f"t = {1000 * t:.0f} ms of flow, shown {slow:.0f} times slower",
                               "Particles released just ahead of the support and carried along the streamlines, coloured by "
                               "speed; slow (blue) streaks beside or behind a support mark separated air. Steady RANS "
                               "(k-omega SST), half-car Student mesh, 1 prism layer, 20 m/s: the smoke shows time-averaged "
                               "streamlines, not real unsteady turbulence. One run per variant; only the ranking is "
                               "trustworthy. CFD only: the CAD has no supports.", bar, dark=True))
        last = panel
    for col in cols:
        for kind in ("side", "top"):
            col[kind]["p"].close()
    files = mv.write()
    last.save(stem.with_name(stem.name + "_still.png"), optimize=True)
    for f in list(files) + [stem.with_name(stem.name + "_still.png")]:
        log(f"   wrote {f} ({f.stat().st_size / 1e6:.2f} MB)")
    return files


def step_films():
    import shutil
    support_film("front", FRONT_RUNS, OUT / "supports_front", gif_width=640, gif_every=4)
    mp4, gif = support_film("rear", REAR_RUNS, OUT / "supports_rear", gif_width=900, gif_every=3)
    shutil.move(gif, OUT / "supports_compare.gif")
    log(f"   README GIF: media/cfd/supports/supports_compare.gif ({(OUT / 'supports_compare.gif').stat().st_size / 1e6:.2f} MB)")


def step_wake():
    """CP_bl1 vs CPFF: visualise.py's compare_ABCD film for two runs (near and wake grids from its cache)."""
    import pyvista as pv
    import visualise as vis
    import vis_render as vr
    datas, parts = [], {}
    for run, label, title in (("CP_bl1", "CP_bl1", "CP_bl1: flat plates front and rear"),
                              ("CPFF_bl1", "CPFF", "CPFF: J front + F rear supports")):
        log(" ", vis.export_run(run))
        d = CACHE / run
        datas.append({"car": pv.read(d / "car.vtp"), "near": pv.read(d / "near.vti"), "wake": pv.read(d / "wake.vti"),
                      "info": json.loads((d / "info.json").read_text()), "run": run, "label": label, "title": title})
        parts[label] = vr.forces_by_part(run)
    stem = OUT / "wake_CP_bl1_CPFF"
    vr.compare_video(datas, parts, stem=stem, title="CP_bl1 vs CPFF (wing supports): downforce distribution and the wake",
                     caption=("Both on CP's as-built bodywork, 1 prism layer. Steady RANS (k-omega SST), half car mirrored, "
                              "Student mesh, 20 m/s. One run per variant: the follower's-window q-ratio differs by 0.01 at "
                              "most, below what this mesh resolves. CFD only: the CAD has no supports."))
    for f in (stem.with_suffix(".mp4"), stem.with_suffix(".gif")):
        log(f"   {f.relative_to(ROOT)} {f.stat().st_size / 1e6:.2f} MB")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", default="all", choices=["export", "films", "wake", "all"])
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    OUT.mkdir(parents=True, exist_ok=True)
    if a.step in ("export", "all"):
        step_export(ALL_RUNS, a.force)
    if a.step in ("films", "all"):
        step_films()
    if a.step in ("wake", "all"):
        step_wake()
    return 0


def selftest() -> int:
    """Hand checks: the seed filter on a 3x3x3 grid with one solid node; streamline speed on a uniform
    20 m/s field is 1.0 U; the rear film's slow-down is 12 s / 0.20 s = 60."""
    import pyvista as pv
    ok = True
    g = pv.ImageData(dimensions=(3, 3, 3), spacing=(1, 1, 1), origin=(0, 0, 0))
    v = np.ones(27, dtype=np.uint8); v[26] = 0                 # node (2, 2, 2) inside the car
    g["valid"] = v
    kept = valid(g, [(0.5, 0.5, 0.5), (1.5, 1.5, 1.5)])
    ok &= len(kept) == 1 and tuple(kept[0]) == (0.5, 0.5, 0.5)
    print(f"  seed filter: {len(kept)} of 2 kept (want 1, the one away from the solid node)")
    g2 = pv.ImageData(dimensions=(21, 5, 5), spacing=(0.05, 0.05, 0.05), origin=(0, 0, 0))
    g2["U"] = np.tile([20.0, 0.0, 0.0], (g2.n_points, 1))
    g2["valid"] = np.ones(g2.n_points, dtype=np.uint8)
    L = lines_for(g2, [(0.05, 0.1, 0.1)], dt=0.002)
    s = float(np.median(L[0][2])) if L else float("nan")
    ok &= abs(s - 1.0) < 1e-3
    print(f"  uniform 20 m/s: streamline speed {s:.4f} U (want 1.0000)")
    slow = (FRAMES / 24.0) / VIEWS["rear"]["t_film"]
    ok &= abs(slow - 60.0) < 1e-9
    print(f"  rear film slow-down {slow:.1f} (want 60.0)")
    print(f"vis_supports self-test: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
