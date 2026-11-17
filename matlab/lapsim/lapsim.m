function res = lapsim(car, track, opts)
%LAPSIM Quasi-steady point-mass lap time simulation (Ring 6a core).
%   res = lapsim(car, track)        car from car_from_params, track from load_track
%   res = lapsim(car, track, opts)  opts.ds (m, default 0.5), opts.v0 (m/s,
%                                   open tracks only, default 0), opts.verbose,
%                                   opts.four_wheel (false): corner speed limit
%                                   from cornering_balance.m (four wheel loads,
%                                   load transfer, limiting axle) instead of
%                                   the point-mass m v^2 k <= mu(Fz) Fz;
%                                   opts.aero_front ('car'): front aero share,
%                                   'car' = the car struct's value, 'target' =
%                                   aero_balance_target from car_params.txt,
%                                   or a number
%   lapsim('--selftest')
%
%   Method
%     1. The track is a list of straights and constant-radius arcs, sampled
%        every ds metres into a curvature profile kappa(s).
%     2. Corner speed limit at every sample: the largest v with
%            m v^2 |kappa|  <=  mu(Fz) * Fz,   Fz = m g + 0.5 rho ClA v^2
%        capped by the power/drag top speed.
%     3. Forward pass from the start: accelerate with the longitudinal grip
%        left after the lateral demand (friction ellipse), the power cap and
%        the torque cap, minus drag and rolling resistance (long_forces).
%     4. Backward pass from the end: brake with all four wheels' remaining grip
%        plus drag. The speed profile is the minimum of the two passes.
%     5. Closed tracks are flying laps: the forward pass is repeated with the
%        previous lap's final speed as the start speed until it converges.
%   Time is summed with dt = 2 ds / (v_i + v_i+1), exact for constant
%   acceleration within a step.
%
%   Output fields: t_lap (s), s, v, v_corner, ax, ay (m/s^2), x, y (track
%   centreline), v_top (m/s), v_mean, v_max, track, car, energy_J (tractive).

if ischar(car) && strcmp(car, '--selftest')
    res = selftest();
    return
end
if nargin < 3, opts = struct(); end
if ~isfield(opts, 'ds'), opts.ds = 0.5; end
if ~isfield(opts, 'v0'), opts.v0 = 0; end
if ~isfield(opts, 'verbose'), opts.verbose = false; end
if ~isfield(opts, 'four_wheel'), opts.four_wheel = false; end
if ~isfield(opts, 'aero_front'), opts.aero_front = 'car'; end
if ischar(opts.aero_front) || isstring(opts.aero_front)
    switch char(opts.aero_front)
        case 'car'      % the car struct's own value (variant table or parameter file)
        case 'target'   % aero_balance_target from the parameter file
            if ~isfield(car, 'aero_front_target') || isnan(car.aero_front_target)
                error('lapsim:noTarget', 'opts.aero_front = ''target'' needs car.aero_front_target (aero_balance_target in car_params.txt)');
            end
            car.aero_front = car.aero_front_target;
        otherwise
            error('lapsim:aeroFront', 'opts.aero_front must be ''car'', ''target'' or a number');
    end
else
    car.aero_front = opts.aero_front;
end

% ---- sample the track -------------------------------------------------------
[s, kappa, x, y] = sample_track(track, opts.ds);
n = numel(s);
ds = diff(s);

% ---- corner speed limit -----------------------------------------------------
v_top = top_speed(car);
v_corner = v_top * ones(n, 1);
ak = abs(kappa);
% every distinct curvature is solved once (tracks are piecewise constant)
[ku, ~, ik] = unique(ak);
vk = v_top * ones(size(ku));
for j = find(ku > 1e-9).'
    if opts.four_wheel
        vk(j) = cornering_balance(car, 1 / ku(j), struct('v_top', v_top)).v_max;
    else
        vk(j) = corner_speed(car, ku(j), v_top);
    end
end
v_corner = vk(ik);

% ---- forward / backward passes ------------------------------------------------
if track.closed
    v_start = v_corner(1);
else
    v_start = min(opts.v0, v_corner(1));
