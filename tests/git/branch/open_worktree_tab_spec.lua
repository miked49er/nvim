-- Run with: nvim --headless -l tests/git/branch/open_worktree_tab_spec.lua
-- Switching to an existing Worktree opens a tab, sets its cwd, and is silent.
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local tmp = require("tests.support.tmp")
local actions = require("config.git.branch.picker.actions")

local failures = {}
local function check(name, ok)
  print((ok and "  ok - " or "  FAIL - ") .. name)
  if not ok then table.insert(failures, name) end
end

local notes = {}
vim.notify = function(msg) table.insert(notes, msg) end

local wt = tmp.dir("wt")
local tabs_before = #vim.api.nvim_list_tabpages()
actions.open_worktree_tab(wt)

check("opens a new tab", #vim.api.nvim_list_tabpages() == tabs_before + 1)
check("tab-local cwd is the worktree",
  vim.fs.normalize(vim.fn.getcwd(0, 0)) == vim.fs.normalize(vim.uv.fs_realpath(wt)) or
  vim.fs.normalize(vim.fn.getcwd(0, 0)) == vim.fs.normalize(wt))
check("emits no notification: " .. vim.inspect(notes), #notes == 0)

if #failures > 0 then tmp.exit(1) end
print("all passed")
tmp.exit(0)
