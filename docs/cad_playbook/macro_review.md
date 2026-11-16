# Macro review

The section below records the first real test. The older read-through tables after it are kept for history; where the test contradicted them, the row says so.

## Tested in SolidWorks 2026 (2026-11-16)

**Set-up:** SOLIDWORKS Design Premium for Students 2026 SP2.1. The Student edition runs VBA macros. Side check: the STEP import of `cad/step/tyre_front` works (one solid, Import Diagnostics shows no faulty faces).

**How to run a macro (what worked):**

1. Make the macro project once: Tools > Macro > New, save as `cad/macros/<Name>.swp`. The VBA editor opens.
2. In the VBA editor: File > Import File... and pick `cad/macros/<Name>.bas`. Remove the empty default module (right-click > Remove, do not export). Ctrl+S, close the editor.
3. Run with Tools > Macro > Run and pick the **`.swp`**. Picking the `.bas` in that dialog does not run it; the `.bas` is only the text source for git.
4. After changing a `.bas`: open the `.swp` with Tools > Macro > Edit, remove the old module, import the `.bas` again, save.

The macros find the repo root by walking up from the `.swp`'s folder until they find `params\car_params.txt`, so the `.swp` must be saved somewhere inside the repo; `cad/macros/` is the convention. (Before this fix they went exactly three folders up, which only worked from `cad/macros/`.)

| Macro | What ran | What failed | Fixed in the `.bas` |
|---|---|---|---|
| `SaveStandardViews` | Ran once two lines were commented out. | (a) `swColorsBackgroundAppearance_e.swColorsBackgroundAppearance_PlainWhite` is not in the 2026 type library: compile error (a missing enum name stops the whole module, `On Error Resume Next` cannot catch it). (b) `swModel.ViewDisplayShadedWithEdges`: runtime error 438, the method does not exist on `ModelDoc2`. | (a) `swColorsBackgroundAppearance_Plain` (= 0) plus `swSystemColorsViewportBackground` (= 99) set to white, gradient toggle off; the three settings are saved first and restored at the end. (b) `swModel.ActiveView.DisplayMode = swViewDisplayMode_ShadedWithEdges` (= 5). |
| `ImportFrameNodes` | Drew 116 lines with shared end points once the two CSVs were converted to CRLF by hand. | (a) `FeatureManager.FeatureByPositionReverse(0)`: error 438 (the method is on `ModelDoc2`, not `FeatureManager`); the workaround rename then hit the Origin feature, not the sketch. (b) `Line Input` read the LF-only CSVs as one line. (c) One sketch for all 116 lines meant no box select per group. | (a) The sketch is named through `SketchManager.ActiveSketch` cast to `Feature` before the sketch is closed, with `Extension.GetLastFeatureAdded` as a fallback; the message says if a rename failed. (b) File read whole, split on `vbLf`, `vbCr` removed: LF and CRLF both work. (c) One 3D sketch per group (`FRAME_hoop` ... `FRAME_rear`), line count per sketch in the final message. Node sharing within a sketch unchanged. |
| `ImportAirfoil` | Second test: **failed to compile**, "Expected Function or variable" on `ok = swModel.InsertCurveFileBegin()`. | Earlier audit: `FeatureManager.FeatureByPositionReverse` and `Line Input` on the `.dat`. Compile error: see "Second test" below. | `Extension.GetLastFeatureAdded` for the curve; whole-file read; `swModel.InsertCurveFileBegin` called as a statement. |
| `ExportConfigsSTEP` | Not run yet. | Audit found `swUserPreferenceIntegerValue_e.swStepExportGeometry`, which is not in the 2026 library: it would have been a compile error like (a) above. | Line removed; set Tools > Options > Export > STEP output once by hand. `swStepAP` (= 75) exists and stays. |
| `BuildAssembly` | Does not exist in the repo. | | |

