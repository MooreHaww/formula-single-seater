function out = support_sensitivity(opts)
%SUPPORT_SENSITIVITY Lap times and cornering balance: CP_bl1 against CPF (CP with
%   the F rear-wing supports, docs/wing_supports_plan.md). A sensitivity result
%   for the next version of the car, not the released car: the CAD has no
%   wing supports, and CP stays the default everywhere.
%
%   out = support_sensitivity()        writes media/support_sensitivity.md and .csv
%   out = support_sensitivity(opts)    opts.write (true)
%   support_sensitivity('--selftest')
%
%   Both cars are car_from_params with the same parameter file, tyre model,
%   roll centres and lap-sim settings. Only ClA, CdA and aero_front differ:
%     CP_bl1  CP's row with the numbers of run CP_bl1 (CP meshed with 1 prism
%             layer, ClA 3.977, CdA 1.667, front 0.431; built in memory, the
%             CP row of params/aero_variants.csv is not changed)
%     CPF     row CPF of params/aero_variants.csv (run F_bl1, also 1 layer)
%   so the pair is like for like (same mesh settings). CP's own run-to-run
%   spread in ClA is about 2.2 % (CP vs CP_bl1).
%   Lap times: lapsim point-mass and four-wheel on skidpad, autocross, fast
%   circuit. Balance: cornering_balance_study at the file's weight
%   distribution and each car's own front aero share, radii 45 and 100 m,
%   plus the neutral front share per radius.

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'write'), opts.write = true; end
p = read_car_params();
V = read_aero_variants();
Vb = V; i = find(Vb.variant == "CP");
Vb.ClA(i) = 3.977; Vb.CdA(i) = 1.667; Vb.aero_front(i) = 0.431;
Vb.source(i) = "CFD CP_bl1 (in memory, support_sensitivity.m)";
cars = {car_from_params('CP', p, Vb), car_from_params('CPF', p, V)};
names = {'CP_bl1', 'CPF'};
srcs = {Vb, V};
vars = {'CP', 'CPF'};
tracks = {'skidpad', 'autocross', 'fast_circuit'};

% the 2.2 % band: CP_bl1 with ClA or CdA raised, or its front share lowered, by
% SPREAD (one at a time); the band is the largest resulting change
SPREAD = 0.022;
c0 = cars{1};
cl = c0; cl.ClA = c0.ClA * (1 + SPREAD);
cd = c0; cd.CdA = c0.CdA * (1 + SPREAD);
ca = c0; ca.aero_front = c0.aero_front * (1 - SPREAD);
rows = {};
for t = 1:numel(tracks)
    tr = load_track(tracks{t});
    for fw = [false true]
        o = struct('four_wheel', fw);
        t0 = lapsim(cars{1}, tr, o).t_lap; t1 = lapsim(cars{2}, tr, o).t_lap;
        band = max(abs([lapsim(cl, tr, o).t_lap, lapsim(cd, tr, o).t_lap, lapsim(ca, tr, o).t_lap] - t0));
        rows(end+1, :) = {tracks{t}, tern(fw, 'four-wheel', 'point-mass'), t0, t1, t1 - t0, band, abs(t1 - t0) > band}; %#ok<AGROW>
    end
end
L = cell2table(rows, 'VariableNames', {'track', 'model', 't_CP_bl1_s', 't_CPF_s', 'diff_s', 'band_2p2_s', 'beyond_band'});

bbal = zeros(1, 2);
for j = 1:2
    R = 45 + 55 * (j - 1);                       % 45 and 100 m, the study's radii
    b0 = cornering_balance(c0, R).balance_pct;
    bbal(j) = max(abs([cornering_balance(cl, R).balance_pct, cornering_balance(cd, R).balance_pct, cornering_balance(ca, R).balance_pct] - b0));
end
bal = {};
for k = 1:2
    [~, b] = evalc('cornering_balance_study(struct(''plot'', false, ''write'', false, ''laps'', false, ''variant'', vars{k}, ''aero_source'', srcs{k}, ''wd'', NaN, ''aero'', cars{k}.aero_front))');
    for r = 1:height(b.T)
        n = b.target.T.aero_front_neutral(b.target.T.radius_m == b.T.radius_m(r));
        bal(end+1, :) = {names{k}, b.T.radius_m(r), b.T.aero_front(r), b.T.v_grip_kmh(r), b.T.v_max_kmh(r), ...
            char(b.T.limiting_axle(r)), b.T.balance_pct(r), n, bbal(1 + (b.T.radius_m(r) == 100))}; %#ok<AGROW>
    end
end
B = cell2table(bal, 'VariableNames', {'car', 'radius_m', 'aero_front', 'v_grip_kmh', 'v_max_kmh', 'limiting_axle', 'balance_pct', 'aero_front_neutral', 'balance_band_2p2_pct'});

