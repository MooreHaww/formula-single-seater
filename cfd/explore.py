"""Open one saved CFD result in Ansys CFD-Post (default) or the Fluent window, with
the pictures of cfd/visualise.py already set up, ready to explore and screen-record.

    .venv/Scripts/python cfd/explore.py C              # CFD-Post window, run CP
    .venv/Scripts/python cfd/explore.py D --fluent     # Fluent window (PyFluent, GUI)
    .venv/Scripts/python cfd/explore.py A --test       # CFD-Post in batch: writes a check picture, no window

Variants: A, B, C (= run CP), D, or any run folder name (E, CP, ...).

CFD-Post opens with (Outline tree, tick the boxes to show or hide):
    car Cp            car and wheel walls coloured by Cp = p / 240 Pa, -3 to +1
    symmetry speed    speed on the centre plane Y = 0, 0 to 28 m/s (hidden at start: it is the
                      same orange as the streamlines; tick it to see the centre-plane wake)
    wake 1L/2L/3L     planes at 1, 2, 3 car lengths behind the rear axle (X 4.50, 7.45,
                      10.40 m), velocity deficit 1 - u/U, 0 to 0.6
    wake k 1L/2L/3L   the same planes, turbulence kinetic energy 0 to 8 m2/s2 (hidden)
    streamlines       from 4 seed lines 1.25 m ahead of the car, coloured by speed
    view              three-quarter from front right (the half model is Y >= 0)
    legends           Cp (top left), streamline speed (bottom left), wake deficit (right)
The session file is written to cfd/cases/vis/explore_<run>.cse (git-ignored); edit it
or save your own state from CFD-Post. Steady RANS on a Student mesh: only the ranking
of the variants is trustworthy.
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "cfd" / "cases"
VIS = CASES / "vis"
AWP = Path(r"C:\Program Files\ANSYS Inc\ANSYS Student\v261")
CFDPOST = AWP / "CFD-Post" / "bin" / "cfdpost.exe"
LABELS = {"A": "A", "B": "B", "C": "CP", "D": "D"}
U_INF, Q_INF = 20.0, 240.0
SLICES = {"1L": 4.50, "2L": 7.45, "3L": 10.40}
WALLS_ALL = ["car_body", "car_floor", "car_fw", "car_rw", "wheel_front", "wheel_rear"]


def run_of(v: str) -> str:
    return LABELS.get(v.upper(), v.upper())


def files(run: str):
    cas, dat = CASES / f"halfcar_{run}.cas.h5", CASES / f"halfcar_{run}.dat.h5"
    if not (cas.exists() and dat.exists()):
        raise SystemExit(f"{cas.name} / {dat.name} missing: re-solve with "
                         f".venv/Scripts/python cfd/fluent_halfcar.py solve {run} (about 1 h on 4 cores)")
    return cas, dat


def walls(run: str):
    """Wall zones of this run (A has no wings), from its mesh_info.json."""
    import json
    mi = ROOT / "cfd" / "results" / "runs" / run / "mesh_info.json"
    if mi.exists():
        zones = json.loads(mi.read_text()).get("zones", [])
        w = [z for z in WALLS_ALL if z in zones]
        if w:
            return w
    return WALLS_ALL


def quaternion(eye, centre=(0.0, 0.0, 0.0), up=(0.0, 0.0, 1.0)):
    """CFD-Post camera rotation (world -> view) for a camera at `eye` looking at `centre`."""
    import numpy as np
    b = np.subtract(eye, centre); b = b / np.linalg.norm(b)          # view +Z: toward the viewer
    r = np.cross(up, b); r = r / np.linalg.norm(r)                    # view +X: right
    u = np.cross(b, r)                                                # view +Y: up
    R = np.array([r, u, b])
    w = math.sqrt(max(0.0, 1 + R[0, 0] + R[1, 1] + R[2, 2])) / 2
    x = (R[2, 1] - R[1, 2]) / (4 * w)
    y = (R[0, 2] - R[2, 0]) / (4 * w)
    z = (R[1, 0] - R[0, 1]) / (4 * w)
    return x, y, z, w


def session(run: str, hardcopy: Path | None = None) -> str:
    cas, _ = files(run)
    wl = ", ".join(walls(run))
    q = quaternion((-3.0, 5.5, 3.2), (2.0, 0.0, 0.4))
    s = [f"""COMMAND FILE:
  CFX Post Version = 26.1
