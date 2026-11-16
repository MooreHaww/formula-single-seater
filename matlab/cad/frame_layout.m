function out = frame_layout(opts)
%FRAME_LAYOUT Spaceframe nodes and tube list, plotted against the envelopes.
%   out = frame_layout()            writes cad/frame/frame_nodes.csv and
%                                   frame_tubes.csv, plots media/frame_layout.png,
%                                   prints the clearance check
%   out = frame_layout(opts)        opts.plot, opts.write
%   frame_layout('--selftest')
%
%   Frame: x rearward from the front axle, y right, z up from the ground, mm.
%   Nodes are defined for the right side (y > 0) and the centreline; the
%   left side is mirrored automatically. Node positions that are suspension
%   pickups come straight from params/car_params.txt, so the frame follows
%   the hardpoints. Tube sizes come from tube_main_* and tube_secondary_*.
%
%   Envelopes checked (also from params where they exist): driver legs box,
%   torso box along the seat-back angle, helmet sphere, battery box, motor
%   cylinder, differential on the axle line, wheels at full bump and full
%   steering lock (approximate).
%
%   The CSVs are the input to the Ring 2b chassis: each node becomes a
%   3D-sketch point in cad/layout, each tube a Weldments structural member.

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'write'), opts.write = true; end
p = read_car_params();
[N, T] = define_frame(p);
E = envelopes(p);

% mirror: every node with y > 0 gets a twin with y < 0 and suffix _L
names = fieldnames(N);
NL = struct();
for k = 1:numel(names)
    nm = names{k}; pt = N.(nm);
    if pt(2) > 0
        NL.([nm '_R']) = pt; NL.([nm '_L']) = pt .* [1 -1 1];
    else
        NL.(nm) = pt;
    end
end
% expand tube list: a tube named between right-side nodes gets a left twin;
% a tube marked 'X' is a cross member between a node and its mirror
tubes = {};
for k = 1:size(T, 1)
    a = T{k, 1}; b = T{k, 2}; grp = T{k, 3};
    if strcmp(b, 'X')
        tubes(end+1, :) = {[a '_R'], [a '_L'], grp, [a '_cross']}; %#ok<AGROW>
    else
        tubes(end+1, :) = {sfx(NL, a, '_R'), sfx(NL, b, '_R'), grp, [a '-' b '_R']}; %#ok<AGROW>
        if isfield(NL, [a '_L']) || isfield(NL, [b '_L'])
            tubes(end+1, :) = {sfx(NL, a, '_L'), sfx(NL, b, '_L'), grp, [a '-' b '_L']}; %#ok<AGROW>
        end
    end
end
sizes = tube_sizes(p);
nT = size(tubes, 1);
L = zeros(nT, 1); od = L; wall = L; mass = L;
rho_steel = 7850e-9;    % kg/mm3
for k = 1:nT
    a = NL.(tubes{k, 1}); b = NL.(tubes{k, 2});
    L(k) = norm(b - a);
    s = sizes.(tubes{k, 3}); od(k) = s(1); wall(k) = s(2);
    mass(k) = pi / 4 * (od(k)^2 - (od(k) - 2 * wall(k))^2) * L(k) * rho_steel;
end
out.nodes = NL; out.tubes = tubes; out.length_mm = L; out.od = od; out.wall = wall; out.mass_kg = mass;
out.total_length_m = sum(L) / 1000; out.total_mass_kg = sum(mass);
out.envelopes = E;

% ---- clearance check ------------------------------------------------------------------
out.clearance = clearance_check(NL, tubes, od, E);

% ---- write ---------------------------------------------------------------------------------
if opts.write
    outDir = fullfile(repo_root(), 'cad', 'frame');
    write_csvs(outDir, out);
    fprintf('frame_layout: %d nodes, %d tubes, %.1f m of tube, %.1f kg -> cad/frame/*.csv\n', numel(fieldnames(NL)), nT, out.total_length_m, out.total_mass_kg);
    print_clearance(out.clearance);
end
if opts.plot
    plot_frame(NL, tubes, od, E, p, out);
