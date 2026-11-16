function res = run_accel_simulink(variant)
%RUN_ACCEL_SIMULINK Build, run and compare the Simulink 6b model with accel_test.
%   res = run_accel_simulink()          variant C
%   res = run_accel_simulink('B')
%   run_accel_simulink('--selftest')    agreement within 1 % is the check
%
%   res.t_75_simulink, res.t_75_matlab, res.diff_pct, res.v_75_simulink
%   Needs Simulink; without it the function reports NaN and says so.

if nargin >= 1 && strcmp(variant, '--selftest')
    res = selftest();
    return
end
if nargin < 1 || isempty(variant), variant = 'C'; end
if isstruct(variant), car = variant; else, car = car_from_params(variant); end
res = struct('t_75_simulink', NaN, 't_75_matlab', NaN, 'diff_pct', NaN, 'v_75_simulink', NaN);
ref = accel_test(car, struct('plot', false));
res.t_75_matlab = ref.t_75;
if ~license('test', 'Simulink') || isempty(ver('simulink'))
    warning('run_accel_simulink:nosimulink', 'Simulink not available, skipping the 6b comparison');
    return
end
mdl = build_accel_model(car, 'accel_75m');
out = sim(mdl, 'ReturnWorkspaceOutputs', 'on');
t = out.tout; s = out.s_log; v = out.v_log;
% interpolate the exact 75 m crossing
i = find(s >= 75, 1);
if isempty(i)
    error('run_accel_simulink:short', 'Simulation stopped before 75 m');
end
res.t_75_simulink = interp1(s(i-1:i), t(i-1:i), 75);
res.v_75_simulink = interp1(s(i-1:i), v(i-1:i), 75);
res.diff_pct = 100 * (res.t_75_simulink / res.t_75_matlab - 1);
close_system(mdl, 0);
fprintf('run_accel_simulink variant %s: 75 m in %.3f s (Simulink) vs %.3f s (accel_test), difference %+.2f %%\n', ...
    car.variant, res.t_75_simulink, res.t_75_matlab, res.diff_pct);
end

function ok = selftest()
% Same hand-checkable car as accel_test's self-test (constant 7.279 m/s^2,
% t_75 = 4.540 s) must come out of Simulink within 0.5 %, and the real
% variant C must agree with accel_test within 1 %.
car = car_from_params('A');
car.ClA = 0; car.CdA = 0; car.crr = 0; car.lsens = 0; car.mu0 = 1.4; car.wd_front = 0.47;
car.P_max = 1e9; car.T_max = 1e9; car.F_torque_max = 1e9; car.v_rpm_max = 1e9; car.m = 300; car.g = 9.81;
r1 = run_accel_simulink(car);
tHand = sqrt(2 * 75 / (1.4 * 0.53 * 9.81));
r2 = run_accel_simulink('C');
ok = abs(r1.t_75_simulink - tHand) / tHand < 0.005 && abs(r2.diff_pct) < 1;
if ok
    fprintf('run_accel_simulink self-test: PASS (hand car %.3f s vs %.3f s; variant C Simulink vs MATLAB %+.2f %%)\n', r1.t_75_simulink, tHand, r2.diff_pct);
else
    error('run_accel_simulink self-test: FAIL (%.4f vs %.4f, diff %.2f %%)', r1.t_75_simulink, tHand, r2.diff_pct);
end
end
