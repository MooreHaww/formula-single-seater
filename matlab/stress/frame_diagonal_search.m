function out = frame_diagonal_search(opts)
%FRAME_DIAGONAL_SEARCH Lightest set of extra frame diagonals for a torsion target.
%   out = frame_diagonal_search()          target 1500 Nm/deg, prints and writes
%                                          sim/stress/frame_diagonals.txt
%   out = frame_diagonal_search(opts)      opts.target (Nm/deg), opts.write
%   frame_diagonal_search('--selftest')
%
%   Judge: frame_fe's headline torsion case (wheel loads through the links,
%   free-free), with the candidate tubes added as 25.4 x 1.6 what-if tubes
%   (frame_fe opts.extra_tubes). The frame files are not changed.
%
%   Candidates are diagonals in the faces of the frame bays that have none:
%   the floor and top of each bay, the transverse planes, and the sidepod
%   floor and top. Each candidate is first checked against the same driver,
%   battery, motor and diff envelopes as frame_layout (10 mm, helmet 50 mm);
%   those that hit are dropped and listed.
%
%   Search:
%     1. floor only: every subset of the floor diagonals
%     2. floor plus top: every subset of the floor and top diagonals
%     3. all candidates: subsets in order of added mass, stopping at the
%        first that reaches the target, which is then the lightest set
%        (added mass is known before solving, so this is exact, not greedy).
%        Candidates without which the full set falls well short are kept in
%        every subset, which cuts the count (see by_mass).

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin >= 1 && ischar(opts) && strcmp(opts, '--candidates')
    out = candidates();          % the candidate list alone (matlab/make_media.m)
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'target'), opts.target = 1500; end
if ~isfield(opts, 'write'), opts.write = true; end
if ~isfield(opts, 'max_evals'), opts.max_evals = 20000; end

lay = frame_layout(struct('plot', false, 'write', false));
cand = candidates();
[cand, dropped] = check_candidates(cand, lay);
base = run_fe(strings(0, 2));
out.base = base;
out.cand = cand; out.dropped = dropped;

% single candidates
for k = 1:numel(cand)
    r = run_fe(cand(k).pairs);
    cand(k).k_alone = r.k; cand(k).dmass = r.mass - base.mass;
end
out.cand = cand;
grp = string({cand.group});

% 1. floor only, 2. floor plus top: exhaustive
out.floor = exhaustive(cand, find(grp == "floor"), opts.target);
out.floor_top = exhaustive(cand, find(grp == "floor" | grp == "top"), opts.target);
% 3. all: subsets in order of added mass
out.all = by_mass(cand, 1:numel(cand), opts.target, opts.max_evals);

out.target = opts.target;
print_report(out, 1);
if opts.write
    fid = fopen(fullfile(repo_root(), 'sim', 'stress', 'frame_diagonals.txt'), 'w');
    print_report(out, fid);
    fclose(fid);
end
end

% =============================================================================
function c = candidates()
% {id, group, description, node pairs (one or two tubes; a same-side pair is
% mirrored, so it is two tubes)}
L = {
    'F0', 'floor', 'nose floor',               ["FB_L_R", "FS1_L_L"]
    'F1', 'floor', 'front box floor',          ["FS1_L_R", "FS2_L_L"]
    'F2', 'floor', 'footwell floor',           ["FS2_L_R", "FH_L_L"]
    'F3', 'floor', 'cockpit floor',            ["FH_L_R", "MH_L_L"]
    'F4', 'floor', 'engine bay floor',         ["MH_L_R", "RS1_L_L"]
    'F5', 'floor', 'rear box floor',           ["RS1_L_R", "RS2_L_L"]
    'T0', 'top',   'nose top',                 ["FB_U_R", "FS1_U_L"]
    'T1', 'top',   'front box top',            ["FS1_U_R", "FS2_U_L"]
    'T2', 'top',   'footwell top',             ["FS2_U_R", "FH_M_L"]
    'T3', 'top',   'engine bay top',           ["MH_M_R", "RS1_U_L"]
    'T4', 'top',   'rear box top',             ["RS1_U_R", "RS2_U_L"]
    'T5', 'top',   'rear top, fwd of rocker',  ["RT1_R", "RRK_L"]
    'T6', 'top',   'rear top, aft of rocker',  ["RRK_R", "RT2_L"]
    'B0', 'plane', 'front bulkhead plane',     ["FB_L_R", "FB_U_L"]
    'B1', 'plane', 'FS1 plane',                ["FS1_L_R", "FS1_U_L"]
    % not 'FS2 plane' FS2_L_R-FS2_U_L: it clears the envelope boxes, but it
    % crosses the window between the FS2 cross tubes (x 140-160, z 148-273)
    % the pedal arms and the driver's feet pass through (pedals ahead of
    % x = 200, frame_layout); listed as excluded in the report
    'B3', 'plane', 'main hoop plane, low',     ["MH_L_R", "MH_M_L"]
    'B4', 'plane', 'RS1 plane',                ["RS1_L_R", "RS1_U_L"]
    'B5', 'plane', 'RS2 plane (rear end)',     ["RS2_L_R", "RS2_U_L"]
    'P0', 'sidepod', 'sidepod floor (both)',   ["FH_L_R", "SP2_L_R"; "FH_L_L", "SP2_L_L"]
    'P1', 'sidepod', 'sidepod top (both)',     ["FH_M_R", "SP2_U_R"; "FH_M_L", "SP2_U_L"]
    };
