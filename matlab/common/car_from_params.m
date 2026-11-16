function car = car_from_params(variant, p)
%CAR_FROM_PARAMS Build the SI car struct used by every MATLAB model.
%   car = car_from_params()             variant 'C', params from the repo file
%   car = car_from_params('B')          chosen aero variant (A, B, C or D)
%   car = car_from_params('A', p)       from an already-read parameter struct
%   car = car_from_params('--selftest')
%
%   Fields (SI): m, g, wd_front, h_cg, L (wheelbase), r_wheel, mu0, fz_ref,
%   lsens, crr, rho, ClA, CdA, aero_front, P_max, T_max, rpm_max, i_gear,
%   eta, variant.
%   Tyre model: mu(Fz) = mu0 * (fz_ref / Fz) ^ lsens   (grip falls with load)

if nargin >= 1 && strcmp(variant, '--selftest')
    car = selftest();
    return
end
if nargin < 1 || isempty(variant), variant = 'C'; end
if nargin < 2, p = read_car_params(); end
variant = upper(char(variant));
if ~ismember(variant, {'A', 'B', 'C', 'D'})
    error('car_from_params:variant', 'Variant must be A, B, C or D, got %s', variant);
end

car.variant   = variant;
car.g         = 9.81;
car.m         = p.mass_car + p.mass_driver;
car.wd_front  = p.weight_dist_front;
car.h_cg      = p.cg_height / 1000;
car.L         = p.wheelbase / 1000;
car.track_f   = p.track_front / 1000;
car.track_r   = p.track_rear / 1000;
car.r_wheel   = p.tyre_rolling_radius / 1000;
car.mu0       = p.tyre_mu_peak;
car.fz_ref    = p.tyre_fz_ref;
car.lsens     = p.tyre_load_sensitivity;
car.crr       = p.rolling_resistance;
car.rho       = p.air_density;
car.A_ref     = p.frontal_area;
car.ClA       = p.(['ClA_' variant]);
car.CdA       = p.(['CdA_' variant]);
car.aero_front= p.aero_balance_front;
car.P_max     = p.motor_power_max;
car.T_max     = p.motor_torque_max;
car.rpm_max   = p.motor_rpm_max;
car.i_gear    = p.gear_ratio;
car.eta       = p.drivetrain_efficiency;
car.v_rpm_max = p.motor_rpm_max / 60 * 2 * pi * car.r_wheel / car.i_gear;
car.F_torque_max = car.T_max * car.i_gear * car.eta / car.r_wheel;
end

function ok = selftest()
% Hand check with the committed parameter file:
%   m = 230 + 70 = 300 kg
%   wheel-force limit from torque = 230 * 3.5 * 0.92 / 0.222 = 3335.6 N
%   rpm-limited speed = 6500/60 * 2*pi * 0.222 / 3.5 = 43.18 m/s
car = car_from_params('C');
ok = abs(car.m - 300) < 1e-9 ...
   && abs(car.F_torque_max - 230*3.5*0.92/0.222) < 1e-6 ...
   && abs(car.v_rpm_max - 6500/60*2*pi*0.222/3.5) < 1e-6 ...
   && car.ClA == 4.0;
if ok
    fprintf('car_from_params self-test: PASS (m=%.0f kg, F_torque_max=%.1f N, v_rpm_max=%.2f m/s)\n', ...
        car.m, car.F_torque_max, car.v_rpm_max);
else
    error('car_from_params self-test: FAIL');
end
end
