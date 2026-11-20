function out = mass_budget(opts)
%MASS_BUDGET Roll up the itemised masses in params/car_params.txt.
%   out = mass_budget()          prints the table, writes media/mass_budget.md
%                                and media/mass_budget.png
%   out = mass_budget(opts)      opts.file (parameter file), opts.plot,
%                                opts.write, opts.moves
%   mass_budget('--selftest')
%
%   opts.moves is a cell array {item, x_mm, z_mm; ...} that relocates items
%   before the roll-up, for layout studies ("what if the battery sat in the
%   sidepods"): the file is not changed, the printout and figure say which
%   items were moved, and nothing is written.
%
%   The parameter file holds one mass per item as "m_<item>" with its CG at
%   "x_<item>" (mm rearward of the front axle) and "z_<item>" (mm above the
%   ground), plus "mass_driver" with "x_driver" / "z_driver". The first word
%   of the comment on each mass line is its source flag: CALC, CATALOGUE,
%   ESTIMATE or GUESS. mass_car, cg_x_from_front_axle, cg_height and
%   weight_dist_front are expressions over those lines in the file itself, so
%   this script only re-adds them, checks that the file's expressions agree,
%   and reports how much of the mass is still a guess.
%
%   out fields: items (table: item, mass_kg, x_mm, z_mm, flag), mass_car,
%   mass_total, cg_x, cg_z, wd_front, guess_kg, guess_fraction, by_flag.

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'file'), opts.file = fullfile(repo_root(), 'params', 'car_params.txt'); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'write'), opts.write = true; end
if ~isfield(opts, 'moves'), opts.moves = {}; end
if ~isempty(opts.moves), opts.write = false; end

p = read_car_params(opts.file);
flags = read_flags(opts.file);

fn = fieldnames(p);
names = {}; m = []; x = []; z = []; fl = {};
for k = 1:numel(fn)
    f = fn{k};
    if startsWith(f, 'm_') && isfield(p, ['x_' f(3:end)]) && isfield(p, ['z_' f(3:end)])
        it = f(3:end);
    elseif strcmp(f, 'mass_driver') && isfield(p, 'x_driver')
        it = 'driver';
    else
        continue
    end
    names{end+1, 1} = it; %#ok<AGROW>
    m(end+1, 1) = p.(f); x(end+1, 1) = p.(['x_' it]); z(end+1, 1) = p.(['z_' it]); %#ok<AGROW>
    if isKey(flags, f), fl{end+1, 1} = flags(f); else, fl{end+1, 1} = 'GUESS'; end %#ok<AGROW>
end
if isempty(m)
    error('mass_budget:empty', 'No m_<item> / x_<item> / z_<item> entries in %s', opts.file);
end
for k = 1:size(opts.moves, 1)
    i = find(strcmp(names, opts.moves{k, 1}), 1);
    if isempty(i), error('mass_budget:move', 'No item "%s" to move', opts.moves{k, 1}); end
    x(i) = opts.moves{k, 2}; z(i) = opts.moves{k, 3}; fl{i} = [fl{i} '*'];
end
isDriver = strcmp(names, 'driver');
T = table(string(names), m, x, z, string(fl), 'VariableNames', {'item', 'mass_kg', 'x_mm', 'z_mm', 'flag'});

out.items = T;
out.mass_car = sum(m(~isDriver));
out.mass_total = sum(m);
out.cg_x = sum(m .* x) / out.mass_total;
out.cg_z = sum(m .* z) / out.mass_total;
out.wd_front = 1 - out.cg_x / p.wheelbase;
out.guess_kg = sum(m(strcmp(fl, 'GUESS')));
out.guess_fraction = out.guess_kg / out.mass_total;
flagOrder = {'CALC', 'CATALOGUE', 'ESTIMATE', 'GUESS'};
out.by_flag = table(string(flagOrder)', cellfun(@(s) sum(m(strcmp(fl, s))), flagOrder)', 'VariableNames', {'flag', 'mass_kg'});

% the file's own expressions must agree with the re-added numbers (unless items were moved)
out.file_agrees = abs(p.mass_car - out.mass_car) < 1e-6 && abs(p.cg_x_from_front_axle - out.cg_x) < 1e-6 ...
    && abs(p.cg_height - out.cg_z) < 1e-6 && abs(p.weight_dist_front - out.wd_front) < 1e-9;
if ~out.file_agrees && isempty(opts.moves)
    warning('mass_budget:disagree', ['mass_car / cg expressions in %s do not match the item list ' ...
        '(file %.2f kg, items %.2f kg). An item is missing from the mass_car line.'], opts.file, p.mass_car, out.mass_car);
end

