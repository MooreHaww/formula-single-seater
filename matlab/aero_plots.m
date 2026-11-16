function S = aero_plots(opts)
%AERO_PLOTS Ring 5: coefficients and the drag-against-downforce plot.
%   S = aero_plots()           reads cfd/results/forces.csv, writes
%                              cfd/results/aero_summary.csv and media/aero_drag_vs_downforce.png
%   aero_plots('--selftest')
%
%   Input cfd/results/forces.csv (one row per CFD run, see cfd/README.md):
%     variant, speed_mps, downforce_N, drag_N, downforce_front_N, cells, note
%   Half-car runs must already be doubled to full-car forces (the Fluent
%   journal reports full-car values via the symmetry setting; check the
%   guide). Rows with the same variant and different speed or cells are the
%   speed and mesh checks and get reported as percent changes.
%   If the file is missing, the parameter-file estimates are plotted instead
%   and labelled as such, so the plot exists before the CFD does.
%
%   Outputs per variant: ClA = DF / (0.5 rho v^2), CdA = D / (0.5 rho v^2),
%   L/D = DF / D, front balance = DF_front / DF.
%   Hand check: 1000 N at 20 m/s, rho 1.2 -> ClA = 1000 / (0.5*1.2*400) = 4.1667 m2

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    S = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'file'), opts.file = fullfile(repo_root(), 'cfd', 'results', 'forces.csv'); end
p = read_car_params();
rho = p.air_density;
if isfile(opts.file)
    F = readtable(opts.file, 'TextType', 'string'); src = 'CFD';
else
    v = p.cfd_speed; q = 0.5 * rho * v^2;
    vars = ["A"; "B"; "C"; "D"];
    F = table(vars, repmat(v, 4, 1), q * [p.ClA_A; p.ClA_B; p.ClA_C; p.ClA_D], q * [p.CdA_A; p.CdA_B; p.CdA_C; p.CdA_D], ...
        q * p.aero_balance_front * [p.ClA_A; p.ClA_B; p.ClA_C; p.ClA_D], zeros(4, 1), repmat("parameter-file estimate", 4, 1), ...
        'VariableNames', {'variant', 'speed_mps', 'downforce_N', 'drag_N', 'downforce_front_N', 'cells', 'note'});
    src = 'ESTIMATES (no CFD yet)';
    warning('aero_plots:estimates', 'No %s, plotting the parameter-file estimates', opts.file);
end
q = 0.5 * rho * F.speed_mps.^2;
F.ClA = F.downforce_N ./ q;
F.CdA = F.drag_N ./ q;
F.L_over_D = F.downforce_N ./ F.drag_N;
F.front_balance = F.downforce_front_N ./ F.downforce_N;
S.table = F; S.source = src;

% baseline rows: for each variant the row at cfd_speed with the most cells
vars = unique(F.variant, 'stable');
base = table();
for k = 1:numel(vars)
    sel = F(F.variant == vars(k), :);
    atSpeed = sel(abs(sel.speed_mps - p.cfd_speed) < 0.5, :);
    if isempty(atSpeed), atSpeed = sel; end
    [~, i] = max(atSpeed.cells);
    base = [base; atSpeed(i, :)]; %#ok<AGROW>
end
S.baseline = base;

% checks: mesh and speed sensitivity (percent change in ClA and CdA)
checks = strings(0, 1);
for k = 1:numel(vars)
    sel = F(F.variant == vars(k), :);
    b = base(base.variant == vars(k), :);
    for r = 1:height(sel)
        if sel.cells(r) == b.cells && sel.speed_mps(r) == b.speed_mps, continue, end
        checks(end+1, 1) = sprintf('%s: %s %g -> ClA %+.1f %%, CdA %+.1f %%', vars(k), ...
            ternary(sel.cells(r) ~= b.cells, 'cells', 'speed'), ternary(sel.cells(r) ~= b.cells, sel.cells(r), sel.speed_mps(r)), ...
            100 * (sel.ClA(r) / b.ClA - 1), 100 * (sel.CdA(r) / b.CdA - 1)); %#ok<AGROW>
    end
end
S.checks = checks;

if opts.plot
    outDir = fullfile(repo_root(), 'cfd', 'results');
    if ~isfolder(outDir), mkdir(outDir); end
    writetable(F, fullfile(outDir, 'aero_summary.csv'));
    fig = figure('Name', 'aero', 'Position', [100 100 800 600]); hold on
    for k = 1:height(base)
        plot(base.downforce_N(k), base.drag_N(k), 'o', 'MarkerSize', 9, 'MarkerFaceColor', 'r', 'Color', 'k');
        text(base.downforce_N(k), base.drag_N(k) + 15, sprintf('%s  ClA %.2f, CdA %.2f, L/D %.1f', base.variant(k), base.ClA(k), base.CdA(k), base.L_over_D(k)), ...
            'HorizontalAlignment', 'center');
    end
    xlabel(sprintf('Downforce at %g m/s (N)', p.cfd_speed)); ylabel(sprintf('Drag at %g m/s (N)', p.cfd_speed)); grid on; box on
    xl = xlim; xlim([min(0, xl(1)) xl(2) * 1.1]); yl = ylim; ylim([0 yl(2) * 1.15]);
    title({'Drag against downforce per aero variant', ['Source: ' src]});
    save_fig(fig, 'aero_drag_vs_downforce');
    fprintf('aero_plots (%s):\n', src); disp(base(:, {'variant', 'speed_mps', 'ClA', 'CdA', 'L_over_D', 'front_balance'}));
    if ~isempty(checks), fprintf('  %s\n', checks); end
end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function ok = selftest()
tmp = [tempname '.csv'];
T = table(["X"; "X"; "X"], [20; 20; 30], [1000; 1050; 2250], [400; 410; 900], [450; 470; 1010], [900000; 450000; 900000], ["base"; "half mesh"; "speed check"], ...
    'VariableNames', {'variant', 'speed_mps', 'downforce_N', 'drag_N', 'downforce_front_N', 'cells', 'note'});
writetable(T, tmp);
S = aero_plots(struct('plot', false, 'file', tmp));
delete(tmp);
b = S.baseline;
ok = abs(b.ClA - 1000 / (0.5 * 1.2 * 400)) < 1e-9 && abs(b.CdA - 400 / 240) < 1e-9 && abs(b.front_balance - 0.45) < 1e-9 ...
    && b.cells == 900000 && b.speed_mps == 20 && numel(S.checks) == 2;
if ok
    fprintf('aero_plots self-test: PASS (ClA %.4f m2 for 1000 N at 20 m/s; mesh and speed checks: %s | %s)\n', b.ClA, S.checks(1), S.checks(2));
else
    error('aero_plots self-test: FAIL');
end
end