END
> load filename={cas.as_posix()}
LIBRARY:
  CEL:
    EXPRESSIONS:
      CpExpr = Pressure / {Q_INF} [Pa]
      deficitExpr = 1 - Velocity u / {U_INF} [m s^-1]
    END
  END
END
USER SCALAR VARIABLE: Cp
  Boundary Values = Conservative
  Calculate Global Range = On
  Expression = CpExpr
  Recipe = Expression
END
USER SCALAR VARIABLE: deficit
  Boundary Values = Conservative
  Calculate Global Range = On
  Expression = deficitExpr
  Recipe = Expression
END
CONTOUR: car Cp
  Colour Map = Default Colour Map
  Colour Variable = Cp
  Contour Range = User Specified
  Location List = {wl}
  Min = -3
  Max = 1
  Number of Contours = 41
  Clip Contour = On
  Draw Contours = Off
  Fringe Fill = On
  Lighting = On
  Visibility = On
END
CONTOUR: symmetry speed
  Colour Map = Default Colour Map
  Colour Variable = Velocity
  Contour Range = User Specified
  Location List = symmetry
  Min = 0 [m s^-1]
  Max = {1.4 * U_INF:g} [m s^-1]
  Number of Contours = 29
  Draw Contours = Off
  Fringe Fill = On
  Lighting = Off
  Visibility = Off
END
"""]
    for n, x in SLICES.items():
        for var, lo, hi, vis, tag in (("deficit", 0, 0.6, "On", "wake"), ("Turbulence Kinetic Energy", "0 [m^2 s^-2]",
                                                                           "8 [m^2 s^-2]", "Off", "wake k")):
            s.append(f"""PLANE: {tag} {n}
  Option = YZ Plane
  X = {x} [m]
  Colour Mode = Variable
  Colour Variable = {var}
  Range = User Specified
  Min = {lo}
  Max = {hi}
  Lighting = Off
  Transparency = 0.15
  Visibility = {vis}
END
""")
    seeds = []
    for i, y in enumerate((0.1, 0.3, 0.5, 0.7)):
        name = f"seed line {i + 1}"
        seeds.append(name)
        s.append(f"""LINE: {name}
  Option = Two Points
  Point 1 = -1.25 [m], {y} [m], 0.05 [m]
  Point 2 = -1.25 [m], {y} [m], 1.45 [m]
  Line Samples = 14
  Visibility = Off
END
""")
    s.append(f"""STREAMLINE: streamlines
  Colour Mode = Variable
  Colour Variable = Velocity
  Range = User Specified
  Min = 0 [m s^-1]
  Max = {1.4 * U_INF:g} [m s^-1]
  Location List = {", ".join(seeds)}
  Variable = Velocity
  Locator Sampling Method = Vertex
  Maximum Number of Items = 100
  Streamline Type = 3D Streamline
  Streamline Direction = Forward
  Streamline Width = 2
  Visibility = On
END
""")
    legends = (("Cp legend", "CONTOUR:car Cp", "Cp = p / 240 Pa on the car", "Left", "Top"),
               ("speed legend", "STREAMLINE:streamlines", "streamline speed", "Left", "Bottom"),
               ("deficit legend", "PLANE:wake 1L", "wake velocity deficit 1 - u/U", "Right", "Center"))
    for name, plot, title, xj, yj in legends:
        s.append(f"""LEGEND: {name}
  Legend Plot = /{plot}
  Legend X Justification = {xj}
  Legend Y Justification = {yj}
  Legend Size = 0.45
  Legend Title Mode = User Specified
  Legend Title = {title}
  Legend Format = %4.2f
  Visibility = On
