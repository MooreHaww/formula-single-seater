function out = cornering_balance(car, R, opts)
%CORNERING_BALANCE Four-wheel steady-state cornering limit with load transfer.
%   out = cornering_balance(car, R)        car from car_from_params, R in m
%   out = cornering_balance(car, R, opts)  opts.v_top (m/s, power cap; computed
%                                          from long_forces if absent)
%   cornering_balance('--selftest')
%
%   What it adds to the point-mass lap sim: the vertical load on each of the
%   four wheels in a steady corner, the tyre's falling grip per newton as its
%   load rises, and therefore which axle runs out of grip first.
%
%   Lateral load transfer per axle (Milliken, "Race Car Vehicle Dynamics"
%   ch. 18), car turning at ay = v^2 / R:
%     dFz_f = [ ms ay (h_s - h_ra) kf  +  ms_f ay h_rc_f  +  mu_f ay h_u ] / t_f
%     dFz_r = [ ms ay (h_s - h_ra) (1-kf) + ms_r ay h_rc_r + mu_r ay h_u ] / t_r
%   with ms the sprung mass, h_s its CG height, h_ra the roll-axis height
%   under the sprung CG (interpolated between the front and rear roll-centre
%   heights), kf the front share of the total roll stiffness, ms_f / ms_r the
%   sprung mass carried by each axle, mu_f / mu_r the unsprung mass per axle
%   at wheel-centre height h_u. The three terms are the roll-stiffness
%   (spring) part, the geometric (roll-centre) part and the unsprung part.
%   Downforce 0.5 rho ClA v^2 is added per axle by aero_front; it adds load
%   but no lateral transfer (the aero force itself is vertical).
%
%   Wheel loads: outer = axle/2 + dFz, inner = axle/2 - dFz; an inner wheel
%   cannot go below zero (lift), the outer then carries the whole axle.
%   Tyre: mu(Fz) = mu0 (fz_ref / Fz)^lsens, so a tyre's lateral capacity is
%   mu0 fz_ref^lsens Fz^(1-lsens) and an axle's capacity is the sum of its
%   two tyres. Transferring load between them always loses capacity.
%   Demand per axle in a steady turn (no yaw moment): front wd_front m ay,
%   rear (1 - wd_front) m ay. The corner limit is the largest v where both
%   axles still meet their demand; the axle at 100 % use is the limiting one.
%   Front first = understeer at the limit, rear first = oversteer.
%   balance_pct = 100 (use_f - use_r) at the reported speed: positive means
%   the front axle is working harder.
%
%   Roll stiffness split: with no anti-roll bar in the parameter file the
%   split comes from the ride-frequency springs alone,
%     K_axle = k_wheel t^2 / 2,  k_wheel = (2 pi f_ride)^2 m_sprung_corner.
%   Override with car.roll_stiff_front. Roll-centre heights default to
%   car.h_rc_f / car.h_rc_r (set by the study script from suspension_geometry;
%   fallback 0.06 / 0.069 m, the static values from that script).
%
%   ASSUMPTIONS the results depend on (none are measured yet):
%     tyre_mu_peak 1.4, tyre_fz_ref 750 N, tyre_load_sensitivity 0.10 (file)
%     no anti-roll bars, no tyre vertical stiffness in the roll split
%     roll-centre heights static (no migration with roll)
%     cg_height from the mass budget (most lines ESTIMATE / GUESS)
%     aero_balance_front 0.45 (no CFD yet)
%     no camber, no slip-angle model, no tyre temperature, no driver
%
%   Output fields: v_grip (m/s, grip limit alone), v_top (power/drag cap),
%   v_max = min of the two, power_limited, lat_g, Fz (1x4 N: FO FI RO RI at
%   v_max), dFz_f, dFz_r, use_f, use_r, balance_pct, limiting_axle,
%   inner_lift, v_point_mass (the old single-track answer for comparison),
%   geo (derived geometry: ms, h_s, h_ra, kf, ...).

if ischar(car) && strcmp(car, '--selftest')
    out = selftest();
    return
end
if nargin < 3, opts = struct(); end
car = fill_defaults(car);
geo = geometry(car);

if isfield(opts, 'v_top')
    v_top = opts.v_top;
else
    v_top = top_speed(car);
end

% grip-only limit: largest v with both axles below 100 % use, bisection
vHi = 150;
if margin(car, geo, vHi, R) >= 0
    v_grip = vHi;
else
    lo = 0; hi = vHi;
    for it = 1:60
        mid = (lo + hi) / 2;
        if margin(car, geo, mid, R) >= 0, lo = mid; else, hi = mid; end
        if hi - lo < 1e-7, break, end
    end
    v_grip = lo;
end
v_max = min(v_grip, v_top);
[~, w] = margin(car, geo, v_max, R);