% the frame line must match the frame CSVs: m_frame is the SolidWorks
% weldment's mass, x_frame / z_frame the centroid of the CSV tubes with the
% joint overlaps removed (frame_trimmed_mass.m). Warn if the trimmed CSV mass
% is more than 1.5 kg (3 %) from m_frame or the centroid more than 15 mm off
% (the frame changed and the line was not updated)
out.frame_check = '';
csvT = fullfile(repo_root(), 'cad', 'frame', 'frame_tubes.csv'); csvN = fullfile(repo_root(), 'cad', 'frame', 'frame_nodes.csv');
csvP = fullfile(repo_root(), 'cad', 'frame', 'frame_trims.csv');
iF = find(strcmp(names, 'frame'), 1);
if ~isempty(iF) && isfile(csvT) && isfile(csvN) && isfile(csvP) && isempty(opts.moves)
    ft = frame_trimmed_mass();
    mF = ft.m_trimmed; cgF = ft.cg_trimmed;
    out.frame_trimmed = ft;
    if abs(mF - m(iF)) > 1.5 || abs(cgF(1) - x(iF)) > 15 || abs(cgF(3) - z(iF)) > 15
        out.frame_check = sprintf('the frame CSVs give %.1f kg at x %.0f z %.0f with the joint overlaps removed (%.1f kg on centrelines); the budget says %.1f kg at x %.0f z %.0f. Update m_frame / x_frame / z_frame.', mF, cgF(1), cgF(3), ft.m_csv, m(iF), x(iF), z(iF));
        warning('mass_budget:frame', '%s', out.frame_check);
    end
end

