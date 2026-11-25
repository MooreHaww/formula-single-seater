"""Smoke wind tunnel films for cfd/visualise.py.

Particles are released at a steady rate from a seeding grid 1.25 m ahead of the car
and from a few seeds near the wheels, the wing tips and under the floor, and carried
along the streamlines of the steady RANS solution: a particle released at time t_r
is, at time t, at the point of its streamline whose integration time is t - t_r.
Each particle is drawn as a short streak (its path over the last few milliseconds),
coloured by the local speed. In a steady flow streaklines and streamlines are the
same lines, so this is an animated streamline picture, not unsteady turbulence:
every film says so.
"""
from __future__ import annotations

import time

import numpy as np

from vis_common import Movie, cmap, colorbar_strip, frame_with_text, mirror_lines, mirrored, rake, trace
from visualise import CLIM, GRIDS, OUT, SMOKE_CAPTION, log

BG = (0.05, 0.05, 0.07)
GROUND = (0.17, 0.17, 0.19)
CAR = (0.80, 0.80, 0.82)
RELEASE_DT = 0.020        # s between particles from one seed (40 cm apart at 20 m/s)
TAIL = 0.009              # s of path drawn behind each particle (an 18 cm dash at 20 m/s)
T_FILM = 1.6              # s of flow time shown
FRAMES = 432              # 18 s at 24 fps, so the flow is slowed about 11 times


# ---------------------------------------------------------------------------- seeds
def seed_groups():
    """Half-car seeds (Y >= 0), by group. Positions from the car surfaces of runs
    A, B, CP and D: front-wing tips at Y 0.81 to 0.85 m, front tyres X -0.23..0.23,
    Y 0.51..0.69; rear tyres X 1.32..1.78, Y 0.49..0.67; rear-wing endplates Y 0.63
    to 0.67, Z 0.9..1.58; floor Z 0.04..0.08 up to the diffuser exit at X 2.15."""
    g = {"rake": rake(-1.25, (0.04, 0.84), (0.04, 1.50), 7, 9)}
    g["front wing tip"] = rake(-1.12, (0.88, 0.88), (0.04, 0.44), 1, 6)
    g["front wheel"] = np.vstack([rake(-0.27, (0.74, 0.74), (0.05, 0.42), 1, 4),
                                  rake(-0.27, (0.53, 0.67), (0.48, 0.48), 3, 1)])
    g["rear wheel"] = rake(1.25, (0.71, 0.71), (0.05, 0.40), 1, 4)
    g["rear wing tip"] = np.vstack([rake(0.95, (0.57, 0.57), (0.95, 1.55), 1, 5),
                                    rake(0.95, (0.70, 0.70), (0.95, 1.55), 1, 5)])
    g["floor and diffuser"] = rake(0.50, (0.05, 0.40), (0.016, 0.026), 5, 2)
    return g


