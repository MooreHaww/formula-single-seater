#!/usr/bin/env python3
"""Comparison table of the wing-support runs (front-wing round, docs/wing_supports_plan.md).

    .venv/Scripts/python cfd/support_table.py CP_bl1 CP_bl1r F_bl1 J_bl1 CPFF_bl1   # the first run is the reference
    .venv/Scripts/python cfd/support_table.py --selftest
    .venv/Scripts/python cfd/support_table.py CP_bl1 FINAL_bl1 --out cfd/results/final_table.csv   # another output file

Per run, from cfd/results/runs/<run>/ (forces.out: 200-iteration means, as cfd/postprocess.py)
and cfd/results/wake_cfd.csv (run cfd/postprocess.py first):
  - ClA, CdA, L/D, front share (postprocess.analyse_run, full car);
  - front support force, half car (N): zone car_fws if the run has it (200-it mean), else CP's flat
    front pylon picked out of car_fw by the face export (support_forces.json, a snapshot of the
    saved iteration);
  - rear support force, half car: car_rws, else the rear pylon from the face export;
  - front-wing downforce, full car (N): with its support (car_fw + car_fws, or car_fw that holds the
    pylon) and without it (minus the support / pylon);
  - wake q-ratio in the follower's window at 1, 2, 3 L (wake_cfd.csv).
Differences of the totals are given against the reference in %, and flagged when larger than
SPREAD (CP's 2.2 % run-to-run spread). Writes cfd/results/support_table.csv and prints a
markdown table. Steady RANS, one run per variant: only the ranking is trustworthy.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "cfd"))
RUNS = ROOT / "cfd" / "results" / "runs"
OUT = ROOT / "cfd" / "results" / "support_table.csv"
SPREAD = 2.2                                    # %, CP vs CP_bl1 ClA


def pct(a: float, b: float) -> float:
    """Change of a against b in % (b the reference)."""
    return 100.0 * (a / b - 1.0)


def support(run: str, F: dict, zone: str, wing: str):
    """(downforce, drag, source) of a support, half car, N."""
    import postprocess as pp
    if f"drag_{zone}" in F:
        return pp.window_stats(F[f"downforce_{zone}"])["mean"], pp.window_stats(F[f"drag_{zone}"])["mean"], "zone, 200-it mean"
    js = RUNS / run / "support_forces.json"
    if js.exists():
        p = json.loads(js.read_text())["zones"].get(wing, {}).get("pylon")
        if p:
            return p["downforce_N"], p["drag_N"], "face export, snapshot"
    return float("nan"), float("nan"), "missing"


def row(run: str, wb: float) -> dict:
    import postprocess as pp
    r, F = pp.analyse_run(RUNS / run, wb)
    q = 0.5 * r["density"] * r["speed_mps"] ** 2
    fdn, fdr, fsrc = support(run, F, "car_fws", "car_fw")
    rdn, rdr, rsrc = support(run, F, "car_rws", "car_rw")
    fw = 2 * pp.window_stats(F["downforce_car_fw"])["mean"]
    has_fws = "drag_car_fws" in F
    fw_with = fw + (2 * fdn if has_fws else 0.0)
    fw_wing = fw if has_fws else fw - 2 * fdn
    out = {"run": run, "cells": r["cells"], "converged": r["force_converged"], "ClA": r["ClA"], "CdA": r["CdA"], "L_over_D": r["L_over_D"],
           "aero_front": r["aero_front"], "fws_down_N_half": fdn, "fws_drag_N_half": fdr, "fws_source": fsrc,
           "rws_down_N_half": rdn, "rws_drag_N_half": rdr, "rws_source": rsrc,
           "fw_down_with_support_N": fw_with, "fw_down_wing_only_N": fw_wing, "ClA_fw_with_support": fw_with / q}
    wk = ROOT / "cfd" / "results" / "wake_cfd.csv"
    if wk.exists():
        for w in csv.DictReader(wk.open()):
            if w["run"] == run and float(w["plane_L"]) in (1.0, 2.0, 3.0):
                out[f"q_ratio_{int(float(w['plane_L']))}L"] = float(w["q_ratio"])
    return out


def main(argv) -> int:
    if "--selftest" in argv:
        return selftest()
    out = OUT
    if "--out" in argv:                         # another table file (the FINAL car, 2026-11-28), relative to the repo root
        i = argv.index("--out"); out = ROOT / argv[i + 1]; argv = argv[:i] + argv[i + 2:]
    geo = json.loads((ROOT / "cad" / "step" / "cfd" / "cfd_geometry.json").read_text())
    rows = [row(r, geo["wheelbase_m"]) for r in argv]
    ref = rows[0]
    for r in rows:
        for k in ("ClA", "CdA", "L_over_D", "fw_down_with_support_N"):
            r[f"d_{k}_pct"] = pct(r[k], ref[k])
        r["d_aero_front"] = r["aero_front"] - ref["aero_front"]
        r["beyond_spread"] = ",".join(k for k in ("ClA", "CdA") if abs(r[f"d_{k}_pct"]) > SPREAD) or "none"
    keys = list(rows[0])
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys); w.writeheader()
        w.writerows([{k: (f"{v:.5g}" if isinstance(v, float) else v) for k, v in r.items()} for r in rows])
    print("| | " + " | ".join(r["run"] for r in rows) + " |\n|---|" + "---|" * len(rows))
    def line(lab, fn):
        print(f"| {lab} | " + " | ".join(fn(r) for r in rows) + " |")
    line("cells", lambda r: f"{r['cells']:,}")
    line("front support down / drag, half car (N)", lambda r: f"{r['fws_down_N_half']:.2f} / {r['fws_drag_N_half']:.2f}")
    line("rear support down / drag, half car (N)", lambda r: f"{r['rws_down_N_half']:.2f} / {r['rws_drag_N_half']:.2f}")
    line("ClA", lambda r: f"{r['ClA']:.3f} ({r['d_ClA_pct']:+.1f} %)")
    line("CdA", lambda r: f"{r['CdA']:.3f} ({r['d_CdA_pct']:+.1f} %)")
    line("L/D", lambda r: f"{r['L_over_D']:.3f}")
    line("front share", lambda r: f"{r['aero_front']:.3f} ({r['d_aero_front']:+.3f})")
    line("front wing downforce with / without its support, full car (N)",
         lambda r: f"{r['fw_down_with_support_N']:.1f} / {r['fw_down_wing_only_N']:.1f} ({r['d_fw_down_with_support_N_pct']:+.1f} %)")
    line("q-ratio 1 / 2 / 3 L", lambda r: " / ".join(f"{r.get(f'q_ratio_{n}L', float('nan')):.2f}" for n in (1, 2, 3)))
    line(f"totals beyond {SPREAD} %", lambda r: r["beyond_spread"])
    print("wrote", out)
    return 0


def selftest() -> int:
    """pct(102.2, 100) = +2.2 %; pct(97.8, 100) = -2.2 %."""
    ok = abs(pct(102.2, 100.0) - 2.2) < 1e-9 and abs(pct(97.8, 100.0) + 2.2) < 1e-9
    print(f"support_table self-test: pct +2.2 / -2.2: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
