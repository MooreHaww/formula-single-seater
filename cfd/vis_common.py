"""Shared helpers for cfd/visualise.py: streamline tracing across the two cached
grids, mirroring the half car, captions, colour bars and MP4/GIF writing."""
from __future__ import annotations

import numpy as np

from visualise import CAPTION, CLIM, CMAP, GRIDS, U_INF

FONT_DIRS = ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf")
FONT_BOLD = ("C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf")


# ---------------------------------------------------------------------------- streamlines
def _lines_of(poly):
    """pyvista PolyData of polylines -> list of point-index arrays."""
    out, conn, i = [], np.asarray(poly.lines), 0
    while i < len(conn):
        n = conn[i]
        out.append(conn[i + 1:i + 1 + n])
        i += n + 1
    return out


def _trace(grid, seeds, max_length):
    import pyvista as pv
    src = pv.PolyData(np.asarray(seeds, dtype=float))
    sl = grid.streamlines_from_source(src, vectors="U", integration_direction="forward", integrator_type=45,
                                      initial_step_length=0.2, step_unit="cl", min_step_length=0.01,
                                      max_step_length=0.5, max_steps=40000, terminal_speed=0.5,
                                      max_length=max_length)
    res = []
    if sl.n_points == 0:
        return res
    P, T = np.asarray(sl.points), np.asarray(sl["IntegrationTime"])
    for idx in _lines_of(sl):
        if len(idx) >= 2:
            res.append((P[idx], T[idx]))
    return res


def trace(data, seeds, x_end=11.0, max_length=30.0):
    """Streamlines from seeds: on the fine near grid first, continued on the wake grid
    from where they leave it (behind the car or out of its top). Returns a list of
    (points (n,3), time (n,), speed/U_inf (n,))."""
    near, wake = data["near"], data["wake"]
    (nx0, ny0, nz0), h, (nx1, ny1, nz1) = GRIDS["near"]
    first = _trace(near, seeds, max_length)
    lines, cont, cont_from = [], [], []
    for P, T in first:
        e = P[-1]
        left_box = e[0] > nx1 - 3 * h or e[2] > nz1 - 3 * h or e[1] > ny1 - 3 * h
        if left_box and e[0] < x_end:
            cont.append(e)
            cont_from.append((P, T))
        else:
            lines.append((P, T))
    if cont:
        second = _trace(wake, cont, max_length)
        # match each continuation to its start point
        starts = np.array([s[0][0] for s in second]) if second else np.zeros((0, 3))
        for (P, T), e in zip(cont_from, cont):
            if len(starts):
                j = int(np.argmin(np.linalg.norm(starts - e, axis=1)))
                if np.linalg.norm(starts[j] - e) < 1e-6:
                    P2, T2 = second[j]
                    P, T = np.vstack([P, P2[1:]]), np.concatenate([T, T[-1] + T2[1:]])
            lines.append((P, T))
    out = []
    for P, T in lines:
        keep = P[:, 0] <= x_end
        if keep.sum() < 2:
            continue
        P, T = P[keep], T[keep]
        seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
        dt = np.diff(T)
        spd = np.r_[seg / np.maximum(dt, 1e-9), 0.0]
        spd[-1] = spd[-2] if len(spd) > 1 else 0.0
        out.append((P, T, spd / U_INF))
    return out


def mirror_lines(lines):
    m = []
    for P, T, s in lines:
        Q = P.copy()
        Q[:, 1] *= -1
        m.append((Q, T, s))
    return lines + m


def lines_polydata(lines, x_max=None):
    """List of (P, T, s) -> PolyData polylines with point arrays 'speed' and 'time'.
    x_max clips each line at that X (for the build-up animation)."""
    import pyvista as pv
    pts, conn, spd, tim = [], [], [], []
    off = 0
    for P, T, s in lines:
        if x_max is not None:
            k = int(np.argmax(P[:, 0] > x_max)) if (P[:, 0] > x_max).any() else len(P)
            P, T, s = P[:k], T[:k], s[:k]
        if len(P) < 2:
            continue
        pts.append(P); spd.append(s); tim.append(T)
        conn.append(np.r_[len(P), np.arange(off, off + len(P))])
        off += len(P)
    if not pts:
        return pv.PolyData()
    poly = pv.PolyData(np.vstack(pts), lines=np.concatenate(conn))
    poly["speed"] = np.concatenate(spd).astype(np.float32)
    poly["time"] = np.concatenate(tim).astype(np.float32)
    return poly


