"""Stills, animations and the A-B-C-D comparison for cfd/visualise.py."""
from __future__ import annotations

import csv
import time

import numpy as np

from vis_common import (Movie, cmap, colorbar_strip, frame_with_text, lines_polydata, mirror_lines, mirrored, rake,
                        slice_xz, slice_yz, trace, font)
from visualise import (CAPTION, CLIM, CMAP, OUT, RESULTS, SLICES_L, U_INF, VARIANTS, log, slice_x)

WIN = (1600, 900)
BG = "white"
CAR_COLOUR = (0.72, 0.73, 0.76)
BOX_REGIONS = {"low": (0.8, 0.0, 0.5), "high": (0.65, 1.0, 1.5)}   # half-width, z0, z1 (cfd/postprocess.py)
Q_LEVEL = 4000.0          # 1/s^2, Q-criterion iso-level for the vortex pictures


# ---------------------------------------------------------------------------- plotting basics
def plotter(size=WIN, bg=BG):
    import pyvista as pv
    p = pv.Plotter(off_screen=True, window_size=size)
    p.set_background(bg)
    p.enable_anti_aliasing("ssaa")
    return p


def add_ground(p, x=(-2.0, 11.5), y=(-2.0, 2.0), colour=(0.93, 0.93, 0.94)):
    import pyvista as pv
    g = pv.Plane(center=((x[0] + x[1]) / 2, 0, -0.002), direction=(0, 0, 1), i_size=x[1] - x[0], j_size=y[1] - y[0])
    p.add_mesh(g, color=colour, lighting=False)


def add_car(p, data, colour=CAR_COLOUR, opacity=1.0):
    p.add_mesh(mirrored(data["car"]), color=colour, smooth_shading=False, specular=0.25, ambient=0.25,
               opacity=opacity)


def three_quarter(p, front=True, dist=1.0):
    c = np.array([0.7, 0.0, 0.45])
    if front:
        pos = c + dist * np.array([-4.6, -4.4, 2.6])
    else:
        pos = c + dist * np.array([5.5, -4.6, 2.8])
    p.camera.position, p.camera.focal_point, p.camera.up = pos, c, (0, 0, 1)
    p.camera.view_angle = 30


def shot(p):
    img = p.screenshot(return_img=True)
    p.close()
    return img


def save(img, name):
    path = OUT / name
    img.save(path, optimize=True)
    log("   wrote", path.relative_to(OUT.parents[2]))
    return path


def seeds_stream():
    """Rake 1.25 m ahead of the front-wing leading edge, half car."""
    return np.vstack([rake(-1.25, (0.03, 0.90), (0.04, 1.45), 9, 12)])


_LINES = {}


def stream_lines(data, which="stream"):
    key = (data["run"], which)
    if key not in _LINES:
        t = time.time()
        _LINES[key] = mirror_lines(trace(data, seeds_stream()))
        log(f"   {data['run']}: {len(_LINES[key])} streamlines in {time.time() - t:.0f} s")
    return _LINES[key]


# ---------------------------------------------------------------------------- stills
def surface_views(data, size=(1500, 560)):
    """Top, side and underbody views of Cp on the car (parallel projection)."""
    car = mirrored(data["car"])
    cx, cz = 0.63, 0.45
    views = {"top": ((cx, 0, 10), (cx, 0, 0), (0, 1, 0)),
             "side": ((cx, -10, cz), (cx, 0, cz), (0, 0, 1)),
             "underbody": ((cx, 0, -10), (cx, 0, 0), (0, -1, 0))}
    imgs = {}
    for name, (pos, foc, up) in views.items():
        p = plotter(size)
        p.add_mesh(car, scalars="Cp", cmap=cmap("Cp"), clim=CLIM["Cp"], show_scalar_bar=False, ambient=0.35,
                   diffuse=0.75, specular=0.1)
        p.enable_parallel_projection()
        p.camera.position, p.camera.focal_point, p.camera.up = pos, foc, up
        p.camera.parallel_scale = 0.98 if name != "side" else 0.85
        imgs[name] = shot(p)
    return imgs