end
end

% =============================================================================
function write_csvs(outDir, out)
% Writes frame_nodes.csv and frame_tubes.csv with CRLF line endings. The
% SolidWorks VBA macro (cad/macros/ImportFrameNodes.bas) now accepts LF too,
% but CRLF keeps Notepad, Excel and older macros happy. Mode 'w' plus an
% explicit \r\n gives CRLF on every OS ('wt' would only do so on Windows).
if ~isfolder(outDir), mkdir(outDir); end
NL = out.nodes; tubes = out.tubes; nn = fieldnames(NL);
fid = fopen(fullfile(outDir, 'frame_nodes.csv'), 'w');
fprintf(fid, 'node,x_mm,y_mm,z_mm,note\r\n');
for k = 1:numel(nn)
    fprintf(fid, '%s,%g,%g,%g,%s\r\n', nn{k}, NL.(nn{k}), node_note(nn{k}));
end
fclose(fid);
fid = fopen(fullfile(outDir, 'frame_tubes.csv'), 'w');
fprintf(fid, 'tube,node_a,node_b,group,od_mm,wall_mm,length_mm,mass_kg\r\n');
for k = 1:size(tubes, 1)
    fprintf(fid, '%s,%s,%s,%s,%g,%g,%.1f,%.3f\r\n', tubes{k, 4}, tubes{k, 1}, tubes{k, 2}, tubes{k, 3}, ...
        out.od(k), out.wall(k), out.length_mm(k), out.mass_kg(k));
end
fprintf(fid, '# total length %.2f m, total mass %.1f kg (steel 7850 kg/m3, no joints, no brackets)\r\n', out.total_length_m, out.total_mass_kg);
fclose(fid);
end

function [N, T] = define_frame(p)
% Right-side and centreline nodes. Names: FB front bulkhead, FS front
% suspension box, FBT front box top (rocker mount), FH front hoop, MH main
% hoop, RS rear suspension box, RT rear top (rear rocker and wing mounts).
hpF = @(n) [p.(['f_' n '_x']), p.(['f_' n '_y']), p.(['f_' n '_z'])];
hpR = @(n) [p.(['r_' n '_x']), p.(['r_' n '_y']), p.(['r_' n '_z'])];
N.FB_L  = [-300, 200, 80];
N.FB_U  = [-300, 200, 380];
N.FS1_L = hpF('lwb_in_fwd');
N.FS2_L = hpF('lwb_in_aft');
N.FS1_U = hpF('uwb_in_fwd');
N.FS2_U = hpF('uwb_in_aft');
N.FBT   = [p.f_pushrod_in_x, p.f_pushrod_in_y - 20, p.f_pushrod_in_z + 20];   % rocker pivot bracket sits here
N.FH_L  = [p.front_hoop_x, 290, 80];
N.FH_M  = [p.front_hoop_x, 290, 350];
N.FH_T  = [p.front_hoop_x, 230, 80 + p.front_hoop_height];
N.MH_L  = [p.main_hoop_x, 310, 80];
N.MH_M  = [p.main_hoop_x, 310, 350];
N.MH_B  = [p.main_hoop_x, 310, 620];
N.MH_T  = [p.main_hoop_x, 250, p.main_hoop_height];
N.RS1_L = hpR('lwb_in_fwd');
N.RS2_L = hpR('lwb_in_aft');
N.RS1_U = hpR('uwb_in_fwd');
N.RS2_U = hpR('uwb_in_aft');
N.RT1   = [p.r_uwb_in_fwd_x, p.r_uwb_in_fwd_y, p.r_pushrod_in_z + 20];
N.RT2   = [p.r_uwb_in_aft_x, p.r_uwb_in_aft_y, p.r_pushrod_in_z + 20];
N.RRK   = [p.r_pushrod_in_x, p.r_pushrod_in_y - 10, p.r_pushrod_in_z + 20];
% sidepod battery structure (only when the packs sit beside the driver):
% outer rails 25 mm outboard of the pack faces, in the front and main hoop planes
sidepods = isfield(p, 'battery_y_inner') && p.battery_y_inner > 0;
if sidepods
    ySP = p.battery_y_inner + p.battery_width + 25;
    N.SP1_L = [p.front_hoop_x, ySP, 80];
    N.SP1_U = [p.front_hoop_x, ySP, 320];
    N.SP2_L = [p.main_hoop_x, ySP, 80];
    N.SP2_U = [p.main_hoop_x, ySP, 320];