% ---- print --------------------------------------------------------------------
fprintf('Mass budget from %s\n', opts.file);
if ~isempty(opts.moves), fprintf('  with %d item(s) moved (flag marked *): %s\n', size(opts.moves, 1), strjoin(opts.moves(:, 1)', ', ')); end
Tp = sortrows(T, 'mass_kg', 'descend');
disp(Tp);
fprintf('Car without driver %.1f kg, with driver %.1f kg. CG x %.0f mm from the front axle (%.1f %% front), z %.0f mm.\n', ...
    out.mass_car, out.mass_total, out.cg_x, 100 * out.wd_front, out.cg_z);
fprintf('By flag: CALC %.1f, CATALOGUE %.1f, ESTIMATE %.1f, GUESS %.1f kg (%.0f %% of the total is a guess).\n', ...
    out.by_flag.mass_kg, 100 * out.guess_fraction);
if ~out.file_agrees && isempty(opts.moves), fprintf('WARNING: the file expressions disagree with the item list.\n'); end

% ---- write -------------------------------------------------------------------
if opts.write
    md = fullfile(repo_root(), 'media', 'mass_budget.md');
    fid = fopen(md, 'w');
    fprintf(fid, '# Mass and CG budget\n\nGenerated by `matlab/mass_budget.m` from `params/car_params.txt`. Flags: CALC computed here, CATALOGUE from a data sheet, ESTIMATE sized from the layout, GUESS nothing behind it yet.\n\n');
    fprintf(fid, '| Item | Mass (kg) | x (mm) | z (mm) | Flag |\n|---|---|---|---|---|\n');
    for k = 1:height(Tp)
        fprintf(fid, '| %s | %.1f | %.0f | %.0f | %s |\n', Tp.item(k), Tp.mass_kg(k), Tp.x_mm(k), Tp.z_mm(k), Tp.flag(k));
    end
    fprintf(fid, '\n| Total | Value |\n|---|---|\n');
    fprintf(fid, '| Car without driver | %.1f kg |\n| Car with driver | %.1f kg |\n| CG x from the front axle | %.0f mm |\n| Front weight fraction | %.1f %% |\n| CG height | %.0f mm |\n', ...
        out.mass_car, out.mass_total, out.cg_x, 100 * out.wd_front, out.cg_z);
    for k = 1:height(out.by_flag)
        fprintf(fid, '| %s | %.1f kg |\n', out.by_flag.flag(k), out.by_flag.mass_kg(k));
    end
    fprintf(fid, '\nThe four derived values are expressions in the parameter file; change an item there, not here.\n');
    fclose(fid);
    fprintf('mass_budget: wrote %s\n', md);
end

% ---- plot: side view, circle area proportional to mass ----------------------------------
if opts.plot
    fig = figure('Name', 'Mass budget', 'Color', 'w', 'Position', [100 100 1100 500]);
    hold on; axis equal; grid on
    plot([-800 2400], [0 0], 'k-', 'LineWidth', 1.5);
    th = linspace(0, 2 * pi, 60);
    for R = [p.tyre_od / 2]
        plot(R * cos(th), p.tyre_rolling_radius + R * sin(th), '-', 'Color', [0.5 0.5 0.5]);
        plot(p.wheelbase + R * cos(th), p.tyre_rolling_radius + R * sin(th), '-', 'Color', [0.5 0.5 0.5]);
    end
    cols = containers.Map(flagOrder, {[0.2 0.6 0.2], [0.2 0.4 0.8], [0.9 0.6 0.1], [0.85 0.25 0.25]});
    for k = 1:height(T)
        r = 12 * sqrt(T.mass_kg(k));
        c = cols(strrep(char(T.flag(k)), '*', ''));
        fill(T.x_mm(k) + r * cos(th), T.z_mm(k) + r * sin(th), c, 'FaceAlpha', 0.35, 'EdgeColor', c);
        text(T.x_mm(k), T.z_mm(k), sprintf('%s %.1f', strrep(char(T.item(k)), '_', ' '), T.mass_kg(k)), ...
            'HorizontalAlignment', 'center', 'FontSize', 7);
    end
    plot(out.cg_x, out.cg_z, 'kp', 'MarkerSize', 16, 'MarkerFaceColor', 'y');
    text(out.cg_x, out.cg_z - 60, sprintf('CG %.0f, %.0f mm, %.0f %% front', out.cg_x, out.cg_z, 100 * out.wd_front), 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    xlabel('x from the front axle (mm)'); ylabel('z above the ground (mm)');
    title(sprintf('Mass budget%s: %.1f kg car, %.1f kg with driver. Green CALC, blue CATALOGUE, orange ESTIMATE, red GUESS (%.0f %% of the mass)', ...
        ternary(isempty(opts.moves), '', ' (items moved)'), out.mass_car, out.mass_total, 100 * out.guess_fraction));
    xlim([-800 2400]); ylim([-100 1500]);
    save_fig(fig, 'mass_budget');
end
end

% ------------------------------------------------------------------------
function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function flags = read_flags(file)
% First word of the comment on each "m_*" / "mass_driver" line, if it is a known flag.
flags = containers.Map('KeyType', 'char', 'ValueType', 'char');
lines = splitlines(string(fileread(file)));
for k = 1:numel(lines)
    tok = regexp(lines(k), '^\s*"(m_[A-Za-z0-9_]+|mass_driver)"\s*=[^'']*''\s*([A-Z]+)', 'tokens', 'once');
    if ~isempty(tok) && ismember(tok(2), ["CALC", "CATALOGUE", "ESTIMATE", "GUESS"])
        flags(char(tok(1))) = char(tok(2));
    end
end
end

function ok = selftest()
% Hand check with a three-item file (same expression form as the real file):
%   a 10 kg at (0, 100) CALC, b 30 kg at (1000, 300) GUESS, driver 60 kg at (500, 200)
%   mass_car = 40, total = 100
%   cg_x = (0 + 30000 + 30000) / 100 = 600,  cg_z = (1000 + 9000 + 12000) / 100 = 220
%   wheelbase 1500 -> weight_dist_front = 1 - 600 / 1500 = 0.6
%   guess fraction = 30 / 100 = 0.3
tmp = [tempname '.txt'];
fid = fopen(tmp, 'w');
fprintf(fid, '%s\n', ...
    '"wheelbase"= 1500', ...
    '"m_a"= 10        '' CALC something', ...
    '"x_a"= 0', '"z_a"= 100', ...
    '"m_b"= 30        '' GUESS something else', ...
    '"x_b"= 1000', '"z_b"= 300', ...
    '"mass_driver"= 60   '' ESTIMATE', ...
    '"x_driver"= 500', '"z_driver"= 200', ...
    '"mass_car"= "m_a" + "m_b"', ...
    '"cg_x_from_front_axle"= ("m_a" * "x_a" + "m_b" * "x_b" + "mass_driver" * "x_driver") / ("mass_car" + "mass_driver")', ...
    '"cg_height"= ("m_a" * "z_a" + "m_b" * "z_b" + "mass_driver" * "z_driver") / ("mass_car" + "mass_driver")', ...
    '"weight_dist_front"= 1 - "cg_x_from_front_axle" / "wheelbase"');
fclose(fid);
o = mass_budget(struct('file', tmp, 'plot', false, 'write', false));
ok = abs(o.mass_car - 40) < 1e-9 && abs(o.mass_total - 100) < 1e-9 && abs(o.cg_x - 600) < 1e-9 ...
    && abs(o.cg_z - 220) < 1e-9 && abs(o.wd_front - 0.6) < 1e-12 && abs(o.guess_fraction - 0.3) < 1e-12 ...
    && o.file_agrees && o.items.flag(1) == "CALC" && o.items.flag(2) == "GUESS";
% move b from x 1000 to x 0: cg_x = (0 + 0 + 30000) / 100 = 300, cg_z unchanged 220
o2 = mass_budget(struct('file', tmp, 'plot', false, 'write', false, 'moves', {{'b', 0, 300}}));
delete(tmp);
ok = ok && abs(o2.cg_x - 300) < 1e-9 && abs(o2.cg_z - 220) < 1e-9 && o2.items.flag(2) == "GUESS*";
% the committed file must agree with its own item list and give a plausible car
r = mass_budget(struct('plot', false, 'write', false));
ok = ok && r.file_agrees && r.mass_car > 150 && r.mass_car < 300 && r.wd_front > 0.3 && r.wd_front < 0.6;
if ok
    fprintf('mass_budget self-test: PASS (3-item file: car 40 kg, CG 600 / 220 mm, 60 %% front, guess 30 %%; b moved to x 0 -> CG 300; real file %.1f kg, %.1f %% front)\n', ...
        r.mass_car, 100 * r.wd_front);
else
    error('mass_budget self-test: FAIL');
end
end
