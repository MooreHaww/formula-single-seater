# Showcase films: notes (2026-11-25)

To be merged into README.md / docs/log.md by hand. Nothing was committed, and README.md and docs/log.md were not touched.

## How I read the brief

- **Two films.** Film 1 is a SolidWorks build-up of the as-built car (CP). Film 2 is the MATLAB lap sim of CP with the four-wheel model, on the autocross and on the fast circuit.
- **Film 1, "a few frames per tube group".** Each frame group is shown in 3 stills, added front to back (sorted by x). The order is bulkhead, front, side impact, hoops, hoop braces, sidepod tubes, then the rear box.
- **Film 1, uprights and hubs.** They are not in the brief's stage list. They appear as their own short stage between the suspension arms and the wheels. Without them the wheels would float.
- **Film 1 ground plane.** It is a 4.4 x 2.7 m grey plate. It is remade by the script into `cad/showcase/ground.SLDPRT` (git-ignored), and the car's assembly file is never saved.
- **Film 1 caption.** The brief asks for a short caption naming each stage, so each stage gets a caption pill. There is also a fixed title bar and a fixed footer: "CAD model, built by script from one parameter file. Virtual: nothing here was built or tested."
- **Film 2 lap times.** I used the lap sim as it stands today. The CFD session may change CP's aero numbers. If it does, rerun `make_lap_video`; the clock always shows the new `t_lap`.
- **Film 2 car marker.** It is the CAD top-view silhouette, drawn **enlarged** (7 % of the map span) and labelled "car marker enlarged". At true scale a 3 m car is a few pixels on a 500-1200 m map.
  - The silhouette is the outline of `media/views/formula_single_seater_Default_top.png`, taken column by column.
  - That file is git-ignored. If it is missing, the marker falls back to a dot.
- **Film 2 speed.** Both laps are real time: each MP4 is about 1 MB, far under 10 MB, so no speed-up was needed. The script would remake a film at 2x or 4x, with the caption saying so, if an MP4 came out over 10 MB.
- **Film 2 GIF.** "One GIF of the autocross" is the whole autocross lap in real time, 720x405 at 10 fps. The brief gave no size limit for it; it came out at 1 MB.
- **Lateral g sign.** It is shown as the lap sim gives it (`ay = v^2 * kappa`), so the sign gives the direction of the turn.
- **Lap clock.** It shows "lap clock" while the car moves. On the last 2.5 s it changes to "lap time", which is the lap sim's own `t_lap` to 0.01 s.

## Commands

```
python tools/sw_run.py showcase-build          # film 1: restart SolidWorks, stills, close all, assemble MP4 + GIF (about 80 s)
.venv/Scripts/python tools/showcase_build.py --selftest
```
In MATLAB, from `matlab/`:
```
make_lap_video               % film 2: both tracks (about 200 s)
make_lap_video('selftest')
```

## How each film is made

**Film 1: `car_buildup.mp4` / `.gif`**
- `tools/sw_harness/ShowcaseBuild.cs` is the new `ShowcaseBuild` step, dispatched in `Program.cs`. It opens the CP assembly and adds the ground plate.
- It hides everything, colours the parts for this session only, and fixes one three-quarter front perspective camera: azimuth 38°, elevation 18°, fitted once with everything visible.
- It then shows the components stage by stage. Frame tubes are shown by hiding and showing chassis bodies, with all 123 bodies matched to tubes.
- It saves one PNG per stage from the same camera, which is re-applied before every shot. That gives 30 stills, plus `manifest.csv`.
- Checks inside the step: ground top at z = 0, tyres on the ground, component counts per stage, and 123/123 chassis bodies matched.
- `tools/showcase_build.py` assembles the film:
  - crops every still to one 16:9 box;
  - holds each still for its stage's time and cross-fades over 4 frames (the pictures only, so captions never ghost);
  - captions each frame;
  - encodes with the ffmpeg inside `.venv` (imageio-ffmpeg): MP4 at 24 fps, CRF 20; GIF at 12 fps, 720x405, with a palette.
- `tools/sw_run.py showcase-build` chains these steps: restart SolidWorks, run the step, close all documents, assemble. That follows the GDI rules.

