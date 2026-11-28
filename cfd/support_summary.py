#!/usr/bin/env python3
"""One-page summary image of the wing-support study, for posting (media/cfd/supports/supports_summary.png).

    .venv/Scripts/python cfd/support_summary.py
    .venv/Scripts/python cfd/support_summary.py --selftest

Built from the two film stills (cfd/vis_supports.py films) and the numbers in cfd/results/support_table.csv
and media/support_sensitivity_laps.csv; no number is typed in by hand. 1200 x 1500 px, light background.
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "media" / "cfd" / "supports"
TABLE = ROOT / "cfd" / "results" / "support_table.csv"
LAPS = ROOT / "media" / "support_sensitivity_laps.csv"
SPREAD = 2.2
INK, INK2, MUTED, SURF, RULE = "#0b0b0b", "#52514e", "#8d8c87", "#fcfcfb", "#e4e3df"


def table():
    return {r["run"]: r for r in csv.DictReader(TABLE.open())}


def f(r, k):
    try:
        return float(r[k])
    except (KeyError, ValueError, TypeError):
        return float("nan")


def pct(a, b):
    return 100.0 * (a - b) / b


def claim(d):
    """A total-force change is only claimed outside CP's 2.2 % run-to-run spread."""
    return abs(d) > SPREAD


def lines(T, laps):
    cp, FF = T["CP_bl1"], T["CPFF_bl1"]
    rows = [
        ("Rear support drag, per support", f"{f(cp, 'rws_drag_N_half'):.2f} N", f"{f(FF, 'rws_drag_N_half'):.2f} N",
         f"{pct(f(FF, 'rws_drag_N_half'), f(cp, 'rws_drag_N_half')):+.0f} %"),
        ("Front support drag, per support", f"{f(cp, 'fws_drag_N_half'):.2f} N", f"{f(FF, 'fws_drag_N_half'):.2f} N",
         f"{pct(f(FF, 'fws_drag_N_half'), f(cp, 'fws_drag_N_half')):+.0f} %"),
    ]
    for k, name in (("ClA", "Downforce ClA (whole car)"), ("CdA", "Drag CdA (whole car)")):
        d = pct(f(FF, k), f(cp, k))
        rows.append((name, f"{f(cp, k):.2f} m²", f"{f(FF, k):.2f} m²", f"{d:+.1f} %" + ("" if claim(d) else " (noise)")))
    rows.append(("Front share of downforce", f"{f(cp, 'aero_front'):.3f}", f"{f(FF, 'aero_front'):.3f}",
                 f"{f(FF, 'aero_front') - f(cp, 'aero_front'):+.3f}"))
    for track, name in (("autocross", "Autocross lap (four-wheel sim)"), ("fast_circuit", "Fast-circuit lap (four-wheel sim)")):
        r = next(x for x in laps if x["track"] == track and x["model"] == "four-wheel")
        d = float(r["diff_CPFF_s"])
        rows.append((name, f"{float(r['t_CP_bl1_s']):.2f} s", f"{float(r['t_CPFF_s']):.2f} s",
                     f"{d:+.2f} s" + ("" if r["beyond_band_CPFF"] == "1" else " (in band)")))
    return rows


def main():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.image as mpimg
    T = table()
    laps = list(csv.DictReader(LAPS.open()))
    rows = lines(T, laps)
    W, H, dpi = 1200, 1500, 100
    fig = plt.figure(figsize=(W / dpi, H / dpi), dpi=dpi, facecolor=SURF)

    def text(x, y, s, **kw):
        fig.text(x / W, 1 - y / H, s, va="top", **kw)

    text(48, 36, "Wing supports: lens struts instead of flat plates", fontsize=25, weight="bold", color=INK)
    text(48, 84, "Formula single-seater, half-car CFD (Fluent, steady RANS k-ω SST, 20 m/s). The reference car uses flat 16 mm plates to hold\n"
                 "both wings; CPFF swaps them for lens-section struts with a round front edge (J front, F rear), same size and place.",
         fontsize=11.5, color=INK2, linespacing=1.45)
    y = 150
    for stem, h, cap in (("supports_rear_still.png", 520, "Rear-wing support: flat plate (left) vs the lens struts E, F, H. Side view above, section below."),
                         ("supports_front_still.png", 420, "Front-wing support: flat plate (left) vs lens J. Colour = local speed.")):
        p = OUT / stem
        if p.exists() and p.stat().st_size:
            img = mpimg.imread(p)
            ih, iw = img.shape[:2]
            w = min(W - 96, h * iw / ih)
            hh = w * ih / iw
            ax = fig.add_axes([(W - w) / 2 / W, 1 - (y + hh) / H, w / W, hh / H])
            ax.imshow(img)
            ax.axis("off")
            y += hh + 6
        text(48, y, cap, fontsize=10.5, color=MUTED)
        y += 34

    # numbers
    cols = (48, 560, 760, 960)
    text(cols[0], y, "Per support / whole car", fontsize=11, color=MUTED)
    text(cols[1], y, "Flat plates (CP_bl1)", fontsize=11, color=MUTED)
    text(cols[2], y, "Lens struts (CPFF)", fontsize=11, color=MUTED)
    text(cols[3], y, "Change", fontsize=11, color=MUTED)
    y += 26
    for name, a, b, d in rows:
        fig.add_artist(plt.Line2D([48 / W, (W - 48) / W], [1 - (y - 4) / H] * 2, color=RULE, lw=1))
        text(cols[0], y + 4, name, fontsize=13, color=INK)
        text(cols[1], y + 4, a, fontsize=13, color=INK2)
        text(cols[2], y + 4, b, fontsize=13, color=INK2)
        text(cols[3], y + 4, d, fontsize=13, color=INK, weight="bold")
        y += 36
    text(48, y + 8,
         "All rows compare CP_bl1 with CPFF (J front + F rear, both changed at once); support drag is per support, from the half-car model.\n"
         f"Honest limits: one steady run per variant; CP's own run-to-run spread is {SPREAD} % in ClA, and a repeat with a tiny mesh change moved\n"
         "ClA by 0.9 %. Changes inside that are marked noise. CFD only: the CAD and release v1.0.0 have no supports. Lap times from the\n"
         "project's MATLAB lap simulator with the CFD forces, not a test.",
         fontsize=10, color=MUTED, linespacing=1.5)
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / "supports_summary.png"
    fig.savefig(out, dpi=dpi, facecolor=SURF)
    plt.close(fig)
    print(f"wrote {out} ({out.stat().st_size / 1e3:.0f} kB)")


def selftest():
    ok = True
    ok &= abs(pct(110, 100) - 10.0) < 1e-12 and abs(pct(0.41, 4.34) + 90.553) < 1e-2
    ok &= claim(2.3) and not claim(-2.2) and not claim(1.0) and claim(-3.9)
    T = table()
    rows = lines(T, list(csv.DictReader(LAPS.open())))
    ok &= len(rows) == 7 and rows[0][1] == "4.34 N" and rows[0][2] == "0.43 N"
    print("selftest", "PASS" if ok else "FAIL")
    return ok


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(0 if selftest() else 1)
    main()