def stack(imgs, labels, gap=6, label_font=22):
    from PIL import Image, ImageDraw
    ims = [Image.fromarray(i) if isinstance(i, np.ndarray) else i for i in imgs]
    w = max(i.width for i in ims)
    h = sum(i.height for i in ims) + gap * (len(ims) - 1)
    out = Image.new("RGB", (w, h), "white")
    y = 0
    d = ImageDraw.Draw(out)
    f = font(label_font, bold=True)
    for im, lab in zip(ims, labels):
        out.paste(im, (0, y))
        d.text((12, y + 8), lab, fill=(40, 40, 40), font=f)
        y += im.height + gap
    return out


def still_surface(data):
    imgs = surface_views(data)
    img = stack([imgs["top"], imgs["side"], imgs["underbody"]], ["top", "side (left)", "underbody (from below)"])
    bar = colorbar_strip("Cp", "pressure coefficient Cp = p / (0.5 rho U^2); blue = suction", img.width)
    out = frame_with_text(img, f"{data['title']}: surface pressure",
                          "Pressure of the wall-adjacent cell (first prism layer), colour scale clipped at -3 and +1. "
                          "Downforce comes from suction (blue) under the wings and the floor and pressure (red) on top. "
                          + CAPTION, bar)
    return save(out, f"{data['label']}_surface_cp.png")


def scene_streamlines(data, p, x_max=None, lines=None, width=2.0, opacity=1.0):
    poly = lines_polydata(lines if lines is not None else stream_lines(data), x_max=x_max)
    if poly.n_points:
        p.add_mesh(poly, scalars="speed", cmap=cmap("speed"), clim=CLIM["speed"], line_width=width,
                   show_scalar_bar=False, opacity=opacity, render_lines_as_tubes=False)
    return poly


def still_streamlines(data):
    p = plotter((1600, 820))
    add_ground(p)
    add_car(p, data)
    scene_streamlines(data, p, width=2.2)
    three_quarter(p, front=True, dist=1.3)
    p.camera.focal_point = (2.0, 0.0, 0.7)
    a = shot(p)
    p = plotter((1600, 560))
    add_ground(p)
    add_car(p, data)
    scene_streamlines(data, p, width=1.6)
    p.enable_parallel_projection()
    p.camera.position, p.camera.focal_point, p.camera.up = (4.85, -30, 1.25), (4.85, 0, 1.25), (0, 0, 1)
    p.camera.parallel_scale = 2.2
    b = shot(p)
    img = stack([a, b], ["three-quarter front view", "side view to 3.2 car lengths behind the rear axle"])
    bar = colorbar_strip("speed", "speed / free stream (20 m/s)", 1600)
    out = frame_with_text(img, f"{data['title']}: streamlines coloured by speed",
                          "Streamlines from a rake 1.25 m ahead of the car (9 x 12 seeds per half, mirrored), followed "
                          "to X 11 m. Behind a car with downforce the streamlines rise: that upwash is the reaction to the downforce. " + CAPTION, bar)
    return save(out, f"{data['label']}_streamlines.png")


WAKE_Q_DIV = 6.0         # the wake grid is 2.4 x coarser: its Q is smaller, so a lower level there


def q_off_walls(g, cells=2):
    """Q with the points within `cells` grid cells of a solid set to 0: the zero
    velocity inside the car gives a false velocity jump at the wall."""
    from scipy.ndimage import binary_dilation
    nx, ny, nz = g.dimensions
    solid = (np.asarray(g["valid"]) == 0).reshape((nz, ny, nx))
    near_wall = binary_dilation(solid, iterations=cells).ravel()
    return np.where(near_wall, 0.0, np.asarray(g["Q"])).astype(np.float32)


def vortex_surfaces(data, level=Q_LEVEL):
    """Q-criterion iso-surfaces from the fine grid (around the car) and the wake grid
    (behind it), coloured by streamwise vorticity."""
    import pyvista as pv
    parts = []
    for name, x_lo, x_hi in (("near", -1.3, 3.3), ("wake", 3.3, 11.0)):
        g = data[name].copy(deep=False)
        lev = level if name == "near" else level / WAKE_Q_DIV
        g.point_data["Qm"] = q_off_walls(g)
        iso = g.contour([lev], scalars="Qm")
        if iso.n_points == 0:
            continue
        iso = iso.clip_box((x_lo, x_hi, -1, 2, -1, 4), invert=False)
        iso = iso.extract_surface(algorithm="dataset_surface")
        if iso.n_points == 0 or "vorticity" not in iso.point_data:
            continue
        iso["wx"] = np.asarray(iso["vorticity"])[:, 0]
        parts.append(iso)
    if not parts:
        return pv.PolyData()
    s = parts[0].merge(parts[1:]) if len(parts) > 1 else parts[0]
    s = s.extract_surface(algorithm="dataset_surface")
    m = s.reflect((0, 1, 0), point=(0, 0, 0))
    m["wx"] = -np.asarray(m["wx"])           # mirror flips the sense of rotation
    return s.merge(m)


