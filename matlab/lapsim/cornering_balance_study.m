function out = cornering_balance_study(opts)
%CORNERING_BALANCE_STUDY Weight distribution and aero balance against the
%   four-wheel cornering limit (cornering_balance.m), the default car (default_car(): FINAL) by default.
%   out = cornering_balance_study()      writes media/cornering_balance.png,
%                                        media/cornering_balance_table.csv and
%                                        media/cornering_balance.md
%   out = cornering_balance_study(opts)  opts.plot, opts.write, opts.radii
%                                        ([45 100]), opts.wd (front weight
%                                        fractions), opts.aero (front aero
%                                        fractions), opts.variant (default_car(), 'FINAL'),
%                                        opts.p (parameter struct; default the repo file),
%                                        opts.driver_forward_mm (100),
%                                        opts.aero_source ('table'; or a file or table,
%                                        passed to car_from_params)
%   cornering_balance_study('--selftest')
%
%   Grid: front weight fraction x front aero fraction x corner radius. The
%   CG height, tracks, roll-centre heights and ride frequencies stay at the
%   file's values when wd_front is swept, so the sweep isolates the
%   distribution itself. The roll-centre heights come from
%   suspension_geometry (static values) and the roll stiffness split from
%   the ride-frequency springs (no anti-roll bars in the file).
%
%   The "driver forward" rows use mass_budget's moves option to relocate the
%   driver by opts.driver_forward_mm, which changes wd_front and cg_height
%   together, the way the real change would.
%
%   out fields: table T, assumptions (cellstr), driver (struct with the
%   baseline and moved cases), lap (lap-time comparison with lapsim's
%   four_wheel option), h_rc (roll-centre heights used).

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'write'), opts.write = true; end
if ~isfield(opts, 'radii'), opts.radii = [45 100]; end
if ~isfield(opts, 'wd'), opts.wd = [0.35 NaN 0.47]; end   % NaN = the file's own value, filled below
if ~isfield(opts, 'variant'), opts.variant = default_car(); end
if ~isfield(opts, 'aero_source'), opts.aero_source = 'table'; end   % as car_from_params: 'table', a file or a table
if ~isfield(opts, 'driver_forward_mm'), opts.driver_forward_mm = 100; end
if ~isfield(opts, 'laps'), opts.laps = true; end
if isfield(opts, 'p'), p = opts.p; else, p = read_car_params(); end
opts.wd(isnan(opts.wd)) = p.weight_dist_front;
base = car_from_params(opts.variant, p, opts.aero_source);
% aero reference = the car's own front share (variant table or parameter
% file); target = aero_balance_target (ESTIMATE/target in car_params.txt)
aeroRef = base.aero_front; aeroTarget = base.aero_front_target;
if ~isfield(opts, 'aero')
    opts.aero = unique(round([0.35, aeroTarget, aeroRef, 0.55], 4));
    opts.aero = opts.aero(~isnan(opts.aero));
end
out.variant = opts.variant; out.aero_front_ref = aeroRef; out.aero_front_target = aeroTarget;

% roll-centre heights from the suspension kinematics (static), else defaults
try
    sg = suspension_geometry(struct('plot', false, 'write', false, 'p', p));
    base.h_rc_f = sg.front.rc_static / 1000; base.h_rc_r = sg.rear.rc_static / 1000;
    rcSource = 'suspension_geometry static';
catch
    rcSource = 'fallback 60 / 69 mm';
end
out.h_rc = [base.h_rc_f, base.h_rc_r];
out.h_rc_source = rcSource;

aeroLabel = @(a) ternary(abs(a - aeroRef) < 1e-9, "as filed", ternary(abs(a - aeroTarget) < 1e-9, "target", ternary(a < aeroRef, "rear-heavy", "front-heavy")));

