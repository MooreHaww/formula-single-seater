function out = frame_fe(opts)
%FRAME_FE Linear 3D beam finite-element model of the spaceframe.
%   out = frame_fe()            all load cases, report and figure
%   out = frame_fe(opts)        opts.write (true): sim/stress/frame_fe_report.txt,
%                               opts.plot (true): media/frame_fe_*.png,
%                               opts.p: parameter struct, opts.variant ('C')
%   frame_fe('--selftest')
%
%   Model (written out in docs/stress_frame.md):
%   - Nodes and tubes from cad/frame/frame_nodes.csv and frame_tubes.csv
%     (matlab/cad/frame_layout.m), one Euler-Bernoulli beam element per tube
%     (exact for loads at the nodes), rigid welded joints at the node points,
%     round tube sections from the CSV (OD, wall). Steel 4130: E 205 GPa,
%     G 80 GPa, density 7850 kg/m3, yield 435 MPa (normalised).
%   - Stress: at both ends of every tube (with loads only at the nodes the
%     moments are largest there), outer fibre: sigma = |N|/A + |M|/Z,
%     tau = |T| r/J, von Mises sqrt(sigma^2 + 3 tau^2). No stress
%     concentration at the welds, no buckling check (see the docs).
%   - Suspension loads: the contact-patch forces of sim/stress/load_cases.csv
%     (matlab/load_cases.m) go through each upright into its six links
%     (six-link statics at the static position, hardpoints from the params;
%     the corner's own unsprung mass is taken off), and each link force acts
%     on the frame at the node nearest its inboard point. Where the pickup is
%     off the node (tie rod / toe link on the rack or bracket, pushrod on the
%     rocker) the offset moment goes in too, as through a rigid bracket.
%   - Braking, cornering and the other driving cases: inertia relief. The
%     sprung masses of the mass budget are lumped on the frame nodes they
%     sit on (frame tubes at their ends), gravity acts on them, downforce on
%     the wing mounts, and the rigid-body acceleration that balances all of
%     it is solved for and applied as d'Alembert forces. Three nodes then
%     hold the six rigid-body motions (3-2-1, reactions close to zero by
%     construction) and deflections are reported with the mass-weighted
%     rigid-body motion removed. The solved acceleration is checked against
%     the load case's (a check on the whole load path).
%   - Torsion (the stiffness number): equal and opposite vertical forces at
%     the four contact patches (front left up, front right down, the rear
%     the other way with the same torque) go through the links into the
%     frame, free-free (the moments balance, inertia relief removes the rigid
%     motions). Twist = rotation about x of the front wishbone pickups minus
%     that of the rear ones (from their vertical displacements), stiffness =
%     front torque / twist. Two variants for comparison: the couples applied
%     straight at the eight wishbone nodes per axle (the SolidWorks studies'
%     set-up), and the rear wishbone nodes held in x, y, z with the couple
%     at the front (an upper bound: holding eight nodes stiffens the rear bay).

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'write'), opts.write = true; end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'variant'), opts.variant = 'C'; end
if ~isfield(opts, 'p'), opts.p = read_car_params(); end
p = opts.p;
root = repo_root();
fr = read_frame(root);
if isfield(opts, 'drop_tubes'), fr = drop_tubes(fr, opts.drop_tubes); end     % what-if: tube names (or patterns) taken out
if isfield(opts, 'extra_tubes'), fr = add_tubes(fr, opts.extra_tubes); end   % what-if: extra 25.4 x 1.6 tubes, node pairs
mat = material();
mdl = build_model(fr, mat);
out.frame = fr; out.mat = mat;
out.frame_mass = sum(mdl.el_mass);

% --- suspension pickups and lumped masses -------------------------------------------
sg = suspension_geometry(struct('p', p, 'plot', false, 'travel', -1:1));
corners = corner_defs(sg.hardpoints, p);
pick = map_pickups(corners, fr);
lump = lumped_masses(fr, mdl, p);
out.pickups = pick; out.lumped = lump;

% --- torsion -----------------------------------------------------------------------------
% headline: wheel forces through the real links, free-free (what the car sees in warp)
out.torsion = torsion_wheel_case(mdl, fr, corners, pick, lump, 1000);
out.torsion.mass_efficiency = out.torsion.k_Nm_deg / out.frame_mass;
if isfield(opts, 'torsion_only') && opts.torsion_only, return, end   % for searches (frame_diagonal_search)
% the SolidWorks studies' set-up: couples at the wishbone nodes, free-free
out.torsion_nodes = torsion_free_case(mdl, fr, pick, lump, 1000);
% upper bound: the rear pickups held rigidly (stiffens the rear bay)
out.torsion_held = torsion_case(mdl, fr, pick, 1000);

