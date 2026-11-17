function out = suspension_geometry(opts)
%SUSPENSION_GEOMETRY Double-wishbone kinematics from hardpoints (pre-CAD).
%   out = suspension_geometry()            front and rear from params, plots, prints
%   out = suspension_geometry(opts)        opts.plot (true), opts.write (false):
%                                          write = true rewrites the hardpoint block
%                                          in params/car_params.txt and
%                                          params/suspension_hardpoints.txt
%   suspension_geometry('--selftest')
%
%   Frame: car coordinates of the master layout, x rearward from the front
%   axle, y to the right, z up from the ground, mm. Right-hand corner;
%   mirror in y for the left.
%
%   Method: the upright is a rigid body carrying the two ball joints, the
%   tie-rod (toe-link) outer point, the pushrod outer point, the wheel centre
%   and the contact patch. For each wheel travel step the six-DOF pose is
%   solved by Newton iteration so that the four wishbone legs and the tie rod
%   keep their lengths and the wheel centre sits at the demanded height.
%   From the poses: camber, toe (bump steer), half-track change, pushrod
%   travel (motion ratio = pushrod travel / wheel travel x rocker ratio),
%   and from the front-view instant centres the roll centre height.
%   Static geometry: kingpin inclination, caster, scrub radius, trail.
%
%   Targets (FS practice, see docs/cad_playbook/03_wishbones.md):
%     camber gain       -0.03 to -0.06 deg/mm (top of wheel inward in bump)
%     bump steer        under 0.1 deg over +/-30 mm
%     roll centre       front 30 to 60 mm, rear 50 to 90 mm, moving little
%     motion ratio      0.7 to 1.0 with a 1:1 rocker
%     scrub radius      0 to 20 mm, caster 3 to 7 deg, KPI 4 to 9 deg

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'write'), opts.write = false; end
if ~isfield(opts, 'travel'), opts.travel = -30:1:30; end
if isfield(opts, 'p'), p = opts.p; else, p = read_car_params(); end
% opts.hp: hardpoints to use instead of the ones in the params (suspension_optimise.m);
% opts.corners: subset of {'front', 'rear'}
if isfield(opts, 'hp'), hp = opts.hp; else, hp = hardpoints_from_params(p); end
if ~isfield(opts, 'corners'), opts.corners = {'front', 'rear'}; end
out = struct();
for c = opts.corners
    corner = c{1};
    out.(corner) = sweep_corner(hp.(corner), opts.travel, p);
    if opts.plot
        plot_corner(out.(corner), corner, hp.(corner));
    end
end
out.hardpoints = hp;
if opts.plot
    print_report(out);
end
if opts.write
    write_hardpoints(hp, out);
end
end

% =============================================================================
function hp = hardpoints_from_params(p)
% Pull the hardpoints out of the parameter struct into f.<name> = [x y z].
hp.front = struct();
hp.rear = struct();
names = {'lwb_in_fwd', 'lwb_in_aft', 'lwb_out', 'uwb_in_fwd', 'uwb_in_aft', 'uwb_out', ...
    'pushrod_out', 'pushrod_in'};
for k = 1:numel(names)
    hp.front.(names{k}) = [p.(['f_' names{k} '_x']), p.(['f_' names{k} '_y']), p.(['f_' names{k} '_z'])];
    hp.rear.(names{k})  = [p.(['r_' names{k} '_x']), p.(['r_' names{k} '_y']), p.(['r_' names{k} '_z'])];
