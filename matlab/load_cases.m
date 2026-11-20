function T = load_cases(opts)
%LOAD_CASES Ring 4: tyre contact-patch forces for the stress studies.
%   T = load_cases()           prints the table, writes sim/stress/load_cases.csv
%   T = load_cases(opts)       opts.variant ('CP', the as-built car), opts.plot/write (true)
%   load_cases('--selftest')
%
%   Cases (per wheel, N, at the contact patch, car axes: Fx forward,
%   Fy towards the inside of the turn, Fz up):
%     static        car + driver at rest
%     cornering     design_lateral_g at design_corner_speed with downforce
%     braking       design_braking_g from design_braking_speed with downforce
%     bump          design_bump_g vertical on every wheel (one-wheel bump is
%                   the same number on the loaded wheel)
%     corner_brake  combined: 0.7 of the cornering g and 0.7 of the braking g
%                   (friction-ellipse corner of the envelope)
%   Weight transfer is the rigid-body kind: lateral transfer per axle
%   = m_axle * ay * h / track, longitudinal = m * ax * h / L. No roll
%   stiffness distribution, no suspension geometry. Downforce is split by
%   aero_balance_front. Tyre forces per wheel are shared by the vertical
%   load on that wheel (loads follow grip).
%   For the upright study: apply Fx, Fy, Fz at the contact patch, or at the
%   hub centre with the moments Mx = Fy * r, My = Fx * r (r = rolling radius).
%   Values are re-checked against lap-sim peaks after Ring 6 (max lateral g
%   and max braking g in media/lap_times.csv runs).

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    T = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'variant'), opts.variant = 'CP'; end
if ~isfield(opts, 'write'), opts.write = true; end
if ~isfield(opts, 'p'), opts.p = read_car_params(); end
p = opts.p;
car = car_from_params(opts.variant, p);
g = car.g; m = car.m; h = car.h_cg; L = car.L;
tf = car.track_f; tr = car.track_r; wd = car.wd_front;

cases = {
    'static',       0,                  0,                 1,                0
    'cornering',    p.design_lateral_g, 0,                 1,                p.design_corner_speed
    'braking',      0,                  -p.design_braking_g, 1,              p.design_braking_speed
    'bump',         0,                  0,                 p.design_bump_g,  0
    'corner_brake', 0.7 * p.design_lateral_g, -0.7 * p.design_braking_g, 1,  p.design_corner_speed
    };
wheels = {'FL', 'FR', 'RL', 'RR'};
rows = [];
names = {};
for c = 1:size(cases, 1)
    ay = cases{c, 2} * g; ax = cases{c, 3} * g; nz = cases{c, 4}; v = cases{c, 5};
    DF = 0.5 * car.rho * car.ClA * v^2;
    DFf = DF * car.aero_front; DFr = DF - DFf;
    % static axle loads scaled by the vertical factor, plus downforce
    Ff = (wd * m * g) * nz + DFf;  Fr = ((1 - wd) * m * g) * nz + DFr;
    % longitudinal transfer (braking: ax < 0 moves load forward)
    dFx = m * ax * h / L;            % positive ax -> rear gains
    Ff = Ff - dFx; Fr = Fr + dFx;
    % lateral transfer per axle, inner wheel unloads (turn to the left: right wheel outer)
    dFyf = (Ff / (Ff + Fr)) * m * ay * h / tf;
    dFyr = (Fr / (Ff + Fr)) * m * ay * h / tr;
    Fz = [Ff / 2 - dFyf, Ff / 2 + dFyf, Fr / 2 - dFyr, Fr / 2 + dFyr];   % FL FR RL RR (left turn)
    Fz = max(Fz, 0);
    % share the lateral and longitudinal forces by vertical load
    Fy = m * ay * Fz / sum(Fz);
    if ax < 0
        Fx = m * ax * Fz / sum(Fz);                         % braking on all wheels
    else
        Fx = zeros(1, 4);
    end
    % drag at speed adds to the longitudinal demand in braking/cornering (small)
    for w = 1:4
        rows(end+1, :) = [c, w, Fx(w), Fy(w), Fz(w), hypot(Fx(w), Fy(w)) / max(Fz(w), 1)]; %#ok<AGROW>
        names(end+1, :) = {cases{c, 1}, wheels{w}}; %#ok<AGROW>
    end