rows = {};
for R = opts.radii
    for wd = opts.wd
        for af = opts.aero
            car = base; car.wd_front = wd; car.aero_front = af;
            o = cornering_balance(car, R);
            rows(end+1, :) = {R, wd, af, aeroLabel(af), o.v_grip * 3.6, o.v_max * 3.6, o.power_limited, o.lat_g, ...
                o.limiting_axle, o.balance_pct, o.Fz(1), o.Fz(2), o.Fz(3), o.Fz(4), o.inner_lift, o.v_point_mass * 3.6}; %#ok<AGROW>
        end
    end
end
T = cell2table(rows, 'VariableNames', {'radius_m', 'wd_front', 'aero_front', 'aero_label', 'v_grip_kmh', 'v_max_kmh', ...
    'power_limited', 'lateral_g', 'limiting_axle', 'balance_pct', 'Fz_FO_N', 'Fz_FI_N', 'Fz_RO_N', 'Fz_RI_N', 'inner_lift', 'v_point_mass_kmh'});
out.T = T;
out.roll_stiff_front = cornering_balance_kf(base);

% ---- driver forward: the real change moves the CG height too -------------------
[~, mb0] = evalc('mass_budget(struct(''plot'', false, ''write'', false))');   % evalc: keep its table off the screen
[~, mb1] = evalc('mass_budget(struct(''plot'', false, ''write'', false, ''moves'', {{''driver'', p.x_driver - opts.driver_forward_mm, p.z_driver}}))');
drv = struct();
drv.cases = {'as filed', 'driver forward'};
drv.wd = [mb0.wd_front, mb1.wd_front]; drv.cg_z = [mb0.cg_z, mb1.cg_z];
drv.rows = {};
for k = 1:2
    car = base; car.wd_front = drv.wd(k); car.h_cg = drv.cg_z(k) / 1000;
    for R = opts.radii
        o = cornering_balance(car, R);
        drv.rows(end+1, :) = {drv.cases{k}, R, drv.wd(k), drv.cg_z(k), o.v_grip * 3.6, o.v_max * 3.6, o.power_limited, o.limiting_axle, o.balance_pct}; %#ok<AGROW>
    end
end
drv.T = cell2table(drv.rows, 'VariableNames', {'case', 'radius_m', 'wd_front', 'cg_z_mm', 'v_grip_kmh', 'v_max_kmh', 'power_limited', 'limiting_axle', 'balance_pct'});
out.driver = drv;

% ---- lap times with the four-wheel corner limit, as filed vs driver forward -------
if opts.laps
    tracks = {'autocross', 'fast_circuit'};
    lapRows = {};
    for k = 1:2
        car = base; car.wd_front = drv.wd(k); car.h_cg = drv.cg_z(k) / 1000;
        for t = 1:2
            tr = load_track(tracks{t});
            r0 = lapsim(car, tr);
            r1 = lapsim(car, tr, struct('four_wheel', true));
            lapRows(end+1, :) = {drv.cases{k}, tracks{t}, r0.t_lap, r1.t_lap, r1.t_lap - r0.t_lap}; %#ok<AGROW>
        end
    end
    out.lap = cell2table(lapRows, 'VariableNames', {'case', 'track', 't_point_mass_s', 't_four_wheel_s', 'cost_of_load_transfer_s'});
end

% ---- aero balance target: how close is it to neutral, what is it worth ---------------
% At the file's weight distribution: the neutral front aero share per radius
% (both axles at their limit together), and the corner speed and balance at
% the reference share and at the target share.
tg = struct(); tg.rows = {};
for R = opts.radii
    car = base;
    o0 = cornering_balance(car, R, struct('find_neutral', true));
    car.aero_front = aeroTarget;
    o1 = cornering_balance(car, R);
    tg.rows(end+1, :) = {R, o0.aero_front_neutral, aeroRef, o0.v_grip * 3.6, o0.balance_pct, aeroTarget, o1.v_grip * 3.6, o1.balance_pct}; %#ok<AGROW>
