function out = frame_trimmed_mass(opts)
%FRAME_TRIMMED_MASS Frame tube mass and centroid with the joint overlaps removed.
%   out = frame_trimmed_mass()          from cad/frame/frame_nodes.csv,
%                                       frame_tubes.csv and frame_trims.csv
%   out = frame_trimmed_mass(opts)      opts.dir (folder with the three CSVs),
%                                       opts.m_target (kg, scale the result to
%                                       a measured mass, e.g. SolidWorks')
%   frame_trimmed_mass('--selftest')
%
%   frame_tubes.csv gives every tube its full node-to-node centreline length,
%   so a coped tube end is counted again inside the tube it is welded to.
%   The weldment (BuildTubes / TrimTubes) cuts each trimmed end back to the
%   outside of its boundary tubes. This function does the same cut on the
%   CSV geometry, so the mass budget can use the trimmed mass and centroid:
%     - at every (tube, node) pair in frame_trims.csv the trimmed tube loses
%       the part of its wall that lies inside any of its boundary tubes;
%     - each boundary tube is a solid cylinder of its outside radius that
%       starts at the node and runs along the boundary tube (they all end at
%       the node; a through rail is two collinear tubes, so both halves are
%       boundaries);
%     - the thin wall is sampled as 72 lines along the tube at the mid-wall
%       radius; each line is cut where it leaves the last boundary, and the
%       end's retreat is the mean over the lines (the cope is a saddle, so
%       the mean is less than the outside radius);
%     - untrimmed ends (the tube that runs through, collinear rail halves)
%       keep their node-to-node length, as in the weldment.
%   Mass per tube = CSV mass * remaining length / CSV length; centroid at the
%   middle of the remaining length. With opts.m_target the masses are scaled
%   to that total (centroid unchanged).
%
%   out fields: m_csv, cg_csv (1x3 mm), m_trimmed, cg_trimmed, m_scaled,
%   scale, ends (number of trimmed ends), retreat_mm (per trimmed end),
%   per_tube (table: tube, length_mm, kept_mm, mass_kg, cx, cy, cz).

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'dir'), opts.dir = fullfile(repo_root(), 'cad', 'frame'); end
if ~isfield(opts, 'm_target'), opts.m_target = NaN; end

T = readtable(fullfile(opts.dir, 'frame_tubes.csv'), 'TextType', 'string', 'CommentStyle', '#');
N = readtable(fullfile(opts.dir, 'frame_nodes.csv'), 'TextType', 'string');
P = readtable(fullfile(opts.dir, 'frame_trims.csv'), 'TextType', 'string', 'Delimiter', ',');
T = T(~ismissing(T.tube) & T.tube ~= "", :);
xyz = containers.Map(cellstr(N.node), num2cell([N.x_mm N.y_mm N.z_mm], 2));
row = containers.Map(cellstr(T.tube), num2cell(1:height(T)));

nT = height(T);
cut = zeros(nT, 2);                 % retreat at node_a, node_b (mm)
ends = 0; retreat = [];
for r = 1:height(P)
    node = P.node(r);
    bnd = strtrim(split(P.boundary(r), ';'));
    trm = strtrim(split(P.trimmed(r), ';'));
    for t = trm.'
        k = row(char(t));
        if T.node_a(k) == node, e = 1; other = T.node_b(k);
        elseif T.node_b(k) == node, e = 2; other = T.node_a(k);
        else, error('frame_trimmed_mass:node', 'trim %s: tube %s does not end at %s', P.trim(r), t, node);
        end
        n0 = xyz(char(node)); u = xyz(char(other)) - n0; u = u / norm(u);
        B = zeros(0, 4);            % boundary axis w (1x3) and outside radius
        for b = bnd.'
            kb = row(char(b));
            if T.node_a(kb) == node, ob = T.node_b(kb); elseif T.node_b(kb) == node, ob = T.node_a(kb); else, continue; end
            w = xyz(char(ob)) - n0; w = w / norm(w);
            B(end+1, :) = [w, T.od_mm(kb) / 2]; %#ok<AGROW>
        end
        rm = (T.od_mm(k) - T.wall_mm(k)) / 2;
        c = end_retreat(u, rm, B);
        cut(k, e) = max(cut(k, e), c);
        ends = ends + 1; retreat(end+1, 1) = c; %#ok<AGROW>
    end
end

L = T.length_mm; kept = L - sum(cut, 2);
if any(kept <= 0), error('frame_trimmed_mass:short', 'a tube is cut away completely: %s', strjoin(T.tube(kept <= 0), ', ')); end
m = T.mass_kg .* kept ./ L;
c = zeros(nT, 3);
for k = 1:nT
    a = xyz(char(T.node_a(k))); b = xyz(char(T.node_b(k))); u = (b - a) / norm(b - a);
    c(k, :) = a + u * (cut(k, 1) + kept(k) / 2);
end
ca = zeros(nT, 3);
for k = 1:nT, ca(k, :) = (xyz(char(T.node_a(k))) + xyz(char(T.node_b(k)))) / 2; end

