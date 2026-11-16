function make_tracks()
%MAKE_TRACKS Write the four track CSV files into matlab/lapsim/tracks/.
%   Tracks are lists of straights and constant-radius arcs. Arc length is
%   computed from radius and turn angle so the files stay consistent.
%   Sign convention: positive radius = left turn, negative = right turn.
%
%   skidpad       FS skidpad centreline circle (15.25 m inner diameter plus
%                 half of the 3 m lane = 9.125 m radius), flying lap
%   accel_75m     the FS acceleration event, standing start
%   autocross     FS-style, about 1 km, tight: slaloms, hairpins, short straights
%   fast_circuit  about 3.5 km closed loop with long straights and high-speed
%                 corners (R 80 to 200 m) where downforce shows its value
outDir = fullfile(fileparts(mfilename('fullpath')), 'tracks');
if ~isfolder(outDir), mkdir(outDir); end

write_track(outDir, 'skidpad', true, {arc(9.125, 360, 'L', 'FS skidpad circle, centreline radius 9.125 m')});
write_track(outDir, 'accel_75m', false, {str(75, 'FS acceleration event, 75 m from standing start')});

% ---- autocross, point to point, standing start -------------------------------
A = {
    str(60, 'start straight')
    arc(20, 90, 'R', 'first corner')
    str(30, '')
    arc(9, 60, 'L', 'slalom in')
    arc(9, 120, 'R', 'slalom')
    arc(9, 120, 'L', 'slalom')
    arc(9, 120, 'R', 'slalom')
    arc(9, 60, 'L', 'slalom out')
    str(40, '')
    arc(30, 180, 'L', 'long constant-radius sweeper')
    str(30, '')
    arc(12, 90, 'R', '')
    str(20, '')
    arc(12, 90, 'L', '')
    str(70, 'longest straight')
    arc(8, 180, 'R', 'hairpin')
    str(35, '')
    arc(40, 120, 'L', 'fast sweeper')
    str(25, '')
    arc(15, 90, 'R', '')
    str(45, '')
    arc(10, 45, 'L', 'chicane')
    arc(10, 90, 'R', 'chicane')
    arc(10, 45, 'L', 'chicane')
    str(60, '')
    arc(25, 135, 'L', '')
    str(30, '')
    arc(18, 90, 'R', '')
    str(45, '')
    arc(9, 180, 'L', 'hairpin')
    str(40, '')
    arc(35, 100, 'R', '')
    str(35, 'finish straight')
    };
write_track(outDir, 'autocross', false, A);

% ---- fast circuit, closed, flying lap --------------------------------------
% Signed turn angles sum to -360 deg (one clockwise loop). Geometric closure
% is approximate; the simulator only needs the curvature profile and the
% flying-lap speed wrap.
% Closure by construction (hand derivation in docs/lapsim.md): with main
% straight A, legs B, C, D, E the loop closes when C + D = A - 96.4 and
% E = B + 100. Here A = 800, B = 300, C = 300, D = 403.6, E = 400.
F = {
    str(800, 'main straight')
    arc(120, 90, 'R', 'turn 1, fast')
    str(300, '')
    arc(60, 90, 'R', 'turn 2, medium')
    str(300, '')
    arc(200, 60, 'L', 'esses, very fast')
    arc(200, 60, 'R', 'esses, very fast')
    str(403.6, 'back straight')
    arc(45, 180, 'R', 'hairpin')
    arc(80, 90, 'L', 'turn 6, fast')
    str(400, '')
    arc(110, 90, 'R', 'final corner onto the main straight')
    };
write_track(outDir, 'fast_circuit', true, F);
fprintf('make_tracks: wrote 4 track files to %s\n', outDir);
end

function seg = str(len, note)
seg = struct('length_m', len, 'radius_m', 0, 'angle_deg', 0, 'note', note);
end

function seg = arc(R, angleDeg, dir, note)
sgn = 1; if upper(dir) == 'R', sgn = -1; end
seg = struct('length_m', R * deg2rad(angleDeg), 'radius_m', sgn * R, 'angle_deg', sgn * angleDeg, 'note', note);
end

function write_track(outDir, name, closed, segs)
if closed && numel(segs) > 1
    segs = close_loop(segs, name);
end
fid = fopen(fullfile(outDir, [name '.csv']), 'w');
fprintf(fid, '# name: %s\n# closed: %d\n', name, closed);
fprintf(fid, '# radius_m: 0 = straight, +left, -right. Written by make_tracks.m\n');
fprintf(fid, 'length_m,radius_m,angle_deg,note\n');
total = 0; ang = 0;
for k = 1:numel(segs)
    s = segs{k};
    fprintf(fid, '%.3f,%g,%g,%s\n', s.length_m, s.radius_m, s.angle_deg, s.note);
    total = total + s.length_m; ang = ang + s.angle_deg;
end
fprintf(fid, '# total_m: %.1f, net turn angle: %g deg\n', total, ang);
fclose(fid);
end

function segs = close_loop(segs, name)
% Make the loop close geometrically by adjusting the lengths of the two
% straights (with non-parallel headings) that need the smallest change,
% keeping every straight between 80 and 900 m. Two unknowns, two equations.
L = cellfun(@(s) s.length_m, segs); R = cellfun(@(s) s.radius_m, segs);
[x, y, H] = end_point(L, R);
best = [];
for a = 1:size(H, 1)
    for b = a+1:size(H, 1)
        A = [cos(H(a, 2)) cos(H(b, 2)); sin(H(a, 2)) sin(H(b, 2))];
        if abs(det(A)) < 0.3, continue, end
        d = A \ [-x; -y];
        La = L(H(a, 1)) + d(1); Lb = L(H(b, 1)) + d(2);
        if La >= 80 && Lb >= 80 && La <= 900 && Lb <= 900
            score = max(abs(d));
            if isempty(best) || score < best(1), best = [score, H(a, 1), H(b, 1), La, Lb]; end
        end
    end
end
if isempty(best)
    warning('make_tracks:closure', '%s: could not close the loop by adjusting two straights (end point %.0f, %.0f m)', name, x, y);
    return
end
segs{best(2)}.length_m = best(4); segs{best(3)}.length_m = best(5);
segs{best(2)}.note = strtrim([segs{best(2)}.note ' (length set for loop closure)']);
segs{best(3)}.note = strtrim([segs{best(3)}.note ' (length set for loop closure)']);
L = cellfun(@(s) s.length_m, segs);
[x, y] = end_point(L, R);
fprintf('make_tracks: %s closed by setting segments %d and %d to %.0f and %.0f m (end point error %.2f m)\n', ...
    name, best(2), best(3), best(4), best(5), hypot(x, y));
end

function [x, y, H] = end_point(L, R)
% end point of the segment list and the heading at the start of each straight
psi = 0; x = 0; y = 0; H = zeros(0, 2);
for j = 1:numel(L)
    if R(j) == 0
        H(end+1, :) = [j, psi]; %#ok<AGROW>
        x = x + L(j) * cos(psi); y = y + L(j) * sin(psi);
    else
        d = L(j) / R(j);
        x = x + R(j) * (sin(psi + d) - sin(psi));
        y = y - R(j) * (cos(psi + d) - cos(psi));
        psi = psi + d;
    end
end
end
