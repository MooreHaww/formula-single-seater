function W = wake_postprocess(opts)
%WAKE_POSTPROCESS Ring 5: dirty-air metrics on the wake planes.
%   W = wake_postprocess()          reads cfd/results/wake/<variant>_<n>L.csv
%   W = wake_postprocess(opts)      opts.dir, opts.plot, opts.U_inf, opts.window
%   wake_postprocess('--selftest')
%
%   Input: one ASCII file per variant and plane exported from Fluent
%   (File > Export > Solution Data, ASCII, comma delimited, node values,
%   the four plane surfaces, variables: x-velocity y-velocity z-velocity
%   turb-kinetic-energy). File name <variant>_<n>L.csv where n is the plane
%   distance in car lengths, e.g. C_1L.csv, C_0.5L.csv. Columns are matched
%   by name, so the order does not matter. Coordinate frame as in
%   cfd/fluent_halfcar_setup.md: x downstream, y lateral from the symmetry
%   plane, z up from the ground, all in metres.
%
%   Metrics inside the following-car window (0 <= y <= width/2 because the
%   model is a half car, 0 <= z <= height), area-weighted by equal node
%   weight (Fluent node export is close to uniform on the box mesh):
%     deficit     1 - mean(u) / U_inf
%     q_ratio     mean((u / U_inf)^2)   first-order downforce left for a follower
%     TI          mean(sqrt(2/3 k)) / U_inf
%     upwash_deg  atan(mean(w) / mean(u)) in degrees, positive upward
%   Hand check: uniform u = 0.8 U_inf, w = 0.1 U_inf, k = 0.015 U_inf^2
%     deficit = 0.2, q_ratio = 0.64, TI = sqrt(0.01) = 0.10, upwash = atan(0.125) = 7.13 deg
%
%   Output: table W (variant, plane_lengths, deficit, q_ratio, TI, upwash_deg,
%   n_nodes), written to cfd/results/wake_summary.csv, a metrics-against-
%   distance plot and one u/U_inf contour per plane in media/wake/.

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    W = selftest();
    return
end
if nargin < 1, opts = struct(); end
p = read_car_params();
if ~isfield(opts, 'dir'), opts.dir = fullfile(repo_root(), 'cfd', 'results', 'wake'); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'U_inf'), opts.U_inf = p.cfd_speed; end
if ~isfield(opts, 'window'), opts.window = [p.wake_window_width / 2, p.wake_window_height]; end
files = dir(fullfile(opts.dir, '*_*L.csv'));
if isempty(files)
    warning('wake_postprocess:nofiles', 'No wake plane exports in %s (expected <variant>_<n>L.csv). Nothing to do.', opts.dir);
    W = table(); return
end
rows = [];
names = strings(0, 1);
planes = {};
for k = 1:numel(files)
    tok = regexp(files(k).name, '^(\w+)_([\d\.]+)L\.csv$', 'tokens', 'once');
    if isempty(tok), continue, end
    D = read_fluent_ascii(fullfile(files(k).folder, files(k).name));
    m = metrics(D, opts.U_inf, opts.window);
    rows(end+1, :) = [str2double(tok{2}), m.deficit, m.q_ratio, m.TI, m.upwash_deg, m.n]; %#ok<AGROW>
    names(end+1, 1) = string(tok{1}); %#ok<AGROW>
    planes{end+1} = struct('variant', tok{1}, 'L', str2double(tok{2}), 'D', D); %#ok<AGROW>
end
W = table(names, rows(:, 1), rows(:, 2), rows(:, 3), rows(:, 4), rows(:, 5), rows(:, 6), ...
    'VariableNames', {'variant', 'plane_lengths', 'deficit', 'q_ratio', 'TI', 'upwash_deg', 'n_nodes'});
W = sortrows(W, {'variant', 'plane_lengths'});

