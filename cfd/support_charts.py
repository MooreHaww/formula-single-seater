#!/usr/bin/env python3
"""Charts of the wing-support study (docs/wing_supports_plan.md), as tracked PNGs in media/cfd/supports/.

    .venv/Scripts/python cfd/support_charts.py            # reads the tables below, writes the three charts
    .venv/Scripts/python cfd/support_charts.py --selftest

Reads cfd/results/support_table.csv (cfd/support_table.py, first run = CP_bl1, the reference) and
media/support_sensitivity_laps.csv / _balance.csv (matlab/lapsim/support_sensitivity.m). Writes:
  chart_support_drag.png   drag of the support itself, half car (N): rear and front supports
  chart_totals.png         ClA, CdA and front share against CP_bl1, with CP's 2.2 % run-to-run spread
                           (light band) and the CP_bl1 repeat's change (darker band, CP_bl1r)
  chart_lap_balance.png    lap-time and cornering-balance differences CP_bl1 / CPF / CPFF with the
                           2.2 % band of support_sensitivity.m
Steady RANS, one run per variant: only differences outside the bands are claimed.
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "media" / "cfd" / "supports"
TABLE = ROOT / "cfd" / "results" / "support_table.csv"
LAPS = ROOT / "media" / "support_sensitivity_laps.csv"
BAL = ROOT / "media" / "support_sensitivity_balance.csv"
SPREAD = 2.2          # %, CP vs CP_bl1 ClA

# reference palette (dataviz skill, light mode): ink, recessive grid, reference grey, categorical slots in fixed order
INK, INK2, GRID, SURF = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
REF = "#8d8c87"                                  # the flat plate / CP_bl1 reference
SLOT = ["#2a78d6", "#eb6834", "#1baf7a"]         # blue, orange, aqua
BAND, BAND_REP = "#ecebe7", "#d6d5cf"

NAMES = {"CP_bl1": "CP_bl1, flat plates (reference)", "CP_bl1r": "CP_bl1r, repeat (mesh change)",
         "E_bl1": "E, rear lens", "F_bl1": "F (CPF), rear lens, round front edge", "G_bl1": "G, rear lens with ridges",
         "H_bl1": "H, rear lens, blunt tail", "J_bl1": "J, front lens, round front edge",
         "K_bl1": "K, front lens, pointed", "CPFF_bl1": "CPFF, J front + F rear",
         "CP_bl1ta": "CP_bl1ta, CP on mesh fix A", "G_bl1ta": "G (fix A), rear lens with ridges",
         "K_bl1tb": "K (fix B, no reference), front lens, pointed"}
FRONT_ONLY = ("J_bl1", "K_bl1", "K_bl1tb")          # rear support = CP's plate again
NO_TOTALS = ("K_bl1tb",)                            # mesh fix B: no reference meshes on it, totals not compared


def rows():
    return list(csv.DictReader(TABLE.open()))


def num(r, k):
    try:
        return float(r[k])
    except (KeyError, ValueError):
        return float("nan")


def style(ax):
    ax.set_facecolor(SURF)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color(INK2)
    ax.tick_params(colors=INK2, labelsize=9)
    ax.xaxis.grid(True, color=GRID, lw=0.8)
    ax.set_axisbelow(True)


def chart_support_drag(R, plt):
    """Two panels of horizontal bars: rear and front support drag (half car)."""
    rear = [(r["run"], num(r, "rws_drag_N_half"), r["rws_source"]) for r in R if r["run"] not in FRONT_ONLY]
    front = [(r["run"], num(r, "fws_drag_N_half"), r["fws_source"]) for r in R
             if r["run"] in ("CP_bl1", "CP_bl1r", "CP_bl1ta", "F_bl1", "J_bl1", "K_bl1", "K_bl1tb", "CPFF_bl1") and num(r, "fws_drag_N_half") == num(r, "fws_drag_N_half")]
    fig, axs = plt.subplots(1, 2, figsize=(12.5, 4.6), dpi=130, gridspec_kw={"width_ratios": [1.15, 1]})
    for ax, data, title in ((axs[0], rear, "Rear-wing supports"), (axs[1], front, "Front-wing supports")):
        style(ax)
        data = [d for d in data if d[1] == d[1]][::-1]
        labels = [("F_bl1 (CPF): flat front plate" if (title.startswith("Front") and d[0] == "F_bl1") else NAMES.get(d[0], d[0]))
                  for d in data]
        vals = [d[1] for d in data]
        flat = [("CP_bl1" in d[0]) or (title.startswith("Front") and d[0] == "F_bl1") or (title.startswith("Rear") and d[0] == "J_bl1") for d in data]
        cols = [REF if f else SLOT[0] for f in flat]
        bars = ax.barh(range(len(vals)), vals, height=0.55, color=cols, edgecolor=SURF, linewidth=2)
        for b, d in zip(bars, data):
            if d[0] in NO_TOTALS:
                b.set_hatch("////"); b.set_edgecolor(SURF)
        ax.set_yticks(range(len(vals)), labels, fontsize=9, color=INK)
        vmax = max(vals) * 1.22
        ax.set_xlim(0, vmax)
        for i, v in enumerate(vals):
            ax.text(v + vmax * 0.015, i, f"{v:.2f} N", va="center", fontsize=9, color=INK)
        ax.set_xlabel("drag of the support itself, half car (N), 20 m/s", color=INK2, fontsize=9)
        ax.set_title(title, loc="left", fontsize=11, color=INK, fontweight="bold")
    fig.suptitle("Wing supports: drag of the support itself (half-car CFD, steady RANS, one run per variant)",
                 x=0.01, ha="left", fontsize=12, color=INK)
    fig.text(0.01, 0.005, "Grey: CP's flat 16 mm plate (kept in that run). Blue: lens supports. Zone force (200-iteration mean) "
             "for the lens supports; the flat plate is picked out of the wing zone by per-face export (a snapshot).\n"
             "Fix A / B: local face size on the flap trailing edges (cfd/fluent_halfcar_setup.md). Hatched: K on fix B, which no "
             "reference meshes on. Only the ranking is trustworthy.", fontsize=8, color=INK2)
    fig.patch.set_facecolor(SURF)
    fig.tight_layout(rect=(0, 0.06, 1, 0.94))
    return save(fig, "chart_support_drag.png", plt)


def chart_totals(R, plt):
    """ClA, CdA (% vs CP_bl1) and front share (points vs CP_bl1) per run, with the bands."""
    ref = next(r for r in R if r["run"] == "CP_bl1")
    rep = next((r for r in R if r["run"] == "CP_bl1r"), None)
    runs = [r for r in R if r["run"] != "CP_bl1" and r["run"] not in NO_TOTALS][::-1]
    metrics = [("ClA", "total ClA vs CP_bl1 (%)", lambda r: 100 * (num(r, "ClA") / num(ref, "ClA") - 1), SPREAD),
               ("CdA", "total CdA vs CP_bl1 (%)", lambda r: 100 * (num(r, "CdA") / num(ref, "CdA") - 1), SPREAD),
               ("front", "front share vs CP_bl1 (points)", lambda r: 100 * (num(r, "aero_front") - num(ref, "aero_front")),
                SPREAD / 100 * num(ref, "aero_front") * 100)]
    fig, axs = plt.subplots(1, 3, figsize=(13.5, 4.8), dpi=130, sharey=True)
    for ax, (key, lab, f, band) in zip(axs, metrics):
        style(ax)
        ax.axvspan(-band, band, color=BAND, zorder=0)
        if rep is not None:
            rb = abs(f(rep))
            ax.axvspan(-rb, rb, color=BAND_REP, zorder=0)
        ax.axvline(0, color=INK2, lw=0.8)
        for i, r in enumerate(runs):
            v = f(r)
            out = abs(v) > band
            c = REF if r["run"] in ("CP_bl1r", "CP_bl1ta") else SLOT[0]
            ax.plot([v], [i], "o", ms=8, mfc=c if out else SURF, mec=c, mew=2, zorder=3)
            ax.text(v, i + 0.28, f"{v:+.1f}", ha="center", fontsize=8, color=INK)
        lim = max(max(abs(f(r)) for r in runs), band) * 1.35
        ax.set_xlim(-lim, lim)
        ax.set_ylim(-0.6, len(runs) - 0.2)
        ax.set_xlabel(lab, color=INK2, fontsize=9)
        ax.set_title({"ClA": "Downforce (ClA)", "CdA": "Drag (CdA)", "front": "Aero balance (front share)"}[key],
                     loc="left", fontsize=11, color=INK, fontweight="bold")
    axs[0].set_yticks(range(len(runs)), [NAMES.get(r["run"], r["run"]) for r in runs], fontsize=9, color=INK)
    fig.suptitle("Totals against CP_bl1: only the filled dots are outside CP's 2.2 % run-to-run spread",
                 x=0.01, ha="left", fontsize=12, color=INK)
    rep_txt = (f"darker band: the CP_bl1 repeat's own change (ClA {f_rep(rep, ref, 'ClA'):+.1f} %, CdA {f_rep(rep, ref, 'CdA'):+.1f} %)"
               if rep is not None else "")
    fig.text(0.01, 0.005, f"Light band: CP's 2.2 % spread (front share: 2.2 % of {num(ref, 'aero_front'):.3f}); {rep_txt}. "
             "Hollow dot: inside the spread, not claimed.\nGrey dots: CP_bl1 again (repeat, mesh fix A). "
             "K (fix B) is left out: no reference meshes on its setting. Half-car steady RANS, one run per variant.", fontsize=8, color=INK2)
    fig.patch.set_facecolor(SURF)
    fig.tight_layout(rect=(0, 0.06, 1, 0.93))
    return save(fig, "chart_totals.png", plt)


def f_rep(rep, ref, k):
    return 100 * (num(rep, k) / num(ref, k) - 1)


def chart_lap_balance(plt):
    L = list(csv.DictReader(LAPS.open()))
    B = list(csv.DictReader(BAL.open()))
    cars = [c[2:-2] for c in L[0] if c.startswith("t_")]          # CP_bl1, CPF, (CPFF)
    others = cars[1:]
    tracks = ["skidpad", "autocross", "fast_circuit"]
    fig, axs = plt.subplots(1, 4, figsize=(15.5, 4.4), dpi=130, gridspec_kw={"width_ratios": [1, 1, 1, 1.15]})
    for ax, tr in zip(axs[:3], tracks):
        style(ax)
        rows_ = [r for r in L if r["track"] == tr]
        y = 0
        ticks, labs = [], []
        lim = 0.0
        for r in rows_:
            band = float(r["band_2p2_s"])
            ax.fill_betweenx([y - 0.42, y + 0.42 + 0.5 * (len(others) - 1)], -band, band, color=BAND, zorder=0)
            for j, c in enumerate(others):
                v = float(r[f"diff_{c}_s"])
                out = abs(v) > band
                ax.plot([v], [y + 0.5 * j], "o", ms=8, mfc=SLOT[j] if out else SURF, mec=SLOT[j], mew=2, zorder=3)
                ax.text(v, y + 0.5 * j + 0.17, f"{v:+.3f}", ha="center", fontsize=8, color=INK)
                lim = max(lim, abs(v), band)
            ticks.append(y + 0.25 * (len(others) - 1)); labs.append(r["model"])
            y += 0.5 * len(others) + 0.7
        ax.axvline(0, color=INK2, lw=0.8)
        ax.set_xlim(-1.4 * lim, 1.4 * lim)
        ax.set_yticks(ticks, labs, fontsize=9, color=INK)
        ax.set_ylim(-0.7, y - 0.3)
        ax.set_xlabel("lap time minus CP_bl1 (s)", color=INK2, fontsize=9)
        ax.set_title(tr.replace("_", " ").capitalize(), loc="left", fontsize=11, color=INK, fontweight="bold")
    ax = axs[3]
    style(ax)
    for k, R_ in enumerate((45, 100)):
        rr = {r["car"]: r for r in B if int(float(r["radius_m"])) == R_}
        b0 = float(rr["CP_bl1"]["balance_pct"]); band = float(rr["CP_bl1"]["balance_band_2p2_pct"])
        yb = k * 1.6
        ax.fill_betweenx([yb - 0.5, yb + 0.5 + 0.4 * len(others)], b0 - band, b0 + band, color=BAND, zorder=0)
        ax.plot([b0], [yb], "o", ms=8, mfc=REF, mec=REF, zorder=3)
        ax.text(b0, yb + 0.17, f"CP_bl1 {b0:+.1f}", ha="center", fontsize=8, color=INK)
        for j, c in enumerate(others):
            v = float(rr[c]["balance_pct"])
            out = abs(v - b0) > band
            ax.plot([v], [yb + 0.4 * (j + 1)], "o", ms=8, mfc=SLOT[j] if out else SURF, mec=SLOT[j], mew=2, zorder=3)
            ax.text(v, yb + 0.4 * (j + 1) + 0.17, f"{c} {v:+.1f}", ha="center", fontsize=8, color=INK)
    ax.axvline(0, color=INK2, lw=0.8, ls=":")
    ax.text(0.15, -0.45, "neutral", fontsize=8, color=INK2)
    ax.set_yticks([0.2 * len(others), 1.6 + 0.2 * len(others)], ["45 m", "100 m"], fontsize=9, color=INK)
    ax.set_xlabel("cornering balance (%): + understeer, - rear limits first", color=INK2, fontsize=9)
    ax.set_title("Balance at the limit", loc="left", fontsize=11, color=INK, fontweight="bold")
    ax.set_xlim(-8, 3)
    handles = [plt.Line2D([], [], marker="o", ls="", mfc=SLOT[j], mec=SLOT[j], ms=8, label=c) for j, c in enumerate(others)]
    handles.append(plt.Line2D([], [], marker="o", ls="", mfc=SURF, mec=INK2, mew=2, ms=8, label="hollow: inside the band"))
    fig.legend(handles=handles, loc="upper right", ncol=len(handles), frameon=False, fontsize=9)
    fig.suptitle("Lap sim: CPF (F rear supports), CPFF (J front + F rear) and CPG (G rear, mesh fix A) against CP_bl1",
                 x=0.01, ha="left", fontsize=12, color=INK)
    fig.text(0.01, 0.005, "Grey band: the largest change in that result when CP_bl1's ClA or CdA is raised, or its front share "
             "lowered, by 2.2 % (matlab/lapsim/support_sensitivity.m). Same car, tyres and lap-sim settings; only ClA, CdA and "
             "front share differ. CFD only: the CAD has no supports.", fontsize=8, color=INK2)
    fig.patch.set_facecolor(SURF)
    fig.tight_layout(rect=(0, 0.03, 1, 0.9))
    return save(fig, "chart_lap_balance.png", plt)


def save(fig, name, plt):
    OUT.mkdir(parents=True, exist_ok=True)
    p = OUT / name
    fig.savefig(p, facecolor=fig.get_facecolor())
    plt.close(fig)
    print("wrote", p.relative_to(ROOT), f"{p.stat().st_size / 1e3:.0f} kB")
    return p


def main(argv) -> int:
    if "--selftest" in argv:
        return selftest()
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    R = rows()
    if R[0]["run"] != "CP_bl1":
        sys.exit("support_table.csv must start with CP_bl1 (the reference): run cfd/support_table.py CP_bl1 ...")
    chart_support_drag(R, plt)
    chart_totals(R, plt)
    chart_lap_balance(plt)
    return 0


def selftest() -> int:
    """The front-share band is 2.2 % of 0.431 = 0.948 points; f_rep(3.941 vs 3.977) = -0.905 %."""
    ok = abs(SPREAD / 100 * 0.431 * 100 - 0.9482) < 1e-9
    rep, ref = {"ClA": "3.941"}, {"ClA": "3.977"}
    ok &= abs(f_rep(rep, ref, "ClA") - 100 * (3.941 / 3.977 - 1)) < 1e-12 and abs(f_rep(rep, ref, "ClA") + 0.9052) < 1e-3
    print(f"support_charts self-test: front-share band 0.948 points, repeat -0.905 %: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
