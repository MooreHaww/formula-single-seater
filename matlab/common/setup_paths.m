function setup_paths()
%SETUP_PATHS Add every project MATLAB folder to the path for this session.
root = repo_root();
folders = {'matlab', fullfile('matlab', 'common'), fullfile('matlab', 'lapsim'), ...
    fullfile('matlab', 'lapsim', 'tracks'), fullfile('matlab', 'simulink'), ...
    fullfile('matlab', 'cfd'), fullfile('matlab', 'cad')};
for k = 1:numel(folders)
    d = fullfile(root, folders{k});
    if isfolder(d), addpath(d); end
end
end
