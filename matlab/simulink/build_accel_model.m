function mdl = build_accel_model(car, mdl)
%BUILD_ACCEL_MODEL Build the Simulink 6b longitudinal model programmatically.
%   mdl = build_accel_model()         variant C, model name 'accel_75m'
%   mdl = build_accel_model(car)      from a car struct (car_from_params)
%   mdl = build_accel_model(car, name)
%
%   The model is the same physics as long_forces, drawn with standard blocks
%   so Simulink gets on the project honestly and the 75 m time can be
%   compared with accel_test.m (run_accel_simulink.m does the comparison):
%     omega     = v * i / r                      (motor speed, rad/s)
%     T_motor   = min(T_max, P_max / omega)      (power and torque caps)
%     F_pt      = T_motor * i * eta / r, zero above v_rpm_max
%     Fz        = m g + 0.5 rho ClA v^2
%     mu        = mu0 * (fz_ref / (Fz/4)) ^ lsens
%     F_trac    = mu * Fz * rear share          (rear-axle traction limit)
%     F_x       = min(F_pt, F_trac) - 0.5 rho CdA v^2 - crr Fz
%     dv/dt     = F_x / m,  ds/dt = v,  stop when s >= 75 m
%   Parameters live in the model workspace so the .slx is self-contained.
%   The model is saved as matlab/simulink/accel_75m.slx (ignored by git if
%   you prefer; this script rebuilds it in a second).

if nargin < 1 || isempty(car), car = car_from_params('C'); end
if nargin < 2, mdl = 'accel_75m'; end
if bdIsLoaded(mdl), close_system(mdl, 0); end
slxFile = fullfile(fileparts(mfilename('fullpath')), [mdl '.slx']);
if isfile(slxFile), delete(slxFile); end   % rebuilt below; avoids the name-shadowing warning
new_system(mdl); open_system(mdl);
set_param(mdl, 'StopTime', '30', 'SolverType', 'Variable-step', 'Solver', 'ode45', ...
    'MaxStep', '1e-3', 'RelTol', '1e-7', 'AbsTol', '1e-8');

% ---- parameters into the model workspace ------------------------------------------
mws = get_param(mdl, 'ModelWorkspace');
P = struct('m', car.m, 'g', car.g, 'rho', car.rho, 'ClA', car.ClA, 'CdA', car.CdA, 'crr', car.crr, ...
    'mu0', car.mu0, 'fz_ref', car.fz_ref, 'lsens', car.lsens, 'wd_front', car.wd_front, ...
    'aero_front', car.aero_front, 'P_max', car.P_max, 'T_max', car.T_max, 'i_gear', car.i_gear, ...
    'eta', car.eta, 'r_wheel', car.r_wheel, 'v_rpm_max', car.v_rpm_max, 's_end', 75);
fn = fieldnames(P);
for k = 1:numel(fn), mws.assignin(fn{k}, P.(fn{k})); end

% ---- helpers ------------------------------------------------------------------------
x = 30; y = 30; w = 60; h = 30;
    function b = blk(lib, name, pos, varargin)
        b = [mdl '/' name];
        add_block(lib, b, 'Position', pos, varargin{:});
    end
    function lnk(src, dst)
        add_line(mdl, src, dst, 'autorouting', 'on');
    end

% integrators: v and s
blk('simulink/Continuous/Integrator', 'v', [700 200 740 240], 'InitialCondition', '0');
blk('simulink/Continuous/Integrator', 's', [800 200 840 240], 'InitialCondition', '0');
lnk('v/1', 's/1');

% ---- powertrain force -------------------------------------------------------------------
blk('simulink/Math Operations/Gain', 'omega', [100 60 160 90], 'Gain', 'i_gear/r_wheel');          % rad/s
blk('simulink/Discontinuities/Saturation', 'omega_min', [190 60 250 90], 'LowerLimit', '1', 'UpperLimit', 'inf');
blk('simulink/Sources/Constant', 'P_max', [100 110 160 140], 'Value', 'P_max');
blk('simulink/Math Operations/Divide', 'P_over_omega', [280 80 330 120], 'Inputs', '*/');
blk('simulink/Sources/Constant', 'T_max', [280 140 330 170], 'Value', 'T_max');
blk('simulink/Math Operations/MinMax', 'T_motor', [360 100 410 140], 'Function', 'min', 'Inputs', '2');
blk('simulink/Math Operations/Gain', 'F_pt_raw', [440 105 500 135], 'Gain', 'i_gear*eta/r_wheel');
blk('simulink/Sources/Constant', 'zero', [440 40 500 70], 'Value', '0');
blk('simulink/Signal Routing/Switch', 'rpm_limit', [540 60 590 140], 'Criteria', 'u2 >= Threshold', 'Threshold', 'v_rpm_max');
lnk('v/1', 'omega/1'); lnk('omega/1', 'omega_min/1');
lnk('P_max/1', 'P_over_omega/1'); lnk('omega_min/1', 'P_over_omega/2');
lnk('P_over_omega/1', 'T_motor/1'); lnk('T_max/1', 'T_motor/2');
lnk('T_motor/1', 'F_pt_raw/1');
lnk('zero/1', 'rpm_limit/1'); lnk('v/1', 'rpm_limit/2'); lnk('F_pt_raw/1', 'rpm_limit/3');

