-- Shared "an async git worktree/branch action is running" flag, read by
-- mini.lua's statusline and set by config/telescope/git_branch.lua. A
-- separate module (rather than living in either of those) so the
-- statusline doesn't have to require the picker module just for this.
local M = {}

local label = nil

function M.start(text)
  label = text
  vim.cmd("redrawstatus")
end

function M.stop()
  label = nil
  vim.cmd("redrawstatus")
end

function M.label()
  return label
end

return M
