# tools: SolidWorks build harness

Builds the CAD from the terminal with SolidWorks 2026 open (or closed: it is started and waited for). There is no VBA editor, no module import, no F5 and no message box.

```
python tools/sw_run.py rebuild                 # everything, from empty parts
python tools/sw_run.py <step> [args]           # one step
python tools/sw_run.py status                  # SolidWorks version, open documents
python tools/sw_run.py build                   # only compile
```

Python 3.8+ with the standard library only, plus the .NET SDK (any version under `C:\Program Files\dotnet\sdk`, for its Roslyn compiler). Nothing else is installed.

## Steps

| Step | Does | Report |
|---|---|---|
| `close-all` | closes every open document **without saving** (the files on disk are what counts) | |
| `restart-sw` | closes every document without saving, quits SolidWorks and starts a fresh one (first step of `rebuild`: after several rebuilds in one session OpenDoc6 failed silently) | |
| `new-chassis` | closes `cad/chassis/chassis.SLDPRT`, moves it to `cad/chassis/old/chassis_<time>.SLDPRT`, saves a new empty MMGS part in its place | |
| `ImportFrameNodes` | 114 3D-sketch lines in 7 `FRAME_<group>` sketches from `cad/frame/*.csv` | `cad/chassis/import_frame_nodes_report.txt` |
| `BuildTubes` | 7 groups of structural members, AISI 1020, cut list, checks | `cad/chassis/build_tubes_report.txt` |
| `TrimTubes [--expect-nothing]` | mitre cuts first (tube ends reaching more than 15 mm past their node, `Mitre.cs`), then one coped trim per row of `cad/frame/frame_trims.csv` (174 rows), stub cleanup, mitre check again; with `--expect-nothing` it fails if anything is left to do | `cad/chassis/trim_tubes_report.txt` |
| `CheckChassis` | 114 bodies, one per tube, cut length, mass, all plan rows done, no feature in error, overlap between tubes at a node (warning) | `cad/chassis/check_chassis_report.txt` |
| `new-layout` | same as new-chassis for `cad/layout/master_layout.SLDPRT` | |
| `BuildLayout` | named planes driven by equations, axle axes, `HP_*` hardpoints (right) and `HPL_*` (left, mirrored); saves, closes, reopens and checks again | `cad/layout/build_layout_report.txt` |
| `DrivenTest` | on a copy in `%TEMP%`: wheelbase +50, main_hoop_x +20, rebuild, the planes must follow | `cad/layout/driven_test_report.txt` |
| `new-assembly` | closes and moves the old `cad/formula_single_seater.SLDASM` aside | |
| `BuildAssembly` | STEP bodies to `cad/body/*.SLDPRT` (again if the STEP is newer), layout fixed, parts mated to GROUND/CENTRE/FRONT_AXLE, left wheels, interference (warning), mass | `cad/build_assembly_report.txt` |
| `BuildBodies` | (Python, no SolidWorks) `cad/generate/build_parts.py` then `check_clearances.py`: STEP bodies, clearance rules (frame 10 mm, tyres 25 mm over travel and steer) | `cad/generate/clearance_report.txt` |
| `SuspensionParts` | 24 parts in `cad/suspension/` (FR FL RR RL x lwb uwb upright hub tie push), structural members (links 15.9x0.9, upright and hub 25.4x1.6), named joint points and axes | `cad/suspension/suspension_parts_report.txt` |
| `SuspensionAssembly` | the 24 parts into the assembly: wishbone pivots and tie-rod inner ends on the layout `HP_`/`HPL_` points, ball joints point-to-point, hub on the spindle, pushrod through its inner point, tyre and rim locked to the hub, `Drive_<corner>` distance mate = wheel-centre height | `cad/suspension/suspension_assembly_report.txt` |
| `SuspensionCheck` | -30..+30 mm in 5 mm steps by the Drive mates: camber, toe, half-track, pushrod travel, roll centre, roll camber, compared with `suspension_geometry.m`; outer joints against the rim barrel; interference at droop, static, bump | `cad/suspension/suspension_report.txt` |
| `SuspensionMotion` | Motion study "Bump sweep": one oscillating linear motor per upright, located at the wheel-centre point P_WC (the A_SPIN axis is the fallback), Drive mates suppressed in the study. Animation study first, then Basic Motion and Motion Analysis if motors are refused. Motors are refused in an assembly that has had a motion study deleted, so a fresh `rebuild` is needed. If no motor takes, the step WARNs and deletes the undriven study. The full kinematic sweep is SuspensionCheck's | `cad/suspension/suspension_motion_report.txt` |
| `ChassisStatics` | Simulation add-in, beam studies "Torsion" (free-free, balanced couples), "Braking", "Cornering" on the chassis (loads from `sim/stress/load_cases.csv` through the six-link upright statics), meshed and run; solver files in `sim/stress/results/`. On 2026 SP2.1 Student the forces cannot be put on beam joints through the API, so the solver reports no load: WARN with the reasons in the report. `ChassisStatics probe` lists which entities AddForce2/AddRestraint take | `sim/stress/chassis_statics_report.txt` |
| `FrameSolid [size_mm] [--fuse] [--combine] [--check-only]` | Torsion of the frame as **solids**, to cross-check `matlab/stress/frame_fe.m`. Copies `chassis.SLDPRT` to `cad/chassis/chassis_solid.SLDPRT` (the chassis is not touched). Static study with a solid mesh, AISI 4130, free-free with inertia relief. Loads: the couples at the 16 wishbone pickup nodes, each force on the tube edge nearest its node. Twist is taken from the mesh nodes around the pickups and compared with frame_fe's same case. It also checks tube connectivity and whether each joint moves as one. **On 2026 SP2.1 Student it meshes (1.46 M nodes) and solves in about a minute, but the stiffness is NOT VALID.** The coped tube ends touch their neighbours only along lines, so bonded contact leaves some tubes unjoined; Combine and Boolean union fail for the same reason. Not in the rebuild | `sim/stress/frame_solid_report.txt` |
| `SaveStandardViews <file>` | six PNGs in car axes (Z up, nose to the left): iso, front, side, top, rear, bottom | `media/views/<doc>_views_report.txt` |

