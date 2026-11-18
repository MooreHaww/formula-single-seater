function out = suspension_optimise(opts, varargin)
%SUSPENSION_OPTIMISE Move the hardpoints so the outer joints fit in the rim.
%   out = suspension_optimise()          optimise front and rear, print, no write
%   out = suspension_optimise(opts)      opts.write (false): write the result to
%                                        params through suspension_geometry;
%                                        opts.p: parameter struct; opts.rim_d:
%                                        rim diameter to try (mm, default params);
%                                        opts.starts.front / .rear: extra start
%                                        points (15 x n moves, see apply())
%   suspension_optimise('--selftest')
%
%   The rim is a hard limit. Every outer joint (lower and upper ball joint,
%   tie-rod or toe-link end, pushrod end) that sits inside the rim along the
%   spindle must keep its centre + JOINT_R (params joint_housing_radius,
%   12.5 mm: Aurora COM-5T spherical bearing, 19.05 mm OD, in a 3 mm wall
%   cup) at least joint_rim_margin_min (3 mm) inside the barrel's inner radius
%   rim_d/2 - 11 (build_parts.build_rim: barrel 7 mm below the bead seat,
%   4 mm wall). The joints are fixed to the upright, so their radius does
%   not change with travel or steering; the links do move relative to the
%   wheel, so every link is sampled along its length in the upright's frame
%   at full droop, static and full bump, and at the front also at full
%   steering lock each way (rack moved until the wheel reaches
%   steer_max_wheel_angle, tie-rod length held): a link's surface must keep 3 mm from the rim (barrel and flange) and
%   10 mm from the tyre sidewall (the 25 mm bodywork rule covers tread
%   growth and camber; next to the bead 10 mm covers the sidewall's
%   deflection in cornering).
%
%   Kept close to the current design (targets = values before the run):
%   camber gain, bump steer (under 0.1 deg over +/-30 mm), static roll
%   centre height, motion ratio, the roll-centre movement; at the front also
%   caster (within about 1 deg) and kingpin inclination (about 2 deg), which
%   set the steering feel; kingpin inclination 3..9 deg, caster 3..7 deg
%   (front), scrub radius 0..20 mm.
%
%   Moved: the outer joints (x, y, z), the tie-rod / toe-link ends, the
%   pushrod's outer end height, and the inner pivots of each wishbone by a
%   common z and y shift (they are frame nodes in matlab/cad/frame_layout.m,
%   which follow them), limited to +/-30 mm in z and +/-15 mm in y (rear:
%   +/-30 mm in y, and the cross tubes at the inner pivots at least 10 mm
%   from the diff envelope, checked in absolute terms).
%   Method: Nelder-Mead (fminsearch, no toolbox needed) on a penalty
%   function, from several starts; hardpoints rounded to 0.5 mm and checked
%   again after rounding.

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin >= 1 && ischar(opts) && strcmp(opts, '--package')
    % suspension_optimise('--package', h, corner, p): the rim/tyre check alone
    out = package_report(varargin{1}, varargin{2}, varargin{3});
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'write'), opts.write = false; end
if ~isfield(opts, 'verbose'), opts.verbose = true; end
if isfield(opts, 'p'), p = opts.p; else, p = read_car_params(); end
if isfield(opts, 'rim_d'), p.rim_diameter = opts.rim_d; end
% near-locked linkages in the trial points raise singular-matrix warnings
% in the Newton solve; the solve reports its own failure, so they are noise
w0 = warning; cleanup = onCleanup(@() warning(w0));
warning('off', 'MATLAB:singularMatrix'); warning('off', 'MATLAB:nearlySingularMatrix');
warning('off', 'MATLAB:illConditionedMatrix'); warning('off', 'MATLAB:polyfit:PolyNotUnique');

