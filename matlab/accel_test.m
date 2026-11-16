function res = accel_test(variant, opts)
%ACCEL_TEST Straight-line acceleration of the point-mass car (Ring 0 script).
%   res = accel_test()          variant C, plots speed vs time, prints 0-100 km/h
%   res = accel_test('A')       another aero variant
%   res = accel_test(car)       a car struct (see car_from_params)
%   accel_test('--selftest')    hand-checkable test
%
%   Integrates ds/dt = v, dv/dt = F_drive(v)/m with ode45, where F_drive comes
%   from long_forces (traction limit on the rear axle, power and torque caps,
%   drag and rolling resistance). Stops at the 75 m line of the FS
%   acceleration event. Reports:
%     res.t_100   0 to 100 km/h time (s)
%     res.t_75    75 m time (s) and res.v_75 the speed at the line
%     res.t, res.v, res.s   time history
%   This is the seed the lap simulator grew from; both use long_forces.

if nargin >= 1 && ischar(variant) && strcmp(variant, '--selftest')
    res = selftest();
    return
end
if nargin < 1 || isempty(variant), variant = 'C'; end
if isstruct(variant), car = variant; else, car = car_from_params(variant); end
if nargin < 2, opts = struct(); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 's_end'), opts.s_end = 75; end
if ~isfield(opts, 'v_target'), opts.v_target = 100 / 3.6; end

rhs = @(t, y) [y(2); long_forces(car, y(2), 0).F_drive / car.m];
% stop when s reaches s_end (event 1), record v_target crossing (event 2)
odeopts = odeset('Events', @(t, y) events(t, y, opts), 'RelTol', 1e-8, 'AbsTol', 1e-9, 'MaxStep', 0.01);
[t, y, te, ye, ie] = ode45(rhs, [0 60], [0; 0], odeopts);

res.car = car; res.t = t; res.s = y(:, 1); res.v = y(:, 2);
res.t_75 = NaN; res.v_75 = NaN; res.t_100 = NaN;
for k = 1:numel(ie)
    if ie(k) == 1, res.t_75 = te(k); res.v_75 = ye(k, 2); end
    if ie(k) == 2 && isnan(res.t_100), res.t_100 = te(k); end
end
if isnan(res.t_75)
    % s_end not reached inside 60 s (should not happen); interpolate anyway
    res.t_75 = interp1(res.s, res.t, opts.s_end);
    res.v_75 = interp1(res.s, res.v, opts.s_end);
end
f = long_forces(car, res.v, 0);
res.a = f.F_drive / car.m;

if opts.plot
    fig = figure('Name', 'accel_test');
    yyaxis left
    plot(t, res.v * 3.6, 'LineWidth', 1.5); ylabel('Speed (km/h)'); grid on
    yyaxis right
    plot(t, res.a / car.g, 'LineWidth', 1); ylabel('Acceleration (g)')
    xlabel('Time (s)')
    title(sprintf('Variant %s: 0-100 km/h %.2f s, 75 m in %.2f s (%.0f km/h at the line)', ...
        car.variant, res.t_100, res.t_75, res.v_75 * 3.6));
    save_fig(fig, ['accel_test_' car.variant]);
end
if nargout == 0 || opts.plot
    fprintf('accel_test variant %s: 0-100 km/h = %.3f s, 75 m = %.3f s, speed at 75 m = %.1f km/h\n', ...
        car.variant, res.t_100, res.t_75, res.v_75 * 3.6);
end
end

function [value, isterminal, direction] = events(~, y, opts)
value = [y(1) - opts.s_end; y(2) - opts.v_target];
isterminal = [1; 0];
direction = [1; 1];
end

function ok = selftest()
% Hand check. Remove everything but the traction limit: no aero, no drag,
% no rolling resistance, no load sensitivity, unlimited power and torque.
% The car then accelerates at a constant a = mu * (rear share) * g
%   a     = 1.4 * 0.53 * 9.81 = 7.279 m/s^2
%   t_100 = 27.778 / 7.279   = 3.816 s
%   t_75  = sqrt(2*75/7.279) = 4.539 s
car = car_from_params('A');
car.ClA = 0; car.CdA = 0; car.crr = 0; car.lsens = 0; car.mu0 = 1.4; car.wd_front = 0.47;
car.P_max = 1e9; car.F_torque_max = 1e9; car.v_rpm_max = 1e9; car.m = 300; car.g = 9.81;
r = accel_test(car, struct('plot', false));
a = 1.4 * 0.53 * 9.81;
t100 = (100 / 3.6) / a; t75 = sqrt(2 * 75 / a);
ok = abs(r.t_100 - t100) / t100 < 0.002 && abs(r.t_75 - t75) / t75 < 0.002;
if ok
    fprintf('accel_test self-test: PASS (t_100 = %.3f s vs hand %.3f s; t_75 = %.3f s vs hand %.3f s)\n', ...
        r.t_100, t100, r.t_75, t75);
else
    error('accel_test self-test: FAIL (t_100 %.4f vs %.4f, t_75 %.4f vs %.4f)', r.t_100, t100, r.t_75, t75);
end
end
