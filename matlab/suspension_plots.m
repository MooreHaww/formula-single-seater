function out = suspension_plots(opts)
%SUSPENSION_PLOTS Ring 3: camber gain, bump steer, motion ratio and spring
%   rate from the SolidWorks Motion CSV exports.
%   out = suspension_plots()          reads sim/motion/front_bump.csv and rear_bump.csv
%   out = suspension_plots(opts)      opts.files = {front, rear} to override
%   suspension_plots('--selftest')
%
%   Expected CSV columns (header names, any order, SolidWorks Motion plots
%   combined into one file per corner, see sim/motion/README.md):
%     wheel_travel_mm   positive = bump (wheel moves up relative to chassis)
%     camber_deg        negative = top of the wheel leans inward
%     toe_deg           positive = toe-in
%     track_change_mm   half-track change, positive = outward
%     spring_length_mm  spring free length minus compression
%   If a file is missing the script uses a synthetic data set, says so in the
%   plot title and in the output, and still produces every figure so the
%   pipeline can be checked before the CAD exists.
%
%   Derived numbers (out.front / out.rear):
%     camber_gain_deg_per_mm   slope of camber against travel (linear fit)
%     bump_steer_deg_range     max toe minus min toe over the travel
%     motion_ratio             |d spring_length / d wheel_travel|
%     k_wheel_N_per_m          (2 pi f)^2 * sprung mass per corner, f from
%                              params (ride_frequency_front / _rear)
%     k_spring_N_per_m         k_wheel / motion_ratio^2
%   Spring rate hand check: f = 3 Hz, m_sprung = 60 kg, MR = 0.7
%     k_wheel  = (2 pi 3)^2 * 60 = 355.3 * 60 = 21318 N/m
%     k_spring = 21318 / 0.49    = 43507 N/m  (43.5 N/mm)

if nargin >= 1 && ischar(opts) && strcmp(opts, '--selftest')
    out = selftest();
    return
end
if nargin < 1, opts = struct(); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'files')
    opts.files = {fullfile(repo_root(), 'sim', 'motion', 'front_bump.csv'), ...
                  fullfile(repo_root(), 'sim', 'motion', 'rear_bump.csv')};
end
p = read_car_params();
corners = {'front', 'rear'};
freq = [p.ride_frequency_front, p.ride_frequency_rear];
mSprung = [p.weight_dist_front, 1 - p.weight_dist_front] * (p.mass_car + p.mass_driver) / 2 ...
        - [p.unsprung_mass_corner_front, p.unsprung_mass_corner_rear];
out = struct();
for c = 1:2
    f = opts.files{c};
    if isfile(f)
        D = readtable(f); synthetic = false;
    else
        D = synthetic_data(c); synthetic = true;
        warning('suspension_plots:synthetic', 'No %s, using SYNTHETIC data for the %s corner', f, corners{c});
    end
    D.Properties.VariableNames = lower(D.Properties.VariableNames);
    need = {'wheel_travel_mm', 'camber_deg', 'toe_deg', 'track_change_mm', 'spring_length_mm'};
    for k = 1:numel(need)
        if ~ismember(need{k}, D.Properties.VariableNames)
            error('suspension_plots:columns', '%s lacks column %s', f, need{k});
        end
    end
    z = D.wheel_travel_mm;
    r.synthetic = synthetic;
    pc = polyfit(z, D.camber_deg, 1);       r.camber_gain_deg_per_mm = pc(1);
    r.camber_static_deg = polyval(pc, 0);
    r.bump_steer_deg_range = max(D.toe_deg) - min(D.toe_deg);
    pt = polyfit(z, D.toe_deg, 1);          r.bump_steer_deg_per_mm = pt(1);
    ps = polyfit(z, D.spring_length_mm, 1); r.motion_ratio = abs(ps(1));
    r.track_change_range_mm = max(D.track_change_mm) - min(D.track_change_mm);
    r.ride_frequency_target_hz = freq(c);
    r.sprung_mass_corner_kg = mSprung(c);
    r.k_wheel_N_per_m = (2 * pi * freq(c))^2 * mSprung(c);
    r.k_spring_N_per_m = r.k_wheel_N_per_m / r.motion_ratio^2;
    r.camber_sign_ok = r.camber_gain_deg_per_mm < 0;   % wheel leans inward in bump
    out.(corners{c}) = r;

    if opts.plot
        tag = ''; if synthetic, tag = ' [SYNTHETIC DATA, no motion study yet]'; end
        fig = figure('Name', ['suspension ' corners{c}], 'Position', [100 100 1000 700]);
        subplot(2, 2, 1); plot(z, D.camber_deg, 'LineWidth', 1.5); grid on
        xlabel('Wheel travel (mm, + bump)'); ylabel('Camber (deg)');
        title(sprintf('Camber gain %.4f deg/mm', r.camber_gain_deg_per_mm));
        subplot(2, 2, 2); plot(z, D.toe_deg, 'LineWidth', 1.5); grid on
        xlabel('Wheel travel (mm)'); ylabel('Toe (deg, + in)');
        title(sprintf('Bump steer: %.3f deg over the travel', r.bump_steer_deg_range));
        subplot(2, 2, 3); plot(z, D.track_change_mm, 'LineWidth', 1.5); grid on
        xlabel('Wheel travel (mm)'); ylabel('Half-track change (mm)');
        title(sprintf('Track change range %.2f mm', r.track_change_range_mm));
        subplot(2, 2, 4); plot(z, D.spring_length_mm, 'LineWidth', 1.5); grid on
        xlabel('Wheel travel (mm)'); ylabel('Spring length (mm)');
        title(sprintf('Motion ratio %.3f, spring %.1f N/mm for %.1f Hz', r.motion_ratio, r.k_spring_N_per_m / 1000, freq(c)));
        sgtitle(sprintf('%s corner bump test%s', corners{c}, tag));
        save_fig(fig, ['suspension_' corners{c}]);
    end