end
hp.front.tie_in  = [p.f_tierod_in_x,  p.f_tierod_in_y,  p.f_tierod_in_z];
hp.front.tie_out = [p.f_tierod_out_x, p.f_tierod_out_y, p.f_tierod_out_z];
hp.rear.tie_in   = [p.r_toelink_in_x, p.r_toelink_in_y, p.r_toelink_in_z];
hp.rear.tie_out  = [p.r_toelink_out_x, p.r_toelink_out_y, p.r_toelink_out_z];
hp.front.wheel_centre = [0, p.track_front / 2, p.tyre_rolling_radius];
hp.rear.wheel_centre  = [p.wheelbase, p.track_rear / 2, p.tyre_rolling_radius];
hp.front.static_camber = p.static_camber_front;
hp.rear.static_camber  = p.static_camber_rear;
hp.front.rocker_ratio = p.rocker_ratio_front;
hp.rear.rocker_ratio  = p.rocker_ratio_rear;
end

function r = sweep_corner(h, travel, p)
% Upright body points at the design position (travel = 0)
wc0 = h.wheel_centre;
cp0 = [wc0(1), wc0(2), 0];
% wheel axle direction, outward; a wheel leaning top-in (negative camber)
% has its axle pointing up, so negative camber means positive z here
axis0 = [0, cosd(h.static_camber), -sind(h.static_camber)];
fwd0  = [-1, 0, 0];                                            % forward (x is rearward)
P0 = [h.lwb_out; h.uwb_out; h.tie_out; h.pushrod_out; wc0; cp0; wc0 + 100 * axis0; wc0 + 100 * fwd0];
ref = h.lwb_out;
Lfix = [norm(h.lwb_out - h.lwb_in_fwd); norm(h.lwb_out - h.lwb_in_aft); ...
        norm(h.uwb_out - h.uwb_in_fwd); norm(h.uwb_out - h.uwb_in_aft); ...
        norm(h.tie_out - h.tie_in)];
% h.tie_len: tie-rod length to hold when tie_in has been moved by the rack
% (steering, suspension_optimise.m); otherwise the length at the design position
if isfield(h, 'tie_len'), Lfix(5) = h.tie_len; end
n = numel(travel);
q = zeros(6, 1);                % [translation; rotation vector] of the upright
camber = zeros(n, 1); toe = camber; dy = camber; pushrod = camber; rc_h = camber; wcz = camber;
P = zeros(size(P0, 1), 3, n);
for i = 1:n
    zt = wc0(3) + travel(i);
    % Newton on the 6 constraints
    for it = 1:50
        [F, J] = constraints(q, P0, ref, h, Lfix, zt);
        if norm(F) < 1e-9, break, end
        q = q - J \ F;
    end
    if norm(F) > 1e-6
        error('suspension_geometry:solve', 'No solution at travel %g mm (residual %.2e)', travel(i), norm(F));
    end
    Pi = pose(q, P0, ref);
    P(:, :, i) = Pi;
    ax = Pi(7, :) - Pi(5, :); fw = Pi(8, :) - Pi(5, :);
    camber(i) = -atand(ax(3) / ax(2));             % negative = top inward (right wheel)
    toe(i) = atand(fw(2) / fw(1));                 % positive = toe-in
    dy(i) = Pi(6, 2) - cp0(2);                     % contact patch half-track change
    pushrod(i) = norm(Pi(4, :) - h.pushrod_in) - norm(h.pushrod_out - h.pushrod_in);
    wcz(i) = Pi(5, 3);
    rc_h(i) = roll_centre_height(h, Pi);
