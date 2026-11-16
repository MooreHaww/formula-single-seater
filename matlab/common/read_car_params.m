function p = read_car_params(file)
%READ_CAR_PARAMS Read params/car_params.txt (SolidWorks equation format).
%   p = read_car_params()          reads <repo>/params/car_params.txt
%   p = read_car_params(file)      reads the given file
%   read_car_params()              with no output prints a table
%   read_car_params('--selftest')  runs the self-test
%
%   The file holds lines of the form
%       "name"= value            ' optional comment
%       "name"= "other" * 2 + 5  ' expressions may reference other names
%   Names become struct fields. Everything after an apostrophe outside the
%   quoted name is a comment. Expressions are evaluated in a safe loop until
%   every referenced name is known. Units are whatever the file says (mm,
%   deg, kg, N, m2); the reader does not convert anything.

if nargin == 1 && strcmp(file, '--selftest')
    p = selftest();
    return
end
if nargin < 1 || isempty(file)
    file = fullfile(repo_root(), 'params', 'car_params.txt');
end
if ~isfile(file)
    error('read_car_params:missing', 'Parameter file not found: %s', file);
end

lines = splitlines(string(fileread(file)));
raw = struct();   % name -> expression text (as written)
order = strings(0, 1);
for k = 1:numel(lines)
    L = strtrim(lines(k));
    if L == "" || startsWith(L, "'")
        continue
    end
    tok = regexp(L, '^"([^"]+)"\s*=\s*(.*)$', 'tokens', 'once');
    if isempty(tok)
        warning('read_car_params:skip', 'Line %d not understood, skipped: %s', k, L);
        continue
    end
    name = char(tok{1});
    expr = char(tok{2});
    % strip trailing comment (apostrophe outside double quotes)
    inq = false;
    for c = 1:numel(expr)
        if expr(c) == '"'
            inq = ~inq;
        elseif expr(c) == '''' && ~inq
            expr = expr(1:c-1);
            break
        end
    end
    expr = strtrim(expr);
    % strip unit suffixes SolidWorks accepts, e.g. 1550mm, 12deg, 0.5in (only mm/deg kept as numbers)
    expr = regexprep(expr, '(?<=\d)\s*(mm|deg)(?![A-Za-z_])', '');
    fname = matlab.lang.makeValidName(name);
    raw.(fname) = expr;
    order(end+1, 1) = string(fname); %#ok<AGROW>
end

% Evaluate, resolving references "other_name" iteratively
p = struct();
pending = order;
for pass = 1:50
    stillPending = strings(0, 1);
    for k = 1:numel(pending)
        f = pending(k);
        expr = raw.(f);
        refs = regexp(expr, '"([^"]+)"', 'tokens');
        ok = true;
        for r = 1:numel(refs)
            rf = matlab.lang.makeValidName(refs{r}{1});
            if isfield(p, rf)
                expr = strrep(expr, ['"' refs{r}{1} '"'], sprintf('(%.17g)', p.(rf)));
            else
                ok = false;
            end
        end
        if ~ok
            stillPending(end+1, 1) = f; %#ok<AGROW>
            continue
        end
        % Only digits, operators, parentheses, dots, e-notation and sqrt/abs allowed
        if isempty(regexp(expr, '^[\d\s\.\+\-\*\/\^\(\)eE]+$', 'once')) ...
                && isempty(regexp(expr, '^[\d\s\.\+\-\*\/\^\(\)eEsqrtabs,]+$', 'once'))
            error('read_car_params:badExpr', 'Cannot evaluate "%s"= %s', f, raw.(f));
        end
        p.(f) = eval(expr); %#ok<EVLDIR> expression is validated above
    end
    if isempty(stillPending)
        break
    end
    if numel(stillPending) == numel(pending)
        error('read_car_params:unresolved', 'Unresolved references in: %s', strjoin(stillPending, ', '));
    end
    pending = stillPending;
end

% Reorder fields as in the file
p = orderfields(p, cellstr(order));

if nargout == 0
    names = fieldnames(p);
    vals = cellfun(@(n) p.(n), names);
    T = table(string(names), vals, 'VariableNames', {'Parameter', 'Value'});
    fprintf('Parameters read from %s (%d entries)\n', file, height(T));
    disp(T);
    clear p
end
end

% ------------------------------------------------------------------------
function ok = selftest()
% Hand check: a three-line file with one expression must give
%   a = 1550, b = 1200, c = a - 50 = 1500, d = b/2 + c*2 = 600 + 3000 = 3600
tmp = [tempname '.txt'];
fid = fopen(tmp, 'w');
fprintf(fid, '%s\n', ...
    '''comment line', ...
    '"a"= 1550        '' wheelbase', ...
    '"b"= 1200mm', ...
    '"d"= "b" / 2 + "c" * 2   '' forward reference', ...
    '"c"= "a" - 50');
fclose(fid);
p = read_car_params(tmp);
delete(tmp);
expected = struct('a', 1550, 'b', 1200, 'c', 1500, 'd', 3600);
ok = isequal(fieldnames(p), {'a'; 'b'; 'd'; 'c'});
fn = fieldnames(expected);
for k = 1:numel(fn)
    ok = ok && abs(p.(fn{k}) - expected.(fn{k})) < 1e-9;
end
% And the real file must load with the key names present
q = read_car_params();
ok = ok && all(isfield(q, {'wheelbase', 'mass_car', 'ClA_C', 'motor_power_max'}));
if ok
    fprintf('read_car_params self-test: PASS (a=1550 b=1200 c=1500 d=3600; real file has %d parameters)\n', numel(fieldnames(q)));
else
    error('read_car_params self-test: FAIL');
end
end
