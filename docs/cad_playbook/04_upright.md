# 04 Upright (`cad/suspension/upright_front.SLDPRT`, `upright_rear.SLDPRT`)

The machined aluminium part that joins the two ball joints, the tie rod and the wheel bearing. It is also the Ring 4 stress study part, so keep it a single clean solid with no cosmetic features.

## Inputs

Hardpoints `f_lwb_out`, `f_uwb_out`, `f_tierod_out`, `f_pushrod_out` (rear: `r_lwb_out`, `r_uwb_out`, `r_toelink_out`, `r_pushrod_out`), wheel centre (X 0 or `wheelbase`, Y `track_front/2`, Z `tyre_rolling_radius`), `static_camber_front/rear`. Bearing: 2 x angular contact 7206 (30 x 62 x 16) in a 62 H7 bore, bearing centre at the wheel centre, bore axis = the wheel axis (tilted by static camber about X and by the toe setting, zero here). Material 7075-T6 (or 6061-T6, say which in `docs/stress.md`).

Steering axis: from `f_lwb_out` to `f_uwb_out`: KPI 6.0 deg, caster 4.7 deg (from `suspension_geometry`). The upright does not need to know those numbers; they fall out of the hardpoints.

## Feature order (front)

1. Template, insert the master layout.
2. **Sketch `axis_and_points`** (3D): the two ball-joint points, the tie-rod outer point, the pushrod outer point (front: on the lower wishbone, so not on the upright; rear: on the upright), the wheel centre point and the wheel axis line (200 mm long through the wheel centre, direction from `static_camber` and toe: draw it in a plane parallel to FRONT_AXLE through the wheel centre, angle `="static_camber_front"` from the Y direction). All dimensioned by equations.
3. **Sketch `bearing_housing`** on a plane normal to the wheel axis at the wheel centre: circle D 90 (housing OD). Extrude mid-plane 40 mm (Insert > Boss/Base > Extrude, Mid Plane). This is the hub carrier.
4. **Upper arm**: a plane through the wheel axis and the upper ball joint; sketch a tapered beam from the housing to a D 30 boss at `f_uwb_out`. Extrude mid-plane 20 mm. Merge.
5. **Lower arm**: same to `f_lwb_out`, 25 mm thick, wider (the lower joint carries most of the load).
6. **Steering arm**: a beam from the housing to a D 24 boss at `f_tierod_out`, 16 mm thick. On the rear it is the toe-link arm.
7. **Ball studs**: at each ball-joint point, a sphere D 16 (Revolve of a semicircle, merge) on a short D 12 neck. These spheres are what the wishbone pockets mate to.
8. **Bearing bore**: Cut-Extrude D 62 through the housing along the wheel axis, with a 2 mm lip at the outboard end (D 55 through-hole) to retain the bearings.
9. **Lightening**: none in v1. Fillets R 5 at all arm-to-housing junctions (Simulation needs them; sharp internal corners give infinite stress).
10. Material 7075-T6 (SolidWorks: "7075-T6 (SN)"). Mass target 0.6 to 0.9 kg.

Rear: same, with the toe-link arm pointing rearward (toe link at X 1660) and a pushrod boss at `r_pushrod_out`.

## Mates

Ball spheres to the wishbone pockets (Concentric sphere-sphere); tie-rod pocket to the steering arm sphere; the hub's shaft Concentric to the bearing bore and Coincident on the bearing centre plane.

## Configurations

`Default`.

## Beginner mistakes

- Modelling the upright around the wheel axis as if it were vertical: it is tilted by static camber (1.5 deg) and the ball joints define a steering axis with KPI and caster, so nothing is square to anything. Build from the points, never from the default planes.
- Making the arms as separate bodies and forgetting to merge: the stress study then sees three parts with no contact.
- Sharp internal corners: add the R 5 fillets before the study, not after it fails.
- Making it too thin to look racy: v1 is a block with arms; the stress result will say where it can lose material.

## End-of-part check

- One solid body (Tools > Evaluate > Check reports 1 body, no open surfaces).
- The sphere centres sit exactly on the hardpoints (Measure from the sphere face centre to the origin planes: reads `f_lwb_out_x/y/z`).
- Bearing bore axis passes through the wheel centre (Measure from the bore axis to `WHEEL_CENTRE_HEIGHT` plane = 0 at X = 0).
- Mass 0.5 to 1.0 kg. Save a copy of the feature tree screenshot for `docs/stress.md`.