def valid_seeds(data, pts):
    """Keep seeds whose 8 surrounding grid nodes are all in the fluid."""
    (ox, oy, oz), h, _ = GRIDS["near"]
    g = data["near"]
    nx, ny, nz = g.dimensions
    val = np.asarray(g["valid"]).reshape((nz, ny, nx))
    keep = []
    for p in pts:
        i, j, k = int((p[0] - ox) // h), int((p[1] - oy) // h), int((p[2] - oz) // h)
        if not (0 <= i < nx - 1 and 0 <= j < ny - 1 and 0 <= k < nz - 1):
            keep.append(False)
            continue
        keep.append(bool(val[k:k + 2, j:j + 2, i:i + 2].min() > 0))
    return pts[np.array(keep, dtype=bool)]


_LINES = {}


def smoke_lines(data):
    if data["run"] not in _LINES:
        t = time.time()
        groups = seed_groups()
        seeds = np.vstack([valid_seeds(data, s) for s in groups.values()])
        n_all = sum(len(s) for s in groups.values())
        lines = trace(data, seeds, x_end=11.0, max_length=30.0)
        # each seed releases with its own phase (the same for its mirror image), so the
        # particles do not line up in sheets
        ph = np.random.default_rng(7).uniform(0.0, RELEASE_DT, len(lines))
        _LINES[data["run"]] = [(P, T, s, f) for (P, T, s), f in zip(mirror_lines(lines), np.r_[ph, ph])]
        log(f"   {data['run']}: {len(seeds)} of {n_all} smoke seeds in the fluid, {len(lines)} lines per half, "
            f"longest {max(l[1][-1] for l in lines):.2f} s, {time.time() - t:.0f} s")
    return _LINES[data["run"]]


# ---------------------------------------------------------------------------- particles
def particles(lines, t, dt=RELEASE_DT, tail=TAIL, nseg=4):
    """Streaks of all particles released up to time t, as PolyData lines with 'speed'."""
    import pyvista as pv
    pts, spd, conn = [], [], []
    off = 0
    frac = np.linspace(1.0, 0.0, nseg)                     # tail end -> head
    for P, T, s, phase in lines:
        ages = t - phase - np.arange(0.0, t + 1e-9, dt)
        ages = ages[(ages > 0) & (ages <= T[-1])]
        if len(ages) == 0:
            continue
        A = np.clip(ages[:, None] - tail * frac[None, :], 0.0, None)     # (m, nseg)
        a = A.ravel()
        xyz = np.c_[np.interp(a, T, P[:, 0]), np.interp(a, T, P[:, 1]), np.interp(a, T, P[:, 2])]
        pts.append(xyz)
        spd.append(np.interp(a, T, s))
        m = len(ages)
        idx = off + np.arange(m * nseg).reshape(m, nseg)
        conn.append(np.c_[np.full(m, nseg), idx].ravel())
        off += m * nseg
    if not pts:
        return pv.PolyData()
    poly = pv.PolyData(np.vstack(pts), lines=np.concatenate(conn))
    poly["speed"] = np.concatenate(spd).astype(np.float32)
    return poly


def scene(data, size, ground_width=5.0):
    from vis_render import plotter
    import pyvista as pv
    p = plotter(size, bg=BG)
    g = pv.Plane(center=(4.75, 0, -0.002), direction=(0, 0, 1), i_size=13.5, j_size=ground_width)
    p.add_mesh(g, color=GROUND, lighting=False)
    p.add_mesh(mirrored(data["car"]), color=CAR, smooth_shading=False, specular=0.35, ambient=0.3, diffuse=0.8)
    return p


def draw(p, poly, actor, width=2.0):
    if actor is not None:
        p.remove_actor(actor)
    if poly.n_points == 0:
        return None
    return p.add_mesh(poly, scalars="speed", cmap=cmap("speed"), clim=CLIM["speed"], line_width=width,
                      show_scalar_bar=False, lighting=False)


def ease(u):
    return 0.5 - 0.5 * np.cos(np.pi * np.clip(u, 0, 1))


def flow_time(frames=FRAMES, t_film=T_FILM):
    return np.linspace(0.0, t_film, frames)


# ---------------------------------------------------------------------------- films
def smoke_film(data, frames=FRAMES):
    """One variant: the camera swings slowly from the front-left three-quarter view to
    the rear-left three-quarter view while the smoke fills the flow."""
    log(f"smoke film {data['label']} (run {data['run']})")
    lines = smoke_lines(data)
    mv = Movie(OUT / f"smoke_{data['label']}", fps=24, gif_width=520, gif_every=5, crf=30)
    bar = colorbar_strip("speed", "speed / free stream (20 m/s)", 1280, dark=True)
    p = scene(data, (1280, 720))
    actor = None
    ts = flow_time(frames)
    slow = (frames / 24.0) / T_FILM
    for k, t in enumerate(ts):
        u = ease(k / (frames - 1))
        az = np.deg2rad(-140 + 85 * u)
        foc = np.array([1.2, 0.0, 0.5]) + u * np.array([2.2, 0.0, 0.25])
        r, hgt = 8.0 + 0.8 * u, 3.0 + 0.5 * u
        p.camera.position = foc + np.array([r * np.cos(az), r * np.sin(az), hgt])
        p.camera.focal_point, p.camera.up = foc, (0, 0, 1)
        p.camera.view_angle = 36
        actor = draw(p, particles(lines, t), actor, width=2.4)
        p.render()
        mv.add(frame_with_text(p.screenshot(return_img=True),
                               f"{data['title']}: smoke tunnel   t = {t:.2f} s of flow, shown {slow:.0f} times slower",
                               "Particles released from a grid 1.25 m ahead of the car and next to the wheels, the "
                               "wing tips and under the floor, coloured by speed. " + SMOKE_CAPTION, bar, dark=True))
    p.close()
    for f in mv.write():
        log("   wrote", f.relative_to(OUT.parents[2]))


def smoke_side_by_side(datas, frames=FRAMES):
    """Several variants one above the other, same seeds, same camera, same flow time,
    so the wakes line up."""
    from PIL import Image, ImageDraw
    from vis_common import font
    labels = "".join(d["label"] for d in datas)
    log(f"smoke side by side {labels}")
    size = (1280, 400)
    allines = [smoke_lines(d) for d in datas]
    plots = []
    for d in datas:
        p = scene(d, size, ground_width=14.0)
        p.camera.position, p.camera.focal_point, p.camera.up = (4.4, -13.5, 2.3), (4.4, 0.0, 1.05), (0, 0, 1)
        p.camera.view_angle = 18
        plots.append(p)
    actors = [None] * len(datas)
    mv = Movie(OUT / f"smoke_{labels}", fps=24, gif_width=480, gif_every=6, crf=31)
    bar = colorbar_strip("speed", "speed / free stream (20 m/s)", size[0], dark=True)
    slow = (frames / 24.0) / T_FILM
    f_lab = font(22, bold=True)
    for k, t in enumerate(flow_time(frames)):
        panel = Image.new("RGB", (size[0], len(datas) * size[1] + 4 * (len(datas) - 1)), (60, 60, 66))
        for n, (d, p, lines) in enumerate(zip(datas, plots, allines)):
            actors[n] = draw(p, particles(lines, t), actors[n], width=2.0)
            p.render()
            im = Image.fromarray(p.screenshot(return_img=True))
            ImageDraw.Draw(im).text((14, 10), d["title"], fill=(235, 235, 235), font=f_lab)
            panel.paste(im, (0, n * (size[1] + 4)))
        mv.add(frame_with_text(panel, f"{', '.join(d['label'] for d in datas)}: smoke tunnel side by side   "
                                      f"t = {t:.2f} s of flow, shown {slow:.0f} times slower",
                               "Same seeds, same camera (left side, from 13.5 m) and same flow time in every row; "
                               "coloured by speed. " + SMOKE_CAPTION, bar, dark=True))
    for p in plots:
        p.close()
    for f in mv.write():
        log("   wrote", f.relative_to(OUT.parents[2]))