end

% tube list: {node_a, node_b, group}. 'X' = cross member to the mirror node.
T = {
    % front bulkhead and front box
    'FB_L', 'X', 'bulkhead';   'FB_U', 'X', 'bulkhead';   'FB_L', 'FB_U', 'bulkhead'
    'FB_L', 'FS1_L', 'front';  'FB_U', 'FS1_U', 'front';  'FB_U', 'FS1_L', 'front'
    'FS1_L', 'FS2_L', 'front'; 'FS1_U', 'FS2_U', 'front'; 'FS1_L', 'FS1_U', 'front'; 'FS2_L', 'FS2_U', 'front'
    'FS1_U', 'FS2_L', 'front'
    'FS1_L', 'X', 'front';     'FS2_L', 'X', 'front';     'FS1_U', 'X', 'front';     'FS2_U', 'X', 'front'
    'FBT', 'FS1_U', 'front';   'FBT', 'FS2_U', 'front';   'FBT', 'X', 'front'
    % front box to front hoop
    'FS2_L', 'FH_L', 'front';  'FS2_U', 'FH_M', 'front';  'FS2_U', 'FH_T', 'hoop_brace'; 'FS2_U', 'FH_L', 'front'
    % front hoop
    'FH_L', 'FH_M', 'hoop';    'FH_M', 'FH_T', 'hoop';    'FH_T', 'X', 'hoop';  'FH_L', 'X', 'front'
    % side impact structure
    'FH_L', 'MH_L', 'sis';     'FH_M', 'MH_M', 'sis';     'FH_L', 'MH_M', 'sis'
    % main hoop
    'MH_L', 'MH_M', 'hoop';    'MH_M', 'MH_B', 'hoop';    'MH_B', 'MH_T', 'hoop';   'MH_T', 'X', 'hoop';  'MH_L', 'X', 'sis'
    'FH_T', 'MH_B', 'hoop_brace'    % cockpit side rail / front hoop brace rearward
    % rear box
    'MH_L', 'RS1_L', 'rear';   'MH_M', 'RS1_U', 'rear';   'MH_L', 'RS1_U', 'rear'
    'RS1_L', 'RS2_L', 'rear';  'RS1_U', 'RS2_U', 'rear';  'RS1_L', 'RS1_U', 'rear'; 'RS2_L', 'RS2_U', 'rear'; 'RS1_L', 'RS2_U', 'rear'
    'RS1_L', 'X', 'rear';      'RS2_L', 'X', 'rear';      'RS1_U', 'X', 'rear';     'RS2_U', 'X', 'rear'
    'RS1_U', 'RT1', 'rear';    'RS2_U', 'RT2', 'rear';    'RT1', 'RT2', 'rear';     'RT1', 'X', 'rear'; 'RT2', 'X', 'rear'
    'RRK', 'RT1', 'rear';      'RRK', 'RT2', 'rear';      'RRK', 'X', 'rear'
    % main hoop braces (rearward)
    'MH_T', 'RT2', 'hoop_brace'; 'MH_B', 'RT1', 'hoop_brace'; 'MH_T', 'RT1', 'hoop_brace'
    };
if sidepods
    T = [T; {
        % sidepod battery boxes: outer rails, uprights, ties to the hoops, one diagonal
        'SP1_L', 'SP2_L', 'sidepod'; 'SP1_U', 'SP2_U', 'sidepod'; 'SP1_L', 'SP1_U', 'sidepod'; 'SP2_L', 'SP2_U', 'sidepod'
        'FH_L', 'SP1_L', 'sidepod';  'FH_M', 'SP1_U', 'sidepod';  'MH_L', 'SP2_L', 'sidepod';  'MH_M', 'SP2_U', 'sidepod'
        'SP1_L', 'SP2_U', 'sidepod'
        }];