end
r.travel = travel(:); r.camber = camber; r.toe = toe; r.half_track_change = dy;
r.pushrod_travel = pushrod; r.roll_centre_h = rc_h; r.P = P;
r.motion_ratio = abs(polyfit(travel(:), pushrod, 1) * [1; 0]) * h.rocker_ratio;
pc = polyfit(travel(:), camber, 1); r.camber_gain = pc(1);
r.bump_steer = max(toe) - min(toe);
r.toe_slope = polyfit(travel(:), toe, 1) * [1; 0];
i0 = find(travel == 0, 1); if isempty(i0), i0 = round(n / 2); end
r.rc_static = rc_h(i0); r.rc_range = [min(rc_h), max(rc_h)];
r.static_camber = camber(i0); r.static_toe = toe(i0);
% steering axis geometry at static
sa = h.uwb_out - h.lwb_out;
r.kpi = atand(-sa(2) / sa(3));                     % positive = top inward
r.caster = atand(sa(1) / sa(3));                   % positive = top rearward
t = -h.lwb_out(3) / sa(3);                         % where the axis meets the ground
ground_pt = h.lwb_out + t * sa;
r.scrub_radius = cp0(2) - ground_pt(2);            % positive = axis inboard of the patch
r.trail = ground_pt(1) - cp0(1);                   % positive = axis hits the ground ahead (x rearward, so sign flipped below)
r.trail = -r.trail;
% spring rate for the target ride frequency with this motion ratio
if h.wheel_centre(1) == 0
    f = p.ride_frequency_front; ms = p.weight_dist_front * (p.mass_car + p.mass_driver) / 2 - p.unsprung_mass_corner_front;
else
    f = p.ride_frequency_rear; ms = (1 - p.weight_dist_front) * (p.mass_car + p.mass_driver) / 2 - p.unsprung_mass_corner_rear;
end
r.k_wheel = (2 * pi * f)^2 * ms;                   % N/m
r.k_spring = r.k_wheel / r.motion_ratio^2;
r.ride_frequency = f;
r.wishbone_lengths = Lfix;
end

function [F, J] = constraints(q, P0, ref, h, Lfix, zt)
F = resid(q, P0, ref, h, Lfix, zt);
J = zeros(6, 6);
d = 1e-6;
for k = 1:6
    qk = q; qk(k) = qk(k) + d;
    J(:, k) = (resid(qk, P0, ref, h, Lfix, zt) - F) / d;
end
end

function F = resid(q, P0, ref, h, Lfix, zt)
P = pose(q, P0, ref);
F = [norm(P(1, :) - h.lwb_in_fwd) - Lfix(1)
     norm(P(1, :) - h.lwb_in_aft) - Lfix(2)
     norm(P(2, :) - h.uwb_in_fwd) - Lfix(3)
     norm(P(2, :) - h.uwb_in_aft) - Lfix(4)
     norm(P(3, :) - h.tie_in)     - Lfix(5)
     P(5, 3) - zt];
end

function P = pose(q, P0, ref)
t = q(1:3).'; r = q(4:6);
th = norm(r);
if th < 1e-12
    R = eye(3);
else
    k = r / th; K = [0 -k(3) k(2); k(3) 0 -k(1); -k(2) k(1) 0];
    R = eye(3) + sin(th) * K + (1 - cos(th)) * K^2;