% --- driving cases -------------------------------------------------------------------------
LC = readtable(fullfile(root, 'sim', 'stress', 'load_cases.csv'), 'TextType', 'string', 'VariableNamingRule', 'preserve');
LC.Properties.VariableNames{1} = 'lcase';      % 'case' is a MATLAB keyword
car = car_from_params(opts.variant, p);
names = unique(LC.lcase, 'stable');
names = names(names ~= "static");
out.cases = struct([]);
for k = 1:numel(names)
    rows = LC(LC.lcase == names(k), :);
    out.cases = [out.cases, driving_case(char(names(k)), rows, mdl, fr, corners, pick, lump, p, car)]; %#ok<AGROW>
end
if opts.write, write_report(out, p, root); end
if opts.plot, plot_results(out, mdl, fr, root); end
print_summary(out);
end

% =============================================================================================
% frame, material, model
function fr = read_frame(root)
N = readtable(fullfile(root, 'cad', 'frame', 'frame_nodes.csv'), 'TextType', 'string');
T = readtable(fullfile(root, 'cad', 'frame', 'frame_tubes.csv'), 'TextType', 'string');
T = T(~isnan(T.od_mm) & ismember(T.node_a, N.node), :);      % the file ends with comment rows
fr.node = N.node;
fr.xyz = [N.x_mm, N.y_mm, N.z_mm];
fr.tube = T.tube;
[~, a] = ismember(T.node_a, fr.node);
[~, b] = ismember(T.node_b, fr.node);
if any(a == 0) || any(b == 0), error('frame_fe:nodes', 'A tube names a node that is not in frame_nodes.csv'); end
fr.ends = [a, b];
fr.od = T.od_mm; fr.wall = T.wall_mm; fr.group = T.group;
end

function fr = drop_tubes(fr, pats)
% pats: string array of patterns; a tube whose name contains any is removed
% (a what-if, e.g. the frame before the torsion diagonals)
k = ~contains(fr.tube, string(pats));
fr.tube = fr.tube(k); fr.ends = fr.ends(k, :); fr.od = fr.od(k); fr.wall = fr.wall(k); fr.group = fr.group(k);
end

function fr = add_tubes(fr, pairs)
% pairs: n x 2 string array of node names; each becomes a 25.4 x 1.6 tube (a what-if, not written anywhere)
for i = 1:size(pairs, 1)
    [~, a] = ismember(pairs(i, 1), fr.node); [~, b] = ismember(pairs(i, 2), fr.node);
    if a == 0 || b == 0, error('frame_fe:nodes', 'extra tube %s-%s: unknown node', pairs(i, 1), pairs(i, 2)); end
    fr.ends(end + 1, :) = [a, b]; fr.tube(end + 1) = pairs(i, 1) + "-" + pairs(i, 2);
    fr.od(end + 1) = 25.4; fr.wall(end + 1) = 1.6; fr.group(end + 1) = "whatif";
end
end

function mat = material()
mat.E = 205e3;          % MPa (N/mm2)
mat.G = 80e3;
mat.rho = 7.85e-6;      % kg/mm3
mat.yield = 435;        % MPa, 4130 normalised
mat.fos_target = 1.5;
end

function mdl = build_model(fr, mat)
nn = size(fr.xyz, 1); ne = size(fr.ends, 1);
mdl.nn = nn; mdl.ndof = 6 * nn;
I = zeros(144 * ne, 1); J = I; V = I; c = 0;
mdl.T = cell(ne, 1); mdl.kl = cell(ne, 1); mdl.dofs = zeros(ne, 12);
mdl.A = zeros(ne, 1); mdl.Iy = mdl.A; mdl.Jt = mdl.A; mdl.r = mdl.A; mdl.L = mdl.A; mdl.el_mass = mdl.A;
for e = 1:ne
    a = fr.ends(e, 1); b = fr.ends(e, 2);
    d = fr.xyz(b, :) - fr.xyz(a, :); L = norm(d);
    D = fr.od(e); t = fr.wall(e); di = D - 2 * t;
    A = pi / 4 * (D^2 - di^2); Iy = pi / 64 * (D^4 - di^4); Jt = 2 * Iy;
    kl = beam_k(mat.E, mat.G, A, Iy, Iy, Jt, L);
    R = local_axes(d / L);
    Tm = blkdiag(R, R, R, R);
    dofs = [6 * a - 5:6 * a, 6 * b - 5:6 * b];
    kg = Tm.' * kl * Tm;
    [ii, jj] = ndgrid(dofs, dofs);
    I(c + 1:c + 144) = ii(:); J(c + 1:c + 144) = jj(:); V(c + 1:c + 144) = kg(:); c = c + 144;
    mdl.T{e} = Tm; mdl.kl{e} = kl; mdl.dofs(e, :) = dofs;
    mdl.A(e) = A; mdl.Iy(e) = Iy; mdl.Jt(e) = Jt; mdl.r(e) = D / 2; mdl.L(e) = L;
    mdl.el_mass(e) = mat.rho * A * L;
