-- Owns the statusline's cached branch name, cheaply keyed by cwd (a file
-- read, unlike the worktree label's plain string match). invalidate() is
-- called by the git branch/worktree picker after any git command that might
-- have moved HEAD, so a switch/checkout made through the picker shows up
-- immediately instead of waiting on the DirChanged/FocusGained autocmd below
-- (which only catches branch changes made outside this nvim instance).
local worktree = require('config.worktree')

local M = {}

-- nf-oct-git_branch (U+F418) — distinct from worktree.ICON's repo_forked, so
-- the two glyphs don't read as the same concept in the statusline.
M.ICON = string.char(0xEF, 0x90, 0x98)

local cache = {}

function M.invalidate()
  cache = {}
end

function M.get(cwd)
  local name = cache[cwd]
  if name == nil then
    name = worktree.branch_for_cwd(cwd) or false
    cache[cwd] = name
  end
  return name or nil
end

vim.api.nvim_create_autocmd({ 'DirChanged', 'FocusGained' }, {
  desc = 'Invalidate cached statusline branch name',
  callback = M.invalidate,
})

return M
