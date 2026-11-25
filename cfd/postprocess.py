#!/usr/bin/env python3
"""Post-processing of the half-car Fluent runs written by cfd/fluent_halfcar.py.

    .venv/Scripts/python cfd/postprocess.py                    # all runs in cfd/results/runs
    .venv/Scripts/python cfd/postprocess.py --update-variants  # also put CFD rows in params/aero_variants.csv
    .venv/Scripts/python cfd/postprocess.py --selftest

Reads, per run directory cfd/results/runs/<V><tag>/:
  run_info.json   speed, density, cells, report names (written by the solver script)
  forces.out      half-car force and moment history, one line per iteration
and the wake planes cfd/results/wake/<V><tag>_<n>L.csv (Fluent ASCII node export).

FORCES (half model -> full car: forces and moments times 2)
  mean over the last N iterations (N = 200, or a fifth of the run if shorter)
  ClA = DF / q,  CdA = D / q,  q = 0.5 rho U^2
  front axle aero load: the pitching moment about the Y axis through the front
  contact point (origin, X rearward, Z up) is M = sum(x DF_i + z D_i), so the
  rear axle carries M / L and the front axle DF - M / L (drag high up loads the rear).
  Convergence of the forces: drift = change of the mean between the last N
  and the N before, band = (max - min) / |mean| over the last N; for the
  downforce |mean| is floored at the force of ClA 0.1 m2 (variant A's downforce
  is near zero and a relative band of a near-zero number means nothing). A run counts
  as force-converged when it has >= 300 iterations and drift < 1 % and band < 2 %
  for both downforce and drag. It says nothing about mesh independence.

WAKE (per plane, interpolated linearly onto a 10 mm grid in y, z: area-weighted)
  d = 1 - u / U.  centre deficit = max d,  its (y, z) position
  width = full width (both halves) where d >= d_max / 2 on the row through the centre
  height = vertical extent where d >= d_max / 2 on the column through the centre
  following-car window (0 <= y <= 0.7 m, 0 <= z <= 1.2 m, half of 1.4 m wide):
    deficit = 1 - mean(u/U), q_ratio = mean((u/U)^2), TI = mean(sqrt(2k/3)) / U,
    upwash = atan(mean w / mean u)  (same definitions as matlab/cfd/wake_postprocess.m)

HONESTY: one mesh per variant, under the Ansys Student cell limit, no mesh or
y+ study. Treat the absolute numbers as uncertain (the CFD rows carry an
ASSUMED +-20 % ClA and +-15 % CdA range); only the ranking of the variants,
computed on identical meshing settings, is the trustworthy output.

Outputs: cfd/results/cfd_summary.csv (one row per run, components, convergence),
cfd/results/forces.csv (the input of matlab/aero_plots.m), cfd/results/wake_cfd.csv,
media/cfd/cfd_results.md, media/cfd/cfd_forces.png, media/cfd/cfd_convergence.png,
media/cfd/cfd_wake.png, media/cfd/wake_<run>.png.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "cfd" / "results" / "runs"
WAKE = ROOT / "cfd" / "results" / "wake"
MEDIA = ROOT / "media" / "cfd"
GEO = ROOT / "cad" / "step" / "cfd" / "cfd_geometry.json"
VARIANTS = ROOT / "params" / "aero_variants.csv"
ESTIMATE = ROOT / "params" / "aero_variants_estimate.csv"

N_AVG = 200
MIN_ITERS = 300
DRIFT_MAX, BAND_MAX = 0.01, 0.02
DF_FLOOR_CLA = 0.1                            # m2: downforce convergence measured against at least this much
CFD_RANGE = {"ClA": 0.20, "CdA": 0.15}        # ASSUMPTION, no mesh study: see the docstring
GRID = 0.01                                   # m, wake interpolation grid


# --------------------------------------------------------------------------- forces
def read_forces(path: Path):
    """Fluent report file: three header lines, the last is ("Iteration" "a" "b" ...)."""
    names, rows = None, []
    for line in path.read_text().splitlines():
        s = line.strip()
        if s.startswith("(") and "Iteration" in s:
            names = re.findall(r'"([^"]+)"', s)
            continue
        if names and s and s[0].isdigit():
            v = s.split()
            if len(v) == len(names):
                rows.append([float(q) for q in v])
    if not names or not rows:
        raise ValueError(f"{path}: no data")
    a = np.array(rows)
    # a restarted run repeats iteration numbers: keep the last occurrence
    _, idx = np.unique(a[::-1, 0], return_index=True)
    a = a[::-1][idx]
    return {n: a[:, k] for k, n in enumerate(names)}


def read_forces_all(run_dir: Path):
    """forces.out plus any forces_cont<k>.out of continued runs (iteration numbers
    carry on; a repeated iteration keeps its last value)."""
    files = [run_dir / "forces.out"] + sorted(run_dir.glob("forces_cont*.out"), key=lambda f: int(re.sub(r"\D", "", f.stem) or 0))
    parts = [read_forces(f) for f in files if f.exists()]
    names = list(parts[0])
    a = np.concatenate([np.column_stack([q[n] for n in names]) for q in parts if list(q) == names])
    _, idx = np.unique(a[::-1, 0], return_index=True)
    a = a[::-1][idx]
    return {n: a[:, k] for k, n in enumerate(names)}


def window_stats(h: np.ndarray, n_avg: int = N_AVG, floor: float = 1e-9):
    n = len(h)
    N = max(5, min(n_avg, n // 5)) if n >= 10 else n
    last = h[-N:]
    mean = float(last.mean())
    prev = h[-2 * N:-N] if n >= 2 * N else None
    ref = max(abs(mean), floor)
    drift = abs(mean - prev.mean()) / ref if prev is not None else float("nan")
    band = float(last.max() - last.min()) / ref
    return {"mean": mean, "N": N, "drift": drift, "band": band}


def analyse_run(run_dir: Path, wheelbase: float):
    info = json.loads((run_dir / "run_info.json").read_text())
    F = read_forces_all(run_dir)
    U, rho = info["speed_mps"], info["density"]
    q = 0.5 * rho * U * U
    n_it = int(F["Iteration"][-1])
    sd = window_stats(F["downforce_total"], floor=DF_FLOOR_CLA * q / 2)    # half-car series
    sD = window_stats(F["drag_total"])
    M = window_stats(F["pitch_moment_total"])["mean"] * 2
    DF, D = 2 * sd["mean"], 2 * sD["mean"]
    rear = M / wheelbase
    front = DF - rear
    conv = (n_it >= MIN_ITERS and sd["drift"] < DRIFT_MAX and sD["drift"] < DRIFT_MAX
            and sd["band"] < BAND_MAX and sD["band"] < BAND_MAX)
    r = {"run": run_dir.name, "variant": info["variant"], "tag": info.get("tag") or run_dir.name[len(info["variant"]):], "speed_mps": U, "density": rho,
         "cells": info.get("cells", 0), "iterations": n_it, "downforce_N": DF, "drag_N": D, "front_axle_N": front,
         "rear_axle_N": rear, "ClA": DF / q, "CdA": D / q, "L_over_D": DF / D if D else float("nan"),
         "aero_front": front / DF if abs(DF / q) > 0.5 else float("nan"),
         "df_drift_pct": 100 * sd["drift"], "df_band_pct": 100 * sd["band"],
         "drag_drift_pct": 100 * sD["drift"], "drag_band_pct": 100 * sD["band"], "avg_iters": sd["N"],
         "force_converged": conv}
    pi = run_dir / "post_info.json"
    if pi.exists():
        post = json.loads(pi.read_text())
        r["mass_imbalance_rel"] = post.get("mass_imbalance_rel", float("nan"))
        r["_yplus"] = post.get("yplus", {})
        r["_boxes"] = post.get("wake_boxes", [])
    for k in F:                                                     # components, full car, as ClA_x / CdA_x
        m = re.match(r"(downforce|drag)_(.+)", k)
        if m and m.group(2) != "total":
            r[("ClA_" if m.group(1) == "downforce" else "CdA_") + m.group(2)] = 2 * window_stats(F[k])["mean"] / q
    return r, F


# --------------------------------------------------------------------------- wake
def read_plane(path: Path):
    with path.open() as f:
        rd = csv.reader(f)
        head = [h.strip() for h in next(rd)]
        data = np.array([[float(v) for v in row] for row in rd if row])
    col = {h: data[:, k] for k, h in enumerate(head)}
    get = lambda *names: next(col[n] for n in names if n in col)
    return {"y": get("y-coordinate"), "z": get("z-coordinate"), "u": get("x-velocity"),
            "v": get("y-velocity"), "w": get("z-velocity"), "k": col.get("turb-kinetic-energy")}


def wake_metrics(P, U: float, win=(0.7, 1.2), ymax=2.5, zmax=2.5):
    from scipy.interpolate import griddata
    yg = np.arange(0, min(ymax, P["y"].max()) + 1e-9, GRID)
    zg = np.arange(0, min(zmax, P["z"].max()) + 1e-9, GRID)
    Y, Z = np.meshgrid(yg, zg)
    pts = np.column_stack([P["y"], P["z"]])
    lin = lambda f: griddata(pts, f, (Y, Z), method="linear")
    near = lambda f: griddata(pts, f, (Y, Z), method="nearest")
    fill = lambda f: np.where(np.isnan(lin(f)), near(f), lin(f))
    u, w = fill(P["u"]), fill(P["w"])
    k = fill(P["k"]) if P["k"] is not None else np.zeros_like(u)
    d = 1 - u / U
    i, j = np.unravel_index(np.nanargmax(d), d.shape)
    dmax = float(d[i, j])
    row, colm = d[i, :] >= dmax / 2, d[:, j] >= dmax / 2
    ys, zs = yg[row], zg[colm]
    inwin = (Y <= win[0]) & (Z <= win[1])
    ur = u[inwin] / U
    return {"centre_deficit": dmax, "centre_y_m": float(yg[j]), "centre_z_m": float(zg[i]),
            "width_m": 2 * float(ys.max()) if ys.size else 0.0,
            "height_m": float(zs.max() - zs.min()) if zs.size else 0.0,
            "window_deficit": float(1 - ur.mean()), "q_ratio": float((ur ** 2).mean()),
            "TI": float(np.sqrt(np.clip(2 * k[inwin] / 3, 0, None)).mean() / U),
            "upwash_deg": math.degrees(math.atan2(w[inwin].mean(), u[inwin].mean())),
            "wake_CdA_momentum": 2 * float((u / U * (1 - u / U)).sum() * GRID * GRID) * 2,
            "nodes": int(len(P["u"])), "_grid": (yg, zg, u / U)}


# --------------------------------------------------------------------------- outputs
def write_csv(path: Path, rows: list[dict], keys=None):
    keys = keys or sorted({k for r in rows for k in r if not k.startswith("_")}, key=lambda k: list(rows[0]).index(k) if k in rows[0] else 999)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: (f"{r[k]:.6g}" if isinstance(r.get(k), float) else r.get(k, "")) for k in keys})


def read_estimates():
    """The pre-CFD estimate: aero_variants_estimate.csv (written by aero_estimate.m);
    aero_variants.csv only as a fallback and only its rows that are not CFD."""
    if ESTIMATE.exists():
        with ESTIMATE.open() as f:
            return {r["variant"]: r for r in csv.DictReader(f)}
    if not VARIANTS.exists():
        return {}
    with VARIANTS.open() as f:
        return {r["variant"]: r for r in csv.DictReader(f) if not r["source"].startswith("CFD")}


def pick_final(runs: list[dict]):
    """Per variant: the run without a tag (run name = variant name), solved with the
    common mesh settings. Tagged runs (coarse, w = wake-window mesh, num = numerics
    test, probe) are checks and never go into the variant table."""
    return {r["variant"]: r for r in runs if r["tag"] == "" and r["run"] == r["variant"]}


def yplus_stats(yp: dict) -> list[dict]:
    """Per wall zone: area-average, max (Fluent reports) and the share of faces in
    the y+ bands, from the per-face export (cfd/cases/yplus, if it is there)."""
    rows = []
    for zone, v in sorted(yp.items()):
        r = {"zone": zone, "area_avg": v.get("area_avg"), "max": v.get("max"), "min": v.get("min")}
        f = Path(v.get("face_file", ""))
        if f.is_file():
            y = read_plane_cols(f, ["y-plus"])["y-plus"]
            r.update({"n_faces": int(y.size), "p05": float(np.percentile(y, 5)), "p50": float(np.percentile(y, 50)), "p95": float(np.percentile(y, 95)),
                      "lt5": float((y < 5).mean()), "5to30": float(((y >= 5) & (y < 30)).mean()),
                      "30to300": float(((y >= 30) & (y <= 300)).mean()), "gt300": float((y > 300).mean())})
        rows.append(r)
    return rows


# boxes: the following car's front wing and wheels (low) and its rear wing (high), half width
BOX_REGIONS = {"low": (0.8, 0.0, 0.5), "high": (0.65, 1.0, 1.5)}      # (y max, z min, z max) in m


def read_plane_cols(path: Path, cols: list[str]):
    with path.open() as f:
        rd = csv.reader(f)
        head = [h.strip() for h in next(rd)]
        data = np.array([[float(v) for v in row] for row in rd if row])
    return {h: data[:, k] for k, h in enumerate(head) if h in cols or h.endswith("coordinate")}


def box_metrics(path: Path, U: float, x_centre: float, offsets) -> dict:
    """Average over the five planes of a wake box, each interpolated linearly onto a
    10 mm grid in its region: deficit 1 - mean(u)/U, q-ratio mean((u/U)^2),
    TKE mean k (m2/s2) and TI = sqrt(2 k_mean / 3) / U, mean |x-vorticity| and
    mean vorticity magnitude (1/s), mean upwash angle."""
    from scipy.interpolate import griddata
    c = read_plane_cols(path, ["x-velocity", "z-velocity", "turb-kinetic-energy", "x-vorticity", "vorticity-mag"])
    out = {}
    for reg, (ym, z0, z1) in BOX_REGIONS.items():
        yg = np.arange(0.005, ym, GRID); zg = np.arange(z0 + 0.005, z1, GRID)
        Y, Z = np.meshgrid(yg, zg)
        acc = {k: [] for k in ("u", "w", "k", "wx", "wm")}
        nodes = 0
        for d in offsets:
            sel = np.abs(c["x-coordinate"] - (x_centre + d)) < 1e-3
            pts = np.column_stack([c["y-coordinate"][sel], c["z-coordinate"][sel]])
            inreg = (pts[:, 0] <= ym + 0.05) & (pts[:, 1] >= z0 - 0.05) & (pts[:, 1] <= z1 + 0.05)
            nodes += int(inreg.sum())
            for key, col in (("u", "x-velocity"), ("w", "z-velocity"), ("k", "turb-kinetic-energy"), ("wx", "x-vorticity"), ("wm", "vorticity-mag")):
                vals = c[col][sel]
                g = griddata(pts, vals, (Y, Z), method="linear")
                g = np.where(np.isnan(g), griddata(pts, vals, (Y, Z), method="nearest"), g)
                acc[key].append(np.abs(g) if key == "wx" else g)
        u = np.mean(acc["u"], axis=0) / U
        kk = float(np.mean(acc["k"]))
        out[reg] = {"deficit": float(1 - u.mean()), "q_ratio": float((u ** 2).mean()), "tke": kk, "TI": math.sqrt(2 * kk / 3) / U,
                    "abs_x_vorticity": float(np.mean(acc["wx"])), "vorticity_mag": float(np.mean(acc["wm"])),
                    "upwash_deg": math.degrees(math.atan2(float(np.mean(acc["w"])), float(np.mean(acc["u"])))), "nodes": nodes}
    return out


# which CFD run feeds each row of params/aero_variants.csv (default: the run named like the variant).
# 2026-11-18 (evening): C uses CP, i.e. C's wings and floor plan with the SolidWorks nose, sidepods and floor
# plate (user's choice). A, B and D are still on the older CFD bodywork.
# 2026-11-18 (late): CP has its own row (the as-built reference the lap sim uses by default) and C is
# back on run C, so A to D compare like for like on the older bodywork. Every row maps to its own run.
# 2026-11-25: rows B and D come from B_AB and D_AB (B's and D's aero packages on CP's as-built bodywork),
# so B, D and CP compare like for like; the old rows are kept in params/aero_variants_simplified_BD.csv.
TABLE_RUN = {"B": "B_AB", "D": "D_AB"}
AS_BUILT_RUNS = {"CP", "B_AB", "D_AB"}
# extra words for the note column (2026-11-25): D's 14 deg diffuser would not mesh on CP's bodywork
RUN_NOTE = {"D_AB": "; D's DIFFUSER IS 12 deg HERE, NOT 14 deg (14 deg did not mesh on this bodywork); "
                    "1 prism layer instead of 2 (cell limit; on the old bodywork 1 layer moved ClA -0.2 %, CdA -1.0 %)"}


def update_variants(final: dict, force: bool):
    """Replace the variant rows by CFD rows (converged runs only unless force)."""
    with VARIANTS.open() as f:
        rd = csv.DictReader(f); keys = rd.fieldnames; rows = list(rd)
    changed = []
    for row in rows:
        r = final.get(TABLE_RUN.get(row["variant"], row["variant"]))
        if r is None or (not r["force_converged"] and not force) or math.isnan(r["aero_front"]) and abs(r["ClA"]) > 0.5:
            continue
        af = r["aero_front"] if not math.isnan(r["aero_front"]) else float(row["aero_front"])
        row.update({"ClA": f"{r['ClA']:.3f}", "CdA": f"{r['CdA']:.3f}", "aero_front": f"{af:.3f}",
                    "ClA_lo": f"{r['ClA'] - abs(r['ClA']) * CFD_RANGE['ClA']:.2f}", "ClA_hi": f"{r['ClA'] + abs(r['ClA']) * CFD_RANGE['ClA']:.2f}",
                    "CdA_lo": f"{r['CdA'] * (1 - CFD_RANGE['CdA']):.2f}", "CdA_hi": f"{r['CdA'] * (1 + CFD_RANGE['CdA']):.2f}",
                    "source": f"CFD {r['run']} (Fluent half car, {r['cells']} cells, {'force-converged' if r['force_converged'] else 'NOT converged'})",
                    "note": "range is an ASSUMPTION (+-20 % ClA, +-15 % CdA): mesh checks move ClA < 0.3 % and CdA < 2.4 % but model error is unmeasured; only the ranking of variants is trustworthy"
                            + ("" if not math.isnan(r["aero_front"]) else "; total near zero so aero_front kept from the estimate")
                            + ("; SolidWorks bodywork (nose, sidepods, 10 mm floor plate); unsteady, mean good to about 1 %" if r["run"] == "CP"
                               else f"; as-built bodywork of CP (SolidWorks nose, sidepods, 10 mm floor plate), run {r['run']}" if r["run"] in AS_BUILT_RUNS
                               else "; older CFD bodywork (not the SolidWorks nose and sidepods)")
                            + RUN_NOTE.get(r["run"], "")})
        changed.append(row["variant"])
    with VARIANTS.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys); w.writeheader(); w.writerows(rows)
    return changed


def plots(runs, hist, wakes, est, final):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    MEDIA.mkdir(parents=True, exist_ok=True)
    col = {"A": "#7f7f7f", "B": "#1f77b4", "C": "#d62728", "D": "#2ca02c", "E": "#9467bd", "CP": "#ff7f0e", "B_AB": "#17becf", "D_AB": "#bcbd22"}
    # ClA vs CdA: CFD (final runs) and the estimates with their ranges
    fig, ax = plt.subplots(figsize=(7, 5.5))
    for v, e in sorted(est.items()):
        c = col.get(v, "k")
        x, y = float(e["CdA"]), float(e["ClA"])
        if e.get("source", "").startswith("ESTIMATE") and e.get("ClA_lo"):
            ax.errorbar(x, y, xerr=[[x - float(e["CdA_lo"])], [float(e["CdA_hi"]) - x]],
                        yerr=[[y - float(e["ClA_lo"])], [float(e["ClA_hi"]) - y]], fmt="o", mfc="none", color=c, alpha=0.6, capsize=3)
            ax.annotate(f"{v} est.", (x, y), textcoords="offset points", xytext=(6, -12), color=c, fontsize=8)
    for v, r in sorted(final.items()):
        c = col.get(v, "k")
        ax.plot(r["CdA"], r["ClA"], "s", color=c, ms=9)
        ax.annotate(f"{v} CFD" + ("" if r["force_converged"] else " (not conv.)"), (r["CdA"], r["ClA"]),
                    textcoords="offset points", xytext=(6, 4), color=c, fontsize=9, weight="bold")
    ax.set_xlabel("CdA (m$^2$)"); ax.set_ylabel("ClA (m$^2$, downforce +)"); ax.grid(True, lw=0.3)
    ax.set_title("CFD (squares) vs pre-CFD estimate (circles, RSS range)\nCFD: one Student-size mesh per variant, ranking only", fontsize=10)
    fig.tight_layout(); fig.savefig(MEDIA / "cfd_forces.png", dpi=120); plt.close(fig)
    # convergence history
    if hist:
        fig, axs = plt.subplots(len(hist), 1, figsize=(8, 2.4 * len(hist)), squeeze=False)
        for ax, (name, F) in zip(axs[:, 0], sorted(hist.items())):
            it = F["Iteration"]
            ax.plot(it, 2 * F["downforce_total"], label="downforce (N, full car)")
            ax.plot(it, 2 * F["drag_total"], label="drag (N, full car)")
            ax.set_title(name, fontsize=9); ax.grid(True, lw=0.3); ax.legend(fontsize=7)
            lo = min(np.percentile(2 * F["downforce_total"], 5), np.percentile(2 * F["drag_total"], 5))
            hi = max(np.percentile(2 * F["downforce_total"], 99), np.percentile(2 * F["drag_total"], 99))
            ax.set_ylim(lo - 0.2 * abs(hi - lo), hi + 0.2 * abs(hi - lo))
        axs[-1, 0].set_xlabel("iteration")
        fig.tight_layout(); fig.savefig(MEDIA / "cfd_convergence.png", dpi=110); plt.close(fig)
    # wake metrics vs distance + contours
    if wakes:
        fig, axs = plt.subplots(1, 3, figsize=(13, 4))
        for run in sorted({w["run"] for w in wakes}):
            ws = sorted([w for w in wakes if w["run"] == run], key=lambda w: w["plane_L"])
            c = col.get(ws[0]["variant"], "k"); L = [w["plane_L"] for w in ws]
            ls = "-" if run == ws[0]["variant"] else "--"
            axs[0].plot(L, [w["centre_deficit"] for w in ws], ls, marker="o", color=c, label=run)
            axs[1].plot(L, [w["width_m"] for w in ws], ls, marker="o", color=c, label=run)
            axs[2].plot(L, [w["q_ratio"] for w in ws], ls, marker="o", color=c, label=run)
        for ax, t in zip(axs, ["centre velocity deficit 1 - u/U", "wake width (m, full, at half deficit)", "q-ratio in the following-car window"]):
            ax.set_title(t, fontsize=9); ax.set_xlabel("car lengths behind the rear axle"); ax.grid(True, lw=0.3)
        axs[2].legend(fontsize=7)
        fig.tight_layout(); fig.savefig(MEDIA / "cfd_wake.png", dpi=110); plt.close(fig)
        for run in sorted({w["run"] for w in wakes}):
            ws = sorted([w for w in wakes if w["run"] == run], key=lambda w: w["plane_L"])
            fig, axs = plt.subplots(1, len(ws), figsize=(4 * len(ws), 4), squeeze=False)
            for ax, w in zip(axs[0], ws):
                yg, zg, ur = w["_grid"]
                yy = np.concatenate([-yg[::-1], yg]); uu = np.concatenate([ur[:, ::-1], ur], axis=1)   # mirror the half model
                cs = ax.contourf(yy, zg, uu, levels=np.linspace(0.3, 1.1, 17), cmap="viridis", extend="both")
                ax.add_patch(plt.Rectangle((-0.7, 0), 1.4, 1.2, fill=False, ec="w", lw=1))
                ax.set_xlim(-2.5, 2.5); ax.set_ylim(0, 2.5)
                ax.set_aspect("equal"); ax.set_title(f"{run}: {w['plane_L']:g} L, u/U", fontsize=9); ax.set_xlabel("y (m)")
            axs[0, 0].set_ylabel("z (m)"); fig.colorbar(cs, ax=axs[0, -1], shrink=0.8)
            fig.tight_layout(); fig.savefig(MEDIA / f"wake_{run}.png", dpi=100); plt.close(fig)


def fmt_share(x: float) -> str:
    return "n/a" if math.isnan(x) else f"{x:.2f}"


def write_md(runs, final, wakes, est, changed, boxes=(), yrows=(), comp=()):
    MEDIA.mkdir(parents=True, exist_ok=True)
    L = ["# CFD results (Ansys Fluent, half car)", "",
         "Written by `cfd/postprocess.py`. **What these numbers mean:** one mesh per variant, sized to stay under the "
         "Ansys Student cell limit, steady RANS (k-omega SST), no mesh-independence or y+ study, no comparison with a "
         "test. The absolute ClA, CdA and balance can be off by tens of percent; **only the ranking of the variants "
         "(same meshing settings, same solver settings) is the trustworthy output.** Runs marked *not converged* have "
         "forces still moving by more than 1 % between the last two averaging windows or oscillating more than 2 %.", "",
         "**Bodywork.** CP, B_AB and D_AB share the as-built bodywork (SOLIDWORKS nose, sidepods, 10 mm floor plate) "
         "and are the like-for-like comparison; rows B and D of `params/aero_variants.csv` come from B_AB and D_AB "
         "since 2026-11-25. A, B, C, D, E and the checks are on the older CFD bodywork. **D_AB's diffuser is 12 "
         "degrees, not D's 14** (14 did not mesh on the as-built bodywork), and D_AB has 1 prism layer instead of 2 "
         "(cell limit); CP_bl1 is CP with the same 1 layer, for comparison.", "",
         "## All runs", "",
         "| run | cells | iter | ClA (m2) | CdA (m2) | L/D | front axle share | DF drift / band % | drag drift / band % | force-converged |",
         "|---|---|---|---|---|---|---|---|---|---|"]
    for r in sorted(runs, key=lambda r: r["run"]):
        L.append(f"| {r['run']} | {r['cells']:,} | {r['iterations']} | {r['ClA']:.2f} | {r['CdA']:.2f} | {r['L_over_D']:.2f} | "
                 f"{fmt_share(r['aero_front'])} | {r['df_drift_pct']:.2f} / {r['df_band_pct']:.2f} | "
                 f"{r['drag_drift_pct']:.2f} / {r['drag_band_pct']:.2f} | {'yes' if r['force_converged'] else 'NO'} |")
    L += ["", "## Final run per variant against the pre-CFD estimate", "",
          "| variant | run | CFD ClA | estimate ClA (range) | CFD CdA | estimate CdA (range) | CFD front share | estimate front share |",
          "|---|---|---|---|---|---|---|---|"]
    for v, r in sorted(final.items()):
        e = est.get(v, {})
        rng = lambda a: f"{float(e[a]):.2f} ({float(e[a + '_lo']):.2f} to {float(e[a + '_hi']):.2f})" if e.get(a + "_lo") and e.get("source", "").startswith("ESTIMATE") else e.get(a, "-")
        af = "n/a" if math.isnan(r["aero_front"]) else f"{r['aero_front']:.2f}"
        try:
            ef = "n/a" if abs(float(e["ClA"])) < 0.5 else f"{float(e['aero_front']):.2f}"
        except (KeyError, ValueError):
            ef = "-"
        L.append(f"| {v} | {r['run']} | {r['ClA']:.2f} | {rng('ClA')} | {r['CdA']:.2f} | {rng('CdA')} | {af} | {ef} |")
    if final:
        rank = sorted(final.values(), key=lambda r: -r["ClA"])
        L += ["", "Ranking by downforce (CFD): " + " > ".join(f"{r['variant']} ({r['ClA']:.2f})" for r in rank)
              + ";  by drag: " + " > ".join(f"{r['variant']} ({r['CdA']:.2f})" for r in sorted(final.values(), key=lambda r: -r["CdA"])) + "."]
    comps = sorted({k for r in final.values() for k in r if k.startswith("ClA_")})
    if comps:
        L += ["", "## Components (full car, final runs)", "", "| variant | " + " | ".join(f"{c} / {c.replace('ClA', 'CdA')}" for c in comps) + " |",
              "|---|" + "---|" * len(comps)]
        for v, r in sorted(final.items()):
            L.append(f"| {v} | " + " | ".join(f"{r.get(c, float('nan')):.2f} / {r.get(c.replace('ClA', 'CdA'), float('nan')):.2f}" for c in comps) + " |")
    if wakes:
        L += ["", "## Wake planes", "", "Area-weighted on a 10 mm grid; window = following car's frontal window (1.4 m wide, 1.2 m high). "
              "`wake CdA` is the momentum deficit integral without the pressure term, a rough check against the drag.", "",
              "| run | plane (L) | centre deficit | centre y, z (m) | width (m) | height (m) | window deficit | q-ratio | TI | upwash (deg) | wake CdA | nodes |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for w in sorted(wakes, key=lambda w: (w["run"], w["plane_L"])):
            L.append(f"| {w['run']} | {w['plane_L']:g} | {w['centre_deficit']:.2f} | {w['centre_y_m']:.2f}, {w['centre_z_m']:.2f} | {w['width_m']:.2f} | "
                     f"{w['height_m']:.2f} | {w['window_deficit']:.2f} | {w['q_ratio']:.2f} | {w['TI']:.3f} | {w['upwash_deg']:.1f} | {w['wake_CdA_momentum']:.2f} | {w['nodes']} |")
    if comp:
        L += ["", "## Checks: tagged runs against the standard run of the same variant", "",
              "`coarse` = coarser non-wing surface sizes (mesh check), `w` = wake-window refinement boxes, `num` = numerics test.", "",
              "| run | cells | base run | base cells | ClA change % | CdA change % | front share change |", "|---|---|---|---|---|---|---|"]
        for c in comp:
            L.append(f"| {c['run']} | {c['cells']:,} | {c['base']} | {c['base_cells']:,} | {c['dClA_pct']:+.1f} | {c['dCdA_pct']:+.1f} | {c['d_front']:+.3f} |")
    if boxes:
        L += ["", "## Wake boxes (following car at 1, 2, 3 car lengths)", "",
              "Five planes 0.15 m apart (a 0.6 m deep box) around each station, half model. `low` = Y 0 to 0.8, Z 0 to 0.5 m (the "
              "following car's front wing and wheels); `high` = Y 0 to 0.65, Z 1.0 to 1.5 m (its rear wing). TKE in m2/s2, "
              "TI = sqrt(2 TKE / 3) / U, vorticity in 1/s. Inlet turbulence: TI 0.005.", "",
              "| run | L | region | deficit | q-ratio | TKE | TI | mean abs x-vorticity | mean vorticity magnitude | upwash (deg) | nodes |",
              "|---|---|---|---|---|---|---|---|---|---|---|"]
        for b in sorted(boxes, key=lambda b: (b["run"], b["L"], b["region"] != "low")):
            L.append(f"| {b['run']} | {b['L']:g} | {b['region']} | {b['deficit']:.3f} | {b['q_ratio']:.3f} | {b['tke']:.3f} | {b['TI']:.3f} | "
                     f"{b['abs_x_vorticity']:.2f} | {b['vorticity_mag']:.2f} | {b['upwash_deg']:.1f} | {b['nodes']} |")
    if yrows:
        L += ["", "## y+ on the walls", "",
              "From Fluent's area-weighted average and face maximum, and the share of faces per y+ band (per-face export). "
              "The wall treatment of k-omega SST in Fluent is y+-insensitive: a resolved sublayer below about 1 to 5, wall functions "
              "above about 30, a blend in between (the buffer layer 5 to 30 is where both are weakest).", "",
              "| run | zone | area-avg | max | 5 % | median | 95 % | < 5 | 5 to 30 | 30 to 300 | > 300 |", "|---|---|---|---|---|---|---|---|---|---|---|"]
        for y in yrows:
            pc = lambda k: f"{100 * y[k]:.0f} %" if k in y else "-"  # noqa: E731
            L.append(f"| {y['run']} | {y['zone']} | {y['area_avg']:.0f} | {y['max']:.0f} | {y.get('p05', float('nan')):.0f} | {y.get('p50', float('nan')):.0f} | "
                     f"{y.get('p95', float('nan')):.0f} | {pc('lt5')} | {pc('5to30')} | {pc('30to300')} | {pc('gt300')} |")
    mi = [r for r in runs if not math.isnan(r.get("mass_imbalance_rel", float("nan")))]
    if mi:
        L += ["", "Mass imbalance (net mass flow / inlet mass flow): " + ", ".join(f"{r['run']} {r['mass_imbalance_rel']:.1e}" for r in sorted(mi, key=lambda r: r["run"])) + "."]
    L += ["", f"params/aero_variants.csv updated from CFD for: {', '.join(changed) if changed else 'none'}.", "",
          "Plots: `media/cfd/cfd_forces.png`, `media/cfd/cfd_convergence.png`, `media/cfd/cfd_wake.png`, `media/cfd/wake_<run>.png`.", ""]
    (MEDIA / "cfd_results.md").write_text("\n".join(L), encoding="utf-8")


def run(args) -> int:
    geo = json.loads(GEO.read_text())
    wb = geo["wheelbase_m"]
    win = (geo["wake_planes"]["window_half_width_m"], geo["wake_planes"]["window_height_m"])
    runs, hist = [], {}
    for d in sorted(RUNS.glob("*")):
        if (d / "run_info.json").exists() and (d / "forces.out").exists():
            try:
                r, F = analyse_run(d, wb)
            except (ValueError, KeyError) as e:
                print(f"skip {d.name}: {e}"); continue
            runs.append(r); hist[d.name] = F
    info_by_run = {r["run"]: r for r in runs}
    wakes = []
    files = {f.name: f for f in sorted(RUNS.glob("*/wake/*_*L.csv"))}
    files.update({f.name: f for f in sorted(WAKE.glob("*_*L.csv"))})      # cfd/results/wake wins
    for f in files.values():
        m = re.match(r"^(.+)_([\d.]+)L\.csv$", f.name)
        if not m or m.group(1) not in info_by_run:
            continue
        r = info_by_run[m.group(1)]
        w = wake_metrics(read_plane(f), r["speed_mps"], win)
        w.update({"run": r["run"], "variant": r["variant"], "plane_L": float(m.group(2))})
        wakes.append(w)
    if not runs:
        print("no runs with run_info.json and forces.out in", RUNS); return 1
    out = ROOT / "cfd" / "results"
    write_csv(out / "cfd_summary.csv", runs)
    final = pick_final(runs)
    rows = [{"variant": r["variant"], "speed_mps": r["speed_mps"], "downforce_N": r["downforce_N"], "drag_N": r["drag_N"],
             "downforce_front_N": r["front_axle_N"], "cells": r["cells"],
             "note": f"CFD {r['run']} {'force-converged' if r['force_converged'] else 'NOT converged'}"}
            for r in runs if "probe" not in r["tag"]]
    if rows:
        write_csv(out / "forces.csv", rows, ["variant", "speed_mps", "downforce_N", "drag_N", "downforce_front_N", "cells", "note"])
    if wakes:
        write_csv(out / "wake_cfd.csv", wakes, ["run", "variant", "plane_L", "centre_deficit", "centre_y_m", "centre_z_m", "width_m", "height_m",
                                               "window_deficit", "q_ratio", "TI", "upwash_deg", "wake_CdA_momentum", "nodes"])
    # wake boxes (files in cfd/cases/wake_boxes, listed in post_info.json)
    boxes = []
    for r in runs:
        for b in r.get("_boxes", []):
            f = Path(b["file"])
            if f.is_file():
                m = box_metrics(f, r["speed_mps"], b["x_centre_m"], b["offsets_m"])
                for reg, v in m.items():
                    boxes.append({"run": r["run"], "variant": r["variant"], "L": b["L"], "region": reg, **v})
    if boxes:
        write_csv(out / "wake_boxes.csv", boxes, ["run", "variant", "L", "region", "deficit", "q_ratio", "tke", "TI", "abs_x_vorticity",
                                                  "vorticity_mag", "upwash_deg", "nodes"])
    yrows = []
    for r in runs:
        for y in yplus_stats(r.get("_yplus", {})):
            yrows.append({"run": r["run"], **y})
    if yrows:
        write_csv(out / "yplus.csv", yrows, ["run", "zone", "area_avg", "min", "max", "p05", "p50", "p95", "lt5", "5to30", "30to300", "gt300", "n_faces"])
    # tagged runs against the untagged run of the same variant (mesh and numerics checks)
    comp = []
    for r in runs:
        b = final.get(r["variant"])
        if r["tag"] and b is not None and "probe" not in r["tag"]:
            comp.append({"run": r["run"], "base": b["run"], "cells": r["cells"], "base_cells": b["cells"],
                         "dClA_pct": 100 * (r["ClA"] / b["ClA"] - 1) if abs(b["ClA"]) > 0.5 else float("nan"),
                         "dCdA_pct": 100 * (r["CdA"] / b["CdA"] - 1),
                         "d_front": (r["aero_front"] - b["aero_front"]) if not (math.isnan(r["aero_front"]) or math.isnan(b["aero_front"])) else float("nan")})
    if comp:
        write_csv(out / "cfd_checks.csv", comp)
    est = read_estimates()
    changed = update_variants(final, args.force) if args.update_variants else []
    if not args.no_plots:
        plots(runs, hist, wakes, est, final)
    write_md(runs, final, wakes, est, changed, boxes=boxes, yrows=yrows, comp=comp)
    for r in sorted(runs, key=lambda r: r["run"]):
        print(f"{r['run']:>14}: {r['cells']:>9,} cells {r['iterations']:>5} it  ClA {r['ClA']:6.2f}  CdA {r['CdA']:5.2f}  "
              f"front {r['aero_front']:.2f}  drift {r['df_drift_pct']:.2f}/{r['drag_drift_pct']:.2f} %  "
              f"band {r['df_band_pct']:.2f}/{r['drag_band_pct']:.2f} %  {'converged' if r['force_converged'] else 'NOT converged'}")
    print(f"{len(wakes)} wake planes; variant table updated for: {changed or 'none'}; wrote media/cfd/cfd_results.md")
    return 0


# --------------------------------------------------------------------------- self-test
def selftest() -> int:
    """Hand-checkable: a half car with 500 N downforce at mid-wheelbase and no
    drag -> full car 1000 N, ClA = 1000 / (0.5 1.2 20^2) = 4.1667 m2, M = 2 x 500 x 0.775
    = 775 N m, rear = 775 / 1.55 = 500 N, front share 0.50. A uniform wake u = 0.8 U,
    w = 0.1 U, k = 0.015 U^2 -> deficit 0.2, q-ratio 0.64, TI 0.10, upwash 7.13 deg."""
    ok = True
    with tempfile.TemporaryDirectory() as t:
        d = Path(t)
        lines = ['"forces"', '"Iteration" "drag_total etc.."', '("Iteration" "drag_total" "downforce_total" "pitch_moment_total")']
        for i in range(1, 501):
            lines.append(f"{i} 100 500 387.5" if i > 50 else f"{i} {100 + i} {500 - i} 300")
        (d / "forces.out").write_text("\n".join(lines))
        (d / "run_info.json").write_text(json.dumps({"variant": "X", "tag": "", "speed_mps": 20.0, "density": 1.2, "cells": 1}))
        r, _ = analyse_run(d, 1.55)
        ok &= abs(r["ClA"] - 4.1667) < 1e-3 and abs(r["aero_front"] - 0.5) < 1e-9 and abs(r["CdA"] - 2 * 100 / 240) < 1e-9 and r["force_converged"]
        print(f"  forces: ClA {r['ClA']:.4f} (hand 4.1667), CdA {r['CdA']:.4f} (hand 0.8333), front {r['aero_front']:.3f} (hand 0.500), converged {r['force_converged']}")
        # near-zero downforce: mean 0.5 N, band 0.2 N; floor 12 N -> band 1.67 % (without the floor 40 %)
        h0 = 0.5 + 0.1 * np.sin(np.arange(400))
        b0 = window_stats(h0, floor=12.0)["band"]
        ok &= abs(b0 - (h0[-200:].max() - h0[-200:].min()) / 12.0) < 1e-12 and b0 < BAND_MAX and window_stats(h0)["band"] > 0.3
        print(f"  near-zero downforce band with 12 N floor: {100 * b0:.2f} % (hand about 1.67 %)")
        yy, zz = np.meshgrid(np.linspace(0, 3, 31), np.linspace(0, 3, 31))
        n = yy.size; U = 20.0
        P = {"y": yy.ravel(), "z": zz.ravel(), "u": np.full(n, 0.8 * U), "v": np.zeros(n), "w": np.full(n, 0.1 * U), "k": np.full(n, 0.015 * U * U)}
        w = wake_metrics(P, U)
        ok &= abs(w["window_deficit"] - 0.2) < 1e-9 and abs(w["q_ratio"] - 0.64) < 1e-9 and abs(w["TI"] - 0.1) < 1e-9 and abs(w["upwash_deg"] - 7.125) < 0.01
        print(f"  wake: deficit {w['window_deficit']:.3f} (0.2), q-ratio {w['q_ratio']:.3f} (0.64), TI {w['TI']:.3f} (0.10), upwash {w['upwash_deg']:.2f} (7.13)")
        # a Gaussian blob: centre deficit and half-width read back
        P["u"] = U * (1 - 0.5 * np.exp(-((P["y"]) ** 2 + (P["z"] - 1.0) ** 2) / (2 * 0.3 ** 2)))
        P["y"] = yy.ravel(); w = wake_metrics(P, U)
        fwhm = 2 * 0.3 * math.sqrt(2 * math.log(2))
        ok &= abs(w["centre_deficit"] - 0.5) < 0.01 and abs(w["width_m"] - fwhm) < 0.03 and abs(w["centre_z_m"] - 1.0) < 0.011
        print(f"  gaussian: centre deficit {w['centre_deficit']:.3f} (0.5), width {w['width_m']:.3f} m (FWHM {fwhm:.3f}), centre z {w['centre_z_m']:.2f} (1.0)")
    print("postprocess self-test:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--update-variants", action="store_true", help="write the final CFD run per variant into params/aero_variants.csv (converged runs only)")
    ap.add_argument("--force", action="store_true", help="with --update-variants: also use runs that are not force-converged")
    ap.add_argument("--no-plots", action="store_true")
    args = ap.parse_args()
    return selftest() if args.selftest else run(args)


if __name__ == "__main__":
    sys.exit(main())
