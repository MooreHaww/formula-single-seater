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
| `close-all` | closes every open document **without saving** (the files on disk are what counts); `rebuild` runs it after every SolidWorks step | |
| `restart-sw` | closes every document without saving, quits SolidWorks and starts a fresh one (first step of `rebuild` and again before the layout, suspension, simulation and view groups: after several rebuilds in one session OpenDoc6 failed silently, and one long session ran out of GDI objects) | |
| `new-chassis` | closes `cad/chassis/chassis.SLDPRT`, moves it to `cad/chassis/old/chassis_<time>.SLDPRT`, saves a new empty MMGS part in its place | |
| `ImportFrameNodes` | 114 3D-sketch lines in 7 `FRAME_<group>` sketches from `cad/frame/*.csv` | `cad/chassis/import_frame_nodes_report.txt` |
| `BuildTubes` | structural members, AISI 1020, cut list, checks. Hoop and hoop_brace are one feature each (one group per segment); the other five groups are one feature per tube, so every tube runs node to node and TrimTubes shapes every joint. In one feature, SolidWorks cuts the groups against each other: that left 4 ends floating 9–11 mm short and took 4–9 % out of run-through tubes | `cad/chassis/build_tubes_report.txt` |
| `TrimTubes [--expect-nothing]` | mitre cuts first (tube ends reaching more than 15 mm past their node, `Mitre.cs`), then one coped trim per row of `cad/frame/frame_trims.csv` (196 rows), stub cleanup, mitre check again, then step 2d: any trimmed end more than 0.05 mm from its boundary gets an end-miter `Close_<tube>_<node>`, kept only if the gap closes (none needed since BuildTubes builds the tubes full length); with `--expect-nothing` it fails if anything is left to do | `cad/chassis/trim_tubes_report.txt` |
| `CheckChassis` | 124 bodies, one per tube, cut length, mass, the budget's frame line (weldment mass within 6 % of `m_frame`, centre of mass within 10 mm of `x_frame` / `z_frame`), all plan rows done, no feature in error, overlap between tubes at a node (warning), every trimmed end touching one of its boundary tubes (`ClosestDistance` at most 0.05 mm), steel left per tube (info) | `cad/chassis/check_chassis_report.txt`, `cad/chassis/chassis_tube_mass.csv` (volume and centroid per tube) |
| `new-layout` | same as new-chassis for `cad/layout/master_layout.SLDPRT` | |
| `BuildLayout` | named planes driven by equations, axle axes, `HP_*` hardpoints (right) and `HPL_*` (left, mirrored); saves, closes, reopens and checks again | `cad/layout/build_layout_report.txt` |
| `DrivenTest` | on a copy in `%TEMP%`: wheelbase +50, main_hoop_x +20, rebuild, the planes must follow | `cad/layout/driven_test_report.txt` |
| `new-assembly` | closes and moves the old `cad/formula_single_seater.SLDASM` aside | |
| `BuildAssembly` | STEP bodies to `cad/body/*.SLDPRT` (again if the STEP is newer), layout fixed, parts mated to GROUND/CENTRE/FRONT_AXLE, left wheels, interference (warning), mass. The four wing supports (`fw_support_R/L`, `rw_support_R/L`) get the equivalent density of their CFRP-skin and foam-core sandwich from `cad/generate/supports_mass.csv` as their document density, checked against that CSV's mass Since 2026-11-28 (second session) also the 28 packaging envelopes `env_*`: density = budget mass / volume from `cad/generate/envelopes_mass.csv`, checked the same way; part windows are closed once added (left open, all of them, SolidWorks crashed twice with RPC failed in AddAt; closed, it passed). | `cad/build_assembly_report.txt` |
| `BuildBodies` | (Python, no SolidWorks) `cad/generate/build_parts.py` then `check_clearances.py`: STEP bodies, clearance rules (frame 10 mm, tyres 25 mm over travel and steer). Since 2026-11-28 also the wing supports: rear F and front J in the CFD's section, position and chord (`cfd_variants.rws_section`), the rear pair standing on `RT2_cross`, the front pair between the main element and the nose; they must touch their wing, nose and mount tube without overlapping. Their masses go to `cad/generate/supports_mass.csv` Since 2026-11-28 (second session) also the packaging envelopes (`cad/generate/envelopes.py`: driver, seat, steering, rockers, dampers, brakes, motor and drive, batteries, electronics; space reservations with budget masses), their packaging findings (`cad/generate/packaging_report.txt`, not rule failures) and `cad_cg.py` (CG from the CAD geometry against the budget, `cad_cg_report.txt`). | `cad/generate/clearance_report.txt` |
| `SuspensionParts` | 24 parts in `cad/suspension/` (FR FL RR RL x lwb uwb upright hub tie push), structural members (links 15.9x0.9, upright and hub 25.4x1.6), named joint points and axes | `cad/suspension/suspension_parts_report.txt` |
| `SuspensionAssembly` | the 24 parts into the assembly: wishbone pivots and tie-rod inner ends on the layout `HP_`/`HPL_` points, ball joints point-to-point, hub on the spindle, pushrod through its inner point, tyre and rim locked to the hub, `Drive_<corner>` distance mate = wheel-centre height | `cad/suspension/suspension_assembly_report.txt` |
| `SuspensionCheck` | -30..+30 mm in 5 mm steps by the Drive mates: camber, toe, half-track, pushrod travel, roll centre, roll camber, compared with `suspension_geometry.m`; outer joints against the rim barrel; interference at droop, static, bump | `cad/suspension/suspension_report.txt` |
| `SuspensionMotion` | Motion study "Bump sweep": one oscillating linear motor per upright, located at the wheel-centre point P_WC (the A_SPIN axis is the fallback), Drive mates suppressed in the study. Animation study first, then Basic Motion and Motion Analysis if motors are refused. Motors are refused in an assembly that has had a motion study deleted, so a fresh `rebuild` is needed. If no motor takes, the step WARNs and deletes the undriven study. The full kinematic sweep is SuspensionCheck's | `cad/suspension/suspension_motion_report.txt` |
| `ChassisStatics` | Simulation add-in, beam studies "Torsion" (free-free, balanced couples), "Braking", "Cornering" on the chassis (loads from `sim/stress/load_cases.csv` through the six-link upright statics), meshed and run; solver files in `sim/stress/results/`. On 2026 SP2.1 Student the forces cannot be put on beam joints through the API, so the solver reports no load: WARN with the reasons in the report. `ChassisStatics probe` lists which entities AddForce2/AddRestraint take | `sim/stress/chassis_statics_report.txt` |
| `FrameSolid [size_mm] [--fuse] [--combine] [--check-only]` | Torsion of the frame as **solids**, to cross-check `matlab/stress/frame_fe.m`. Copies `chassis.SLDPRT` to `cad/chassis/chassis_solid.SLDPRT` (the chassis is not touched). Static study with a solid mesh, AISI 4130, free-free with inertia relief. Loads: the couples at the 16 wishbone pickup nodes, each force on the tube edge nearest its node. Twist is taken from the mesh nodes around the pickups and compared with frame_fe's same case. It also checks tube connectivity and whether each joint moves as one. **On 2026 SP2.1 Student it meshes (1.46 M nodes) and solves in about a minute, but the stiffness is NOT VALID.** The coped tube ends touch their neighbours only along lines, so bonded contact leaves some tubes unjoined; Combine and Boolean union fail for the same reason. Superseded by `FrameAnalysis`; kept as the record of why the weldment cannot be used. Not in the rebuild | `sim/stress/frame_solid_report.txt` |
| `FrameAnalysis [size_mm ...] [--overlap 1.0] [--build-only] [--results]` | The valid solid cross-check of `frame_fe.m` (replaces FrameSolid's result). Builds `cad/analysis/frame_analysis.SLDPRT` from the frame CSVs, not from the weldment, which is never opened. Each tube is a hollow cylinder; at a node where `frame_trims.csv` trims it, it is coped against its boundary tubes 1 mm into their wall, otherwise it runs OD/2 past the node. All 124 are fused into one body (about 15 s), and a 40 mm cube is imprinted around each loaded node to give load faces. Two static studies, free-free with inertia relief, AISI 4130: "Torsion nodes" (frame_fe's node couples) and "Torsion links" (the 24 link forces of frame_fe's headline case at the real pickup points). Loads come from `sim/stress/frame_torsion_loads.csv`, written by frame_fe, as remote loads with distributed coupling on the cube faces. Twist is taken as in frame_fe, from the faces at the 16 wishbone nodes. One mesh and solve per size. `--results` re-reads the saved studies without solving. Not in the rebuild (about 2.5 min per solve at 5 mm) | `sim/stress/frame_analysis_report.txt` |
| `SaveStandardViews <file> [--show p1,p2 --name label]` | six PNGs in car axes (Z up, nose to the left): iso, front, side, top, rear, bottom. `--show`: only the assembly components whose names start with the prefixes are visible for the pictures (shown again after, not saved); `--name`: label for the file names. Sketches and points are hidden for the pictures (View > Hide All Types, restored after) unless `--keep-sketches` is given, as for the master layout. The rebuild uses it for the suspension views (`--show FL_,FR_,RL_,RR_,chassis --name suspension`) | `media/views/<doc or label>_views_report.txt` |

`rebuild` runs them in that order and stops at the first step that does not pass. TrimTubes runs twice, and the second run must change nothing. Exit codes: 0 pass (warnings allowed), 1 a check failed, 2 stopped or error, 3 needs a person. Every run gets one line in `cad/harness_runs.log`.

Diagnostics (read-only or on copies): `tree`, `tubeends`, `trimdefs`, `findfeat`, `trimexperiment`, `eqexperiment`, `probeviews`, `nearpoint x y z [r]` (bodies reaching a point), `overruns [n]` (how far each tube body reaches past its nodes). Tools: `mitre [tube node]` (the mitre pass alone), `makeprofile <od> <wall>` (a round-tube weldment profile from 25.4x1.6).

## Dialogs and people

`sw_run.py` watches SolidWorks' dialog windows while a step runs and logs their text (progress boxes such as "Calculating interferences" are normal). If a dialog stays open for 90 s (a licence prompt, sign-in or crash report), or a step gets no answer for 30 min, the step is killed. It is reported as NEEDS A PERSON with the dialog text, and `rebuild` stops there. Files are only ever saved by the step that owns them. Old files are moved to `old/`, never deleted.

### SolidWorks' low-GDI warning

Windows allows each process 10,000 GDI objects by default. One SolidWorks session that ran the whole rebuild reached 9,678 (2026-11-18). SolidWorks then asked "SOLIDWORKS is running critically low on GDI objects … Do you want to continue?", first during the assembly views and then during the suspension views.

**What the harness does:**
- **Answers the warning.** The watcher checks every 0.5 s. When the warning appears, it answers **No** at once, because Yes risks a crash in the middle of a save. It logs the dialog with SolidWorks' GDI count at that moment.
- **Stops the step.** The step gets 20 s to end by itself, then it is ended. It is reported as `STOPPED: SolidWorks low on GDI objects (answered No)`, exit 4, with the message in the console and in `cad/harness_runs.log`.
- **Retries once.** `rebuild` restarts SolidWorks and runs the same step a second time. Every step opens its files from disk, so the retry starts from what the earlier steps saved.

**How it keeps GDI use down:**
- **Restarts SolidWorks between the long groups:** chassis, then layout/bodies/assembly, then suspension, then simulation, then views.
- **Closes documents after every step.** `close-all` runs after every SolidWorks step and closes every document without saving. Every step saves its own file, so nothing is lost, and only one step's windows are open at a time.
- **Logs the GDI count.** After every step, the run log line ends with `[SolidWorks pid …: GDI n (peak n) of 10000, USER n, n MB]`, so the trend is visible.

## Why C# and not Python or the VBA macros

- **VBA** cannot be run without the editor or a `.swp` binary, and `RunMacro2` needs the `.swp` that a person built by importing modules. Its errors arrive as message boxes.
- **Python (pywin32)** works for simple calls, but SolidWorks' late-bound dispatch makes argument-less methods look like properties. `makepy` fails on the type library, and `CastTo` breaks typed calls. The trims need arrays of typed objects (`Body2[]`, `StructuralMemberGroup[]`), and those cannot be passed reliably that way.
- **C#** against the installed interop DLLs gives the same typed API the VBA uses: out and ref parameters, real exceptions, and typed arrays. An `object[]` handed to `StructuralMemberGroup.Segments` is silently dropped (it reads back null), while `SketchSegment[]` works; the harness passes typed arrays everywhere. It is compiled from the plain `.cs` text with the compiler the .NET SDK already has, so nothing is installed.

## Lessons the port turned up (kept in the code comments too)

- `InsertWeldmentTrimFeature2` can return a feature that is in error and cuts nothing. That happens when one tube in the row is already shaped against the boundary by its structural member. Such a feature is invisible to `FirstFeature`/`GetNextFeature` but found by `FeatureByName` and `GetFeatures(false)`. TrimTubes deletes it, retries tube by tube, records rows that need no trim, and cuts the rest in a second trim.
- `Body2` handles go stale after any delete or rebuild. Bodies are re-matched by centroid before reuse.
- `EquationMgr.Add3` refused every form tried; `Add2(-1, expr, true)` works. SolidWorks silently drops an equation line longer than about 500 characters, so the CG lines in `params/car_params.txt` are split into partial sums.
- COM True can come back as `1`; never test `Not result`.
- Simulation results (2026-11-18):
  - `CWResults.GetTranslationalDisplacement`'s second argument is a reference plane, not a list of entities. It always returns every node.
  - At 1.9 M nodes, reading every node (that call, `CWMesh.GetNodes`, `GetMinMaxStress` over all) kept SolidWorks busy for over 20 minutes after a 2-minute solve.
  - `GetDisplacementForEntities(component, step, null, faces, units)` returns (node, value) pairs for the faces' nodes in seconds. The peak stress is read from the solver's `.OUT` file.
- Temporary bodies: `Modeler.CreateBodyFromCyl` takes (base centre, axis, radius, length) and `CreateBodyFromBox3` takes (base centre, height axis, width, length, height), both in metres.
- `Modeler.ImprintingFaces` needs typed `Face2[]` arrays; `object[]` crashes SolidWorks' COM server. `SplitFaceOnParam` reports success on a temporary body but splits nothing.
- Run `Body2.Operations2` on a copy: a refused operation can leave its input body unusable.
