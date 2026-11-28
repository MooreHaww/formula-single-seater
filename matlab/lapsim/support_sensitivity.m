function out = support_sensitivity(opts)
%SUPPORT_SENSITIVITY Lap times and cornering balance: CP_bl1 against CPF (CP with
%   the F rear-wing supports) and, when their rows exist, CPFF (CPF plus the
%   front-wing supports of the front-wing round) and CPG (CP with the ridged G
%   rear-wing supports, finishing round), docs/wing_supports_plan.md.
%   Written as a sensitivity study (2026-11-26 to 28). Since 2026-11-28 the CAD
%   has the F and J supports and FINAL (= CPFF's geometry, run FINAL_bl1) is the
%   default car (default_car()); this study keeps its own cars and compares them
%   at the parameter file's current mass and CG.
%
%   out = support_sensitivity()        writes media/support_sensitivity.md and .csv
%   out = support_sensitivity(opts)    opts.write (true)
%   support_sensitivity('--selftest')
%
%   All cars are car_from_params with the same parameter file, tyre model,
%   roll centres and lap-sim settings. Only ClA, CdA and aero_front differ:
%     CP_bl1  CP's row with the numbers of run CP_bl1 (CP meshed with 1 prism
%             layer, ClA 3.977, CdA 1.667, front 0.431; built in memory, the
%             CP row of params/aero_variants.csv is not changed)
%     CPF     row CPF of params/aero_variants.csv (run F_bl1, also 1 layer)
%     CPFF    row CPFF (run CPFF_bl1, also 1 layer), only if the row exists
%     CPG     row CPG (run G_bl1ta, 1 layer and mesh fix A), only if the row exists
%   so the cars are like for like (same mesh settings). CP's own run-to-run
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
names = {'CP_bl1', 'CPF'};
vars = {'CP', 'CPF'};
srcs = {Vb, V};
runs = {'CP_bl1', 'F_bl1'};                      % the CFD run behind each car, in the order of names
extra = {'CPFF', 'CPFF_bl1'; 'CPG', 'G_bl1ta'};
for e = 1:size(extra, 1)
    if any(V.variant == extra{e, 1})
        names{end+1} = extra{e, 1}; vars{end+1} = extra{e, 1}; srcs{end+1} = V; runs{end+1} = extra{e, 2}; %#ok<AGROW>
    end
end
nc = numel(names);
cars = cell(1, nc);
for k = 1:nc
    cars{k} = car_from_params(vars{k}, p, srcs{k});
end
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
        tt = zeros(1, nc);
        for k = 1:nc
            tt(k) = lapsim(cars{k}, tr, o).t_lap;
        end
        band = max(abs([lapsim(cl, tr, o).t_lap, lapsim(cd, tr, o).t_lap, lapsim(ca, tr, o).t_lap] - tt(1)));
        d = tt(2:end) - tt(1);
        rows(end+1, :) = [{tracks{t}, tern(fw, 'four-wheel', 'point-mass')}, num2cell(tt), num2cell(d), {band}, num2cell(abs(d) > band)]; %#ok<AGROW>
    end
end
vn = [{'track', 'model'}, strcat('t_', names, '_s'), strcat('diff_', names(2:end), '_s'), {'band_2p2_s'}, strcat('beyond_band_', names(2:end))];
L = cell2table(rows, 'VariableNames', vn);

bbal = zeros(1, 2);
for j = 1:2
    R = 45 + 55 * (j - 1);                       % 45 and 100 m, the study's radii
    b0 = cornering_balance(c0, R).balance_pct;
    bbal(j) = max(abs([cornering_balance(cl, R).balance_pct, cornering_balance(cd, R).balance_pct, cornering_balance(ca, R).balance_pct] - b0));
end
bal = {};
for k = 1:nc
    [~, b] = evalc('cornering_balance_study(struct(''plot'', false, ''write'', false, ''laps'', false, ''variant'', vars{k}, ''aero_source'', srcs{k}, ''wd'', NaN, ''aero'', cars{k}.aero_front))');
    for r = 1:height(b.T)
        n = b.target.T.aero_front_neutral(b.target.T.radius_m == b.T.radius_m(r));
        bal(end+1, :) = {names{k}, b.T.radius_m(r), b.T.aero_front(r), b.T.v_grip_kmh(r), b.T.v_max_kmh(r), ...
            char(b.T.limiting_axle(r)), b.T.balance_pct(r), n, bbal(1 + (b.T.radius_m(r) == 100))}; %#ok<AGROW>
    end
end
B = cell2table(bal, 'VariableNames', {'car', 'radius_m', 'aero_front', 'v_grip_kmh', 'v_max_kmh', 'limiting_axle', 'balance_pct', 'aero_front_neutral', 'balance_band_2p2_pct'});

out.cars = cars; out.names = names; out.lap = L; out.balance = B;
out.aero = table(string(names'), cellfun(@(c) c.ClA, cars'), cellfun(@(c) c.CdA, cars'), cellfun(@(c) c.aero_front, cars'), ...
    'VariableNames', {'car', 'ClA', 'CdA', 'aero_front'});
disp(out.aero); disp(L); disp(B);