end
P = (R * (P0 - ref).').' + ref + t;
end

function hrc = roll_centre_height(h, P)
% Front view (y-z) instant centre: each wishbone's inboard axis projected to
% the plane x = wheel-centre x, joined to the ball joint. Roll centre = where
% the line IC -> contact patch crosses y = 0.
xw = P(5, 1);
upA = axis_at_x(h.uwb_in_fwd, h.uwb_in_aft, xw);
loA = axis_at_x(h.lwb_in_fwd, h.lwb_in_aft, xw);
ic = line_intersect_yz(upA, P(2, :), loA, P(1, :));
cp = P(6, :);
if any(isinf(ic))
    hrc = 0;       % parallel arms: IC at infinity, roll centre on the ground
    return
end
% line from IC through CP, evaluated at y = 0, measured from the ground
% plane through the contact patch (the chassis is fixed in this frame)
s = (0 - ic(2)) / (cp(2) - ic(2));
hrc = ic(3) + s * (cp(3) - ic(3)) - cp(3);
end

function pt = axis_at_x(a, b, x)
d = b - a;
if abs(d(1)) < 1e-9, pt = a; return, end
t = (x - a(1)) / d(1);
pt = a + t * d;
end

function ic = line_intersect_yz(a1, a2, b1, b2)
% intersection of lines a1-a2 and b1-b2 in the y-z plane, returned as [x y z]
d1 = a2(2:3) - a1(2:3); d2 = b2(2:3) - b1(2:3);
den = d1(1) * d2(2) - d1(2) * d2(1);
if abs(den) < 1e-9, ic = [Inf Inf Inf]; return, end
r = b1(2:3) - a1(2:3);
t = (r(1) * d2(2) - r(2) * d2(1)) / den;
yz = a1(2:3) + t * d1;
ic = [a1(1), yz];
end

% =============================================================================
function plot_corner(r, corner, h)
fig = figure('Name', ['suspension geometry ' corner], 'Position', [80 80 1200 750]);
subplot(2, 3, 1); plot(r.travel, r.camber, 'LineWidth', 1.5); grid on
xlabel('Wheel travel (mm, + bump)'); ylabel('Camber (deg)'); title(sprintf('Camber gain %.4f deg/mm', r.camber_gain));
subplot(2, 3, 2); plot(r.travel, r.toe, 'LineWidth', 1.5); grid on
xlabel('Wheel travel (mm)'); ylabel('Toe (deg, + in)'); title(sprintf('Bump steer %.3f deg over travel', r.bump_steer));
subplot(2, 3, 3); plot(r.travel, r.roll_centre_h, 'LineWidth', 1.5); grid on
xlabel('Wheel travel (mm)'); ylabel('Roll centre height (mm)'); title(sprintf('RC static %.0f mm, range %.0f to %.0f', r.rc_static, r.rc_range));
subplot(2, 3, 4); plot(r.travel, r.half_track_change, 'LineWidth', 1.5); grid on
xlabel('Wheel travel (mm)'); ylabel('Half-track change (mm)'); title('Contact patch lateral movement');
subplot(2, 3, 5); plot(r.travel, r.pushrod_travel, 'LineWidth', 1.5); grid on
xlabel('Wheel travel (mm)'); ylabel('Pushrod travel (mm)'); title(sprintf('Motion ratio %.3f, spring %.0f N/m', r.motion_ratio, r.k_spring));
% front view of the linkage at droop, static, bump
subplot(2, 3, 6); hold on; axis equal; grid on
idx = [1, find(r.travel == 0, 1), numel(r.travel)];
cols = [0.6 0.6 0.6; 0 0 0; 0.85 0.3 0.1];
for k = 1:3
    P = r.P(:, :, idx(k));
    plot([h.lwb_in_fwd(2) P(1, 2)], [h.lwb_in_fwd(3) P(1, 3)], '-', 'Color', cols(k, :), 'LineWidth', 1.5);
    plot([h.uwb_in_fwd(2) P(2, 2)], [h.uwb_in_fwd(3) P(2, 3)], '-', 'Color', cols(k, :), 'LineWidth', 1.5);
    plot([P(1, 2) P(2, 2)], [P(1, 3) P(2, 3)], '-', 'Color', cols(k, :), 'LineWidth', 2);
    plot([h.tie_in(2) P(3, 2)], [h.tie_in(3) P(3, 3)], '--', 'Color', cols(k, :));
    plot([h.pushrod_in(2) P(4, 2)], [h.pushrod_in(3) P(4, 3)], ':', 'Color', cols(k, :), 'LineWidth', 1.5);
    ax = P(7, :) - P(5, :); tyre = [P(5, 2:3) - 110 * [ax(3), -ax(2)] / norm(ax(2:3)); P(5, 2:3) + 110 * [ax(3), -ax(2)] / norm(ax(2:3))];
    plot(tyre(:, 1), tyre(:, 2), '-', 'Color', cols(k, :), 'LineWidth', 4);
end
plot(0, r.rc_static, 'r+', 'MarkerSize', 12, 'LineWidth', 2);
xlabel('y (mm)'); ylabel('z (mm)'); title('Front view: droop (grey), static (black), bump (orange), RC (+)');
sgtitle(sprintf('%s double wishbone: KPI %.1f deg, caster %.1f deg, scrub %.0f mm, trail %.0f mm', corner, r.kpi, r.caster, r.scrub_radius, r.trail));
save_fig(fig, ['suspension_geometry_' corner]);
end

function print_report(out)
fprintf('suspension_geometry: kinematics over %+d to %+d mm (right-hand corner)\n', min(out.front.travel), max(out.front.travel));
fprintf('  %-28s %10s %10s   target\n', 'quantity', 'front', 'rear');
row = @(n, a, b, t, f) fprintf(['  %-28s ' f ' ' f '   %s\n'], n, a, b, t);
row('camber gain (deg/mm)', out.front.camber_gain, out.rear.camber_gain, '-0.03 to -0.06', '%10.4f');
row('static camber (deg)', out.front.static_camber, out.rear.static_camber, 'from params', '%10.2f');
row('bump steer (deg over travel)', out.front.bump_steer, out.rear.bump_steer, '< 0.10', '%10.3f');
row('roll centre static (mm)', out.front.rc_static, out.rear.rc_static, 'F 30-60, R 50-90', '%10.1f');
row('roll centre min (mm)', out.front.rc_range(1), out.rear.rc_range(1), 'stays above ground', '%10.1f');
row('roll centre max (mm)', out.front.rc_range(2), out.rear.rc_range(2), '', '%10.1f');
row('motion ratio', out.front.motion_ratio, out.rear.motion_ratio, '0.7 to 1.0', '%10.3f');
row('spring rate (N/mm)', out.front.k_spring / 1000, out.rear.k_spring / 1000, 'for ride frequency', '%10.1f');
row('KPI (deg)', out.front.kpi, out.rear.kpi, '4 to 9', '%10.2f');
row('caster (deg)', out.front.caster, out.rear.caster, '3 to 7 (front)', '%10.2f');
row('scrub radius (mm)', out.front.scrub_radius, out.rear.scrub_radius, '0 to 20', '%10.1f');
row('trail (mm)', out.front.trail, out.rear.trail, '5 to 25 (front)', '%10.1f');
row('half-track change max (mm)', max(abs(out.front.half_track_change)), max(abs(out.rear.half_track_change)), 'small', '%10.2f');
end

function write_hardpoints(hp, out)
% Rewrite the hardpoint block in params/car_params.txt between the markers
% and write params/suspension_hardpoints.txt as a standalone copy.
root = repo_root();
lines = {};
lines{end+1} = sprintf('''  Suspension hardpoints written by matlab/suspension_geometry.m on %s', datestr(now, 'yyyy-mm-dd'));
lines{end+1} = '''  Right-hand corners; mirror in Y. Frame: X rearward from the front axle, Y right, Z up from the ground, mm.';
lines{end+1} = sprintf('''  Results: camber gain F %.4f / R %.4f deg/mm, bump steer F %.3f / R %.3f deg, RC F %.0f / R %.0f mm, MR F %.3f / R %.3f', ...
    out.front.camber_gain, out.rear.camber_gain, out.front.bump_steer, out.rear.bump_steer, ...
    out.front.rc_static, out.rear.rc_static, out.front.motion_ratio, out.rear.motion_ratio);
map = {'lwb_in_fwd', 'lwb_in_aft', 'lwb_out', 'uwb_in_fwd', 'uwb_in_aft', 'uwb_out', 'tie', 'pushrod_out', 'pushrod_in'};
for c = {'front', 'rear'}
    pre = c{1}(1);
    lines{end+1} = ''; %#ok<AGROW>
    lines{end+1} = sprintf('''  ---- %s right corner ----', c{1}); %#ok<AGROW>
    for k = 1:numel(map)
        nm = map{k};
        if strcmp(nm, 'tie')
            if strcmp(c{1}, 'front'), inn = 'tierod_in'; outn = 'tierod_out'; else, inn = 'toelink_in'; outn = 'toelink_out'; end
            lines = add_pt(lines, [pre '_' inn], hp.(c{1}).tie_in);
            lines = add_pt(lines, [pre '_' outn], hp.(c{1}).tie_out);
        else
            lines = add_pt(lines, [pre '_' nm], hp.(c{1}).(nm));
        end
    end
end
block = strjoin(lines, newline);
% standalone file
fid = fopen(fullfile(root, 'params', 'suspension_hardpoints.txt'), 'w');
fprintf(fid, '%s\n', block);
fclose(fid);
% replace block in car_params.txt
f = fullfile(root, 'params', 'car_params.txt');
txt = fileread(f);
beginMark = ''' ==== BEGIN hardpoints';
endMark = ''' ==== END hardpoints';
a = strfind(txt, beginMark);
b = strfind(txt, endMark);
if isempty(a) || isempty(b)
    error('suspension_geometry:markers', 'Markers BEGIN/END hardpoints not found in car_params.txt');
end
head = txt(1:a - 1);
tail = txt(b:end);
newtxt = [head beginMark ' (generated, do not edit by hand) ====' newline block newline tail];
fid = fopen(f, 'w'); fwrite(fid, newtxt); fclose(fid);
fprintf('suspension_geometry: hardpoints written to params/car_params.txt and params/suspension_hardpoints.txt\n');
end

function lines = add_pt(lines, name, pt)
ax = 'xyz';
for k = 1:3
    lines{end+1} = sprintf('"%s_%s"= %g', name, ax(k), pt(k)); %#ok<AGROW>
end
end

% =============================================================================
function ok = selftest()
% Hand check: parallel, equal, horizontal wishbones of length 300 mm with a
% parallel equal tie rod. Then over +/-30 mm:
%   camber change = 0 exactly, toe change = 0 exactly,
%   half-track change at 30 mm = sqrt(300^2 - 30^2) - 300 = -1.5076 mm,
%   roll centre on the ground (instant centres at infinity) = 0 mm,
%   a vertical pushrod from the upright has motion ratio 1 (rocker 1:1).
h.lwb_in_fwd = [-150 250 150]; h.lwb_in_aft = [150 250 150]; h.lwb_out = [0 550 150];
h.uwb_in_fwd = [-150 250 350]; h.uwb_in_aft = [150 250 350]; h.uwb_out = [0 550 350];
h.tie_in = [-80 250 250]; h.tie_out = [-80 550 250];
h.pushrod_out = [0 540 200]; h.pushrod_in = [0 540 600];
h.wheel_centre = [0 600 222]; h.static_camber = 0; h.rocker_ratio = 1;
p = read_car_params();
r = sweep_corner(h, -30:5:30, p);
dyHand = sqrt(300^2 - 30^2) - 300;
ok = max(abs(r.camber)) < 1e-6 && max(abs(r.toe)) < 1e-6 ...
   && abs(r.half_track_change(end) - dyHand) < 1e-6 && max(abs(r.roll_centre_h)) < 1e-6 ...
   && abs(r.motion_ratio - 1) < 1e-3;
% the committed hardpoints must solve and give a negative camber gain
o = suspension_geometry(struct('plot', false));
ok = ok && o.front.camber_gain < 0 && o.rear.camber_gain < 0;
if ok
    fprintf('suspension_geometry self-test: PASS (parallel arms: camber 0, toe 0, half-track %.4f mm vs hand %.4f, RC 0, MR %.3f)\n', ...
        r.half_track_change(end), dyHand, r.motion_ratio);
else
    error('suspension_geometry self-test: FAIL (camber %.2e, toe %.2e, dy %.4f vs %.4f, rc %.2e, MR %.4f, gains F %.4f R %.4f)', ...
        max(abs(r.camber)), max(abs(r.toe)), r.half_track_change(end), dyHand, max(abs(r.roll_centre_h)), r.motion_ratio, o.front.camber_gain, o.rear.camber_gain);
end
end