out.v_grip = v_grip; out.v_top = v_top; out.v_max = v_max;
out.power_limited = v_top < v_grip;
out.lat_g = v_max^2 / R / car.g;
out.Fz = w.Fz; out.dFz_f = w.dFz_f; out.dFz_r = w.dFz_r;
out.Fy_req = w.Fy_req; out.Fy_max = w.Fy_max;
out.use_f = w.use(1); out.use_r = w.use(2);
out.balance_pct = 100 * (w.use(1) - w.use(2));
if w.use(1) >= w.use(2), out.limiting_axle = "front"; else, out.limiting_axle = "rear"; end
out.inner_lift = w.inner_lift;
out.v_point_mass = min(point_mass_speed(car, R), v_top);
out.geo = geo;
end

% ------------------------------------------------------------------------
function car = fill_defaults(car)
if ~isfield(car, 'h_rc_f'), car.h_rc_f = 0.060; end     % ASSUMPTION: suspension_geometry static result
if ~isfield(car, 'h_rc_r'), car.h_rc_r = 0.069; end
if ~isfield(car, 'm_unsprung_f'), car.m_unsprung_f = 22.2; end   % two corners, file value
if ~isfield(car, 'm_unsprung_r'), car.m_unsprung_r = 22.2; end
if ~isfield(car, 'h_unsprung'), car.h_unsprung = car.r_wheel; end
if ~isfield(car, 'roll_stiff_front')
    if isfield(car, 'ride_freq_f') && isfield(car, 'ride_freq_r')
        msf = car.wd_front * car.m / 2 - car.m_unsprung_f / 2;
        msr = (1 - car.wd_front) * car.m / 2 - car.m_unsprung_r / 2;
        Kf = (2 * pi * car.ride_freq_f)^2 * msf * car.track_f^2 / 2;
        Kr = (2 * pi * car.ride_freq_r)^2 * msr * car.track_r^2 / 2;
        car.roll_stiff_front = Kf / (Kf + Kr);
    else
        car.roll_stiff_front = 0.5;
    end
end
end

function geo = geometry(car)
g = car.g; m = car.m; L = car.L;
geo.mu_f = car.m_unsprung_f; geo.mu_r = car.m_unsprung_r; geo.h_u = car.h_unsprung;
geo.ms = m - geo.mu_f - geo.mu_r;
geo.h_s = (m * car.h_cg - (geo.mu_f + geo.mu_r) * geo.h_u) / geo.ms;
geo.Wf = car.wd_front * m * g; geo.Wr = (1 - car.wd_front) * m * g;
geo.ms_f = geo.Wf / g - geo.mu_f; geo.ms_r = geo.Wr / g - geo.mu_r;
geo.a_s = geo.ms_r / geo.ms * L;                       % sprung CG from the front axle
geo.h_rc_f = car.h_rc_f; geo.h_rc_r = car.h_rc_r;
geo.h_ra = geo.h_rc_f + (geo.h_rc_r - geo.h_rc_f) * geo.a_s / L;
geo.h_roll = geo.h_s - geo.h_ra;
geo.kf = car.roll_stiff_front;
end

function w = wheel_loads(car, geo, v, R)
ay = v^2 / R;
DF = 0.5 * car.rho * car.ClA * v^2;
DFf = car.aero_front * DF; DFr = DF - DFf;
w.dFz_f = (geo.ms * ay * geo.h_roll * geo.kf + geo.ms_f * ay * geo.h_rc_f + geo.mu_f * ay * geo.h_u) / car.track_f;
w.dFz_r = (geo.ms * ay * geo.h_roll * (1 - geo.kf) + geo.ms_r * ay * geo.h_rc_r + geo.mu_r * ay * geo.h_u) / car.track_r;
Ff = geo.Wf + DFf; Fr = geo.Wr + DFr;
Fz = [Ff / 2 + w.dFz_f, Ff / 2 - w.dFz_f, Fr / 2 + w.dFz_r, Fr / 2 - w.dFz_r];   % FO FI RO RI
w.inner_lift = any(Fz([2 4]) < 0);
if Fz(2) < 0, Fz(1) = Ff; Fz(2) = 0; end
if Fz(4) < 0, Fz(3) = Fr; Fz(4) = 0; end
w.Fz = Fz; w.ay = ay;
w.Fy_max = [tyre_capacity(car, Fz(1)) + tyre_capacity(car, Fz(2)), tyre_capacity(car, Fz(3)) + tyre_capacity(car, Fz(4))];
w.Fy_req = [car.wd_front, 1 - car.wd_front] * car.m * ay;
w.use = w.Fy_req ./ max(w.Fy_max, 1e-9);
end

function Fy = tyre_capacity(car, Fz)
% mu(Fz) Fz = mu0 fz_ref^lsens Fz^(1 - lsens), zero at zero load
Fy = car.mu0 * car.fz_ref^car.lsens * max(Fz, 0)^(1 - car.lsens);
end

function [mg, w] = margin(car, geo, v, R)
w = wheel_loads(car, geo, v, R);
mg = 1 - max(w.use);
end

function v = top_speed(car)
g = @(vv) long_forces(car, vv, 0).F_drive;
hi = min(car.v_rpm_max, 150); lo = 0;
if g(hi) >= 0, v = hi; return, end
for it = 1:60, mid = (lo + hi) / 2; if g(mid) >= 0, lo = mid; else, hi = mid; end, end
v = lo;
end