if opts.plot
    outDir = fullfile(repo_root(), 'cfd', 'results');
    writetable(W, fullfile(outDir, 'wake_summary.csv'));
    mediaDir = fullfile(repo_root(), 'media', 'wake');
    if ~isfolder(mediaDir), mkdir(mediaDir); end
    vars = unique(W.variant);
    fig = figure('Name', 'wake metrics', 'Position', [100 100 1000 700]);
    met = {'deficit', 'q_ratio', 'TI', 'upwash_deg'};
    lab = {'Velocity deficit 1 - U/U_\infty', 'Dynamic pressure ratio (U/U_\infty)^2', 'Turbulence intensity', 'Upwash angle (deg)'};
    for i = 1:4
        subplot(2, 2, i); hold on
        for v = 1:numel(vars)
            sel = W.variant == vars(v);
            plot(W.plane_lengths(sel), W.(met{i})(sel), '-o', 'LineWidth', 1.5, 'DisplayName', char(vars(v)));
        end
        grid on; xlabel('Car lengths behind the rear axle'); ylabel(lab{i}); legend('Location', 'best');
    end
    sgtitle('Dirty air in the following-car window, per variant');
    exportgraphics(fig, fullfile(mediaDir, 'wake_metrics.png'), 'Resolution', 150); close(fig);
    for k = 1:numel(planes)
        pl = planes{k};
        fig = figure('Name', 'plane', 'Position', [100 100 700 500]);
        yi = linspace(0, opts.window(1) * 1.3, 120); zi = linspace(0, opts.window(2) * 1.3, 100);
        [YI, ZI] = meshgrid(yi, zi);
        UI = griddata(pl.D.y, pl.D.z, pl.D.u / opts.U_inf, YI, ZI, 'linear');
        contourf(YI, ZI, UI, 20, 'LineStyle', 'none'); colorbar; hold on
        rectangle('Position', [0 0 opts.window(1) opts.window(2)], 'EdgeColor', 'w', 'LineWidth', 1.5, 'LineStyle', '--');
        axis equal tight; xlabel('y (m) from symmetry plane'); ylabel('z (m)');
        title(sprintf('%s, %g L behind: u/U_\\infty (window dashed, q-ratio %.2f)', pl.variant, pl.L, W.q_ratio(W.variant == pl.variant & W.plane_lengths == pl.L)));
        exportgraphics(fig, fullfile(mediaDir, sprintf('%s_%gL_u.png', pl.variant, pl.L)), 'Resolution', 150); close(fig);
    end
    fprintf('wake_postprocess: cfd/results/wake_summary.csv and media/wake/*.png written\n'); disp(W);
    sel = W.plane_lengths == 1;
    for v = 1:numel(vars)
        q = W.q_ratio(sel & W.variant == vars(v));
        if ~isempty(q), fprintf('  Headline: a car one length behind %s keeps about %.0f %% of its downforce\n', vars(v), 100 * q); end
    end
end
end

function D = read_fluent_ascii(file)
% Fluent ASCII export: header line with names like nodenumber, x-coordinate,
% y-coordinate, z-coordinate, x-velocity, ... comma or whitespace separated.
T = readtable(file, 'VariableNamingRule', 'preserve');
names = lower(string(T.Properties.VariableNames));
pick = @(cands) find_col(T, names, cands);
D.x = pick(["x-coordinate", "x", "x_coordinate"]);
D.y = pick(["y-coordinate", "y", "y_coordinate"]);
D.z = pick(["z-coordinate", "z", "z_coordinate"]);
D.u = pick(["x-velocity", "u", "x_velocity"]);
D.v = pick(["y-velocity", "v", "y_velocity"]);
D.w = pick(["z-velocity", "w", "z_velocity"]);
D.k = pick(["turb-kinetic-energy", "k", "turb_kinetic_energy", "tke"]);
end

function c = find_col(T, names, cands)
for k = 1:numel(cands)
    i = find(strtrim(names) == cands(k), 1);
    if ~isempty(i), c = T.(T.Properties.VariableNames{i}); return, end
end
error('wake_postprocess:column', 'Column %s not found; export x/y/z-velocity and turb-kinetic-energy from Fluent', cands(1));
end

function m = metrics(D, U, win)
in = D.y >= 0 & D.y <= win(1) & D.z >= 0 & D.z <= win(2);
if nnz(in) < 10
    error('wake_postprocess:window', 'Fewer than 10 nodes inside the window; check the coordinate frame (y lateral, z up)');
end
u = D.u(in); w = D.w(in); k = D.k(in);
m.n = nnz(in);
m.deficit = 1 - mean(u) / U;
m.q_ratio = mean((u / U).^2);
m.TI = mean(sqrt(2 / 3 * max(k, 0))) / U;
m.upwash_deg = atan2d(mean(w), mean(u));
end

function ok = selftest()
% Uniform synthetic plane: u = 0.8 U, w = 0.1 U, k = 0.015 U^2 inside the
% window, free stream outside it (so the window filter is tested too).
U = 20; tmp = tempname; mkdir(tmp);
[Y, Z] = meshgrid(linspace(0, 1.2, 40), linspace(0, 1.8, 50));
in = Y <= 0.7 & Z <= 1.2;
u = U * (0.8 * in + 1.0 * ~in); w = 0.1 * U * in; k = 0.015 * U^2 * in;
T = table((1:numel(Y)).', 3 * ones(numel(Y), 1), Y(:), Z(:), u(:), zeros(numel(Y), 1), w(:), k(:), ...
    'VariableNames', {'nodenumber', 'x-coordinate', 'y-coordinate', 'z-coordinate', 'x-velocity', 'y-velocity', 'z-velocity', 'turb-kinetic-energy'});
writetable(T, fullfile(tmp, 'T_1L.csv'));
W = wake_postprocess(struct('dir', tmp, 'plot', false, 'U_inf', U, 'window', [0.7 1.2]));
rmdir(tmp, 's');
ok = height(W) == 1 && abs(W.deficit - 0.2) < 1e-9 && abs(W.q_ratio - 0.64) < 1e-9 ...
    && abs(W.TI - 0.1) < 1e-9 && abs(W.upwash_deg - atand(0.125)) < 1e-9 && W.variant == "T";
if ok
    fprintf('wake_postprocess self-test: PASS (deficit %.2f, q-ratio %.2f, TI %.2f, upwash %.2f deg)\n', W.deficit, W.q_ratio, W.TI, W.upwash_deg);
else
    error('wake_postprocess self-test: FAIL');
end
end
