function out = aero_estimate(opts)
%AERO_ESTIMATE Pre-CFD, first-principles aero estimate for variants A to D.
%   out = aero_estimate()         tables and figures to media/ (aero_estimate.md,
%                                 aero_estimate_table.csv, aero_estimate.png,
%                                 aero_estimate_wake.png)
%   out = aero_estimate(opts)     opts.plot, opts.write (true), opts.p (parameter
%                                 struct), opts.assume (struct of assumption
%                                 overrides, e.g. struct('inst_front', 0.7)),
%                                 opts.write_variants (false): also write the
%                                 four estimate rows into params/aero_variants.csv,
%                                 the table the lap sim reads (rows whose source
%                                 starts with CFD are never overwritten)
%   aero_estimate('--selftest')
%
%   EVERYTHING HERE IS AN ESTIMATE. Nothing is measured; no CFD result goes into it.
%   The numbers are handbook formulas with assumed coefficients; every
%   assumption is a named entry with a low and a high value (see the local
%   function assumptions), and the quoted range of each result is the
%   root-sum-square of the one-at-a-time changes. Method per component:
%
%   WINGS (front and rear, three elements each, sections from cad/airfoils)
%     1. Zero-lift angle of each section from thin-airfoil theory on the camber
%        line of its .dat file:  aL0 = -(1/pi) int_0^pi dz/dx (cos t - 1) dt.
%     2. The stack is one thin airfoil whose camber line is the chain of the
%        three zero-lift lines (Glauert flap theory):
%          Cl_ideal = 2 pi [th1 + tau1 (th2 - th1) + tau2 (th3 - th2)]
%        th_i = element angle - aL0_i, tau = 1 - (tf - sin tf)/pi with
%        cos tf = 2 E - 1 and E the chord fraction behind the slot.
%     3. Real flow: section slope kappa * 2 pi, each flap term times an
%        empirical slotted-flap effectiveness eta(deflection) (falls from 1
%        to 0.4 between 0 and 60 deg), and a cap at a 2D maximum by element
%        count (1.6 / 3.0 / 4.2 on the developed chord).
%     4. Finite span: Helmbold low-aspect-ratio slope factor
%          CL/Cl = 1 / (sqrt(1 + (a0/(pi AR))^2) + a0/(pi AR))
%        with the endplates raising the aspect ratio (Hoerner):
%          AR_eff = AR (1 + 1.9 h_endplate / span).
%     5. Front wing in ground effect: an empirical gain on CL that decays with
%        height over chord (kge_max at h/c 0.08, e-folding 0.25) and the
%        induced-drag factor of McCormick, phi = (16 h/b)^2 / (1 + (16 h/b)^2).
%     6. Front flaps start at fw_flap_inner_y (the centre has the main element
%        alone): strip sum of cl2d * chord over the two parts of the span.
%        Installation factors (wheels at the front; hoop, driver and
%        front-wing upwash at the rear), assumed.
%     7. Drag: induced CL^2 / (pi e AR_eff) (times phi at the front), profile
%        0.015 + 0.003 Cl2d^2, endplate skin friction.
%   UNDERBODY (flat raked floor, plus the diffuser in C and D)
%     One-dimensional channel between floor and moving ground: continuity
%     gives the speed at each station from the area w(x) h(x); the pressure
%     recovers from the throat to the exit pressure with efficiency eta_d:
%       q1 = (1 - Cp_exit) / (1 - eta_d (1 - (A1/A_exit)^2)),  Cp1 = 1 - q1
%       Cp(x) = Cp1 + eta_d (1 - (A1/A(x))^2) q1
%     Downforce = -k3d * integral of Cp over the plan area (k3d: side inflow
%     and three-dimensional loss), drag from the suction on the sloped roof.
%   BODY AND WHEELS
%     Body drag Cd on the body frontal area; a small body lift; isolated
%     rotating-wheel coefficients on tyre frontal area (rear wheels reduced,
%     they run in the front wheels' wake).
%   VARIANT D DEVICES
%     Beam wing (single element, free tips, no endplates) by the same wing
%     method; endplate strakes as inclined plates (drag only).
%   FRONT / REAR SPLIT
%     Moments about the contact patches: a downforce ClA_i at x_i and a drag
%     CdA_i at height z_i load the axles by
%       front = sum ClA_i (1 - x_i/L) - sum CdA_i z_i / L,   rear = total - front
%     so the drag of a high rear wing moves load from the front axle to the rear.
%   WAKE (velocity deficit, width, height of the centre, at n car lengths)
%     Momentum-integral Gaussian wake with a ground image: the drag fixes
%       CdA / 2 = 2 pi sigma^2 (d - d^2/2),  d = centre deficit / U
%     starting from an assumed deficit d0 at the end of the near wake, and the
%     width grows by the spreading parameter S = (U / dU) d r_half / dx
%     (which gives the classical x^(1/3) far wake). The wake centre is carried
%     upward by the rear wing's trailing vortex pair and its ground image:
%       dz/dx = k ClA_rear / (4 pi b'^2) * (1 - b'^2 / (b'^2 + 4 z^2)),  b' = pi/4 span,
%     with k (wake_rise_factor) the assumed fraction of the ideal rise.
%     The following-car window averages are integrated on a grid.
%
%   Output fields: T (totals per variant with ranges), comp (components per
%   variant), assumptions (table with the sensitivity of variant C), wake
%   (table per variant and plane), trim (front-flap change that reaches
%   aero_balance_target on variant C), sections (aL0 per airfoil file).

if nargin >= 1 && (ischar(opts) || isstring(opts)) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'write'), opts.write = true; end
if ~isfield(opts, 'write_variants'), opts.write_variants = false; end
if ~isfield(opts, 'p'), opts.p = read_car_params(); end
if ~isfield(opts, 'assume'), opts.assume = struct(); end
p = opts.p;
A = assumptions();
fn = fieldnames(opts.assume);
for k = 1:numel(fn)
    i = find(strcmp({A.name}, fn{k}), 1);
    if isempty(i), error('aero_estimate:assume', 'Unknown assumption %s', fn{k}); end
    A(i).nom = opts.assume.(fn{k});
end
sec = load_sections();
variants = {'A', 'B', 'C', 'D'};
planes = [0.5 1 2 3];
nom = cell2struct({A.nom}.', {A.name}.', 1);

% ---- nominal ------------------------------------------------------------------
M = cell(1, 4); W = cell(1, 4);
for k = 1:4
    M{k} = variant_model(p, variants{k}, nom, sec);
    W{k} = wake_model(p, M{k}, nom, planes, variants{k});
end
q0 = pack(M, W);

% ---- uncertainty: one-at-a-time, root-sum-square of each side ------------------
up = zeros(size(q0)); dn = zeros(size(q0));
sensC = zeros(numel(A), 6);    % variant C: dClA lo/hi, dCdA lo/hi, dbalance lo/hi
for i = 1:numel(A)
    for side = 1:2
        v = nom;
        if side == 1, v.(A(i).name) = A(i).lo; else, v.(A(i).name) = A(i).hi; end
        Mi = cell(1, 4); Wi = cell(1, 4);
        for k = 1:4
            Mi{k} = variant_model(p, variants{k}, v, sec);
            Wi{k} = wake_model(p, Mi{k}, v, planes, variants{k});
        end
        d = pack(Mi, Wi) - q0;
        d(isnan(d)) = 0;
        up = up + max(d, 0).^2; dn = dn + min(d, 0).^2;
        sensC(i, side) = Mi{3}.ClA - M{3}.ClA;
        sensC(i, 2 + side) = Mi{3}.CdA - M{3}.CdA;
        sensC(i, 4 + side) = Mi{3}.aero_front - M{3}.aero_front;
    end
end
qHi = q0 + sqrt(up); qLo = q0 - sqrt(dn);
[T, WT] = unpack(q0, qLo, qHi, variants, planes, M);
out.T = T; out.wake = WT;
out.comp = cellfun(@(m) m.comp, M, 'UniformOutput', false);
out.models = M; out.wake_models = W;
out.assumptions = struct2table(A);
out.assumptions.dClA_C_lo = sensC(:, 1); out.assumptions.dClA_C_hi = sensC(:, 2);
out.assumptions.dCdA_C_lo = sensC(:, 3); out.assumptions.dCdA_C_hi = sensC(:, 4);
out.assumptions.dbal_C_lo = sensC(:, 5); out.assumptions.dbal_C_hi = sensC(:, 6);
out.sections = sec;
out.planes = planes;

% ---- trim: front flap change that reaches the balance target on C and D ----------
out.trim = trim_to_target(p, nom, sec);

if opts.write || opts.plot
    mediaDir = fullfile(repo_root(), 'media');
    if ~isfolder(mediaDir), mkdir(mediaDir); end
end
if opts.write
    writetable(T, fullfile(mediaDir, 'aero_estimate_table.csv'));
    writetable(WT, fullfile(mediaDir, 'aero_estimate_wake.csv'));
    write_markdown(fullfile(mediaDir, 'aero_estimate.md'), out, p);
    print_report(out);
    if ~opts.write_variants, check_variant_table(T); end
end
if opts.write_variants
    write_variant_table(T);
end
if opts.plot
    plot_estimate(out, p);
end
end

% =============================================================================
% ASSUMPTIONS. name, nominal, low, high, what it is. None is measured.
% =============================================================================
function A = assumptions()
L = {
    'kappa_slope',     0.90, 0.80, 1.00, 'section lift slope as a fraction of 2 pi (viscous loss)'
    'eta_flap_scale',  1.00, 0.80, 1.15, 'scale on the slotted-flap effectiveness curve eta(deflection)'
    'clmax_scale',     1.00, 0.85, 1.15, 'scale on the 2D maximum Cl caps 1.6 / 3.0 / 4.2 (1, 2, 3 elements, developed chord)'
    'endplate_k',      1.90, 1.00, 2.20, 'Hoerner endplate factor: AR_eff = AR (1 + k h/b)'
    'oswald_e',        0.90, 0.75, 1.00, 'span efficiency in the induced drag'
    'kge_max',         1.40, 1.15, 1.70, 'front wing ground-effect gain on CL at h/c 0.08 (decays with e-folding 0.25 in h/c)'
    'inst_front',      0.85, 0.70, 0.95, 'front wing installation factor (tyres behind the tips, nose above the main element; the missing centre flaps are modelled, not in this factor)'
    'inst_rear',       0.85, 0.70, 0.95, 'rear wing installation factor (hoop and driver ahead, front-wing upwash)'
    'cd_profile_scale',1.00, 0.60, 1.60, 'scale on the wing profile drag 0.015 + 0.003 Cl2d^2'
    'xcp_frac',        0.40, 0.30, 0.50, 'wing centre of pressure as a fraction of the stack length from the main leading edge'
    'eta_diff',        0.50, 0.30, 0.65, 'underbody pressure-recovery efficiency (to 10 deg diffuser angle)'
    'eta_diff_slope',  0.03, 0.00, 0.06, 'loss of recovery efficiency per degree of diffuser angle above 10 deg'
    'k3d_floor',       0.60, 0.40, 0.80, 'underbody three-dimensional factor (side inflow, edge leakage)'
    'cp_exit',        -0.12,-0.25, 0.00, 'pressure coefficient at the underbody exit (car base pressure)'
    'body_ClA',       -0.10,-0.25, 0.05, 'body upper-surface force as ClA in m2 (negative = lift)'
    'cd_body',         0.60, 0.45, 0.80, 'body drag coefficient on its own frontal area (open cockpit, driver, hoop, suspension links)'
    'A_body',          0.61, 0.55, 0.67, 'body frontal area in m2 without wheels and wings: 2 x 0.306 m2 measured on the half-car CFD body of variant A (cad/step/cfd/cfd_geometry.json); the range covers the missing suspension links and the simplified shape'
    'cd_wheel',        0.58, 0.45, 0.75, 'isolated rotating wheel drag coefficient on tyre frontal area'
    'cl_wheel',        0.44, 0.25, 0.60, 'isolated rotating wheel lift coefficient on tyre frontal area'
    'rear_wheel_factor',0.75,0.50, 1.00, 'rear wheel force as a fraction of the front (runs in its wake)'
    'beam_inst',       0.60, 0.40, 0.80, 'beam wing installation factor, variant D (under the main wing, behind the tyres)'
    'wake_S',          0.20, 0.10, 0.35, 'wake spreading parameter S = (U/dU) d r_half/dx'
    'wake_d0',         0.80, 0.60, 0.95, 'centre velocity deficit at the end of the near wake'
    'wake_x_close',    0.50, 0.30, 1.00, 'length of the near wake behind the rear end of the car, m'
    'wake_rise_factor',0.60, 0.30, 1.00, 'fraction of the ideal vortex-pair rise rate that the wake centre follows (roll-up, decay and wheel wakes not modelled)'
    'wake_S_mult_D',   1.25, 1.00, 1.60, 'variant D: spreading multiplier for the strakes and free beam-wing tips (not derived)'
    'wake_ti_ratio',   0.30, 0.20, 0.45, 'turbulence intensity as a fraction of the centre deficit'
    };
A = cell2struct(L, {'name', 'nom', 'lo', 'hi', 'what'}, 2);
end

% =============================================================================
% AIRFOIL SECTIONS
% =============================================================================
function sec = load_sections()
names = {'fw_main', 'fw_flap1', 'fw_flap2', 'rw_main', 'rw_flap1', 'rw_flap2', 'symmetric'};
d = fullfile(repo_root(), 'cad', 'airfoils');
sec = struct();
for k = 1:numel(names)
    xy = read_dat(fullfile(d, [names{k} '.dat']));
    [xc, zc, tmax] = camber_line(xy);
    sec.(names{k}).aL0 = zero_lift_angle(@(x) interp1(xc, zc, x, 'pchip'));
    sec.(names{k}).camber_max = max(zc);
    sec.(names{k}).t_max = tmax;
end
end

function xy = read_dat(file)
txt = splitlines(string(fileread(file)));
xy = zeros(0, 2);
for k = 2:numel(txt)
    v = sscanf(txt(k), '%f %f');
    if numel(v) == 2, xy(end+1, :) = v.'; end %#ok<AGROW>
end
end

function [xc, zc, tmax] = camber_line(xy)
% Selig order: TE -> upper -> LE -> lower -> TE. Camber = mean of the two
% surfaces at the same x.
[~, iLE] = min(xy(:, 1));
up = flipud(xy(1:iLE, :)); lo = xy(iLE:end, :);
[xu, iu] = unique(up(:, 1)); zu = up(iu, 2);
[xl, il] = unique(lo(:, 1)); zl = lo(il, 2);
xc = (1 - cos(linspace(0, pi, 201))).' / 2;
xc = min(max(xc, max(xu(1), xl(1))), min(xu(end), xl(end)));
zU = interp1(xu, zu, xc, 'pchip'); zL = interp1(xl, zl, xc, 'pchip');
zc = (zU + zL) / 2; tmax = max(zU - zL);
[xc, iu] = unique(xc); zc = zc(iu);
end

function aL0 = zero_lift_angle(zfun)
% thin-airfoil theory: aL0 = -(1/pi) int_0^pi dz/dx (cos t - 1) dt, x = (1 - cos t)/2
n = 400; t = ((1:n) - 0.5) * pi / n;                 % midpoint rule
x = (1 - cos(t)) / 2; h = 1e-4;
xa = max(x - h, 0); xb = min(x + h, 1);
dz = (zfun(xb) - zfun(xa)) ./ (xb - xa);
aL0 = -(1 / pi) * sum(dz .* (cos(t) - 1)) * (pi / n);
end

% =============================================================================
% WING FORMULAS
% =============================================================================
function tau = glauert_tau(E)
% flap effectiveness d(alpha_zero-lift)/d(deflection) for flap chord fraction E
tf = acos(2 * E - 1);
tau = 1 - (tf - sin(tf)) / pi;
end

function eta = eta_slotted(delta_deg)
% ASSUMED empirical effectiveness of a slotted flap against deflection (the
% thin-airfoil increment is not reached once the flap flow thickens and
% separates). Shape after the textbook flap-effectiveness curves; the scale
% is the assumption eta_flap_scale.
d = [0 10 20 30 40 50 60 90]; e = [1.00 0.95 0.87 0.75 0.62 0.50 0.40 0.25];
eta = interp1(d, e, min(max(abs(delta_deg), 0), 90));
end

function f = helmbold(a0, AR)
% finite-wing lift slope over section slope, valid down to low aspect ratio
k = a0 / (pi * AR);
f = 1 / (sqrt(1 + k^2) + k);
end

function phi = mccormick_phi(h_over_b)
% induced-drag factor in ground effect
r = (16 * h_over_b)^2;
phi = r / (1 + r);
end

function g = stack_geometry(p, pre, v)
% chord-line chain of the three elements, as cad/generate/build_parts.py builds it
c = [p.([pre '_main_chord']), p.([pre '_flap1_chord']), p.([pre '_flap2_chord'])] / 1000;
a = deg2rad([p.([pre '_main_aoa_' v]), p.([pre '_flap1_aoa_' v]), p.([pre '_flap2_aoa_' v])]);
ov = p.wing_element_overlap / 1000;
gp = (p.wing_element_gap + 8) / 1000;              % + 8 mm: the CFD geometry widens every slot (SLOT_EXTRA in cad/generate/cfd_variants.py); only the element positions use it, the flap effectiveness has no gap term
g.c = c; g.a = a;
g.ctot = sum(c) - 2 * ov;                          % developed chord
g.len = sum(c .* cos(a)) - 2 * ov;                 % projected length
g.rise = sum(c .* sin(a)) + 2 * gp;                % main LE to flap-2 TE
g.span = p.([pre '_span']) / 1000;
g.h_ep = p.([pre '_endplate_height']) / 1000;
g.l_ep = p.([pre '_endplate_length']) / 1000;
if strcmp(pre, 'fw')
    g.x_le = p.fw_le_x / 1000;                     % fw_le_x: forward of the playbook's -600 so the flaps clear the front tyres
    g.z_le = p.fw_ground_clearance / 1000 + 0.03;  % lowest point is about 0.03 below the LE (camber down)
else
    g.x_le = (p.wheelbase + p.rear_overhang) / 1000 - g.len;
    g.z_le = p.rw_height / 1000;
end
g.E = [(c(2) + c(3) - 2 * ov) / g.ctot, (c(3) - ov) / g.ctot];
end

function w = wing_stack(p, pre, v, a, sec, dflap)
% dflap: extra angle on both flaps in degrees (used by the trim solver)
if nargin < 6, dflap = 0; end
g = stack_geometry(p, pre, v);
g.a(2:3) = g.a(2:3) + deg2rad(dflap);
aL0 = [sec.([pre '_main']).aL0, sec.([pre '_flap1']).aL0, sec.([pre '_flap2']).aL0];
th = g.a - aL0;                                   % zero-lift-line angles, rad
d = diff(th);                                     % slot deflections
tau = glauert_tau(g.E);
eta = min(1, a.eta_flap_scale * eta_slotted(rad2deg(d)));
a0 = a.kappa_slope * 2 * pi;
w.cl_ideal = 2 * pi * (th(1) + sum(tau .* d));
w.cl2d_uncapped = a0 * (th(1) + sum(eta .* tau .* d));
w.cl2d_cap = a.clmax_scale * 4.2;
w.cl2d = min(w.cl2d_uncapped, w.cl2d_cap);
w.capped = w.cl2d_uncapped > w.cl2d_cap;
w.S = g.span * g.ctot;
w.AR = g.span / g.ctot;
w.AR_eff = w.AR * (1 + a.endplate_k * g.h_ep / g.span);
w.f3d = helmbold(a0, w.AR_eff);
if strcmp(pre, 'fw')
    hc = (p.fw_ground_clearance / 1000) / g.ctot;
    w.kge = 1 + (a.kge_max - 1) * exp(-max(hc - 0.08, 0) / 0.25);
    w.h_mean = p.fw_ground_clearance / 1000 + g.rise / 3;
    w.phi = mccormick_phi(w.h_mean / g.span);
    w.inst = a.inst_front;
else
    w.kge = 1; w.phi = 1; w.h_mean = g.z_le + g.rise / 2;
    w.inst = a.inst_rear;
end
% Front wing: the flaps start at fw_flap_inner_y; the centre has the main
% element alone. Strip sum of the section lift per unit span cl2d * chord,
% referred to the developed chord of the flapped part.
w.flap_span_frac = 1; w.cl2d_centre = NaN; lenC = g.len;
cdp = a.cd_profile_scale * (0.015 + 0.003 * w.cl2d^2);
if strcmp(pre, 'fw') && isfield(p, 'fw_flap_inner_y') && p.fw_flap_inner_y > 0
    fo = 1 - p.fw_flap_inner_y / 1000 / (g.span / 2);
    clc = min(a0 * th(1), a.clmax_scale * 1.6);
    cdc = a.cd_profile_scale * (0.015 + 0.003 * clc^2);
    lo = fo * w.cl2d * g.ctot; lc = (1 - fo) * clc * g.c(1);
    w.flap_span_frac = fo; w.cl2d_centre = clc;
    cl_eff = (lo + lc) / g.ctot;                              % mean section lift on the reference chord
    cdp = (fo * cdp * g.ctot + (1 - fo) * cdc * g.c(1)) / g.ctot;
    lenC = (lo * g.len + lc * g.c(1) * cos(g.a(1))) / (lo + lc);   % lift-weighted stack length for the centre of pressure
else
    cl_eff = w.cl2d;
end
w.cl2d_eff = cl_eff;
w.CL = cl_eff * w.f3d * w.kge * w.inst;
w.CDi = w.CL^2 / (pi * a.oswald_e * w.AR_eff) * w.phi;
w.cd_profile = cdp;
w.CdA_endplates = 2 * 2 * g.h_ep * g.l_ep * 0.005;       % two plates, two sides, Cf 0.005
w.ClA = w.CL * w.S;
w.CdA = (w.CDi + w.cd_profile) * w.S + w.CdA_endplates;
w.x = g.x_le + a.xcp_frac * lenC;
w.z = g.z_le + g.rise / 2;
w.geo = g; w.theta = th; w.tau = tau; w.eta = eta; w.aL0 = aL0;
end

% =============================================================================
% UNDERBODY
% =============================================================================
function u = underbody(p, v, a)
x0 = p.floor_start_from_front_axle / 1000; xa = p.wheelbase / 1000;
xStep = 1.400; wF = p.floor_width / 1000; wR = 0.940;    % as build_parts.py: stepped in beside the rear tyres
h0 = p.ride_height_front / 1000; h1 = p.ride_height_rear / 1000;
hasDiff = any(strcmp(v, {'C', 'D'}));
if hasDiff
    ang = p.(['diffuser_angle_' v]); Ld = p.diffuser_length / 1000;
else
    ang = 0; Ld = 0;
end
x = linspace(x0, xa + Ld, 2001).';
h = h0 + (h1 - h0) * min(x - x0, xa - x0) / (xa - x0) + max(x - xa, 0) * tand(ang);
w = wF * (x < xStep) + wR * (x >= xStep);
u = channel(x, h, w, a.eta_diff - a.eta_diff_slope * max(ang - 10, 0), a.cp_exit, a.k3d_floor);
u.angle = ang; u.h_exit = h(end);
end

function u = channel(x, h, w, eta, cpExit, k3d)
% one-dimensional floor-to-ground channel, see the header
Ar = w .* h;
[A1, i1] = min(Ar);
rec = @(Ax) eta * (1 - (A1 ./ Ax).^2);
u.q1 = (1 - cpExit) / (1 - rec(Ar(end)));
u.cp1 = 1 - u.q1;
cp = u.cp1 + rec(Ar) * u.q1;
cp(1:i1) = u.cp1 * (x(1:i1) - x(1)) / max(x(i1) - x(1), eps);   % linear from 0 at the inlet edge to the throat (only if the throat is not the inlet)
if i1 == 1, cp(1) = u.cp1; end
dhdx = gradient(h, x);
u.ClA = -k3d * trapz(x, cp .* w);
u.CdA = -k3d * trapz(x, cp .* w .* dhdx);
u.x = trapz(x, x .* cp .* w) / trapz(x, cp .* w);
u.cp_mean = trapz(x, cp .* w) / trapz(x, w);
u.area_ratio = Ar(end) / A1; u.eta = eta; u.cp = cp; u.xs = x; u.plan_area = trapz(x, w);
u.z = mean(h);
end

% =============================================================================
% ONE VARIANT
% =============================================================================
function m = variant_model(p, v, a, sec, dflapFront)
if nargin < 5, dflapFront = 0; end
L = p.wheelbase / 1000;
comp = struct('name', {}, 'ClA', {}, 'CdA', {}, 'x', {}, 'z', {});
add = @(c, name, ClA, CdA, x, z) [c, struct('name', name, 'ClA', ClA, 'CdA', CdA, 'x', x, 'z', z)];

% body and wheels
comp = add(comp, 'body', a.body_ClA, a.cd_body * a.A_body, 0.80, 0.35);
Aw = p.tyre_od / 1000 * p.tyre_width / 1000;
zw = 0.26;                                           % drag acts a little above the wheel centre
comp = add(comp, 'front wheels', -2 * Aw * a.cl_wheel, 2 * Aw * a.cd_wheel, 0, zw);
comp = add(comp, 'rear wheels', -2 * Aw * a.cl_wheel * a.rear_wheel_factor, 2 * Aw * a.cd_wheel * a.rear_wheel_factor, L, zw);

% underbody
u = underbody(p, v, a);
comp = add(comp, ternary(u.angle > 0, 'floor + diffuser', 'floor'), u.ClA, u.CdA, u.x, u.z);
m.underbody = u;

% wings
m.fw = []; m.rw = []; m.beam = [];
ClA_up = 0; bUp = p.rw_span / 1000;
if ~strcmp(v, 'A')
    m.fw = wing_stack(p, 'fw', v, a, sec, dflapFront);
    m.rw = wing_stack(p, 'rw', v, a, sec);
    comp = add(comp, 'front wing', m.fw.ClA, m.fw.CdA, m.fw.x, m.fw.z);
    comp = add(comp, 'rear wing', m.rw.ClA, m.rw.CdA, m.rw.x, m.rw.z);
    ClA_up = m.rw.ClA;
end
if strcmp(v, 'D')
    b = beam_wing(p, a, sec);
    comp = add(comp, 'beam wing', b.ClA, b.CdA, b.x, b.z);
    m.beam = b; ClA_up = ClA_up + b.ClA;
    nvg = 2 * (p.vg_count_rw + p.vg_count_fw);        % both sides
    Avg = p.vg_length / 1000 * p.vg_height / 1000;
    cdaVg = nvg * Avg * 0.8 * sind(p.vg_angle);       % normal-force coefficient 0.8 on an inclined low-aspect plate, ASSUMED
    xvg = (2 * p.vg_count_rw * 2.0 + 2 * p.vg_count_fw * (-0.3)) / nvg;
    zvg = (2 * p.vg_count_rw * 1.25 + 2 * p.vg_count_fw * 0.2) / nvg;
    comp = add(comp, 'endplate strakes', 0, cdaVg, xvg, zvg);
end

m.comp = struct2table(comp);
m.ClA = sum([comp.ClA]); m.CdA = sum([comp.CdA]);
m.ClA_front = sum([comp.ClA] .* (1 - [comp.x] / L)) - sum([comp.CdA] .* [comp.z]) / L;
m.ClA_rear = m.ClA - m.ClA_front;
if abs(m.ClA) > 0.3, m.aero_front = m.ClA_front / m.ClA; else, m.aero_front = NaN; end
m.comp.front_axle_m2 = m.comp.ClA .* (1 - m.comp.x / L) - m.comp.CdA .* m.comp.z / L;
m.z_drag = sum([comp.CdA] .* [comp.z]) / m.CdA;
m.ClA_upwash = ClA_up; m.b_upwash = bUp;
m.variant = v;
end

function b = beam_wing(p, a, sec)
c = p.beam_chord / 1000; s = p.beam_span / 1000;
a0 = a.kappa_slope * 2 * pi;
th = deg2rad(p.beam_aoa_D) - sec.rw_flap1.aL0;         % section of the rear first flap
b.cl2d = min(a0 * th, a.clmax_scale * 1.6);
b.AR = s / c;                                          % no endplates: free tips on purpose
b.CL = b.cl2d * helmbold(a0, b.AR) * a.beam_inst;
b.S = s * c;
b.ClA = b.CL * b.S;
b.CdA = (b.CL^2 / (pi * a.oswald_e * b.AR) + a.cd_profile_scale * (0.015 + 0.003 * b.cl2d^2)) * b.S;
b.x = p.beam_x_le / 1000 + a.xcp_frac * c;
b.z = p.beam_z_le / 1000;
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

% =============================================================================
% WAKE
% =============================================================================
function w = wake_model(p, m, a, planes, v)
L = p.overall_length / 1000;
if strcmp(v, 'A')
    xEnd = (p.wheelbase + p.tyre_od / 2) / 1000;       % no wings: the car ends at the back of the rear tyres
else
    xEnd = (p.wheelbase + p.rear_overhang) / 1000;     % rear wing trailing edge
end
xp = p.wheelbase / 1000 + planes * L;                  % repo convention: n lengths behind the rear axle
S = a.wake_S; if strcmp(v, 'D'), S = S * a.wake_S_mult_D; end
x0 = xEnd + a.wake_x_close;
sig = gauss_sigma(m.CdA, a.wake_d0);
z = max(m.z_drag, 0.3);
bp = pi / 4 * m.b_upwash;
dx = 0.005; x = x0;
n = numel(planes);
w.x = xp; w.dist_behind_car = xp - xEnd;
w.deficit = nan(1, n); w.fwhm = nan(1, n); w.zc = nan(1, n); w.sigma = nan(1, n);
w.win_deficit = nan(1, n); w.q_ratio = nan(1, n); w.upwash_deg = nan(1, n); w.TI = nan(1, n);
win = [p.wake_window_width / 2, p.wake_window_height];
[xs, order] = sort(xp);
d = a.wake_d0;
for j = 1:n
    while x < xs(j)
        d = gauss_deficit(m.CdA, sig);
        sig = sig + S * d / 1.1774 * dx;               % r_half = 1.1774 sigma
        z = z + a.wake_rise_factor * rise_rate(m.ClA_upwash, bp, z) * dx;
        x = x + dx;
    end
    d = gauss_deficit(m.CdA, sig);
    k = order(j);
    w.deficit(k) = d; w.sigma(k) = sig; w.fwhm(k) = 2.3548 * sig; w.zc(k) = z;
    [w.win_deficit(k), w.q_ratio(k)] = window_average(d, sig, z, win);
    w.upwash_deg(k) = atand(a.wake_rise_factor * rise_rate(m.ClA_upwash, bp, z));
    w.TI(k) = a.wake_ti_ratio * d;
end
w.inside_near_wake = xp < x0;
end

function r = rise_rate(ClA, bp, z)
% vertical speed over U of a counter-rotating pair of span bp carrying the
% downforce ClA, with its ground image: Gamma = U ClA / (2 bp)
r = max(ClA, 0) / (4 * pi * bp^2) * (1 - bp^2 / (bp^2 + 4 * z^2));
end

function sig = gauss_sigma(CdA, d)
% CdA / 2 = 2 pi sigma^2 (d - d^2 / 2)
sig = sqrt(CdA / (4 * pi * (d - d^2 / 2)));
end

function d = gauss_deficit(CdA, sig)
% inverse of gauss_sigma: d - d^2/2 = k, the root below 1
k = CdA / (4 * pi * sig^2);
d = 1 - sqrt(max(1 - 2 * k, 0));
end

function [def, q] = window_average(d, sig, zc, win)
% mean deficit and mean (u/U)^2 over |y| <= win(1), 0 <= z <= win(2); Gaussian
% about (0, zc) plus its image about the ground, deficit capped at 1
y = linspace(0, win(1), 41); z = linspace(0, win(2), 61);
[Y, Z] = meshgrid(y, z);
D = d * (exp(-(Y.^2 + (Z - zc).^2) / (2 * sig^2)) + exp(-(Y.^2 + (Z + zc).^2) / (2 * sig^2)));
D = min(D, 1);
def = mean(D(:)); q = mean((1 - D(:)).^2);
end

% =============================================================================
% TRIM TO THE BALANCE TARGET
% =============================================================================
function tr = trim_to_target(p, a, sec)
tr = struct('variant', {}, 'target', {}, 'dflap_deg', {}, 'ClA', {}, 'CdA', {}, 'aero_front', {}, 'aero_front_before', {}, 'ClA_before', {});
if ~isfield(p, 'aero_balance_target'), return, end
for v = {'B', 'C', 'D'}
    f = @(dd) variant_model(p, v{1}, a, sec, dd).aero_front - p.aero_balance_target;
    m0 = variant_model(p, v{1}, a, sec);
    lo = -30; hi = 15;
    if f(lo) * f(hi) > 0
        dd = NaN; m1 = m0;
    else
        for it = 1:50
            mid = (lo + hi) / 2;
            if f(mid) * f(lo) > 0, lo = mid; else, hi = mid; end
        end
        dd = (lo + hi) / 2; m1 = variant_model(p, v{1}, a, sec, dd);
    end
    tr(end+1) = struct('variant', v{1}, 'target', p.aero_balance_target, 'dflap_deg', dd, 'ClA', m1.ClA, 'CdA', m1.CdA, ...
        'aero_front', m1.aero_front, 'aero_front_before', m0.aero_front, 'ClA_before', m0.ClA); %#ok<AGROW>
end
tr = struct2table(tr);
end

% =============================================================================
% PACKING FOR THE UNCERTAINTY LOOP
% =============================================================================
function q = pack(M, W)
% per variant: ClA CdA ClA_front aero_front, then per plane deficit fwhm zc win_deficit q_ratio TI upwash
q = [];
for k = 1:numel(M)
    q = [q, M{k}.ClA, M{k}.CdA, M{k}.ClA_front, M{k}.aero_front, W{k}.deficit, W{k}.fwhm, W{k}.zc, W{k}.win_deficit, W{k}.q_ratio, W{k}.TI, W{k}.upwash_deg]; %#ok<AGROW>
end
end

function [T, WT] = unpack(q0, qLo, qHi, variants, planes, M)
n = numel(planes); per = 4 + 7 * n;
rows = cell(numel(variants), 14); wrows = {};
for k = 1:numel(variants)
    i0 = (k - 1) * per;
    g = @(j) [q0(i0 + j), qLo(i0 + j), qHi(i0 + j)];
    c = g(1); d = g(2); f = g(3); b = g(4);
    rows(k, :) = {variants{k}, c(1), c(2), c(3), d(1), d(2), d(3), f(1), c(1) - f(1), b(1), b(2), b(3), c(1) / d(1), M{k}.z_drag};
    for j = 1:n
        idx = @(blk) 4 + (blk - 1) * n + j;
        de = g(idx(1)); fw = g(idx(2)); zc = g(idx(3)); wd = g(idx(4)); qr = g(idx(5)); ti = g(idx(6)); uw = g(idx(7));
        wrows(end+1, :) = {variants{k}, planes(j), de(1), de(2), de(3), fw(1), fw(2), fw(3), zc(1), wd(1), wd(2), wd(3), qr(1), qr(2), qr(3), ti(1), uw(1)}; %#ok<AGROW>
    end
end
T = cell2table(rows, 'VariableNames', {'variant', 'ClA', 'ClA_lo', 'ClA_hi', 'CdA', 'CdA_lo', 'CdA_hi', 'ClA_front', 'ClA_rear', ...
    'aero_front', 'aero_front_lo', 'aero_front_hi', 'L_over_D', 'z_drag_m'});
WT = cell2table(wrows, 'VariableNames', {'variant', 'plane_lengths', 'deficit_centre', 'deficit_centre_lo', 'deficit_centre_hi', ...
    'fwhm_m', 'fwhm_lo', 'fwhm_hi', 'centre_height_m', 'deficit_window', 'deficit_window_lo', 'deficit_window_hi', ...
    'q_ratio_window', 'q_ratio_lo', 'q_ratio_hi', 'TI_centre', 'upwash_deg'});
end

% =============================================================================
% OUTPUT
% =============================================================================
function print_report(out)
T = out.T;
fprintf('\naero_estimate: PRE-CFD ESTIMATE, nothing measured (range = root-sum-square of the assumption ranges)\n');
for k = 1:height(T)
    fprintf('  %s  ClA %5.2f (%5.2f to %5.2f) m2   CdA %4.2f (%4.2f to %4.2f) m2   L/D %4.1f   front %5.2f / rear %5.2f m2   front share %s\n', ...
        T.variant{k}, T.ClA(k), T.ClA_lo(k), T.ClA_hi(k), T.CdA(k), T.CdA_lo(k), T.CdA_hi(k), T.L_over_D(k), T.ClA_front(k), T.ClA_rear(k), share_str(T(k, :)));
end
W = out.wake;
fprintf('  Wake (momentum-integral Gaussian wake with ground image, lowest confidence):\n');
for k = 1:height(W)
    fprintf('    %s %3.1f L: centre deficit %.2f (%.2f to %.2f), width FWHM %.2f m (%.2f to %.2f), centre at z %.2f m, window deficit %.2f, q-ratio %.2f\n', ...
        W.variant{k}, W.plane_lengths(k), W.deficit_centre(k), W.deficit_centre_lo(k), W.deficit_centre_hi(k), W.fwhm_m(k), W.fwhm_lo(k), W.fwhm_hi(k), ...
        W.centre_height_m(k), W.deficit_window(k), W.q_ratio_window(k));
end
if ~isempty(out.trim)
    fprintf('  Trim to the %.2f front target by turning both front flaps:\n', out.trim.target(1));
    for k = 1:height(out.trim)
        fprintf('    %s: %+.1f deg -> ClA %.2f (was %.2f), CdA %.2f, front share %.2f (was %.2f)\n', out.trim.variant{k}, out.trim.dflap_deg(k), ...
            out.trim.ClA(k), out.trim.ClA_before(k), out.trim.CdA(k), out.trim.aero_front(k), out.trim.aero_front_before(k));
    end
end
end

function s = share_str(row)
if isnan(row.aero_front)
    s = 'n/a (total near zero)';
else
    s = sprintf('%.2f (%.2f to %.2f)', row.aero_front, row.aero_front_lo, row.aero_front_hi);
end
end

function write_markdown(file, out, p)
T = out.T; fid = fopen(file, 'w');
fprintf(fid, '# Pre-CFD aero estimate (variants A to D)\n\n');
fprintf(fid, 'Written by `matlab/aero/aero_estimate.m` from `params/car_params.txt` and the airfoil files in `cad/airfoils/`. **Every number is an ESTIMATE from handbook formulas with assumed coefficients; nothing is measured and no CFD result went into it (CFD results, when they exist: `media/cfd/cfd_results.md`).** Method and assumptions: `docs/aero_estimate.md`. The range is the root-sum-square of the one-at-a-time changes of the assumptions listed at the bottom.\n\n');
fprintf(fid, '## Totals\n\n| Variant | ClA (m2) | range | CdA (m2) | range | L/D | on front axle (m2) | on rear axle (m2) | front share | range |\n|---|---|---|---|---|---|---|---|---|---|\n');
desc = {'A no wings', 'B moderate wings', 'C max wings + diffuser', 'D wake-tuned'};
for k = 1:height(T)
    if isnan(T.aero_front(k)), sh = 'n/a'; shr = 'total near zero'; else, sh = sprintf('%.2f', T.aero_front(k)); shr = sprintf('%.2f to %.2f', T.aero_front_lo(k), T.aero_front_hi(k)); end
    fprintf(fid, '| %s | %.2f | %.2f to %.2f | %.2f | %.2f to %.2f | %.1f | %.2f | %.2f | %s | %s |\n', desc{k}, T.ClA(k), T.ClA_lo(k), T.ClA_hi(k), ...
        T.CdA(k), T.CdA_lo(k), T.CdA_hi(k), T.L_over_D(k), T.ClA_front(k), T.ClA_rear(k), sh, shr);
end
fprintf(fid, '\nPositive ClA is downforce. The axle loads include the pitching moment of the drag (drag at height z moves `CdA z / L` from the front axle to the rear), so they are what the tyres see. Balance target in the parameter file: %.2f front (ESTIMATE/target).\n', p.aero_balance_target);
fprintf(fid, '\n## Components\n');
for k = 1:numel(out.comp)
    C = out.comp{k};
    fprintf(fid, '\n**%s**\n\n| Component | ClA (m2) | CdA (m2) | x of force (m) | z of drag (m) | on front axle (m2) |\n|---|---|---|---|---|---|\n', desc{k});
    for i = 1:height(C)
        fprintf(fid, '| %s | %+.3f | %.3f | %.2f | %.2f | %+.3f |\n', C.name{i}, C.ClA(i), C.CdA(i), C.x(i), C.z(i), C.front_axle_m2(i));
    end
end
fprintf(fid, '\n## Wing detail\n\n| Variant | Wing | Cl ideal (thin airfoil) | Cl 2D used | capped | AR | AR eff | 3D factor | ground gain | installation | CL (planform) | S (m2) | CDi | cd profile |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n');
for k = 2:4
    m = out.models{k};
    ws = {m.fw, m.rw}; nm = {'front', 'rear'};
    for i = 1:2
        w = ws{i};
        fprintf(fid, '| %s | %s | %.2f | %.2f | %s | %.2f | %.2f | %.3f | %.2f | %.2f | %.2f | %.3f | %.3f | %.3f |\n', m.variant, nm{i}, w.cl_ideal, w.cl2d, ...
            ternary(w.capped, 'yes', 'no'), w.AR, w.AR_eff, w.f3d, w.kge, w.inst, w.CL, w.S, w.CDi, w.cd_profile);
    end
end
fprintf(fid, '\nZero-lift angles from the airfoil files (thin-airfoil theory, deg): ');
sn = fieldnames(out.sections);
for k = 1:numel(sn), fprintf(fid, '%s %.2f%s', sn{k}, rad2deg(out.sections.(sn{k}).aL0), ternary(k < numel(sn), ', ', sprintf('.\n'))); end
fprintf(fid, '\n## Underbody\n\n| Variant | diffuser angle (deg) | area ratio | recovery efficiency | throat Cp | mean Cp | ClA (m2) | CdA (m2) |\n|---|---|---|---|---|---|---|---|\n');
for k = 1:4
    u = out.models{k}.underbody;
    fprintf(fid, '| %s | %g | %.2f | %.2f | %.2f | %.2f | %.3f | %.3f |\n', out.models{k}.variant, u.angle, u.area_ratio, u.eta, u.cp1, u.cp_mean, u.ClA, u.CdA);
end
if ~isempty(out.trim)
    fprintf(fid, '\n## Trim to the balance target\n\nFront-flap change (both flaps, same angle) at which the estimate reaches the %.2f front target. A design hint, not a result.\n\n| Variant | flap change (deg) | ClA before | ClA after | CdA after | front share before | after |\n|---|---|---|---|---|---|---|\n', out.trim.target(1));
    for k = 1:height(out.trim)
        fprintf(fid, '| %s | %+.1f | %.2f | %.2f | %.2f | %.2f | %.2f |\n', out.trim.variant{k}, out.trim.dflap_deg(k), out.trim.ClA_before(k), out.trim.ClA(k), out.trim.CdA(k), out.trim.aero_front_before(k), out.trim.aero_front(k));
    end
end
W = out.wake;
fprintf(fid, '\n## Wake estimate\n\nMethod: momentum-integral Gaussian wake with a ground image and a constant spreading parameter; wake centre lifted by the rear wing''s trailing vortex pair. Planes are n car lengths (%.2f m) behind the rear axle, as in `cfd/fluent_halfcar_setup.md`. Window = the following car''s frontal window (%.1f m wide, %.1f m high). **Lowest-confidence numbers in this file**: the spreading parameter is known only to a factor of about two, and the model has no wheel wakes, no vortex structure and no unsteadiness.\n\n', p.overall_length / 1000, p.wake_window_width, p.wake_window_height);
fprintf(fid, '| Variant | plane (L) | centre deficit | range | width FWHM (m) | range | centre height (m) | window deficit | range | window q-ratio | range | TI at centre | upwash (deg) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n');
for k = 1:height(W)
    fprintf(fid, '| %s | %g | %.2f | %.2f to %.2f | %.2f | %.2f to %.2f | %.2f | %.2f | %.2f to %.2f | %.2f | %.2f to %.2f | %.2f | %.1f |\n', W.variant{k}, W.plane_lengths(k), ...
        W.deficit_centre(k), W.deficit_centre_lo(k), W.deficit_centre_hi(k), W.fwhm_m(k), W.fwhm_lo(k), W.fwhm_hi(k), W.centre_height_m(k), ...
        W.deficit_window(k), W.deficit_window_lo(k), W.deficit_window_hi(k), W.q_ratio_window(k), W.q_ratio_lo(k), W.q_ratio_hi(k), W.TI_centre(k), W.upwash_deg(k));
end
A = out.assumptions;
fprintf(fid, '\n## Assumptions and what each one moves (variant C)\n\n| Assumption | nominal | low | high | what | ClA change low / high | CdA change low / high | front share change low / high |\n|---|---|---|---|---|---|---|---|\n');
for k = 1:height(A)
    fprintf(fid, '| `%s` | %g | %g | %g | %s | %+.2f / %+.2f | %+.2f / %+.2f | %+.3f / %+.3f |\n', A.name{k}, A.nom(k), A.lo(k), A.hi(k), A.what{k}, ...
        A.dClA_C_lo(k), A.dClA_C_hi(k), A.dCdA_C_lo(k), A.dCdA_C_hi(k), A.dbal_C_lo(k), A.dbal_C_hi(k));
end
fclose(fid);
end

function plot_estimate(out, p)
T = out.T; nV = height(T);
names = {'body', 'front wheels', 'rear wheels', 'floor', 'floor + diffuser', 'front wing', 'rear wing', 'beam wing', 'endplate strakes'};
cols = [0.45 0.45 0.45; 0.20 0.20 0.20; 0.65 0.65 0.65; 0.47 0.67 0.19; 0.47 0.67 0.19; 0.00 0.45 0.74; 0.85 0.33 0.10; 0.93 0.69 0.13; 0.49 0.18 0.56];
fig = figure('Name', 'aero estimate', 'Position', [80 80 1250 760]);
light_theme(fig);
for q = 1:2
    subplot(2, 2, q); hold on; grid on; box on
    fld = ternary(q == 1, 'ClA', 'CdA');
    hLeg = gobjects(0); lab = {};
    for k = 1:nV
        C = out.comp{k}; pos = 0; neg = 0;
        for i = 1:height(C)
            v = C.(fld)(i); ci = find(strcmp(names, C.name{i}));
            if v >= 0, base = pos; pos = pos + v; else, base = neg + v; neg = neg + v; end
            h = rectangle('Position', [k - 0.35, base, 0.7, max(abs(v), 1e-6)], 'FaceColor', cols(ci, :), 'EdgeColor', 'w'); %#ok<NASGU>
            if ~any(strcmp(lab, C.name{i}))
                hLeg(end+1) = patch(NaN, NaN, cols(ci, :)); lab{end+1} = C.name{i}; %#ok<AGROW>
            end
        end
        tot = T.(fld)(k);
        errorbar(k, tot, tot - T.([fld '_lo'])(k), T.([fld '_hi'])(k) - tot, 'k.', 'LineWidth', 1.5, 'MarkerSize', 16, 'CapSize', 10, 'HandleVisibility', 'off');
        plot(k + 0.42, p.([fld '_' T.variant{k}]), 'kd', 'MarkerFaceColor', 'w', 'HandleVisibility', 'off');
    end
    set(gca, 'XTick', 1:nV, 'XTickLabel', T.variant); xlim([0.4 nV + 0.7]);
    ylabel([fld ' (m^2)']);
    title({sprintf('%s by component', fld), 'dot = total with range, diamond = old guess'}, 'FontSize', 9);
    if q == 1, legend(hLeg, lab, 'Location', 'northwest', 'FontSize', 7); end
end
subplot(2, 2, 3); hold on; grid on; box on
for k = 1:nV
    if isnan(T.aero_front(k)), continue, end
    errorbar(k, T.aero_front(k), T.aero_front(k) - T.aero_front_lo(k), T.aero_front_hi(k) - T.aero_front(k), 'ko', 'MarkerFaceColor', 'k', 'LineWidth', 1.5, 'CapSize', 10);
end
yline(p.aero_balance_target, 'r--', sprintf('target %.2f', p.aero_balance_target));
yline(p.weight_dist_front, 'b:', sprintf('weight %.3f', p.weight_dist_front));
set(gca, 'XTick', 1:nV, 'XTickLabel', T.variant); xlim([0.4 nV + 0.6]);
ylabel('Front share of the aero load'); title({'Front axle share, incl. drag pitching moment', '(A: total near zero, not shown)'}, 'FontSize', 9);
subplot(2, 2, 4); hold on; grid on; box on
W = out.wake; st = {'-o', '-s', '-^', '-d'};
for k = 1:nV
    s = W(strcmp(W.variant, T.variant{k}), :);
    errorbar(s.plane_lengths, s.deficit_window, s.deficit_window - s.deficit_window_lo, s.deficit_window_hi - s.deficit_window, st{k}, 'LineWidth', 1.3, 'DisplayName', T.variant{k});
end
xlabel('Car lengths behind the rear axle'); ylabel('Mean velocity deficit in the following-car window');
legend('Location', 'northeast'); title({'Wake estimate', '(momentum-integral model, lowest confidence)'}, 'FontSize', 9);
sgtitle('PRE-CFD ESTIMATE: handbook formulas with assumed coefficients, nothing measured', 'FontWeight', 'bold');
save_fig(fig, 'aero_estimate');

fig = figure('Name', 'aero estimate wake', 'Position', [80 80 1100 420]);
light_theme(fig);
flds = {'deficit_centre', 'fwhm_m', 'centre_height_m'}; labs = {'Centre velocity deficit', 'Wake width, FWHM (m)', 'Height of the wake centre (m)'};
for q = 1:3
    subplot(1, 3, q); hold on; grid on; box on
    for k = 1:nV
        s = W(strcmp(W.variant, T.variant{k}), :);
        plot(s.plane_lengths, s.(flds{q}), st{k}, 'LineWidth', 1.5, 'DisplayName', T.variant{k});
    end
    xlabel('Car lengths behind the rear axle'); ylabel(labs{q});
    if q == 1, legend('Location', 'northeast'); end
end
sgtitle('PRE-CFD wake ESTIMATE: Gaussian momentum wake, spreading parameter assumed');
save_fig(fig, 'aero_estimate_wake');
fprintf('aero_estimate: media/aero_estimate.md, aero_estimate_table.csv, aero_estimate_wake.csv, aero_estimate.png, aero_estimate_wake.png written\n');
end

function light_theme(fig)
% figures are saved on white; force the light theme where MATLAB has one
try
    theme(fig, 'light');
catch
end
end

% =============================================================================
% VARIANT TABLE (params/aero_variants.csv, read by car_from_params)
% =============================================================================
function check_variant_table(T)
file = fullfile(repo_root(), 'params', 'aero_variants.csv');
if ~isfile(file), fprintf('aero_estimate: no params/aero_variants.csv yet; run aero_estimate(struct(''write_variants'', true)) to create it\n'); return, end
V = readtable(file, 'TextType', 'string', 'Delimiter', ',');
for k = 1:height(T)
    r = V(V.variant == T.variant{k}, :);
    if isempty(r) || ~startsWith(lower(r.source(1)), "estimate"), continue, end
    if abs(r.ClA(1) - T.ClA(k)) > 0.02 || abs(r.CdA(1) - T.CdA(k)) > 0.01
        warning('aero_estimate:stale', 'params/aero_variants.csv row %s (ClA %.2f, CdA %.2f) differs from the current estimate (%.2f, %.2f). Rerun aero_estimate(struct(''write_variants'', true)) if the lap sim should follow.', ...
            T.variant{k}, r.ClA(1), r.CdA(1), T.ClA(k), T.CdA(k));
    end
end
end

function write_variant_table(T)
file = fullfile(repo_root(), 'params', 'aero_variants.csv');
keep = table();
if isfile(file)
    V = readtable(file, 'TextType', 'string', 'Delimiter', ',');
    keep = V(startsWith(lower(V.source), "cfd"), :);
end
rows = {}; est = {};
for k = 1:height(T)
    af = T.aero_front(k); note = 'matlab/aero/aero_estimate.m, range = RSS of the assumption ranges';
    if isnan(af)
        af = T.ClA_front(k) / T.ClA(k);
        note = [note '; total near zero so the front share is a ratio of small numbers (front ' sprintf('%.2f', T.ClA_front(k)) ' m2, rear ' sprintf('%.2f', T.ClA_rear(k)) ' m2)']; %#ok<AGROW>
    end
    est(end+1, :) = {T.variant{k}, round(T.ClA(k), 3), round(T.CdA(k), 3), round(af, 3), round(T.ClA_lo(k), 2), round(T.ClA_hi(k), 2), round(T.CdA_lo(k), 2), round(T.CdA_hi(k), 2), 'ESTIMATE pre-CFD', note}; %#ok<AGROW>
    if ~isempty(keep) && any(keep.variant == T.variant{k})
        r = keep(keep.variant == T.variant{k}, :);
        rows(end+1, :) = {char(r.variant(1)), r.ClA(1), r.CdA(1), r.aero_front(1), r.ClA_lo(1), r.ClA_hi(1), r.CdA_lo(1), r.CdA_hi(1), char(r.source(1)), char(r.note(1))}; %#ok<AGROW>
        fprintf('aero_estimate: params/aero_variants.csv row %s is a CFD row, left alone\n', T.variant{k});
    else
        rows(end+1, :) = est(end, :); %#ok<AGROW>
    end
end
names = {'variant', 'ClA', 'CdA', 'aero_front', 'ClA_lo', 'ClA_hi', 'CdA_lo', 'CdA_hi', 'source', 'note'};
V = cell2table(rows, 'VariableNames', names);
writetable(V, file);
% the estimate alone, kept for the before/after comparison once CFD rows replace it (lap_experiments.m)
writetable(cell2table(est, 'VariableNames', names), fullfile(repo_root(), 'params', 'aero_variants_estimate.csv'));
fprintf('aero_estimate: params/aero_variants.csv written (%d rows)\n', height(V));
end

% =============================================================================
% SELF-TEST (hand-checkable)
% =============================================================================
function ok = selftest()
% (1) Zero-lift angle of a parabolic camber line z = 4 h x (1 - x), h = 0.04:
%       thin-airfoil theory gives aL0 = -2 h = -0.0800 rad. A flat line gives 0.
% (2) Glauert flap effectiveness with the hinge at mid chord (E = 0.5):
%       tf = pi/2, tau = 1 - (pi/2 - 1)/pi = 0.8183
% (3) Helmbold factor: AR = 2, a0 = 2 pi: k = 1, 1/(sqrt(2) + 1) = 0.4142;
%       very large AR -> 1
% (4) McCormick ground factor at 16 h/b = 1: 0.5. Endplates h/b = 0.5, k 1.9: AR x 1.95
% (5) Underbody channel: constant area, exit Cp 0 -> no suction, ClA = 0;
%       area ratio 2, efficiency 1, exit Cp 0: q1 = 1/(1 - 0.75) = 4, throat Cp = -3
% (6) Wake momentum: sigma = 1 m, d = 0.2 -> CdA = 4 pi (0.2 - 0.02) = 2.2619 m2,
%       and the inverse gives d = 0.2 back
% (7) Axle split: ClA 2 m2 at x = L/4 and CdA 0.5 m2 at z = 0.2 L:
%       front = 2 * 0.75 - 0.5 * 0.2 = 1.4 m2 -> share 0.70
% (8) Sections from the repo files: NACA 0012 aL0 = 0; NACA 6412 between
%       -6.6 and -5.6 deg (thin-airfoil value for 6 % camber at 40 % chord)
% (9) Direction checks on the real car: ClA and CdA rise from A to B to C;
%       every range brackets its nominal value.
h = 0.04;
a1 = zero_lift_angle(@(x) 4 * h * x .* (1 - x));
a0 = zero_lift_angle(@(x) 0 * x);
ok = abs(a1 + 2 * h) < 2e-4 && abs(a0) < 1e-12;
t5 = glauert_tau(0.5);
ok = ok && abs(t5 - (1 - (pi / 2 - 1) / pi)) < 1e-12 && abs(t5 - 0.8183) < 1e-4;
ok = ok && abs(helmbold(2 * pi, 2) - 1 / (sqrt(2) + 1)) < 1e-12 && abs(helmbold(2 * pi, 1e6) - 1) < 1e-5;
ok = ok && abs(mccormick_phi(1 / 16) - 0.5) < 1e-12;
x = linspace(0, 1, 501).';
u0 = channel(x, 0.05 * ones(size(x)), ones(size(x)), 0.5, 0, 1);
u2 = channel(x, 0.05 * (1 + x), ones(size(x)), 1, 0, 1);
ok = ok && abs(u0.ClA) < 1e-12 && abs(u2.q1 - 4) < 1e-9 && abs(u2.cp1 + 3) < 1e-9 && u2.ClA > 0 && u2.CdA > 0;
CdA = 4 * pi * (0.2 - 0.02);
ok = ok && abs(CdA - 2.2619) < 1e-4 && abs(gauss_deficit(CdA, 1) - 0.2) < 1e-9 && abs(gauss_sigma(CdA, 0.2) - 1) < 1e-9;
L = 1.55; ClA = 2; cd = 0.5;
front = ClA * (1 - 0.25) - cd * (0.2 * L) / L;
ok = ok && abs(front - 1.4) < 1e-12 && abs(front / ClA - 0.70) < 1e-12;
sec = load_sections();
ok = ok && abs(sec.symmetric.aL0) < 1e-3 && rad2deg(sec.fw_main.aL0) > -6.6 && rad2deg(sec.fw_main.aL0) < -5.6;
o = aero_estimate(struct('plot', false, 'write', false));
T = o.T;
ok = ok && all(diff(T.ClA(1:3)) > 0) && all(diff(T.CdA(1:3)) > 0) ...
    && all(T.ClA_lo <= T.ClA & T.ClA <= T.ClA_hi) && all(T.CdA_lo <= T.CdA & T.CdA <= T.CdA_hi) ...
    && height(o.wake) == 16 && all(o.wake.deficit_centre > 0 & o.wake.deficit_centre < 1);
% the split of the full model must reproduce the hand formula on its own components
m = o.models{3}; C = m.comp; Lc = read_car_params().wheelbase / 1000;
ok = ok && abs(sum(C.ClA .* (1 - C.x / Lc)) - sum(C.CdA .* C.z) / Lc - m.ClA_front) < 1e-12;
if ok
    fprintf('aero_estimate self-test: PASS (parabolic camber aL0 %.4f rad vs -0.0800; tau(0.5) %.4f; Helmbold AR 2 %.4f; channel AR 2 throat Cp %.1f; wake CdA %.4f m2; split 0.70; NACA 6412 aL0 %.2f deg; ClA A/B/C %.2f / %.2f / %.2f)\n', ...
        a1, t5, helmbold(2 * pi, 2), u2.cp1, CdA, rad2deg(sec.fw_main.aL0), T.ClA(1), T.ClA(2), T.ClA(3));
else
    error('aero_estimate self-test: FAIL (aL0 %.5f, tau %.5f, channel %.4g %.4g %.4g, wake %.5f, NACA 6412 aL0 %.3f deg)', ...
        a1, t5, u0.ClA, u2.q1, u2.cp1, gauss_deficit(CdA, 1), rad2deg(sec.fw_main.aL0));
end
end