def rake(x, y_range, z_range, ny, nz):
    ys, zs = np.linspace(*y_range, ny), np.linspace(*z_range, nz)
    Y, Z = np.meshgrid(ys, zs, indexing="ij")
    return np.c_[np.full(Y.size, x), Y.ravel(), Z.ravel()]


# ---------------------------------------------------------------------------- geometry
def mirrored(mesh):
    """Half-car mesh -> full car (mirror about Y = 0), cell data kept."""
    m = mesh.reflect((0, 1, 0), point=(0, 0, 0))
    return mesh.merge(m)


def slice_yz(grid, x, name):
    """Values on the plane X = x of an ImageData grid, nearest grid plane;
    returns (y, z, values[ny, nz]) for the half car (Y >= 0)."""
    (ox, oy, oz), h = grid.origin, grid.spacing[0]
    nx, ny, nz = grid.dimensions
    i = int(round((x - ox) / h))
    i = min(max(i, 0), nx - 1)
    a = np.asarray(grid[name]).reshape((nz, ny, nx) + ((3,) if np.asarray(grid[name]).ndim == 2 else ()))
    v = a[:, :, i]
    y = oy + h * np.arange(ny)
    z = oz + h * np.arange(nz)
    return y, z, np.swapaxes(v, 0, 1)            # [ny, nz, ...]


def slice_xz(grid, name, j=0):
    """Values on the grid plane Y index j (j = 0 is next to the symmetry plane)."""
    (ox, oy, oz), h = grid.origin, grid.spacing[0]
    nx, ny, nz = grid.dimensions
    arr = np.asarray(grid[name])
    a = arr.reshape((nz, ny, nx) + ((3,) if arr.ndim == 2 else ()))
    v = a[:, j, :]
    return ox + h * np.arange(nx), oz + h * np.arange(nz), np.swapaxes(v, 0, 1)   # [nx, nz, ...]


def cmap(key):
    """Colour map for one of the common scales. Cp: blue (suction) - white at Cp = 0 -
    red (pressure), with white placed at 0 on the asymmetric -3..+1 scale."""
    import matplotlib
    from matplotlib.colors import LinearSegmentedColormap
    if key == "Cp":
        lo, hi = CLIM["Cp"]
        w = (0.0 - lo) / (hi - lo)
        return LinearSegmentedColormap.from_list("cp0", [(0.0, "#08306b"), (0.35 * w, "#2171b5"), (0.8 * w, "#c6dbef"),
                                                         (w, "#ffffff"), (w + 0.4 * (1 - w), "#fc9272"),
                                                         (1.0, "#99000d")])
    return matplotlib.colormaps[CMAP[key]]


