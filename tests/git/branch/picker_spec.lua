-- Run with: nvim --headless -l tests/git/branch/picker_spec.lua
-- Real picker flows (menus, prompts, git actions) against real temp repos,
-- driven by the scripted menu adapter. No Telescope.
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local tmp = require("tests.support.tmp")
local scripted = require("config.ui.menu_adapter.scripted")
local picker = require("config.git.branch.picker")
local BACK = scripted.BACK

local failures = {}
local function check(name, ok, detail)
  print((ok and "  ok - " or "  FAIL - ") .. name .. ((not ok and detail) and (": " .. detail) or ""))
  if not ok then table.insert(failures, name) end
end

local notes = {}
vim.notify = function(msg) table.insert(notes, msg) end
local function noted(pattern)
  for _, n in ipairs(notes) do if n:find(pattern, 1, true) then return true end end
  return false
end

local function sh(cwd, ...)
  local r = vim.system({ "git", ... }, { text = true, cwd = cwd }):wait()
  assert(r.code == 0, table.concat({ ... }, " ") .. ": " .. (r.stderr or ""))
  return vim.trim(r.stdout)
end

local tmp_root = tmp.dir()
local n = 0
local function scenario()
  n = n + 1
  local main = tmp_root .. "/r" .. n
  vim.fn.mkdir(main, "p")
  sh(main, "init", "-b", "main")
  sh(main, "config", "user.email", "t@t")
  sh(main, "config", "user.name", "t")
  vim.fn.writefile({ "one" }, main .. "/f.txt")
  sh(main, "add", ".")
  sh(main, "commit", "-m", "c1")
  vim.fn.chdir(main)
  notes = {}
  return main
end

local function drive(script)
  local ad = scripted.new(script)
  picker.set_adapter(ad)
  picker.open_menu()
  return ad
end

local function titles(ad)
  local t = {}
  for _, p in ipairs(ad.prompts) do t[#t + 1] = p.title end
  return table.concat(t, ">")
end

local function branches(main)
  return sh(main, "branch", "--format=%(refname:short)")
end

print("Esc goes back one level at every depth")
do
  scenario()
  local ad = drive({ "Branch", "Switch/Create", BACK, BACK, BACK })
  check("path", titles(ad) == "Git>Branch>Switch/Create Branch>Branch>Git", titles(ad))
end

print("branch: type a new name, base defaults to HEAD, creates and switches")
do
  local main = scenario()
  drive({ "Branch", "Switch/Create", { input = "feat x" }, { input = "" } })
  vim.wait(10000, function() return noted("Created and switched") end, 20)
  check("on new branch", sh(main, "rev-parse", "--abbrev-ref", "HEAD") == "feat-x")
end

print("branch: Esc from the base prompt returns to the switch picker")
do
  scenario()
  local ad = drive({ "Branch", "Switch/Create", { input = "nope" }, BACK, BACK })
  check("path", titles(ad):find("Switch/Create Branch>Base ref.-Switch/Create Branch>Branch") ~= nil, titles(ad))
end

print("branch: selecting an existing branch switches")
do
  local main = scenario()
  sh(main, "branch", "other")
  drive({ "Branch", "Switch/Create", "other" })
  check("switched", sh(main, "rev-parse", "--abbrev-ref", "HEAD") == "other")
end

print("branch: rename via picker then text prompt")
do
  local main = scenario()
  sh(main, "branch", "old")
  local ad = drive({ "Branch", "Rename", "old", BACK, "old", { text = "new name" } })
  check("back from text reopens list", titles(ad):find("New name for old>Rename Branch>New name for old") ~= nil, titles(ad))
  check("renamed", branches(main):find("new-name", 1, true) ~= nil and not branches(main):find("old", 1, true))
end

print("branch: delete asks for confirmation; declined keeps the branch")
do
  local main = scenario()
  sh(main, "branch", "gone")
  drive({ "Branch", "Delete", { pick = { "gone" } }, false })
  check("kept", branches(main):find("gone", 1, true) ~= nil)
  drive({ "Branch", "Delete", { pick = { "gone" } }, true })
  vim.wait(10000, function() return noted("Deleted branch gone") end, 20)
  check("deleted", not branches(main):find("gone", 1, true))
end

print("stash: push selected files with a message; back from message reopens files")
do
  local main = scenario()
  vim.fn.writefile({ "two" }, main .. "/f.txt")
  local file = function(e) return e.ordinal == "f.txt" end
  local ad = drive({ "Stash", "Push (Select Files)", { pick = file }, BACK, { pick = file }, { text = "wip" } })
  check("path", titles(ad):find("Stash Files>Stash message %(optional%)>Stash Files>Stash message") ~= nil, titles(ad))
  check("stash created", sh(main, "stash", "list"):find("wip", 1, true) ~= nil)
  check("tree clean", sh(main, "status", "--porcelain") == "")
end

print("stash: drop single stash after confirm")
do
  local main = scenario()
  vim.fn.writefile({ "two" }, main .. "/f.txt")
  sh(main, "stash", "push", "-m", "keep")
  local ad = drive({ "Stash", "Drop", { pick = { function() return true end } }, true })
  check("confirm shown", ad.prompts[4] and ad.prompts[4].kind == "confirm")
  check("dropped", sh(main, "stash", "list") == "")
end

print("worktree: create, then remove through the menu")
do
  local main = scenario()
  drive({ "Worktree", "Switch/Create", { input = "wt1" }, { input = "" } })
  vim.wait(10000, function() return noted("Worktree: ") end, 20)
  local path = main .. "/.claude/worktrees/wt1"
  check("worktree exists", vim.uv.fs_stat(path) ~= nil)
  vim.cmd("tabclose")
  vim.fn.chdir(main)
  local ad = drive({ "Worktree", "Remove", { pick = { "wt1" } }, true })
  vim.wait(10000, function() return noted("Removed worktree") end, 20)
  check("confirm title names path", ad.prompts[4] and ad.prompts[4].title:find("wt1", 1, true) ~= nil)
  check("worktree removed", vim.uv.fs_stat(path) == nil)
end

print("worktree: Prune with nothing orphaned notifies and shows no list")
do
  scenario()
  local ad = drive({ "Worktree", "Prune" })
  check("notified", noted("No orphaned worktree folders"))
  check("no list opened", #ad.prompts == 2)
end

if #failures > 0 then
  print(#failures .. " FAILED")
  tmp.exit(1)
end
print("all ok")
tmp.exit(0)