end
end

function s = tube_sizes(p)
s.hoop = [p.tube_main_od, p.tube_main_wall];
s.hoop_brace = [p.tube_main_od, p.tube_main_wall];
s.sis = [p.tube_main_od, p.tube_secondary_wall];
s.sidepod = [p.tube_main_od, p.tube_secondary_wall];
s.bulkhead = [p.tube_main_od, p.tube_secondary_wall];
s.front = [p.tube_secondary_od, p.tube_secondary_wall];
s.rear = [p.tube_secondary_od, p.tube_secondary_wall];
end

function n = sfx(NL, a, side)
if isfield(NL, [a side]), n = [a side]; else, n = a; end
end

function s = node_note(n)
map = {'FB', 'front bulkhead'; 'FS1', 'front suspension fwd pickup'; 'FS2', 'front suspension aft pickup'; ...
    'FBT', 'front rocker mount'; 'FH', 'front hoop'; 'MH', 'main hoop'; 'RS1', 'rear suspension fwd pickup'; ...
    'RS2', 'rear suspension aft pickup'; 'RT', 'rear top / wing mount'; 'RRK', 'rear rocker mount'; ...
    'SP1', 'sidepod battery, front hoop plane'; 'SP2', 'sidepod battery, main hoop plane'};
s = '';
for k = 1:size(map, 1)
    if startsWith(n, map{k, 1}), s = map{k, 2}; end
end
end

% =============================================================================
function E = envelopes(p)
% boxes: [xmin xmax ymin ymax zmin zmax]; cylinders along y: [x z r halflen]
hip = [p.driver_hip_x, p.driver_hip_z];
a = p.seat_back_angle;
sh = hip + 560 * [sind(a), cosd(a)];                  % shoulder point (x, z)
% legs: feet on a heel rest above the lower rails, pedals ahead of x = 200
E.box.legs    = [200, hip(1), -190, 190, 150, 430];
bx = [p.battery_x_front, p.battery_x_front + p.battery_length]; bz = [p.battery_z_bottom, p.battery_z_bottom + p.battery_height];
if isfield(p, 'battery_y_inner') && p.battery_y_inner > 0
    % two packs in the sidepods, mirrored about the centreline
    E.box.battery_R = [bx, p.battery_y_inner, p.battery_y_inner + p.battery_width, bz];
    E.box.battery_L = [bx, -(p.battery_y_inner + p.battery_width), -p.battery_y_inner, bz];
else
    E.box.battery = [bx, -p.battery_width / 2, p.battery_width / 2, bz];
end
% torso: bounding box of a 280 mm thick slab along the seat back; the back
% surface lies in the main hoop plane, as on every FS car
E.box.torso   = [min(hip(1), sh(1)) - 60, min(max(hip(1), sh(1)) + 60, p.main_hoop_x), -230, 230, hip(2) - 60, sh(2) + 40];
E.sphere.helmet = [sh(1) + 200 * sind(a), 0, sh(2) + 200 * cosd(a), 150];
E.cyl.motor = [p.motor_x, p.motor_z, p.motor_diameter / 2, p.motor_length / 2];
E.cyl.diff  = [p.wheelbase, p.tyre_rolling_radius, 80, 150];
E.torso_line = [hip; sh];   % for the plot
end