def still_vortices(data):
    iso = vortex_surfaces(data)
    imgs = []
    for view in ("front", "low rear"):
        p = plotter((1600, 760))
        if view == "front":
            add_ground(p)
        add_car(p, data)
        if iso.n_points:
            p.add_mesh(iso, scalars="wx", cmap=cmap("wx"), clim=CLIM["wx"], show_scalar_bar=False, opacity=0.85,
                       smooth_shading=True, specular=0.3)
        if view == "front":
            p.camera.position, p.camera.focal_point, p.camera.up = (-3.2, -5.4, 3.4), (2.6, 0.0, 0.55), (0, 0, 1)
            p.camera.view_angle = 38
        else:
            p.camera.position, p.camera.focal_point, p.camera.up = (5.0, -2.6, -1.7), (1.3, 0.0, 0.45), (0, 0, 1)
            p.camera.view_angle = 46
        imgs.append(shot(p))
    img = stack(imgs, ["three-quarter front view: front-wing, wheel and rear-wing tip vortices",
                       "from below and behind (ground not drawn): floor, diffuser and wheel vortices"])
    bar = colorbar_strip("wx", "streamwise vorticity (1/s); red and blue = opposite sense of rotation", 1600)
    out = frame_with_text(img, f"{data['title']}: vortices (Q-criterion iso-surfaces)",
                          f"Surfaces where the Q-criterion (rotation stronger than strain) is {Q_LEVEL:.0f} 1/s^2 around "
                          f"the car (12.5 mm grid) and {Q_LEVEL / WAKE_Q_DIV:.0f} 1/s^2 in the wake (30 mm grid, where "
                          "vortices are smeared), blanked within 2 grid cells of a wall. " + CAPTION, bar)
    return save(out, f"{data['label']}_vortices.png")


def car_outline_yz(data):
    """Frontal silhouette of the car (both halves) as (y, z) mask for the wake pictures."""
    P = np.asarray(mirrored(data["car"]).points)
    yb, zb = np.linspace(-1.0, 1.0, 201), np.linspace(0, 1.5, 151)
    H, _, _ = np.histogram2d(P[:, 1], P[:, 2], bins=[yb, zb])
    from scipy.ndimage import binary_closing, binary_fill_holes
    m = binary_fill_holes(binary_closing(H > 0, iterations=2))
    return (yb[:-1] + yb[1:]) / 2, (zb[:-1] + zb[1:]) / 2, m


def wake_field(data, x, name, grid=None):
    g = data[grid] if grid else (data["near"] if x < 3.3 else data["wake"])
    y, z, v = slice_yz(g, x, name if name != "deficit" else "U")
    if name == "deficit":
        v = 1.0 - v[..., 0] / U_INF
        valid = slice_yz(g, x, "valid")[2] > 0
        v = np.where(valid, v, np.nan)
    elif name == "k":
        valid = slice_yz(g, x, "valid")[2] > 0
        v = np.where(valid, v, np.nan)
    yy = np.r_[-y[::-1], y]
    vv = np.r_[v[::-1], v]
    return yy, z, vv


