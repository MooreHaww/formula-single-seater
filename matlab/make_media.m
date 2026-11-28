function out = make_media(opts)
%MAKE_MEDIA Figures, animation and tables for the README, all into media/.
%   out = make_media()        everything below
%   out = make_media(opts)    opts.gif, opts.stress, opts.tables (true each)
%   make_media('--selftest')
%
%   media/suspension_bump_steer.gif   front and rear corner in front view
%       through +/-30 mm of wheel travel (suspension_geometry, the same
%       kinematic solve the hardpoints were optimised with), then the front
%       corner in top view from lock to lock (rack moves the tie-rod inner
%       end, tie rod length held)
%   media/frame_stress_cases.png      peak von Mises per load case with and
%       without the torsion diagonals, against yield / 1.5
%   media/frame_torsion_diagonals.png torsional stiffness and frame mass for
%       the diagonal families of frame_diagonal_search
%   media/frame_stress_bump.png       the frame coloured by von Mises in the
%       worst driving case (bump), deflection exaggerated
%   media/mass_table.md               mass budget with flags and CG
%   media/lap_time_table.md           lap times, the default car (default_car(): FINAL), before and after
%       the diagonals (point-mass and four-wheel), and all four variants
%
%   The SolidWorks standard views (chassis, assembly, master layout) are
%   rendered by the harness step SaveStandardViews (python tools/sw_run.py
%   rebuild) into media/views/; this script does not touch them.

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
f = {'gif', 'stress', 'tables'};
for k = 1:numel(f), if ~isfield(opts, f{k}), opts.(f{k}) = true; end, end
root = repo_root(); md = fullfile(root, 'media');
p = read_car_params();
out = struct();
if opts.gif, out.gif = suspension_gif(p, fullfile(md, 'suspension_bump_steer.gif')); end
if opts.stress, out.stress = stress_plots(p, md); end
if opts.tables
    out.mass = mass_table(fullfile(md, 'mass_table.md'));
    out.lap = lap_table(p, fullfile(md, 'lap_time_table.md'));
end
end

% =============================================================================
function info = suspension_gif(p, file)
% a single travel point gives polyfit a degree-1 fit through one point; the
% motion ratio and camber gain of those poses are not used here
w0 = warning('off', 'MATLAB:polyfit:PolyNotUnique'); cleanup = onCleanup(@() warning(w0));
s = suspension_geometry(struct('plot', false, 'travel', -30:2:30));
hp = s.hardpoints;
% steering sweep: rack travel to the lock found by suspension_optimise's package check
pk = suspension_optimise('--package', hp.front, 'front', p);
rack = pk.lock_rack; if isempty(rack) || isnan(rack), rack = 25; end
racks = linspace(-rack, rack, 25);
h = hp.front; L0 = norm(h.tie_out - h.tie_in);
steer = cell(numel(racks), 1); ang = zeros(numel(racks), 1);
for k = 1:numel(racks)
    hk = h; hk.tie_in = h.tie_in + [0, racks(k), 0]; hk.tie_len = L0;
    o = suspension_geometry(struct('p', p, 'hp', struct('front', hk), 'corners', {{'front'}}, 'plot', false, 'travel', 0));
    steer{k} = struct('P', o.front.P(:, :, 1), 'tie_in', hk.tie_in);
    ang(k) = o.front.toe(1) - s.front.static_toe;
end
n = numel(s.front.travel);
seqB = [1:n, n - 1:-1:2];                       % bump down -> up -> down
seqS = [ceil(numel(racks) / 2):numel(racks), numel(racks) - 1:-1:1, 2:ceil(numel(racks) / 2)];
fig = figure('Visible', 'off', 'Position', [100 100 960 420], 'Color', 'w');
try, theme(fig, 'light'); catch, end
first = true;
for k = seqB
    clf(fig);
    draw_front_view(subplot(1, 2, 1), hp.front, s.front, k, 'Front corner');
    draw_front_view(subplot(1, 2, 2), hp.rear, s.rear, k, 'Rear corner');
    sgtitle(sprintf('Wheel travel %+3.0f mm (bump +)  |  suspension_geometry.m kinematics', s.front.travel(k)), 'Interpreter', 'none');
    first = add_frame(fig, file, first, 0.08);