base = suspension_geometry(struct('p', p, 'plot', false, 'travel', -30:5:30));
hp0 = base.hardpoints;
out = struct();
out.p = p;
hp = hp0;
for c = {'front', 'rear'}
    cn = c{1};
    tgt = targets_from(base.(cn));
    if strcmp(cn, 'front')
        pk0 = package_report(hp0.front, 'front', p);
        tgt.lock_rack = pk0.lock_rack;
    end
    if isfield(opts, 'starts') && isfield(opts.starts, cn), x0 = opts.starts.(cn); else, x0 = []; end
    [h, res] = optimise_corner(hp0.(cn), cn, tgt, p, opts.verbose, x0);
    hp.(cn) = h;
    out.(cn) = res;
    out.(cn).before = package_report(hp0.(cn), cn, p);
end
out.hardpoints = hp;
out.base = base;
if opts.verbose, print_summary(out); end
if opts.write
    if ~(out.front.feasible && out.rear.feasible)
        error('suspension_optimise:infeasible', 'Not written: no solution keeps the joints in the rim and the targets.');
    end
    suspension_geometry(struct('p', p, 'hp', hp, 'plot', false, 'write', true));
end
end

% =============================================================================
function t = targets_from(r)
t.camber_gain = r.camber_gain;
t.rc = r.rc_static;
t.rc_span = diff(r.rc_range);
t.mr = r.motion_ratio;
t.caster = r.caster;
t.kpi = r.kpi;
end

function [hBest, res] = optimise_corner(h0, cn, tgt, p, verbose, x0)
nv = 15;
fun = @(x) cost(x, h0, cn, tgt, p);
starts = zeros(nv, 1);
% second start: drop the upper joint into the rim and the toe-link end towards
% the axle, the obvious move
s2 = zeros(nv, 1); s2(3) = -20; s2(7) = -sign(h0.tie_out(1) - h0.wheel_centre(1)) * 30;
starts = [starts, s2];
if strcmp(cn, 'front')
    % third start from a scan of the lock clearance (2026-11-17): both ball
    % joints further inboard and the upper one lower keep the legs off the
    % tyre at full lock
    s3 = zeros(nv, 1); s3(1:3) = [0 -25 -30]; s3(4:6) = [-10 -35 0]; s3(7:8) = [0 -30];
    starts = [starts, s3];
end
% extra starts given by the caller (opts.starts.<corner>, a 15 x n matrix of
% moves, e.g. the result of an earlier run to refine it)
starts = [starts, x0];
fo = optimset('MaxFunEvals', 6000, 'MaxIter', 6000, 'TolX', 0.05, 'TolFun', 1e-6, 'Display', 'off');
best = inf; xb = zeros(nv, 1);
for k = 1:size(starts, 2)
    x = starts(:, k);
    for pass = 1:3                     % restarts shake Nelder-Mead out of flat spots
        [x, f] = fminsearch(fun, x, fo);
    end
    if verbose, fprintf('  %s start %d: cost %.4g\n', cn, k, f); end
    if f < best, best = f; xb = x; end
end
xb = round(xb * 2) / 2;                % 0.5 mm
hBest = apply(xb, h0);
[f, m] = cost(xb, h0, cn, tgt, p);
m.pkg = package_report(hBest, cn, p);          % full check, with steering to lock
res = m;
res.cost = f;
res.x = xb;
res.target = tgt;
res.feasible = m.pkg.ok && m.bump_steer <= 0.1 && m.scrub <= 30 && abs(m.camber_gain - tgt.camber_gain) <= 0.005 && ...
    abs(m.rc - tgt.rc) <= 10 && abs(m.mr - tgt.mr) <= 0.03;
if isfield(m, 'diff_clear'), res.feasible = res.feasible && m.diff_clear >= 10; end
end

function h = apply(x, h0)
% x (mm): 1-3 uwb_out xyz, 4-6 lwb_out xyz, 7-9 tie_out xyz, 10 tie_in z,
% 11 uwb inner z, 12 uwb inner y, 13 lwb inner z, 14 lwb inner y, 15 pushrod_out z
h = h0;
h.uwb_out = h0.uwb_out + x(1:3).';
h.lwb_out = h0.lwb_out + x(4:6).';
h.tie_out = h0.tie_out + x(7:9).';
h.tie_in = h0.tie_in + [0, 0, x(10)];
h.uwb_in_fwd = h0.uwb_in_fwd + [0, x(12), x(11)];
h.uwb_in_aft = h0.uwb_in_aft + [0, x(12), x(11)];
h.lwb_in_fwd = h0.lwb_in_fwd + [0, x(14), x(13)];
h.lwb_in_aft = h0.lwb_in_aft + [0, x(14), x(13)];
h.pushrod_out = h0.pushrod_out + [0, 0, x(15)];
end

