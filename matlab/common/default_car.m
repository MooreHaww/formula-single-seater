function [variant, wakeRun, ref] = default_car(which)
%DEFAULT_CAR The one place that says which aero row is "the car".
%   v = default_car()                   'FINAL' (since 2026-11-28)
%   [v, wakeRun, ref] = default_car()   also the CFD run whose wake planes belong to
%                                       it ('FINAL_bl1') and the like-for-like aero
%                                       reference struct (CP_bl1, see below)
%   default_car('--selftest')
%
%   FINAL = CP's bodywork and wings with the F rear and J front wing supports
%   (CFD run FINAL_bl1, 1 prism layer: 2 layers went over the Student cell
%   limit). Every script that used CP as "the as-built car" by default now
%   asks this function. CP stays available by name (car_from_params('CP')).
%
%   Because FINAL is a 1-layer run, the fair aero reference is CP_bl1 (CP
%   meshed with 1 layer: ClA 3.977, CdA 1.667, front 0.431, cfd/results/
%   cfd_summary.csv), not the 2-layer CP row. ref holds those numbers and a
%   variant table with CP's row replaced by them, for car_from_params('CP', p, ref.table).
%   Noise: 2.2 % (CP vs CP_bl1, which also differ by the layer count) and
%   0.9 % (CP_bl1 vs its repeat CP_bl1r).

if nargin >= 1 && strcmp(which, '--selftest')
    variant = selftest();
    return
end
variant = 'FINAL';
wakeRun = 'FINAL_bl1';
if nargout > 2
    ref.name = 'CP_bl1';
    ref.ClA = 3.977; ref.CdA = 1.667; ref.aero_front = 0.431;
    ref.spread = 0.022; ref.repeat = 0.009;
    V = read_aero_variants();
    i = find(V.variant == "CP");
    if ~isempty(i)
        V.ClA(i) = ref.ClA; V.CdA(i) = ref.CdA; V.aero_front(i) = ref.aero_front;
        V.source(i) = "CFD CP_bl1 (in memory, default_car.m: CP meshed with 1 prism layer)";
    end
    ref.table = V;
end
end

function ok = selftest()
% Hand check: the default is FINAL, its row exists, car_from_params() gives it,
% and the CP_bl1 reference car carries the CP_bl1 numbers while 'CP' by name
% still reads the CP row.
[v, w, ref] = default_car();
V = read_aero_variants();
c = car_from_params();
cb = car_from_params('CP', [], ref.table);
cp = car_from_params('CP');
ok = strcmp(v, 'FINAL') && strcmp(w, 'FINAL_bl1') && any(V.variant == "FINAL") && strcmp(c.variant, 'FINAL') ...
    && c.ClA == V.ClA(V.variant == "FINAL") && cb.ClA == 3.977 && cb.CdA == 1.667 && cb.aero_front == 0.431 ...
    && cp.ClA == V.ClA(V.variant == "CP");
if ok
    fprintf('default_car self-test: PASS (default %s, ClA %.3f; CP_bl1 reference %.3f / %.3f / %.3f; CP by name %.3f)\n', ...
        c.variant, c.ClA, cb.ClA, cb.CdA, cb.aero_front, cp.ClA);
else
    error('default_car self-test: FAIL');
end
end