end
v = v_corner;
for iter = 1:6
    v = forward_pass(car, v_corner, ak, ds, v_start, n);
    v = backward_pass(car, v, ak, ds, n);
    if ~track.closed, break, end
    if abs(v(end) - v_start) < 1e-3, break, end
    v_start = min(v(end), v_corner(1));
end
if track.closed
    % enforce exact periodicity for reporting
    v(1) = min(v(1), v(end)); v(end) = v(1);
end

% ---- outputs ------------------------------------------------------------------
vm = (v(1:end-1) + v(2:end)) / 2;
dt = ds ./ max(vm, 1e-3);
res.t_lap = sum(dt);
res.t = [0; cumsum(dt)];
res.s = s; res.v = v; res.v_corner = v_corner; res.kappa = kappa;
res.ax = [diff(v.^2) ./ (2 * ds); 0];
res.ay = v.^2 .* kappa;
res.x = x; res.y = y;
res.v_top = v_top; res.v_mean = s(end) / res.t_lap; res.v_max = max(v);
res.track = track; res.car = car; res.four_wheel = opts.four_wheel;
% tractive energy: positive longitudinal force times distance
fdrv = max(0, res.ax(1:end-1) * car.m + long_forces(car, vm, 0).F_drag + long_forces(car, vm, 0).F_rr);
res.energy_J = sum(fdrv .* ds);
if opts.verbose
    fprintf('lapsim %-14s variant %s: %.3f s, mean %.1f km/h, max %.1f km/h\n', ...
        track.name, car.variant, res.t_lap, res.v_mean * 3.6, res.v_max * 3.6);
end
end

% =============================================================================
function v = forward_pass(car, v_corner, ak, ds, v_start, n)
v = v_corner;
v(1) = min(v_start, v_corner(1));
for i = 1:n-1
    Fy = car.m * v(i)^2 * ak(i);
    f = long_forces(car, v(i), Fy);
    ax = f.F_drive / car.m;
    v(i+1) = min(v_corner(i+1), sqrt(max(0, v(i)^2 + 2 * ax * ds(i))));
end
end

function v = backward_pass(car, v, ak, ds, n)
for i = n-1:-1:1
    Fy = car.m * v(i+1)^2 * ak(i+1);
    f = long_forces(car, v(i+1), Fy);
    ax = f.F_brake / car.m;
    v(i) = min(v(i), sqrt(v(i+1)^2 + 2 * ax * ds(i)));
end
end

function v = corner_speed(car, k, v_top)
% largest v with m v^2 k <= mu(Fz) Fz, by bisection on g(v) = Fmax - m v^2 k
g = @(vv) long_forces(car, vv, 0).Fmax - car.m * vv.^2 * k;
if g(v_top) >= 0
    v = v_top; return
end
lo = 0; hi = v_top;
for it = 1:60
    mid = (lo + hi) / 2;
    if g(mid) >= 0, lo = mid; else, hi = mid; end
    if hi - lo < 1e-6, break, end
end
v = lo;
end

function v = top_speed(car)
% largest v with F_drive(v) >= 0 (power, torque, rpm, drag, rolling)
g = @(vv) long_forces(car, vv, 0).F_drive;
hi = min(car.v_rpm_max, 150);
if g(hi) >= 0, v = hi; return, end
lo = 0;
for it = 1:60
    mid = (lo + hi) / 2;
    if g(mid) >= 0, lo = mid; else, hi = mid; end
    if hi - lo < 1e-6, break, end
end
v = lo;
end

function [s, kappa, x, y] = sample_track(track, ds)
% segments: length_m, radius_m (0 = straight, +left, -right)
L = track.length_m(:); R = track.radius_m(:);
total = sum(L);
n = max(2, round(total / ds) + 1);
s = linspace(0, total, n).';
segEnd = cumsum(L);
segStart = [0; segEnd(1:end-1)];
kappa = zeros(n, 1);
for j = 1:numel(L)
    idx = s >= segStart(j) - 1e-9 & s < segEnd(j) - 1e-9;
    if R(j) ~= 0, kappa(idx) = 1 / R(j); end
