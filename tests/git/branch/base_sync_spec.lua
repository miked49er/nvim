-- Run with: nvim --headless -l tests/git/branch/base_sync_spec.lua
-- Real git repos in a temp dir (bare "origin" + clones); no mocks.

local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local tmp = require("tests.support.tmp")
package.loaded["config.git.branch.cache"] = { invalidate = function() end }
local sync = require("config.git.branch.base_sync")

local failures = {}
local function check(name, ok, detail)
  if ok then
    print("  ok - " .. name)
  else
    print("  FAIL - " .. name .. (detail and (": " .. detail) or ""))
    table.insert(failures, name)
  end
end

local function sh(cwd, ...)
  local r = vim.system({ "git", ... }, { text = true, cwd = cwd }):wait()
  assert(r.code == 0, table.concat({ ... }, " ") .. ": " .. (r.stderr or ""))
  return vim.trim(r.stdout)
end

local tmp_root = tmp.dir()
local n = 0
-- Returns clone dir, other (pusher) dir, scenario dir. origin has main with c1;
-- `me` clones it; then `other` pushes c2, so me's main is one commit behind.
local function scenario()
  n = n + 1
  local d = tmp_root .. "/s" .. n
  vim.fn.mkdir(d, "p")
  sh(d, "init", "--bare", "-b", "main", "origin.git")
  local function clone(name)
    sh(d, "clone", d .. "/origin.git", name)
    sh(d .. "/" .. name, "config", "user.email", "t@t")
    sh(d .. "/" .. name, "config", "user.name", "t")
    return d .. "/" .. name
  end
  local other = clone("other")
  sh(other, "checkout", "-B", "main")
  sh(other, "commit", "--allow-empty", "-m", "c1")
  sh(other, "push", "origin", "main")
  local me = clone("me")
  sh(other, "commit", "--allow-empty", "-m", "c2")
  sh(other, "push", "origin", "main")
  return me, other, d
end

local function run(cwd, base)
  vim.fn.chdir(cwd)
  local got
  sync.prepare(base, function(ref, warning)
    got = { ref = ref, warning = warning }
  end)
  vim.wait(10000, function() return got ~= nil end, 20)
  return got or {}
end

print("fast-forwards checked-out base")
do
  local me, other = scenario()
  local tip = sh(other, "rev-parse", "HEAD")
  local r = run(me, "main")
  check("local main fast-forwarded", sh(me, "rev-parse", "main") == tip)
  check("no warning", r.warning == nil)
  check("start ref resolves to remote tip", r.ref ~= nil and sh(me, "rev-parse", r.ref) == tip)
end

print("fast-forwards base that is not checked out")
do
  local me, other = scenario()
  sh(me, "checkout", "-b", "feature")
  local tip = sh(other, "rev-parse", "HEAD")
  local r = run(me, "main")
  check("local main fast-forwarded", sh(me, "rev-parse", "main") == tip)
  check("start ref at tip", r.ref ~= nil and sh(me, "rev-parse", r.ref) == tip and r.warning == nil)
end

print("base checked out in another worktree")
do
  local me, other, d = scenario()
  sh(me, "checkout", "-b", "feature")
  sh(me, "worktree", "add", d .. "/wt", "main")
  local tip = sh(other, "rev-parse", "HEAD")
  local r = run(me, "main")
  check("starts from origin/main", r.ref == "origin/main" and sh(me, "rev-parse", r.ref) == tip)
  check("no warning", r.warning == nil)
end

print("base that is already a remote ref is fetched")
do
  local me, other = scenario()
  local tip = sh(other, "rev-parse", "HEAD")
  local r = run(me, "origin/main")
  check("ref passes through", r.ref == "origin/main")
  check("remote-tracking ref updated by fetch", sh(me, "rev-parse", "origin/main") == tip)
  check("no warning", r.warning == nil)
end

print("diverged base")
do
  local me, other = scenario()
  sh(me, "commit", "--allow-empty", "-m", "local-only")
  local tip = sh(other, "rev-parse", "HEAD")
  local r = run(me, "main")
  check("starts from origin/main", r.ref == "origin/main" and sh(me, "rev-parse", r.ref) == tip)
end

print("fetch fails")
do
  local me = scenario()
  sh(me, "remote", "set-url", "origin", tmp_root .. "/nonexistent.git")
  local r = run(me, "main")
  check("falls back to local base", r.ref == "main")
  check("warns", type(r.warning) == "string" and r.warning:find("behind") ~= nil)
end

print("fast-forward and origin ref both fail")
do
  local me = scenario()
  sh(me, "branch", "orphanbase")
  local r = run(me, "orphanbase")
  check("falls back to local base", r.ref == "orphanbase")
  check("warns", type(r.warning) == "string" and r.warning:find("behind") ~= nil)
end

print("editor stays responsive during fetch")
do
  local me = scenario()
  vim.fn.chdir(me)
  local done = false
  sync.prepare("main", function() done = true end)
  check("prepare returns before completion", done == false)
  vim.wait(10000, function() return done end, 20)
end

vim.fn.chdir(repo_root)
tmp.cleanup()
if #failures > 0 then
  print(#failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
tmp.exit(0)