end
for k = seqS
    clf(fig);
    draw_top_view(subplot(1, 1, 1), h, steer{k}, racks(k), ang(k));
    sgtitle(sprintf('Front steering, rack %+5.1f mm, road wheel %+5.1f deg (lock %.0f mm)', racks(k), ang(k), rack), 'Interpreter', 'none');
    first = add_frame(fig, file, first, 0.08);
end
close(fig);
info = struct('file', file, 'frames', numel(seqB) + numel(seqS), 'lock_rack_mm', rack, 'steer_deg', [min(ang) max(ang)]);
fprintf('make_media: %s (%d frames)\n', file, info.frames);
end

function first = add_frame(fig, file, first, dt)
im = print(fig, '-RGBImage', '-r80');
[A, map] = rgb2ind(im, 128, 'nodither');
if first
    imwrite(A, map, file, 'gif', 'LoopCount', Inf, 'DelayTime', dt);
    first = false;
else
    imwrite(A, map, file, 'gif', 'WriteMode', 'append', 'DelayTime', dt);
end
end

function draw_front_view(ax, h, r, k, ttl)
% y-z view (looking rearward) of the right-hand corner at sweep index k
hold(ax, 'on'); axis(ax, 'equal'); grid(ax, 'on');
P = r.P(:, :, k);
c = [0 0.35 0.7];
plot(ax, [h.lwb_in_fwd(2) P(1, 2)], [h.lwb_in_fwd(3) P(1, 3)], '-', 'Color', c, 'LineWidth', 2);
plot(ax, [h.uwb_in_fwd(2) P(2, 2)], [h.uwb_in_fwd(3) P(2, 3)], '-', 'Color', c, 'LineWidth', 2);
plot(ax, [P(1, 2) P(2, 2)], [P(1, 3) P(2, 3)], '-k', 'LineWidth', 3);                 % upright
plot(ax, [h.tie_in(2) P(3, 2)], [h.tie_in(3) P(3, 3)], '--', 'Color', [0.85 0.4 0], 'LineWidth', 1.5);
plot(ax, [h.pushrod_in(2) P(4, 2)], [h.pushrod_in(3) P(4, 3)], ':', 'Color', [0.4 0.6 0.2], 'LineWidth', 2);
% tyre outline: a rectangle in the wheel plane, rolling radius by tyre half width
ax3 = P(7, :) - P(5, :); a = ax3(2:3) / norm(ax3(2:3)); up = [-a(2), a(1)];
R = h.wheel_centre(3); hw = 90;
wc = P(5, 2:3);
box = wc + [-hw * a - R * up; hw * a - R * up; hw * a + R * up; -hw * a + R * up; -hw * a - R * up];
plot(ax, box(:, 1), box(:, 2), '-', 'Color', [0.3 0.3 0.3], 'LineWidth', 1.5);
plot(ax, [h.lwb_in_fwd(2) h.uwb_in_fwd(2)], [h.lwb_in_fwd(3) h.uwb_in_fwd(3)], 's', 'Color', [0.5 0.5 0.5], 'MarkerFaceColor', [0.5 0.5 0.5]);
yline(ax, 0, '-', 'Color', [0.6 0.6 0.6]);
plot(ax, [0 0], [0 0], 'k');
xlim(ax, [h.lwb_in_fwd(2) - 60, h.wheel_centre(2) + 180]); ylim(ax, [-40, 520]);
xlabel(ax, 'y (mm)'); ylabel(ax, 'z (mm)');
title(ax, sprintf('%s: camber %+.2f deg, toe %+.3f deg, RC %.0f mm', ttl, r.camber(k), r.toe(k), r.roll_centre_h(k)));
end