end
tg.T = cell2table(tg.rows, 'VariableNames', {'radius_m', 'aero_front_neutral', 'aero_front_ref', 'v_grip_ref_kmh', 'balance_ref_pct', 'aero_front_target', 'v_grip_target_kmh', 'balance_target_pct'});
if opts.laps
    tracks = {'autocross', 'fast_circuit'};
    lr = {};
    for t = 1:2
        tr = load_track(tracks{t});
        r0 = lapsim(base, tr, struct('four_wheel', true));
        r1 = lapsim(base, tr, struct('four_wheel', true, 'aero_front', 'target'));
        lr(end+1, :) = {tracks{t}, r0.t_lap, r1.t_lap, r1.t_lap - r0.t_lap}; %#ok<AGROW>
    end
    tg.lap = cell2table(lr, 'VariableNames', {'track', 't_ref_s', 't_target_s', 'gain_s'});
end
out.target = tg;

% ---- assumptions the conclusions rest on --------------------------------------------
out.assumptions = {
    sprintf('tyre: mu_peak %.2f at %.0f N, load sensitivity exponent %.2f (file starting values, no tyre data)', p.tyre_mu_peak, p.tyre_fz_ref, p.tyre_load_sensitivity)
    sprintf('cg_height %.0f mm from the mass budget (%.0f %% of the mass is a GUESS)', p.cg_height, 100 * mb0.guess_fraction)
    sprintf('roll-centre heights %.0f / %.0f mm (%s), held fixed with roll', 1000 * base.h_rc_f, 1000 * base.h_rc_r, rcSource)
    sprintf('roll stiffness split %.0f %% front from ride frequencies %.1f / %.1f Hz; no anti-roll bars, tyre stiffness ignored', 100 * out.roll_stiff_front, p.ride_frequency_front, p.ride_frequency_rear)
    sprintf('aero (%s): ClA %.3f, CdA %.3f, balance %.3f front as filed, target %.2f (ESTIMATE/target); downforce adds load without lateral transfer', base.aero_source, base.ClA, base.CdA, aeroRef, aeroTarget)
    'steady state only: no yaw moment, no slip angles, no camber, no transient, no driver'
    'unsprung mass 22.2 kg per axle at wheel-centre height (all GUESS lines)'
    };

if opts.write || opts.plot
    mediaDir = fullfile(repo_root(), 'media');
    if ~isfolder(mediaDir), mkdir(mediaDir); end
end
if opts.write
    writetable(T, fullfile(mediaDir, 'cornering_balance_table.csv'));
    write_markdown(fullfile(mediaDir, 'cornering_balance.md'), out, p, opts);
    print_report(out);
end
if opts.plot
    plot_study(out, opts, p);
end
end

% ------------------------------------------------------------------------
function kf = cornering_balance_kf(car)
o = cornering_balance(car, 50, struct('v_top', 1e9));
kf = o.geo.kf;
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function print_report(out)
T = out.T;
fprintf('\ncornering_balance_study (variant %s): grip-limited corner speed, four-wheel model\n', out.variant);
fprintf('roll centres %.0f / %.0f mm (%s), roll stiffness %.0f %% front\n', 1000 * out.h_rc(1), 1000 * out.h_rc(2), out.h_rc_source, 100 * out.roll_stiff_front);
for R = unique(T.radius_m).'
    fprintf('  R = %3d m:\n', R);
    s = T(T.radius_m == R, :);
    for i = 1:height(s)
        fprintf('    wd %.3f  aero %.2f (%-11s)  v_grip %5.1f km/h  v_max %5.1f km/h%s  %.2f g  %s limits  balance %+5.1f %%  point-mass %5.1f km/h\n', ...
            s.wd_front(i), s.aero_front(i), s.aero_label(i), s.v_grip_kmh(i), s.v_max_kmh(i), ternary(s.power_limited(i), ' (power)', '        '), ...
            s.lateral_g(i), s.limiting_axle(i), s.balance_pct(i), s.v_point_mass_kmh(i));
    end
