"""Assemble the car build-up film from the SolidWorks stills.

    .venv/Scripts/python tools/showcase_build.py            (run by: python tools/sw_run.py showcase-build)
    .venv/Scripts/python tools/showcase_build.py --selftest

Input: media/showcase/frames_build/*.png and manifest.csv, written by the ShowcaseBuild step of the
SolidWorks harness (one still per stage, one fixed camera). Output:
    media/showcase/car_buildup.mp4   1280x720, 24 fps, H.264, under 10 MB
    media/showcase/car_buildup.gif   720x405, 12 fps, under 5 MB
    media/showcase/frames_build/film/*.png   the captioned film frames (git-ignored)

Every still is cropped to one 16:9 box around the whole scene (the union over all stills, with a margin),
held for its stage's time, cross-faded into the next, and captioned with its stage. ffmpeg is the one
inside .venv (imageio-ffmpeg). Exit 0 only if both files exist and are under their size limits.
"""
import csv
import glob
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "media", "showcase", "frames_build")
FILM = os.path.join(SRC, "film")
OUT = os.path.join(REPO, "media", "showcase")
FPS = 24
W, H = 1280, 720
FADE = 4                      # frames of cross-fade between stills
HOLD = {"empty": 18, "frame": 7, "rear_wing": 16}    # frames per still; anything else 14
FINAL_HOLD = 48               # 2 s on the finished car
MP4_LIMIT = 10 * 1024 * 1024
GIF_LIMIT = 5 * 1024 * 1024
TITLE = "Formula single-seater: SolidWorks build-up of the final car (CP with lens wing supports)"
FOOT = "CAD model, built by script from one parameter file. Virtual: nothing here was built or tested."


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def font(size, bold=False):
    for f in (("arialbd.ttf" if bold else "arial.ttf"), "segoeui.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default()


def crop_box(files, margin=0.06):
    """One 16:9 box (x0, y0, x1, y1) around the non-white pixels of every still."""
    x0 = y0 = 10 ** 9
    x1 = y1 = -1
    for f in files:
        a = np.asarray(Image.open(f).convert("L"))
        ys, xs = np.nonzero(a < 245)
        if len(xs) == 0:
            continue
        x0, x1, y0, y1 = min(x0, xs.min()), max(x1, xs.max()), min(y0, ys.min()), max(y1, ys.max())
    w, h = (x1 - x0) * (1 + 2 * margin), (y1 - y0) * (1 + 2 * margin)
    if w / h < 16 / 9:
        w = h * 16 / 9
    else:
        h = w * 9 / 16
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return box_in(cx, cy, w, h, Image.open(files[0]).size)


def box_in(cx, cy, w, h, size):
    """Shift a w x h box centred at (cx, cy) inside an image of `size` (it must fit)."""
    sw, sh = size
    if w > sw or h > sh:
        raise ValueError("crop %dx%d larger than the still %dx%d" % (w, h, sw, sh))
    x0 = min(max(cx - w / 2, 0), sw - w)
    y0 = min(max(cy - h / 2, 0), sh - h)
    return int(round(x0)), int(round(y0)), int(round(x0 + w)), int(round(y0 + h))


def caption(im, text, n_stage, n_total):
    d = ImageDraw.Draw(im, "RGBA")
    d.rectangle([0, 0, W, 46], fill=(255, 255, 255, 215))
    d.text((24, 11), TITLE, font=font(22, True), fill=(30, 30, 30))
    if text:
        f = font(34, True)
        tw = d.textlength(text, font=f)
        d.rounded_rectangle([24, H - 118, 24 + tw + 36, H - 62], 10, fill=(20, 40, 70, 225))
        d.text((42, H - 112), text, font=f, fill=(255, 255, 255))
        d.text((W - 150, H - 108), "%d / %d" % (n_stage, n_total), font=font(22), fill=(90, 90, 90))
    d.rectangle([0, H - 40, W, H], fill=(255, 255, 255, 215))
    d.text((24, H - 32), FOOT, font=font(19), fill=(70, 70, 70))
    return im


def build():
    rows = list(csv.DictReader(open(os.path.join(SRC, "manifest.csv"), encoding="utf-8")))
    rows = [r for r in rows if r["stage"] != "fit"]
    if len(rows) < 20:
        print("STOPPED: only %d stills in %s (run the ShowcaseBuild step first)" % (len(rows), SRC))
        return 2
    files = [os.path.join(SRC, r["file"]) for r in rows]
    box = crop_box(files)
    # stage numbers for the caption counter (the frame stills of one group share a stage)
    stages = []
    for r in rows:
        if not stages or stages[-1] != r["caption"]:
            stages.append(r["caption"])
    # pictures without captions: the cross-fade blends pictures only, and the incoming stage's caption is
    # drawn on top (blending captioned frames ghosted two captions into one, 2026-11-25)
    stills = [Image.open(f).convert("RGB").crop(box).resize((W, H), Image.LANCZOS) for f in files]
    if os.path.isdir(FILM):
        shutil.rmtree(FILM)
    os.makedirs(FILM)
    n = 0

    def put(im, r):
        nonlocal n
        caption(im.copy(), r["caption"], stages.index(r["caption"]) + 1, len(stages)).save(os.path.join(FILM, "%04d.png" % n))
        n += 1

    for i, (r, im) in enumerate(zip(rows, stills)):
        key = "frame" if r["stage"].startswith("frame_") else r["stage"]
        hold = HOLD.get(key, 14) + (FINAL_HOLD if i == len(rows) - 1 else 0)
        if i > 0:
            for k in range(1, FADE + 1):
                put(Image.blend(stills[i - 1], im, k / (FADE + 1)), r)
            hold -= FADE
        for _ in range(max(hold, 1)):
            put(im, r)
    seconds = n / FPS
    ff = ffmpeg()
    mp4 = os.path.join(OUT, "car_buildup.mp4")
    gif = os.path.join(OUT, "car_buildup.gif")
    pal = os.path.join(FILM, "palette.png")
    run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(FILM, "%04d.png"),
         "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", mp4])
    vf = "fps=12,scale=720:405:flags=lanczos"
    run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(FILM, "%04d.png"),
         "-vf", vf + ",palettegen=stats_mode=diff", pal])
    run([ff, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(FILM, "%04d.png"), "-i", pal,
         "-lavfi", vf + "[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4", gif])
    os.remove(pal)
    sm, sg = os.path.getsize(mp4), os.path.getsize(gif)
    ok = sm < MP4_LIMIT and sg < GIF_LIMIT
    print("%s  car build-up film: %d stills, %d frames at %d fps = %.1f s; crop %s of %s"
          % ("PASS" if ok else "FAIL", len(rows), n, FPS, seconds, box, Image.open(files[0]).size))
    print("  %s  %.2f MB (limit 10 MB)" % (mp4, sm / 2 ** 20))
    print("  %s  %.2f MB (limit 5 MB)" % (gif, sg / 2 ** 20))
    return 0 if ok else 1


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("ffmpeg failed: %s\n%s" % (" ".join(cmd[:6]), r.stderr[-2000:]))


def selftest():
    # box_in by hand: a 160 x 90 box centred at (20, 50) in a 400 x 300 image is shifted right to x 0..160
    ok = box_in(20, 50, 160, 90, (400, 300)) == (0, 5, 160, 95)
    # centred, no shift: (200, 150) -> 120..280, 105..195
    ok = ok and box_in(200, 150, 160, 90, (400, 300)) == (120, 105, 280, 195)
    # crop_box on a synthetic still: a black block at x 150..249, y 130..169 in 400 x 300; pixel spans
    # 99 x 39, widened 12 %: 110.9 x 43.7 -> 16:9 by width: h 62.4; centre (199.5, 149.5) -> (144, 118, 255, 181)
    tmp = os.path.join(OUT, "_selftest.png")
    os.makedirs(OUT, exist_ok=True)
    im = Image.new("RGB", (400, 300), "white")
    ImageDraw.Draw(im).rectangle([150, 130, 249, 169], fill="black")
    im.save(tmp)
    b = crop_box([tmp])
    os.remove(tmp)
    ok = ok and b == (144, 118, 255, 181)
    print("showcase_build self-test: %s (crop %s, hand (144, 118, 255, 181))" % ("PASS" if ok else "FAIL", b))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else build())
