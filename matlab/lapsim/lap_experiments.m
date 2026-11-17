function out = lap_experiments(opts)
%LAP_EXPERIMENTS Ring 6 experiments: variants, aero sweep, following-car
%   penalty and sensitivity on the two main tracks.
%   out = lap_experiments()            full run, figures to media/
%   out = lap_experiments(opts)        opts.quick = true for a coarse sweep
%   lap_experiments('--selftest')
%
%   1. Lap time for variants A to D on skidpad, acceleration, autocross and
%      the fast circuit. Speed-versus-distance plots per track.
%   2. Sweep of ClA against CdA: contour of lap time on each track with the
%      variants marked.
%   3. Following-car penalty: downforce scaled by the dirty-air dynamic
%      pressure ratio from cfd/results/wake_cfd.csv (cfd/postprocess.py) or
%      cfd/results/wake_summary.csv (one car length), or
%      an assumed 0.70 if no CFD exists yet.
%   4. Sensitivity: plus or minus 10 % on mass, power and grip.
%   5. Aero source, before and after: every variant with the first guesses
%      in car_params.txt (ClA_<v>, CdA_<v>, aero_balance_front) against the
%      variant table params/aero_variants.csv (pre-CFD estimate now, CFD
%      later; edit that one file to change what the lap sim uses), point-mass
%      and four-wheel corner limit, plus the lap-time span of the table's
%      ClA / CdA range.
%   Writes media/lap_times.csv, media/lap_aero_before_after.csv and
%   media/results_table.md.

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'quick'), opts.quick = false; end
if ~isfield(opts, 'plot'), opts.plot = true; end
p = read_car_params();
variants = {'A', 'B', 'C', 'D'};
trackNames = {'skidpad', 'accel_75m', 'autocross', 'fast_circuit'};
tracks = cellfun(@load_track, trackNames);
mediaDir = fullfile(repo_root(), 'media');
if ~isfolder(mediaDir), mkdir(mediaDir); end

% ---- 1. variants --------------------------------------------------------------
lapT = zeros(numel(tracks), numel(variants));
runs = cell(numel(tracks), numel(variants));
for i = 1:numel(tracks)
    for k = 1:numel(variants)
        car = car_from_params(variants{k}, p);
        runs{i, k} = lapsim(car, tracks(i));
        lapT(i, k) = runs{i, k}.t_lap;
    end
end
T = array2table(lapT, 'VariableNames', strcat('t_', variants), 'RowNames', trackNames);
T.gain_wings_s = lapT(:, 1) - lapT(:, 3);      % A minus C: what the wings are worth
out.lap_times = T;
if opts.plot
    writetable(T, fullfile(mediaDir, 'lap_times.csv'), 'WriteRowNames', true);
    for i = 3:4   % the two real tracks
        fig = figure('Name', ['speed ' trackNames{i}], 'Position', [100 100 1000 650]);
        subplot(3, 1, [1 2]); hold on
        for k = 1:numel(variants)
            plot(runs{i, k}.s, runs{i, k}.v * 3.6, 'LineWidth', 1.2, 'DisplayName', ...
                sprintf('%s: %.2f s (ClA %.1f, CdA %.2f)', variants{k}, lapT(i, k), runs{i, k}.car.ClA, runs{i, k}.car.CdA));
        end
        grid on; ylabel('Speed (km/h)'); legend('Location', 'best');
        title(sprintf('%s (%.0f m): speed against distance, variants A-D', strrep(trackNames{i}, '_', ' '), tracks(i).total_m));
        subplot(3, 1, 3);
        plot(runs{i, 3}.x, runs{i, 3}.y, 'k-', 'LineWidth', 1); axis equal; grid on
        xlabel('x (m)'); ylabel('y (m)'); title('Centreline (from the segment list)');
        save_fig(fig, ['speed_vs_distance_' trackNames{i}]);
    end
end

