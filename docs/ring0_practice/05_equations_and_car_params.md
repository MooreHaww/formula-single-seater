# 05 Global variables and equations linked to params/car_params.txt (45 min)

Goal: the rim's diameter and width come from the parameter file. Change the file, press Rebuild, the rim changes. This is the mechanism behind the whole car ("change the wheelbase, press Rebuild, the car follows"), and the project's part template is made at the end of this exercise.

## How it works

SolidWorks keeps a list of **global variables** (`"rim_width" = 178`) and **equations** (`"D1@Sketch_rim_profile" = "rim_width"`) per document, in Tools > Equations. The list can be **linked to an external text file**: SolidWorks then reads the variables from that file on every rebuild and (if you let it) writes changes back. `params/car_params.txt` is written in exactly that file's format (one `"name"= value ' comment` per line), so one file serves SolidWorks and MATLAB.

## Steps

1. Open `cad/practice/rim.SLDPRT`.
2. **Tools > Equations** (also: right-click the `Equations` folder in the tree if it exists, > Manage Equations). The dialog has three views at the top left: Equation View, Dimension View, Ordered View. Stay in Equation View.
3. At the bottom of the dialog tick **Link to external file** (**verify**: in 2024 it is a checkbox near the bottom left labelled "Link to external file"; clicking it opens a file picker). Pick `params/car_params.txt`. A second dialog asks what to link: keep **Equations** and **Global Variables** ticked; choose the option that treats the file as the source (in 2024: "Link to file" with "Link to external file" direction arrows showing file -> model) **verify** the wording. OK.
4. The Global Variables table fills with every entry of the file (245 of them, including the long `mass_car` and `cg_*` expressions, which SolidWorks evaluates itself; if any line is flagged with a red error, note which and tell the MATLAB side, the file format is shared). The dialog may also warn that lines starting with `'` are comments; that is fine.
5. Now point the rim at the variables. Still in the Equations dialog, in the **Equations** section (lower table), click the first empty row under "Equations"... Easier way, in the model: close the dialog, double-click the `Revolve_rim` feature in the graphics area or the tree so its dimensions appear, double-click the `127` radius dimension. In the Modify box type `=` (an equals sign first): a drop-down of **Global Variables** and functions appears; pick `rim_diameter` and complete it to `="rim_diameter"/2`. Tick. The dimension now shows a small Σ (sigma) in front of the value, meaning it is driven by an equation. Do the same for the `178` width: `="rim_width"`, and for the `89` offset: `="rim_width"/2`.
6. Ctrl+B. Nothing moves yet (same numbers). Tools > Equations: the Equations table lists the three equations with their dimension names (`D1@Sketch_rim_profile = "rim_diameter"/2`, ...). The variables show the file as their source.
7. **The test.** Close SolidWorks' dialog. In a text editor (Notepad, VS Code) open `params/car_params.txt`, change `"rim_width"= 178` to `"rim_width"= 200`, save. Back in SolidWorks, Ctrl+B (or Ctrl+Q). The rim grows to 200 wide. Mass Properties: barrel pi/4 x (254^2 - 240^2) x 200 = 1,086,371 mm^3; total 1,086,371 + 252,132 - 2,078 = 1,336,425 mm^3 -> **3.608 kg**. (The disc stays at 40 mm outboard? Yes: step 5 tied only the barrel's centring to `rim_width/2`; the `40` is a plain number, so the disc keeps its place. Good: check that the disc is still 40 from the centre.)
8. Change the file back to 178, save, Ctrl+B: 3.286 kg again. If SolidWorks did not pick up the change, Tools > Equations shows whether the link is "to file" and a **Sync** or re-link control; check also that the file was saved as plain text and not renamed.
9. Save the rim.

## Make the project template (15 min)

Every car part starts from one template so the units and the link are never forgotten.

1. File > New > Part. Tools > Options > Document Properties: Units MMGS, decimals .12, ISO. Tools > Equations > Link to external file > `params/car_params.txt` (as above). Rename the three default planes as the playbook asks: **Top Plane** -> `GROUND`, **Right Plane** -> `CENTRE`, **Front Plane** -> `FRONT_AXLE` (slow double-click the name in the tree, or select and F2). **verify** the mapping against `docs/cad_playbook/00_index.md` (Coordinate frame): sketch the ground on the Top plane, the centreline on the Right plane, the axle plane on the Front plane; if a part later comes out mirrored, the note there says to flip the Y sign convention once in the master layout and nowhere else.
2. File > Save As > Save as type **Part Templates (*.prtdot)**. The dialog jumps to the templates folder; instead navigate to `cad/templates/` in the repo (make the folder) and save `car_part.prtdot`. Then Tools > Options > System Options > File Locations > Document Templates > Add > `cad/templates/`, so it appears in the New dialog's template picker (Advanced view).
3. Test: File > New > Advanced > the `cad/templates` tab > `car_part`. The new part has the three named planes and Tools > Equations already lists the file. **verify** that a linked equation file path saved in a template is kept absolute (`C:\...\params\car_params.txt`); on another machine or after moving the repo, re-link once per part as the README says.
4. Do the same for an assembly template (`car_assembly.asmdot`): MMGS only, no equations needed.

## Expected result

The rim follows `rim_width` in the text file (178 -> 200 -> 178 changes the mass 3.286 -> 3.608 -> 3.286 kg), and `cad/templates/car_part.prtdot` exists with MMGS, the three named planes and the linked file.

## Check

- Double-click `Revolve_rim`: the three driven dimensions show the Σ prefix.
- Tools > Equations: the top of the dialog names `car_params.txt` as the linked file and lists 245 global variables; none in red.
- A new part from the template shows GROUND, CENTRE, FRONT_AXLE in the tree and the linked file in Tools > Equations.

## Things that go wrong

- Typing `"rim_width"` **without** the leading `=` in the Modify box: SolidWorks reads it as text and ignores it. The `=` is what switches the box into equation mode.
- Typing a name that is not in the file: SolidWorks silently creates a **local** global variable with that name and value, and the part stops following the file for that number. The playbook's rule: if a parameter is missing, add it to the file, never invent a local one. Tools > Equations shows local variables without the file icon.
- Two parts open, both linked, one of them with "write back to file" enabled: a dimension edit in that part rewrites `car_params.txt` with SolidWorks' own formatting (it may drop the comments and the MATLAB-side markers). Keep the link **read-only** (file -> model) everywhere; edit the file in a text editor.
- SolidWorks cannot evaluate a line: everything in `car_params.txt` uses only `+ - * / ( )`, numbers and other names, which both sides accept. If 2026 refuses the long `cg_x_from_front_axle` line (length limit, **verify**), say so in `docs/log.md` and split it into partial sums in the file; MATLAB will read either form.