end
mdl.K = sparse(I, J, V, mdl.ndof, mdl.ndof);
mdl.K = (mdl.K + mdl.K.') / 2;
mdl.xyz = fr.xyz; mdl.ends = fr.ends;
end

function k = beam_k(E, G, A, Iy, Iz, J, L)
% 12 x 12 local stiffness, DOFs u v w rx ry rz at each end, x along the beam
k = zeros(12);
k([1 7], [1 7]) = E * A / L * [1 -1; -1 1];
k([4 10], [4 10]) = G * J / L * [1 -1; -1 1];
kz = E * Iz / L^3 * [12 6*L -12 6*L; 6*L 4*L^2 -6*L 2*L^2; -12 -6*L 12 -6*L; 6*L 2*L^2 -6*L 4*L^2];
k([2 6 8 12], [2 6 8 12]) = kz;
ky = E * Iy / L^3 * [12 -6*L -12 -6*L; -6*L 4*L^2 6*L 2*L^2; -12 6*L 12 6*L; -6*L 2*L^2 6*L 4*L^2];
k([3 5 9 11], [3 5 9 11]) = ky;
end

function R = local_axes(ex)
% rows: local x, y, z in global coordinates (round tubes: any y/z will do)
ref = [0 0 1];
if abs(ex * ref.') > 0.9, ref = [0 1 0]; end
ey = cross(ref, ex); ey = ey / norm(ey);
ez = cross(ex, ey);
R = [ex; ey; ez];
end

% =============================================================================================
% loads
function C = corner_defs(hp, p)
% the four corners: inboard points, outboard points, wheel centre, contact patch,
% unsprung mass; left corners mirrored in y
links = {'lwb_in_fwd', 'lwb_out'; 'lwb_in_aft', 'lwb_out'; 'uwb_in_fwd', 'uwb_out'; 'uwb_in_aft', 'uwb_out'; ...
         'tie_in', 'tie_out'; 'pushrod_in', 'pushrod_out'};
C = struct([]);
for cn = ["FL", "FR", "RL", "RR"]
    h = hp.(ternary(startsWith(cn, "F"), 'front', 'rear'));
    s = ternary(endsWith(cn, "L"), -1, 1);
    m = [1 s 1];
    c.name = cn;
    c.inner = zeros(6, 3); c.outer = zeros(6, 3);
    for i = 1:6
        c.inner(i, :) = h.(links{i, 1}) .* m;
        c.outer(i, :) = h.(links{i, 2}) .* m;
    end
    c.link_names = {'lwb_fwd', 'lwb_aft', 'uwb_fwd', 'uwb_aft', 'tie', 'pushrod'};
    c.wc = h.wheel_centre .* m;
    c.cp = [c.wc(1), c.wc(2), 0];
    c.m_unsprung = ternary(startsWith(cn, "F"), p.unsprung_mass_corner_front, p.unsprung_mass_corner_rear);
    C = [C, c]; %#ok<AGROW>
end
end

function pick = map_pickups(C, fr)
pick = struct([]);
for k = 1:numel(C)
    for i = 1:6
        d = vecnorm(fr.xyz - C(k).inner(i, :), 2, 2);
        [dm, n] = min(d);
        pick(k, i).node = n; pick(k, i).offset = C(k).inner(i, :) - fr.xyz(n, :); pick(k, i).dist = dm; %#ok<AGROW>
    end
end
end

function [t, resid] = link_forces(c, Fext, Pext)
% Six-link statics on the upright: link tensions t (N, + pulls the upright
% inboard) that balance external forces Fext (k x 3) acting at Pext (k x 3).
A = zeros(6); b = zeros(6, 1);
o = c.wc;
for i = 1:6
    u = c.inner(i, :) - c.outer(i, :); u = u / norm(u);
    A(1:3, i) = u.'; A(4:6, i) = cross(c.outer(i, :) - o, u).' / 1000;
end
for j = 1:size(Fext, 1)
    b(1:3) = b(1:3) - Fext(j, :).';
    b(4:6) = b(4:6) - cross(Pext(j, :) - o, Fext(j, :)).' / 1000;
end
t = A \ b;
resid = norm(A * t - b);
end

function F = add_force(F, node, f, m)
F(6 * node - 5:6 * node - 3) = F(6 * node - 5:6 * node - 3) + f(:);
if nargin > 3, F(6 * node - 2:6 * node) = F(6 * node - 2:6 * node) + m(:); end
end

function lump = lumped_masses(fr, mdl, p)
% Sprung masses on the frame nodes (kg per node). Frame tubes: half to each end.
nn = size(fr.xyz, 1);
mN = zeros(nn, 1);
for e = 1:numel(mdl.el_mass)
    mN(fr.ends(e, :)) = mN(fr.ends(e, :)) + mdl.el_mass(e) / 2;
end
mb = mass_budget_items(p);
idx = @(pat) find(~cellfun(@isempty, regexp(cellstr(fr.node), pat, 'once')));
lump.assign = {};
for k = 1:height(mb)
    it = char(mb.item(k)); m = mb.mass_kg(k);
    switch it
        case {'frame', 'corners_front', 'corners_rear'}
            continue          % frame: from the tubes; corners: unsprung
        case 'driver'
            nodes = idx('^(FH_L|FH_M|MH_L|MH_M)_');
        case 'battery'
            nodes = idx('^SP[12]_');
        case 'rear_wing'
            nodes = idx('^RT[12]_');
        case 'front_wing'
            nodes = idx('^FB_');
        otherwise
            d = vecnorm(fr.xyz - [mb.x_mm(k), 0, mb.z_mm(k)], 2, 2);
            [~, o] = sort(d); nodes = o(1:4);
    end
    mN(nodes) = mN(nodes) + m / numel(nodes);
    lump.assign(end + 1, :) = {it, m, strjoin(cellstr(fr.node(nodes)), ' ')};
end
lump.m = mN;
lump.total = sum(mN);
lump.cg = (mN.' * fr.xyz) / lump.total;
lump.unsprung = 2 * p.unsprung_mass_corner_front + 2 * p.unsprung_mass_corner_rear;
% rigid-body modes and mass matrix (translational lumped masses)
nd = 6 * nn;
Phi = zeros(nd, 6);
for n = 1:nn
    r = fr.xyz(n, :) - lump.cg;
    Phi(6 * n - 5:6 * n - 3, 1:3) = eye(3);
    Phi(6 * n - 5:6 * n - 3, 4:6) = [0 r(3) -r(2); -r(3) 0 r(1); r(2) -r(1) 0];  % theta x r
    Phi(6 * n - 2:6 * n, 4:6) = eye(3);
end
Mv = zeros(nd, 1);
for n = 1:nn, Mv(6 * n - 5:6 * n - 3) = mN(n); end
lump.Phi = Phi; lump.Mv = Mv;
end

function T = mass_budget_items(p)
% the item list of the mass budget without printing
T = evalc_quiet(@() mass_budget(struct('plot', false, 'write', false))); %#ok<NASGU> p: the budget reads the params file itself
T = T.items;
end

function out = evalc_quiet(f)
out = [];
evalc('out = f();');
end

% =============================================================================================
% solving
function u = solve_fixed(K, F, fixed)
nd = size(K, 1);
free = setdiff(1:nd, fixed);
u = zeros(nd, 1);
u(free) = K(free, free) \ F(free);
end

function [u, a, Feff] = solve_inertia_relief(mdl, lump, F, fr)
% acceleration a (6 x 1: m/s2-equivalent in N/kg on translations, rad/s2 *
% rotations) that balances F, d'Alembert forces, then a 3-2-1 support
Phi = lump.Phi; M = lump.Mv;
MPhi = M .* Phi;
a = (Phi.' * MPhi) \ (Phi.' * F);          % F = M a  (N, kg, mm units: N/kg = m/s2)
Feff = F - MPhi * a;
nA = find(fr.node == "FB_L_R"); nB = find(fr.node == "RS2_L_R"); nC = find(fr.node == "FB_L_L");
fixed = [6 * nA - 5, 6 * nA - 4, 6 * nA - 3, 6 * nB - 4, 6 * nB - 3, 6 * nC - 3];
u = solve_fixed(mdl.K, Feff, fixed);
% remove the mass-weighted rigid-body part
c = (Phi.' * MPhi) \ (MPhi.' * u);
u = u - Phi * c;
end

function s = element_stress(mdl, u)
% von Mises at both ends of every element (outer fibre), MPa; axial force N
ne = numel(mdl.L);
s.vm = zeros(ne, 2); s.N = zeros(ne, 1); s.M = zeros(ne, 2); s.Tq = zeros(ne, 1);
for e = 1:ne
    ul = mdl.T{e} * u(mdl.dofs(e, :));
    f = mdl.kl{e} * ul;                    % end forces on the element, local
    N = f(7); Tq = f(10);
    Z = mdl.Iy(e) / mdl.r(e);
    for j = 1:2
        o = 6 * (j - 1);
        M = hypot(f(o + 5), f(o + 6));
        sig = abs(N) / mdl.A(e) + M / Z;
        tau = abs(Tq) * mdl.r(e) / mdl.Jt(e);
        s.vm(e, j) = sqrt(sig^2 + 3 * tau^2);
        s.M(e, j) = M;
    end
    s.N(e) = N; s.Tq(e) = Tq;
end
[s.max, i] = max(s.vm(:));
[s.el, s.end] = ind2sub(size(s.vm), i);
end

% =============================================================================================
% cases
function nodes = wb_nodes(pick, k)
nodes = [pick(k, 1:4).node];
end

function r = torsion_case(mdl, fr, pick, Ftot)
% rear wishbone nodes held in x, y, z; +Ftot/4 up at each left front wishbone node,
% -Ftot/4 at each right one
F = zeros(mdl.ndof, 1);
nFL = wb_nodes(pick, 1); nFR = wb_nodes(pick, 2);
for n = nFL, F = add_force(F, n, [0 0 Ftot / 4]); end
for n = nFR, F = add_force(F, n, [0 0 -Ftot / 4]); end
rear = unique([wb_nodes(pick, 3), wb_nodes(pick, 4)]);
fixed = reshape([6 * rear - 5; 6 * rear - 4; 6 * rear - 3], 1, []);
u = solve_fixed(mdl.K, F, fixed);
r = torsion_measures(mdl, fr, pick, F, u, 'rear wishbone pickups held (x, y, z), front couple');
r.fixed_nodes = fr.node(rear);
end

function r = torsion_free_case(mdl, fr, pick, lump, Ftot)
% free-free: front couple as above, rear couple of the same torque the other way
F = zeros(mdl.ndof, 1);
yF = mean(abs(fr.xyz(wb_nodes(pick, 2), 2))); yR = mean(abs(fr.xyz(wb_nodes(pick, 4), 2)));
Fr = Ftot * yF / yR;
for n = wb_nodes(pick, 1), F = add_force(F, n, [0 0 Ftot / 4]); end
for n = wb_nodes(pick, 2), F = add_force(F, n, [0 0 -Ftot / 4]); end
for n = wb_nodes(pick, 3), F = add_force(F, n, [0 0 -Fr / 4]); end
for n = wb_nodes(pick, 4), F = add_force(F, n, [0 0 Fr / 4]); end
[u, a] = solve_inertia_relief(mdl, lump, F, fr);
r = torsion_measures(mdl, fr, pick, F, u, 'free-free, equal and opposite couples front and rear (inertia relief)');
r.accel = a;
end

function r = torsion_measures(mdl, fr, pick, F, u, bc)
uz = u(3:6:end);
tw = @(kL, kR) mean(atand((uz(wb_nodes(pick, kL)) - uz(wb_nodes(pick, kR))) ./ ...
    (fr.xyz(wb_nodes(pick, kR), 2) - fr.xyz(wb_nodes(pick, kL), 2))));
r.bc = bc;
% torque about x of the FRONT couple (free-free: the rear one is equal and opposite)
front = fr.xyz(:, 1) < mean(fr.xyz(:, 1));
r.torque_Nm = sum(F(3:6:end) .* fr.xyz(:, 2) .* front - F(2:6:end) .* fr.xyz(:, 3) .* front) / 1000;
r.twist_front = tw(1, 2); r.twist_rear = tw(3, 4);
r.twist_deg = r.twist_front - r.twist_rear;
r.k_Nm_deg = abs(r.torque_Nm / r.twist_deg);
r.u = u;
r.stress = element_stress(mdl, u);
% twist along the car: rotation about x of each station (nodes at one x, left/right pairs)
xs = unique(round(fr.xyz(:, 1)));
r.station_x = xs; r.station_twist = nan(size(xs));
for k = 1:numel(xs)
    idx = find(round(fr.xyz(:, 1)) == xs(k) & fr.xyz(:, 2) > 1);
    v = [];
    for i = idx.'
        j = find(abs(fr.xyz(:, 1) - fr.xyz(i, 1)) < 1 & abs(fr.xyz(:, 2) + fr.xyz(i, 2)) < 1 & abs(fr.xyz(:, 3) - fr.xyz(i, 3)) < 1);
        if ~isempty(j), v(end + 1) = atand((uz(j) - uz(i)) / (2 * fr.xyz(i, 2))); end %#ok<AGROW>
    end
    if ~isempty(v), r.station_twist(k) = mean(v); end
end
end

function r = torsion_wheel_case(mdl, fr, C, pick, lump, Fw)
% +Fw up at FL, -Fw at FR; the rear the other way with the same torque
tF = 2 * C(2).wc(2); tR = 2 * C(4).wc(2);
fz = [Fw, -Fw, -Fw * tF / tR, Fw * tF / tR];
F = zeros(mdl.ndof, 1);
for k = 1:4
    t = link_forces(C(k), [0 0 fz(k)], C(k).cp);
    F = apply_links(F, C(k), pick(k, :), t);
end
[u, a] = solve_inertia_relief(mdl, lump, F, fr);
r = torsion_measures(mdl, fr, pick, F, u, sprintf(['free-free, %g N up and down at the front contact patches and the same ' ...
    'torque the other way at the rear, through the links (inertia relief)'], Fw));
r.accel = a;
end

function F = apply_links(F, c, pk, t)
% link tensions t -> forces (and bracket moments) on the frame at the pickup nodes
for i = 1:6
    u = c.inner(i, :) - c.outer(i, :); u = u / norm(u);
    f = -t(i) * u;                                              % on the frame, at the pickup
    F = add_force(F, pk(i).node, f, cross(pk(i).offset, f));    % N and N mm, like the stiffness matrix
end
end

function r = driving_case(name, rows, mdl, fr, C, pick, lump, p, car)
g = 9.81;
% accelerations of the case in car axes (x rearward, y right, z up), m/s2:
% braking pushes everything forward relative to the car = acceleration
% rearward; the load cases turn left (Fy towards the inside = -y)
switch name
    case 'cornering',    acc = [0, -p.design_lateral_g * g, 0];              v = p.design_corner_speed;
    case 'braking',      acc = [p.design_braking_g * g, 0, 0];               v = p.design_braking_speed;
    case 'bump',         acc = [0, 0, (p.design_bump_g - 1) * g];            v = 0;
    case 'corner_brake', acc = [0.7 * p.design_braking_g * g, -0.7 * p.design_lateral_g * g, 0]; v = p.design_corner_speed;
    otherwise,           acc = [0 0 0]; v = 0;
end
F = zeros(mdl.ndof, 1);
r.name = name; r.links = zeros(4, 6); r.resid = 0;
for k = 1:4
    row = rows(rows.wheel == C(k).name, :);
    Ft = [-row.Fx_N, -row.Fy_N, row.Fz_N];                     % car axes
    % unsprung mass of the corner: its weight and inertia stay off the links
    Fu = C(k).m_unsprung * ([0 0 -g] - acc);
    [t, res] = link_forces(C(k), [Ft; Fu], [C(k).cp; C(k).wc]);
    r.links(k, :) = t.'; r.resid = max(r.resid, res);
    F = apply_links(F, C(k), pick(k, :), t);
end
% downforce on the wing mounts
DF = 0.5 * car.rho * car.ClA * v^2;
nF = find(startsWith(fr.node, "FB_")); nR = find(startsWith(fr.node, "RT"));
for n = nF.', F = add_force(F, n, [0 0 -DF * car.aero_front / numel(nF)]); end
for n = nR.', F = add_force(F, n, [0 0 -DF * (1 - car.aero_front) / numel(nR)]); end
% gravity on the sprung masses
F(3:6:end) = F(3:6:end) - lump.m * g;
[u, a, ~] = solve_inertia_relief(mdl, lump, F, fr);
r.accel = a; r.accel_expected = acc; r.downforce = DF;
r.u = u; r.stress = element_stress(mdl, u);
d = reshape(u, 6, []).'; dn = vecnorm(d(:, 1:3), 2, 2);
[r.max_defl, r.max_defl_node] = max(dn);
% relative motion of the front and rear suspension pickups (what the wheels feel)
r.defl_pickups = max(dn(unique([pick(:).node])));
end

% =============================================================================================
% output
function print_summary(out)
t = out.torsion;
fprintf('frame_fe: %d nodes, %d tubes, frame %.1f kg\n', size(out.frame.xyz, 1), numel(out.frame.tube), out.frame_mass);
fprintf('  torsion (through the links, free-free): %.0f Nm/deg (%.0f Nm, twist %.4f deg), %.1f Nm/deg/kg; peak %.0f MPa in %s\n', ...
    t.k_Nm_deg, abs(t.torque_Nm), t.twist_deg, t.mass_efficiency, t.stress.max, out.frame.tube(t.stress.el));
fprintf('  torsion (couples at the wishbone nodes, free-free, the SolidWorks set-up): %.0f Nm/deg\n', out.torsion_nodes.k_Nm_deg);
fprintf('  torsion (rear pickups held, upper bound): %.0f Nm/deg\n', out.torsion_held.k_Nm_deg);
for k = 1:numel(out.cases)
    c = out.cases(k);
    fprintf('  %-12s peak %.0f MPa in %s (FoS %.2f), max deflection %.2f mm at %s; accel %s vs case %s m/s2\n', c.name, ...
        c.stress.max, out.frame.tube(c.stress.el), out.mat.yield / c.stress.max, c.max_defl, out.frame.node(c.max_defl_node), ...
        mat2str(round(c.accel(1:3).', 2)), mat2str(round(c.accel_expected, 2)));
end
end

function write_report(out, p, root)
f = fullfile(root, 'sim', 'stress', 'frame_fe_report.txt');
fid = fopen(f, 'w');
c = onCleanup(@() fclose(fid));
fr = out.frame; m = out.mat;
fprintf(fid, 'Frame beam FE (matlab/stress/frame_fe.m), %s\n', datestr(now, 'yyyy-mm-dd HH:MM'));
fprintf(fid, 'Model: %d nodes, %d tubes (one beam element each, rigid joints), frame %.2f kg; 4130 E %.0f GPa, yield %.0f MPa, FoS wanted %.1f\n', ...
    size(fr.xyz, 1), numel(fr.tube), out.frame_mass, m.E / 1e3, m.yield, m.fos_target);
fprintf(fid, 'Load cases and boundary conditions: docs/stress_frame.md\n\n');
fprintf(fid, 'Pickups -> frame nodes\n');
cn = ["FL", "FR", "RL", "RR"]; ln = {'lwb_fwd', 'lwb_aft', 'uwb_fwd', 'uwb_aft', 'tie', 'pushrod'};
for k = [2 4]
    for i = 1:6
        fprintf(fid, '  %s %-8s -> %-8s %5.1f mm\n', cn(k), ln{i}, fr.node(out.pickups(k, i).node), out.pickups(k, i).dist);
    end
end
fprintf(fid, '\nSprung masses on the frame: %.1f kg (frame tubes %.1f kg + items), CG x %.0f z %.0f mm; unsprung %.1f kg not on the frame\n', ...
    out.lumped.total, out.frame_mass, out.lumped.cg(1), out.lumped.cg(3), out.lumped.unsprung);
for k = 1:size(out.lumped.assign, 1)
    fprintf(fid, '  %-17s %5.1f kg on %s\n', out.lumped.assign{k, :});
end
for tc = {out.torsion, out.torsion_nodes, out.torsion_held}
    t = tc{1};
    fprintf(fid, '\nTorsion, %s\n', t.bc);
    fprintf(fid, '  torque %.1f Nm, front twist %.5f deg, rear twist %.5f deg -> %.0f Nm/deg\n', t.torque_Nm, t.twist_front, t.twist_rear, t.k_Nm_deg);
    fprintf(fid, '  peak von Mises %.1f MPa in %s at %s\n', t.stress.max, fr.tube(t.stress.el), fr.node(fr.ends(t.stress.el, t.stress.end)));
    fprintf(fid, '  twist along the car (rotation about x per station, deg):');
    for k = 1:numel(t.station_x)
        if ~isnan(t.station_twist(k)), fprintf(fid, '  x %g: %.5f', t.station_x(k), t.station_twist(k)); end
    end
    fprintf(fid, '\n');
end
fprintf(fid, '\nMass efficiency: %.0f Nm/deg / %.1f kg = %.1f Nm/deg per kg of frame\n', out.torsion.k_Nm_deg, out.frame_mass, out.torsion.mass_efficiency);
for k = 1:numel(out.cases)
    cs = out.cases(k);
    fprintf(fid, '\nCase %s (load_cases.csv, downforce %.0f N)\n', cs.name, cs.downforce);
    fprintf(fid, '  link forces, N (+ tension): lwb_fwd lwb_aft uwb_fwd uwb_aft tie pushrod; statics residual %.2e\n', cs.resid);
    for j = 1:4, fprintf(fid, '    %s %s\n', cn(j), sprintf('%9.0f', cs.links(j, :))); end
    fprintf(fid, '  inertia relief: acceleration found %s m/s2 (case %s), rotation %s rad/s2\n', ...
        mat2str(round(cs.accel(1:3).', 2)), mat2str(round(cs.accel_expected, 2)), mat2str(round(cs.accel(4:6).' * 1000, 3)));
    fprintf(fid, '  peak von Mises %.1f MPa in %s at %s: factor of safety %.2f on yield\n', cs.stress.max, fr.tube(cs.stress.el), ...
        fr.node(fr.ends(cs.stress.el, cs.stress.end)), m.yield / cs.stress.max);
    [~, o] = sort(max(cs.stress.vm, [], 2), 'descend');
    fprintf(fid, '  next highest: %s\n', strjoin(arrayfun(@(e) sprintf('%s %.0f', fr.tube(e), max(cs.stress.vm(e, :))), o(2:6).', 'UniformOutput', false), ', '));
    fprintf(fid, '  max elastic deflection %.3f mm at %s; largest at a suspension pickup %.3f mm\n', cs.max_defl, fr.node(cs.max_defl_node), cs.defl_pickups);
end
fprintf('frame_fe: report -> %s\n', f);
end

function plot_results(out, mdl, fr, root)
fig = figure('Visible', 'off', 'Position', [100 100 1200 500]);
try, theme(fig, 'light'); catch, end      % the desktop may be in dark mode
cases = {out.torsion, out.cases(strcmp({out.cases.name}, 'braking')), out.cases(strcmp({out.cases.name}, 'cornering'))};
titles = {sprintf('Torsion %.0f Nm/deg', out.torsion.k_Nm_deg), 'Braking 1.5 g', 'Cornering 1.6 g'};
for k = 1:3
    subplot(1, 3, k); hold on; axis equal; view(35, 20); grid on
    r = cases{k};
    d = reshape(r.u, 6, []).'; sc = 50 / max(vecnorm(d(:, 1:3), 2, 2));
    vm = max(r.stress.vm, [], 2); cm = parula(256);
    for e = 1:size(fr.ends, 1)
        P = fr.xyz(fr.ends(e, :), :);
        plot3(P(:, 1), P(:, 2), P(:, 3), ':', 'Color', [0.7 0.7 0.7]);
        Q = P + sc * d(fr.ends(e, :), 1:3);
        ci = 1 + round(255 * min(1, vm(e) / max(vm)));
        plot3(Q(:, 1), Q(:, 2), Q(:, 3), '-', 'Color', cm(ci, :), 'LineWidth', 1.5);
    end
    title(sprintf('%s (peak %.0f MPa, x%.0f)', titles{k}, r.stress.max, sc)); xlabel('x'); ylabel('y'); zlabel('z');
end
save_fig(fig, 'frame_fe');     % saves to media/ and closes
end

function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end

% =============================================================================================
function ok = selftest()
% Hand-checkable cases on one tube (25.4 x 1.6, 500 mm, 4130):
% 1 cantilever tip load P: tip deflection P L^3 / (3 E I), root stress P L / Z
% 2 torque T: twist T L / (G J), shear T r / J
% 3 axial P: extension P L / (E A)
% 4 inertia relief on a free tube with an end load P: acceleration P / m,
%   reactions zero
% and on the real frame: the torsion couple gives an antisymmetric
% response (left = -right), and the driving cases balance (acceleration
% found = case acceleration within 5 %).
mat = material();
fr.node = ["A"; "B"]; fr.xyz = [0 0 0; 500 0 0]; fr.ends = [1 2]; fr.od = 25.4; fr.wall = 1.6; fr.tube = "AB"; fr.group = "t";
mdl = build_model(fr, mat);
A = mdl.A(1); I = mdl.Iy(1); J = mdl.Jt(1); L = 500; E = mat.E; G = mat.G; r = 12.7;
fixed = 1:6;
P = 100;
F = zeros(12, 1); F(9) = P;                                      % tip load in z
u = solve_fixed(mdl.K, F, fixed); s = element_stress(mdl, u);
ok = true;
ok = ok & chk(u(9), P * L^3 / (3 * E * I), 'cantilever tip deflection');
ok = ok & chk(s.vm(1, 1), P * L * r / I, 'cantilever root stress');
F = zeros(12, 1); F(10) = 50e3;                                  % 50 Nm torque
u = solve_fixed(mdl.K, F, fixed); s = element_stress(mdl, u);
ok = ok & chk(u(10), 50e3 * L / (G * J), 'twist T L / G J');
ok = ok & chk(s.vm(1, 1), sqrt(3) * 50e3 * r / J, 'von Mises of pure shear');
F = zeros(12, 1); F(7) = 1000;
u = solve_fixed(mdl.K, F, fixed);
ok = ok & chk(u(7), 1000 * L / (E * A), 'axial extension');
% inertia relief on the free tube
lump.m = [1; 1] * mdl.el_mass(1) / 2;
lump.cg = [250 0 0];
nd = 12; Phi = zeros(nd, 6);
for n = 1:2
    rr = fr.xyz(n, :) - lump.cg;
    Phi(6 * n - 5:6 * n - 3, 1:3) = eye(3);
    Phi(6 * n - 5:6 * n - 3, 4:6) = [0 rr(3) -rr(2); -rr(3) 0 rr(1); rr(2) -rr(1) 0];
    Phi(6 * n - 2:6 * n, 4:6) = eye(3);
end
lump.Phi = Phi; lump.Mv = repelem(lump.m, 6) .* repmat([1 1 1 0 0 0].', 2, 1);
F = zeros(12, 1); F(7) = 10;                                     % 10 N axial at one end
Pt = Phi(:, 1:3);                                               % a line of two masses has no inertia about its axis: translations only
a = (Pt.' * (lump.Mv .* Pt)) \ (Pt.' * F);
ok = ok & chk(a(1), 10 / sum(lump.m), 'inertia relief acceleration P / m');
% the real frame
o = frame_fe(struct('write', false, 'plot', false));
% antisymmetry needs a mirror-symmetric frame: the torsion diagonals (*_diag,
% one tube each from a right node to a left node, 2026-11-18) are not, so the
% check runs on the frame without them
os = frame_fe(struct('write', false, 'plot', false, 'torsion_only', true, 'drop_tubes', "_diag"));
os.torsion_held = torsion_case(build_model(os.frame, material()), os.frame, os.pickups, 1000);
t = os.torsion_held; uz = t.u(3:6:end);
iR = find(os.frame.node == "FS1_L_R"); iL = find(os.frame.node == "FS1_L_L");
ok = ok & chk(uz(iL), -uz(iR), 'torsion (frame without the single diagonals): left pickup moves opposite to the right');
for k = 1:numel(o.cases)
    c = o.cases(k);
    err = norm(c.accel(1:3).' - c.accel_expected) / max(9.81, norm(c.accel_expected));
    ok = ok & report(err < 0.05, sprintf('%s: acceleration found %s vs case %s (%.1f %%)', c.name, ...
        mat2str(round(c.accel(1:3).', 2)), mat2str(round(c.accel_expected, 2)), 100 * err));
end
if ok
    fprintf('frame_fe self-test: PASS (cantilever, torsion, axial, inertia relief by hand; frame torsion antisymmetric, %.0f Nm/deg; driving cases balance)\n', o.torsion.k_Nm_deg);
else
    error('frame_fe:selftest', 'frame_fe self-test: FAIL');
end
end

function ok = chk(v, ref, msg)
ok = abs(v - ref) <= 1e-6 * max(1, abs(ref));
report(ok, sprintf('%s: %.6g vs hand %.6g', msg, v, ref));
end

function ok = report(ok, msg)
if ok, fprintf('  ok   %s\n', msg); else, fprintf('  FAIL %s\n', msg); end
end