if opts.write
    md = fullfile(repo_root(), 'media');
    writetable(L, fullfile(md, 'support_sensitivity_laps.csv'));
    writetable(B, fullfile(md, 'support_sensitivity_balance.csv'));
    fid = fopen(fullfile(md, 'support_sensitivity.md'), 'w');
    fprintf(fid, '# Wing supports: lap-time and balance sensitivity (%s)\n\n', strjoin(names, ' vs '));
    fprintf(fid, 'Written by `matlab/lapsim/support_sensitivity.m` on %s, at the current mass and CG of `params/car_params.txt`. Written as a sensitivity study; since 2026-11-28 the CAD has the F and J supports and **FINAL (= CPFF''s geometry, run FINAL_bl1) is the default car**, so the CPFF column is the car. ', datestr(now, 'yyyy-mm-dd')); %#ok<TNOW1,DATST>
    fprintf(fid, 'CPF = CP with the F rear-wing supports; CPFF = CPF plus the front-wing supports of the front-wing round; CPG = CP with the ridged G rear-wing supports (run G_bl1ta, also mesh fix A); all CFD only. ');
    fprintf(fid, 'All cars come from runs meshed with 1 prism layer (%s); everything else (mass, tyres, roll centres, lap-sim settings) is the same. ', strjoin(runs, ', '));
    fprintf(fid, 'CP''s own run-to-run aero spread is about 2.2 %% in ClA; only the ranking of CFD variants is trustworthy. ');
    fprintf(fid, '**Band** = the largest change in that result when CP_bl1''s ClA or CdA is raised, or its front share lowered, by 2.2 %% (one at a time); a difference inside the band is not claimed.\n\n');
    fprintf(fid, '| car | ClA | CdA | front share | ClA vs CP_bl1 | CdA vs CP_bl1 | front share vs CP_bl1 |\n|---|---|---|---|---|---|---|\n');
    for k = 1:nc
        fprintf(fid, '| %s | %.3f | %.3f | %.3f | %+.1f %% | %+.1f %% | %+.3f |\n', names{k}, cars{k}.ClA, cars{k}.CdA, cars{k}.aero_front, ...
            100 * (cars{k}.ClA / c0.ClA - 1), 100 * (cars{k}.CdA / c0.CdA - 1), cars{k}.aero_front - c0.aero_front);
    end
    fprintf(fid, '\n| track | model |%s 2.2 %% band (s) |\n|---|---|%s---|\n', ...
        [sprintf(' %s (s) |', names{:}), sprintf(' %s - CP_bl1 (s) |', names{2:end})], repmat('---|', 1, 2 * nc - 1));
    for r = 1:height(L)
        fprintf(fid, '| %s | %s |', strrep(L.track{r}, '_', ' '), L.model{r});
        for k = 1:nc
            fprintf(fid, ' %.3f |', L.(['t_' names{k} '_s'])(r));
        end
        for k = 2:nc
            fprintf(fid, ' %+.3f%s |', L.(['diff_' names{k} '_s'])(r), tern(L.(['beyond_band_' names{k}])(r), ' (beyond)', ' (inside)'));
        end
        fprintf(fid, ' %.3f |\n', L.band_2p2_s(r));
    end
    if any(strcmp(names, 'CPFF'))                % the front supports alone: CPFF against CPF, same band
        dff = L.t_CPFF_s - L.t_CPF_s;
        fprintf(fid, '\nCPFF - CPF (what the front supports add to the rear ones), s:');
        for r = 1:height(L)
            fprintf(fid, ' %s %s %+.3f%s;', strrep(L.track{r}, '_', ' '), L.model{r}, dff(r), tern(abs(dff(r)) > L.band_2p2_s(r), ' (beyond)', ' (inside)'));
        end
        fprintf(fid, ' band as above.\n');
    end
    fprintf(fid, '\n| car | R (m) | front aero | v grip (km/h) | v max (km/h) | limits | balance (%%) | neutral front aero | balance 2.2 %% band (points) |\n|---|---|---|---|---|---|---|---|---|\n');
    for r = 1:height(B)
        fprintf(fid, '| %s | %d | %.3f | %.1f | %.1f | %s | %+.1f | %.3f | %.1f |\n', B.car{r}, B.radius_m(r), B.aero_front(r), B.v_grip_kmh(r), B.v_max_kmh(r), B.limiting_axle{r}, B.balance_pct(r), B.aero_front_neutral(r), B.balance_band_2p2_pct(r));
    end
    fprintf(fid, '\nBalance = front-axle use minus rear-axle use at the limit (positive = understeer). Weight distribution, CG, roll centres and tyres as filed for all cars.\n');
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
okff = ~any(V.variant == "CPFF") || strcmp(car_from_params('CPFF', p).variant, 'CPFF');
okg = ~any(V.variant == "CPG") || strcmp(car_from_params('CPG', p).variant, 'CPG');
ok = ok && okff && okg;
fprintf('support_sensitivity self-test: same aero -> same time %s, +5 %% ClA not slower %s, CPF row read %s, CPFF row read (if present) %s, CPG row read (if present) %s\n', ...
    tern(abs(t1 - t0) < 1e-12), tern(t2 <= t0), tern(any(V.variant == "CPF")), tern(okff), tern(okg));
end

function s = tern(b, yes, no)
if nargin < 2, yes = 'PASS'; no = 'FAIL'; end
if b, s = yes; else, s = no; end
end