function [f, m] = cost(x, h0, cn, tgt, p)
% limits on the moves
lim = [60 40 60, 60 40 60, 60 40 60, 30, 30 15 30 15, 40].';
lo = -lim; hi = lim;
if strcmp(cn, 'rear')
    % the rear inner pivots carry the RS1/RS2 cross tubes past the diff: their
    % clearance is a penalty below (diff_clearance), in absolute terms. A move
    % limit relative to the current hardpoints drifted on each re-run (2026-11-18).
    % with the upper pivots held up, the camber gain comes from the arm
    % lengths: the inner pivots may move up to 30 mm across (frame_layout
    % checks the tubes against the batteries and the diff afterwards)
    lo([12 14]) = -30; hi([12 14]) = 30;
end
f = 1e3 * sum(max(0, lo - x).^2 + max(0, x - hi).^2);
h = apply(x, h0);
hp.(cn) = h;
try
    o = suspension_geometry(struct('p', p, 'hp', hp, 'corners', {{cn}}, 'plot', false, 'travel', -30:5:30));
    r = o.(cn);
catch
    f = f + 1e6; m = struct('pkg', struct('ok', false), 'bump_steer', inf, 'camber_gain', nan, 'rc', nan, 'mr', nan);
    return
end
m.camber_gain = r.camber_gain; m.bump_steer = r.bump_steer; m.rc = r.rc_static;
m.rc_span = diff(r.rc_range); m.mr = r.motion_ratio; m.kpi = r.kpi; m.caster = r.caster;
m.scrub = r.scrub_radius; m.trail = r.trail;
f = f + ((m.camber_gain - tgt.camber_gain) / 0.002)^2 ...
      + (m.bump_steer / 0.05)^2 + (max(0, m.bump_steer - 0.1) / 0.01)^2 ...
      + ((m.rc - tgt.rc) / 4)^2 + ((m.rc_span - tgt.rc_span) / 25)^2 ...
      + ((m.mr - tgt.mr) / 0.01)^2 ...
      + band(m.kpi, 3, 10, 0.5) + band(m.scrub, 0, 25, 2) ...
      + 1e-4 * sum(x.^2);                        % smallest move that does the job
% steering feel (front only, the rear does not steer): keep caster and kingpin
% inclination near where they were
if strcmp(cn, 'front')
    f = f + ((m.caster - tgt.caster) / 1)^2 + ((m.kpi - tgt.kpi) / 2)^2 + band(m.caster, 3, 7, 0.5);
else
    f = f + band(m.caster, 0, 7, 0.5) + band(m.kpi, 3, 10, 0.5) + band(m.trail, -10, 25, 2);
    m.diff_clear = diff_clearance(h, p);
    f = f + 1e2 * max(0, 11 - m.diff_clear)^2;       % frame_layout wants 10 mm; 1 mm extra
end
m.pkg = package_report(h, cn, p, r, 7);       % full lock found to about 0.3 mm of rack
f = f + 1e2 * sum(max(0, m.pkg.viol + 1).^2);     % 1 mm extra margin while optimising
f = f + (max(0, m.pkg.tyre_short) / 3)^2;           % tyre goal, soft
if strcmp(cn, 'front') && isfield(tgt, 'lock_rack') && isfield(m.pkg, 'lock_rack')
    if isempty(m.pkg.lock_rack), f = f + 100; else, f = f + ((m.pkg.lock_rack - tgt.lock_rack) / 2)^2; end   % same steering ratio
    % outer wheel between full Ackermann and parallel steer at full lock
    if isnan(m.pkg.outer_angle), f = f + 100; else, f = f + band(m.pkg.outer_angle, ackermann_outer(p), p.steer_max_wheel_angle, 1); end
end
end

