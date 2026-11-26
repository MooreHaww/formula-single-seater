function car = car_from_params(variant, p, aeroSource)
%CAR_FROM_PARAMS Build the SI car struct used by every MATLAB model.
%   car = car_from_params()             variant 'CP' (the as-built car: C's
%                                       wings on the SolidWorks bodywork),
%                                       params from the repo file
%   car = car_from_params('B')          chosen aero variant (A, B, C, D or CP;
%                                       A to D are the like-for-like CFD
%                                       comparison on the older bodywork).
%                                       CP falls back to C's numbers where a
%                                       table or the parameter file has no CP
%   car = car_from_params('A', p)       from an already-read parameter struct
%   car = car_from_params('A', p, src)  src = 'table' (default): ClA, CdA and
%                                       aero_front from params/aero_variants.csv
%                                       (the one file to edit when CFD numbers
%                                       arrive; falls back to the parameter
%                                       file if the table or the row is
%                                       missing); 'params': the first guesses
%                                       ClA_<v>, CdA_<v>, aero_balance_front in
%                                       car_params.txt; or a table / file name
%                                       in the format of read_aero_variants
%   car = car_from_params('--selftest')
%
%   Fields (SI): m, g, wd_front, h_cg, L (wheelbase), r_wheel, mu0, fz_ref,
%   lsens, crr, rho, ClA, CdA, aero_front, P_max, T_max, rpm_max, i_gear,
%   eta, variant, aero_source (where the aero numbers came from),
%   ClA_range, CdA_range ([lo hi], NaN if unknown), aero_front_target.
%   Tyre model: mu(Fz) = mu0 * (fz_ref / Fz) ^ lsens   (grip falls with load)

if nargin >= 1 && strcmp(variant, '--selftest')
    car = selftest();
    return
end
if nargin < 1 || isempty(variant), variant = 'CP'; end
if nargin < 2 || isempty(p), p = read_car_params(); end
if nargin < 3, aeroSource = 'table'; end
variant = upper(char(variant));
if ~ismember(variant, {'A', 'B', 'C', 'D', 'CP', 'CPF'})
    error('car_from_params:variant', 'Variant must be A, B, C, D, CP or CPF, got %s', variant);
end
pv = variant;                                   % parameter-file guess: CP has C's wings
if ~isfield(p, ['ClA_' pv]) && startsWith(pv, 'CP'), pv = 'C'; end   % CP, CPF: C's wings

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
car.ClA       = p.(['ClA_' pv]);
car.CdA       = p.(['CdA_' pv]);
car.aero_front= p.aero_balance_front;
car.aero_source = 'car_params.txt first guess';
car.ClA_range = [NaN NaN]; car.CdA_range = [NaN NaN];
if ~(ischar(aeroSource) && strcmp(aeroSource, 'params'))
    if istable(aeroSource), V = aeroSource;
    elseif strcmp(aeroSource, 'table'), V = read_aero_variants();
    else, V = read_aero_variants(aeroSource);
    end
    tv = variant;
    if ~isempty(V) && strcmp(tv, 'CP') && ~any(V.variant == "CP"), tv = 'C'; end   % older table: C's row
    if ~isempty(V) && any(V.variant == tv)
        r = V(V.variant == tv, :);
        car.ClA = r.ClA; car.CdA = r.CdA; car.aero_front = r.aero_front;
        car.ClA_range = [r.ClA_lo, r.ClA_hi]; car.CdA_range = [r.CdA_lo, r.CdA_hi];
        car.aero_source = char(r.source);
    end
end
% design target for the front aero share (ESTIMATE/target in the file, from
% the cornering balance study); the models report against it, they do not use
% it unless asked (lapsim opts.aero_front = 'target')
if isfield(p, 'aero_balance_target'), car.aero_front_target = p.aero_balance_target; else, car.aero_front_target = NaN; end
% extra fields for the four-wheel cornering model (cornering_balance.m)
car.ride_freq_f  = p.ride_frequency_front;
car.ride_freq_r  = p.ride_frequency_rear;
car.m_unsprung_f = 2 * p.unsprung_mass_corner_front;
car.m_unsprung_r = 2 * p.unsprung_mass_corner_rear;
car.P_max     = p.motor_power_max;
car.T_max     = p.motor_torque_max;
car.rpm_max   = p.motor_rpm_max;
car.i_gear    = p.gear_ratio;
car.eta       = p.drivetrain_efficiency;
car.v_rpm_max = p.motor_rpm_max / 60 * 2 * pi * car.r_wheel / car.i_gear;
car.F_torque_max = car.T_max * car.i_gear * car.eta / car.r_wheel;
end

function ok = selftest()
% Hand check with the committed parameter file, masses pinned to the
% original starting values (the file's own are the rolled-up budget):
%   m = 230 + 70 = 300 kg
%   wheel-force limit from torque = 230 * 3.5 * 0.92 / 0.222 = 3335.6 N
%   rpm-limited speed = 6500/60 * 2*pi * 0.222 / 3.5 = 43.18 m/s
p = read_car_params(); p.mass_car = 230; p.mass_driver = 70;
car = car_from_params('C', p, 'params');
ok = abs(car.m - 300) < 1e-9 ...
   && abs(car.F_torque_max - 230*3.5*0.92/0.222) < 1e-6 ...
   && abs(car.v_rpm_max - 6500/60*2*pi*0.222/3.5) < 1e-6 ...
   && car.ClA == 4.0 && car.aero_front == p.aero_balance_front;
% Aero from a variant table: a one-row table for C must replace all three
% aero numbers and leave the other variants on the parameter-file guesses.
V = table("C", 4.5, 1.5, 0.42, NaN, NaN, NaN, NaN, "CFD test row", "", ...
    'VariableNames', {'variant', 'ClA', 'CdA', 'aero_front', 'ClA_lo', 'ClA_hi', 'CdA_lo', 'CdA_hi', 'source', 'note'});
cC = car_from_params('C', p, V); cB = car_from_params('B', p, V);
ok = ok && cC.ClA == 4.5 && cC.CdA == 1.5 && cC.aero_front == 0.42 && strcmp(cC.aero_source, 'CFD test row') ...
   && cB.ClA == p.ClA_B && cB.CdA == p.CdA_B && cB.aero_front == p.aero_balance_front;
% CP (the as-built default): a table without a CP row gives C's row; a CP
% row wins; the parameter-file guess is C's
cP = car_from_params('CP', p, V); cD = car_from_params([], p, V);
V2 = [V; table("CP", 3.9, 1.66, 0.43, NaN, NaN, NaN, NaN, "CFD CP row", "", 'VariableNames', V.Properties.VariableNames)];
cP2 = car_from_params('CP', p, V2); cP3 = car_from_params('CP', p, 'params');
ok = ok && cP.ClA == 4.5 && strcmp(cP.variant, 'CP') && strcmp(cD.variant, 'CP') && cD.ClA == 4.5 ...
   && cP2.ClA == 3.9 && cP2.CdA == 1.66 && cP2.aero_front == 0.43 && cP3.ClA == p.ClA_C;
if ok
    fprintf('car_from_params self-test: PASS (m=%.0f kg, F_torque_max=%.1f N, v_rpm_max=%.2f m/s)\n', ...
        car.m, car.F_torque_max, car.v_rpm_max);
else
    error('car_from_params self-test: FAIL');
end
end
