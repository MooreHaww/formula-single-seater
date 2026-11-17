function plan = frame_trims(opts)
%FRAME_TRIMS Trim plan for the weldment: which tube ends are trimmed against which tubes.
%   plan = frame_trims()                 plan from frame_layout, writes cad/frame/frame_trims.csv
%   plan = frame_trims(struct('write', false))
%   frame_trims('--selftest')
%
%   Every tube in cad/frame/frame_tubes.csv ends at a node, so all overlaps
%   sit at nodes. Rule (2026-11-17, docs/log.md): at each node the tube ends
%   are ranked: thicker wall first (2.4 before 1.6), then the tube that
%   continues straight through the node (another tube within 18 deg of in
%   line), then group (hoop, hoop_brace, bulkhead, sis, front, rear,
%   sidepod), then the longer tube. The first runs through. Every other
%   tube is coped against every higher-ranked tube at the node, as it would
%   be fitted in the jig in that order. Two exactly collinear halves of one
%   rail (under 3 deg) keep their ends. SolidWorks lengthens a tube by about
%   2r/tan(angle) to reach its neighbour (up to 153 mm at the main-hoop
%   bend); the coped trim leaves the part outside the neighbour, and the
%   harness cuts that by the mitre plane (tools/sw_harness/Mitre.cs). Tubes with the same boundary set share a
%   row: Trim_<node> first, then Trim_<node>_b2, _b3 ... in rank order, so a
%   boundary is trimmed before it is used. The earlier rule (boundary = the
%   first tube plus its straight partner, all others against those only) left
%   10 joints where neither tube was cut against the other (CheckChassis
%   overlap warning, the spike above the main hoop, a stub through the nose).
%   The SolidWorks step (tools/sw_harness/TrimTubes.cs, cad/macros/TrimTubes.bas)
%   makes one Trim/Extend feature per row with a coped cut.
%
%   Output CSV columns: trim, node, boundary, trimmed  (tube ids joined by ';').
%   The plan follows the tube list; rerun after frame_layout when the frame changes.

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    plan = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'write'), opts.write = true; end

o = frame_layout(struct('plot', false, 'write', false));
plan = make_plan(o.nodes, o.tubes, o.wall, o.length_mm);
if opts.write
    write_plan(fullfile(repo_root(), 'cad', 'frame', 'frame_trims.csv'), plan);
    nT = sum(cellfun(@numel, {plan.trimmed}));
    fprintf('frame_trims: %d trim features (one per boundary set at a node), %d tube ends trimmed -> cad/frame/frame_trims.csv\n', numel(plan), nT);
end
end

% =============================================================================
function plan = make_plan(NL, tubes, wall, L)
groupOrder = {'hoop', 'hoop_brace', 'bulkhead', 'sis', 'front', 'rear', 'sidepod'};
nT = size(tubes, 1);
gRank = zeros(nT, 1);
for k = 1:nT
    r = find(strcmp(groupOrder, tubes{k, 3}), 1);
    if isempty(r), r = numel(groupOrder) + 1; end
    gRank(k) = r;
end
cosStraight = cosd(18); cosCollinear = cosd(3);
plan = struct('trim', {}, 'node', {}, 'boundary', {}, 'trimmed', {});
nn = fieldnames(NL);
for j = 1:numel(nn)
    n = nn{j};
    ends = find(strcmp(tubes(:, 1), n) | strcmp(tubes(:, 2), n));
    m = numel(ends);
    if m < 2, continue, end
    D = zeros(m, 3);
    for a = 1:m, D(a, :) = away(NL, tubes(ends(a), :), n); end
    C = D * D';                                   % cos between away vectors
    straight = any(C <= -cosStraight & ~eye(m), 2);
    wv = wall(:); lv = L(:);
    key = [-wv(ends), -straight, gRank(ends), -lv(ends)];
    [~, ord] = sortrows(key);
    ends = ends(ord); C = C(ord, ord);
    % boundary set of every lower-ranked tube
    B = cell(m, 1);
    for k = 2:m
        b = [];
        for q = 1:k - 1
            if C(q, k) <= -cosCollinear, continue, end          % collinear halves of one rail
            b(end + 1) = q; %#ok<AGROW>
        end
        B{k} = b;
    end
    % rows: tubes with the same boundary set, ordered by their highest-ranked boundary
    keys = cellfun(@(b) sprintf('%d,', b), B(2:end), 'UniformOutput', false);
    [uk, ~, ic] = unique(keys, 'stable');
    rows = struct('b', {}, 't', {});
    for u = 1:numel(uk)
        members = find(ic == u) + 1;
        b = B{members(1)};
        if isempty(b), continue, end
        rows(end + 1).b = b; rows(end).t = members; %#ok<AGROW>
    end
    if isempty(rows), continue, end
    [~, ro] = sort(arrayfun(@(r) max(r.b) * 1000 + min(r.t), rows));
    rows = rows(ro);
    for u = 1:numel(rows)
        if u == 1, nm = ['Trim_' n]; else, nm = sprintf('Trim_%s_b%d', n, u); end
        plan(end + 1).trim = nm; %#ok<AGROW>
        plan(end).node = n;
        plan(end).boundary = tubes(ends(rows(u).b), 4)';
        plan(end).trimmed = tubes(ends(rows(u).t), 4)';
    end