def draw_wake_panel(ax, data, x, name, outline=None, boxes=True, ylim=(-1.6, 1.6), zlim=(0, 2.8)):
    # the 30 mm wake grid everywhere; next to the car the 12.5 mm grid on top of it
    # (it covers only |Y| < 0.95 m, Z < 1.8 m)
    for grid in (("wake", "near") if x < 3.3 else ("wake",)):
        yy, z, vv = wake_field(data, x, name, grid)
        im = ax.imshow(vv.T, origin="lower", extent=(yy[0], yy[-1], z[0], z[-1]), cmap=cmap(name),
                       vmin=CLIM[name][0], vmax=CLIM[name][1], interpolation="bilinear", aspect="equal")
    if outline is not None:
        oy, oz, m = outline
        ax.contour(oy, oz, m.T.astype(float), levels=[0.5], colors="white", linewidths=0.9, linestyles="--")
    if boxes:
        for (hw, z0, z1), c in zip(BOX_REGIONS.values(), ("cyan", "lime")):
            ax.add_patch(__import__("matplotlib.patches").patches.Rectangle((-hw, z0), 2 * hw, z1 - z0, fill=False,
                                                                           ec=c, lw=1.0, ls=":"))
    ax.set_xlim(*ylim); ax.set_ylim(*zlim)
    ax.tick_params(labelsize=8)
    return im


def fig_to_img(fig):
    import io
    from PIL import Image
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=fig.dpi)
    buf.seek(0)
    return Image.open(buf).convert("RGB")


def still_wake(data):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    outline = car_outline_yz(data)
    fig, axs = plt.subplots(2, 3, figsize=(16, 8.6), dpi=100, constrained_layout=True)
    for j, n in enumerate(SLICES_L):
        x = slice_x(n)
        for i, name in enumerate(("deficit", "k")):
            im = draw_wake_panel(axs[i, j], data, x, name, outline)
            axs[i, j].set_title(f"{n:g} car length{'s' if n > 1 else ''} behind the rear axle (X {x:.2f} m)",
                                fontsize=10)
            if j == 0:
                axs[i, j].set_ylabel("Z (m)")
            if i == 1:
                axs[i, j].set_xlabel("Y (m), looking forward at the back of the car")
            if j == 2:
                fig.colorbar(im, ax=axs[i, :], shrink=0.9, pad=0.01,
                             label="velocity deficit 1 - u/U" if name == "deficit" else "turbulence kinetic energy k (m2/s2)")
    img = fig_to_img(fig)
    plt.close(fig)
    out = frame_with_text(img, f"{data['title']}: wake slices",
                          "Top: velocity deficit 1 - u/U (0 = free stream). Bottom: turbulence kinetic energy. "
                          "White dashed: the car's frontal outline. Dotted boxes: the following car's windows used in "
                          "cfd/results/wake_boxes.csv (cyan: front wing and wheels, Z 0 to 0.5 m; green: rear wing, "
                          "Z 1.0 to 1.5 m). " + CAPTION)
    return save(out, f"{data['label']}_wake_slices.png")


def symmetry_panel(ax, data, grid_name, xlim, zlim, density=1.6):
    g = data[grid_name]
    x, z, U = slice_xz(g, "U", j=0)
    _, _, val = slice_xz(g, "valid", j=0)
    sp = np.linalg.norm(U, axis=-1) / U_INF
    sp = np.where(val > 0, sp, np.nan)
    im = ax.imshow(sp.T, origin="lower", extent=(x[0], x[-1], z[0], z[-1]), cmap=cmap("speed"),
                   vmin=CLIM["speed"][0], vmax=CLIM["speed"][1], interpolation="bilinear", aspect="equal")
    solid = np.where(val > 0, np.nan, 1.0)
    ax.imshow(solid.T, origin="lower", extent=(x[0], x[-1], z[0], z[-1]), cmap="Greys", vmin=0, vmax=1.6,
              interpolation="nearest", aspect="equal")
    ix = (x >= xlim[0]) & (x <= xlim[1])
    iz = (z >= zlim[0]) & (z <= zlim[1])
    ax.streamplot(x[ix], z[iz], U[np.ix_(ix, iz)][..., 0].T, U[np.ix_(ix, iz)][..., 2].T, color="white",
                  linewidth=0.5, density=density, arrowsize=0.6)
    ax.set_xlim(*xlim); ax.set_ylim(*zlim)
    ax.set_xlabel("X (m), flow left to right; front axle at 0"); ax.set_ylabel("Z (m)")
    return im