out.m_csv = sum(T.mass_kg); out.cg_csv = sum(T.mass_kg .* ca, 1) / out.m_csv;
out.m_trimmed = sum(m); out.cg_trimmed = sum(m .* c, 1) / out.m_trimmed;
out.scale = 1; out.m_scaled = out.m_trimmed;
if ~isnan(opts.m_target), out.scale = opts.m_target / out.m_trimmed; out.m_scaled = opts.m_target; end
out.ends = ends; out.retreat_mm = retreat;
out.per_tube = table(T.tube, L, kept, m * out.scale, c(:, 1), c(:, 2), c(:, 3), ...
    'VariableNames', {'tube', 'length_mm', 'kept_mm', 'mass_kg', 'cx', 'cy', 'cz'});
end

function c = end_retreat(u, rm, B)
% mean over the wall lines of the distance along u at which a line leaves
% the last boundary half-cylinder it starts in (0 if it starts outside all)
if isempty(B), c = 0; return; end
a1 = null(u(:).'); a1 = a1(:, 1).'; a2 = cross(u, a1);
phi = (0:71) * 2 * pi / 72;
% far enough for the shallowest boundary: a wall line can stay inside a
% cylinder at angle th for up to about 2R / tan(th) (271 mm at 5.4 deg)
s = sqrt(max(1 - (B(:, 1:3) * u(:)).^2, 0));
step = 0.05; tmax = min(1500, max(6 * max(B(:, 4)), max(2.2 * B(:, 4) ./ max(s, 0.02))));
ts = (0:step:tmax).';
c = 0;
for f = phi
    e = rm * (cos(f) * a1 + sin(f) * a2);
    Pt = e + ts * u;                         % points along the line, node at the origin
    in = false(size(ts));
    for j = 1:size(B, 1)
        w = B(j, 1:3); ax = Pt * w.'; rad = vecnorm(Pt - ax * w, 2, 2);
        in = in | (ax >= 0 & rad < B(j, 4));
    end
    if in(1)
        k = find(~in, 1);
        if isempty(k), k = numel(ts); end
        c = c + ts(k);
    end
end
c = c / numel(phi);
end

function ok = selftest()
% Hand check: a 25.4 x 1.6 tube trimmed square against a straight rail of the
% same size (the rail is two collinear tubes through the node). A wall line
% at angle f around the tube leaves the rail where t^2 + (rm sin f)^2 = R^2,
% so the mean retreat is mean(sqrt(R^2 - rm^2 sin^2 f)), with R = 12.7 and
% rm = 11.9: 12.7 * (2/pi) * E(m) = 12.7 * 0.6366 * 1.1218 = 9.07 mm (E =
% complete elliptic integral of the second kind, parameter m = (rm/R)^2 =
% 0.878). Tube 500 mm, 1 kg -> kept 490.93 mm, 0.98186 kg, centroid 4.54 mm
% further from the trimmed node (z 254.54 mm).
d = tempname; mkdir(d);
w = @(f, s) fwrite(fopen(fullfile(d, f), 'w'), s);
w('frame_nodes.csv', sprintf('node,x_mm,y_mm,z_mm,note\nN0,0,0,0,\nNX1,300,0,0,\nNX2,-300,0,0,\nNZ,0,0,500,\n'));
w('frame_tubes.csv', sprintf(['tube,node_a,node_b,group,od_mm,wall_mm,length_mm,mass_kg\n' ...
    'R1,N0,NX1,x,25.4,1.6,300,0.6\nR2,N0,NX2,x,25.4,1.6,300,0.6\nUP,N0,NZ,x,25.4,1.6,500,1.0\n']));
w('frame_trims.csv', sprintf('trim,node,boundary,trimmed\nTrim_N0,N0,R1;R2,UP\n'));
fclose('all');
o = frame_trimmed_mass(struct('dir', d));
[~, E] = ellipke((11.9 / 12.7)^2);
cHand = 12.7 * 2 / pi * E;
kUP = o.per_tube.tube == "UP";
ok = abs(o.retreat_mm - cHand) < 0.05 && abs(o.per_tube.kept_mm(kUP) - (500 - cHand)) < 0.05 ...
    && abs(o.per_tube.mass_kg(kUP) - (500 - cHand) / 500) < 1e-4 && abs(o.per_tube.cz(kUP) - (cHand + (500 - cHand) / 2)) < 0.05 ...
    && abs(o.m_csv - 2.2) < 1e-12 && o.ends == 1;
o2 = frame_trimmed_mass(struct('dir', d, 'm_target', 1.1));
ok = ok && abs(o2.m_scaled - 1.1) < 1e-12 && abs(sum(o2.per_tube.mass_kg) - 1.1) < 1e-9 && norm(o2.cg_trimmed - o.cg_trimmed) < 1e-9;
rmdir(d, 's');
if ok
    fprintf('frame_trimmed_mass self-test: PASS (square cope on a 25.4 x 1.6 rail: retreat %.2f mm, hand %.2f mm)\n', o.retreat_mm, cHand);
else
    error('frame_trimmed_mass self-test: FAIL (retreat %.3f mm, hand %.3f mm)', o.retreat_mm, cHand);
end
end
