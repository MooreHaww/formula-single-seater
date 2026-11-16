function out = save_fig(fig, name, closeIt)
%SAVE_FIG Save a figure as <repo>/media/<name>.png and (by default) close it.
%   out = save_fig(fig, 'name')     returns the written path
%   save_fig(fig, 'name', false)    keeps the figure open
if nargin < 3, closeIt = true; end
mediaDir = fullfile(repo_root(), 'media');
if ~isfolder(mediaDir), mkdir(mediaDir); end
out = fullfile(mediaDir, [name '.png']);
set(fig, 'Color', 'w');
exportgraphics(fig, out, 'Resolution', 150);
if closeIt, close(fig); end
end
