function summary = run_all(mode)
%RUN_ALL One entry point: self-tests, then every analysis, then a summary.
%   run_all               everything (self-tests + full analyses, ~1 to 2 min)
%   run_all('test')       self-tests only (fast, no figures)
%   run_all('quick')      self-tests + analyses with a coarse aero sweep
%
%   Runs clean from a fresh MATLAB session: cd to the repo (or anywhere) and
%   call  run('matlab/run_all.m')  or add matlab/ to the path and type run_all.
%   Outputs go to media/ (figures, lap_times.csv, results_table.md),
%   sim/stress/load_cases.csv and cfd/results/.
%   Scripts that depend on data not yet produced (motion study CSVs, CFD
%   forces and wake planes) run on synthetic data or estimates and say so.

if nargin < 1, mode = 'full'; end
addpath(fullfile(fileparts(mfilename('fullpath')), 'common'));
setup_paths();
t0 = tic;
fprintf('==== Formula Single-Seater run_all (%s) ====\n', mode);
fprintf('Repo: %s\n', repo_root());

% ---- self-tests ---------------------------------------------------------------
tests = {'read_car_params', 'car_from_params', 'long_forces', 'accel_test', 'make_airfoils', ...
    'load_track', 'lapsim', 'cornering_speed_vs_downforce', 'lap_experiments', ...
    'suspension_plots', 'load_cases', 'aero_plots', 'wake_postprocess'};
hasSimulink = license('test', 'Simulink') && ~isempty(ver('simulink'));
if hasSimulink, tests{end+1} = 'run_accel_simulink'; end
results = struct('name', tests, 'pass', num2cell(false(size(tests))), 'msg', '');
fprintf('\n-- Self-tests (%d) --\n', numel(tests));
for k = 1:numel(tests)
    try
        feval(tests{k}, '--selftest');
        results(k).pass = true;
    catch ME
        results(k).pass = false; results(k).msg = ME.message;
        fprintf('  FAIL %s: %s\n', tests{k}, ME.message);
    end
end
nPass = nnz([results.pass]);
fprintf('-- Self-tests: %d / %d passed --\n', nPass, numel(tests));
summary.tests = results;
if strcmp(mode, 'test')
    summary.elapsed_s = toc(t0);
    return
end

% ---- analyses ---------------------------------------------------------------------
fprintf('\n-- Analyses --\n');
close all
summary.params = read_car_params();
summary.airfoils = make_airfoils();
summary.accel = accel_test('C');
summary.cornering = cornering_speed_vs_downforce();
summary.lap = lap_experiments(struct('quick', strcmp(mode, 'quick')));
summary.loads = load_cases();
summary.suspension = suspension_plots();
summary.aero = aero_plots();
summary.wake = wake_postprocess();
if hasSimulink
    summary.simulink = run_accel_simulink('C');
end

% ---- headline numbers -----------------------------------------------------------------
fprintf('\n==== Headline numbers ====\n');
lt = summary.lap.lap_times;
fprintf('0-100 km/h (C):            %.2f s\n', summary.accel.t_100);
fprintf('75 m acceleration (C):     %.2f s', summary.accel.t_75);
if hasSimulink, fprintf('   Simulink %.2f s (%+.2f %%)', summary.simulink.t_75_simulink, summary.simulink.diff_pct); end
fprintf('\n');
fprintf('Skidpad lap (C):           %.2f s\n', lt{'skidpad', 't_C'});
fprintf('Autocross A / B / C / D:   %.2f / %.2f / %.2f / %.2f s  (wings worth %.2f s)\n', lt{'autocross', 1:4}, lt{'autocross', 'gain_wings_s'});
fprintf('Fast circuit A / B / C / D: %.2f / %.2f / %.2f / %.2f s (wings worth %.2f s)\n', lt{'fast_circuit', 1:4}, lt{'fast_circuit', 'gain_wings_s'});
fprintf('Following one car length (q-ratio %.2f, %s): autocross +%.2f s, fast circuit +%.2f s\n', ...
    summary.lap.q_ratio, summary.lap.q_ratio_source, summary.lap.following.penalty_s);
T = summary.cornering;
for R = [60 120]
    fprintf('Max speed, R = %3d m corner, A / C: %.0f / %.0f km/h\n', R, T.v_max_kmh(T.radius_m == R & T.variant == "A"), T.v_max_kmh(T.radius_m == R & T.variant == "C"));
end
fprintf('Aero source: %s\n', summary.aero.source);
fprintf('Suspension data: %s\n', ternary(summary.suspension.front.synthetic, 'SYNTHETIC (no motion study yet)', 'from sim/motion CSVs'));
summary.elapsed_s = toc(t0);
fprintf('run_all finished in %.0f s, figures in media/\n', summary.elapsed_s);
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