function C = clearance_check(NL, tubes, od, E)
% minimum (surface to surface) distance between every tube and every envelope
C = struct('item', {}, 'tube', {}, 'clearance_mm', {}, 'required_mm', {}, 'ok', {});
req_box = 10; req_head = 50;
items = fieldnames(E.box);
for k = 1:size(tubes, 1)
    a = NL.(tubes{k, 1}); b = NL.(tubes{k, 2});
    pts = a + (b - a) .* linspace(0, 1, 41).';
    for j = 1:numel(items)
        bx = E.box.(items{j});
        d = min(point_box_distance(pts, bx)) - od(k) / 2;
        C(end+1) = struct('item', items{j}, 'tube', tubes{k, 4}, 'clearance_mm', d, 'required_mm', req_box, 'ok', d >= req_box); %#ok<AGROW>
    end
    s = E.sphere.helmet;
    d = min(vecnorm(pts - s(1:3), 2, 2)) - s(4) - od(k) / 2;
    C(end+1) = struct('item', 'helmet', 'tube', tubes{k, 4}, 'clearance_mm', d, 'required_mm', req_head, 'ok', d >= req_head); %#ok<AGROW>
    cy = fieldnames(E.cyl);
    for j = 1:numel(cy)
        c = E.cyl.(cy{j});
        inY = abs(pts(:, 2)) <= c(4) + od(k) / 2;
        dr = hypot(pts(:, 1) - c(1), pts(:, 3) - c(2)) - c(3) - od(k) / 2;
        dy = abs(pts(:, 2)) - c(4) - od(k) / 2;
        d = min(max(dr, dy));
        if ~any(inY), d = min(dy); end
        C(end+1) = struct('item', cy{j}, 'tube', tubes{k, 4}, 'clearance_mm', d, 'required_mm', req_box, 'ok', d >= req_box); %#ok<AGROW>
    end
end
end

function d = point_box_distance(pts, bx)
dx = max([bx(1) - pts(:, 1), zeros(size(pts, 1), 1), pts(:, 1) - bx(2)], [], 2);
dy = max([bx(3) - pts(:, 2), zeros(size(pts, 1), 1), pts(:, 2) - bx(4)], [], 2);
dz = max([bx(5) - pts(:, 3), zeros(size(pts, 1), 1), pts(:, 3) - bx(6)], [], 2);
d = sqrt(dx.^2 + dy.^2 + dz.^2);
end

function print_clearance(C)
bad = C(~[C.ok]);
if isempty(bad)
    fprintf('  clearance check: all tubes clear of driver, battery, motor and diff envelopes\n');
else
    fprintf('  clearance check: %d violations\n', numel(bad));
    for k = 1:numel(bad)
        fprintf('    %-10s vs %-18s %7.1f mm (need %g)\n', bad(k).item, bad(k).tube, bad(k).clearance_mm, bad(k).required_mm);
    end
end
items = unique({C.item});
for j = 1:numel(items)
    sel = strcmp({C.item}, items{j});
    fprintf('  closest tube to %-8s: %.0f mm\n', items{j}, min([C(sel).clearance_mm]));
end
end

% =============================================================================
function plot_frame(NL, tubes, od, E, p, out)
fig = figure('Name', 'frame layout', 'Position', [60 60 1300 800]);
views = {[-40 22], 'iso'; [0 0], 'side'; [0 90], 'top'};
for v = 1:3
    if v == 1, subplot(2, 2, [1 3]); else, subplot(2, 2, 2 * v - 2); end
    hold on
    for k = 1:size(tubes, 1)
        a = NL.(tubes{k, 1}); b = NL.(tubes{k, 2});
        lw = 1 + (od(k) > 25 && out.wall(k) > 2);
        plot3([a(1) b(1)], [a(2) b(2)], [a(3) b(3)], 'k-', 'LineWidth', lw);
    end
    draw_box(E.box.legs, [0.2 0.6 0.9]); draw_box(E.box.torso, [0.2 0.6 0.9]);
    bf = fieldnames(E.box);
    for j = find(startsWith(bf, 'battery'))', draw_box(E.box.(bf{j}), [0.9 0.6 0.1]); end
    draw_sphere(E.sphere.helmet, [0.2 0.6 0.9]);
    draw_cyl(E.cyl.motor, [0.8 0.2 0.2]); draw_cyl(E.cyl.diff, [0.5 0.5 0.5]);
    % wheels
    for xw = [0, p.wheelbase]
        if xw == 0, tr = p.track_front; else, tr = p.track_rear; end
        for sgn = [-1 1]
            draw_cyl([xw, p.tyre_rolling_radius, p.tyre_od / 2, p.tyre_width / 2], [0.3 0.3 0.3], sgn * tr / 2);
        end
    end
    axis equal; grid on; view(views{v, 1});
    xlabel('x (mm, rearward)'); ylabel('y (mm)'); zlabel('z (mm)');
    title(sprintf('%s view', views{v, 2}));