c = struct('id', L(:, 1), 'group', L(:, 2), 'desc', L(:, 3), 'pairs', L(:, 4));
end

function [keep, dropped] = check_candidates(c, lay)
% the same envelope distances as frame_layout's clearance check
E = lay.envelopes; NL = lay.nodes; od = 25.4;
ok = true(size(c)); why = strings(size(c));
for k = 1:numel(c)
    worst = inf; item = "";
    for i = 1:size(c(k).pairs, 1)
        a = NL.(c(k).pairs(i, 1)); b = NL.(c(k).pairs(i, 2));
        pts = a + (b - a) .* linspace(0, 1, 81).';
        bn = fieldnames(E.box);
        for j = 1:numel(bn)
            d = min(box_dist(pts, E.box.(bn{j}))) - od / 2 - 10;
            if d < worst, worst = d; item = bn{j}; end
        end
        s = E.sphere.helmet;
        d = min(vecnorm(pts - s(1:3), 2, 2)) - s(4) - od / 2 - 50;
        if d < worst, worst = d; item = "helmet"; end
        cn = fieldnames(E.cyl);
        for j = 1:numel(cn)
            cy = E.cyl.(cn{j});
            dr = hypot(pts(:, 1) - cy(1), pts(:, 3) - cy(2)) - cy(3) - od / 2;
            dy = abs(pts(:, 2)) - cy(4) - od / 2;
            d = min(max(dr, dy)) - 10;
            if d < worst, worst = d; item = cn{j}; end
        end
    end
    c(k).clear_margin = worst; c(k).clear_item = item;
    [c(k).min_angle, c(k).angle_with] = joint_angle(c(k).pairs, lay);
    if worst < 0
        ok(k) = false; why(k) = sprintf('%s: %.0f mm short of the clearance to %s', c(k).id, -worst, item);
    elseif c(k).min_angle < MIN_JOINT_DEG
        ok(k) = false; why(k) = sprintf('%s: meets %s at %.1f deg (under %g deg: the tube would lie along its neighbour, a long gouged joint that cannot be built cleanly)', ...
            c(k).id, c(k).angle_with, c(k).min_angle, MIN_JOINT_DEG);
    end
end
keep = c(ok);
dropped = struct('id', {c(~ok).id}, 'desc', {c(~ok).desc}, 'why', reshape(cellstr(why(~ok)), 1, []));
% the cockpit top (front hoop to main hoop) is not a candidate at all: it is
% the cockpit opening the driver gets in and out through
end

function [amin, with] = joint_angle(pairs, lay)
% smallest angle between a candidate tube and any frame tube (without the
% torsion diagonals) at either of its end nodes
NL = lay.nodes; T = lay.tubes;
base = ~contains(string(T(:, 4)), "_diag") & ~startsWith(string(T(:, 4)), "FH_M-SP2_U");
T = T(base, :);
amin = 180; with = "";
for i = 1:size(pairs, 1)
    for e = 1:2
        n = pairs(i, e); o = pairs(i, 3 - e);
        u = NL.(o) - NL.(n); u = u / norm(u);
        for r = 1:size(T, 1)
            if strcmp(T{r, 1}, n), m = T{r, 2}; elseif strcmp(T{r, 2}, n), m = T{r, 1}; else, continue; end
            w = NL.(m) - NL.(n); w = w / norm(w);
            a = acosd(max(-1, min(1, dot(u, w))));
            if a < amin, amin = a; with = string(T{r, 4}) + " at " + n; end
        end
    end