end
end

function d = away(NL, t, n)
% unit vector from node n along tube t
if strcmp(t{1}, n), d = NL.(t{2}) - NL.(t{1}); else, d = NL.(t{1}) - NL.(t{2}); end
d = d / norm(d);
end

function write_plan(file, plan)
fid = fopen(file, 'w');
fprintf(fid, 'trim,node,boundary,trimmed\r\n');
for k = 1:numel(plan)
    fprintf(fid, '%s,%s,%s,%s\r\n', plan(k).trim, plan(k).node, strjoin(plan(k).boundary, ';'), strjoin(plan(k).trimmed, ';'));
end
fclose(fid);
end

% =============================================================================
function ok = selftest()
% Hand case, node N at the origin (all tubes in the x-y plane):
%   H1 (A-N, 500 mm) and H2 (N-B, 400 mm) hoop tubes along x, 2.4 wall,
%   collinear through N; Q (N-D) hoop tube at 45 deg, 2.4; S (N-C) sis tube
%   along y, 1.6.
%   Rank: H1, H2 (2.4 and straight through; H1 longer), Q (2.4), S (1.6).
%   H2 is collinear with H1: not trimmed. Q: boundary {H1, H2}. S: boundary
%   {H1, H2, Q}. So two rows at N: Trim_N (H1;H2 | Q), Trim_N_b2 (H1;H2;Q | S).
% Corner case, node M: two sis tubes at 90 deg, E (M-F, 300 mm) and G (M-H,
%   200 mm): E runs through, G is trimmed against E (the first tube always
%   counts). So 3 rows in all.
NL = struct('N', [0 0 0], 'A', [-500 0 0], 'B', [400 0 0], 'C', [0 300 0], 'D', [200 200 0], ...
            'M', [0 0 1000], 'F', [300 0 1000], 'H', [0 200 1000]);
T = {'A', 'N', 'hoop', 'H1'; 'N', 'B', 'hoop', 'H2'; 'N', 'C', 'sis', 'S'; 'N', 'D', 'hoop', 'Q'; ...
     'M', 'F', 'sis', 'E'; 'M', 'H', 'sis', 'G'};
wall = [2.4 2.4 1.6 2.4 1.6 1.6];
L = zeros(6, 1);
for k = 1:6, L(k) = norm(NL.(T{k, 2}) - NL.(T{k, 1})); end
p = make_plan(NL, T, wall, L);
r1 = p(strcmp({p.trim}, 'Trim_N')); r2 = p(strcmp({p.trim}, 'Trim_N_b2')); rM = p(strcmp({p.trim}, 'Trim_M'));
ok = numel(p) == 3 && ~isempty(r1) && ~isempty(r2) && ~isempty(rM) ...
     && isequal(r1.boundary, {'H1', 'H2'}) && isequal(r1.trimmed, {'Q'}) ...
     && isequal(r2.boundary, {'H1', 'H2', 'Q'}) && isequal(r2.trimmed, {'S'}) ...
     && isequal(rM.boundary, {'E'}) && isequal(rM.trimmed, {'G'});
% real frame: every tube id exists, no tube is boundary and trimmed in one row,
% every tube end at a node with 2+ ends is trimmed at most once there,
% trim names unique
o = frame_layout(struct('plot', false, 'write', false));
pr = make_plan(o.nodes, o.tubes, o.wall, o.length_mm);
ids = o.tubes(:, 4);
ok = ok && all(ismember([pr.boundary, pr.trimmed], ids)) && numel(unique({pr.trim})) == numel(pr);
for k = 1:numel(pr)
    ok = ok && isempty(intersect(pr(k).boundary, pr(k).trimmed));
end
nodes = unique({pr.node});
for k = 1:numel(nodes)
    tr = [pr(strcmp({pr.node}, nodes{k})).trimmed];
    ok = ok && numel(unique(tr)) == numel(tr);
end
nEnds = sum(cellfun(@numel, {pr.trimmed}));
if ok
    fprintf('frame_trims self-test: PASS (hand node N: Q against H1+H2, S against H1+H2+Q, collinear H2 kept; corner M: E trims G; real frame %d rows at %d nodes, %d trimmed ends)\n', numel(pr), numel(nodes), nEnds);
else
    error('frame_trims self-test: FAIL');
end
end