function draw_top_view(ax, h, st, rack, ang)
% x-y view (from above) of the front right corner at a rack position
hold(ax, 'on'); axis(ax, 'equal'); grid(ax, 'on');
P = st.P; c = [0 0.35 0.7];
plot(ax, [h.lwb_in_fwd(1) P(1, 1) h.lwb_in_aft(1)], [h.lwb_in_fwd(2) P(1, 2) h.lwb_in_aft(2)], '-', 'Color', c, 'LineWidth', 2);
plot(ax, [h.uwb_in_fwd(1) P(2, 1) h.uwb_in_aft(1)], [h.uwb_in_fwd(2) P(2, 2) h.uwb_in_aft(2)], '-', 'Color', c * 0.6 + 0.4, 'LineWidth', 1.5);
plot(ax, [st.tie_in(1) P(3, 1)], [st.tie_in(2) P(3, 2)], '-', 'Color', [0.85 0.4 0], 'LineWidth', 2);
plot(ax, [st.tie_in(1) st.tie_in(1)], [st.tie_in(2) - rack - 60, st.tie_in(2) - rack + 0], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 4);   % rack stub
% tyre outline in plan: length 2 R, width = tyre width, along the wheel heading
fw = P(8, 1:2) - P(5, 1:2); fw = fw / norm(fw); sd = [-fw(2), fw(1)];
R = h.wheel_centre(3); hw = 90; wc = P(5, 1:2);
box = wc + [-R * fw - hw * sd; R * fw - hw * sd; R * fw + hw * sd; -R * fw + hw * sd; -R * fw - hw * sd];
plot(ax, box(:, 1), box(:, 2), '-', 'Color', [0.3 0.3 0.3], 'LineWidth', 1.5);
set(ax, 'XDir', 'reverse');            % forward (-x) to the right of the screen
xlim(ax, [-400, 400]); ylim(ax, [150, 750]);
xlabel(ax, 'x (mm, rearward positive; forward is to the right)'); ylabel(ax, 'y (mm)');
title(ax, sprintf('Front right corner from above: steer %+.1f deg', ang));
end