out.cars = cars; out.lap = L; out.balance = B;
out.aero = table(string(names'), [cars{1}.ClA; cars{2}.ClA], [cars{1}.CdA; cars{2}.CdA], [cars{1}.aero_front; cars{2}.aero_front], ...
    'VariableNames', {'car', 'ClA', 'CdA', 'aero_front'});
disp(out.aero); disp(L); disp(B);

if opts.write
    md = fullfile(repo_root(), 'media');
    writetable(L, fullfile(md, 'support_sensitivity_laps.csv'));
    writetable(B, fullfile(md, 'support_sensitivity_balance.csv'));
    fid = fopen(fullfile(md, 'support_sensitivity.md'), 'w');
    fprintf(fid, '# Rear-wing supports F: lap-time and balance sensitivity (CP_bl1 vs CPF)\n\n');
    fprintf(fid, 'Written by `matlab/lapsim/support_sensitivity.m`. **A sensitivity result for the next version, not the released car**: the CAD has no wing supports and CP stays the default. ');
    fprintf(fid, 'Both cars come from runs meshed with 1 prism layer (CP_bl1, F_bl1); everything else (mass, tyres, roll centres, lap-sim settings) is the same. ');
    fprintf(fid, 'CP''s own run-to-run aero spread is about 2.2 %% in ClA; only the ranking of CFD variants is trustworthy. ');
    fprintf(fid, '**Band** = the largest change in that result when CP_bl1''s ClA or CdA is raised, or its front share lowered, by 2.2 %% (one at a time); a difference inside the band is not claimed.\n\n');
    fprintf(fid, '| car | ClA | CdA | front share |\n|---|---|---|---|\n');
    for k = 1:2
        fprintf(fid, '| %s | %.3f | %.3f | %.3f |\n', names{k}, cars{k}.ClA, cars{k}.CdA, cars{k}.aero_front);
    end
    fprintf(fid, '| change | %+.1f %% | %+.1f %% | %+.3f |\n\n', 100 * (cars{2}.ClA / cars{1}.ClA - 1), 100 * (cars{2}.CdA / cars{1}.CdA - 1), cars{2}.aero_front - cars{1}.aero_front);
    fprintf(fid, '| track | model | CP_bl1 (s) | CPF (s) | CPF - CP_bl1 (s) | 2.2 %% band (s) | beyond the band |\n|---|---|---|---|---|---|---|\n');
    for r = 1:height(L)
        fprintf(fid, '| %s | %s | %.3f | %.3f | %+.3f | %.3f | %s |\n', strrep(L.track{r}, '_', ' '), L.model{r}, L.t_CP_bl1_s(r), L.t_CPF_s(r), L.diff_s(r), L.band_2p2_s(r), tern(L.beyond_band(r), 'yes', 'no'));
    end
    fprintf(fid, '\n| car | R (m) | front aero | v grip (km/h) | v max (km/h) | limits | balance (%%) | neutral front aero | balance 2.2 %% band (points) |\n|---|---|---|---|---|---|---|---|---|\n');
    for r = 1:height(B)
        fprintf(fid, '| %s | %d | %.3f | %.1f | %.1f | %s | %+.1f | %.3f | %.1f |\n', B.car{r}, B.radius_m(r), B.aero_front(r), B.v_grip_kmh(r), B.v_max_kmh(r), B.limiting_axle{r}, B.balance_pct(r), B.aero_front_neutral(r), B.balance_band_2p2_pct(r));
    end
    fprintf(fid, '\nBalance = front-axle use minus rear-axle use at the limit (positive = understeer). Weight distribution, CG, roll centres and tyres as filed for both cars.\n');
    fclose(fid);
end
end

function ok = selftest()
% Hand check: the same aero numbers give the same lap time (difference 0),
% and more downforce at equal drag cannot make the autocross slower.
p = read_car_params();
tr = load_track('autocross');
c0 = car_from_params('CP', p); c1 = c0;
t0 = lapsim(c0, tr, struct('ds', 2)).t_lap; t1 = lapsim(c1, tr, struct('ds', 2)).t_lap;
c2 = c0; c2.ClA = c0.ClA * 1.05;
t2 = lapsim(c2, tr, struct('ds', 2)).t_lap;
ok = abs(t1 - t0) < 1e-12 && t2 <= t0;
V = read_aero_variants();
ok = ok && any(V.variant == "CPF") && strcmp(car_from_params('CPF', p).variant, 'CPF');
fprintf('support_sensitivity self-test: same aero -> same time %s, +5 %% ClA not slower %s, CPF row read %s\n', ...
    tern(abs(t1 - t0) < 1e-12), tern(t2 <= t0), tern(any(V.variant == "CPF")));
end

function s = tern(b, yes, no)
if nargin < 2, yes = 'PASS'; no = 'FAIL'; end
if b, s = yes; else, s = no; end
end