function d = diff_clearance(h, p)
% Surface distance from the rear frame cross tubes at the four inner pivots
% (straight across in y, so they pass the diff over its full width) to the
% diff envelope of frame_layout: a cylinder along y at (wheelbase,
% tyre_rolling_radius), radius 80. Tube OD tube_secondary_od.
pts = [h.uwb_in_fwd; h.uwb_in_aft; h.lwb_in_fwd; h.lwb_in_aft];
d = min(hypot(pts(:, 1) - p.wheelbase, pts(:, 3) - p.tyre_rolling_radius)) - 80 - p.tube_secondary_od / 2;
end

function v = band(x, lo, hi, s)
v = (max(0, lo - x) / s)^2 + (max(0, x - hi) / s)^2;
end

% =============================================================================
function pk = package_report(h, cn, p, r, steer)
% Joint and link clearance against the wheel, in the upright's frame.
% steer: 0 no steering, otherwise the number of bisection steps used to find
% the rack position at full lock (20 for the final check, fewer in the loop).
JOINT_R = 12; JOINT_GAP = 0;          % fallbacks; params: joint_housing_radius, joint_rim_margin_min
if isfield(p, 'joint_housing_radius'), JOINT_R = p.joint_housing_radius; end
if isfield(p, 'joint_rim_margin_min'), JOINT_GAP = p.joint_rim_margin_min; end
LINK_R = 15.9 / 2;
RIM_GAP = 3;                          % hard: link surface to the rim (rigid, both metal)
TYRE_MIN = 3;                         % hard: link surface to the tyre, no contact
TYRE_GOAL = 10;                       % goal: room for the sidewall's deflection in cornering
rIn = p.rim_diameter / 2 - 11;        % barrel inner radius
rBead = p.rim_diameter / 2;           % bead seat
halfW = p.rim_width / 2;
halfT = p.tyre_width / 2;
rTyre = p.tyre_od / 2;
if nargin < 5, steer = 20; end
if nargin < 4 || isempty(r)
    hp.(cn) = h;
    o = suspension_geometry(struct('p', p, 'hp', hp, 'corners', {{cn}}, 'plot', false, 'travel', -30:5:30));
    r = o.(cn);