END
""")
    s.append(">hide /DEFAULT LEGEND:Default Legend View 1, view=/VIEW:View 1" + chr(10))
    shown = (["CONTOUR:car Cp", "STREAMLINE:streamlines"] + [f"PLANE:wake {n}" for n in SLICES]
             + [f"LEGEND:{lg[0]}" for lg in legends])
    s.append("".join(f">show /{o}, view=/VIEW:View 1" + chr(10) for o in shown))
    s.append(f"""VIEW:View 1
  Camera Mode = User Specified
  CAMERA:
    Option = Pivot Point and Quaternion
    Pivot Point = 2.0, 0.0, 0.4
    Scale = 0.45
    Pan = 0, 0
    Rotation Quaternion = {q[0]:.6f}, {q[1]:.6f}, {q[2]:.6f}, {q[3]:.6f}
    Send To Viewer = True
  END
END
""")
    if hardcopy is not None:
        s.append(f"""HARDCOPY:
  Hardcopy Filename = {hardcopy.as_posix()}
  Hardcopy Format = png
  Image Width = 1600
  Image Height = 900
  Use Screen Size = Off
  White Background = On
END
>print
> quit
""")
    return "".join(s)


def open_cfdpost(run: str, test: bool) -> int:
    VIS.mkdir(parents=True, exist_ok=True)
    if test:
        png = VIS / f"explore_{run}_test.png"
        cse = VIS / f"explore_{run}_test.cse"
        cse.write_text(session(run, png))
        print(f"CFD-Post batch: {cse}")
        r = subprocess.run([str(CFDPOST), "-batch", str(cse)], capture_output=True, text=True, timeout=1800)
        print(r.stdout[-4000:], r.stderr[-2000:])
        print("picture:", png, "exists" if png.exists() else "MISSING")
        return 0 if png.exists() else 1
    cse = VIS / f"explore_{run}.cse"
    cse.write_text(session(run))
    print(f"opening CFD-Post with {cse}")
    subprocess.Popen([str(CFDPOST), "-session", str(cse)], cwd=str(VIS))
    return 0


def open_fluent(run: str, test: bool) -> int:
    """Fluent window with case + data read and a few graphics objects defined
    (Results > Graphics in the tree): car Cp, symmetry velocity, pathlines."""
    import ansys.fluent.core as pyfluent
    cas, _ = files(run)
    ui = "no_gui" if test else "gui"
    s = pyfluent.launch_fluent(mode="solver", dimension=3, precision="double", processor_count=4, ui_mode=ui,
                               cleanup_on_exit=test)
    s.settings.file.read_case_data(file_name=str(cas))
    g = s.settings.results.graphics
    wl = walls(run)
    made = []
    try:
        g.contour["car_cp"] = {"field": "pressure-coefficient", "surfaces_list": wl, "filled": True,
                               "range_option": {"option": "auto-range-off",
                                                "auto_range_off": {"minimum": -3.0, "maximum": 1.0}}}
        made.append("contour car_cp")
        g.contour["symmetry_speed"] = {"field": "velocity-magnitude", "surfaces_list": ["symmetry"], "filled": True,
                                       "range_option": {"option": "auto-range-off",
                                                        "auto_range_off": {"minimum": 0.0, "maximum": 1.4 * U_INF}}}
        made.append("contour symmetry_speed")
        rake = s.settings.results.surfaces.rake_surface
        rake["seed_rake"] = {"number_of_points": 40, "p0": [-1.25, 0.3, 0.05], "p1": [-1.25, 0.3, 1.45]}
        g.pathline["pathlines"] = {"field": "velocity-magnitude", "release_from_surfaces": ["seed_rake"]}
        made.append("pathline pathlines")
        if not test:
            g.contour["car_cp"].display()
    except Exception as e:                       # the window still opens with the result read
        print("could not define every graphics object:", type(e).__name__, e)
    print("defined:", ", ".join(made) or "nothing")
    if test:
        s.exit()
    else:
        print("Fluent is open; close it from its own window (File > Exit).")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("variant", help="A, B, C (= run CP), D, or a run name such as E")
    ap.add_argument("--fluent", action="store_true", help="open in Fluent instead of CFD-Post")
    ap.add_argument("--test", action="store_true", help="no window: check that the set-up works")
    a = ap.parse_args(argv)
    run = run_of(a.variant)
    files(run)
    return open_fluent(run, a.test) if a.fluent else open_cfdpost(run, a.test)


if __name__ == "__main__":
    sys.exit(main())