end
T = table(string(names(:, 1)), string(names(:, 2)), rows(:, 3), rows(:, 4), rows(:, 5), rows(:, 6), ...
    'VariableNames', {'case', 'wheel', 'Fx_N', 'Fy_N', 'Fz_N', 'mu_required'});
T.Mx_hub_Nm = T.Fy_N * car.r_wheel;
T.My_hub_Nm = T.Fx_N * car.r_wheel;

if opts.write
    outDir = fullfile(repo_root(), 'sim', 'stress');
    if ~isfolder(outDir), mkdir(outDir); end
    writetable(T, fullfile(outDir, 'load_cases.csv'));
    fprintf('load_cases (variant %s, m = %.0f kg, h = %.0f mm): sim/stress/load_cases.csv written\n', opts.variant, m, h * 1000);
    disp(T);
    % the worst wheel per case for the upright
    fprintf('Worst wheel per case (largest resultant):\n');
    for c = 1:size(cases, 1)
        sel = T.case == cases{c, 1};
        res = hypot(hypot(T.Fx_N(sel), T.Fy_N(sel)), T.Fz_N(sel));
        [~, i] = max(res); ww = T.wheel(sel);
        fprintf('  %-13s %s  Fx %7.0f  Fy %7.0f  Fz %7.0f N\n', cases{c, 1}, ww(i), T.Fx_N(sel & T.wheel == ww(i)), ...
            T.Fy_N(sel & T.wheel == ww(i)), T.Fz_N(sel & T.wheel == ww(i)));
    end
    warning('off', 'backtrace');
    fprintf('Note: tyre mu_required above the tyre peak (%.2f) means the case exceeds grip and is an envelope, not a driving state.\n', car.mu0);
end
end

function ok = selftest()
% Hand checks (no aero, so set v = 0 by using a modified parameter struct):
%   static: four wheel loads sum to m g = 300 * 9.81 = 2943 N,
%           front axle = 0.47 * 2943 = 1383.2 N
%   cornering at 1.6 g, h = 0.3 m: total lateral = 1.6 * 2943 = 4708.8 N,
%           sum of Fz unchanged (2943 N), outer wheels carry more
%   braking at 1.5 g, L = 1.55 m: longitudinal transfer = 300*1.5*9.81*0.3/1.55 = 854.4 N
%           front axle = 1383.2 + 854.4 = 2237.6 N
p = read_car_params();
p.design_corner_speed = 0; p.design_braking_speed = 0;   % no aero
p.mass_car = 230; p.mass_driver = 70; p.weight_dist_front = 0.47; p.cg_height = 300; p.wheelbase = 1550;
T = load_cases(struct('write', false, 'p', p));
s = T(T.case == "static", :); c = T(T.case == "cornering", :); b = T(T.case == "braking", :);
mg = 300 * 9.81;
ok = abs(sum(s.Fz_N) - mg) < 1e-6 && abs(sum(s.Fz_N(1:2)) - 0.47 * mg) < 1e-6;
ok = ok && abs(sum(c.Fy_N) - 1.6 * mg) < 1e-6 && abs(sum(c.Fz_N) - mg) < 1e-6 && c.Fz_N(2) > c.Fz_N(1);
front_brake = 0.47 * mg + 300 * 1.5 * 9.81 * 0.3 / 1.55;
ok = ok && abs(sum(b.Fz_N(1:2)) - front_brake) < 1e-6 && abs(sum(b.Fx_N) + 1.5 * mg) < 1e-6;
if ok
    fprintf('load_cases self-test: PASS (static sum %.1f N, front %.1f N; braking front axle %.1f N)\n', sum(s.Fz_N), sum(s.Fz_N(1:2)), sum(b.Fz_N(1:2)));
else
    error('load_cases self-test: FAIL');
end
end