end
% last node takes the last segment's curvature
if R(end) ~= 0, kappa(end) = 1 / R(end); end
% centreline geometry by integrating heading
dsv = diff(s);
psi = [0; cumsum(kappa(1:end-1) .* dsv)];
x = [0; cumsum(cos(psi(1:end-1)) .* dsv)];
y = [0; cumsum(sin(psi(1:end-1)) .* dsv)];
end

% =============================================================================
function ok = selftest()
% Hand checks on a car with no aero, no drag, no rolling resistance, no load
% sensitivity, mu = 1.4, unlimited power, m = 300 kg, rear share 0.53:
%  (1) Skidpad, R = 9.125 m (FS centreline), flying lap:
%        v   = sqrt(mu g R) = sqrt(1.4*9.81*9.125) = 11.195 m/s
%        lap = 2*pi*R / v   = 57.334 / 11.195    = 5.121 s
%  (2) 75 m acceleration from rest: a = 1.4*0.53*9.81 = 7.279 m/s^2
%        t = sqrt(2*75/a) = 4.539 s
%  (3) A 100 m straight then the skidpad circle: entry speed into the circle
%      must equal the circle speed (backward pass brakes for it).
car = car_from_params('A', [], 'params');   % hand car: start from the parameter-file guesses, not the variant table
car.ClA = 0; car.CdA = 0; car.crr = 0; car.lsens = 0; car.mu0 = 1.4; car.wd_front = 0.47;
car.P_max = 1e9; car.F_torque_max = 1e9; car.v_rpm_max = 1e9; car.m = 300; car.g = 9.81;
R = 9.125; mu = 1.4; g = 9.81;
tr = struct('name', 'skidpad_test', 'closed', true, 'length_m', 2 * pi * R, 'radius_m', R);
r1 = lapsim(car, tr, struct('ds', 0.25));
lapHand = 2 * pi * R / sqrt(mu * g * R);
e1 = abs(r1.t_lap - lapHand) / lapHand;

tr2 = struct('name', 'accel_test', 'closed', false, 'length_m', 75, 'radius_m', 0);
r2 = lapsim(car, tr2, struct('ds', 0.25));
a = mu * 0.53 * g; tHand = sqrt(2 * 75 / a);
e2 = abs(r2.t_lap - tHand) / tHand;

tr3 = struct('name', 'straight_then_circle', 'closed', false, 'length_m', [100; 2 * pi * R], 'radius_m', [0; R]);
r3 = lapsim(car, tr3, struct('ds', 0.25));
iCircle = find(r3.s >= 100, 1);
e3 = abs(r3.v(iCircle) - sqrt(mu * g * R)) / sqrt(mu * g * R);
ok = e1 < 0.005 && e2 < 0.005 && e3 < 0.01 && max(r3.v) > r3.v(iCircle);
%  (4) opts.aero_front: 'target' must give exactly the lap of a car whose
%      aero_front was set to aero_balance_target by hand, and a number must
%      override the car's value (traction-limited 75 m with downforce: more
%      rear aero share = more rear grip = a shorter time).
c4 = car_from_params('C'); c4.aero_front = 0.45;
c5 = c4; c5.aero_front = c4.aero_front_target;
tT = lapsim(c4, tr2, struct('aero_front', 'target')).t_lap; tH = lapsim(c5, tr2).t_lap;
tRear = lapsim(c4, tr2, struct('aero_front', 0.30)).t_lap; tFront = lapsim(c4, tr2, struct('aero_front', 0.60)).t_lap;
ok = ok && abs(tT - tH) < 1e-12 && tRear < tFront;
if ok
    fprintf('lapsim self-test: PASS (skidpad %.3f s vs hand %.3f s; 75 m %.3f s vs hand %.3f s; circle entry %.2f m/s vs %.2f)\n', ...
        r1.t_lap, lapHand, r2.t_lap, tHand, r3.v(iCircle), sqrt(mu * g * R));
else
    error('lapsim self-test: FAIL (errors %.4f %.4f %.4f)', e1, e2, e3);
end
end
