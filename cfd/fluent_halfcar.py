#!/usr/bin/env python3
"""Half-car CFD in Ansys Fluent, driven from Python (PyFluent). No clicks.

    .venv/Scripts/python cfd/fluent_halfcar.py mesh  C            # mesh only  -> cfd/cases/halfcar_C.msh.h5
    .venv/Scripts/python cfd/fluent_halfcar.py solve C            # solve the saved mesh
    .venv/Scripts/python cfd/fluent_halfcar.py all   C            # both
    options: --scale 1.3 (body, floor, wheel, ground and refinement-box sizes times this)
             --wing-scale 1.0 (wing face sizes; the 2.5 mm minimum is never scaled)
             --speed 30 (m/s, default cfd speed from cfd_geometry.json)   --iters 1500
             --tag coarse (suffix on the case and result names)           --cores 4   --gui

STATUS (see cfd/fluent_halfcar_setup.md, "What has run"): every call below has
run on Ansys Student 2026 R1 with ansys-fluent-core 0.44 on this PC, at the
default sizes for all four variants (C: 955,009 cells; the licence refuses
1,048,576 or more). No mesh-independence study: only the ranking of the
variants is trustworthy, the absolute forces are not.

What it does
  mesh:  Fluent Meshing, Watertight Geometry workflow on cad/step/cfd/fluid_<V>.step
         (the air as one solid). Zones are named by matching each imported CAD
         face's bounding box to cad/step/cfd/faces_<V>.csv, because a STEP file
         carries no named selections that the Fluent reader keeps. Two bodies of
         influence (boi_near, boi_wake), face sizes per zone, boundary layers on
         the car and the wheels (2 layers), poly-hexcore volume mesh. Stops if
         the cell count is over the Student limit.
  solve: steady pressure-based coupled solver, k-omega SST, air 1.2 kg/m3,
         velocity inlet, pressure outlet, symmetry on Y = 0, side and top, ground
         moving with the air, wheels rotating about their axles, force and
         moment reports every iteration, residual and force convergence
         criteria, four wake planes exported as CSV.
Outputs
  cfd/cases/halfcar_<V><tag>.msh.h5, .cas.h5, .dat.h5      (git-ignored)
  cfd/results/runs/<V><tag>/forces.out      report file, one row per iteration (HALF car, N and N m)
  cfd/results/runs/<V><tag>/run_info.json   variant, speed, cells, iterations, zone areas, settings
  cfd/results/runs/<V><tag>/mesh_info.json  cell count, quality, zone list
  cfd/results/wake/<V><tag>_<n>L.csv        wake plane node values (read by cfd/postprocess.py and
                                            matlab/cfd/wake_postprocess.m)
Then run  .venv/Scripts/python cfd/postprocess.py
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEO = ROOT / "cad" / "step" / "cfd"
CASES = ROOT / "cfd" / "cases"
RESULTS = ROOT / "cfd" / "results"
ALLOW_OVER = False                      # --allow-over: write a mesh above the limit (only to test what the licence does)
STUDENT_CELL_LIMIT = 1_048_576          # Ansys Student 2026 R1: Fluent refuses more cells (see cfd/fluent_halfcar_setup.md)
CELL_TARGET = (800_000, 1_000_000)

# mesh sizes in mm at --scale 1 (multiplied by --scale, except the wing faces and the minimum: --wing-scale)
SIZES = {
    "min": 2.5, "max": 640.0, "growth": 1.2, "curvature_angle": 18.0,
    "face": {"car_fw": 12.0, "car_rw": 12.0, "wheel_front": 14.0, "wheel_rear": 14.0, "car_floor": 18.0, "car_body": 24.0, "ground": 160.0},
    "boi_near": 40.0, "boi_wake": 70.0,
    "vol_growth": 1.35, "cells_per_gap": 1.0, "proximity_to": "edges",
    "bl_layers": 2, "bl_rate": 1.2, "bl_transition": 0.272,
}
BOUNDARY_TYPES = {"inlet": "velocity-inlet", "outlet": "pressure-outlet", "symmetry": "symmetry", "side": "symmetry", "top": "symmetry"}
WALLS_STATIONARY = ["car_body", "car_floor", "car_fw", "car_rw"]
# --scale coarsens everything except these face sizes and the minimum size (--wing-scale):
# at 1.2 x the wing faces the slots and the rear flap at Y = 0 fail the surface mesh ("breakout detected")
WING_ZONES = ("car_fw", "car_rw")


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def set_aside(path: Path):
    """Fluent does not overwrite an existing file from a script (it asks, and
    the question goes unanswered, leaving the old file). Move an existing file
    to <name>.prev<suffixes> first; only one previous copy is kept."""
    if path.exists():
        suffix = "".join(path.suffixes)
        prev = path.with_name(path.name[: -len(suffix)] + ".prev" + suffix)
        os.replace(path, prev)
        log(f"  existing {path.name} moved to {prev.name}")


def load_geometry():
    f = GEO / "cfd_geometry.json"
    if not f.is_file():
        sys.exit(f"{f} not found: run  .venv/Scripts/python cad/generate/cfd_variants.py  first")
    return json.loads(f.read_text())


def launch(mode: str, cores: int, gui: bool, cwd: Path):
    if "AWP_ROOT261" not in os.environ:
        guess = Path(r"C:\Program Files\ANSYS Inc\ANSYS Student\v261")
        if guess.is_dir():
            os.environ["AWP_ROOT261"] = str(guess)
    import ansys.fluent.core as pyfluent
    cwd.mkdir(parents=True, exist_ok=True)
    log(f"launching Fluent ({mode}, {cores} cores), PyFluent {pyfluent.__version__}")
    # A start right after another session closed can fail (seen once: the new
    # process exits before PyFluent connects, most likely while the single
    # Student licence is still being released). Wait and try again.
    last = None
    for attempt in range(4):
        try:
            s = pyfluent.launch_fluent(mode=mode, precision="double", processor_count=cores, ui_mode="gui" if gui else "no_gui",
                                       start_timeout=300, cwd=str(cwd))
            break
        except Exception as e:  # noqa: BLE001
            last = e
            log(f"  launch attempt {attempt + 1} failed ({type(e).__name__}); waiting 45 s")
            time.sleep(45)
    else:
        raise RuntimeError(f"Fluent did not start after 4 attempts: {last}")
    log("  ", s.get_fluent_version())
    return s


# ---------------------------------------------------------------------------
# zone naming by bounding box
# ---------------------------------------------------------------------------
def read_faces(variant: str):
    rows = list(csv.DictReader(open(GEO / f"faces_{variant}.csv")))
    for r in rows:
        r["bbox_mm"] = [1000 * float(r[k]) for k in ("xmin_m", "xmax_m", "ymin_m", "ymax_m", "zmin_m", "zmax_m")]
    return rows


def zone_bbox(mu, zid):
    bb = mu.get_bounding_box_of_zone_list(zone_id_list=[zid])
    return [bb[0][0], bb[1][0], bb[0][1], bb[1][1], bb[0][2], bb[1][2]]


def match_zones(mu, ids, rows, what: str):
    """Group face zone ids by zone name: nearest CAD face by bounding box."""
    groups, worst = {}, 0.0
    for zid in ids:
        v = zone_bbox(mu, zid)
        scored = sorted((sum(abs(a - b) for a, b in zip(v, r["bbox_mm"])), r["zone"]) for r in rows)
        d, name = scored[0]
        size = max(v[1] - v[0], v[3] - v[2], v[5] - v[4], 1.0)
        # a mesh zone's box is a little inside the CAD face's box (facets cut curved edges)
        if d > max(6.0, 0.03 * size) * 6:
            other = next((s for s in scored if s[1] != name), None)
            raise RuntimeError(f"{what}: zone {zid} box {[round(x, 1) for x in v]} has no CAD face within tolerance "
                               f"(nearest {name} at {d:.1f} mm summed over six sides, next other zone {other})")
        worst = max(worst, d)
        groups.setdefault(name, []).append(zid)
    log(f"  {what}: {len(ids)} zones matched to {len(groups)} names, worst box mismatch {worst:.2f} mm")
    return groups


def merge_and_rename(mu, groups, prefix=""):
    """One zone per name. The imported CAD faces get the prefix 'geo-' so the
    plain names stay free for the surface mesh zones (a taken name would come
    back as name.<id>)."""
    for name, zl in groups.items():
        keep = mu.merge_face_zones(face_zone_id_list=zl) if len(zl) > 1 else zl[0]
        if not isinstance(keep, int):
            keep = zl[0]
        mu.rename_face_zone(zone_id=keep, new_name=prefix + name)


def mesh_zone_ids(mu, object_name: str):
    return list(mu.get_face_zones_of_object(object_name=object_name))


# ---------------------------------------------------------------------------
# meshing
# ---------------------------------------------------------------------------
def run_mesh(variant: str, scale: float, tag: str, cores: int, gui: bool, keep_session=False, wing_scale: float = 1.0):
    geo = load_geometry()
    rows = read_faces(variant)
    names_expected = sorted({r["zone"] for r in rows})
    k = scale
    name = f"halfcar_{variant}{tag}"
    run_dir = RESULTS / "runs" / f"{variant}{tag}"; run_dir.mkdir(parents=True, exist_ok=True)
    s = launch("meshing", cores, gui, CASES)
    info = {"variant": variant, "scale": scale, "wing_scale": wing_scale, "sizes_mm": SIZES, "started": time.strftime("%Y-%m-%d %H:%M:%S")}
    try:
        wt = s.watertight(); mu = s.meshing_utilities
        # 1. import: one zone per CAD face, and keep that separation in the surface mesh
        ig = wt.import_geometry
        ig.file_name.set_state(str(GEO / f"fluid_{variant}.step"))
        ig.length_unit.set_state("mm")
        ig.cad_import_options.one_zone_per.set_state("face")
        ig.import_cad_preferences.separate_zone_by.set_state("face")
        ig()
        geo_obj = [o for o in mu.get_objects(filter="*")][0]
        groups = match_zones(mu, mesh_zone_ids(mu, geo_obj), rows, "CAD faces")
        if sorted(groups) != names_expected:
            raise RuntimeError(f"zone names after import {sorted(groups)}, expected {names_expected}")
        merge_and_rename(mu, groups, prefix="geo-")

        # 2. bodies of influence
        wt.import_geometry.insertable_tasks.import_boi_geometry.insert()
        b = wt.import_boi_geometry
        b.geometry_file_name.set_state(str(GEO / "boi_boxes.step"))
        b()
        ls = wt.add_local_sizing_wtm
        ls.add_child.set_state("yes")
        ls.boi_execution.set_state("Body Of Influence")
        labels = list(ls.boi_face_label_list.allowed_values() or [])
        info["labels_after_boi_import"] = labels
        for bname in ("boi_near", "boi_wake"):
            lab = [x for x in labels if bname in x]
            if len(lab) != 1:
                raise RuntimeError(f"body of influence {bname}: labels offered are {labels}")
            ls.add_child.set_state("yes")
            ls.boi_execution.set_state("Body Of Influence")
            ls.boi_control_name.set_state(bname)
            ls.boi_zoneor_label.set_state("label")
            ls.boi_face_label_list.set_state(lab)
            ls.boi_size.set_state(SIZES[bname] * k)
            ls.add_child_and_update()
        # 3. face sizes per zone
        for zname, size in SIZES["face"].items():
            if zname not in groups:
                continue
            ls.add_child.set_state("yes")
            ls.boi_execution.set_state("Face Size")
            ls.boi_control_name.set_state(f"size_{zname}")
            ls.boi_zoneor_label.set_state("zone")
            ls.boi_face_zone_list.set_state(["geo-" + zname])
            ls.boi_size.set_state(size * (wing_scale if zname in WING_ZONES else k))
            ls.boi_growth_rate.set_state(SIZES["growth"])
            ls.add_child_and_update()

        # 4. surface mesh
        sm = wt.create_surface_mesh
        c = sm.cfd_surface_mesh_controls
        c.min_size.set_state(SIZES["min"]);   # never scaled: at 3 mm (one cell per gap) the slots fail
        c.max_size.set_state(SIZES["max"]); c.growth_rate.set_state(SIZES["growth"])
        c.size_functions.set_state("Curvature & Proximity"); c.curvature_normal_angle.set_state(SIZES["curvature_angle"])
        c.cells_per_gap.set_state(SIZES["cells_per_gap"]); c.scope_proximity_to.set_state(SIZES["proximity_to"])
        t0 = time.time(); sm(); log(f"  surface mesh in {time.time() - t0:.0f} s")
        mesh_obj = [o for o in mu.get_objects(filter="*") if o != geo_obj and not o.startswith("boi_")][0]
        groups = match_zones(mu, mesh_zone_ids(mu, mesh_obj), rows, "surface mesh zones")
        if sorted(groups) != names_expected:
            raise RuntimeError(f"zone names after the surface mesh {sorted(groups)}, expected {names_expected}")
        merge_and_rename(mu, groups)
        try:                                                 # where the surface faces are (each becomes a prism column)
            info["surface_faces"] = {z: int(mu.get_face_zone_count(face_zone_name_list=[z])) for z in names_expected}
            log(f"  surface faces by zone: {info['surface_faces']}")
        except Exception as e:  # noqa: BLE001
            log(f"  surface faces by zone not read: {e}")

        # 5. describe: one fluid region, nothing to cap, no share topology
        dg = wt.describe_geometry
        dg.setup_type.set_state("fluid")
        dg()
        ub = wt.update_boundaries
        zl = [z for z in BOUNDARY_TYPES if z in groups]
        ub.selection_type.set_state("zone")
        ub.boundary_zone_list.set_state(zl); ub.boundary_zone_type_list.set_state([BOUNDARY_TYPES[z] for z in zl])
        ub.old_boundary_zone_list.set_state(zl); ub.old_boundary_zone_type_list.set_state(["wall"] * len(zl))
        ub()
        wt.update_regions()

        # 6. boundary layers on the car and the wheels only (the ground moves with the air)
        bl = wt.add_boundary_layers
        bl.add_child.set_state("yes")
        bl.control_name.set_state("car_layers")
        bl.offset_method_type.set_state("smooth-transition")
        bl.number_of_layers.set_state(SIZES["bl_layers"]); bl.rate.set_state(SIZES["bl_rate"]); bl.transition_ratio.set_state(SIZES["bl_transition"])
        bl.face_scope.grow_on.set_state("selected-zones")
        bl.zone_selection_list.set_state([z for z in groups if z.startswith(("car_", "wheel_"))])
        bl.add_child_and_update()

        # 7. volume mesh
        vm = wt.create_volume_mesh_wtm
        vm.volume_fill.set_state("poly-hexcore")
        vm.volume_fill_controls.hex_max_cell_length.set_state(SIZES["max"])
        vm.volume_fill_controls.growth_rate.set_state(SIZES["vol_growth"])   # poly transition from the surface to the hex core: most of the cells
        t0 = time.time(); vm(); log(f"  volume mesh in {time.time() - t0:.0f} s")

        count = int(mu.get_cell_zone_count(cell_zone_name_pattern="*"))     # despite its name this is the number of cells in the matching zones
        info["cells"] = count
        log(f"  cells: {count:,}")
        try:
            q = mu.get_cell_quality_limits(cell_zone_name_pattern="*", measure="Orthogonal Quality")
            info["orthogonal_quality_min_avg_max"] = q; log(f"  orthogonal quality (min, max, avg ...): {q}")
        except Exception as e:  # noqa: BLE001
            info["orthogonal_quality_min_avg_max"] = f"not read: {e}"
        zones = {}
        for zid in mu.get_face_zones(filter="*"):
            nm = mu.convert_zone_ids_to_name_strings(zone_id_list=[zid])
            if nm and not nm[0].startswith(("origin-", "boi_")):
                zones[nm[0]] = mu.get_zone_type(zone_id=zid)
        info["zones"] = zones
        log(f"  zones: {zones}")
        missing = [z for z in names_expected if z not in zones]
        wrong = [z for z, t in BOUNDARY_TYPES.items() if zones.get(z) != t]
        if missing or wrong:
            raise RuntimeError(f"zones after meshing: missing {missing}, wrong type {wrong}; have {zones}")
        if count > STUDENT_CELL_LIMIT and not ALLOW_OVER:
            raise RuntimeError(f"{count:,} cells is over the Student limit of {STUDENT_CELL_LIMIT:,}: rerun with a larger --scale")
        if not (CELL_TARGET[0] <= count <= CELL_TARGET[1]):
            log(f"  NOTE: cell count outside the target {CELL_TARGET[0]:,} to {CELL_TARGET[1]:,}")
        mesh_file = CASES / f"{name}.msh.h5"
        set_aside(mesh_file)
        s.tui.file.write_mesh(str(mesh_file).replace("\\", "/"))
        if not mesh_file.exists():
            raise RuntimeError(f"{mesh_file} was not written")
        info["mesh_file"] = str(mesh_file); info["finished"] = time.strftime("%Y-%m-%d %H:%M:%S")
        (run_dir / "mesh_info.json").write_text(json.dumps(info, indent=1, default=str))
        log(f"  wrote {mesh_file}")
        if keep_session:
            return s, info
    finally:
        if not keep_session:
            s.exit()
    return None, info


# ---------------------------------------------------------------------------
# solver
# ---------------------------------------------------------------------------
def run_solve(variant: str, speed: float | None, iters: int, tag: str, cores: int, gui: bool, session=None):
    geo = load_geometry()
    U = float(speed if speed is not None else geo["reference"]["speed"])
    rho = float(geo["reference"]["density"]); mu_air = 1.8e-5
    name = f"halfcar_{variant}{tag}"
    run_dir = RESULTS / "runs" / f"{variant}{tag}"; run_dir.mkdir(parents=True, exist_ok=True)
    wake_dir = RESULTS / "wake"; wake_dir.mkdir(parents=True, exist_ok=True)
    fwd = lambda p: str(p).replace("\\", "/")  # noqa: E731
    if session is not None:
        s = session.switch_to_solver()
    else:
        s = launch("solver", cores, gui, CASES)
        s.settings.file.read_mesh(file_name=fwd(CASES / f"{name}.msh.h5"))
    info = {"variant": variant, "tag": tag, "speed_mps": U, "density": rho, "viscosity": mu_air, "iterations_requested": iters,
            "started": time.strftime("%Y-%m-%d %H:%M:%S"), "half_model": True}
    try:
        st = s.settings
        st.mesh.check()
        st.setup.general.solver.type = "pressure-based"
        st.setup.general.solver.time = "steady"
        v = st.setup.models.viscous
        v.model = "k-omega"; v.k_omega_model = "sst"
        air = st.setup.materials.fluid["air"]
        air.density.value = rho; air.viscosity.value = mu_air

        bc = st.setup.boundary_conditions
        walls = list(bc.wall.get_object_names())
        info["zones"] = {"wall": walls, "velocity_inlet": list(bc.velocity_inlet.get_object_names()),
                         "pressure_outlet": list(bc.pressure_outlet.get_object_names()), "symmetry": list(bc.symmetry.get_object_names())}
        log("  zones:", info["zones"])
        for need in ("ground", "wheel_front", "wheel_rear", "car_body"):
            if need not in walls:
                raise RuntimeError(f"wall zone {need} missing; walls are {walls}")
        inlet = bc.velocity_inlet["inlet"]
        inlet.momentum.velocity_magnitude.value = U
        inlet.turbulence.turbulence_specification = "Intensity and Viscosity Ratio"
        inlet.turbulence.turbulent_intensity = 0.005
        inlet.turbulence.turbulent_viscosity_ratio = 10
        outlet = bc.pressure_outlet["outlet"]
        outlet.momentum.gauge_pressure.value = 0
        outlet.turbulence.turbulence_specification = "Intensity and Viscosity Ratio"
        outlet.turbulence.backflow_turbulent_intensity = 0.005
        outlet.turbulence.backflow_turbulent_viscosity_ratio = 10
        g = bc.wall["ground"].momentum
        g.wall_motion = "Moving Wall"; g.relative = "Absolute"; g.velocity_spec = "Translational"
        g.speed.value = U; g.direction = [1, 0, 0]
        R = geo["wheels"]["radius_loaded_m"]; omega = U / R
        for zn, key in (("wheel_front", "front_centre_m"), ("wheel_rear", "rear_centre_m")):
            w = bc.wall[zn].momentum
            w.wall_motion = "Moving Wall"; w.relative = "Absolute"; w.velocity_spec = "Rotational"
            w.rotation_speed.value = omega
            w.rotation_axis_origin = geo["wheels"][key]
            w.rotation_axis_direction = [0, -1, 0]        # bottom of the tyre moves with the ground (+X): omega vector along -Y
        info["wheel_omega_rad_s"] = omega

        rv = st.setup.reference_values
        rv.area = geo["reference"]["area_m2"] / 2          # half model: half the reference area, so Fluent's own Cl and Cd are the car's
        rv.density = rho; rv.velocity = U; rv.length = geo["wheelbase_m"]; rv.viscosity = mu_air

        m = st.solution.methods
        m.p_v_coupling.flow_scheme = "Coupled"
        d = m.spatial_discretization.discretization_scheme
        d["pressure"] = "second-order"; d["mom"] = "second-order-upwind"; d["k"] = "second-order-upwind"; d["omega"] = "second-order-upwind"

        # ---- reports: half-car forces in N, moment about the Y axis through the front axle ground point in N m
        car_zones = [z for z in WALLS_STATIONARY if z in walls]
        groups = {"total": car_zones + ["wheel_front", "wheel_rear"], "wheels": ["wheel_front", "wheel_rear"]}
        groups.update({z: [z] for z in car_zones})
        rd = st.solution.report_definitions
        defs = []
        for gname, zl in groups.items():
            for qn, vec in (("drag", [1, 0, 0]), ("downforce", [0, 0, -1])):
                n = f"{qn}_{gname}"
                rd.force.create(n)
                rd.force[n] = {"force_vector": vec, "zones": zl}
                defs.append(n)
        rd.moment.create("pitch_moment_total")
        rd.moment["pitch_moment_total"] = {"mom_center": [0, 0, 0], "mom_axis": [0, 1, 0], "zones": groups["total"], "report_output_type": "Moment"}
        defs.append("pitch_moment_total")
        rf = st.solution.monitor.report_files
        rf.create("forces")
        rf["forces"] = {"file_name": fwd(run_dir / "forces.out"), "report_defs": defs, "frequency": 1, "print": False}
        info["report_defs"] = defs

        res = st.solution.monitor.residual
        for eq in ("continuity", "x-velocity", "y-velocity", "z-velocity", "k", "omega"):
            res.equations[eq].absolute_criteria = 1e-4
        # force convergence: stop when downforce and drag move less than 0.2 % over 100 iterations (after the first 300)
        cc = st.solution.monitor.convergence_conditions
        try:
            for n in ("downforce_total", "drag_total"):
                cc.convergence_reports.create(f"conv_{n}")
                cc.convergence_reports[f"conv_{n}"] = {"report_defs": n, "stop_criterion": 0.002, "previous_values_to_consider": 100,
                                                        "initial_values_to_ignore": 300, "print": True, "active": True}
            cc.condition = "all-conditions-are-met"
            info["force_convergence_criterion"] = "set: 0.2 % over 100 iterations after the first 300, on downforce_total and drag_total"
        except Exception as e:  # noqa: BLE001
            info["force_convergence_criterion"] = f"NOT SET ({type(e).__name__}: {str(e)[:200]}); judge convergence from forces.out (cfd/postprocess.py does)"
            log("  " + info["force_convergence_criterion"])

        st.solution.initialization.hybrid_initialize()
        for ext in (".cas.h5", ".dat.h5"):
            set_aside(CASES / f"{name}{ext}")
        set_aside(run_dir / "forces.out")
        s.settings.file.write_case(file_name=fwd(CASES / f"{name}.cas.h5"))
        t0 = time.time()
        st.solution.run_calculation.iterate(iter_count=iters)
        info["solve_seconds"] = round(time.time() - t0, 1)
        log(f"  {iters} iterations requested, {info['solve_seconds']:.0f} s")
        set_aside(CASES / f"{name}.cas.h5")
        s.settings.file.write_case_data(file_name=fwd(CASES / f"{name}.cas.h5"))

        # ---- wake planes ---------------------------------------------------
        wp = geo["wake_planes"]
        surf = st.results.surfaces.plane_surface
        exported = []
        for n, x in zip(wp["lengths_behind_rear_axle"], wp["x_m"]):
            pname = f"plane_{n:g}l".replace(".", "p")        # Fluent lower-cases surface names
            surf.create(pname)
            surf[pname].method = "yz-plane"
            surf[pname].x = x
            f = wake_dir / f"{variant}{tag}_{n:g}L.csv"
            set_aside(f)
            st.file.export.ascii(file_name=fwd(f), surface_name_list=[pname], delimiter="comma", location="node",
                                 quantities=["x-velocity", "y-velocity", "z-velocity", "turb-kinetic-energy", "total-pressure"])
            exported.append(str(f))
        info["wake_files"] = exported
        grid = s.scheme.eval("(inquire-grids)")           # ((id cells faces nodes dim))
        info["cells"] = int(grid[0][1]) if grid else None
        info["finished"] = time.strftime("%Y-%m-%d %H:%M:%S")
        (run_dir / "run_info.json").write_text(json.dumps(info, indent=1, default=str))
        log(f"  wrote {run_dir / 'run_info.json'}")
    finally:
        s.exit()
    return info


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=["mesh", "solve", "all"])
    ap.add_argument("variant", choices=["A", "B", "C", "D"])
    ap.add_argument("--scale", type=float, default=2.0, help="multiplies the body, floor, wheel, ground and refinement-box sizes")
    ap.add_argument("--wing-scale", type=float, default=1.0, help="multiplies the wing face sizes (the minimum size 2.5 mm is never scaled)")
    ap.add_argument("--speed", type=float, default=None)
    ap.add_argument("--iters", type=int, default=1500)
    ap.add_argument("--tag", default="")
    ap.add_argument("--cores", type=int, default=4)
    ap.add_argument("--gui", action="store_true")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE", help="override a SIZES entry, e.g. --set curvature_angle=20 (recorded in mesh_info.json)")
    ap.add_argument("--allow-over", action="store_true", help="write the mesh even above STUDENT_CELL_LIMIT (licence test)")
    a = ap.parse_args()
    global ALLOW_OVER
    ALLOW_OVER = a.allow_over
    for kv in a.set:
        k, v = kv.split("=", 1)
        if k not in SIZES or isinstance(SIZES[k], dict):
            sys.exit(f"--set {k}: not a SIZES entry ({[q for q in SIZES if not isinstance(SIZES[q], dict)]})")
        SIZES[k] = type(SIZES[k])(v)
    tag = f"_{a.tag}" if a.tag else ""
    if a.action in ("mesh", "all"):
        run_mesh(a.variant, a.scale, tag, a.cores, a.gui, wing_scale=a.wing_scale)
    if a.action in ("solve", "all"):
        run_solve(a.variant, a.speed, a.iters, tag, a.cores, a.gui)
    return 0


if __name__ == "__main__":
    sys.exit(main())
