# 03 Wishbones (`cad/suspension/wishbone_front_lower.SLDPRT`, `_front_upper`, `_rear_lower`, `_rear_upper`, plus `tierod.SLDPRT`, `toelink.SLDPRT`, `pushrod.SLDPRT`)

Four A-arms and three two-force links. All geometry comes from the hardpoints; the parts themselves are just tubes swept along the layout's construction lines plus a clevis or rod end at each point.

## Inputs

Hardpoint block in `car_params.txt` (`f_lwb_*`, `f_uwb_*`, `r_lwb_*`, `r_uwb_*`, `f_tierod_*`, `r_toelink_*`, `f_pushrod_*`, `r_pushrod_*`). Tube: 16 mm OD x 1.5 mm wall steel for wishbones (not in the parameter file; add `wishbone_tube_od`= 16 and `wishbone_tube_wall`= 1.5 if you want them linked). Rod ends: M8 spherical, ball diameter 16 (model as a sphere D 16 in a 22 mm housing). Pushrod and tie rod 14 x 1.5.

Lengths (from `suspension_geometry` output, for the record; the CAD derives them): front lower legs 329 / 325 mm, front upper 278 / 282 mm, front tie rod 305 mm; rear lower 272 / 325 mm, rear upper 241 / 244 mm, toe link 380 mm. **verify** by measuring in the CAD after step 3; a mismatch means a hardpoint was typed wrong.

## Feature order (front lower; the others are copies)

1. New part from the template; insert the master layout (reference geometry and sketches).
2. **Sketch `legs`**: 3D sketch, Convert Entities on the layout's two leg construction lines (inboard fwd to outer, inboard aft to outer). If Convert Entities refuses on an inserted sketch, draw the two lines and dimension their endpoints to the planes with the same `="f_lwb_in_fwd_x"` equations (three per point).
3. **Sketch `tube_profile`**: a plane normal to the forward leg at its inboard end (Insert > Reference Geometry > Plane, "Perpendicular to curve" at point) with a circle D 16. Insert > Boss/Base > Sweep along the forward leg. Repeat for the aft leg. Two bodies; tick "Merge result" on the second.
4. **Outer node**: Insert > Boss/Base > Extrude a cylinder D 22 x 24 mm centred on the outer hardpoint, axis vertical (this is the ball-joint housing; the upright's ball joint sits inside it). Cut a sphere D 16 at the hardpoint (Revolve-cut of a semicircle) so the mate has a spherical face: in the assembly a Concentric mate between two spherical faces behaves as a ball joint.
5. **Inboard ends**: at each inboard point a cylinder D 22 x 20 along the pivot axis (the line between the two inboard points), with a D 8 hole along the axis for the pivot bolt. The chassis has no tab in v1; the hole axis is what the Concentric mate uses.
6. Fillets R 3 where the tubes meet the housings (cosmetic, last, suppress during the Motion study if it slows it down).
7. Material 1020 steel. Mass about 0.45 kg each.

Tie rod, toe link and pushrod: one line, one sweep of D 14, a D 16 spherical pocket at each end.

## Mates (see `15_assembly.md` for the pattern)

- Inboard: Concentric between the inboard bolt-hole cylinder and the layout's pivot axis (reference axis through `HP_f_lwb_in_fwd` and `HP_f_lwb_in_aft`), plus one Coincident between the housing mid-plane and a plane through the hardpoint to fix the position along the axis. That leaves rotation about the pivot free, which is what a wishbone does.
- Outer: Concentric between the spherical pocket and the upright's ball (sphere to sphere): free rotation, fixed centre.
- The pushrod outer goes to the lower wishbone (front) or the upright (rear) at `*_pushrod_out`; the inner to the rocker.

## Configurations

`Default` only. Left-hand parts are the same file mirrored in the assembly (Insert > Mirror Components, option "Mirror" not "Copy", about the layout CENTRE plane). **verify**: mirrored components may create `_mirror` derived parts; accept that.

## Beginner mistakes

- Sweeping with the profile not perpendicular to the path: the tube becomes elliptical. Use the "perpendicular to curve" plane.
- Building the wishbone in its own local frame and then trying to mate it into position by distances: the point of this playbook is that every part is already in car coordinates, so mates are only coincident/concentric, never distance mates.
- Forgetting the spherical pocket: a cylinder-to-cylinder concentric mate at the outer point locks a rotation and the Motion study over-constrains (the "redundant constraints" message in Ring 3).
- Modelling the rod-end bolt and jam nut: not in v1.

## End-of-part check

- Measure (Tools > Evaluate > Measure) the distance between the inboard housings and the outer housing: matches the lengths above within 1 mm.
- The part is in car coordinates: the outer housing centre reads `f_lwb_out_x/y/z` in Measure against the origin planes.
- Mass under 0.6 kg.
