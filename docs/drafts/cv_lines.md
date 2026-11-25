# CV lines (draft)

**How I read the brief:**
- These are CV entries for this project, honest that everything is virtual: nothing was built or tested physically.
- They use only the numbers final in `docs/log.md` on 2026-11-25: 123 tubes, frame 46.26 kg, car 232.6 / 302.6 kg, 1476 / 1470 Nm/deg, safety factor 2.62, 26-step rebuild, 27/27 tests.
- There are no aero numbers, because the CFD session is still changing them.

## One line

Designed a Formula-Student-sized electric single-seater entirely in simulation (SolidWorks, MATLAB, Ansys Fluent): a scripted 26-step CAD rebuild from one parameter file, a 123-tube frame checked to 1476 Nm/deg by beam FE and 1470 Nm/deg by a solid model, and a lap-time simulation, all virtual, with no physical prototype.

## Three bullets

- Built a virtual Formula-style single-seater from one parameter file. A Python/C# harness drives SolidWorks through a 26-step scripted rebuild (frame weldment, suspension, bodywork, assembly), and every step checks its own result.
- Designed and analysed a 123-tube steel spaceframe (46.26 kg, car 232.6 kg without driver). Torsional stiffness is 1476 Nm/deg from a MATLAB beam FE model, confirmed at 1470 Nm/deg by a fused solid model in SolidWorks Simulation; the lowest factor of safety is 2.62 in the bump case. Nothing was built or physically tested.
- Ran half-car CFD in Ansys Fluent (via PyFluent) to rank wing packages and fed the results into a MATLAB lap-time simulation, with 27 of 27 self-tests passing. Results are used for comparing set-ups, not predicting real lap times.
