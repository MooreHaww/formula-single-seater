function f = long_forces(car, v, Fy)
%LONG_FORCES Longitudinal force budget of the point-mass car at speed v.
%   f = long_forces(car, v, Fy)   v in m/s (scalar or vector), Fy = lateral
%   force the tyres are already providing (N, same size as v or scalar).
%   f = long_forces('--selftest')
%
%   This one function is the physics shared by accel_test, the lap simulator
%   and (by construction) the Simulink 6b model, so they cannot disagree.
%
%   Fields of f (all N unless noted):
%     Fz         total vertical load = m g + 0.5 rho ClA v^2
%     mu         friction coefficient with load sensitivity
%                mu = mu0 * (fz_ref / (Fz/4)) ^ lsens
%     Fmax       mu * Fz, total tyre force available
%     Fgrip      longitudinal grip left after Fy: sqrt(Fmax^2 - Fy^2)
%     F_pt       powertrain force at the wheels: min(P eta / v, torque limit),
%                zero above the rpm-limited speed
%     F_drive    net accelerating force = min(rear-axle grip, F_pt) - drag - rolling
%     F_brake    net decelerating force = Fgrip + drag + rolling (all four wheels)
%     F_drag, F_rr
%   Rear-axle grip = Fgrip * (rear share of Fz), rear share from the static
%   weight distribution and the aero balance.

if ischar(car) && strcmp(car, '--selftest')
    f = selftest();
    return
end
if nargin < 3, Fy = 0; end
v = max(v, 0);
Fz   = car.m * car.g + 0.5 * car.rho * car.ClA * v.^2;
mu   = car.mu0 * (car.fz_ref ./ (Fz / 4)).^car.lsens;
Fmax = mu .* Fz;
Fy   = min(abs(Fy), Fmax);
Fgrip = sqrt(max(0, Fmax.^2 - Fy.^2));
aero = Fz - car.m * car.g;
rearShare = ((1 - car.wd_front) * car.m * car.g + (1 - car.aero_front) * aero) ./ Fz;
F_pt = min(car.P_max * car.eta ./ max(v, 0.5), car.F_torque_max);
F_pt(v >= car.v_rpm_max) = 0;
F_drag = 0.5 * car.rho * car.CdA * v.^2;
F_rr   = car.crr * Fz;

f.Fz = Fz; f.mu = mu; f.Fmax = Fmax; f.Fgrip = Fgrip;
f.F_pt = F_pt; f.F_drag = F_drag; f.F_rr = F_rr;
f.F_drive = min(Fgrip .* rearShare, F_pt) - F_drag - F_rr;
f.F_brake = Fgrip + F_drag + F_rr;
end

function ok = selftest()
% Hand check, car: m = 300 kg, g = 9.81, no aero, no load sensitivity,
% mu0 = 1.4, wd_front = 0.47, P = 80 kW, eta = 0.92, crr = 0.015,
% torque limit 3336 N, v = 10 m/s, Fy = 0:
%   Fz   = 2943 N
%   Fmax = 1.4 * 2943 = 4120.2 N
%   rear share = 0.53 -> rear grip = 2183.7 N
%   F_pt = min(80000*0.92/10, 3336) = min(7360, 3336) = 3336 N
%   F_rr = 0.015 * 2943 = 44.1 N, drag 0
%   F_drive = 2183.7 - 44.1 = 2139.6 N
%   F_brake = 4120.2 + 44.1 = 4164.3 N
car = test_car();
f = long_forces(car, 10, 0);
ok = abs(f.F_drive - (0.53 * 4120.2 - 44.145)) < 0.2 && abs(f.F_brake - 4164.3) < 0.2;
% With Fy = Fmax no longitudinal grip is left: F_drive = -F_rr
f2 = long_forces(car, 10, f.Fmax);
ok = ok && abs(f2.F_drive + 44.145) < 1e-6;
% Above the rpm limit the powertrain gives nothing
f3 = long_forces(car, car.v_rpm_max + 1, 0);
ok = ok && f3.F_pt == 0;
if ok
    fprintf('long_forces self-test: PASS (F_drive=%.1f N, F_brake=%.1f N at 10 m/s)\n', f.F_drive, f.F_brake);
else
    error('long_forces self-test: FAIL');
end
end

function car = test_car()
car = car_from_params('A');
car.ClA = 0; car.CdA = 0; car.lsens = 0; car.mu0 = 1.4; car.wd_front = 0.47;
car.m = 300; car.g = 9.81; car.crr = 0.015; car.P_max = 80000; car.eta = 0.92;
car.F_torque_max = 3336;
end
