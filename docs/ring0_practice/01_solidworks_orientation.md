# 01 SolidWorks 2026 orientation (45 min)

Goal: know where everything is, set the options once, and be able to look at a model from any side without thinking.

## 1. Start and the Welcome dialog (5 min)

1. Start SolidWorks 2026 from the Start menu. The first start asks you to accept the licence and may ask for the Student Edition serial or an "SOLIDWORKS ID" login (**verify**: the 2026 student licence is activated online through the 3DEXPERIENCE ID you used to download it; if it asks for a serial, it is the one in your download email).
2. A **Welcome** dialog appears: New (Part, Assembly, Drawing), Recent documents, Learn, Alerts. Ctrl+F2 brings it back at any time. Click **Part**.
3. If the template picker opens instead (Advanced view), pick "Part" and OK. In exercise 5 you will make the project's own template; for now the default is fine.

## 2. The five areas of the window (10 min)

Point at each one and name it; the names matter because every later file uses them.

| Area | Where | What it does |
|---|---|---|
| **CommandManager** | ribbon across the top, tabs Features, Sketch, Surfaces, Evaluate, MBD Dimensions, ... | the tools. Features = 3D (Extrude, Revolve, Cut, Fillet, Hole Wizard). Sketch = 2D (Line, Circle, Smart Dimension, Relations). Evaluate = Measure, Mass Properties, Check, Interference. Right-click a tab to show more (Weldments, Sheet Metal). |
| **FeatureManager design tree** | left panel | the history of the part: every sketch and feature in order. Click one to highlight it, right-click for Edit Sketch / Edit Feature / Suppress / Rename. The tabs at the top of the panel switch to the **PropertyManager** (the options of the current command), the **ConfigurationManager** (variants of the part), DimXpert and the Display Manager. |
| **Graphics area** | the middle | the model. The **Heads-up View toolbar** floats at the top of it: zoom to fit, section view, view orientation, display style, hide/show, appearance. |
| **Task Pane** | right edge, collapsed | Resources, Design Library (standard parts, the weldment profiles live here), File Explorer, Appearances. Mostly closed. |
| **Status bar** | bottom | units (click it to change), sketch state (Under Defined / Fully Defined / Over Defined), coordinates of the cursor in a sketch. |

**verify**: SolidWorks 2025 introduced a refreshed interface (new icons, an optional light theme, "Compact" CommandManager); 2026 may have moved a few commands between tabs. If a tool named below is not where this says, type its name in the **search box at the top right** of the window ("Search commands") and run it from there; the result also shows the menu path.

## 3. Mouse and keyboard (10 min)

Do each one three times until it is reflex.

| Action | How |
|---|---|
| Rotate | hold the middle button (wheel) and drag |
| Pan | Ctrl + middle drag |
| Zoom | scroll the wheel (zooms towards the cursor); Shift + middle drag for smooth zoom |
| Zoom to fit | F |
| Zoom to selection | right-click > Zoom to selection, or Shift+Z? **verify** |
| Standard views | Ctrl+1 Front, Ctrl+2 Back, Ctrl+3 Left, Ctrl+4 Right, Ctrl+5 Top, Ctrl+6 Bottom, Ctrl+7 Isometric, Ctrl+8 Normal To (the selected face or sketch plane) |
| View orientation dialog | Space bar (also lets you save a named view) |
| Shortcut toolbar | S (a small floating toolbar of the most used tools for the current context: sketch, part, assembly) |
| Mouse gestures | right-button drag in a direction gives a wheel of 8 commands; try it once, then decide whether you like it (Tools > Customize > Mouse Gestures to change or switch off) |
| Rebuild | Ctrl+B (Ctrl+Q forces a full rebuild of every feature) |
| Repeat the last command | Enter |
| Escape a command | Esc |
| Undo | Ctrl+Z (works inside sketches too) |
| Select several | Ctrl+click (in a sketch, box-select left to right selects fully enclosed, right to left selects anything touched) |

## 4. Options to set once (10 min)

Tools > Options opens two tabs: **System Options** (global, every file) and **Document Properties** (this file only; saved into the template).

System Options:
- General: untick "Use English language menus" only if your Windows is not English (it is). Tick "Enable Confirmation Corner" (the small tick in the top right of the graphics area to leave a sketch) **verify** still present.
- Backup/Recover: Auto-recover every 10 minutes; backup copies 2.
- File Locations: note the folder for **Document Templates** and **Weldment Profiles** (you need both later); write them in `docs/log.md`.
- Performance: "Verification on rebuild" off (default). Level of detail slider in the middle.
- Colors: Background appearance "Plain (Viewport Background)" white. The screenshot macro assumes a white background.

Document Properties (for this file; exercise 5 saves them in the template):
- Units: **MMGS (millimetre, gram, second)**, length decimals .12 (two decimals), angle decimals .12.
- Drafting Standard: ISO.
- Dimensions > Primary precision .12.
- Image Quality: shaded slider at about three quarters (smoother curves in screenshots, slower rebuild on huge models; the car is not huge).

Click OK, then File > Save As and save the empty part as `cad/practice/orientation_test.SLDPRT` so you have seen the save dialog: note the file type list (Part, and under it STEP, Parasolid, IGES, STL, PNG, ... which is how exports are done).

## 5. A first sketch, just to touch everything (10 min)

1. In the FeatureManager click **Front Plane**. A small context toolbar appears: click the **Sketch** icon (or Sketch tab > Sketch). The view turns normal to the plane; the Confirmation Corner shows a sketch icon top right.
2. Sketch tab > **Circle**. Click the origin (it snaps; a small orange dot appears), move out, click again. Esc.
3. Sketch tab > **Smart Dimension** (also D on the S shortcut toolbar). Click the circle, move the cursor away, click to place the dimension, type `100`, Enter. The circle turns from blue to **black**: fully defined. Look at the status bar: "Fully Defined".
4. Exit the sketch (Confirmation Corner tick, or Ctrl+Q? no: click the tick). The tree shows `Sketch1`.
5. Features tab > **Extruded Boss/Base**. The PropertyManager appears on the left: Direction 1 Blind, depth `20`. Green tick.
6. Press Ctrl+7 (iso), F (fit). A disc. Evaluate tab > **Mass Properties**: it reports volume 157079.63 mm^3 (= pi/4 x 100^2 x 20, hand check 157,080). Mass is in grams because no material is set; right-click **Material** in the tree > Edit Material > Aluminium Alloys > 6061 Alloy > Apply, Close. Mass Properties again: 424.12 g (2700 kg/m3 x 1.5708e-4 m3 = 0.4241 kg). That is the pattern of every check in this guide: build, read Mass Properties, compare with a number you computed by hand.
7. Rename `Sketch1` to `Sketch_disc` and `Boss-Extrude1` to `Extrude_disc` (slow double-click, or select and F2). Ctrl+S.

## Expected result

A 100 mm x 20 mm 6061 disc at 424 g, saved in `cad/practice/`, with MMGS units, and you can rotate, pan, zoom and go to any standard view without looking at this page.

## Check

- Status bar shows MMGS.
- Tools > Options > System Options > Backup/Recover shows 10 minutes.
- Mass Properties 424.1 g within 0.5 g.
- Delete `orientation_test.SLDPRT` afterwards or keep it; it is not part of the car.