end
names = {'lwb_out', 'uwb_out', 'tie_out', 'pushrod_out'};
pk.joint_r = zeros(1, 4); pk.joint_ax = zeros(1, 4); pk.joint_margin = nan(1, 4);
viol = [];
% static frame
[e, wc] = frame_of(r.P(:, :, r.travel == 0));
for k = 1:4
    d = h.(names{k}) - wc;
    ax = d * e(:, 1);
    rad = sqrt(max(0, d * d.' - ax^2));
    pk.joint_r(k) = rad; pk.joint_ax(k) = ax;
    if ax >= -halfW - JOINT_R && ax <= halfW
        pk.joint_margin(k) = rIn - (rad + JOINT_R);
        viol(end + 1) = JOINT_GAP - pk.joint_margin(k); %#ok<AGROW>
    end
end
pk.joint_names = names;
% links over travel (and rack travel at the front)
poses = {};
it = find(ismember(r.travel, [-30 0 30]));
for i = it(:).'
    poses{end + 1} = struct('P', r.P(:, :, i), 'tie_in', h.tie_in); %#ok<AGROW>
end
if strcmp(cn, 'front') && steer
    % steering: the rack stops where the INNER wheel reaches the full lock
    % (steer_max_wheel_angle). This is the right wheel, so it is the inner
    % wheel in a right turn, when it toes out (toe < 0). The same rack the
    % other way makes it the outer wheel, at whatever angle the linkage gives
    % (less than the inner with Ackermann, more with anti-Ackermann).
    L0 = norm(h.tie_out - h.tie_in);
    try
        o5 = solve_rack(h, p, L0, 5);
        sgnIn = -sign(o5.front.toe(2));        % rack direction that toes this wheel out
    catch
        sgnIn = 1;
    end
    rlock = abs(rack_to_lock(h, p, sgnIn, steer));
    if isnan(rlock)
        viol(end + 1) = 50;                     % the linkage locks up before full lock
        rlock = [];
    end
    pk.lock_rack = rlock; pk.lock_toe = [nan nan]; pk.outer_angle = nan;
    for sgn = [-1 1]
        if isempty(rlock), break, end
        try
            os = solve_rack(h, p, norm(h.tie_out - h.tie_in), sgn * rlock);
        catch
            viol(end + 1) = 50; continue %#ok<AGROW>
        end
        for i = 1:3
            poses{end + 1} = struct('P', os.front.P(:, :, i), 'tie_in', h.tie_in + [0, sgn * rlock, 0]); %#ok<AGROW>
        end
        pk.lock_toe(1 + (sgn > 0)) = os.front.toe(2);
        if sgn == -sgnIn, pk.outer_angle = abs(os.front.toe(2)); end
    end
end
worst = -inf;
pk.link_names = {'lwb_fwd', 'lwb_aft', 'uwb_fwd', 'uwb_aft', 'tie', 'pushrod'};
pk.link_by = -inf(1, 6);           % worst per link over all poses (hard limits)
pk.tyre_short = -inf;              % how far the closest link is inside the tyre goal
pk.link_pose = zeros(1, 6);        % which pose: 1-3 droop/static/bump, 4-6 lock one way, 7-9 the other
for k = 1:numel(poses)
    P = poses{k}.P;
    [e, wc] = frame_of(P);
    links = {P(1, :), h.lwb_in_fwd; P(1, :), h.lwb_in_aft; P(2, :), h.uwb_in_fwd; P(2, :), h.uwb_in_aft; ...
             P(3, :), poses{k}.tie_in; P(4, :), h.pushrod_in};
    for j = 1:size(links, 1)
        a = links{j, 1}; b = links{j, 2};
        L = norm(b - a);
        for s = (JOINT_R:5:min(L, 250)) / L          % past the joint housing
            q = a + s * (b - a) - wc;
            ax = q * e(:, 1);
            rad = sqrt(max(0, q * q.' - ax^2));
            % the wheel in (along-spindle, radius): rim = barrel and flange,
            % tyre = the section between bead and tread
            dRim = rect_dist(ax, rad, [-halfW, halfW], [rIn, rBead]) - LINK_R;
            dTyre = rect_dist(ax, rad, [-halfT, halfT], [rBead, rTyre]) - LINK_R;
            v = max(RIM_GAP - dRim, TYRE_MIN - dTyre);
            pk.tyre_short = max(pk.tyre_short, TYRE_GOAL - dTyre);
            worst = max(worst, v);
            if v > pk.link_by(j), pk.link_by(j) = v; pk.link_pose(j) = k; end
        end
    end
end
pk.link_worst = worst;                  % > 0 = a link closer to the wheel than the hard gaps allow
pk.tyre_gap = TYRE_GOAL - pk.tyre_short;  % closest link surface to the tyre, mm
if worst > -inf, viol(end + 1) = worst; end
pk.viol = viol;
pk.ok = all(viol <= 0);
jm = pk.joint_margin(~isnan(pk.joint_margin));
pk.joint_viol_max = max([-inf, JOINT_GAP - jm]);       % > 0: a joint closer to the barrel than joint_rim_margin_min
pk.joint_gap = JOINT_GAP;
pk.rIn = rIn; pk.JOINT_R = JOINT_R;
end

function a = ackermann_outer(p)
% Outer wheel angle for full Ackermann when the inner wheel is at full lock.
a = acotd(cotd(p.steer_max_wheel_angle) + p.track_front / p.wheelbase);
end

function d = rect_dist(x, y, xr, yr)
% Signed distance from (x, y) to the rectangle xr x yr (negative inside).
dx = max([xr(1) - x, 0, x - xr(2)]);
dy = max([yr(1) - y, 0, y - yr(2)]);
if dx == 0 && dy == 0
    d = -min([x - xr(1), xr(2) - x, y - yr(1), yr(2) - y]);
else
    d = hypot(dx, dy);
end
end

function rack = rack_to_lock(h, p, sgn, nit)
% Rack displacement (sign sgn) at which the wheel reaches steer_max_wheel_angle
% at static height, by bisection, capped at steer_rack_travel; returns the
% solved poses at travel -30, 0, +30 for that rack position.
L = norm(h.tie_out - h.tie_in);
lo = 0; hi = p.steer_rack_travel;
try
    oh = solve_rack(h, p, L, sgn * hi);
    if abs(oh.front.toe(2)) <= p.steer_max_wheel_angle
        rack = sgn * hi; return
    end
    for k = 1:nit
        mid = (lo + hi) / 2;
        om = solve_rack(h, p, L, sgn * mid);
        if abs(om.front.toe(2)) > p.steer_max_wheel_angle, hi = mid; else, lo = mid; end
    end
    rack = sgn * lo;
catch
    rack = nan;
end
end

function o = solve_rack(h, p, L, rk)
h.tie_in = h.tie_in + [0, rk, 0];
h.tie_len = L;
o = suspension_geometry(struct('p', p, 'hp', struct('front', h), 'corners', {{'front'}}, ...
    'plot', false, 'travel', [-30 0 30]));
end

function [e, wc] = frame_of(P)
% upright frame from the pose rows: 5 wheel centre, 7 axle point, 8 forward point
wc = P(5, :);
a = P(7, :) - wc; a = a / norm(a);
f = P(8, :) - wc; f = f - (f * a.') * a; f = f / norm(f);
e = [a.', f.', cross(a, f).'];
end

% =============================================================================
function print_summary(out)
fprintf('\nsuspension_optimise: rim %g mm, barrel inner radius %.0f mm, joint housing %d mm\n', ...
    out.p.rim_diameter, out.front.pkg.rIn, out.front.pkg.JOINT_R);
for c = {'front', 'rear'}
    cn = c{1}; r = out.(cn); b = out.base.(cn); t = r.target;
    fprintf('%s: %s\n', cn, ternary(r.feasible, 'FEASIBLE', 'NOT FEASIBLE'));
    fprintf('  camber gain %.4f (was %.4f) deg/mm, bump steer %.3f (was %.3f) deg, RC %.1f (was %.1f) mm, RC span %.0f (was %.0f) mm, MR %.3f (was %.3f)\n', ...
        r.camber_gain, t.camber_gain, r.bump_steer, b.bump_steer, r.rc, t.rc, r.rc_span, t.rc_span, r.mr, t.mr);
    fprintf('  KPI %.1f (was %.1f) deg, caster %.1f (was %.1f) deg, scrub %.1f (was %.1f) mm, trail %.1f (was %.1f) mm\n', ...
        r.kpi, b.kpi, r.caster, b.caster, r.scrub, b.scrub_radius, r.trail, b.trail);
    for k = 1:4
        fprintf('  %-12s radius %6.1f (was %6.1f) mm, along spindle %6.1f mm, margin %s\n', r.pkg.joint_names{k}, ...
            r.pkg.joint_r(k), r.before.joint_r(k), r.pkg.joint_ax(k), num2str(r.pkg.joint_margin(k), '%.1f'));
    end
    fprintf('  links: worst %.1f mm (<= 0 clears; was %.1f)\n', r.pkg.link_worst, r.before.link_worst);
    fprintf('  closest link to the tyre: %.1f mm (goal 10, hard limit 3)\n', r.pkg.tyre_gap);
    if isfield(r.pkg, 'lock_rack')
        fprintf(['  steering: inner wheel at %g deg with rack +/-%.1f mm, outer wheel then %.1f deg ' ...
            '(full Ackermann %.1f, parallel %g; was %.1f); rack travel in the params +/-%g mm\n'], ...
            out.p.steer_max_wheel_angle, r.pkg.lock_rack, r.pkg.outer_angle, ackermann_outer(out.p), ...
            out.p.steer_max_wheel_angle, r.before.outer_angle, out.p.steer_rack_travel);
    end
    fprintf('  moves (mm): %s\n', mat2str(r.x.', 4));
end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

% =============================================================================
function ok = selftest()
% Hand-checkable: a joint 100 mm above the wheel centre on a level axle has
% radius 100, so with a 12 mm housing (no margin) it fits a 254 mm rim (barrel 116) with
% 4 mm to spare and fails a 230 mm rim (barrel 104) by 8 mm. And the rear
% upper joint of the 2026-11-16 design (radius 140 > 104, the violation that
% started this) must be flagged in the real corner, so the check is not vacuous.
p = read_car_params();
o = suspension_geometry(struct('p', p, 'plot', false, 'travel', -30:5:30));
h = o.hardpoints.rear;
wc = h.wheel_centre;
h.static_camber = 0;
h.uwb_out = [wc(1), wc(2) - 40, wc(3) + 100];
P = repmat(wc, 8, 1); P(7, :) = wc + [0 100 0]; P(8, :) = wc + [-100 0 0];
r = struct('travel', 0, 'P', P);
ok = true;
p0 = p; p.joint_housing_radius = 12; p.joint_rim_margin_min = 0;    % the hand cases below use a 12 mm housing, no margin
pk = package_report(h, 'rear', p, r);
ok = ok && check(abs(pk.joint_r(2) - 100) < 1e-9 && abs(pk.joint_margin(2) - 4) < 1e-9, ...
    sprintf('joint 100 mm above the axle: radius %.3f (100), margin %.3f (4) in a 254 rim', pk.joint_r(2), pk.joint_margin(2)));
p2 = p; p2.rim_diameter = 230;
pk2 = package_report(h, 'rear', p2, r);
ok = ok && check(abs(pk2.joint_margin(2) + 8) < 1e-9, sprintf('same joint in a 230 rim: margin %.3f (-8)', pk2.joint_margin(2)));
% the housing rule: 12.5 mm housing and 3 mm wanted. Radius 100 leaves 116 - 112.5 = 3.5 (passes),
% radius 101 leaves 2.5 (flagged although the housing still fits)
p5 = p; p5.joint_housing_radius = 12.5; p5.joint_rim_margin_min = 3;
pk5 = package_report(h, 'rear', p5, r);
h6 = h; h6.uwb_out = [wc(1), wc(2) - 40, wc(3) + 101];
pk6 = package_report(h6, 'rear', p5, r);
ok = ok && check(abs(pk5.joint_margin(2) - 3.5) < 1e-9 && pk5.joint_gap - pk5.joint_margin(2) <= 0 && ...
    abs(pk6.joint_margin(2) - 2.5) < 1e-9 && pk6.joint_gap - pk6.joint_margin(2) > 0, ...
    sprintf('housing 12.5 mm, 3 mm wanted: radius 100 margin %.2f (3.5, ok), radius 101 margin %.2f (2.5, flagged)', pk5.joint_margin(2), pk6.joint_margin(2)));
p = p0;
h3 = o.hardpoints.rear;
h3.uwb_out = [1565, 522, 360];                % 2026-11-16 rear upper ball joint
pk3 = package_report(h3, 'rear', p);
ok = ok && check(~pk3.ok && pk3.joint_r(2) > 130, sprintf('2026-11-16 rear upper joint flagged: radius %.1f, ok = %d', pk3.joint_r(2), pk3.ok));
pk4 = package_report(o.hardpoints.rear, 'rear', p);
ok = ok && check(pk4.ok, sprintf('rear hardpoints in the params fit the rim: worst link %.1f mm, joint margins %s', pk4.link_worst, mat2str(pk4.joint_margin, 3)));
x = zeros(15, 1); x(1:3) = [1 2 3]; x(11) = 5;
ha = apply(x, o.hardpoints.front);
ok = ok && check(isequal(ha.uwb_out - o.hardpoints.front.uwb_out, [1 2 3]) && ...
    ha.uwb_in_fwd(3) - o.hardpoints.front.uwb_in_fwd(3) == 5, 'design variables move the named points');
if ok
    fprintf('suspension_optimise self-test: PASS\n');
else
    error('suspension_optimise:selftest', 'suspension_optimise self-test: FAIL');
end
end

function ok = check(c, msg)
ok = c;
if c, fprintf('  ok   %s\n', msg); else, fprintf('  FAIL %s\n', msg); end
end