end
fprintf('  Aero balance target (aero_balance_target %.2f, as filed %.2f):\n', out.aero_front_target, out.aero_front_ref); disp(out.target.T);
if isfield(out.target, 'lap'), disp(out.target.lap); end
fprintf('  Driver forward:\n'); disp(out.driver.T);
if isfield(out, 'lap'), fprintf('  Lap times, point-mass vs four-wheel corner limit:\n'); disp(out.lap); end
fprintf('  Assumptions:\n'); fprintf('    - %s\n', out.assumptions{:});
end

function write_markdown(file, out, p, opts)
T = out.T;
fid = fopen(file, 'w');
fprintf(fid, '# Cornering balance study (variant %s, four-wheel steady-state model)\n\n', opts.variant);
fprintf(fid, 'Written by `matlab/lapsim/cornering_balance_study.m`. Grip-limited corner speed from `cornering_balance.m`: lateral load transfer per axle (roll stiffness, roll centres, unsprung mass), tyre load sensitivity, limit set by the axle that reaches 100 %% of its capacity first. `v_max` is capped by the power/drag top speed (%.0f km/h); `balance` = front-axle use minus rear-axle use at that speed, positive = understeer at the limit. `point-mass` is the old lap-sim answer (mu at the average wheel load, no transfer).\n\n', 3.6 * cornering_balance(car_from_params(opts.variant, p), 50).v_top);
fprintf(fid, '| R (m) | front weight | front aero | v grip (km/h) | v max (km/h) | lat g | limits | balance (%%) | FO / FI / RO / RI (N) | point-mass (km/h) |\n|---|---|---|---|---|---|---|---|---|---|\n');
for i = 1:height(T)
    fprintf(fid, '| %d | %.1f %% | %.2f (%s) | %.1f | %.1f%s | %.2f | %s | %+.1f | %.0f / %.0f / %.0f / %.0f%s | %.1f |\n', ...
        T.radius_m(i), 100 * T.wd_front(i), T.aero_front(i), T.aero_label(i), T.v_grip_kmh(i), T.v_max_kmh(i), ternary(T.power_limited(i), ' (power)', ''), ...
        T.lateral_g(i), T.limiting_axle(i), T.balance_pct(i), T.Fz_FO_N(i), T.Fz_FI_N(i), T.Fz_RO_N(i), T.Fz_RI_N(i), ternary(T.inner_lift(i), ' lift', ''), T.v_point_mass_kmh(i));
end
g = out.target.T;
fprintf(fid, '\n## Aero balance target\n\n`aero_balance_target` = %.2f in `params/car_params.txt` (ESTIMATE/target, not a result). The neutral share is the front aero fraction at which both axles reach their grip limit together at the file''s weight distribution (%.1f %% front); it moves with the assumed tyre load sensitivity, CG height and roll stiffness split.\n\n| R (m) | neutral front aero | as filed | v grip (km/h) | balance (%%) | target | v grip (km/h) | balance (%%) |\n|---|---|---|---|---|---|---|---|\n', out.aero_front_target, 100 * p.weight_dist_front);
for i = 1:height(g)
    fprintf(fid, '| %d | %.3f | %.2f | %.1f | %+.1f | %.2f | %.1f | %+.1f |\n', g.radius_m(i), g.aero_front_neutral(i), g.aero_front_ref(i), g.v_grip_ref_kmh(i), g.balance_ref_pct(i), g.aero_front_target(i), g.v_grip_target_kmh(i), g.balance_target_pct(i));
end
if isfield(out.target, 'lap')
    gl = out.target.lap;
    fprintf(fid, '\nLap time with the four-wheel corner limit, front aero share as filed against the target:\n\n| track | as filed (s) | target (s) | change (s) |\n|---|---|---|---|\n');
    for i = 1:height(gl)
        fprintf(fid, '| %s | %.2f | %.2f | %+.2f |\n', gl.track{i}, gl.t_ref_s(i), gl.t_target_s(i), gl.gain_s(i));
    end