end
if opts.plot
    fprintf('suspension_plots:\n');
    for c = 1:2
        r = out.(corners{c});
        fprintf('  %-5s camber gain %+.4f deg/mm (%s), bump steer %.3f deg, MR %.3f, spring %.1f N/mm%s\n', ...
            corners{c}, r.camber_gain_deg_per_mm, ternary(r.camber_sign_ok, 'inward in bump: OK', 'WRONG SIGN'), ...
            r.bump_steer_deg_range, r.motion_ratio, r.k_spring_N_per_m / 1000, ternary(r.synthetic, '  [SYNTHETIC]', ''));
    end
end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function D = synthetic_data(c)
% A plausible double-wishbone corner: camber gain -0.05 deg/mm (front) or
% -0.04 (rear), a little bump steer, motion ratio 0.70 / 0.75.
z = (-30:1:30).';
if c == 1, cg = -0.05; mr = 0.70; else, cg = -0.04; mr = 0.75; end
D = table(z, -1.0 + cg * z, 0.02 * sin(z / 30 * pi / 2) + 0.1, 0.004 * z.^2 / 30, 200 - mr * z, ...
    'VariableNames', {'wheel_travel_mm', 'camber_deg', 'toe_deg', 'track_change_mm', 'spring_length_mm'});
end

function ok = selftest()
% Synthetic front data has camber gain -0.05 deg/mm and motion ratio 0.70.
% Spring rate hand check with the formula above using the script's own
% sprung mass and target frequency from the parameter file.
tmpF = [tempname '.csv']; tmpR = [tempname '.csv'];
writetable(synthetic_data(1), tmpF); writetable(synthetic_data(2), tmpR);
o = suspension_plots(struct('plot', false, 'files', {{tmpF, tmpR}}));
delete(tmpF); delete(tmpR);
p = read_car_params();
mS = p.weight_dist_front * (p.mass_car + p.mass_driver) / 2 - p.unsprung_mass_corner_front;
kWheel = (2 * pi * p.ride_frequency_front)^2 * mS;
ok = abs(o.front.camber_gain_deg_per_mm + 0.05) < 1e-9 && abs(o.front.motion_ratio - 0.70) < 1e-9 ...
   && abs(o.front.k_spring_N_per_m - kWheel / 0.49) < 1e-6 && abs(o.rear.motion_ratio - 0.75) < 1e-9 ...
   && ~o.front.synthetic;
% The documented hand example: f = 3 Hz, m = 60 kg, MR = 0.7 -> 43507 N/m
kHand = (2 * pi * 3)^2 * 60 / 0.7^2;
ok = ok && abs(kHand - 43507) < 2;
if ok
    fprintf('suspension_plots self-test: PASS (camber gain -0.050 deg/mm, MR 0.70, front spring %.0f N/m; hand example %.0f N/m)\n', o.front.k_spring_N_per_m, kHand);
else
    error('suspension_plots self-test: FAIL');
end
end