end
sgtitle(sprintf('Spaceframe layout: %d tubes, %.1f m, %.1f kg. Driver (blue), battery (orange), motor (red), diff (grey)', ...
    size(tubes, 1), out.total_length_m, out.total_mass_kg));
save_fig(fig, 'frame_layout');
end

function draw_box(b, col)
[X, Y, Z] = meshgrid(b(1:2), b(3:4), b(5:6));
k = convhull(X(:), Y(:), Z(:));
trisurf(k, X(:), Y(:), Z(:), 'FaceColor', col, 'FaceAlpha', 0.25, 'EdgeColor', col);
end

function draw_sphere(s, col)
[X, Y, Z] = sphere(16);
surf(s(1) + s(4) * X, s(2) + s(4) * Y, s(3) + s(4) * Z, 'FaceColor', col, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
end

function draw_cyl(c, col, y0)
if nargin < 3, y0 = 0; end
th = linspace(0, 2 * pi, 32);
for y = y0 + [-c(4), c(4)]
    plot3(c(1) + c(3) * cos(th), y * ones(size(th)), c(2) + c(3) * sin(th), '-', 'Color', col, 'LineWidth', 1.2);
end
for t = th(1:4:end)
    plot3(c(1) + c(3) * cos(t) * [1 1], y0 + [-c(4) c(4)], c(2) + c(3) * sin(t) * [1 1], '-', 'Color', col);
end
end

% =============================================================================
function ok = selftest()
% Hand checks:
%   (1) the front bulkhead lower cross tube spans y = -200 to +200: 400 mm
%   (2) point-to-box distance: point (0,0,0) to box [10 20 10 20 10 20] is
%       sqrt(3)*10 = 17.3205 mm; a point inside gives 0
%   (3) 1 m of 25.4 x 2.4 steel tube: area = pi/4 (25.4^2 - 20.6^2) = 173.4 mm2
%       -> 1.361 kg
o = frame_layout(struct('plot', false, 'write', false));
i = find(strcmp(o.tubes(:, 4), 'FB_L_cross'), 1);
ok = ~isempty(i) && abs(o.length_mm(i) - 400) < 1e-9;
d = point_box_distance([0 0 0; 15 15 15], [10 20 10 20 10 20]);
ok = ok && abs(d(1) - sqrt(3) * 10) < 1e-9 && d(2) == 0;
m1 = pi / 4 * (25.4^2 - 20.6^2) * 1000 * 7850e-9;
ok = ok && abs(m1 - 1.361) < 0.002;
ok = ok && all([o.clearance.ok]) && o.total_mass_kg > 15 && o.total_mass_kg < 50;
%   (4) CSV line endings: the nodes header 'node,x_mm,y_mm,z_mm,note' is 24
%       characters, so bytes 25 and 26 are CR LF (13 10); the file has as many
%       CRs as LFs (no bare LF) and nodes + 1 lines
tmp = tempname; write_csvs(tmp, o);
b = fileread(fullfile(tmp, 'frame_nodes.csv')); bt = fileread(fullfile(tmp, 'frame_tubes.csv'));
nCR = nnz(b == 13); nLF = nnz(b == 10);
ok = ok && isequal(double(b(25:26)), [13 10]) && nCR == nLF && nLF == numel(fieldnames(o.nodes)) + 1 ...
        && nnz(bt == 13) == nnz(bt == 10);
rmdir(tmp, 's');
if ok
    fprintf('frame_layout self-test: PASS (cross tube 400 mm, box distance %.4f mm, %d tubes %.1f kg, all clearances OK, CSVs CRLF)\n', d(1), size(o.tubes, 1), o.total_mass_kg);
else
    error('frame_layout self-test: FAIL (mass %.1f kg, clearance violations %d)', o.total_mass_kg, nnz(~[o.clearance.ok]));
end
end
