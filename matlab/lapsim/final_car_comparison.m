function out = final_car_comparison(opts)
%FINAL_CAR_COMPARISON The final car (FINAL) against the previous default (CP),
%   with the aero effect and the CG effect separated (2026-11-28).
%
%   out = final_car_comparison()        writes media/final_car_comparison.md and .csv
%   out = final_car_comparison(opts)    opts.write (true)
%   final_car_comparison('--selftest')
%
%   Four cars, all 302.56 kg (the mass did not change: the four wing supports,
%   1.73 kg, were taken off the wing lines, so their mass effect is zero by
%   construction):
%     old     CP's aero row (2 prism layers) at the OLD CG: the parameter file
%             with the 18 mass positions of the 2026-11-28 reconciliation set
%             back to their earlier values (OLD_POS below; commit a6caef60,
%             41.84 % front, CG 308.9 mm high). The previous default car.
%     CP      CP's row at the NEW CG (the current file: 42.26 %, 319.9 mm)
%     CP_bl1  CP meshed with 1 prism layer (ClA 3.977, CdA 1.667, front 0.431,
%             default_car's reference table) at the new CG
%     FINAL   row FINAL (run FINAL_bl1, 1 prism layer) at the new CG: the car
%   Effects, each a difference of two neighbours, so they add up to the total:
%     CG effect     CP - old             (same aero, CG moved)
%     layer term    CP_bl1 - CP          (CP's 1-layer against its 2-layer run;
%                                         also CP's own 2.2 % spread)
%     aero effect   FINAL - CP_bl1       (the supports, like for like at 1 layer)
%     total         FINAL - old  = CG + layer + aero
%   FINAL is a 1-layer run, so the fair aero reference is CP_bl1, not the
%   2-layer CP row.
%   Noise bands: the largest change of each result when CP_bl1's ClA or CdA is
%   raised, or its front share lowered, by 2.2 % (CP vs CP_bl1) or by 0.9 %
%   (CP_bl1 vs its repeat CP_bl1r), one at a time. An aero difference inside
%   the 2.2 % band is not claimed. The CG effect is not noise (same aero, same
%   model), but it rests on the CG estimate (24 % of the mass is a GUESS).
%
%   Results: lap times (point-mass and four-wheel: skidpad, 75 m, autocross,
%   fast circuit), 0-100 km/h, cornering balance at 45 and 100 m (grip speed,
%   balance, neutral front share, limiting axle), load cases (largest wheel
%   load per case), frame stress (lowest factor of safety and its case), ride
%   (spring rates for the 3.2 / 3.5 Hz targets, the frequencies the old springs
%   would give, roll stiffness split), the following-car penalty with each
%   car's own wake (q-ratio at 1 car length) and frame torsional stiffness
%   (checked to be independent of the mass positions).

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'write'), opts.write = true; end
pNew = read_car_params();
pOld = old_params();
[refVar, refWake, ref] = default_car();
cars = {   % name, variant, params, aero source, wake run
    'old',    'CP',   pOld, 'table',   "CP"
    'CP',     'CP',   pNew, 'table',   "CP"
    'CP_bl1', 'CP',   pNew, ref.table, "CP_bl1"
    refVar,   refVar, pNew, 'table',   string(refWake)};
W = readtable(fullfile(repo_root(), 'cfd', 'results', 'wake_cfd.csv'), 'TextType', 'string');
sg = suspension_geometry(struct('plot', false, 'write', false, 'p', pNew));   % roll centres: geometry only
rc = [sg.front.rc_static, sg.rear.rc_static] / 1000;
R = cell(size(cars, 1), 1);
for k = 1:size(cars, 1)
    q = mean(W.q_ratio(W.run == cars{k, 5} & W.plane_L == 1));
    R{k} = evaluate(cars{k, 2}, cars{k, 3}, cars{k, 4}, q, rc, pOld);
    fprintf('final_car_comparison: %s done\n', cars{k, 1});
end
% noise bands around CP_bl1 (new CG), at 2.2 % and 0.9 %
qb = mean(W.q_ratio(W.run == "CP_bl1" & W.plane_L == 1));
band = zeros(numel(R{1}.value), 2);
spreads = [ref.spread, ref.repeat];
for s = 1:2
    for f = 1:3
        Vp = ref.table; i = find(Vp.variant == "CP");
        switch f
            case 1, Vp.ClA(i) = Vp.ClA(i) * (1 + spreads(s));
            case 2, Vp.CdA(i) = Vp.CdA(i) * (1 + spreads(s));
            case 3, Vp.aero_front(i) = Vp.aero_front(i) * (1 - spreads(s));
        end
        Rp = evaluate('CP', pNew, Vp, qb, rc, pOld);
        band(:, s) = max(band(:, s), abs(Rp.value - R{3}.value));
    end
end
T = R{1}.meta;
T.old = R{1}.value; T.CP_new = R{2}.value; T.CP_bl1_new = R{3}.value; T.FINAL = R{4}.value;
T.cg_effect = T.CP_new - T.old;
T.layer_term = T.CP_bl1_new - T.CP_new;
T.aero_effect = T.FINAL - T.CP_bl1_new;
T.total = T.FINAL - T.old;
T.band_2p2 = band(:, 1); T.band_0p9 = band(:, 2);
T.aero_beyond_2p2 = abs(T.aero_effect) > T.band_2p2 + 1e-12;
T.aero_beyond_0p9 = abs(T.aero_effect) > T.band_0p9 + 1e-12;
T.total_beyond_2p2 = abs(T.total) > T.band_2p2 + 1e-12;
out.T = T; out.cars = cars(:, 1).'; out.text = cellfun(@(r) r.text, R, 'UniformOutput', false);
out.pOld = pOld; out.pNew = pNew;
disp(T(:, {'result', 'old', 'CP_new', 'CP_bl1_new', 'FINAL', 'cg_effect', 'aero_effect', 'total', 'band_2p2'}));
if opts.write, write_md(out, ref); end
end

% =============================================================================
function r = evaluate(variant, p, src, q, rc, pOld)
% every result of one car, as a flat list (result, unit, decimals, value)
names = {}; units = {}; dec = []; val = []; txt = struct();
    function add(n, u, d, v), names{end+1, 1} = n; units{end+1, 1} = u; dec(end+1, 1) = d; val(end+1, 1) = v; end %#ok<AGROW>
car = car_from_params(variant, p, src);
add('car mass with driver', 'kg', 2, car.m);
add('front weight share', '%', 2, 100 * car.wd_front);
add('CG height', 'mm', 1, 1000 * car.h_cg);
add('ClA', 'm2', 3, car.ClA); add('CdA', 'm2', 3, car.CdA); add('front aero share', '-', 3, car.aero_front);
tracks = {'skidpad', 'accel_75m', 'autocross', 'fast_circuit'};
tp = zeros(1, 4);
for t = 1:4
    tr = load_track(tracks{t});
    [~, r1] = evalc('lapsim(car, tr)'); tp(t) = r1.t_lap;
    [~, r4] = evalc('lapsim(car, tr, struct(''four_wheel'', true))');
    add(sprintf('%s, point-mass', strrep(tracks{t}, '_', ' ')), 's', 3, tp(t));
    add(sprintf('%s, four-wheel', strrep(tracks{t}, '_', ' ')), 's', 3, r4.t_lap);
end
[~, a] = evalc('accel_test(car, struct(''plot'', false))');
add('0-100 km/h (accel_test)', 's', 3, a.t_100);
add('75 m (accel_test)', 's', 3, a.t_75);
% cornering balance, as cornering_balance_study: roll centres from the kinematics
cb = car; cb.h_rc_f = rc(1); cb.h_rc_r = rc(2);
for Rr = [45 100]
    o = cornering_balance(cb, Rr, struct('find_neutral', true));
    add(sprintf('grip speed at %d m', Rr), 'km/h', 1, o.v_grip * 3.6);
    add(sprintf('corner speed at %d m (power cap)', Rr), 'km/h', 1, o.v_max * 3.6);
    add(sprintf('balance at %d m (front use - rear use)', Rr), 'points', 2, o.balance_pct);
    add(sprintf('neutral front aero share at %d m', Rr), '-', 3, o.aero_front_neutral);
    txt.(sprintf('limit_%d', Rr)) = char(o.limiting_axle);
end
% ride: springs for the target frequencies at this car's sprung masses, the
% frequencies the OLD car's springs would give here, roll stiffness split
ms = @(pp) [pp.weight_dist_front * (pp.mass_car + pp.mass_driver) / 2 - pp.unsprung_mass_corner_front, ...
            (1 - pp.weight_dist_front) * (pp.mass_car + pp.mass_driver) / 2 - pp.unsprung_mass_corner_rear];
f0 = [p.ride_frequency_front, p.ride_frequency_rear];
m1 = ms(p); m0 = ms(pOld);
kw = (2 * pi * f0).^2 .* m1;                             % wheel rate, N/m
add('front wheel rate for 3.2 Hz', 'N/mm', 2, kw(1) / 1000);
add('rear wheel rate for 3.5 Hz', 'N/mm', 2, kw(2) / 1000);
fo = f0 .* sqrt(m0 ./ m1);                               % old springs on this car
add('front ride frequency with the old springs', 'Hz', 3, fo(1));
add('rear ride frequency with the old springs', 'Hz', 3, fo(2));
Kf = kw(1) * (p.track_front / 1000)^2 / 2; Kr = kw(2) * (p.track_rear / 1000)^2 / 2;
add('roll stiffness split, front', '%', 2, 100 * Kf / (Kf + Kr));
% loads and frame stress (this car's own loads, in memory)
[~, LC] = evalc('load_cases(struct(''variant'', variant, ''p'', p, ''aero_source'', src, ''write'', false))');
for c = ["cornering", "braking", "bump", "corner_brake"]
    add(sprintf('largest wheel load, %s', strrep(c, '_', '+')), 'N', 0, max(LC.Fz_N(LC.(1) == c)));   % column 1 is 'case', a keyword
end
[~, fe] = evalc('frame_fe(struct(''write'', false, ''plot'', false, ''p'', p, ''variant'', variant, ''aero_source'', src, ''loads'', LC))');
fos = arrayfun(@(c) fe.mat.yield / c.stress.max, fe.cases);
[fmin, i] = min(fos);
add('frame, lowest factor of safety (4130 yield)', '-', 3, fmin);
txt.fos_case = fe.cases(i).name;
for c = 1:numel(fe.cases)
    add(sprintf('frame FoS, %s', strrep(fe.cases(c).name, '_', '+')), '-', 3, fos(c));
end
add('frame torsional stiffness (through the links)', 'Nm/deg', 1, fe.torsion.k_Nm_deg);
% following-car penalty: the same car behind, downforce times its own wake's q-ratio at 1 L
add('own-wake q-ratio at 1 L', '-', 3, q);
for t = [3 4]
    tr = load_track(tracks{t}); cf = car; cf.ClA = car.ClA * q;
    [~, rf] = evalc('lapsim(cf, tr)');
    add(sprintf('following penalty, %s', strrep(tracks{t}, '_', ' ')), 's', 3, rf.t_lap - tp(t));
end
r.meta = table(string(names), string(units), dec, 'VariableNames', {'result', 'unit', 'decimals'});
r.value = val; r.text = txt;
end

% =============================================================================
function p = old_params()
% The current parameter file with the 18 mass positions of the 2026-11-28
% reconciliation set back to their values before it (commit a6caef60): the
% CG of the previous default car (41.84 % front, 308.9 mm high).
OLD_POS = {'x_chain_drive', 1620; 'z_chain_drive', 240; 'x_corners_front', 0; 'z_corners_front', 240;
    'x_corners_rear', 1550; 'z_corners_rear', 240; 'x_front_wing', -300; 'z_front_wing', 150;
    'x_rear_wing', 1850; 'z_rear_wing', 1250; 'x_floor_diffuser', 1200; 'z_floor_diffuser', 60;
    'x_bodywork', 700; 'z_bodywork', 350; 'x_cockpit', 650; 'z_cockpit', 300; 'x_driver', 840; 'z_driver', 330};
src = fullfile(repo_root(), 'params', 'car_params.txt');
L = splitlines(string(fileread(src)));
for k = 1:size(OLD_POS, 1)
    pat = "^""" + OLD_POS{k, 1} + """=";
    i = find(startsWith(L, regexpPattern(pat)));
    if numel(i) ~= 1, error('final_car_comparison:old', 'line "%s" found %d times', OLD_POS{k, 1}, numel(i)); end
    L(i) = sprintf('"%s"= %g', OLD_POS{k, 1}, OLD_POS{k, 2});
end
f = [tempname '.txt'];
writelines(L, f);
c = onCleanup(@() delete(f));
p = read_car_params(f);
end

% =============================================================================
function write_md(out, ref)
T = out.T; md = fullfile(repo_root(), 'media');
writetable(T, fullfile(md, 'final_car_comparison.csv'));
fid = fopen(fullfile(md, 'final_car_comparison.md'), 'w'); c = onCleanup(@() fclose(fid));
fprintf(fid, '# The final car (FINAL) against the previous default (CP)\n\n');
fprintf(fid, 'Written by `matlab/lapsim/final_car_comparison.m` on %s. ', datestr(now, 'yyyy-mm-dd')); %#ok<TNOW1,DATST>
fprintf(fid, '**FINAL is the default car since 2026-11-28** (`default_car()`): CP''s bodywork and wings with the F rear and J front wing supports, aero row FINAL (CFD run FINAL_bl1). ');
fprintf(fid, 'Every result here is a model (quasi-steady lap sim, rigid chassis, assumed tyres, steady RANS aero): use the differences to compare, not as predictions.\n\n');
po = out.pOld; pn = out.pNew;
fprintf(fid, '| car | aero row | mass with driver | front weight | CG x / z (mm, with driver) |\n|---|---|---|---|---|\n');
fprintf(fid, '| old (the previous default) | CP (2 prism layers): ClA %.3f, CdA %.3f, front %.3f | %.2f kg | %.2f %% | %.1f / %.1f |\n', ...
    T.old(T.result == "ClA"), T.old(T.result == "CdA"), T.old(T.result == "front aero share"), po.mass_car + po.mass_driver, 100 * po.weight_dist_front, po.cg_x_from_front_axle, po.cg_height);
fprintf(fid, '| CP at the new CG | CP (2 layers) | %.2f kg | %.2f %% | %.1f / %.1f |\n', pn.mass_car + pn.mass_driver, 100 * pn.weight_dist_front, pn.cg_x_from_front_axle, pn.cg_height);
fprintf(fid, '| CP_bl1 at the new CG | CP_bl1 (1 layer, in memory): ClA %.3f, CdA %.3f, front %.3f | same | same | same |\n', ref.ClA, ref.CdA, ref.aero_front);
fprintf(fid, '| **FINAL** (the car) | FINAL (1 layer, run FINAL_bl1): ClA %.3f, CdA %.3f, front %.3f | same | same | same |\n\n', ...
    T.FINAL(T.result == "ClA"), T.FINAL(T.result == "CdA"), T.FINAL(T.result == "front aero share"));
fprintf(fid, '**How the change splits.** CG effect = CP at the new CG minus old (the 2026-11-28 mass-budget reconciliation moved the CG; the mass is unchanged). ');
fprintf(fid, 'Supports'' mass effect = 0: the four supports (1.73 kg) were taken off the wing lines, so the total is the same 302.56 kg, and their position is already in the old CG (308.9 mm; 311.3 mm before the supports had lines). ');
fprintf(fid, 'Layer term = CP_bl1 minus CP (CP''s 1-layer run against its 2-layer run; it is also CP''s own 2.2 %% spread). ');
fprintf(fid, '**Aero effect = FINAL minus CP_bl1**: FINAL is a 1-layer run, so CP_bl1, not the 2-layer CP row, is its fair aero reference. Total = FINAL minus old = CG + layer + aero.\n\n');
fprintf(fid, '**Noise.** Band = the largest change of that result when CP_bl1''s ClA or CdA is raised, or its front share lowered, by 2.2 %% (CP vs CP_bl1) or 0.9 %% (CP_bl1 vs its repeat), one at a time. An aero effect inside the 2.2 %% band is not claimed; "0.9" marks one that is beyond the repeat noise only. The CG effect is not aero noise, but it rests on the CG estimate (24 %% of the mass is a GUESS).\n\n');
fprintf(fid, '| result | unit | old (CP, old CG) | CP, new CG | CP_bl1, new CG | **FINAL** | CG effect | layer term | **aero effect** | total | band 2.2 %% / 0.9 %% | aero beyond |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n');
for i = 1:height(T)
    d = T.decimals(i); fm = sprintf('%%.%df', d); fs = sprintf('%%+.%df', d);
    if T.aero_beyond_2p2(i), b = '**2.2**'; elseif T.aero_beyond_0p9(i), b = '0.9 only'; else, b = 'no'; end
    if T.band_2p2(i) == 0 && T.aero_effect(i) == 0, b = '-'; end
    fprintf(fid, ['| %s | %s | ' fm ' | ' fm ' | ' fm ' | **' fm '** | ' fs ' | ' fs ' | **' fs '** | ' fs ' | ' fm ' / ' fm ' | %s |\n'], ...
        T.result(i), T.unit(i), T.old(i), T.CP_new(i), T.CP_bl1_new(i), T.FINAL(i), T.cg_effect(i), T.layer_term(i), T.aero_effect(i), T.total(i), T.band_2p2(i), T.band_0p9(i), b);
end
names = out.cars;
fprintf(fid, '\nLimiting axle at 45 / 100 m: %s.\n', strjoin(cellfun(@(n, t) sprintf('%s %s / %s', n, t.limit_45, t.limit_100), names, out.text.', 'UniformOutput', false), '; '));
fprintf(fid, 'Lowest factor of safety in the case: %s.\n\n', strjoin(cellfun(@(n, t) sprintf('%s %s', n, t.fos_case), names, out.text.', 'UniformOutput', false), '; '));
fprintf(fid, 'Notes. The point-mass lap sim has no load transfer: it sees the CG only through the static rear weight share in its traction limit (`long_forces`), so its CG effect is small. The four-wheel model, the 0-100 / 75 m traction limit (with load transfer), the balance, the loads and the stress see the CG height as well. ');
fprintf(fid, 'Ride: the model sizes the springs for the target frequencies (3.2 / 3.5 Hz) at the current sprung masses, so the frequencies stay at target and the spring rates and roll split move; "with the old springs" is what the springs sized for the old CG would give. ');
fprintf(fid, 'Frame torsional stiffness is a property of the tubes: the torsion case is a self-balanced couple, so the lumped masses do not enter it (the CG effect on it is checked to be zero). ');
fprintf(fid, 'Grip speed = the speed at which the tyres saturate on that radius, ignoring power; at 100 m it is above the car''s top speed (downforce grows with speed as fast as the grip needed), so the 100 m corner is power-capped and "corner speed (power cap)" is the one that counts. ');
fprintf(fid, 'Roll centres: the balance rows use the kinematic static values from `suspension_geometry` (as `cornering_balance_study`); the four-wheel lap times use the lap sim''s defaults (as `lap_experiments`). ');
fprintf(fid, 'Following penalty: the same car one length behind, its downforce times the q-ratio of its own CFD wake at 1 car length (old and CP: run CP; CP_bl1: run CP_bl1; FINAL: run FINAL_bl1).\n');
end

% =============================================================================
function ok = selftest()
% Hand checks:
%  (1) the CG shift equals sum(m_i * dx_i) / M over the 18 moved positions;
%  (2) the old file gives the a6caef60 state, 41.84 % front and 308.9 mm;
%  (3) the cars built from the two files carry each file's front share and CG height, same mass;
%  (4) the effects add up to the total.
pn = read_car_params(); po = old_params();
M = pn.mass_car + pn.mass_driver;
items = {'chain_drive', 'm_chain_drive'; 'corners_front', 'm_corners_front'; 'corners_rear', 'm_corners_rear'; ...
    'front_wing', 'm_front_wing'; 'rear_wing', 'm_rear_wing'; 'floor_diffuser', 'm_floor_diffuser'; ...
    'bodywork', 'm_bodywork'; 'cockpit', 'm_cockpit'; 'driver', 'mass_driver'};
dx = 0; dz = 0;
for k = 1:size(items, 1)
    m = pn.(items{k, 2});
    dx = dx + m * (pn.(['x_' items{k, 1}]) - po.(['x_' items{k, 1}]));
    dz = dz + m * (pn.(['z_' items{k, 1}]) - po.(['z_' items{k, 1}]));
end
okx = abs((pn.cg_x_from_front_axle - po.cg_x_from_front_axle) - dx / M) < 1e-9;
okz = abs((pn.cg_height - po.cg_height) - dz / M) < 1e-9;
ok2 = abs(100 * po.weight_dist_front - 41.84) < 0.005 && abs(po.cg_height - 308.9) < 0.05 && pn.mass_car == po.mass_car;
c0 = car_from_params('CP', po); c1 = car_from_params('CP', pn);
ok3 = c0.wd_front == po.weight_dist_front && c1.wd_front == pn.weight_dist_front && ...
    abs(c0.h_cg - po.cg_height / 1000) < 1e-12 && abs(c1.h_cg - pn.cg_height / 1000) < 1e-12 && c0.m == c1.m;
T = table([1; 2], [2; 5], [3; 4], [7; 1], 'VariableNames', {'old', 'CP_new', 'CP_bl1_new', 'FINAL'});
ok4 = all(((T.CP_new - T.old) + (T.CP_bl1_new - T.CP_new) + (T.FINAL - T.CP_bl1_new)) == (T.FINAL - T.old));
ok = okx && okz && ok2 && ok3 && ok4;
fprintf(['final_car_comparison self-test: %s (CG shift x %+.2f mm = sum m dx / M %+.2f, z %+.2f = %+.2f; old file %.2f %% front, %.1f mm; ' ...
    'cars carry the file''s CG: old %.4f / %.4f m, new %.4f / %.4f m, same mass %.2f kg; effects add up %s)\n'], tern(ok), pn.cg_x_from_front_axle - po.cg_x_from_front_axle, dx / M, ...
    pn.cg_height - po.cg_height, dz / M, 100 * po.weight_dist_front, po.cg_height, c0.wd_front, c0.h_cg, c1.wd_front, c1.h_cg, c1.m, tern(ok4));
if ~ok, error('final_car_comparison self-test: FAIL'); end
end

function s = tern(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