`rebuild` runs them in that order and stops at the first step that does not pass. TrimTubes runs twice, and the second run must change nothing. Exit codes: 0 pass (warnings allowed), 1 a check failed, 2 stopped or error, 3 needs a person. Every run gets one line in `cad/harness_runs.log`.

Diagnostics (read-only or on copies): `tree`, `tubeends`, `trimdefs`, `findfeat`, `trimexperiment`, `eqexperiment`, `probeviews`, `nearpoint x y z [r]` (bodies reaching a point), `overruns [n]` (how far each tube body reaches past its nodes). Tools: `mitre [tube node]` (the mitre pass alone), `makeprofile <od> <wall>` (a round-tube weldment profile from 25.4x1.6).

## Dialogs and people

`sw_run.py` watches SolidWorks' dialog windows while a step runs and logs their text (progress boxes such as "Calculating interferences" are normal). If a dialog stays open for 90 s (a licence prompt, sign-in or crash report), or a step gets no answer for 30 min, the step is killed. It is reported as NEEDS A PERSON with the dialog text, and `rebuild` stops there. Files are only ever saved by the step that owns them. Old files are moved to `old/`, never deleted.

## Why C# and not Python or the VBA macros

- **VBA** cannot be run without the editor or a `.swp` binary, and `RunMacro2` needs the `.swp` that a person built by importing modules. Its errors arrive as message boxes.
- **Python (pywin32)** works for simple calls, but SolidWorks' late-bound dispatch makes argument-less methods look like properties. `makepy` fails on the type library, and `CastTo` breaks typed calls. The trims need arrays of typed objects (`Body2[]`, `StructuralMemberGroup[]`), and those cannot be passed reliably that way.
- **C#** against the installed interop DLLs gives the same typed API the VBA uses: out and ref parameters, real exceptions, and typed arrays. An `object[]` handed to `StructuralMemberGroup.Segments` is silently dropped (it reads back null), while `SketchSegment[]` works; the harness passes typed arrays everywhere. It is compiled from the plain `.cs` text with the compiler the .NET SDK already has, so nothing is installed.

## Lessons the port turned up (kept in the code comments too)

- `InsertWeldmentTrimFeature2` can return a feature that is in error and cuts nothing. That happens when one tube in the row is already shaped against the boundary by its structural member. Such a feature is invisible to `FirstFeature`/`GetNextFeature` but found by `FeatureByName` and `GetFeatures(false)`. TrimTubes deletes it, retries tube by tube, records rows that need no trim, and cuts the rest in a second trim.
- `Body2` handles go stale after any delete or rebuild. Bodies are re-matched by centroid before reuse.
- `EquationMgr.Add3` refused every form tried; `Add2(-1, expr, true)` works. SolidWorks silently drops an equation line longer than about 500 characters, so the CG lines in `params/car_params.txt` are split into partial sums.
- COM True can come back as `1`; never test `Not result`.