def still_symmetry(data):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axs = plt.subplots(2, 1, figsize=(16, 9.4), dpi=100, gridspec_kw={"height_ratios": [1.15, 1]},
                            constrained_layout=True)
    im = symmetry_panel(axs[0], data, "near", (-1.3, 3.4), (0, 1.55), density=2.2)
    axs[0].set_title("around the car (12.5 mm grid)", fontsize=10)
    symmetry_panel(axs[1], data, "wake", (-1.3, 11.2), (0, 2.8), density=1.4)
    axs[1].set_title("to 3 car lengths behind the rear axle (30 mm grid)", fontsize=10)
    for n in SLICES_L:
        axs[1].axvline(slice_x(n), color="black", lw=0.9, ls="--", alpha=0.7)
    fig.colorbar(im, ax=axs, shrink=0.8, pad=0.01, label="speed / free stream")
    img = fig_to_img(fig)
    plt.close(fig)
    out = frame_with_text(img, f"{data['title']}: flow on the centre plane (Y = 0)",
                          "Speed on the symmetry plane with in-plane streamlines (white); grey = inside the car or the "
                          "driver. Dashed lines: 1, 2 and 3 car lengths behind the rear axle. " + CAPTION)
    return save(out, f"{data['label']}_symmetry.png")


def stills(data):
    log(f"stills {data['label']} (run {data['run']})")
    still_surface(data)
    still_streamlines(data)
    still_vortices(data)
    still_wake(data)
    still_symmetry(data)


# ---------------------------------------------------------------------------- animations
def anim_orbit(data, frames=240):
    mv = Movie(OUT / f"{data['label']}_orbit", fps=24, gif_width=560, gif_every=4, crf=28)
    lines = stream_lines(data)
    bar = colorbar_strip("speed", "speed / free stream (20 m/s)", 1280)
    p = plotter((1280, 720))
    add_ground(p)
    add_car(p, data)
    scene_streamlines(data, p, lines=lines)
    c = np.array([1.6, 0.0, 0.5])
    r, hgt = 7.2, 2.6
    for k in range(frames):
        a = math_rad(-120 + 360.0 * k / frames)
        p.camera.position = c + np.array([r * np.cos(a), r * np.sin(a), hgt])
        p.camera.focal_point, p.camera.up = c, (0, 0, 1)
        p.camera.view_angle = 32
        p.render()
        mv.add(frame_with_text(p.screenshot(return_img=True), f"{data['title']}: streamlines, orbit",
                               "Streamlines from a rake ahead of the car, coloured by speed. " + CAPTION, bar))
    p.close()
    for f in mv.write():
        log("   wrote", f.relative_to(OUT.parents[2]))


def math_rad(deg):
    return np.deg2rad(deg)


