# 10 MATLAB first hour (60 min)

Goal: run the repo's self-tests, read one script and understand how it is built, change a parameter and see the effect, and write a script of your own with a hand-checked answer. MATLAB R2026a with Simulink; nothing else is needed.

## 1. The desktop (10 min)

Start MATLAB. Four areas:

| Area | What |
|---|---|
| **Command Window** | type a line, Enter, it runs. `>>` is the prompt. Up arrow recalls history. |
| **Current Folder** | the folder MATLAB is working in; scripts here run by name. Use the address bar at the top to go to the repo. |
| **Workspace** | the variables that exist right now; double-click one to open it in the Variables editor. |
| **Editor** | opens when you open a `.m` file; Run (F5), Run Section (Ctrl+Enter), breakpoints by clicking the dash next to a line number. |

Set the current folder to the repo: type in the Command Window

```matlab
cd('C:\Users\<you>\Desktop\OnWorkPro\formula-single-seater')
```

(or use the folder icon). `pwd` prints it. `ls` or `dir` lists it. Tab completes paths and names.

## 2. Run the self-tests (5 min)

```matlab
run('matlab/run_all.m')
```

Wait: that runs everything (about one minute, 17 self-tests then every analysis, figures into `media/`). To run only the tests:

```matlab
addpath('matlab')
s = run_all('test');
```

Expected: 17 lines ending in PASS and `-- Self-tests: 17 / 17 passed --`. `s` is a **struct** in the Workspace; `s.tests` is an array of structs with fields `name`, `pass`, `msg`. Try:

```matlab
s.tests(4)            % the fourth test
{s.tests.name}'       % every name as a column cell array
[s.tests.pass]        % 1 for pass
```

## 3. Read one script (15 min)

Open `matlab/accel_test.m` (double-click in Current Folder, or `edit accel_test`). Read it top to bottom with these questions:

- The first line `function r = accel_test(car, opts)`: inputs on the right, output on the left. The comment block right under it is the **help**: `help accel_test` prints it.
- `if nargin >= 1 && ...'--selftest'` near the top: every script in this repo runs its own check when called with that string. Scroll to the bottom: `function ok = selftest()` is the check, with the hand calculation in the comment. That pattern (a hand-computable case, compared with a tolerance) is the one to copy.
- `car = car_from_params('C')` builds the car from the parameter file; `long_forces(car, v, Fy)` gives the drive and brake force at speed `v`. Open those two files too (Ctrl+D on the name in the Editor jumps to it, **verify** the shortcut in R2026a, or right-click > Open).
- Find the time stepping loop: `while` or `for` with `v = v + a * dt`. That is the whole model.

Put a **breakpoint** on the first line inside the loop (click the dash by the line number), then in the Command Window:

```matlab
r = accel_test('C');
```

The Editor stops at the line with a green arrow. Hover over `v`, `a`, `F` to see their values; press **Continue** (F5) a few times and watch `v` grow; **Step** (F10) runs one line. Clear the breakpoint (click it again) and Continue to let it finish. `r` is a struct: `r.t_100`, `r.t_75`.

## 4. Change a parameter and see the effect (10 min)

Open `params/car_params.txt` in the MATLAB Editor (it opens text files too). Find `"motor_power_max"= 80000`. Change it to `60000`. Save. Then

```matlab
r = accel_test('C'); r.t_75
```

The 75 m time rises (from 4.14 s to 4.26 s; the first 40 m are traction-limited, so power only matters at the end). Change it back to 80000, save, run again: 4.14 s. That is the loop you will use through Ring 6: edit the file, run one script, read one number. No rebuild step; MATLAB reads the file every call.

Look at how the file is read: `edit read_car_params` (in `matlab/common/`). The `regexp` line pulls `"name"= value` apart; the loop under it evaluates expressions like `"mass_car"= "m_frame" + ...` by substituting known names. You do not need to understand regular expressions today; note that the file format is shared with SolidWorks (exercise 5) and never put anything in it that both cannot read.

## 5. Write your own script (20 min)

Make a file `matlab/practice/skidpad_speed.m` (create the folder) with this content, typed by hand, not pasted, so the Editor's auto-indent and the red underlines (the Code Analyzer) are seen once:

```matlab
function v = skidpad_speed(mu, R)
%SKIDPAD_SPEED Steady cornering speed of a point mass without aero.
%   v = skidpad_speed(mu, R) in m/s, from  m v^2 / R = mu m g  ->  v = sqrt(mu g R)
%   skidpad_speed('--selftest') checks the FS skidpad: mu 1.4, R 9.125 -> 11.195 m/s
if nargin >= 1 && ischar(mu) && strcmp(mu, '--selftest')
    v = selftest();
    return
end
g = 9.81;
v = sqrt(mu * g * R);
end

function ok = selftest()
% hand value: sqrt(1.4 * 9.81 * 9.125) = sqrt(125.32) = 11.195 m/s
v = skidpad_speed(1.4, 9.125);
ok = abs(v - 11.195) < 0.001;
if ok
    fprintf('skidpad_speed self-test: PASS (%.3f m/s)\n', v);
else
    error('skidpad_speed self-test: FAIL (%.4f)', v);
end
end
```

Run it:

```matlab
addpath('matlab/practice')
skidpad_speed('--selftest')
skidpad_speed(1.4, 9.125) * 3.6      % km/h
```

Expected: `PASS (11.195 m/s)` and 40.30 km/h. Compare with the repo's lap simulator, which does the same thing with aero and load sensitivity switched off in its own self-test (`lapsim('--selftest')` prints `skidpad 5.122 s`; 2 pi x 9.125 / 11.195 = 5.121 s, the same number from a different route).

Then one plot:

```matlab
R = 5:1:50;
figure; plot(R, skidpad_speed(1.4, R) * 3.6, 'LineWidth', 1.5); grid on
xlabel('corner radius (m)'); ylabel('speed (km/h)'); title('Point mass, mu = 1.4, no aero')
```

`skidpad_speed(1.4, R)` works on the whole vector `R` at once because `sqrt` and `*` are element-wise here; that is the MATLAB habit to pick up early: loops are for time stepping, not for arrays. Compare the curve with `media/cornering_speed_vs_downforce.png` (variant A is close to this line; it also has a top-speed cap and the tyre load sensitivity).

## Expected result

17 of 17 self-tests pass; you have stepped through `accel_test` under the debugger; a parameter change moved the 75 m time and was reverted; `matlab/practice/skidpad_speed.m` exists, passes its self-test and plots.

## Check

- `run_all('test')` still reports 17 / 17 (you changed the parameter file back).
- `git status` shows only `matlab/practice/skidpad_speed.m` as new (and `media/` files if you ran the full `run_all`).

## Three things people trip on

- **Path**: a function is found only if its folder is on the path (`addpath`) or is the current folder. `run_all` adds the repo's folders itself (`setup_paths.m`); your own practice folder needs `addpath` once per session, or `savepath` (not recommended) or a `startup.m`.
- **Script vs function**: a file starting with `function` has its own workspace; a plain script shares the Command Window's. Everything in this repo is a function so that nothing leaks.
- **Semicolons**: a line without `;` prints its result. Deliberate at the prompt, noise inside a function.
