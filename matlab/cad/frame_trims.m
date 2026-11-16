function plan = frame_trims(opts)
%FRAME_TRIMS Trim plan for the weldment: which tube ends are trimmed against which tubes.
%   plan = frame_trims()                 plan from frame_layout, writes cad/frame/frame_trims.csv
%   plan = frame_trims(struct('write', false))
%   frame_trims('--selftest')
%
%   Every tube in cad/frame/frame_tubes.csv ends at a node, so all overlaps
%   sit at nodes. At each node with two or more tube ends:
%     * the boundary is the highest-ranked tube there: thicker wall first
%       (2.4 before 1.6), then group (hoop, hoop_brace, bulkhead, sis, front,
%       rear, sidepod), then the longer tube. A tube of the same group that
%       continues within 18 deg of straight through joins the boundary, so a
%       continuous rail stays whole (its two halves keep their ends);
%     * every other tube ending at that node is trimmed against the boundary.
%   One row per node that has something to trim; the SolidWorks macro
%   cad/macros/TrimTubes.bas makes one Trim/Extend feature per row, named
%   Trim_<node>, with a coped cut (tube ends follow the boundary tube surface).
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
    fprintf('frame_trims: %d trim features (one per node), %d tube ends trimmed -> cad/frame/frame_trims.csv\n', numel(plan), nT);
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
% sort key: thicker wall, then group, then longer
key = [-wall(:), gRank, -L(:)];
plan = struct('trim', {}, 'node', {}, 'boundary', {}, 'trimmed', {});
nn = fieldnames(NL);
for j = 1:numel(nn)
    n = nn{j};
    ends = find(strcmp(tubes(:, 1), n) | strcmp(tubes(:, 2), n));
    if numel(ends) < 2, continue, end
    [~, ord] = sortrows(key(ends, :));
    ends = ends(ord);
    t1 = ends(1);
    boundary = t1;
    % same-group partner that continues straight through the node
    d1 = away(NL, tubes(t1, :), n);
    best = -0.95; partner = [];                 % cos(162 deg) = -0.951
    for k = ends(2:end)'
        if ~strcmp(tubes{k, 3}, tubes{t1, 3}), continue, end
        c = dot(d1, away(NL, tubes(k, :), n));
        if c < best, best = c; partner = k; end
    end
    boundary = [boundary, partner]; %#ok<AGROW>
    trimmed = setdiff(ends, boundary, 'stable');
    if isempty(trimmed), continue, end
    plan(end + 1).trim = ['Trim_' n]; %#ok<AGROW>
    plan(end).node = n;
    plan(end).boundary = tubes(boundary, 4)';
    plan(end).trimmed = tubes(trimmed, 4)';
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
% Hand case, node N at the origin:
%   H1 (A-N) and H2 (N-B) are hoop tubes along x, 2.4 wall, straight through N;
%   S (N-C) is a sis tube along y, 1.6 wall; Q (N-D) is a hoop tube at 45 deg
%   (not straight through).
%   At N: the boundary is the longest hoop tube H1 (500 > 400 > 283 mm) plus
%   its straight-through partner H2 (cos = -1); S and Q are trimmed.
%   At A, B, C, D only one tube ends: no row. So exactly 1 row.
% Corner case, node M: two sis tubes at 90 deg, E (M-F, 300 mm) and G (M-H,
%   200 mm): the longer E is the boundary, G is trimmed; no partner (cos 0).
NL = struct('N', [0 0 0], 'A', [-500 0 0], 'B', [400 0 0], 'C', [0 300 0], 'D', [200 200 0], ...
            'M', [0 0 1000], 'F', [300 0 1000], 'H', [0 200 1000]);
T = {'A', 'N', 'hoop', 'H1'; 'N', 'B', 'hoop', 'H2'; 'N', 'C', 'sis', 'S'; 'N', 'D', 'hoop', 'Q'; ...
     'M', 'F', 'sis', 'E'; 'M', 'H', 'sis', 'G'};
wall = [2.4 2.4 1.6 2.4 1.6 1.6];
L = zeros(6, 1);
for k = 1:6, L(k) = norm(NL.(T{k, 2}) - NL.(T{k, 1})); end
p = make_plan(NL, T, wall, L);
rowN = p(strcmp({p.node}, 'N')); rowM = p(strcmp({p.node}, 'M'));
ok = numel(p) == 2 && isequal(sort(rowN.boundary), {'H1', 'H2'}) && isequal(sort(rowN.trimmed), {'Q', 'S'}) ...
     && isequal(rowM.boundary, {'E'}) && isequal(rowM.trimmed, {'G'});
% real frame: every tube id in the plan exists, no tube is both boundary and
% trimmed in one row, every node with 2+ ends that is not a straight pass has a row
o = frame_layout(struct('plot', false, 'write', false));
pr = make_plan(o.nodes, o.tubes, o.wall, o.length_mm);
ids = o.tubes(:, 4);
allIds = [pr.boundary, pr.trimmed];
ok = ok && all(ismember(allIds, ids));
for k = 1:numel(pr)
    ok = ok && isempty(intersect(pr(k).boundary, pr(k).trimmed));
end
nEnds = sum(cellfun(@numel, {pr.trimmed}));
if ok
    fprintf('frame_trims self-test: PASS (hand node N: boundary H1+H2, trimmed Q+S; corner M: E trims G; real frame %d rows, %d trimmed ends)\n', numel(pr), nEnds);
else
    error('frame_trims self-test: FAIL');
end
end