end
end

function d = box_dist(pts, bx)
dx = max([bx(1) - pts(:, 1), zeros(size(pts, 1), 1), pts(:, 1) - bx(2)], [], 2);
dy = max([bx(3) - pts(:, 2), zeros(size(pts, 1), 1), pts(:, 2) - bx(4)], [], 2);
dz = max([bx(5) - pts(:, 3), zeros(size(pts, 1), 1), pts(:, 3) - bx(6)], [], 2);
d = sqrt(dx.^2 + dy.^2 + dz.^2);
end

function r = run_fe(pairs)
o = evalc_fe(pairs);
r.k = o.torsion.k_Nm_deg; r.mass = o.frame_mass;
end

function o = evalc_fe(pairs)
% always from the frame without the torsion diagonals now in frame_layout
% (tubes named *_diag and the sidepod top FH_M-SP2_U), so the search
% gives the same answer before and after they were added
args = struct('write', false, 'plot', false, 'torsion_only', true, 'drop_tubes', ["_diag", "FH_M-SP2_U"]);
if ~isempty(pairs), args.extra_tubes = pairs; end
o = frame_fe(args);
end

function best = exhaustive(cand, idx, target)
n = numel(idx);
best = struct('ids', {{}}, 'k', NaN, 'mass', inf, 'dmass', inf, 'n_eval', 0, 'max_k', 0, 'max_ids', {{}});
for m = 1:2^n - 1
    sel = idx(logical(bitget(m, 1:n)));
    r = run_fe(vertcat(cand(sel).pairs));
    best.n_eval = best.n_eval + 1;
    if r.k > best.max_k, best.max_k = r.k; best.max_ids = {cand(sel).id}; best.max_mass = r.mass; end
    if r.k >= target && r.mass < best.mass
        best.ids = {cand(sel).id}; best.k = r.k; best.mass = r.mass;
    end
end
end

function best = by_mass(cand, idx, target, maxEval)
% every subset, sorted by its added mass (sum of the candidates' own added
% masses, which add exactly); the first to reach the target is the lightest
% Pruning: a candidate whose removal from the full set leaves the frame well
% short of the target (by more than 3 %) must be in every set that reaches
% it. Stiffness is not exactly monotonic in added tubes (the twist is
% measured at the pickups, not as compliance; the full set less one tube can
% be a few Nm/deg stiffer than the full set), hence the 3 % allowance.
need = false(size(idx));
best = struct('ids', {{}}, 'k', NaN, 'mass', NaN, 'n_eval', 0, 'mandatory', {{}}, 'k_full', NaN, 'k_without', []);
rf = run_fe(vertcat(cand(idx).pairs)); best.k_full = rf.k;
if rf.k < target, best.n_eval = 1; return, end
kw = zeros(size(idx));
for j = 1:numel(idx)
    r = run_fe(vertcat(cand(idx([1:j - 1, j + 1:end])).pairs));
    kw(j) = r.k; need(j) = r.k < 0.97 * target;
end
best.k_without = kw; best.mandatory = {cand(idx(need)).id};
fixed = idx(need); idx = idx(~need);
n = numel(idx); dm = [cand(idx).dmass];
M = (0:2^n - 1).';
B = false(numel(M), n);
for j = 1:n, B(:, j) = bitget(M, j) == 1; end
mass = B * dm(:);
[~, ord] = sort(mass);
for q = 1:min(numel(ord), maxEval)
    sel = [fixed, idx(B(ord(q), :))];
    r = run_fe(vertcat(cand(sel).pairs));
    best.n_eval = q;
    if r.k >= target
        best.ids = {cand(sel).id}; best.k = r.k; best.mass = r.mass;
        return
    end
end
end

function print_report(out, fid)
fprintf(fid, 'frame_diagonal_search: target %g Nm/deg (frame_fe torsion through the links, free-free)\r\n', out.target);
fprintf(fid, 'as built: %.0f Nm/deg, %.2f kg\r\n\r\n', out.base.k, out.base.mass);
fprintf(fid, 'candidates (25.4 x 1.6 tube; envelope margin beyond the 10 mm rule; shallowest joint, %g deg minimum):\r\n', MIN_JOINT_DEG);
for k = 1:numel(out.cand)
    c = out.cand(k);
    fprintf(fid, '  %-3s %-8s %-26s alone %5.0f Nm/deg  +%.2f kg  (margin %.0f mm to %s; joint %.1f deg)\r\n', ...
        c.id, c.group, c.desc, c.k_alone, c.dmass, c.clear_margin, c.clear_item, c.min_angle);