% ---- 2. ClA / CdA sweep -------------------------------------------------------
if opts.quick, nG = 7; else, nG = 13; end
ClA_g = linspace(0, 6, nG); CdA_g = linspace(0.5, 2.0, nG);
sweep = struct();
for i = 3:4
    Z = zeros(nG, nG);
    for a = 1:nG
        for d = 1:nG
            car = car_from_params('C', p); car.ClA = ClA_g(a); car.CdA = CdA_g(d);
            Z(d, a) = lapsim(car, tracks(i), struct('ds', 1)).t_lap;
        end
    end
    sweep.(trackNames{i}) = struct('ClA', ClA_g, 'CdA', CdA_g, 't', Z);
    if opts.plot
        fig = figure('Name', ['sweep ' trackNames{i}], 'Position', [100 100 800 600]);
        levels = round(linspace(min(Z(:)), max(Z(:)), 12), 1);
        contourf(ClA_g, CdA_g, Z, 24, 'LineStyle', 'none'); colorbar; hold on
        contour(ClA_g, CdA_g, Z, levels, 'k', 'ShowText', 'on', 'LabelFormat', '%.1f s');
        for k = 1:numel(variants)
            car = car_from_params(variants{k}, p);
            plot(car.ClA, car.CdA, 'wo', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
            text(car.ClA + 0.1, car.CdA, variants{k}, 'Color', 'w', 'FontWeight', 'bold');
        end
        xlabel('ClA (m^2)'); ylabel('CdA (m^2)');
        title(sprintf('%s: lap time (s) against downforce and drag', strrep(trackNames{i}, '_', ' ')));
        save_fig(fig, ['laptime_contour_' trackNames{i}]);
    end
end
out.sweep = sweep;

% ---- 3. following-car penalty -------------------------------------------------
qratio = 0.70; qsrc = 'assumed (no CFD yet)';
cfdWake = fullfile(repo_root(), 'cfd', 'results', 'wake_cfd.csv');      % cfd/postprocess.py, window average
wakeFile = fullfile(repo_root(), 'cfd', 'results', 'wake_summary.csv');  % matlab/cfd/wake_postprocess.m
if isfile(cfdWake)
    W = readtable(cfdWake, 'TextType', 'string');
    sel = W.plane_L == 1 & W.run == "C";          % the final C run (run name = variant name)
    if any(sel)
        qratio = mean(W.q_ratio(sel)); qsrc = 'CFD, cfd/results/wake_cfd.csv, variant C at 1 L';
    end
end
if strcmp(qsrc, 'assumed (no CFD yet)') && isfile(wakeFile)
    W = readtable(wakeFile);
    sel = W.plane_lengths == 1 & strcmp(string(W.variant), "C");
    if any(sel)
        qratio = mean(W.q_ratio(sel)); qsrc = 'cfd/results/wake_summary.csv, variant C at 1 L';
    end
end
follow = zeros(2, 1);
for i = 3:4
    car = car_from_params('C', p); car.ClA = car.ClA * qratio;
    follow(i - 2) = lapsim(car, tracks(i)).t_lap - lapT(i, 3);
end
out.following = table(trackNames(3:4).', follow, 'VariableNames', {'track', 'penalty_s'});
out.q_ratio = qratio; out.q_ratio_source = qsrc;

% ---- 4. sensitivity ----------------------------------------------------------------
sens = zeros(3, 2, 2);  % parameter x (minus, plus) x track
names = {'mass', 'power', 'grip'};
for i = 3:4
    for jp = 1:3
        for sgn = 1:2
            car = car_from_params('C', p);
            fac = 1 + (sgn * 2 - 3) * 0.10;
            switch jp
                case 1, car.m = car.m * fac;
                case 2, car.P_max = car.P_max * fac; car.F_torque_max = car.F_torque_max * fac;
                case 3, car.mu0 = car.mu0 * fac;
            end
            sens(jp, sgn, i - 2) = lapsim(car, tracks(i)).t_lap - lapT(i, 3);
        end
    end
end
out.sensitivity = sens;
if opts.plot
    fig = figure('Name', 'sensitivity', 'Position', [100 100 800 450]);
    for i = 1:2
        subplot(1, 2, i)
        barh([sens(:, 1, i), sens(:, 2, i)]); set(gca, 'YTickLabel', names); grid on
        xlabel('Lap time change (s)'); legend({'-10 %', '+10 %'}, 'Location', 'best');
        title(strrep(trackNames{i + 2}, '_', ' '));
    end
    save_fig(fig, 'sensitivity');
end

% ---- 5. aero source: before against the variant table -----------------------------------
% before = params/aero_variants_estimate.csv (the pre-CFD estimate, saved by
% cfd/postprocess.py --update-variants before it writes CFD rows) when it
% exists, otherwise the first guesses in car_params.txt
estFile = fullfile(repo_root(), 'params', 'aero_variants_estimate.csv');
if isfile(estFile), beforeSrc = estFile; beforeName = 'the pre-CFD estimate (`params/aero_variants_estimate.csv`)';
else, beforeSrc = 'params'; beforeName = 'the first guesses in `params/car_params.txt` (`ClA_<v>`, `CdA_<v>`, `aero_balance_front`)'; end
baRows = {};
srcNote = strings(1, numel(variants));
for k = 1:numel(variants)
    c0 = car_from_params(variants{k}, p, beforeSrc);
    c1 = car_from_params(variants{k}, p);
    srcNote(k) = string(c1.aero_source);
    for i = 3:4
        t0 = lapsim(c0, tracks(i)).t_lap; t1 = lapT(i, k);
        f0 = lapsim(c0, tracks(i), struct('four_wheel', true)).t_lap;
        f1 = lapsim(c1, tracks(i), struct('four_wheel', true)).t_lap;
        tBest = NaN; tWorst = NaN;
        if all(~isnan([c1.ClA_range c1.CdA_range]))
            cb = c1; cb.ClA = c1.ClA_range(2); cb.CdA = c1.CdA_range(1);
            cw = c1; cw.ClA = c1.ClA_range(1); cw.CdA = c1.CdA_range(2);
            tBest = lapsim(cb, tracks(i)).t_lap; tWorst = lapsim(cw, tracks(i)).t_lap;
        end
        baRows(end+1, :) = {variants{k}, trackNames{i}, c0.ClA, c0.CdA, c0.aero_front, c1.ClA, c1.CdA, c1.aero_front, t0, t1, t1 - t0, f0, f1, f1 - f0, tBest, tWorst}; %#ok<AGROW>
    end
end
out.before_after = cell2table(baRows, 'VariableNames', {'variant', 'track', 'ClA_before', 'CdA_before', 'front_before', 'ClA_after', 'CdA_after', 'front_after', ...
    't_before_s', 't_after_s', 'change_s', 't4w_before_s', 't4w_after_s', 'change_4w_s', 't_after_best_s', 't_after_worst_s'});
out.aero_source = srcNote;

% ---- results table ---------------------------------------------------------------------
if opts.plot
    fid = fopen(fullfile(mediaDir, 'results_table.md'), 'w');
    fprintf(fid, '# Lap simulation results\n\nGenerated by `matlab/lapsim/lap_experiments.m` on %s from `params/car_params.txt`.\n', datestr(now, 'yyyy-mm-dd HH:MM'));
    fprintf(fid, 'Aero values come from `params/aero_variants.csv` (A: %s; B: %s; C: %s; D: %s). Nothing in that table is measured unless its source says CFD.\n\n', srcNote);
    writetable(out.before_after, fullfile(mediaDir, 'lap_aero_before_after.csv'));
    fprintf(fid, '| Track | A (no wings) | B (moderate) | C (max) | D (wake-tuned) | Wings worth (A-C) |\n|---|---|---|---|---|---|\n');
    for i = 1:numel(trackNames)
        fprintf(fid, '| %s | %.2f s | %.2f s | %.2f s | %.2f s | %.2f s |\n', strrep(trackNames{i}, '_', ' '), lapT(i, :), lapT(i, 1) - lapT(i, 3));
    end
    fprintf(fid, '\n**Following-car penalty** (variant C with downforce scaled by q-ratio %.2f, %s): autocross +%.2f s, fast circuit +%.2f s.\n\n', ...
        qratio, qsrc, follow(1), follow(2));
    fprintf(fid, '**Sensitivity of variant C** (lap time change for -10 %% / +10 %%):\n\n| Parameter | Autocross | Fast circuit |\n|---|---|---|\n');
    for jp = 1:3
        fprintf(fid, '| %s | %+.2f / %+.2f s | %+.2f / %+.2f s |\n', names{jp}, sens(jp, 1, 1), sens(jp, 2, 1), sens(jp, 1, 2), sens(jp, 2, 2));
    end
    B = out.before_after;
    fprintf(fid, '\n## Aero source, before and after\n\nBefore = %s. After = `params/aero_variants.csv`, the table the lap sim now reads. Best / worst = the table''s range (highest ClA with lowest CdA, and the reverse), point-mass. The four-wheel columns use the corner limit of `cornering_balance.m`, where the front share matters.\n\n', beforeName);
    fprintf(fid, '| Variant | Track | ClA / CdA / front before | after | point-mass before (s) | after (s) | change (s) | best to worst (s) | four-wheel before (s) | after (s) | change (s) |\n|---|---|---|---|---|---|---|---|---|---|---|\n');
    for r = 1:height(B)
        fprintf(fid, '| %s | %s | %.2f / %.2f / %.2f | %.2f / %.2f / %.2f | %.2f | %.2f | %+.2f | %.2f to %.2f | %.2f | %.2f | %+.2f |\n', B.variant{r}, strrep(B.track{r}, '_', ' '), ...
            B.ClA_before(r), B.CdA_before(r), B.front_before(r), B.ClA_after(r), B.CdA_after(r), B.front_after(r), B.t_before_s(r), B.t_after_s(r), B.change_s(r), ...
            B.t_after_best_s(r), B.t_after_worst_s(r), B.t4w_before_s(r), B.t4w_after_s(r), B.change_4w_s(r));
    end
    fprintf(fid, '\nPoint-mass model: no weight transfer, no transients, perfect driver. Use for comparing setups, not for predicting a real lap.\n');
    fclose(fid);
    fprintf('lap_experiments: media/lap_times.csv, results_table.md and figures written\n');
    disp(T);
    fprintf('Following-car penalty (q-ratio %.2f, %s): autocross +%.2f s, fast circuit +%.2f s\n', qratio, qsrc, follow(1), follow(2));
    fprintf('Aero source before (%s) and after (params/aero_variants.csv):\n', beforeName); disp(out.before_after);
end
end

function ok = selftest()
% Hand-checkable ordering, not a number: on the fast circuit more downforce
% must never make the car slower when drag is held fixed, and on every track
% the no-wing car A must be slower than C in the committed parameter set.
p = read_car_params();
tr = load_track('fast_circuit');
c0 = car_from_params('C', p); c0.ClA = 0;
c1 = car_from_params('C', p); c1.ClA = 3;
t0 = lapsim(c0, tr, struct('ds', 2)).t_lap; t1 = lapsim(c1, tr, struct('ds', 2)).t_lap;
ok = t1 < t0;
tr2 = load_track('autocross');
tA = lapsim(car_from_params('A', p), tr2, struct('ds', 2)).t_lap;
tC = lapsim(car_from_params('C', p), tr2, struct('ds', 2)).t_lap;
ok = ok && tC < tA;
if ok
    fprintf('lap_experiments self-test: PASS (fast circuit %.2f s -> %.2f s with ClA 0 -> 3; autocross A %.2f s, C %.2f s)\n', t0, t1, tA, tC);
else
    error('lap_experiments self-test: FAIL');
end
end
