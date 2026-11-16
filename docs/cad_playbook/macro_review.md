# Macro review (read-through, no SolidWorks available)

The four `.bas` modules in `cad/macros/` were re-read for API mistakes against what I know of the SolidWorks API up to 2025 and for Student-edition limits. Nothing here has been executed. Items marked **fixed** were changed in the files; items marked **verify** need a look in the API Help (Help > API Help, or the online "SOLIDWORKS API Help" for 2026) on first run.

## Cross-cutting

| Topic | Finding | Status |
|---|---|---|
| Type library references | A new macro created with Tools > Macro > New references "SldWorks 2026 Type Library" and "SOLIDWORKS 2026 Constant type library" automatically, so bare enum names like `swDocPART`, `swStandardViews_e.swIsometricView` resolve. If you import the `.bas` into a macro created another way, add them under Tools > References in the VBA editor. | verify once |
| `GetCurrentMacroPathName` | Exists on `ISldWorks` and returns the running `.swp` path; the repo root is derived from it (three levels up). Running the macro from a different folder breaks the paths, so keep the `.swp` next to the `.bas` in `cad/macros/`. | ok |
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
| `swUserPreferenceIntegerValue_e.swStepAP` with value 214 is documented. `swStepExportGeometry` is **not certain** to exist under that name (the option "Solid/Surface geometry" may be `swStepExportGeometryRule` or only reachable through Tools > Options). Wrapped in `On Error Resume Next`; set the option once in Tools > Options > Export > STEP as a fallback. | fixed (guarded), verify |
| `IModelDocExtension.SaveAs3(name, version, options, exportData, advancedSaveAsOptions, errors, warnings)` is the 2019+ signature with 7 arguments; passing `Nothing` for both object arguments is allowed for STEP. If 2026 reports "wrong number of arguments", use `SaveAs2` (6 arguments, no advanced options). | verify |
| `ShowConfiguration2` returns Boolean and activates by name; configuration names with spaces are fine, but the file name is sanitised (`SafeName`). | ok |
| `CreateMassProperty` on an assembly with lightweight components returns zeros; set the assembly to resolved (right-click top > Set Lightweight to Resolved) before running. | verify |
| The log is appended, never overwritten, so repeated runs accumulate; that is intended (dated). | ok |
| On a part with many configurations each `ForceRebuild3` is a full rebuild; the CFD body has 4, fine. | ok |

## SaveStandardViews.bas

| Finding | Status |
|---|---|
| Plain background: the toggle `swColorsGradientPartBackground` may not exist by that name; the integer preference `swColorsBackgroundAppearance` with `swColorsBackgroundAppearance_PlainWhite` is the documented one in recent releases. Both are now attempted under `On Error Resume Next`. If neither works, set Tools > Options > System Options > Colors > Background appearance to "Plain (Viewport Background)" by hand once. | fixed (guarded), verify |
| `ShowNamedView2("", viewId)` with `swStandardViews_e` values is documented; the iso/front/right/top/back/bottom ids are 7/1/4/5/2/6 **verify** the constants resolve from the type library. | verify |
| `SaveAs3` to a `.png` path performs an image export of the current view at the graphics-area size; it is documented behaviour for `SaveAs`. If the file comes out tiny, maximise the SolidWorks window first. Image export options (Tools > Options > Export > PNG) apply. | verify |
| The `.png` SaveAs changes nothing in the document and does not alter `GetPathName`, so the document name is read before the loop. | ok |
| `media/views/` is ignored by `.gitignore`; copy the one picture you want into `docs/` or `media/`. | ok |

## ImportFrameNodes.bas (new)

| Finding | Status |
|---|---|
| `SketchManager.Insert3DSketch True` opens a 3D sketch; a second call closes it. `CreateLine(x1, y1, z1, x2, y2, z2)` in metres works inside a 3D sketch. | ok |
| `AddToDB = False` keeps inference on so that lines ending at the same coordinates share a sketch point (needed for the weldment corner treatment and for the beam mesh). If the sketch still shows separate coincident points, Tools > Sketch Tools > Repair Sketch merges them. With 98 lines and inference on, expect 10 to 30 s. | verify |
| `Scripting.Dictionary` needs no reference when created with `CreateObject`. | ok |
| The CSV comment line starting with `#` at the end of `frame_tubes.csv` is skipped. | ok |

## What to test first, in order (about 30 minutes with SolidWorks open)

1. **Template and references**: new part, Tools > Macro > New, import `ImportAirfoil.bas`, check Tools > References shows both SolidWorks libraries. Press F5 with the part open: the file dialog must open in `cad/airfoils/`. Pick `symmetric.dat`, chord 300. Expect a curve named `Airfoil_symmetric_c300` in the tree. This tests `GetCurrentMacroPathName`, the file reader and the curve API in one go.
2. **SaveStandardViews** on the same part: six PNGs in `media/views/`. If the background is not white, the two preference lines failed: set it by hand and note which enum worked.
3. **ExportConfigsSTEP** on the Ring 0 rim part after adding a second configuration (any dimension change): two STEP files and `export_log.txt` with two mass lines. Open one STEP back in SolidWorks (File > Open, STEP) to confirm it is a solid. If `SaveAs3` errors, switch to `SaveAs2` as noted.
4. **ImportFrameNodes** in an empty part: 98 lines, then Repair Sketch, then one Structural Member on the four main-hoop lines with the 25.4x2.4 profile. If the member refuses the corner treatment, the endpoints did not merge: that is the `AddToDB` question above.

Report back: which of the four ran unchanged, which needed an edit, and what the edit was, so the `.bas` files can be corrected.
