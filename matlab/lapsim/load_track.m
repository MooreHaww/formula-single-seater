function track = load_track(name)
%LOAD_TRACK Read a track CSV from matlab/lapsim/tracks/.
%   track = load_track('autocross')   -> struct name, closed, length_m, radius_m
%   track = load_track('--selftest')
%
%   File format (see make_tracks.m, which writes them):
%     # name: autocross
%     # closed: 0
%     length_m,radius_m,angle_deg,note
%     60,0,0,start straight
%     31.42,-20,90,right-hander
%   radius_m: 0 = straight, positive = left turn, negative = right turn.
%   angle_deg and note are informational only.

if strcmp(name, '--selftest')
    track = selftest();
    return
end
file = name;
if ~isfile(file)
    file = fullfile(fileparts(mfilename('fullpath')), 'tracks', [char(name) '.csv']);
end
if ~isfile(file)
    error('load_track:missing', 'Track file not found: %s', file);
end
txt = splitlines(string(fileread(file)));
track.name = char(name); track.closed = false;
L = []; R = []; notes = strings(0, 1);
headerSeen = false;
for k = 1:numel(txt)
    t = strtrim(txt(k));
    if t == "", continue, end
    if startsWith(t, "#")
        kv = regexp(t, '^#\s*(\w+)\s*:\s*(.*)$', 'tokens', 'once');
        if ~isempty(kv)
            switch lower(kv{1})
                case 'name',   track.name = char(strtrim(kv{2}));
                case 'closed', track.closed = str2double(kv{2}) ~= 0;
            end
        end
        continue
    end
    if ~headerSeen, headerSeen = true; continue, end   % column header row
    c = split(t, ',');
    L(end+1, 1) = str2double(c(1)); %#ok<AGROW>
    R(end+1, 1) = str2double(c(2)); %#ok<AGROW>
    if numel(c) >= 4, notes(end+1, 1) = c(4); else, notes(end+1, 1) = ""; end %#ok<AGROW>
end
if any(isnan(L)) || any(isnan(R)) || isempty(L)
    error('load_track:parse', 'Could not parse %s', file);
end
track.length_m = L; track.radius_m = R; track.note = notes;
track.total_m = sum(L);
end

function ok = selftest()
% Hand check: the skidpad file is one segment of length 2*pi*9.125 = 57.334 m
t = load_track('skidpad');
ok = t.closed && numel(t.length_m) == 1 && abs(t.length_m - 2 * pi * 9.125) < 0.01 && t.radius_m == 9.125;
t2 = load_track('accel_75m');
ok = ok && ~t2.closed && t2.length_m == 75 && t2.radius_m == 0;
t3 = load_track('autocross'); t4 = load_track('fast_circuit');
ok = ok && t3.total_m > 900 && t3.total_m < 1300 && t4.closed && t4.total_m > 3000;
if ok
    fprintf('load_track self-test: PASS (skidpad %.3f m, autocross %.0f m, fast circuit %.0f m)\n', t.total_m, t3.total_m, t4.total_m);
else
    error('load_track self-test: FAIL');
end
end