**How the 2026 names were checked:** the online API Help pages render by script and could not be read, so every enum name and member the four macros use was checked by reflection against `C:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\SolidWorks.Interop.swconst.dll` and `SolidWorks.Interop.sldworks.dll` of the installed 2026 SP2.1. All 17 enum names now resolve, and every `ModelDoc2`, `ModelView`, `SketchManager`, `ModelDocExtension`, `Feature` and `SldWorks` member called exists. That proved the names exist, but not that each call compiles; the second test below showed the gap.

### Second test (2026-11-16): ImportAirfoil compile error

**Found:** `ImportAirfoil` did not compile: "Expected Function or variable" on `ok = swModel.InsertCurveFileBegin()`. A compile error in any module stops the whole macro project.

**Cause (from the installed `SolidWorks.Interop.sldworks.dll`):** `InsertCurveFileBegin`, `InsertCurveFilePoint` and `InsertCurveFileEnd` are members of `IModelDoc2` (and the old `IModelDoc`), not of `IPartDoc`; `IPartDoc` has no `InsertCurveFile*` member at all. `InsertCurveFileBegin` returns **Void** (a Sub), while `InsertCurveFilePoint` and `InsertCurveFileEnd` return Boolean. Assigning a Sub's result is exactly what VBA reports as "Expected Function or variable". Moving the calls onto a `SldWorks.PartDoc` variable would have turned it into "Method or data member not found", so that route was not taken.

**Fix:** `swModel.InsertCurveFileBegin` is called as a statement on the `ModelDoc2` variable; `InsertCurveFilePoint` is checked per point (refused points counted in the Immediate window); `InsertCurveFileEnd` keeps its Boolean check.

**Per-interface check of all four macros:** a script dumped every interface's members from the 2026 interop DLL (kind, return type, required and optional argument counts, read/write for properties). It then resolved each call in the `.bas` files to the declared type of its variable (`ModelDoc2`, `SldWorks`, `SketchManager`, `ModelView`, `ModelDocExtension`, `Feature`, `Sketch`, `MassProperty`, `Configuration`/`ConfigurationManager`), following chains such as `swModel.Extension.SaveAs3` and `swModel.ConfigurationManager.ActiveConfiguration.Name`. For each call it checks:

- the member exists on that interface;
- a Void member is not used as a value;
- an assignment targets a writable property;
- the number of arguments is within the required..total range.

Result: 76 member uses checked, the `InsertCurveFileBegin` line was the only problem, and none remain after the fix. The checker was itself tested on a module with planted errors: it caught `PartDoc.InsertCurveFileBegin` (no such member), an assignment to the read-only `GetPathName`, three arguments to `ShowNamedView2` (takes two) and `ViewDisplayShadedWithEdges` (no such member), and passed the correct lines. A separate scan found no variable declared twice in one procedure and none used without a `Dim` (`Option Explicit`).

**Still not covered by any of this:** runtime behaviour, VBA-only objects (`Application`, `Scripting.Dictionary`, file I/O), and the `Sketch` to `Feature` cast in `ImportFrameNodes`, which happens at run time. All four macros as they stand are **untested, need the app**; the next run should start with `ImportAirfoil` (Debug > Compile VBAProject in the VBA editor first, which reports compile errors without running anything).

