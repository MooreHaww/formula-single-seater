"""Make the aerodynamics visible: stills, animations and smoke films from the saved
Fluent results (no new solves, no Fluent licence needed).

Reads cfd/cases/halfcar_<run>.cas.h5 + .dat.h5 with VTK's Fluent CFF reader
(vtkFLUENTCFFReader, VTK 9.7) and renders with PyVista (3D) and matplotlib (2D).

Variants (labels in every picture):
    A  run A   no wings
    B  run B_AB  moderate wings, as-built bodywork
    C  run CP    maximum wings, as-built (SolidWorks) bodywork (the lap sim uses it)
    D  run D_AB  wake-tuned, as-built bodywork, diffuser 12 deg (NOT D's 14 deg:
                 14 deg did not mesh on this bodywork), 1 prism layer
B, C and D share the as-built bodywork (SolidWorks nose, sidepods, 10 mm floor
plate) since 2026-11-25; A has the older CFD bodywork (see cfd/geometry_notes.md).
The old B and D pictures (older bodywork) are in media/cfd/vis_old_simplified/.

Steps (each reads what the step before it wrote):
    export   case/data -> cfd/cases/vis/<run>/ (git-ignored cache):
             car.vtp   car and wheel surface; Cp and the near-wall values are those of
                       the wall-adjacent cell (first prism layer), not wall values
             near.vti  12.5 mm grid around the car (X -1.3..3.4, Y 0..0.95, Z 0..1.8 m)
             wake.vti  30 mm grid to 3.2 car lengths (X -1.3..11.2, Y 0..1.6, Z 0..2.8 m)
             Both grids are resampled (linear, inside each Fluent cell) from the
             cell values averaged to the mesh nodes; vorticity and Q from them.
    stills   media/cfd/vis/<V>_*.png
    anims    media/cfd/vis/<V>_orbit / _sweep / _buildup .mp4 + .gif
    compare  media/cfd/vis/compare_ABCD.png + .mp4 + .gif
    smoke    media/cfd/vis/smoke_<V>.mp4 + .gif (C, D, A) and smoke_ABD.mp4 + .gif
    all      everything above, in that order

Usage:
    .venv/Scripts/python cfd/visualise.py all
    .venv/Scripts/python cfd/visualise.py smoke C          # one smoke film (C, D or A)
    .venv/Scripts/python cfd/visualise.py smoke ABD        # the A-B-D smoke side by side
    .venv/Scripts/python cfd/visualise.py anims C --only orbit   # one film (orbit, sweep, buildup)
    .venv/Scripts/python cfd/visualise.py stills A B       # some variants
    .venv/Scripts/python cfd/visualise.py --selftest

Everything is a steady RANS solution (k-omega SST) of a half car on a Student mesh
(about 1 million cells), mirrored for the pictures. Only the ranking of the variants
is trustworthy; every picture says so.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "cfd" / "cases"
CACHE = CASES / "vis"
OUT = ROOT / "media" / "cfd" / "vis"
RESULTS = ROOT / "cfd" / "results"

U_INF, RHO = 20.0, 1.2
Q_INF = 0.5 * RHO * U_INF ** 2                  # 240 Pa
CAR_LENGTH, WHEELBASE = 2.95, 1.55
SLICES_L = (1.0, 2.0, 3.0)                        # car lengths behind the rear axle
def slice_x(n_l: float) -> float:
    return WHEELBASE + n_l * CAR_LENGTH            # 4.50, 7.45, 10.40 m

VARIANTS = {   # label -> (run folder, title)
    "A": ("A", "A  no wings"),
    "B": ("B_AB", "B  moderate wings, as-built bodywork (run B_AB)"),
    "C": ("CP", "C  max wings, SolidWorks bodywork (run CP)"),
    "D": ("D_AB", "D  wake-tuned, as-built bodywork, diffuser 12° not 14° (run D_AB)"),
}
SMOKE_VARIANTS = ("C", "D", "A")

GRIDS = {   # name: (origin, spacing, upper corner), metres
    "near": ((-1.30, 0.004, 0.004), 0.0125, (3.40, 0.95, 1.80)),
    "wake": ((-1.30, 0.004, 0.004), 0.030, (11.20, 1.60, 2.80)),
}
CAR_BOX = ((-1.30, 2.60), (2e-4, 0.95), (2e-4, 1.70))   # boundary faces inside this box are car or wheel walls

# common colour scales (the same in every picture, so variants compare side by side)
CLIM = {"Cp": (-3.0, 1.0), "speed": (0.0, 1.4), "deficit": (0.0, 0.6), "k": (0.0, 8.0), "wx": (-200.0, 200.0)}
CMAP = {"Cp": "RdBu_r", "speed": "turbo", "deficit": "magma", "k": "viridis", "wx": "coolwarm"}
BODY_NOTE = ("B, C and D are on the same as-built bodywork (D's diffuser is 12 degrees here, not 14); "
             "A is on the older CFD bodywork. ")
CAPTION = (BODY_NOTE + "Steady RANS (k-omega SST), half car mirrored, Student mesh of about 1 million cells, 20 m/s. "
           "Only the ranking of the variants is trustworthy, not the absolute values.")
SMOKE_CAPTION = (BODY_NOTE + "Steady-state RANS solution: the smoke shows time-averaged streamlines, not real unsteady "
                 "turbulence. Only the ranking of the variants is trustworthy.")


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


# ---------------------------------------------------------------------------- export
def read_case(run: str):
    """Fluent CFF case + data -> pyvista UnstructuredGrid with Cp, U (vector), k (cell data)."""
    import vtk
    import pyvista as pv
    cas = CASES / f"halfcar_{run}.cas.h5"
    if not cas.exists() or not cas.with_name(f"halfcar_{run}.dat.h5").exists():
        raise FileNotFoundError(f"{cas} or its .dat.h5 is missing: rerun `.venv/Scripts/python cfd/fluent_halfcar.py all {run}`")
    r = vtk.vtkFLUENTCFFReader()
    r.SetFileName(str(cas))
    r.UpdateInformation()
    want = {"SV_P", "SV_U", "SV_V", "SV_W", "SV_K"}
    for i in range(r.GetNumberOfCellArrays()):
        n = r.GetCellArrayName(i)
        r.SetCellArrayStatus(n, int(n in want))
    r.Update()
    ug = pv.wrap(r.GetOutput())[0]
    cd = ug.cell_data
    U = np.c_[cd["SV_U"], cd["SV_V"], cd["SV_W"]].astype(np.float32)
    Cp = (np.asarray(cd["SV_P"]) / Q_INF).astype(np.float32)
    k = np.asarray(cd["SV_K"], dtype=np.float32)
    ug.clear_data()
    ug.cell_data["U"] = U
    ug.cell_data["Cp"] = Cp
    ug.cell_data["k"] = k
    return ug


def car_surface(ug):
    """Car and wheel walls: the fluid's boundary faces inside CAR_BOX, minus the
    symmetry plane (Y = 0) and the ground (Z = 0)."""
    surf = ug.extract_surface(algorithm="dataset_surface")
    c = surf.cell_centers().points
    (x0, x1), (y0, y1), (z0, z1) = CAR_BOX
    m = (c[:, 0] > x0) & (c[:, 0] < x1) & (c[:, 1] > y0) & (c[:, 1] < y1) & (c[:, 2] > z0) & (c[:, 2] < z1)
    car = surf.extract_cells(np.flatnonzero(m)).extract_surface(algorithm="dataset_surface")
    car.cell_data["speed"] = np.linalg.norm(car.cell_data["U"], axis=1) / U_INF
    return car


def resample(ugp, name: str):
    import pyvista as pv
    (ox, oy, oz), h, (ux, uy, uz) = GRIDS[name]
    dims = (int(round((ux - ox) / h)) + 1, int(round((uy - oy) / h)) + 1, int(round((uz - oz) / h)) + 1)
    g = pv.ImageData(dimensions=dims, spacing=(h, h, h), origin=(ox, oy, oz))
    s = g.sample(ugp)
    valid = np.asarray(s["vtkValidPointMask"]).astype(bool)
    U = np.asarray(s["U"], dtype=np.float32)
    U[~valid] = 0.0                                          # inside the car: no flow
    out = pv.ImageData(dimensions=dims, spacing=(h, h, h), origin=(ox, oy, oz))
    out.point_data["U"] = U
    out.point_data["Cp"] = np.where(valid, s["Cp"], 0.0).astype(np.float32)
    out.point_data["k"] = np.where(valid, s["k"], 0.0).astype(np.float32)
    out.point_data["valid"] = valid.astype(np.uint8)
    d = out.compute_derivative(scalars="U", gradient=False, vorticity=True, qcriterion=True)
    out.point_data["vorticity"] = np.asarray(d["vorticity"], dtype=np.float32)
    out.point_data["Q"] = np.asarray(d["qcriterion"], dtype=np.float32)
    return out


def export_run(run: str, force: bool = False) -> str:
    d = CACHE / run
    if not force and all((d / f).exists() for f in ("car.vtp", "near.vti", "wake.vti", "info.json")):
        return f"{run}: cached"
    d.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    ug = read_case(run)
    car = car_surface(ug)
    car.save(d / "car.vtp")
    ugp = ug.cell_data_to_point_data()
    times = {}
    for name in GRIDS:
        t = time.time()
        g = resample(ugp, name)
        g.save(d / f"{name}.vti")
        times[name] = round(time.time() - t)
    info = {"run": run, "cells": ug.n_cells, "car_faces": car.n_cells, "car_bounds": list(map(float, car.bounds)),
            "grid_seconds": times, "made": time.strftime("%Y-%m-%d %H:%M"),
            "source": f"cfd/cases/halfcar_{run}.cas.h5 + .dat.h5"}
    (d / "info.json").write_text(json.dumps(info, indent=1))
    return f"{run}: exported in {time.time() - t0:.0f} s ({ug.n_cells:,} cells, car {car.n_cells:,} faces, grids {times})"


def step_export(labels, force=False, workers=4):
    runs = [VARIANTS[v][0] for v in labels]
    log("export", runs)
    with ProcessPoolExecutor(max_workers=min(workers, len(runs))) as ex:
        for msg in ex.map(export_run, runs, [force] * len(runs)):
            log(" ", msg)


def load(label: str):
    import pyvista as pv
    run = VARIANTS[label][0]
    d = CACHE / run
    if not (d / "info.json").exists():
        log(f"  {run}: no cache, exporting first")
        log(" ", export_run(run))
    return {"car": pv.read(d / "car.vtp"), "near": pv.read(d / "near.vti"), "wake": pv.read(d / "wake.vti"),
            "info": json.loads((d / "info.json").read_text()), "run": run, "label": label, "title": VARIANTS[label][1]}


# ---------------------------------------------------------------------------- main
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", default="all",
                    choices=["export", "stills", "anims", "compare", "smoke", "all"])
    ap.add_argument("variants", nargs="*",
                    help="A B C D (default: all four; smoke: C D A and the A-B-D side by side; "
                         "smoke ABD: only the side by side)")
    ap.add_argument("--only", choices=["orbit", "sweep", "buildup"], help="anims: only this film")
    ap.add_argument("--force", action="store_true", help="export: redo the cache")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    given = [v.upper() for v in a.variants]
    side = "ABD" in given                       # the smoke side-by-side film
    if side and a.step != "smoke":
        ap.error("ABD (the smoke side-by-side film) goes with the smoke step: visualise.py smoke ABD")
    labels = [v for v in given if v != "ABD"] or ([] if side else list(VARIANTS))
    bad = [v for v in labels if v not in VARIANTS]
    if bad:
        ap.error(f"unknown variant(s) {bad}; use A B C D")
    OUT.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    if a.step in ("export", "all"):
        step_export(labels, a.force)
    if a.step in ("stills", "all"):
        import vis_render as vr
        for v in labels:
            vr.stills(load(v))
    if a.step in ("anims", "all"):
        import vis_render as vr
        for v in labels:
            vr.anims(load(v), only=a.only)
    if a.step in ("compare", "all"):
        import vis_render as vr
        vr.compare([load(v) for v in "ABCD"])
    if a.step in ("smoke", "all"):
        import vis_smoke as vs
        films = list(SMOKE_VARIANTS) if (a.step == "all" or not given) else labels
        for v in films:
            vs.smoke_film(load(v))
        if side or not given or a.step == "all":
            vs.smoke_side_by_side([load(v) for v in "ABD"])
    log(f"done in {time.time() - t0:.0f} s; pictures in {OUT}")
    return 0


def selftest() -> int:
    """Hand-checkable: Cp of a known pressure; slice positions; vorticity of a solid-body
    rotation on a small grid (omega_x = 2 * Omega)."""
    import pyvista as pv
    ok = True
    def check(name, got, want, tol):
        nonlocal ok
        good = abs(got - want) <= tol
        ok &= good
        print(f"  {'ok  ' if good else 'FAIL'} {name}: {got:.4f} vs hand {want:.4f}")
    check("Cp of -480 Pa at 20 m/s", -480.0 / Q_INF, -2.0, 1e-9)
    check("slice 1 L (m)", slice_x(1.0), 4.50, 1e-9)
    check("slice 3 L (m)", slice_x(3.0), 10.40, 1e-9)
    g = pv.ImageData(dimensions=(5, 11, 11), spacing=(0.1, 0.1, 0.1), origin=(0, -0.5, -0.5))
    p = g.points
    om = 3.0                                   # rad/s about +X: v = -om z, w = om y
    g.point_data["U"] = np.c_[np.full(len(p), 20.0), -om * p[:, 2], om * p[:, 1]]
    d = g.compute_derivative(scalars="U", gradient=False, vorticity=True)
    check("x-vorticity of solid-body rotation 3 rad/s", float(np.median(d["vorticity"][:, 0])), 2 * om, 1e-6)
    # smoke particles on a straight 20 m/s streamline: released at t = 0, 0.25, 0.5 s;
    # at t = 0.6 s they are 0.6, 0.35 and 0.1 s old -> heads at X 12, 7 and 2 m
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from vis_smoke import particles
    T = np.linspace(0.0, 1.0, 11)
    line = (np.c_[20.0 * T, np.zeros(11), np.zeros(11)], T, np.ones(11), 0.0)
    poly = particles([line], 0.6, dt=0.25, tail=0.05, nseg=2)
    heads = np.sort(np.asarray(poly.points)[1::2, 0])
    check("smoke: number of particles at t 0.6 s", len(heads), 3, 0)
    for got, want in zip(heads, (2.0, 7.0, 12.0)):
        check(f"smoke: particle head X (m), {want / 20:.2f} s old", got, want, 1e-9)
    check("smoke: streak length (m) for a 0.05 s tail", float(np.ptp(np.asarray(poly.points)[0:2, 0])), 1.0, 1e-9)
    print(f"visualise self-test: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
