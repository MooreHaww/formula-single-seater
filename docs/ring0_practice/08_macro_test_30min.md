# 08 Macro test order (30 min)

The four VBA macros in `cad/macros/` were written without SolidWorks open and have never run. This is the order to run them so that each failure tells you one thing. Detailed review notes per macro: `docs/cad_playbook/macro_review.md`; installation: `cad/macros/README.md`.

Before you start: `wing_element.SLDPRT` (exercise 6) and `rim.SLDPRT` (exercise 2) exist, and the VBA editor can be opened (Tools > Macro > New). **verify** that the Student edition's Tools menu has the Macro submenu; it does in Student Design Premium (the university licence), which is the same program as the commercial one.

## 0. Install all four (5 min)

For each `.bas`: Tools > Macro > **New**, save as `cad/macros/<Name>.swp` (same folder as the `.bas`, this matters: the macros find the repo root three folders up from their own path). The VBA editor opens with an empty module. File > **Import File...** > pick the `.bas`. In the Project tree remove the empty module the wizard made (right-click > Remove, No to export). Tools > **References**: "SldWorks 2026 Type Library" and "SOLIDWORKS 2026 Constant type library" must be ticked (**verify** the exact names; they are the first two entries when created through Tools > Macro > New). Ctrl+S, close the editor.

## 1. ImportAirfoil (5 min)

- Open a new part (MMGS). Tools > Macro > Run > `ImportAirfoil.swp`.
- Expect: a file dialog opening in `cad/airfoils/`. Pick `symmetric.dat`. An input box asks the chord: `300`. A message box reports the point count and that the curve is in the Front plane. A feature `Airfoil_symmetric_c300` appears in the tree.
- Check: Measure the curve's extent: 300 in X, 36 in Y. Compare with the manual import from exercise 6: identical shape (the macro scales `symmetric.dat`, x/c from 0 to 1, by the chord you typed).
- If the file dialog opens elsewhere: `GetCurrentMacroPathName` did not give the `.swp` path, the `.swp` is not in `cad/macros/`.
- If "Unable to create curve": two identical points in a row; the reader is supposed to drop them. Note the line of the error (Debug in the VBA error box highlights it) in `docs/log.md`.

## 2. SaveStandardViews (5 min)

- With `rim.SLDPRT` open and the window maximised: Tools > Macro > Run > `SaveStandardViews.swp`.
- Expect: six PNG files in `media/views/` named `rim_Default_iso.png`, `_front`, `_right`, `_top`, `_rear`, `_bottom`, white background, the part filling the view.
- If the background is not white: both preference calls failed. Set Tools > Options > Colors > Background appearance to Plain (Viewport Background) white by hand and note it; the macro keeps working.
- If the images are tiny: the graphics area was small; maximise the window.
- If `SaveAs3` returns an error: note the number from the message box; the review notes suggest `SaveAs2` as the fallback (edit the one line in the VBA editor).

## 3. ExportConfigsSTEP (10 min)

- Open `rim.SLDPRT`. Add a second configuration first: ConfigurationManager tab > right-click the part name > Add Configuration, name `wide`; with `wide` active, double-click the width dimension and set it to 200 **This configuration only** (the Modify box's configuration drop-down), rebuild. Switch back to `Default`.
- Tools > Macro > Run > `ExportConfigsSTEP.swp`.
- Expect: `cfd/geometry/rim_Default.STEP` and `rim_wide.STEP`, and `cfd/geometry/export_log.txt` with two lines giving mass and CG per configuration (3.286 and 3.608 kg if exercise 5's hand numbers hold).
- Check: File > Open one STEP (file type STEP, Import as solid): a single solid body.
- If "wrong number of arguments" on `SaveAs3`: switch to `SaveAs2` as the review notes say. If a STEP export option enum is unknown: it is wrapped in On Error, the export still runs with the Tools > Options > Export > STEP settings; set AP214 and "Solid/Surface geometry" there once.

## 4. ImportFrameNodes (5 min plus a wait)

- Open a new part from the car template (MMGS). Tools > Macro > Run > `ImportFrameNodes.swp`.
- Expect: 10 to 30 seconds, then a 3D sketch `FRAME_SKELETON` with 98 lines matching `media/frame_layout.png` (iso view, F to fit). A message box reports 42 nodes and 98 lines.
- Check: Tools > Sketch Tools > **Repair Sketch** reports nothing to repair (endpoints merged). Then Weldments > Structural Member > `iso / tube_round / 25.4x2.4` on the four main-hoop lines (`MH_*`, select them in the graphics area), End Miter: the preview must show mitred corners. If it refuses the corner treatment, the endpoints did not merge: that is the `AddToDB` question in the review notes; run Repair Sketch and try again, and report which.
- Do not keep this part; the chassis is built in Ring 2b from a fresh template.

## Report (what to write in docs/log.md)

One line per macro: ran unchanged / needed an edit (which line, what) / failed (error text). The `.bas` files are the source; after fixing something in the VBA editor, File > Export File... back over the `.bas` so git sees the change. Delete `media/views/*.png` or leave them; the folder is git-ignored.
