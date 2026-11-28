function V = read_aero_variants(file)
%READ_AERO_VARIANTS Read the aero variant table the lap sim uses.
%   V = read_aero_variants()          reads <repo>/params/aero_variants.csv
%   V = read_aero_variants(file)      reads the given file
%   read_aero_variants('--selftest')
%
%   The table is the ONE file to edit when better aero numbers arrive. One
%   row per variant: A, B, C, D (the like-for-like comparison, CFD on the
%   older bodywork) and CP (C's wings on the SolidWorks bodywork: the
%   as-built car, the default of car_from_params):
%     variant      A, B, C, D, CP, CPF (CP with the F rear-wing supports of
%                  docs/wing_supports_plan.md) CPFF (CPF plus J front-wing
%                  supports) or CPG (CP with the ridged G rear supports): CFD only, the CAD has no supports
%     ClA          m2, positive = downforce
%     CdA          m2
%     aero_front   fraction of the aero load on the front axle, including the
%                  pitching moment of the drag (front axle load / total)
%     ClA_lo, ClA_hi, CdA_lo, CdA_hi   range of the estimate (empty or NaN is fine)
%     source       free text; starts with ESTIMATE for the pre-CFD model
%                  (matlab/aero/aero_estimate.m) or with CFD once a run exists.
%                  aero_estimate never overwrites a row whose source starts
%                  with CFD.
%     note         free text
%   Returns an empty table if the file does not exist (car_from_params then
%   falls back to the ClA_<v> / CdA_<v> guesses in car_params.txt).
%   Rows are checked: known variant letters, no duplicates, CdA > 0,
%   numeric ClA and aero_front.

if nargin == 1 && (ischar(file) || isstring(file)) && strcmp(file, '--selftest')
    V = selftest();
    return
end
if nargin < 1 || isempty(file)
    file = fullfile(repo_root(), 'params', 'aero_variants.csv');
end
if ~isfile(file)
    V = table();
    return
end
opts = detectImportOptions(file, 'Delimiter', ',', 'TextType', 'string');
V = readtable(file, opts);
need = {'variant', 'ClA', 'CdA', 'aero_front'};
miss = setdiff(need, V.Properties.VariableNames);
if ~isempty(miss)
    error('read_aero_variants:columns', '%s: missing column(s) %s', file, strjoin(miss, ', '));
end
V.variant = upper(strtrim(string(V.variant)));
for c = {'ClA_lo', 'ClA_hi', 'CdA_lo', 'CdA_hi'}
    if ~ismember(c{1}, V.Properties.VariableNames), V.(c{1}) = nan(height(V), 1); end
end
for c = {'source', 'note'}
    if ~ismember(c{1}, V.Properties.VariableNames), V.(c{1}) = repmat("", height(V), 1); end
    V.(c{1}) = string(V.(c{1})); V.(c{1})(ismissing(V.(c{1}))) = "";
end
if ~isnumeric(V.ClA) || ~isnumeric(V.CdA) || ~isnumeric(V.aero_front)
    error('read_aero_variants:numeric', '%s: ClA, CdA and aero_front must be numbers', file);
end
bad = ~ismember(V.variant, ["A", "B", "C", "D", "CP", "CPF", "CPFF", "CPG"]);   % CPF, CPFF, CPG: CP with wing supports (CFD only, 2026-11-26 to 28)
if any(bad), error('read_aero_variants:variant', '%s: unknown variant %s', file, strjoin(V.variant(bad), ', ')); end
if numel(unique(V.variant)) < height(V), error('read_aero_variants:duplicate', '%s: a variant appears twice', file); end
if any(isnan(V.ClA) | isnan(V.CdA) | isnan(V.aero_front)) || any(V.CdA <= 0)
    error('read_aero_variants:values', '%s: ClA, CdA and aero_front must be filled in and CdA positive', file);
end
end

function ok = selftest()
% Hand check: a two-row file must come back as written, a missing file must
% give an empty table, a duplicate variant and a zero CdA must be refused.
%   C,4.5,1.5,0.42  and  A,-0.1,0.5,1.5  ->  V.ClA(V.variant == "C") = 4.5
tmp = [tempname '.csv'];
fid = fopen(tmp, 'w');
fprintf(fid, 'variant,ClA,CdA,aero_front,source,note\n');
fprintf(fid, 'c,4.5,1.5,0.42,CFD run 12,"mesh 0.9 M, 20 m/s"\n');
fprintf(fid, 'A,-0.1,0.5,1.5,ESTIMATE pre-CFD,\n');
fclose(fid);
V = read_aero_variants(tmp);
ok = height(V) == 2 && V.ClA(V.variant == "C") == 4.5 && V.CdA(V.variant == "C") == 1.5 && V.aero_front(V.variant == "C") == 0.42 ...
    && V.ClA(V.variant == "A") == -0.1 && V.source(V.variant == "C") == "CFD run 12" && all(isnan(V.ClA_lo));
ok = ok && isempty(read_aero_variants([tempname '.csv']));
fid = fopen(tmp, 'a'); fprintf(fid, 'C,4.0,1.4,0.45,x,\n'); fclose(fid);
ok = ok && refuses(tmp, 'read_aero_variants:duplicate');
fid = fopen(tmp, 'w'); fprintf(fid, 'variant,ClA,CdA,aero_front\nB,3,0,0.5\n'); fclose(fid);
ok = ok && refuses(tmp, 'read_aero_variants:values');
delete(tmp);
% the repo's own table, if present, must hold all four variants and CP
R = read_aero_variants();
ok = ok && (isempty(R) || all(ismember(["A", "B", "C", "D", "CP"], R.variant)));
if ok
    fprintf('read_aero_variants self-test: PASS (two-row file read back: C 4.5 / 1.5 / 0.42; missing file -> empty; duplicate and CdA 0 refused; repo table %d rows)\n', height(R));
else
    error('read_aero_variants self-test: FAIL');
end
end

function r = refuses(file, id)
r = false;
try
    read_aero_variants(file);
catch ME
    r = strcmp(ME.identifier, id);
end
end
