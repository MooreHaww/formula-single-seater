function T = cornering_speed_vs_downforce(opts)
%CORNERING_SPEED_VS_DOWNFORCE Headline plot: max speed through fixed-radius
%   corners against downforce, with the aero variants marked.
%   T = cornering_speed_vs_downforce()      writes media/cornering_speed_vs_downforce.png
%                                           and media/cornering_speed_table.csv
%   cornering_speed_vs_downforce('--selftest')
%
%   For each corner radius the script sweeps ClA from 0 to 6 m2 and solves
%   m v^2 / R = mu(Fz) Fz with Fz = m g + 0.5 rho ClA v^2, capped by the
%   power-limited top speed for the matching drag (CdA follows the straight
%   line fitted through variants A, B, C, so more downforce costs drag).
%   x-axis: downforce at 100 km/h, which is 0.5 * rho * ClA * 27.78^2 and
%   linear in ClA. Variants A to D are marked at their own ClA.
%   Radii include the high-speed corners of the fast circuit (120, 200 m).

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    T = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'radii'), opts.radii = [15 30 60 120 200]; end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'ClA_sweep'), opts.ClA_sweep = 0:0.2:6; end
p = read_car_params();
variants = {'A', 'B', 'C', 'D'};
cars = cellfun(@(v) car_from_params(v, p), variants);
ClA_v = [cars.ClA]; CdA_v = [cars.CdA];
pf = polyfit(ClA_v(1:3), CdA_v(1:3), 1);        % CdA = pf(1) * ClA + pf(2)
v100 = 100 / 3.6;
df100 = @(ClA) 0.5 * p.air_density * ClA * v100^2;

base = cars(3);
nR = numel(opts.radii); nC = numel(opts.ClA_sweep);
V = zeros(nR, nC);
for i = 1:nR
    for j = 1:nC
        c = base; c.ClA = opts.ClA_sweep(j); c.CdA = max(0.3, polyval(pf, c.ClA));
        V(i, j) = corner_vmax(c, opts.radii(i));
    end
end
% variants
Vv = zeros(nR, numel(cars)); DF = zeros(nR, numel(cars));
for i = 1:nR
    for k = 1:numel(cars)
        Vv(i, k) = corner_vmax(cars(k), opts.radii(i));
        DF(i, k) = 0.5 * cars(k).rho * cars(k).ClA * Vv(i, k)^2;
    end
end

% table: one row per (radius, variant)
rows = [];
for i = 1:nR
    for k = 1:numel(cars)
        rows = [rows; opts.radii(i), k, cars(k).ClA, cars(k).CdA, Vv(i, k), Vv(i, k) * 3.6, DF(i, k), Vv(i, k)^2 / opts.radii(i) / 9.81]; %#ok<AGROW>
    end
end
T = array2table(rows, 'VariableNames', {'radius_m', 'variant_idx', 'ClA_m2', 'CdA_m2', 'v_max_mps', 'v_max_kmh', 'downforce_at_vmax_N', 'lateral_g'});
T.variant = string(variants(T.variant_idx)).'; T.variant_idx = [];
T = movevars(T, 'variant', 'After', 'radius_m');

if opts.plot
    mediaDir = fullfile(repo_root(), 'media');
    if ~isfolder(mediaDir), mkdir(mediaDir); end
    writetable(T, fullfile(mediaDir, 'cornering_speed_table.csv'));
    fig = figure('Name', 'cornering speed vs downforce', 'Position', [100 100 900 600]);
    cols = lines(nR); hold on
    hs = gobjects(nR, 1);
    styles = {'-', '-', '-', '--', ':'};   % dashed/dotted so coincident power-limited lines stay visible
    for i = 1:nR
        hs(i) = plot(df100(opts.ClA_sweep), V(i, :) * 3.6, styles{min(i, numel(styles))}, 'Color', cols(i, :), 'LineWidth', 2, ...
            'DisplayName', sprintf('R = %g m', opts.radii(i)));
        for k = 1:numel(cars)
            plot(df100(cars(k).ClA), Vv(i, k) * 3.6, 'o', 'MarkerFaceColor', cols(i, :), 'Color', 'k', 'MarkerSize', 7, 'HandleVisibility', 'off');
            if i == nR
                text(df100(cars(k).ClA), Vv(i, k) * 3.6 + 4, variants{k}, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            end
        end
    end
    grid on; box on
    xlabel('Downforce at 100 km/h (N)   [= 0.5 \rho ClA v^2, so linear in ClA]');
    ylabel('Maximum corner speed (km/h)');
    title({'Maximum speed through a fixed-radius corner against downforce', ...
        sprintf('Markers: aero variants A-D (ClA %s m^2). Drag follows the A-B-C trend; flat line = power-limited top speed.', ...
        strjoin(compose('%.1f', ClA_v), '/'))});
    legend(hs, 'Location', 'southeast');
    save_fig(fig, 'cornering_speed_vs_downforce');
    fprintf('cornering_speed_vs_downforce: media/cornering_speed_vs_downforce.png and cornering_speed_table.csv written\n');
    disp(T(T.radius_m == 60 | T.radius_m == 120, :));
end
end

function v = corner_vmax(car, R)
% top speed cap
g = @(vv) long_forces(car, vv, 0).F_drive;
hi = min(car.v_rpm_max, 150); lo = 0;
if g(hi) < 0
    for it = 1:60, mid = (lo + hi) / 2; if g(mid) >= 0, lo = mid; else, hi = mid; end, end
    vtop = lo;
else
    vtop = hi;
end
h = @(vv) long_forces(car, vv, 0).Fmax - car.m * vv.^2 / R;
if h(vtop) >= 0, v = vtop; return, end
lo = 0; hi = vtop;
for it = 1:60, mid = (lo + hi) / 2; if h(mid) >= 0, lo = mid; else, hi = mid; end, end
v = lo;
end

function ok = selftest()
% Hand check: no aero, no load sensitivity, mu = 1.4, R = 50 m, unlimited power
%   v = sqrt(mu g R) = sqrt(1.4 * 9.81 * 50) = 26.21 m/s = 94.3 km/h
% With ClA = 4 m2, rho = 1.2, m = 300 kg (still no load sensitivity):
%   m v^2 / R = mu (m g + 0.5 rho ClA v^2)
%   v^2 (m/R - 0.5 mu rho ClA) = mu m g
%   v^2 (6 - 3.36) = 4120.2  ->  v = sqrt(1560.7) = 39.51 m/s = 142.2 km/h
car = car_from_params('A');
car.ClA = 0; car.CdA = 0; car.lsens = 0; car.mu0 = 1.4; car.m = 300; car.g = 9.81; car.rho = 1.2;
car.P_max = 1e9; car.F_torque_max = 1e9; car.v_rpm_max = 1e9; car.crr = 0;
v1 = corner_vmax(car, 50);
car.ClA = 4;
v2 = corner_vmax(car, 50);
ok = abs(v1 - sqrt(1.4 * 9.81 * 50)) < 1e-3 && abs(v2 - sqrt(1.4 * 300 * 9.81 / (300 / 50 - 0.5 * 1.4 * 1.2 * 4))) < 1e-3;
if ok
    fprintf('cornering_speed_vs_downforce self-test: PASS (R=50 m: %.2f m/s without aero, %.2f m/s with ClA=4)\n', v1, v2);
else
    error('cornering_speed_vs_downforce self-test: FAIL (%.3f, %.3f)', v1, v2);
end
end
