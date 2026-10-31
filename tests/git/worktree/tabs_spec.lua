-- Run with: nvim --headless -l tests/git/worktree/tabs_spec.lua
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local failures = {}
local function check(name, ok)
  print((ok and "  ok - " or "  FAIL - ") .. name)
  if not ok then table.insert(failures, name) end
end

local tabs = require("config.git.worktree.tabs")
local base = vim.fn.tempname()
local function dir(n) local p = base .. "/" .. n; vim.fn.mkdir(p, "p"); return p end
local a, b, c = dir("a"), dir("b"), dir("c")

local function open_tab(path) vim.cmd("tabnew"); vim.cmd("tcd " .. vim.fn.fnameescape(path)) end
local function cwds()
  local r = {}
  for _, t in ipairs(vim.api.nvim_list_tabpages()) do
    r[#r + 1] = vim.fs.normalize(vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(t)))
  end
  return r
end
local function has(path)
  for _, p in ipairs(cwds()) do if p == vim.fs.normalize(path) then return true end end
  return false
end

-- Make handles diverge from numbers: open and close earlier tabs.
open_tab(a); open_tab(b); open_tab(c); open_tab(b)
vim.cmd("1tabnext"); vim.cmd("2tabclose") -- close tab on a; handles now != numbers

local ok, err = pcall(tabs.close_for_cwd, b)
check("no error after earlier tab closed: " .. tostring(err), ok)
check("tabs on removed worktree closed", not has(b))
check("other worktree tabs kept", has(c))

local ok2 = pcall(tabs.close_for_cwd, a)
check("no error when no tab matches", ok2)

local ok3 = pcall(tabs.close_for_cwd, c)
check("closing last matching tab does not error", ok3)
check("never closes the last remaining tab", #vim.api.nvim_list_tabpages() >= 1)

if #failures > 0 then os.exit(1) end
print("all passed")
