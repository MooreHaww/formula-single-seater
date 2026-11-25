# Release notes, v1.0.0 (draft)

**How I read the brief:**
- These are release notes for a first tagged release of this repository: what is in it, how to rebuild it with one command, and the known limits.
- Aero numbers are left as [FILL] (pending the CFD session).
- Only numbers final in `docs/log.md` on 2026-11-25 are used.
- No tag or GitHub release was created.

---

## Formula Single-Seater v1.0.0

A Formula-Student-sized electric single-seater, designed and tested entirely in simulation. Nothing has been built or physically tested.

### What is in this release

- **One parameter file**, `params/car_params.txt`. The CAD, the frame and suspension analysis, the aero tables and the lap-time simulation all read it.
- **Scripted CAD (SolidWorks)**: a Python launcher and a C# harness rebuild the car in 26 steps. They cover the frame weldment (123 tubes, every tube end trimmed and checked against its neighbours), the master layout, bodywork and wings, the suspension parts and assembly, a clearance check and a motion study, and the standard views. Each step writes a report and stops at the first failure.
- **Frame**:
  - 123 tubes, trimmed weldment 46.26 kg;
  - car 232.6 kg without the driver, 302.6 kg with;
  - torsional stiffness 1476 Nm/deg (MATLAB beam FE), cross-checked at 1470 Nm/deg on a fused solid model in SolidWorks Simulation;
  - lowest factor of safety on yield 2.62 (bump case, nominal beam stress).
- **Aero (Ansys Fluent, half car, driven by PyFluent)**: the wing packages, ranked. As built: ClA [FILL], CdA [FILL], front share [FILL]. Chosen variant: [FILL].
- **Lap-time simulation (MATLAB, Simulink cross-check)**: point-mass and four-wheel models, aero variants, following-car penalty, sensitivity, cornering balance. Lap times: [FILL].
- **Tests**: `run_all('test')`, 27 of 27 self-tests pass, each against a hand calculation where one exists.

### Rebuild in one command

Requirements: SolidWorks 2026 (Student is enough), Python 3, and the .NET SDK (the harness is compiled with its C# compiler). MATLAB R2026a is needed only to regenerate the frame CSVs and the analysis.

```
python tools/sw_run.py rebuild
```

After changing parameters, regenerate the MATLAB inputs first; the commands are in `README.md` under "Rebuild in one command".

### Known limits

- **Nothing physical.** No prototype, no torsion rig, no wind tunnel, no track. Every number is a model.
- **Tyres are assumed.** Friction and load sensitivity are placeholder values with no tyre data. All lap times and the cornering balance move with them.
- **Steady RANS on a Student mesh.** The CFD ranks the variants; the absolute ClA and CdA are not trustworthy.
- **Rigid chassis in the lap sim.** The frame's stiffness does not enter any lap time, only its mass.
- **Frame stiffness is under its own target** by decision. A diagonal at a joint too shallow to build cleanly was removed.
- **SolidWorks Simulation does not solve on the production weldment.** The beam studies are set up but report no result. Frame stress comes from the MATLAB beam model, and the only SolidWorks result is torsion on a separate fused-solid frame.
- **Frame material differs between models.** The CAD weldment is AISI 1020; the stress model and solid check use 4130.
- **Assumed suspension hardware.** The ball-joint housing size is assumed, and the rim clearance margin depends on it.
- **Placeholder masses.** Part of the mass budget (brackets and welds, inverter, wings, bodywork) is a guess.