# ---------------------------------------------------------------------------- 2D panels and captions
def font(size, bold=False):
    from PIL import ImageFont
    for f in (FONT_BOLD if bold else FONT_DIRS):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def colorbar_strip(key, label, width, height=None, dark=False):
    """Horizontal colour bar for one of the common scales, as a PIL image; text grows
    with the width so it stays readable on the wide comparison picture."""
    from PIL import Image, ImageDraw
    cm = cmap(key)
    lo, hi = CLIM[key]
    fs = max(15, width // 110)
    height = height or int(5.5 * fs)
    fg = (225, 225, 225) if dark else "black"
    img = Image.new("RGB", (width, height), (20, 20, 24) if dark else "white")
    d = ImageDraw.Draw(img)
    x0, x1, y0, y1 = 60, width - 60, 8, 8 + int(1.5 * fs)
    grad = (np.array([cm(t)[:3] for t in np.linspace(0, 1, x1 - x0)]) * 255).astype(np.uint8)
    img.paste(Image.fromarray(np.repeat(grad[None, :, :], y1 - y0, axis=0)), (x0, y0))
    d.rectangle([x0, y0, x1, y1], outline=fg)
    f = font(fs)
    for t in np.linspace(lo, hi, 5):
        xx = x0 + (t - lo) / (hi - lo) * (x1 - x0)
        d.line([xx, y1, xx, y1 + 5], fill=fg)
        s = f"{t:g}"
        d.text((xx - d.textlength(s, font=f) / 2, y1 + 6), s, fill=fg, font=f)
    d.text((x0 + (x1 - x0) / 2 - d.textlength(label, font=f) / 2, y1 + 8 + int(1.6 * fs)), label, fill=fg, font=f)
    return img


def frame_with_text(img, title, caption=CAPTION, bar=None, dark=False):
    """Add a title bar above and a caption (and optional colour bar image) below."""
    from PIL import Image, ImageDraw
    if isinstance(img, np.ndarray):
        img = Image.fromarray(img)
    w = img.width
    fg, bg = ("white", (20, 20, 24)) if dark else ("black", "white")
    ft, fc = font(max(18, w // 60), bold=True), font(max(13, w // 100))
    # wrap the caption to the width
    words, lines, cur = caption.split(), [], ""
    tmp = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    for wd in words:
        t = (cur + " " + wd).strip()
        if tmp.textlength(t, font=fc) > w - 30:
            lines.append(cur); cur = wd
        else:
            cur = t
    lines.append(cur)
    th = int(ft.size * 1.3) + 16             # room for descenders
    ch = (fc.size + 6) * len(lines) + 12
    bh = bar.height if bar is not None else 0
    out = Image.new("RGB", (w, th + img.height + bh + ch), bg)
    d = ImageDraw.Draw(out)
    d.text((15, 8), title, fill=fg, font=ft)
    out.paste(img, (0, th))
    if bar is not None:
        out.paste(bar, ((w - bar.width) // 2, th + img.height))
    y = th + img.height + bh + 6
    for ln in lines:
        d.text((15, y), ln, fill=fg if not dark else (210, 210, 210), font=fc)
        y += fc.size + 6
    return out


def even(img):
    """Pad to even width and height (H.264 needs them)."""
    from PIL import Image
    w, h = img.size
    if w % 2 == 0 and h % 2 == 0:
        return img
    out = Image.new("RGB", (w + w % 2, h + h % 2), img.getpixel((0, 0)))
    out.paste(img, (0, 0))
    return out


class Movie:
    """Stream frames into an MP4 (H.264, full size) and keep every `gif_every`-th frame,
    shrunk to `gif_width`, for a GIF (128 colours). Frames never pile up in memory."""

    def __init__(self, stem, fps=24, gif_width=640, gif_every=2, crf=26):
        self.stem, self.fps, self.gw, self.ge, self.crf = stem, fps, gif_width, gif_every, crf
        self.small, self.n, self.size, self.w = [], 0, None, None

    def add(self, img):
        import imageio.v2 as iio
        from PIL import Image
        if isinstance(img, np.ndarray):
            img = Image.fromarray(img)
        img = even(img.convert("RGB"))
        if self.size is None:
            self.size = img.size
            # imageio-ffmpeg already writes yuv420p (plays everywhere); CRF sets the size/quality
            self.w = iio.get_writer(self.stem.with_suffix(".mp4"), fps=self.fps, codec="libx264", quality=None,
                                    macro_block_size=2, ffmpeg_params=["-crf", str(self.crf), "-preset", "slow"])
        elif img.size != self.size:
            img = img.resize(self.size, Image.LANCZOS)
        self.w.append_data(np.asarray(img))
        if self.n % self.ge == 0:
            h = int(round(img.height * self.gw / img.width))
            self.small.append(img.resize((self.gw, h), Image.LANCZOS))
        self.n += 1

    def write(self):
        from PIL import Image
        self.w.close()
        gif = self.stem.with_suffix(".gif")
        pal = [f.convert("P", palette=Image.ADAPTIVE, colors=128) for f in self.small]
        pal[0].save(gif, save_all=True, append_images=pal[1:], duration=int(1000 * self.ge / self.fps), loop=0,
                    optimize=True)
        return self.stem.with_suffix(".mp4"), gif