end
d = out.driver.T;
fprintf(fid, '\n## Driver %d mm forward (mass_budget moves, CG height follows)\n\n| case | R (m) | front weight | CG z (mm) | v grip (km/h) | v max (km/h) | limits | balance (%%) |\n|---|---|---|---|---|---|---|---|\n', opts.driver_forward_mm);
for i = 1:height(d)
    fprintf(fid, '| %s | %d | %.1f %% | %.0f | %.1f | %.1f%s | %s | %+.1f |\n', d.case{i}, d.radius_m(i), 100 * d.wd_front(i), d.cg_z_mm(i), d.v_grip_kmh(i), d.v_max_kmh(i), ternary(d.power_limited(i), ' (power)', ''), d.limiting_axle(i), d.balance_pct(i));
end
if isfield(out, 'lap')
    L = out.lap;
    fprintf(fid, '\n## Lap times with the four-wheel corner limit (`lapsim` option `four_wheel`)\n\n| case | track | point-mass (s) | four-wheel (s) | cost (s) |\n|---|---|---|---|---|\n');
    for i = 1:height(L)
        fprintf(fid, '| %s | %s | %.2f | %.2f | %+.2f |\n', L.case{i}, L.track{i}, L.t_point_mass_s(i), L.t_four_wheel_s(i), L.cost_of_load_transfer_s(i));
    end
end
fprintf(fid, '\n## Assumptions these numbers depend on\n\n');
fprintf(fid, '- %s\n', out.assumptions{:});
fclose(fid);
end

