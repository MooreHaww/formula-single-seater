function out = make_lap_video(which)
%MAKE_LAP_VIDEO  Track-lap films from the lap-time simulation (as-built car CP, four-wheel model).
%
%   make_lap_video                 both tracks: autocross and fast circuit
%   make_lap_video('autocross')    one track
%   make_lap_video('selftest')     hand-checkable tests of the timing and silhouette helpers
%
% Writes (all git-ignored, remade by this script):
%   media/showcase/lap_autocross.mp4, lap_fast_circuit.mp4   1280x720, 30 fps, H.264, each under 10 MB
%   media/showcase/lap_autocross.gif                          720x405, 10 fps
%   media/showcase/frames_lap/<track>/*.png                   the film frames
%   media/showcase/lap_video_report.txt                       lap times, last clock shown, file sizes
%
% Each film: a top-down map of the track coloured by the simulated speed, the car moving round it, and
% live panels for the lap clock, speed, lateral g and longitudinal g. The car marker is the top-view
% silhouette of the CAD model (media/views/formula_single_seater_Default_top.png, written by
% "python tools/sw_run.py savestandardviews"); if that picture is missing it falls back to a dot. The
% marker is drawn enlarged so it can be seen at map scale (a 3 m car on a 500-1200 m map is a few pixels).
%
% Time: the frames are spaced in real time (1/30 s of simulated lap per frame). The lap clock on the
% last frames is the lap sim's own t_lap; the script stops if the time it integrates from s and v
% differs from t_lap by more than 1 ms. If an MP4 comes out over 10 MB the film is remade sped up and
% the caption says so.
%
% ffmpeg is the one inside .venv (imageio-ffmpeg), found by path.

if nargin < 1, which = 'all'; end
here = fileparts(mfilename('fullpath'));
repo = fileparts(here);
addpath(fullfile(here, 'common')); setup_paths();
if strcmp(which, 'selftest'), out = selftest(); return; end

tracks = {'autocross', 'fast_circuit'};
if ~strcmp(which, 'all'), tracks = {which}; end
car = car_from_params('CP');
sil = car_silhouette(fullfile(repo, 'media', 'views', 'formula_single_seater_Default_top.png'));
ff = ffmpeg_path(repo);
outdir = fullfile(repo, 'media', 'showcase');
if ~exist(outdir, 'dir'), mkdir(outdir); end
lines = {sprintf('make_lap_video report, %s', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')))};
out = struct('track', {}, 't_lap', {}, 'clock', {}, 'mp4', {}, 'mb', {}, 'speedup', {});
for k = 1:numel(tracks)
    nm = tracks{k};
    tr = load_track(nm);
    evalc('r = lapsim(car, tr, struct(''four_wheel'', true));');
    t = lap_times(r.s, r.v);
    if abs(t(end) - r.t_lap) > 1e-3
        error('make_lap_video:time', '%s: integrated time %.4f s differs from t_lap %.4f s', nm, t(end), r.t_lap);
    end
    mp4 = fullfile(outdir, ['lap_' nm '.mp4']);
    for speedup = [1 2 4]
        fdir = fullfile(outdir, 'frames_lap', nm);
        [nfr, clock] = render_frames(r, t, nm, sil, speedup, fdir);
        system_ok(sprintf('"%s" -y -loglevel error -framerate 30 -i "%s" -vf "scale=1280:720:flags=lanczos,format=yuv420p" -c:v libx264 -preset slow -crf 23 -movflags +faststart "%s"', ...
            ff, fullfile(fdir, '%05d.png'), mp4));
        mb = dir(mp4).bytes / 2^20;
        if mb < 10, break; end
        fprintf('%s: %.1f MB at %gx, remaking faster\n', nm, mb, speedup);
    end
    line = sprintf('%-13s four-wheel t_lap %.4f s, last clock shown "%s", %d frames (%.1f s film at %gx), %s %.2f MB (limit 10 MB: %s)', ...
        nm, r.t_lap, clock, nfr, nfr / 30, speedup, ['lap_' nm '.mp4'], mb, tf_str(mb < 10));
    if strcmp(nm, 'autocross')
        gif = fullfile(outdir, 'lap_autocross.gif');
        pal = fullfile(fdir, 'palette.png');
        vf = 'fps=10,scale=720:405:flags=lanczos';
        system_ok(sprintf('"%s" -y -loglevel error -framerate 30 -i "%s" -vf "%s,palettegen=stats_mode=diff" "%s"', ff, fullfile(fdir, '%05d.png'), vf, pal));
        system_ok(sprintf('"%s" -y -loglevel error -framerate 30 -i "%s" -i "%s" -lavfi "%s[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" "%s"', ...
            ff, fullfile(fdir, '%05d.png'), pal, vf, gif));
        delete(pal);
        line = sprintf('%s; lap_autocross.gif %.2f MB', line, dir(gif).bytes / 2^20);
    end
    fprintf('%s\n', line);
    lines{end + 1} = line; %#ok<AGROW>
    out(end + 1) = struct('track', nm, 't_lap', r.t_lap, 'clock', clock, 'mp4', mp4, 'mb', mb, 'speedup', speedup); %#ok<AGROW>
end
fid = fopen(fullfile(outdir, 'lap_video_report.txt'), 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

% ---------------------------------------------------------------------------------------------------
function [n, clock] = render_frames(r, t, nm, sil, speedup, fdir)
CAPTION = 'Lap-time simulation, as-built car (CP). Rigid chassis, assumed tyre grip (mu 1.4). Not a physical test.';
fps = 30;
if exist(fdir, 'dir'), rmdir(fdir, 's'); end
mkdir(fdir);
g = 9.81;
x = r.x(:); y = r.y(:); v = r.v(:) * 3.6; ax = r.ax(:) / g; ay = r.ay(:) / g;
ax(end) = ax(end - 1);                        % lapsim pads the last ax with 0
psi = unwrap(atan2(gradient(y), gradient(x)));
% frame times: real time (x speedup), the exact t_lap as the last moving frame, then a 2.5 s hold
tf = 0:speedup / fps:r.t_lap;
if tf(end) < r.t_lap - 1e-9, tf(end + 1) = r.t_lap; end
nhold = round(2.5 * fps);
tf = min(tf, t(end));                     % t(end) and t_lap differ by round-off; never interpolate past the data
I = @(q) interp1(t, q, tf);
X = I(x); Y = I(y); V = I(v); AX = I(ax); AY = I(ay); PSI = I(psi);
if any(isnan([X V AX AY PSI])), error('make_lap_video:nan', '%s: NaN in the interpolated lap', nm); end

names = struct('autocross', 'Autocross', 'fast_circuit', 'Fast circuit');
f = figure('Visible', 'off', 'Units', 'pixels', 'Position', [20 20 1280 720], 'Color', 'w');
try, theme(f, 'light'); catch, end   % R2025a+ follows the desktop's dark theme otherwise
annotation(f, 'textbox', [0 0.935 1 0.065], 'String', sprintf('%s: lap-time simulation, four-wheel model', names.(nm)), ...
    'EdgeColor', 'none', 'BackgroundColor', [0.96 0.96 0.96], 'FontWeight', 'bold', 'FontUnits', 'pixels', 'FontSize', 22, ...
    'VerticalAlignment', 'middle', 'Margin', 14);
cap = CAPTION;
if speedup > 1, cap = sprintf('%s Shown at %gx speed.', CAPTION, speedup); end
annotation(f, 'textbox', [0 0 1 0.055], 'String', cap, 'EdgeColor', 'none', 'BackgroundColor', [0.96 0.96 0.96], ...
    'FontUnits', 'pixels', 'FontSize', 17, 'VerticalAlignment', 'middle', 'Margin', 14, 'Color', [0.2 0.2 0.2]);

% map, coloured by speed
am = axes(f, 'Position', [0.015 0.08 0.60 0.84]);
patch(am, [x; NaN], [y; NaN], [v; NaN], 'EdgeColor', 'interp', 'FaceColor', 'none', 'LineWidth', 7);
hold(am, 'on');
colormap(am, turbo);
clim(am, [floor(min(v(v > 5)) / 10) * 10, ceil(max(v) / 10) * 10]);   % colour range = the lap's own speeds
plot(am, x(1), y(1), 'ks', 'MarkerSize', 12, 'MarkerFaceColor', 'w', 'LineWidth', 2);
axis(am, 'equal'); axis(am, 'off');
span = max(max(x) - min(x), max(y) - min(y));
pad = 0.06 * span;
xlim(am, [min(x) - pad, max(x) + pad]); ylim(am, [min(y) - pad, max(y) + pad]);
cb = colorbar(am, 'southoutside');
cb.Label.String = 'simulated speed (km/h)'; cb.FontSize = 11;
Lm = 0.07 * span;                            % marker length: enlarged, not to scale
if isempty(sil)
    car = plot(am, X(1), Y(1), 'o', 'MarkerSize', 14, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w', 'LineWidth', 2);
else
    car = patch(am, 'XData', sil(:, 1), 'YData', sil(:, 2), 'FaceColor', [0.05 0.05 0.05], 'EdgeColor', [0.05 0.05 0.05], 'LineWidth', 1);
end
note = text(am, 0.01, 0.99, 'car marker enlarged', 'Units', 'normalized', 'VerticalAlignment', 'top', ...
    'Color', [0.45 0.45 0.45], 'FontUnits', 'pixels', 'FontSize', 14); %#ok<NASGU>

% live panels
clk = annotation(f, 'textbox', [0.645 0.80 0.34 0.11], 'String', '', 'EdgeColor', [0.8 0.8 0.8], ...
    'BackgroundColor', [0.08 0.1 0.14], 'Color', 'w', 'FontWeight', 'bold', 'FontUnits', 'pixels', 'FontSize', 34, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontName', 'Consolas');
specs = {V, 'speed', 'km/h', '%5.1f', [0 ceil(max(v) / 20) * 20]; ...
         AY, 'lateral g', 'g', '%+5.2f', [-1 1] * ceil(max(abs(ay)) * 2) / 2; ...
         AX, 'longitudinal g', 'g', '%+5.2f', [floor(min(ax) * 2) / 2, ceil(max(ax) * 2) / 2]};
ys = [0.565 0.335 0.105];
for i = 1:3
    a = axes(f, 'Position', [0.685 ys(i) 0.30 0.16]); %#ok<LAXES>
    q = specs{i, 1};
    plot(a, tf, q, '-', 'Color', [0.82 0.82 0.82], 'LineWidth', 1.2); hold(a, 'on');
    yline(a, 0, ':', 'Color', [0.6 0.6 0.6]);
    hl(i) = plot(a, tf(1), q(1), '-', 'Color', [0.1 0.35 0.65], 'LineWidth', 1.8); %#ok<AGROW>
    hd(i) = plot(a, tf(1), q(1), 'o', 'MarkerFaceColor', [0.85 0.2 0.1], 'MarkerEdgeColor', 'none', 'MarkerSize', 7); %#ok<AGROW>
    xlim(a, [0 r.t_lap]); ylim(a, specs{i, 5});
    set(a, 'Box', 'on', 'FontUnits', 'pixels', 'FontSize', 13, 'XColor', [0.4 0.4 0.4], 'YColor', [0.4 0.4 0.4]);
    if i == 3, xlabel(a, 'lap time (s)'); else, a.XTickLabel = {}; end
    ht(i) = title(a, '', 'FontUnits', 'pixels', 'FontSize', 19, 'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.02 0]); %#ok<AGROW>
end

n = 0;
nmove = numel(tf);
for j = 1:nmove + nhold
    i = min(j, nmove);
    c = cos(PSI(i)); s = sin(PSI(i));
    if isempty(sil)
        set(car, 'XData', X(i), 'YData', Y(i));
    else
        set(car, 'XData', X(i) + Lm * (c * sil(:, 1) - s * sil(:, 2)), 'YData', Y(i) + Lm * (s * sil(:, 1) + c * sil(:, 2)));
    end
    for p = 1:3
        q = specs{p, 1};
        set(hl(p), 'XData', tf(1:i), 'YData', q(1:i));
        set(hd(p), 'XData', tf(i), 'YData', q(i));
        set(ht(p), 'String', sprintf(['%s  ' specs{p, 4} ' %s'], specs{p, 2}, q(i), specs{p, 3}));
    end
    if j < nmove
        clock = sprintf('lap clock  %6.2f s', tf(i));
    else
        clock = sprintf('lap time  %6.2f s', r.t_lap);
    end
    clk.String = clock;
    drawnow;
    fr = getframe(f);
    imwrite(fr.cdata, fullfile(fdir, sprintf('%05d.png', n)));
    n = n + 1;
end
close(f);
end

% ---------------------------------------------------------------------------------------------------
function t = lap_times(s, v)
% Time at every point of the lap from distance and speed, trapezoidal in 1/v as lapsim does:
% dt = 2 ds / (v_i + v_i+1).
s = s(:); v = v(:);
t = [0; cumsum(2 * diff(s) ./ (v(1:end - 1) + v(2:end)))];
end

function P = car_silhouette(png)
% Outline of the car's top view as a polygon in car axes, length 1, x forward, centred.
% The picture has the car's nose on the left; for each pixel column the top and bottom of the
% non-white pixels give the outline (fine for a car seen from above, which has no holes that matter).
P = [];
if ~isfile(png), return; end
a = imread(png);
if size(a, 3) == 3, a = mean(double(a), 3); end
m = a < 240;
cols = find(any(m, 1));
if numel(cols) < 50, return; end
cols = cols(1):4:cols(end);
top = zeros(size(cols)); bot = top;
for k = 1:numel(cols)
    rr = find(m(:, cols(k)));
    if isempty(rr), rr = [NaN; NaN]; end
    top(k) = rr(1); bot(k) = rr(end);
end
ok = ~isnan(top); cols = cols(ok); top = top(ok); bot = bot(ok);
L = cols(end) - cols(1);
cx = (cols(1) + cols(end)) / 2; cy = (min(top) + max(bot)) / 2;
fwd = -(cols - cx) / L;                        % nose (left of the picture) is +x
P = [[fwd, fliplr(fwd)]', -([top, fliplr(bot)]' - cy) / L];
end

function ff = ffmpeg_path(repo)
d = dir(fullfile(repo, '.venv', 'Lib', 'site-packages', 'imageio_ffmpeg', 'binaries', 'ffmpeg*.exe'));
if isempty(d), error('make_lap_video:ffmpeg', 'no ffmpeg in .venv (pip install imageio-ffmpeg)'); end
ff = fullfile(d(1).folder, d(1).name);
end

function system_ok(cmd)
[st, msg] = system(cmd);
if st ~= 0, error('make_lap_video:ffmpeg', 'ffmpeg failed (%d): %s', st, msg); end
end

function s = tf_str(b)
if b, s = 'yes'; else, s = 'NO'; end
end

% ---------------------------------------------------------------------------------------------------
function ok = selftest()
% lap_times by hand: 100 m at a constant 10 m/s is 10 s; from rest to 2 m/s over 1 m is 2*1/(0+2) = 1 s
t1 = lap_times(0:10:100, 10 * ones(1, 11));
t2 = lap_times([0 1], [0 2]);
ok1 = abs(t1(end) - 10) < 1e-12 && abs(t2(end) - 1) < 1e-12;
% car_silhouette on a synthetic picture: a black 201 x 51 px block -> a 1 x 0.25 box (50/200), centred
tmp = [tempname '.png'];
im = 255 * ones(300, 400, 'uint8');
im(100:150, 100:300) = 0;
imwrite(im, tmp);
P = car_silhouette(tmp);
delete(tmp);
ok2 = abs(max(P(:, 1)) - 0.5) < 1e-12 && abs(min(P(:, 1)) + 0.5) < 1e-12 && abs(max(P(:, 2)) - 0.125) < 1e-12 ...
    && abs(min(P(:, 2)) + 0.125) < 1e-12;
ok = ok1 && ok2;
fprintf('make_lap_video self-test: %s (lap_times 10 s and 1 s: %s; silhouette box 1 x 0.25: %s)\n', ...
    tf_str(ok), tf_str(ok1), tf_str(ok2));
end
