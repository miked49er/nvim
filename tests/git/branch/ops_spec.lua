-- Run with: nvim --headless -l tests/git/branch/ops_spec.lua
-- Real git repos in a temp dir; no mocks. Ops return results, never notify.

local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local tmp = require("tests.support.tmp")
local repo = require("config.git.repo")
local ops = require("config.git.branch.ops")

local failures = {}
local function check(name, ok, detail)
  if ok then
    print("  ok - " .. name)
  else
    print("  FAIL - " .. name .. (detail and (": " .. detail) or ""))
    table.insert(failures, name)
  end
end

local notified = {}
vim.notify = function(msg) table.insert(notified, msg) end

local function sh(cwd, ...)
  local r = vim.system({ "git", ... }, { text = true, cwd = cwd }):wait()
  assert(r.code == 0, table.concat({ ... }, " ") .. ": " .. (r.stderr or ""))
  return vim.trim(r.stdout)
end

local tmp_root = tmp.dir()
local n = 0
-- origin (bare) + a clone with one commit on main.
local function scenario()
  n = n + 1
  local d = tmp_root .. "/s" .. n
  vim.fn.mkdir(d, "p")
  sh(d, "init", "--bare", "-b", "main", "origin.git")
  sh(d, "clone", d .. "/origin.git", "me")
  local me = d .. "/me"
  sh(me, "config", "user.email", "t@t")
  sh(me, "config", "user.name", "t")
  sh(me, "checkout", "-B", "main")
  vim.fn.writefile({ "base" }, me .. "/f.txt")
  sh(me, "add", ".")
  sh(me, "commit", "-m", "c1")
  sh(me, "push", "-u", "origin", "main")
  return me, d
end

local function open(dir)
  return assert(repo.open(dir))
end

print("switch / create")
do
  local me = scenario()
  local h = open(me)
  local r = ops.create(h, "feat", "main")
  check("create ok", r.ok and r.value == "feat")
  check("on feat", sh(me, "rev-parse", "--abbrev-ref", "HEAD") == "feat")
  r = ops.switch(h, "main")
  check("switch ok", r.ok and sh(me, "rev-parse", "--abbrev-ref", "HEAD") == "main")
  r = ops.switch(h, "nope")
  check("switch failure carries err", r.ok == false and type(r.err) == "string" and r.err ~= "")
end

print("push upstream mismatch")
do
  local me = scenario()
  local h = open(me)
  -- branch created from origin/main tracks origin/main under another name
  sh(me, "switch", "-c", "feat", "--track", "origin/main")
  sh(me, "commit", "--allow-empty", "-m", "c2")
  local r = ops.push(h)
  check("push ok", r.ok, r.err)
  check("sets upstream to same-named branch", sh(me, "rev-parse", "--abbrev-ref", "@{u}") == "origin/feat")
  check("main on origin untouched", sh(me, "rev-parse", "origin/main") ~= sh(me, "rev-parse", "feat"))
  -- matching upstream: plain push
  sh(me, "commit", "--allow-empty", "-m", "c3")
  r = ops.push(h)
  check("push with matching upstream ok", r.ok and r.value == "feat")
end

print("merge")
do
  local me = scenario()
  local h = open(me)
  sh(me, "switch", "-c", "a")
  vim.fn.writefile({ "a" }, me .. "/f.txt")
  sh(me, "commit", "-am", "a")
  sh(me, "switch", "main")
  vim.fn.writefile({ "main" }, me .. "/f.txt")
  sh(me, "commit", "-am", "m")
  local r = ops.merge(h, { name = "a", is_local = true })
  check("conflicting merge fails", r.ok == false)
  check("conflict files listed", r.conflicts ~= nil and #r.conflicts == 1 and r.conflicts[1] == "f.txt")
  sh(me, "merge", "--abort")
  sh(me, "switch", "-c", "b", "main~1")
  sh(me, "commit", "--allow-empty", "-m", "b")
  sh(me, "switch", "main")
  sh(me, "reset", "--hard", "main")
  r = ops.merge(h, { name = "b", is_local = true })
  check("clean merge ok", r.ok and r.value == "b", r.err)
end

print("stash")
do
  local me = scenario()
  local h = open(me)
  vim.fn.writefile({ "x" }, me .. "/f.txt")
  local r = ops.stash_push(h, { message = "one" })
  check("stash push ok", r.ok and r.value.saved == true, r.err)
  r = ops.stash_push(h, {})
  check("nothing to stash reported", r.ok and r.value.saved == false)
  for i = 2, 3 do
    vim.fn.writefile({ "x" .. i }, me .. "/f.txt")
    ops.stash_push(h, { message = "s" .. i })
  end
  check("three stashes", #h:stashes() == 3)
  -- stash@{0}=s3, {1}=s2, {2}=one. Drop 0 and 2 given in ascending order.
  r = ops.stash_drop_many(h, { "stash@{0}", "stash@{2}" })
  check("drop many ok", r.ok and #r.value.dropped == 2 and #r.value.failed == 0, r.err)
  check("dropped highest index first", r.value.dropped[1] == "stash@{2}")
  local left = h:stashes()
  check("correct stash remains", #left == 1 and left[1].raw:find("s2", 1, true) ~= nil)
  r = ops.stash_drop(h, "stash@{0}")
  check("single drop ok", r.ok and r.value == "stash@{0}")
  r = ops.stash_pop(h)
  check("pop with none fails", r.ok == false)
end

print("stash push selected files")
do
  local me = scenario()
  local h = open(me)
  vim.fn.writefile({ "1" }, me .. "/a.txt")
  vim.fn.writefile({ "2" }, me .. "/b.txt")
  local r = ops.stash_push(h, { files = { "a.txt" } })
  check("ok", r.ok and r.value.saved, r.err)
  check("only selected file stashed", vim.uv.fs_stat(me .. "/a.txt") == nil and vim.uv.fs_stat(me .. "/b.txt") ~= nil)
end

print("stash apply conflict")
do
  local me = scenario()
  local h = open(me)
  vim.fn.writefile({ "stashed" }, me .. "/f.txt")
  ops.stash_push(h, {})
  vim.fn.writefile({ "other" }, me .. "/f.txt")
  sh(me, "commit", "-am", "other")
  local r = ops.stash_apply(h, "stash@{0}")
  check("conflict fails with files", r.ok == false and r.conflicts ~= nil and r.conflicts[1] == "f.txt")
end

print("delete (async) and pull")
do
  local me = scenario()
  local h = open(me)
  sh(me, "branch", "gone")
  local got
  ops.delete_async(h, "gone", { force = false }, function(r) got = r end)
  vim.wait(10000, function() return got ~= nil end, 20)
  check("delete ok", got and got.ok and got.value == "gone")
  local r = ops.pull(h)
  check("pull ok", r.ok and r.value == "main", r and r.err)
end

check("no notifications from ops", #notified == 0, table.concat(notified, "|"))

vim.fn.chdir(repo_root)
tmp.cleanup()
if #failures > 0 then
  print(#failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
tmp.exit(0)