function plot_study(out, opts, p)
T = out.T; radii = opts.radii; aeros = opts.aero; wds = opts.wd;
fig = figure('Name', 'cornering balance', 'Position', [100 100 1100 750]);
cols = lines(numel(aeros));
for r = 1:numel(radii)
    R = radii(r);
    subplot(2, numel(radii), r); hold on; grid on; box on
    for a = 1:numel(aeros)
        s = T(T.radius_m == R & abs(T.aero_front - aeros(a)) < 1e-9, :);
        plot(100 * s.wd_front, s.v_grip_kmh, '-o', 'Color', cols(a, :), 'LineWidth', 2, 'MarkerFaceColor', cols(a, :), ...
            'DisplayName', sprintf('aero %.2f front (%s)', aeros(a), s.aero_label(1)));
    end
    s = T(T.radius_m == R & abs(T.aero_front - out.aero_front_ref) < 1e-9, :);
    plot(100 * s.wd_front, s.v_point_mass_kmh, 'k--', 'LineWidth', 1.2, 'DisplayName', 'point-mass lap sim (no transfer)');
    yl = ylim;
    vt = s.v_max_kmh(1); if any(s.power_limited), plot(xlim, [1 1] * max(T.v_max_kmh(T.radius_m == R)), 'k:', 'DisplayName', 'power-limited top speed'); end %#ok<NASGU>
    for k = 1:2
        xline(100 * out.driver.wd(k), ':', out.driver.cases{k}, 'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
    end
    ylim([yl(1), max(yl(2), max(s.v_point_mass_kmh) + 3)]);
    xlabel('Front weight fraction (%)'); ylabel('Grip-limited corner speed (km/h)');
    title(sprintf('R = %d m, variant %s', R, opts.variant));
    if r == 1, legend('Location', 'southwest', 'FontSize', 8); end
    subplot(2, numel(radii), numel(radii) + r); hold on; grid on; box on
    for a = 1:numel(aeros)
        s = T(T.radius_m == R & abs(T.aero_front - aeros(a)) < 1e-9, :);
        plot(100 * s.wd_front, s.balance_pct, '-o', 'Color', cols(a, :), 'LineWidth', 2, 'MarkerFaceColor', cols(a, :));
    end
    yline(0, 'k-', 'neutral', 'HandleVisibility', 'off');
    for k = 1:2
        xline(100 * out.driver.wd(k), ':', 'HandleVisibility', 'off');
    end
    xlabel('Front weight fraction (%)'); ylabel({'Balance at the limit (%)', 'front use - rear use: + understeer, - oversteer'});
    title(sprintf('R = %d m: which axle gives up first', R));
end
sgtitle({sprintf('Four-wheel cornering limit, variant %s: load transfer + tyre load sensitivity (exponent %.2f, ASSUMED)', opts.variant, p.tyre_load_sensitivity), ...
    sprintf('roll centres %.0f / %.0f mm, roll stiffness %.0f %% front (springs only), CG %.0f mm; dotted verticals: as filed and driver %d mm forward', ...
    1000 * out.h_rc(1), 1000 * out.h_rc(2), 100 * out.roll_stiff_front, p.cg_height, opts.driver_forward_mm)}, 'FontSize', 10);
save_fig(fig, 'cornering_balance');
fprintf('cornering_balance_study: media/cornering_balance.png, cornering_balance_table.csv and cornering_balance.md written\n');
end

% ------------------------------------------------------------------------
function ok = selftest()
% Hand-checkable direction tests on a coarse grid (no files, no figure):
%   (1) the table has radii x wd x aero rows, in order;
%   (2) with the file's rear-biased roll stiffness, moving weight forward
%       (35 -> 47 %) must move the balance toward understeer (balance rises
%       monotonically with wd_front) at every radius and aero split;
%   (3) more front aero must reduce the front axle's use, so balance falls
%       monotonically with aero_front at fixed wd;
%   (4) the grip-limited speed never exceeds the point-mass speed (load
%       transfer with load sensitivity can only lose capacity).
o = cornering_balance_study(struct('plot', false, 'write', false, 'laps', false, 'radii', [45 100], 'wd', [0.35 0.414 0.47], 'aero', [0.35 0.55]));
T = o.T;
ok = height(T) == 2 * 3 * 2 && isequal(T.radius_m(1:6), 45 * ones(6, 1));
for R = [45 100]
    for a = [0.35 0.55]
        b = T.balance_pct(T.radius_m == R & abs(T.aero_front - a) < 1e-9);
        ok = ok && all(diff(b) > 0);
    end
    for wd = [0.35 0.414 0.47]
        b = T.balance_pct(T.radius_m == R & abs(T.wd_front - wd) < 1e-9);
        ok = ok && all(diff(b) < 0);
    end
end
ok = ok && all(T.v_grip_kmh <= T.v_point_mass_kmh + 1e-6 | T.power_limited);
ok = ok && height(o.driver.T) == 4 && o.driver.wd(2) > o.driver.wd(1);
%   (5) aero balance target: feeding the solved neutral share back into
%       cornering_balance must give balance 0 at that radius, and because
%       balance falls as the front share rises, the balance at the target
%       must have the sign of (neutral - target).
g = o.target.T; g = g(g.radius_m == 45, :);
c = car_from_params(o.variant); c.h_rc_f = o.h_rc(1); c.h_rc_r = o.h_rc(2); c.aero_front = g.aero_front_neutral;
bN = cornering_balance(c, 45).balance_pct;
ok = ok && abs(bN) < 0.01 && (sign(g.balance_target_pct) == sign(g.aero_front_neutral - g.aero_front_target) || abs(g.balance_target_pct) < 0.01);
if ok
    fprintf('cornering_balance_study self-test: PASS (%d rows; balance rises with front weight and falls with front aero; driver forward %.1f -> %.1f %% front; neutral front aero at 45 m %.3f, target %.2f gives %+.1f %%)\n', ...
        height(T), 100 * o.driver.wd(1), 100 * o.driver.wd(2), g.aero_front_neutral, g.aero_front_target, g.balance_target_pct);
else
    error('cornering_balance_study self-test: FAIL');
end
end
