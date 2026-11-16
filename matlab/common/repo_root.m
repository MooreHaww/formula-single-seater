function root = repo_root()
%REPO_ROOT Absolute path of the repository root (the folder holding params/).
%   root = repo_root() works from any MATLAB working folder because it is
%   derived from this file's own location: <root>/matlab/common/repo_root.m
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
