-- Worktrees always live at <repo_root>/.claude/worktrees/<name> (see
-- lua/config/telescope/git_branch.lua), so a cheap path match avoids
-- spawning git on every statusline/tabline redraw.
local M = {}

function M.label_for_cwd(cwd)
  return cwd:match('%.claude[\\/]worktrees[\\/]([^\\/]+)')
end

return M