% =============================================================================
function info = stress_plots(p, md)
drop = ["_diag", "FH_M-SP2_U"];
A = frame_fe(struct('write', false, 'plot', false));
B = frame_fe(struct('write', false, 'plot', false, 'drop_tubes', drop));
names = ["torsion (1194 Nm)", string({A.cases.name})];
pb = [B.torsion.stress.max, arrayfun(@(c) c.stress.max, B.cases)];
pa = [A.torsion.stress.max, arrayfun(@(c) c.stress.max, A.cases)];
fig = figure('Visible', 'off', 'Position', [100 100 900 420], 'Color', 'w');
try, theme(fig, 'light'); catch, end
bh = bar(categorical(names, names), [pb; pa].', 'grouped'); hold on
bh(1).FaceColor = [0.65 0.65 0.65]; bh(2).FaceColor = [0 0.35 0.7];
yl = A.mat.yield / A.mat.fos_target;
yline(yl, '--r', sprintf('yield / %.1f = %.0f MPa', A.mat.fos_target, yl), 'LabelHorizontalAlignment', 'left');
set(gca, 'TickLabelInterpreter', 'none'); ylim([0, 1.15 * yl]);
ylabel('peak von Mises (MPa)');
legend({sprintf('without diagonals (%.1f kg)', B.frame_mass), sprintf('with diagonals (%.1f kg)', A.frame_mass)}, 'Location', 'northeast');
title('Frame peak stress per load case (frame\_fe.m)');
subtitle('beam model, nominal stress: no stress concentration at the welds'); grid on
save_fig(fig, 'frame_stress_cases');

% torsion families
C = frame_diagonal_search('--candidates');
pairsOf = @(ids) vertcat(C(ismember({C.id}, ids)).pairs);
fam = {'none (as built)', {}
    'floor only (4 that fit)', {'F0', 'F1', 'F3', 'F4'}
    'floor + top (7 that fit)', {'F0', 'F1', 'F3', 'F4', 'T0', 'T1', 'T6'}};   % T5 dropped (5.4 deg joint, 2026-11-25)
k = zeros(size(fam, 1) + 1, 1); m = k;
for i = 1:size(fam, 1)
    args = struct('write', false, 'plot', false, 'torsion_only', true, 'drop_tubes', drop);
    if ~isempty(fam{i, 2}), args.extra_tubes = pairsOf(fam{i, 2}); end
    r = frame_fe(args); k(i) = r.torsion.k_Nm_deg; m(i) = r.frame_mass;
end
k(end) = A.torsion.k_Nm_deg; m(end) = A.frame_mass;
TT = readtable(fullfile(repo_root(), 'cad', 'frame', 'frame_tubes.csv'), 'TextType', 'string', 'CommentStyle', '#');
nDiag = sum(contains(TT.tube, "_diag") | startsWith(TT.tube, "FH_M-SP2_U"));
lab = [fam(:, 1); {sprintf('chosen set (%d tubes)', nDiag)}];
fig = figure('Visible', 'off', 'Position', [100 100 900 420], 'Color', 'w');
try, theme(fig, 'light'); catch, end
cat = categorical(lab, lab);
b = bar(cat, k, 'FaceColor', [0 0.35 0.7]); hold on
yline(1500, '--r', 'target 1500 Nm/deg', 'LabelHorizontalAlignment', 'left');
text(1:numel(k), k + 40, compose('%.0f Nm/deg\n%.1f kg', k, m), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
ylim([0, 1.25 * max(k)]); ylabel('torsional stiffness, through the links (Nm/deg)'); grid on
title('Frame torsional stiffness by diagonal family (frame\_diagonal\_search.m)');
save_fig(fig, 'frame_torsion_diagonals');

% worst driving case on the frame
[~, iw] = max(arrayfun(@(c) c.stress.max, A.cases));
cw = A.cases(iw); fr = A.frame;
fig = figure('Visible', 'off', 'Position', [100 100 900 560], 'Color', 'w');
try, theme(fig, 'light'); catch, end
hold on; axis equal; view(35, 20); grid on
d = reshape(cw.u, 6, []).'; sc = 50 / max(vecnorm(d(:, 1:3), 2, 2));
vm = max(cw.stress.vm, [], 2); cm = parula(256); vmax = max(vm);
for e = 1:size(fr.ends, 1)
    P = fr.xyz(fr.ends(e, :), :);
    plot3(P(:, 1), P(:, 2), P(:, 3), ':', 'Color', [0.75 0.75 0.75]);
    Q = P + sc * d(fr.ends(e, :), 1:3);
    ci = 1 + round(255 * min(1, vm(e) / vmax));
    plot3(Q(:, 1), Q(:, 2), Q(:, 3), '-', 'Color', cm(ci, :), 'LineWidth', 2);
end
colormap(cm); clim([0 vmax]); cb = colorbar; cb.Label.String = 'von Mises, MPa (element peak)';
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
title(sprintf('Frame, %s case: peak %.0f MPa, FoS %.2f on yield; deflection x%.0f', cw.name, cw.stress.max, A.mat.yield / cw.stress.max, sc));
save_fig(fig, 'frame_stress_bump');
info = struct('k_family', k, 'mass_family', m, 'peak_with', pa, 'peak_without', pb, 'case_names', names);
fprintf('make_media: frame_stress_cases.png, frame_torsion_diagonals.png, frame_stress_bump.png\n');
end

% =============================================================================
function mb = mass_table(file)
mb = mass_budget_quiet();
T = sortrows(mb.items, 'mass_kg', 'descend');
fid = fopen(file, 'w');
fprintf(fid, '# Mass budget\r\n\r\nGenerated by `matlab/make_media.m` on %s from `params/car_params.txt` (via `matlab/mass_budget.m`).\r\n\r\n', datestr(now, 'yyyy-mm-dd HH:MM')); %#ok<TNOW1,DATST>
fprintf(fid, 'Flags: CALC = computed from the CAD or frame files, CATALOGUE = a datasheet, ESTIMATE = a reasoned number, GUESS = a placeholder.\r\n\r\n');
fprintf(fid, '| Item | Mass (kg) | x (mm) | z (mm) | Flag |\r\n|---|---|---|---|---|\r\n');
for k = 1:height(T)
    fprintf(fid, '| %s | %.1f | %.0f | %.0f | %s |\r\n', T.item(k), T.mass_kg(k), T.x_mm(k), T.z_mm(k), T.flag(k));
end
fprintf(fid, '| **Car without driver** | **%.1f** | | | |\r\n| **With driver** | **%.1f** | %.0f | %.0f | |\r\n\r\n', mb.mass_car, mb.mass_total, mb.cg_x, mb.cg_z);
fprintf(fid, 'CG %.0f mm behind the front axle (%.1f %% front), %.0f mm above the ground. %.0f %% of the mass is a GUESS, so the CG height is partly a guess too.\r\n', ...
    mb.cg_x, 100 * mb.wd_front, mb.cg_z, 100 * mb.guess_fraction);
% wing lines and their supports (2026-11-28): the 6.0 and 7.0 kg guesses included the mounts, so the
% modelled supports are taken off them; shown as the split, wing + supports = the old guess
mi = @(n) mb.items.mass_kg(mb.items.item == n);
if any(mb.items.item == "fw_supports") && any(mb.items.item == "rw_supports")
    fprintf(fid, '\r\nWing lines: front_wing %.3f + fw_supports %.3f = %.3f kg; rear_wing %.3f + rw_supports %.3f = %.3f kg (the wing guesses included mounts and pylons; the supports are CALC from the CAD and are taken off them).\r\n', ...
        mi("front_wing"), mi("fw_supports"), mi("front_wing") + mi("fw_supports"), mi("rear_wing"), mi("rw_supports"), mi("rear_wing") + mi("rw_supports"));
end
fprintf(fid, '\r\nThe CAD packaging envelopes (`cad/generate/envelopes.py`) take their masses from these lines and add none; `cad/generate/cad_cg_report.txt` compares the CG from the CAD geometry with this one.\r\n');
fclose(fid);
fprintf('make_media: %s\n', file);
end

function mb = mass_budget_quiet()
evalc('mb = mass_budget();');
end

function L = lap_table(p, file)
% the default car (default_car(): FINAL; CP before 2026-11-28), before and after the torsion diagonals; "before" removes the
% diagonals' tube mass and their 13 % brackets-and-welds share from the
% budget at their own centroid. The lap sim takes the chassis as rigid, so
% only the mass and CG change shows.
T = readtable(fullfile(repo_root(), 'cad', 'frame', 'frame_tubes.csv'), 'TextType', 'string', 'CommentStyle', '#');
isd = contains(T.tube, ["_diag", "FH_M-SP2_U"]);
md = sum(T.mass_kg(isd)) * p.m_frame / sum(T.mass_kg) * (1 + p.m_brackets_welds / p.m_frame);   % CSV centreline mass scaled to the weldment's
N = readtable(fullfile(repo_root(), 'cad', 'frame', 'frame_nodes.csv'), 'TextType', 'string');
xyz = @(n) [N.x_mm(N.node == n), N.y_mm(N.node == n), N.z_mm(N.node == n)];
c = zeros(1, 3);
for k = find(isd).'
    c = c + T.mass_kg(k) * (xyz(T.node_a(k)) + xyz(T.node_b(k))) / 2;
end
c = c / sum(T.mass_kg(isd));
M = p.mass_car + p.mass_driver;
pb = p;
pb.mass_car = p.mass_car - md;
pb.cg_x_from_front_axle = (p.cg_x_from_front_axle * M - md * c(1)) / (M - md);
pb.cg_height = (p.cg_height * M - md * c(3)) / (M - md);
pb.weight_dist_front = 1 - pb.cg_x_from_front_axle / p.wheelbase;
tracks = {'skidpad', 'accel_75m', 'autocross', 'fast_circuit'};
V = {'A', 'B', 'C', 'D', 'CP', 'FINAL'};
ref = default_car();
t = nan(numel(tracks), 2, 2); tv = nan(numel(tracks), numel(V));
for k = 1:numel(tracks)
    tr = load_track(tracks{k});
    for s = 1:2
        pp = ternary(s == 1, pb, p);
        car = car_from_params(ref, pp);
        t(k, s, 1) = lap_quiet(car, tr, struct());
        t(k, s, 2) = lap_quiet(car, tr, struct('four_wheel', true));
    end
    for v = 1:numel(V), tv(k, v) = lap_quiet(car_from_params(V{v}, p), tr, struct()); end
end
fid = fopen(file, 'w');
fprintf(fid, '# Lap times\r\n\r\nGenerated by `matlab/make_media.m` on %s with `matlab/lapsim/lapsim.m`. ', datestr(now, 'yyyy-mm-dd HH:MM')); %#ok<TNOW1,DATST>
fprintf(fid, 'Quasi-steady simulation, perfect driver, rigid chassis. Use it to compare set-ups, not to predict a real lap.\r\n\r\n');
fprintf(fid, '## Aero variants (point-mass)\r\n\r\nA no wings, B moderate, C maximum, D wake-tuned: A and C on the older CFD bodywork, B and D on the as-built bodywork (runs B_AB, D_AB). CP is C''s wings on the SolidWorks nose, sidepods and floor plate (the car until 2026-11-28). **FINAL is the car**: CP with the F rear and J front wing supports (CFD run FINAL_bl1, 1 prism layer; its fair aero reference is CP_bl1, not the 2-layer CP row). Aero from `params/aero_variants.csv` (CFD of the half car, ranking quality).\r\n\r\n');
fprintf(fid, '| Track | A | B | C | D | CP (2-layer row) | **FINAL (the car)** |\r\n|---|---|---|---|---|---|---|\r\n');
for k = 1:numel(tracks), fprintf(fid, '| %s | %.2f s | %.2f s | %.2f s | %.2f s | %.2f s | **%.2f s** |\r\n', strrep(tracks{k}, '_', ' '), tv(k, :)); end
fprintf(fid, '\r\n## Effect of the frame torsion diagonals (%s, the car)\r\n\r\n', ref);
fprintf(fid, 'Before: the car with the %d diagonals removed (%.1f kg of tube plus brackets and welds, centroid x %.0f z %.0f mm): %.1f kg, CG x %.0f z %.0f mm. After: %.1f kg, CG x %.0f z %.0f mm (without driver; CG with driver).\r\n\r\n', ...
    sum(isd), md, c(1), c(3), pb.mass_car, pb.cg_x_from_front_axle, pb.cg_height, p.mass_car, p.cg_x_from_front_axle, p.cg_height);
fprintf(fid, '| Track | point-mass before | after | change | four-wheel before | after | change |\r\n|---|---|---|---|---|---|---|\r\n');
for k = 1:numel(tracks)
    fprintf(fid, '| %s | %.2f s | %.2f s | %+.2f s | %.2f s | %.2f s | %+.2f s |\r\n', strrep(tracks{k}, '_', ' '), ...
        t(k, 1, 1), t(k, 2, 1), t(k, 2, 1) - t(k, 1, 1), t(k, 1, 2), t(k, 2, 2), t(k, 2, 2) - t(k, 1, 2));
end
kq = @(a) frame_fe(setfield(struct('write', false, 'plot', false, 'torsion_only', true), a{:})).torsion.k_Nm_deg; %#ok<SFLD>
[~, k0] = evalc('kq({''drop_tubes'', ["_diag", "FH_M-SP2_U"]})'); [~, k1] = evalc('kq({''write'', false})');
fprintf(fid, '\r\nThe lap sim cannot credit the stiffer frame: it treats the chassis as rigid, so the stiffness gain (%.0f to %.0f Nm/deg) shows nowhere in these numbers, only the added mass does.\r\n', k0, k1);
fclose(fid);
L = struct('tracks', {tracks}, 't_C', t, 't_variants', tv, 'dm_kg', md);
fprintf('make_media: %s\n', file);
end

function tl = lap_quiet(car, tr, o)
evalc('r = lapsim(car, tr, o);');
tl = r.t_lap;
end

function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end

% =============================================================================
function ok = selftest()
% the GIF writer: two frames of known colour come back as two frames
f = [tempname '.gif'];
fig = figure('Visible', 'off', 'Position', [100 100 200 150], 'Color', 'r');
first = add_frame(fig, f, true, 0.1);
set(fig, 'Color', 'b'); add_frame(fig, f, first, 0.1); close(fig);
info = imfinfo(f);
ok = numel(info) == 2;
delete(f);
fprintf('make_media selftest: %s\n', string(ok));
if ~ok, error('make_media:selftest', 'self-test failed'); end
end
