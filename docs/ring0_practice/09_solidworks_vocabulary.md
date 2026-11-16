# 09 SolidWorks vocabulary, one page

Keep this open during Ring 2. Words in **bold** are the ones the playbook files use without explanation.

## Documents

| Word | Meaning |
|---|---|
| **Part** (.SLDPRT) | one component: sketches and features making one or more solid bodies |
| **Assembly** (.SLDASM) | parts (and sub-assemblies) placed relative to each other by mates; stores only references to the part files |
| Drawing (.SLDDRW) | 2D views of a part or assembly; not used in this project except for the hub |
| **Template** (.prtdot / .asmdot) | a saved empty document with units, planes, equations: every car part starts from `cad/templates/car_part.prtdot` |
| **Configuration** | a named variant of a document (dimensions, suppressed features, different parts in an assembly); the car's aero variants A to D are configurations |
| **Pack and Go** | copies an assembly with every file it references into one folder or zip |

## Tree and geometry

| Word | Meaning |
|---|---|
| **FeatureManager design tree** | the ordered history of the document on the left; the model is rebuilt top to bottom |
| **PropertyManager** | the options panel of the current command, in the same left panel |
| **ConfigurationManager** | the tab listing configurations |
| **Rollback bar** | the yellow line at the bottom of the tree; drag it up to see the model as it was before later features |
| **Origin**, **Front / Top / Right Plane** | the default reference geometry of every document; renamed GROUND, CENTRE, FRONT_AXLE in the car template |
| **Reference geometry** | planes, axes, points and coordinate systems you add (Insert > Reference Geometry); mates and sketches can use them, they never disappear when a face does |
| **Body** | one connected solid. A part may be multibody (weldments are, on purpose) |
| **Face, edge, vertex** | the topology of a body; what you click to sketch on, mate to, or dimension |
| **Suppress** | switch a feature or component off without deleting it (greyed in the tree); per configuration |
| **Rebuild** (Ctrl+B) | re-evaluate the tree after a change; Ctrl+Q forces every feature |
| Error (red) / Warning (yellow) | a feature could not rebuild / rebuilt with something dangling; fix before continuing |

## Sketching

| Word | Meaning |
|---|---|
| **Sketch** | a 2D drawing on a plane or flat face, the input of most features |
| **3D Sketch** | lines and points in space, used for frame centrelines and hardpoints |
| **Smart Dimension** | the one dimension tool: it works out whether you want a length, diameter, angle or distance from what you pick |
| **Relation** (constraint) | a geometric rule: Coincident, Horizontal, Vertical, Tangent, Concentric, Equal, Symmetric, Collinear, On Edge |
| **Under defined** (blue) | free to move; **Fully defined** (black) locked by dimensions and relations; **Over defined** (yellow/red) conflicting |
| **Construction geometry** / **centreline** | dashed, not part of the profile; used as revolve axes, mirror lines, dimension references |
| **Convert Entities** | copies edges, curves or another sketch into the current sketch, with an On Edge relation that keeps them linked |
| **Offset Entities** | the same at a distance |
| **Trim / Extend** | cut or lengthen sketch lines to make a closed profile |
| **Contour** | a closed loop in a sketch; a feature can use one, several, or the regions between them |
| **Inference** | the dotted lines and icons that appear while sketching, showing a relation SolidWorks will add if you click now |

## Features

| Word | Meaning |
|---|---|
| **Boss/Base** | adds material (Extrude, Revolve, Sweep, Loft) |
| **Cut** | removes material (Extruded Cut, Revolved Cut, Hole Wizard) |
| **Extrude** | push a profile along its normal: Blind (a distance), Through All, Up To Surface, Mid Plane (both ways) |
| **Revolve** | spin a profile about a centreline |
| **Sweep** | move a profile along a path (tubes, chain, helix springs) |
| **Loft** | blend between several profiles (nose, sidepods) |
| **Shell** | hollow a body to a wall thickness |
| **Fillet / Chamfer** | round / bevel an edge |
| **Hole Wizard** | a standard hole (clearance, tapped, counterbored) with its size and standard attached |
| **Linear / Circular Pattern**, **Mirror** | copies of a feature or body |
| **Combine** | add, subtract or intersect bodies in a multibody part (the CFD body) |
| **Thin feature** | an extrude or revolve of an open profile given a wall thickness (seat, bodywork) |
| **Weldment**, **Structural Member**, **Trim/Extend**, **Cut list** | the tube-frame toolset: a sketch of centrelines, a profile swept along each, trimming where they meet, a table of lengths |
| **Curve Through XYZ Points** | a 3D curve from a text table (airfoils) |
| **Equation**, **Global variable**, **Link to external file** | dimensions driven by named values, which can come from `params/car_params.txt` |
| **Material** | density and stiffness assigned to the part; drives Mass Properties and Simulation |

## Assembly

| Word | Meaning |
|---|---|
| **Component** | a part or sub-assembly inside an assembly; `(f)` fixed, `(-)` under defined, nothing = fully mated |
| **Mate** | a relation between components: Coincident, Concentric, Parallel, Perpendicular, Distance, Angle, Tangent; advanced: Width, Path, Symmetric; mechanical: Hinge, Gear, Rack |
| **Mate alignment** (Aligned / Anti-aligned) | which way a coincident or concentric mate faces; flip it when a part lands inside out |
| **Degrees of freedom** | what a component can still do after its mates; a wheel should keep one rotation |
| **Interference Detection** | reports overlapping volumes between components |
| **In-context** (the `->` suffix) | a sketch or feature that references another component's geometry from inside the assembly; fine when the reference is the master layout, dangerous otherwise |
| **Lightweight / Resolved** | components loaded partly (fast) or fully (needed for mass properties, Motion, Simulation) |
| **Motion Study** | the tab at the bottom of an assembly: animation, basic motion, or SolidWorks Motion (Ring 3) |

## Evaluate

| Word | Meaning |
|---|---|
| **Mass Properties** | mass, volume, centre of mass, inertia of the selection |
| **Measure** | distances, angles, radii between any two things |
| **Check** | reports open edges, invalid faces, body count |
| **Section View** | cut the view by a plane to see inside |
| **Sensor** | a watched value (mass, dimension, simulation result) with an alarm |

## Simulation and Motion (Rings 3 and 4, for reading ahead)

| Word | Meaning |
|---|---|
| **Study** | one analysis setup: Static, Frequency, Buckling, Motion |
| **Fixture** | a support (Fixed, Roller/Slider, Hinge, Reference Geometry) |
| **External load** | force, pressure, torque, remote load, gravity |
| **Mesh** | the finite elements: solid (tetrahedra), shell, or **beam** (one line per tube, what the weldment chassis uses) |
| **Connector** | bolt, pin, spring, rigid link between parts |
| **Factor of safety** | material strength over computed stress; the upright's headline number |
| **Motion analysis** | rigid-body dynamics of the assembly with motors, springs, contacts; the bump and steering sweeps of Ring 3 |