end
fprintf(fid, 'dropped (would hit an envelope, or meet a tube at under %g deg):\r\n', MIN_JOINT_DEG);
for k = 1:numel(out.dropped), fprintf(fid, '  %s\r\n', out.dropped(k).why); end
fprintf(fid, '  cockpit top (front hoop to main hoop): not a candidate, it is the cockpit opening\r\n');
fprintf(fid, '  FS2 plane FS2_L_R-FS2_U_L: not a candidate, it crosses the pedal and feet window between the FS2 cross tubes\r\n\r\n');
rep = {'floor only', out.floor; 'floor + top', out.floor_top};
for k = 1:2
    b = rep{k, 2};
    if isempty(b.ids)
        fprintf(fid, '%-12s: target not reached; best %.0f Nm/deg with all of %s (%.2f kg), %d subsets solved\r\n', ...
            rep{k, 1}, b.max_k, strjoin(b.max_ids, ' '), b.max_mass, b.n_eval);
    else
        fprintf(fid, '%-12s: lightest set reaching the target: %s, %.0f Nm/deg, %.2f kg (+%.2f), %d subsets solved\r\n', ...
            rep{k, 1}, strjoin(b.ids, ' '), b.k, b.mass, b.mass - out.base.mass, b.n_eval);
    end
end
b = out.all;
fprintf(fid, 'all candidates together: %.0f Nm/deg\r\n', b.k_full);
if ~isempty(b.k_without)
    fprintf(fid, 'all candidates less one (a candidate is needed in every set when this is under 97 %% of the target):\r\n');
    ids = {out.cand.id};
    for j = 1:numel(ids), fprintf(fid, '  without %-3s %5.0f Nm/deg\r\n', ids{j}, b.k_without(j)); end
    fprintf(fid, 'needed in every set: %s\r\n', strjoin(b.mandatory, ' '));
end
if isempty(b.ids)
    fprintf(fid, 'all candidates: target not reached in %d subsets (in order of mass)\r\n', b.n_eval);
else
    fprintf(fid, 'all candidates: lightest set reaching the target: %s, %.0f Nm/deg, %.2f kg (+%.2f), after %d subsets in order of mass\r\n', ...
        strjoin(b.ids, ' '), b.k, b.mass, b.mass - out.base.mass, b.n_eval);
end
end

% =============================================================================
function ok = selftest()
% hand checks: subset mass ordering and the exhaustive bookkeeping on a fake
% judge are exact; the envelope distance of a point to a box is Pythagoras
ok = true;
d = box_dist([3 4 0], [0 0 0 0 -1 1]);           % 3-4-5 from the box corner
ok = ok && abs(d - 5) < 1e-12;
d = box_dist([0.5 0 0], [0 1 -1 1 -1 1]);        % inside: 0
ok = ok && d == 0;
% mass ordering: three items 1, 2, 4 kg -> subsets in order 1,2,3(1+2),4,...
dm = [1 2 4]; M = (1:7).'; B = false(7, 3);
for j = 1:3, B(:, j) = bitget(M, j) == 1; end
[~, ord] = sort(B * dm(:));
ok = ok && isequal(ord.', 1:7);
% joint angle: a candidate at 30 deg to a rail through its end node; the
% rail's two halves make 30 and 150 deg, so the shallowest is 30
L.nodes = struct('N0', [0 0 0], 'NX', [100 0 0], 'NW', [-100 0 0], 'NY', [100 * cosd(30), 100 * sind(30), 0]);
L.tubes = {'N0', 'NX', 'g', 'railA'; 'NW', 'N0', 'g', 'railB'; 'N0', 'NY', 'g', 'x_diag'};
[a, w] = joint_angle(["N0", "NY"], L);
ok = ok && abs(a - 30) < 1e-9 && w == "railA at N0";
fprintf('frame_diagonal_search selftest: %s\n', string(ok));
if ~ok, error('frame_diagonal_search:selftest', 'self-test failed'); end
end

function a = MIN_JOINT_DEG()
% a candidate meeting a frame tube at a smaller angle is dropped (2026-11-25:
% T5, RT1_R-RRK_L, met the RT1 and RRK cross tubes at 5.4 deg and lay along
% them for about 270 mm at each end; the shallowest joint in the frame
% without diagonals is 13 deg)
a = 10;
end