function v = point_mass_speed(car, R)
% the lap sim's single-track limit: mu at the average wheel load Fz/4
h = @(vv) long_forces(car, vv, 0).Fmax - car.m * vv.^2 / R;
lo = 0; hi = 150;
if h(hi) >= 0, v = hi; return, end
for it = 1:60, mid = (lo + hi) / 2; if h(mid) >= 0, lo = mid; else, hi = mid; end, end
v = lo;
end

% ------------------------------------------------------------------------
function ok = selftest()
% (1) Symmetric car: m = 300 kg, 50 % front, h_cg 0.3 m, tracks 1.2 m, roll
%     centres 0.05 m both ends, 10 kg unsprung per axle at 0.25 m, roll
%     stiffness split 0.5, no aero, no load sensitivity, mu = 1.4, R = 50 m.
%     With equal tracks and equal roll-centre heights the three transfer terms
%     add back up to the rigid-body value m ay h / t:
%       v  = sqrt(1.4 * 9.81 * 50) = 26.207 m/s,  ay = 13.734 m/s^2
%       dFz per axle = 0.5 * 300 * 13.734 * 0.3 / 1.2 = 515.0 N, same both ends
%       the four loads sum to m g = 2943 N (transfer sums to zero)
%       both axles at 100 % use: neutral, balance 0
% (2) Tyre capacity with load sensitivity 0.10, ref 750 N, mu0 1.4:
%       wheels at 1000 N and 500 N: 1.4 * 750^0.1 * (1000^0.9 + 500^0.9) = 2089.3 N
%       (less than the 2100 N of two wheels at 750 N)
% (3) Same car with load sensitivity 0.10: the limit speed must drop below
%     26.207 m/s, and with the roll stiffness moved to the front (0.7) the
%     front axle must limit (understeer, balance > 0).
car = car_from_params('A');
car.ClA = 0; car.CdA = 0; car.crr = 0; car.lsens = 0; car.mu0 = 1.4; car.fz_ref = 750;
car.m = 300; car.g = 9.81; car.wd_front = 0.5; car.h_cg = 0.3; car.track_f = 1.2; car.track_r = 1.2; car.L = 1.55;
car.h_rc_f = 0.05; car.h_rc_r = 0.05; car.m_unsprung_f = 10; car.m_unsprung_r = 10; car.h_unsprung = 0.25;
car.roll_stiff_front = 0.5; car.P_max = 1e9; car.F_torque_max = 1e9; car.v_rpm_max = 1e9;
o1 = cornering_balance(car, 50, struct('v_top', 1e9));
vHand = sqrt(1.4 * 9.81 * 50);
dHand = 0.5 * 300 * (vHand^2 / 50) * 0.3 / 1.2;
ok = abs(o1.v_grip - vHand) < 1e-3 ...
    && abs(o1.dFz_f - dHand) < 0.05 && abs(o1.dFz_r - dHand) < 0.05 ...
    && abs(sum(o1.Fz) - 300 * 9.81) < 1e-6 ...
    && abs((o1.Fz(1) - o1.Fz(2)) - 2 * dHand) < 0.1 && abs((o1.Fz(3) - o1.Fz(4)) - 2 * dHand) < 0.1 ...
    && abs(o1.balance_pct) < 1e-6 && ~o1.inner_lift;
car2 = car; car2.lsens = 0.10;
capHand = 1.4 * 750^0.1 * (1000^0.9 + 500^0.9);
cap = tyre_capacity(car2, 1000) + tyre_capacity(car2, 500);
ok = ok && abs(cap - capHand) < 1e-6 && abs(capHand - 2089.3) < 0.1;
o2 = cornering_balance(car2, 50, struct('v_top', 1e9));
car3 = car2; car3.roll_stiff_front = 0.7;
o3 = cornering_balance(car3, 50, struct('v_top', 1e9));
ok = ok && o2.v_grip < vHand - 0.05 && abs(o2.balance_pct) < 1e-6 ...
    && o3.balance_pct > 0 && o3.limiting_axle == "front" && o3.v_grip < o2.v_grip;
if ok
    fprintf('cornering_balance self-test: PASS (symmetric: v %.3f m/s, dFz %.1f N both axles, loads sum %.1f N; tyre pair %.1f N; with load sensitivity %.3f m/s, front-stiff balance %+.1f %%)\n', ...
        o1.v_grip, o1.dFz_f, sum(o1.Fz), cap, o2.v_grip, o3.balance_pct);
else
    error('cornering_balance self-test: FAIL (v %.4f vs %.4f, dFz %.2f/%.2f vs %.2f, sum %.2f, cap %.2f, v2 %.3f, bal3 %.2f)', ...
        o1.v_grip, vHand, o1.dFz_f, o1.dFz_r, dHand, sum(o1.Fz), cap, o2.v_grip, o3.balance_pct);
end
end