% ---- vertical load and traction limit -------------------------------------------------
blk('simulink/Math Operations/Product', 'v_sq', [100 260 150 300], 'Inputs', '2');
blk('simulink/Math Operations/Gain', 'aero_down', [180 265 260 295], 'Gain', '0.5*rho*ClA');
blk('simulink/Sources/Constant', 'mg', [100 320 160 350], 'Value', 'm*g');
blk('simulink/Math Operations/Sum', 'Fz', [290 280 320 310], 'Inputs', '++');
lnk('v/1', 'v_sq/1'); lnk('v/1', 'v_sq/2'); lnk('v_sq/1', 'aero_down/1');
lnk('aero_down/1', 'Fz/1'); lnk('mg/1', 'Fz/2');
% mu = mu0 * (fz_ref / (Fz/4))^lsens
blk('simulink/Math Operations/Gain', 'fz_tyre', [350 280 410 310], 'Gain', '0.25');
blk('simulink/Sources/Constant', 'fz_ref', [350 330 410 360], 'Value', 'fz_ref');
blk('simulink/Math Operations/Divide', 'fz_ratio', [440 295 490 335], 'Inputs', '*/');
blk('simulink/Sources/Constant', 'lsens', [440 350 490 380], 'Value', 'lsens');
blk('simulink/Math Operations/Math Function', 'pow', [520 300 570 340], 'Operator', 'pow');
blk('simulink/Math Operations/Gain', 'mu', [600 305 650 335], 'Gain', 'mu0');
lnk('Fz/1', 'fz_tyre/1'); lnk('fz_ref/1', 'fz_ratio/1'); lnk('fz_tyre/1', 'fz_ratio/2');
lnk('fz_ratio/1', 'pow/1'); lnk('lsens/1', 'pow/2'); lnk('pow/1', 'mu/1');
% rear axle load = (1-wd) m g + (1-aero_front) * aero
blk('simulink/Math Operations/Gain', 'aero_rear', [290 400 370 430], 'Gain', '(1-aero_front)');
blk('simulink/Sources/Constant', 'mg_rear', [290 450 370 480], 'Value', '(1-wd_front)*m*g');
blk('simulink/Math Operations/Sum', 'Fz_rear', [400 420 430 450], 'Inputs', '++');
blk('simulink/Math Operations/Product', 'F_trac', [680 330 730 370], 'Inputs', '2');
lnk('aero_down/1', 'aero_rear/1'); lnk('aero_rear/1', 'Fz_rear/1'); lnk('mg_rear/1', 'Fz_rear/2');
lnk('mu/1', 'F_trac/1'); lnk('Fz_rear/1', 'F_trac/2');

% ---- resistances and net force ----------------------------------------------------------
blk('simulink/Math Operations/Gain', 'F_drag', [180 500 260 530], 'Gain', '0.5*rho*CdA');
blk('simulink/Math Operations/Gain', 'F_rr', [350 500 410 530], 'Gain', 'crr');
blk('simulink/Math Operations/MinMax', 'F_drive', [780 330 830 370], 'Function', 'min', 'Inputs', '2');
blk('simulink/Math Operations/Sum', 'F_x', [880 340 910 370], 'Inputs', '+--');
blk('simulink/Math Operations/Gain', 'a', [940 340 990 370], 'Gain', '1/m');
lnk('v_sq/1', 'F_drag/1'); lnk('Fz/1', 'F_rr/1');
lnk('rpm_limit/1', 'F_drive/1'); lnk('F_trac/1', 'F_drive/2');
lnk('F_drive/1', 'F_x/1'); lnk('F_drag/1', 'F_x/2'); lnk('F_rr/1', 'F_x/3');
lnk('F_x/1', 'a/1'); lnk('a/1', 'v/1');

% ---- stop at 75 m, log s and v ------------------------------------------------------------------
blk('simulink/Logic and Bit Operations/Compare To Constant', 'at_line', [900 200 960 240], 'relop', '>=', 'const', 's_end');
blk('simulink/Sinks/Stop Simulation', 'stop', [1000 205 1040 235]);
lnk('s/1', 'at_line/1'); lnk('at_line/1', 'stop/1');
blk('simulink/Sinks/To Workspace', 'log_s', [900 260 960 290], 'VariableName', 's_log', 'SaveFormat', 'Array');
blk('simulink/Sinks/To Workspace', 'log_v', [900 300 960 330], 'VariableName', 'v_log', 'SaveFormat', 'Array');
lnk('s/1', 'log_s/1'); lnk('v/1', 'log_v/1');

% annotation
add_block('built-in/Note', [mdl '/note'], 'Position', [30 560 30 560], 'Text', ...
    sprintf('Formula Single-Seater, Ring 6b: 75 m acceleration, variant %s. Same physics as matlab/common/long_forces.m. Built by build_accel_model.m', car.variant));

save_system(mdl, fullfile(fileparts(mfilename('fullpath')), [mdl '.slx']));
fprintf('build_accel_model: %s.slx built and saved (variant %s)\n', mdl, car.variant);
end