def anim_sweep(data, frames=150):
    """A slice of velocity deficit moving from the rear wing back to 3 car lengths;
    3D view on the left, deficit and k on the slice on the right."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from PIL import Image
    import pyvista as pv
    mv = Movie(OUT / f"{data['label']}_sweep", fps=24)
    outline = car_outline_yz(data)
    xs = np.linspace(2.2, slice_x(3.0), frames)
    p = plotter((900, 640))
    add_ground(p)
    add_car(p, data)
    p.camera.position, p.camera.focal_point, p.camera.up = (13.5, -9.5, 5.5), (5.0, 0, 0.6), (0, 0, 1)
    p.camera.view_angle = 34
    actor = None
    for k, x in enumerate(xs):
        yy, z, vv = wake_field(data, x, "deficit", "wake")      # same plane size all the way back
        Y, Z = np.meshgrid(yy, z, indexing="ij")
        sg = pv.StructuredGrid(np.full_like(Y, x), Y, Z)
        sg["deficit"] = np.nan_to_num(vv, nan=0.0).ravel(order="F")
        if actor is not None:
            p.remove_actor(actor)
        actor = p.add_mesh(sg, scalars="deficit", cmap=cmap("deficit"), clim=CLIM["deficit"], show_scalar_bar=False,
                           opacity=0.92, lighting=False)
        p.render()
        left = Image.fromarray(p.screenshot(return_img=True))
        fig, axs = plt.subplots(2, 1, figsize=(5.6, 6.4), dpi=100, constrained_layout=True)
        n_l = (x - 1.55) / 2.95
        for ax, name, lab in ((axs[0], "deficit", "velocity deficit 1 - u/U"), (axs[1], "k", "k (m2/s2)")):
            im = draw_wake_panel(ax, data, x, name, outline)
            fig.colorbar(im, ax=ax, shrink=0.85, pad=0.01, label=lab)
            ax.set_ylabel("Z (m)")
        axs[0].set_title(f"X {x:.2f} m = {n_l:.2f} car lengths behind the rear axle", fontsize=10)
        axs[1].set_xlabel("Y (m)")
        right = fig_to_img(fig)
        plt.close(fig)
        right = right.resize((int(right.width * left.height / right.height), left.height))
        frame = Image.new("RGB", (left.width + right.width, left.height), "white")
        frame.paste(left, (0, 0)); frame.paste(right, (left.width, 0))
        mv.add(frame_with_text(frame, f"{data['title']}: wake slice sweep",
                               "A slice moving from the rear wing back to 3 car lengths. Dotted boxes: the following "
                               "car's windows (front wing and wheels; rear wing). " + CAPTION))
    p.close()
    for f in mv.write():
        log("   wrote", f.relative_to(OUT.parents[2]))


def anim_buildup(data, frames=168, hold=36):
    mv = Movie(OUT / f"{data['label']}_buildup", fps=24)
    lines = stream_lines(data)
    bar = colorbar_strip("speed", "speed / free stream (20 m/s)", 1280)
    xs = np.r_[np.linspace(-1.3, 11.0, frames), np.full(hold, 11.0)]
    for x in xs:
        p = plotter((1280, 720))
        add_ground(p)
        add_car(p, data)
        scene_streamlines(data, p, x_max=x, lines=lines)
        p.camera.position, p.camera.focal_point, p.camera.up = (-3.5, -8.8, 4.6), (4.2, 0, 0.4), (0, 0, 1)
        p.camera.view_angle = 40
        mv.add(frame_with_text(shot(p), f"{data['title']}: flow build-up, front to back",
                               "Streamlines drawn up to a plane moving from the front to 3 car lengths behind the "
                               "rear axle, coloured by speed. " + CAPTION, bar))
    for f in mv.write():
        log("   wrote", f.relative_to(OUT.parents[2]))


def anims(data, only=None):
    log(f"animations {data['label']} (run {data['run']})")
    for name, f in (("orbit", anim_orbit), ("sweep", anim_sweep), ("buildup", anim_buildup)):
        if only in (None, name):
            f(data)


# ---------------------------------------------------------------------------- comparison A-D
def forces_by_part(run):
    """Full-car downforce by part (N), mean of the last 200 iterations of forces.out."""
    import re
    f = RESULTS / "runs" / run / "forces.out"
    head = re.findall(r'"([^"]+)"', f.read_text().splitlines()[2])          # column names
    a = np.loadtxt(f, skiprows=3)[-200:]
    col = {n: i for i, n in enumerate(head)}
    parts = {"front wing": "downforce_car_fw", "rear wing": "downforce_car_rw", "floor": "downforce_car_floor",
             "body": "downforce_car_body", "wheels": "downforce_wheels"}
    by = {k: (2 * float(a[:, col[n]].mean()) if n in col else 0.0) for k, n in parts.items()}   # A has no wings
    return by, 2 * float(a[:, col["downforce_total"]].mean()), 2 * float(a[:, col["drag_total"]].mean())


def compare(datas):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from PIL import Image
    log("compare A B C D")
    cols = []
    parts = {}
    for d in datas:
        parts[d["label"]] = forces_by_part(d["run"])
    vmax = max(max(v[0].values()) for v in parts.values()) * 1.15
    vmin = min(min(v[0].values()) for v in parts.values()) * 1.15
    for d in datas:
        views = surface_views(d, size=(900, 380))
        by, df, dr = parts[d["label"]]
        fig, axs = plt.subplots(3, 1, figsize=(6.0, 9.6), dpi=100, gridspec_kw={"height_ratios": [0.9, 1, 1]},
                                constrained_layout=True)
        ax = axs[0]
        names = list(by)
        ax.barh(names[::-1], [by[n] for n in names[::-1]], color=["#888", "#999", "#4a7", "#c44", "#36c"])
        ax.set_xlim(vmin, vmax); ax.axvline(0, color="k", lw=0.6)
        ax.set_title(f"downforce by part (N, full car, 20 m/s)\ntotal {df:.0f} N, drag {dr:.0f} N", fontsize=10)
        ax.tick_params(labelsize=9)
        outline = car_outline_yz(d)
        im1 = draw_wake_panel(axs[1], d, slice_x(1.0), "deficit", outline, ylim=(-1.4, 1.4), zlim=(0, 2.4))
        axs[1].set_title("velocity deficit at 1 car length", fontsize=10)
        fig.colorbar(im1, ax=axs[1], shrink=0.8, pad=0.01)
        im2 = draw_wake_panel(axs[2], d, slice_x(1.0), "k", outline, ylim=(-1.4, 1.4), zlim=(0, 2.4))
        axs[2].set_title("turbulence kinetic energy at 1 car length (m2/s2)", fontsize=10)
        fig.colorbar(im2, ax=axs[2], shrink=0.8, pad=0.01)
        chart = fig_to_img(fig)
        plt.close(fig)
        top = stack([views["underbody"], views["top"]], ["underbody Cp", "top Cp"], label_font=18)
        chart = chart.resize((top.width, int(chart.height * top.width / chart.width)))
        col = Image.new("RGB", (top.width, top.height + chart.height + 50), "white")
        from PIL import ImageDraw
        ImageDraw.Draw(col).text((12, 8), d["title"], fill="black", font=font(26, bold=True))
        col.paste(top, (0, 50)); col.paste(chart, (0, 50 + top.height))
        cols.append(col)
    w = sum(c.width for c in cols) + 10 * (len(cols) - 1)
    h = max(c.height for c in cols)
    img = Image.new("RGB", (w, h), "white")
    x = 0
    for c in cols:
        img.paste(c, (x, 0)); x += c.width + 10
    bar = colorbar_strip("Cp", "surface pressure coefficient Cp (blue = suction)", int(0.6 * img.width))
    out = frame_with_text(img, "Variants A, B, C, D side by side: where the downforce comes from, and the wake",
                          "Same colour scales in every column. Downforce by part from Fluent's force reports (mean of the "
                          "last 200 iterations). C is run CP (SolidWorks bodywork); A, B and D have the older CFD "
                          "bodywork. " + CAPTION, bar)
    save(out, "compare_ABCD.png")
    compare_video(datas, parts)


def compare_video(datas, parts, frames=150):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    log("   compare video")
    mv = Movie(OUT / "compare_ABCD", fps=24, gif_width=960)
    unders = {d["label"]: surface_views(d, size=(700, 300))["underbody"] for d in datas}
    outlines = {d["label"]: car_outline_yz(d) for d in datas}
    xs = np.linspace(2.2, slice_x(3.0), frames)
    for x in xs:
        fig, axs = plt.subplots(3, 4, figsize=(19.2, 10.0), dpi=100, gridspec_kw={"height_ratios": [0.62, 1, 1]})
        for j, d in enumerate(datas):
            by, df, dr = parts[d["label"]]
            axs[0, j].imshow(unders[d["label"]]); axs[0, j].axis("off")
            axs[0, j].set_title(f"{d['title']}\nunderbody Cp, downforce {df:.0f} N, drag {dr:.0f} N", fontsize=10)
            for i, name in ((1, "deficit"), (2, "k")):
                draw_wake_panel(axs[i, j], d, x, name, outlines[d["label"]], ylim=(-1.4, 1.4), zlim=(0, 2.4))
        n_l = (x - 1.55) / 2.95
        axs[1, 0].set_ylabel("velocity deficit\nZ (m)")
        axs[2, 0].set_ylabel("k (0 to 8 m2/s2)\nZ (m)")
        fig.suptitle(f"wake slice at X {x:.2f} m = {n_l:.2f} car lengths behind the rear axle "
                     f"(deficit 0 to 0.6, k 0 to 8 m2/s2, same scales for all)", fontsize=12)
        fig.subplots_adjust(left=0.05, right=0.99, top=0.88, bottom=0.04, wspace=0.12, hspace=0.25)
        img = fig_to_img(fig)
        plt.close(fig)
        mv.add(frame_with_text(img, "A, B, C, D: downforce distribution and the wake",
                               "Top: surface pressure under the car (blue = suction, Cp -3 to +1). Middle and bottom: a "
                               "wake slice moving back from the rear wing. " + CAPTION))
    for f in mv.write():
        log("   wrote", f.relative_to(OUT.parents[2]))
