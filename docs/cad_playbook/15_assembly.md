# 15 Top assembly (`cad/formula_single_seater.SLDASM`) and configurations

Every part is modelled in car coordinates, so the assembly is mostly three-plane mates and the suspension joints. Build it in the order parts are finished so the Ring 2 checks (zero rebuild errors, Interference Detection, 50 mm wheelbase change, mass and CG) run early and often.

**By macro (untested, needs the app):** `cad/macros/BuildAssembly.bas`. Run `BuildAssembly.main` with nothing open, after `BuildLayout` and `BuildTubes` (and `TrimTubes`).
- It imports `cad/step/*.step` once to `cad/body/*.SLDPRT`.
- It makes or opens `cad/formula_single_seater.SLDASM`. The layout goes in first and is fixed.
- The chassis and the 18 bodies get three Coincident mates to GROUND / CENTRE / FRONT_AXLE, named `<component>_G/_C/_X`. A part whose mates are refused is fixed in place and listed.
- The left tyres and rims are second instances turned 180 deg about the axle's vertical axis, and fixed.
- Then it runs Interference Detection (coincidence and the chassis' own tube contacts not counted), reports the mass and CG of what is in so far, saves, and writes `cad/build_assembly_report.txt`.
- A rerun only adds what is missing.

The suspension corners, the wing sub-assemblies and the A to D configurations below are scriptable (`AddMate5` with Concentric and sphere mates, `AddConfiguration3`, component suppression). They come as a macro once the wishbone, upright and hub parts exist.

## Structure

```
formula_single_seater.SLDASM
  master_layout.SLDPRT          (fixed; the only fixed component)
  chassis.SLDPRT
  suspension_front_R.SLDASM     (lower and upper wishbone, upright, hub, rim, tyre, tie rod, pushrod)
  suspension_front_L.SLDASM     (Mirror Components of the right)
  suspension_rear_R.SLDASM, suspension_rear_L.SLDASM
  rockers, springs (x4), steering rack (block), halfshafts
  body_main.SLDPRT, sidepod.SLDPRT (+ mirror), floor_diffuser.SLDPRT
  front_wing.SLDASM, rear_wing.SLDASM
  details: seat, driver_dummy, steering_wheel, motor, diff, battery
```

## Mate pattern

1. Insert `master_layout` first; it is fixed at the origin (the "(f)" prefix).
2. Every part built in car coordinates: three Coincident mates, GROUND to GROUND, CENTRE to CENTRE, FRONT_AXLE to FRONT_AXLE (select the planes from the FeatureManager flyout, not the graphics). Rename the three mates `<part>_G`, `_C`, `_X`.
3. **Suspension corner sub-assembly** (`suspension_front_R.SLDASM`): insert the layout again inside it (fixed) so the sub-assembly has the hardpoints, then:
   - wishbone lower: Concentric (inboard bolt bore to the layout axis through `HP_f_lwb_in_fwd` and `HP_f_lwb_in_aft`) + Coincident (housing mid-plane to a plane through `HP_f_lwb_in_fwd` normal to the axis). Free: rotation about the pivot.
   - wishbone upper: same.
   - upright: Concentric sphere-sphere to both wishbone pockets. Free: steering rotation about the ball-joint axis.
   - tie rod: Concentric sphere-sphere at both ends (inner to a dummy sphere on the layout at `HP_f_tierod_in`, or to the steering rack block). The upright's steering freedom is now fixed.
   - hub: Concentric to the upright bore + Coincident on the bearing-centre plane. Free: wheel rotation.
   - rim, tyre: as in `06_wheel.md`.
   - pushrod: sphere-sphere to the lower wishbone's `pushrod_out` pocket and to the rocker (rocker lives in the top assembly; leave the inner end free here and mate it at the top).
   Result: one degree of freedom (wheel travel) plus wheel spin. That is the Motion study's input.
4. Mirror: Insert > Mirror Components, mirror plane CENTRE, select the right corner sub-assembly, choose "Mirror" (not "Copy") for the parts whose geometry is handed (wishbones, upright, hub); rims and tyres can be copies. Rear corners: the rear sub-assembly is a separate file (`suspension_rear_R.SLDASM`) because the toe link replaces the tie rod and the pushrod goes to the upright.
5. Rockers: Concentric to the frame node axis (layout reference axis along X through the node) + Coincident mid-plane. Springs: sphere-sphere both ends. Pushrod inner: sphere-sphere to the rocker.
6. Wings: `front_wing.SLDASM` and `rear_wing.SLDASM` with three-plane mates.

## Configurations

`A`, `B`, `C`, `D` in the top assembly. For each: ConfigurationManager > right-click the configuration > Properties, then for the wing sub-assemblies and `floor_diffuser` set the referenced configuration via Component Properties (right-click the component > Component Properties > "Referenced configuration" and tick "This configuration" **verify** the 2026 dialog), and in `A` suppress `front_wing` and `rear_wing` (right-click > Suppress, with "This configuration" active). The master layout's own configuration (FW_POSITION angles) must match: set its referenced configuration the same way. The Configure Component table (right-click a component > Configure Component) does all of this in one grid and is faster. **verify** that mirrored components follow the configuration of their seed.

## Checks (Ring 2 report)

1. **Rebuild errors**: Ctrl+Q (force rebuild) with the FeatureManager expanded; zero yellow/red. Screenshot.
2. **Interference Detection**: Tools > Evaluate > Interference Detection, "Treat coincidence as interference" off, "Include multibody part interferences" on. Expected: the tyre-to-floor? none; wishbone-to-chassis at the pickups: the inboard housings sit on the tube centrelines, so they interfere with the tubes by design (v1 has no tabs). List those as accepted. Anything else is a fault.
3. **Wheelbase +50**: edit `wheelbase` 1550 to 1600 in `car_params.txt`, open the assembly, Ctrl+Q. The rear axle, rear corners, rear box tubes (only if the frame skeleton was drawn with equations; the macro-made skeleton does **not** follow, which is the one thing that will not move: note it) and the rear wing move. Zero errors. Edit back to 1550, Ctrl+Q.
4. **Mass Properties**: Tools > Evaluate > Mass Properties with the driver dummy suppressed gives `mass_car` and the CG (X from the front axle = `cg_x_from_front_axle`, Z = `cg_height`); with the dummy, the total. Write all three back to `car_params.txt`, rerun `run_all` in MATLAB.
5. **CFD bodies**: `14_cfd_body.md`.

## Beginner mistakes

- Mating to faces instead of planes and axes: faces change when a feature changes; planes and named reference points do not. Only use faces for the spherical pockets and bearing bores.
- Over-defining a wishbone with two Concentric mates on the two inboard housings: SolidWorks accepts it, Motion flags it as redundant. One Concentric to the axis, one Coincident along it.
- Letting the layout float in the sub-assembly: fix it (right-click > Fix) or every corner drifts.
- Forgetting "This configuration" versus "All configurations" when suppressing the wings in A: suppressing in all configurations deletes the wings from every variant.
- Interference Detection on a 300-component assembly with the frame's 98 bodies takes minutes: run it with the chassis excluded first (select components), then only chassis vs wishbones.

## End-of-assembly check

- Ring 2 checks 1 to 4 pass and are in `docs/log.md` with screenshots.
- `SaveStandardViews` run on the assembly in configuration C; the iso shot goes in the README as a placeholder until the renders exist.
