#!/usr/bin/env python3
"""Force on the rear-wing supports from a saved solution, by summing per-face pressure
and wall shear (docs/wing_supports_plan.md).

    .venv/Scripts/python cfd/support_forces.py export CP        # Fluent: reads halfcar_CP.cas.h5/.dat.h5, writes face CSVs (no case is saved)
    .venv/Scripts/python cfd/support_forces.py sum CP           # no Fluent: sums the CSVs, checks them, prints and writes JSON
    .venv/Scripts/python cfd/support_forces.py --selftest

Why: CP's rear pylon is part of the rear-wing zone car_rw, so Fluent's reports give the
wing and pylon together. The variants E-H have the support in its own zone (car_rws).
For CP and CP_bl1 the pylon faces are picked out of car_rw by position and normal:
    centre within the pylon's box (X 1666-1896 mm, Y 141.5-158.5 mm, Z below 1135 mm,
    i.e. under the wing's lower surface) and a nearly horizontal normal (|n_z| < 0.5).
Force on the wall from the faces: F = sum(p * A_vec) + sum(tau * |A|), with p the gauge
pressure (Fluent's reports use the same, reference pressure 0) and A_vec the face area
vector Fluent exports for boundary faces. The method is checked on whole zones: the
sum over every face of car_rw (and car_rws) must match Fluent's own report for that zone
at the saved iteration (the last row of forces.out) within CHECK_TOL.

The saved data is ONE iteration. CP is unsteady (downforce band 2.5 %), so a snapshot
differs from the 200-iteration mean used elsewhere; the JSON gives the zone's snapshot /
mean ratio so that difference can be judged. Half car, N; downforce is -Fz.

Outputs: cfd/cases/support_faces/<run>_<zone>.csv (git-ignored),
         cfd/results/runs/<run>/support_forces.json
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "cfd"))
CASES = ROOT / "cfd" / "cases"
RUNS = ROOT / "cfd" / "results" / "runs"
FACES = CASES / "support_faces"
QUANT = ["pressure", "x-wall-shear", "y-wall-shear", "z-wall-shear", "x-face-area", "y-face-area", "z-face-area"]
PYLON_BOX = {"x": (1666.0, 1896.0), "y": (141.5, 158.5), "z_max": 1135.0, "nz_max": 0.5}     # mm, CP's rear pylon
CHECK_TOL = 0.01                                                                          # 1 % of the zone's downforce


def export(run: str, cores: int = 4) -> int:
    import fluent_halfcar as fh
    FACES.mkdir(parents=True, exist_ok=True)
    s = fh.launch("solver", cores, False, CASES)
    try:
        s.settings.file.read_case_data(file_name=fh.fwd(CASES / f"halfcar_{run}.cas.h5"))
        walls = list(s.settings.setup.boundary_conditions.wall.get_object_names())
        zones = [z for z in ("car_rw", "car_rws") if z in walls]
        for z in zones:
            f = FACES / f"{run}_{z}.csv"
            fh.set_aside(f)
            s.settings.file.export.ascii(file_name=fh.fwd(f), surface_name_list=[z], delimiter="comma",
                                         location="cell-center", quantities=QUANT)
            print("wrote", f, flush=True)
    finally:
        s.exit()
    return 0


def read_faces(path: Path) -> dict:
    with path.open() as fh_:
        rd = csv.reader(fh_)
        head = [h.strip() for h in next(rd)]
        rows = [[float(v) for v in r] for r in rd if r and r[0].strip()]
    a = np.array(rows)
    return {h: a[:, k] for k, h in enumerate(head)}


def col(d: dict, name: str) -> np.ndarray:
    """Column by name, ignoring case and spaces (Fluent's header spelling varies)."""
    key = name.replace(" ", "").lower()
    for k in d:
        if k.replace(" ", "").lower() == key:
            return d[k]
    raise KeyError(f"{name} not in {list(d)}")


def face_forces(d: dict, sign_shear: float = 1.0):
    """Per-face force vectors (N) from a face table: pressure * area vector + shear * |area|."""
    A = np.column_stack([col(d, "x-face-area"), col(d, "y-face-area"), col(d, "z-face-area")])
    p = col(d, "pressure")
    tau = np.column_stack([col(d, "x-wall-shear"), col(d, "y-wall-shear"), col(d, "z-wall-shear")])
    Am = np.linalg.norm(A, axis=1)
    return p[:, None] * A + sign_shear * tau * Am[:, None], A, Am


def last_row(run: str) -> dict:
    import postprocess as pp
    F = pp.read_forces_all(RUNS / run)
    return {k: float(v[-1]) for k, v in F.items()}, {k: v for k, v in F.items()}


def pylon_mask(d: dict, A: np.ndarray, Am: np.ndarray) -> np.ndarray:
    x, y, z = (col(d, c) * 1000.0 for c in ("x-coordinate", "y-coordinate", "z-coordinate"))
    nz = np.abs(A[:, 2]) / np.maximum(Am, 1e-30)
    b = PYLON_BOX
    return (x > b["x"][0]) & (x < b["x"][1]) & (y > b["y"][0]) & (y < b["y"][1]) & (z < b["z_max"]) & (nz < b["nz_max"])


def summarise(run: str) -> dict:
    last, hist = last_row(run)
    out = {"run": run, "note": "half car, N; snapshot of the saved iteration; downforce = -Fz", "zones": {}}
    import postprocess as pp
    for z in ("car_rw", "car_rws"):
        f = FACES / f"{run}_{z}.csv"
        if not f.exists():
            continue
        d = read_faces(f)
        best = None
        for sgn in (1.0, -1.0):                     # shear sign convention: the one that matches Fluent's report
            Fv, A, Am = face_forces(d, sgn)
            tot = Fv.sum(axis=0)
            err = abs(-tot[2] - last[f"downforce_{z}"]) / max(abs(last[f"downforce_{z}"]), 1.0) + \
                abs(tot[0] - last[f"drag_{z}"]) / max(abs(last[f"drag_{z}"]), 1.0)
            if best is None or err < best[0]:
                best = (err, sgn, Fv, A, Am, tot)
        err, sgn, Fv, A, Am, tot = best
        zr = {"faces": int(len(Am)), "shear_sign": sgn,
              "sum_downforce_N": float(-tot[2]), "sum_drag_N": float(tot[0]),
              "fluent_downforce_N_last": last[f"downforce_{z}"], "fluent_drag_N_last": last[f"drag_{z}"],
              "mean200_downforce_N": float(pp.window_stats(hist[f"downforce_{z}"])["mean"]),
              "mean200_drag_N": float(pp.window_stats(hist[f"drag_{z}"])["mean"])}
        zr["check_downforce_rel"] = (zr["sum_downforce_N"] - zr["fluent_downforce_N_last"]) / max(abs(zr["fluent_downforce_N_last"]), 1.0)
        zr["check_drag_rel"] = (zr["sum_drag_N"] - zr["fluent_drag_N_last"]) / max(abs(zr["fluent_drag_N_last"]), 1.0)
        zr["check_pass"] = abs(zr["check_downforce_rel"]) < CHECK_TOL and abs(zr["check_drag_rel"]) < CHECK_TOL
        if z == "car_rw" and run.startswith("CP"):
            m = pylon_mask(d, A, Am)
            Fp = Fv[m].sum(axis=0)
            zr["pylon"] = {"faces": int(m.sum()), "area_m2": float(Am[m].sum()),
                           "downforce_N": float(-Fp[2]), "drag_N": float(Fp[0]), "side_N": float(Fp[1])}
        if z == "car_rws":
            zr["support"] = {"faces": int(len(Am)), "area_m2": float(Am.sum()), "downforce_N": float(-tot[2]),
                             "drag_N": float(tot[0]), "side_N": float(tot[1])}
        out["zones"][z] = zr
    (RUNS / run / "support_forces.json").write_text(json.dumps(out, indent=1))
    return out


def selftest() -> int:
    """A closed unit cube at uniform pressure has zero net force; a plate of 2 m2 at 3 Pa
    with outward normal -z (fluid above pushes down) gives downforce 6 N."""
    faces = []
    for ax in range(3):
        for s_ in (-1, 1):
            a = [0.0, 0.0, 0.0]; a[ax] = s_ * 1.0
            faces.append([0.0, 0.0, 0.0, 5.0, 0.0, 0.0, 0.0, *a])
    hdr = ["x-coordinate", "y-coordinate", "z-coordinate"] + QUANT
    d = {h: np.array([r[k] for r in faces]) for k, h in enumerate(hdr)}
    Fv, _, _ = face_forces(d)
    ok1 = np.allclose(Fv.sum(axis=0), 0.0)
    d2 = {h: np.array([v]) for h, v in zip(hdr, [0, 0, 0, 3.0, 0, 0, 0, 0, 0, -2.0])}
    Fv2, _, _ = face_forces(d2)
    ok2 = abs(-Fv2.sum(axis=0)[2] - 6.0) < 1e-12
    print(f"selftest closed cube net force zero: {'PASS' if ok1 else 'FAIL'}; plate downforce 6 N: {'PASS' if ok2 else 'FAIL'}")
    return 0 if ok1 and ok2 else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", nargs="?", choices=["export", "sum"])
    ap.add_argument("run", nargs="?")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.action == "export":
        return export(a.run)
    r = summarise(a.run)
    print(json.dumps(r, indent=1))
    return 0 if all(z["check_pass"] for z in r["zones"].values()) else 1


if __name__ == "__main__":
    sys.exit(main())