**Film 2: `lap_autocross.mp4`, `lap_fast_circuit.mp4`, `lap_autocross.gif`**
- `matlab/make_lap_video.m` runs `lapsim(car_from_params('CP'), load_track(track), struct('four_wheel', true))`.
- It integrates time from `s` and `v` (dt = 2 ds / (v_i + v_i+1), as lapsim does) and stops if that differs from `t_lap` by over 1 ms.
- It resamples the lap at 30 fps in real time and draws each frame in an invisible figure:
  - the track map coloured by simulated speed;
  - the car silhouette rotated to the path heading;
  - a lap clock;
  - traces of speed, lateral g and longitudinal g, each showing its live value.
- It writes the PNGs to `media/showcase/frames_lap/<track>/` and encodes them with the `.venv` ffmpeg (CRF 23).
- It writes `media/showcase/lap_video_report.txt`.
- Each frame carries the caption "Lap-time simulation, as-built car (CP). Rigid chassis, assumed tyre grip (mu 1.4). Not a physical test."
- The autocross is a standing start (v = 0 at the line), as in the lap sim. The fast circuit is a flying lap (closed track).

## Checks done

| Check | Result |
|---|---|
| `showcase_build.py --selftest` (crop box worked by hand: (144, 118, 255, 181)) | PASS |
| `make_lap_video('selftest')`: 100 m at 10 m/s = 10 s; rest to 2 m/s over 1 m = 1 s; silhouette of a 201 x 51 px block = 1 x 0.25 | PASS |
| Integrated lap time vs lapsim `t_lap`: autocross 62.1220 / 62.1220 s, fast circuit 83.0807 / 83.0807 s | equal |
| Last clock shown vs lap sim: autocross "62.12 s" (t_lap 62.1220 s; `media/lap_time_table.md` four-wheel CP 62.12 s); fast circuit "83.08 s" (83.0807 s; table 83.08 s) | equal |
| Every frame of all five files decoded: no blank or near-uniform frame (lowest pixel std 37 on any frame) | pass |
| Frame sheets (12 frames spread over each file) of all five files, checked by eye | captions correct, no broken frames |

Two bugs were found by eye and fixed:
- **Cross-fade ghosting (film 1).** Blending two captioned frames ghosted two captions together. The cross-fade now blends the pictures only and captions afterwards.
- **Blank last frames (fast circuit).** The final instant was interpolated a round-off past the data, which gave NaN, so the car and the values vanished. The frame times are now clamped to the data, and the script stops on any NaN.

Also forced: MATLAB's light theme for the lap figures. MATLAB R2026a followed the desktop's dark theme and gave grey-on-white titles.

## Files

| File | Length | Size | Under 10 MB |
|---|---|---|---|
| media/showcase/car_buildup.mp4 (1280x720, 24 fps) | 13.6 s | 0.37 MB | yes |
| media/showcase/car_buildup.gif (720x405, 12 fps) | 13.7 s | 0.36 MB | yes (under 5 MB too) |
| media/showcase/lap_autocross.mp4 (1280x720, 30 fps, real time) | 64.7 s (62.12 s lap + 2.5 s hold) | 1.04 MB | yes |
| media/showcase/lap_autocross.gif (720x405, 10 fps, real time) | 64.7 s | 0.98 MB | yes |
| media/showcase/lap_fast_circuit.mp4 (1280x720, 30 fps, real time) | 85.6 s (83.08 s lap + 2.5 s hold) | 0.98 MB | yes |

**New files:**
- tools/sw_harness/ShowcaseBuild.cs
- tools/showcase_build.py
- matlab/make_lap_video.m
- this note

**Edited files:**
- tools/sw_harness/Program.cs: one dispatch line.
- tools/sw_run.py: the `showcase-build` step.
- .gitignore: frame folders, showcase mp4/gif, and cad/showcase/.

## Seen, not changed

- **Rear wing (film 1).** In the as-built CAD the rear wing sits well above the rear of the car, with no visible mounts. That is what the CAD has: wing mounts are not modelled.
- **Fast circuit.** The car is at its top speed (about 148 km/h) for most of the lap, so most of the map shows the top of the colour scale. The colour range is set to each lap's own speeds to show what variation there is.
- **Longitudinal g.** The lap sim gives braking spikes down to about -3.5 g on the fast circuit (-34.6 m/s^2 at one sample). The film shows them as the sim gives them.