**Line endings:** `matlab/cad/frame_layout.m` writes the CSVs with explicit `\r\n` now (its self-test checks the bytes), `.gitattributes` pins `*.csv` and `*.bas` to CRLF, and the four `.bas` files are saved with CRLF (the VBA editor's File > Import expects it).

**Next test, in order:** `SaveStandardViews` (white background, shaded with edges, your own background back afterwards); `ImportFrameNodes` in an empty part (seven sketches, counts 12 / 10 / 7 / 4 / 18 / 32 / 33); `ImportAirfoil` with `symmetric.dat`, chord 300; `ExportConfigsSTEP` on a part with two configurations.

### BuildTubes.bas (new, 2026-11-16)

**Why:** in the 2026 test, the Structural Member command showed every sketch during selection, so a box select caught lines from other `FRAME_*` sketches even when they were hidden. The macro builds each member from one sketch's segments without any selection.

**API route, confirmed in the installed 2026 interop DLLs:**

| Step | Call (variable type) | Signature in 2026 |
|---|---|---|
| sketch of a group | `Feature.GetSpecificFeature2` (Feature) then `Sketch.GetSketchSegments` (Sketch) | both return Object (late-bound) |
| group | `FeatureManager.CreateStructuralMemberGroup` (FeatureManager) | returns `StructuralMemberGroup` |
| group settings | `StructuralMemberGroup.Segments`, `.ApplyCornerTreatment`, `.CornerTreatmentType` | writable properties; miter = `swSolidworksWeldmentEndCondOptions_e.swEndConditionMiter` (1) |
| member | `FeatureManager.InsertStructuralWeldment5(Path, ConnectedSegmentsOption, AllowProtrusion, Groups, ConfigurationName)` | 5 args, returns Feature; `swConnectedSegments_SimpleCut` (1). Fallback `InsertStructuralWeldment4` (4 args) |
| weldment feature | `PartDoc.IsWeldment`, `FeatureManager.InsertWeldmentFeature` | Boolean property; returns Feature |
| failure reason | `FeatureManager.GetCreateFeatureErrors(ByRef Msgs, ByRef FeatureTypeName)` | returns Int32 |
| material | `PartDoc.SetMaterialPropertyName2(Config, Database, Name)` (Sub), `PartDoc.GetMaterialPropertyName2(Config, ByRef Database)` | `AISI 1020` and `Plain Carbon Steel` both exist in the installed `solidworks materials.sldmat` (7900 and 7800 kg/m³); the macro uses AISI 1020 |
| cut list | `BodyFolder.SetAutomaticUpdate`, `.UpdateCutList`, `.GetBodyCount`; `Feature.GetFirstSubFeature` / `GetNextSubFeature`; `Feature.CustomPropertyManager`, `CustomPropertyManager.Get6` (6 args) | all present |
| mass | `ModelDocExtension.CreateMassProperty`, `MassProperty.Mass` | kg with system units |
| save | `ModelDoc2.Save3(Options, ByRef Errors, ByRef Warnings)`, or `ModelDocExtension.SaveAs3` (7 args) for an unsaved part | |

The per-interface checker now covers five modules and 136 member uses, with no problems. All enum names used in `BuildTubes` exist in 2026.

**What depends on run-time behaviour** (cannot be settled from the type library; the macro reports each one):
- **A branched network in one group** (more than two segments at a node). If SolidWorks refuses the all-segments group, the macro retries with one group per segment in the same feature. That is always valid, but nothing within the group is mitered, so the trim does the joints. The message says which mode each group got.
- **The empty profile configuration name `""`** in `InsertStructuralWeldment5`. If it is refused, the macro falls back to `InsertStructuralWeldment4`.
- **Whether the Weldment feature has to be inserted first.** The macro inserts it only when `IsWeldment` is False.
- **The database name `SOLIDWORKS Materials`.** The macro reads the material back to check; a failure is reported, not fatal.
- **The feature type names `SolidBodyFolder` / `CutListFolder` and the cut-list property `LENGTH`** (resolved in mm). If `LENGTH` is missing, the length line FAILs and says so.
- **Late-bound casts:** the Object/Variant returns (`GetSpecificFeature2`, `GetSketchSegments`, the sub-feature walk) are only type-checked when the macro runs.
- **Mass and cut length are measured before the trim.** The tubes overlap at the joints, so both read slightly high; the limits (38 to 46 kg, ±5 %) allow for it.

**First run (2026-11-16): a bug, fixed.**
- **What happened:** on a part without `FRAME_*` sketches, the macro inserted a Weldment feature and then stopped with "no sketch named FRAME_hoop". A second run inserted another one (`Weldment`, `Weldment1`). `PartDoc.IsWeldment` had stayed False with a Weldment feature present but no members, so it cannot tell whether the feature exists.
- **Fix, part 1: check first.** All checks now run for all seven groups before anything is changed: sketch exists, has segments, group in the CSV, profile file exists, plus the CSV and save-path checks before them. Any failure there stops with "Nothing was changed".
- **Fix, part 2: no second Weldment.** The Weldment feature is inserted only after those checks, and only if the part has none. A part counts as having one if any of these holds:
  - `IsWeldment` is True;
  - a feature has the type name `WeldmentFeature`. That name appears in the installed weldment DLLs but could not be confirmed from the type library;
  - a feature is named `Weldment` or `Weldment<n>`, the default names.
- **Stop messages:** a stop during the build says that the members made so far are kept and the part is not saved.
- **Still untested in the app:** the full build path (members, material, cut list, save).

## Read-through before the test (history)

The four `.bas` modules in `cad/macros/` were re-read for API mistakes against what I knew of the SolidWorks API up to 2025 and for Student-edition limits, before anything was executed. Items marked **fixed** were changed in the files; items marked **verify** were to be checked on first run.

## Cross-cutting

| Topic | Finding | Status |
|---|---|---|
| Type library references | A new macro created with Tools > Macro > New references "SldWorks 2026 Type Library" and "SOLIDWORKS 2026 Constant type library" automatically, so bare enum names like `swDocPART`, `swStandardViews_e.swIsometricView` resolve. If you import the `.bas` into a macro created another way, add them under Tools > References in the VBA editor. | verify once |
| `GetCurrentMacroPathName` | Exists on `ISldWorks` and returns the running `.swp` path; the repo root was derived from it (three levels up). **Changed after the 2026 test:** the macros now walk up until they find `params\car_params.txt`. | fixed |
| Student edition | Student Design Premium (university licence) has the same API as the commercial product; the older "Student Design Kit" blocked some file exports. STEP and PNG export should work; if `SaveAs3` returns errors `0x…` with no file, check Tools > Options > Export is reachable at all (the Student Edition watermark is added to drawings only). | verify on first run of ExportConfigsSTEP |
| Units | All API positions are metres; the macros convert from mm or x/c. | ok |
| Dim inside loops | VBA hoists `Dim` to procedure scope; harmless. | ok |

## ImportAirfoil.bas

| Finding | Status |
|---|---|
| `InsertCurveFileBegin` / `InsertCurveFilePoint` / `InsertCurveFileEnd` are the documented way to script "Curve Through XYZ Points"; the curve lands in the model's XY plane (z = 0), which is the default Front plane. In the project template the Front plane is renamed FRONT_AXLE (normal to X), so a wing section imported this way is in the wrong plane for an extrude along Y. The message box now says so; `10_front_wing.md` gives the workaround (import the `.sldcrv` manually or move the body). | fixed (message), workflow documented |
| `GetOpenFileName(title, initialName, filter, options, configName, displayName)` returns the selected path as a String; the last two arguments are ByRef outputs and must be variables, which they are. | ok |
| Title-line detection assumed the first character is non-numeric; a title starting with a digit would have been skipped as data. Now the first line is skipped unless it already parses as two numbers. | fixed |
| `ReDim Preserve xs(0 To count - 1)` with `count = 0` would raise an error; guarded. | fixed |
| `feat.Name` was used in the message even when `feat` is Nothing. | fixed |
| `InsertCurveFileEnd` fails if two consecutive points coincide; the reader drops exact duplicates and opens the trailing edge by 0.0005 (x/c), so a closed Selig file still imports. | ok |

## ExportConfigsSTEP.bas

| Finding | Status |
|---|---|
| `swUserPreferenceIntegerValue_e.swStepAP` with value 214 is documented. `swStepExportGeometry` is **not certain** to exist under that name (the option "Solid/Surface geometry" may be `swStepExportGeometryRule` or only reachable through Tools > Options). Wrapped in `On Error Resume Next`; set the option once in Tools > Options > Export > STEP as a fallback. **Wrong:** a missing enum name is a compile error, not a runtime error; the name is not in 2026 and the line is removed. | fixed after the 2026 audit |
| `IModelDocExtension.SaveAs3(name, version, options, exportData, advancedSaveAsOptions, errors, warnings)` is the 2019+ signature with 7 arguments; passing `Nothing` for both object arguments is allowed for STEP. If 2026 reports "wrong number of arguments", use `SaveAs2` (6 arguments, no advanced options). | verify |
| `ShowConfiguration2` returns Boolean and activates by name; configuration names with spaces are fine, but the file name is sanitised (`SafeName`). | ok |
| `CreateMassProperty` on an assembly with lightweight components returns zeros; set the assembly to resolved (right-click top > Set Lightweight to Resolved) before running. | verify |
| The log is appended, never overwritten, so repeated runs accumulate; that is intended (dated). | ok |
| On a part with many configurations each `ForceRebuild3` is a full rebuild; the CFD body has 4, fine. | ok |

## SaveStandardViews.bas

| Finding | Status |
|---|---|
| Plain background: the toggle `swColorsGradientPartBackground` may not exist by that name; the integer preference `swColorsBackgroundAppearance` with `swColorsBackgroundAppearance_PlainWhite` is the documented one in recent releases. Both are now attempted under `On Error Resume Next`. If neither works, set Tools > Options > System Options > Colors > Background appearance to "Plain (Viewport Background)" by hand once. **Wrong:** `_PlainWhite` does not exist in 2026 and caused a compile error; replaced by `_Plain`. | fixed after the 2026 test |
| `ShowNamedView2("", viewId)` with `swStandardViews_e` values is documented; the iso/front/right/top/back/bottom ids are 7/1/4/5/2/6 **verify** the constants resolve from the type library. | verify |
| `SaveAs3` to a `.png` path performs an image export of the current view at the graphics-area size; it is documented behaviour for `SaveAs`. If the file comes out tiny, maximise the SolidWorks window first. Image export options (Tools > Options > Export > PNG) apply. | verify |
| The `.png` SaveAs changes nothing in the document and does not alter `GetPathName`, so the document name is read before the loop. | ok |
| `media/views/` is ignored by `.gitignore`; copy the one picture you want into `docs/` or `media/`. | ok |

## ImportFrameNodes.bas (new)

| Finding | Status |
|---|---|
| `SketchManager.Insert3DSketch True` opens a 3D sketch; a second call closes it. `CreateLine(x1, y1, z1, x2, y2, z2)` in metres works inside a 3D sketch. | ok |
| `AddToDB = False` keeps inference on so that lines ending at the same coordinates share a sketch point (needed for the weldment corner treatment and for the beam mesh). If the sketch still shows separate coincident points, Tools > Sketch Tools > Repair Sketch merges them. With 98 lines and inference on, expect 10 to 30 s. **2026 test:** 116 lines drawn with shared end points. | ok (tested) |
| `Scripting.Dictionary` needs no reference when created with `CreateObject`. | ok |
| The CSV comment line starting with `#` at the end of `frame_tubes.csv` is skipped. | ok |

## What to test first, in order (about 30 minutes with SolidWorks open)

1. **Template and references**: new part, Tools > Macro > New, import `ImportAirfoil.bas`, check Tools > References shows both SolidWorks libraries. Press F5 with the part open: the file dialog must open in `cad/airfoils/`. Pick `symmetric.dat`, chord 300. Expect a curve named `Airfoil_symmetric_c300` in the tree. This tests `GetCurrentMacroPathName`, the file reader and the curve API in one go.
2. **SaveStandardViews** on the same part: six PNGs in `media/views/`. If the background is not white, the two preference lines failed: set it by hand and note which enum worked.
3. **ExportConfigsSTEP** on the Ring 0 rim part after adding a second configuration (any dimension change): two STEP files and `export_log.txt` with two mass lines. Open one STEP back in SolidWorks (File > Open, STEP) to confirm it is a solid. If `SaveAs3` errors, switch to `SaveAs2` as noted.
4. **ImportFrameNodes** in an empty part: 98 lines, then Repair Sketch, then one Structural Member on the four main-hoop lines with the 25.4x2.4 profile. If the member refuses the corner treatment, the endpoints did not merge: that is the `AddToDB` question above.

Report back: which of the four ran unchanged, which needed an edit, and what the edit was, so the `.bas` files can be corrected.
