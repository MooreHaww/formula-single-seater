# LinkedIn post (draft)

**How I read the brief:**
- A post of about 150 words plus 5 hashtags.
- Blanks marked [FILL] for the aero numbers (pending the CFD session) and for the chosen car/variant.
- Only the numbers final in `docs/log.md` on 2026-11-25 are used, and it says plainly that the car is virtual.

---

I designed a Formula-style single-seater without building a single part, and that is the point of this project.

Everything starts from one parameter file. A scripted harness rebuilds the whole car in SolidWorks in 26 steps (frame, suspension, bodywork, assembly), and every step checks its own result.

The 123-tube steel frame weighs 46.26 kg, and the car is 232.6 kg without the driver (302.6 kg with). A MATLAB beam model gives 1476 Nm/deg of torsional stiffness, and a fused solid model in SolidWorks Simulation agrees at 1470. The lowest factor of safety, in the bump case, is 2.62.

Aero: half-car CFD in Ansys Fluent ranked the wing packages. The chosen car is [FILL: chosen variant], with ClA [FILL] and CdA [FILL]. A MATLAB lap-time simulation turns that into lap times. 27 of 27 self-tests pass.

What it is not: tested. No prototype, no wind tunnel, no track. Every number is a model, and I've written down where each one could be wrong.

#FormulaStudent #SolidWorks #CFD #MATLAB #MechanicalEngineering
