-- Run with: nvim --headless -l tests/git/repo_spec.lua
-- Real temp git repos; no mocks.
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local tmp = require("tests.support.tmp")
local repo = require("config.git.repo")

local failures = {}
local function check(name, ok, detail)
  print((ok and "  ok - " or "  FAIL - ") .. name .. ((not ok and detail) and (": " .. detail) or ""))
  if not ok then table.insert(failures, name) end
end

local function sh(cwd, ...)
  local r = vim.system({ "git", ... }, { text = true, cwd = cwd }):wait()
  assert(r.code == 0, table.concat({ ... }, " ") .. ": " .. (r.stderr or ""))
  return vim.trim(r.stdout)
end
local function norm(p) return vim.fs.normalize(p):lower() end

local tmp_root = tmp.dir()
local main = tmp_root .. "/main"
vim.fn.mkdir(main, "p")
sh(main, "init", "-b", "main")
sh(main, "config", "user.email", "t@t")
sh(main, "config", "user.name", "t")
vim.fn.writefile({ "a" }, main .. "/a.txt")
sh(main, "add", "a.txt")
sh(main, "commit", "-m", "c1")
local wt_path = tmp_root .. "/wt"
sh(main, "worktree", "add", "-b", "feat/x", wt_path)

print("open: not a repo")
do
  local plain = tmp_root .. "/plain"
  vim.fn.mkdir(plain, "p")
  local h, err = repo.open(plain)
  check("returns nil + reason", h == nil and type(err) == "string", tostring(err))
  local got, called = "unset", false
  repo.open_async(plain, function(x) got, called = x, true end)
  vim.wait(5000, function() return called end, 20)
  check("open_async nil too", called and got == nil)
end

print("open: roots")
do
  local h = repo.open(main)
  check("root", h and norm(h.root) == norm(main), h and h.root)
  check("main_root", h and norm(h.main_root) == norm(main), h and h.main_root)
  local w = repo.open(wt_path)
  check("worktree root is itself", w and norm(w.root) == norm(wt_path), w and w.root)
  check("worktree main_root is main repo", w and norm(w.main_root) == norm(main), w and w.main_root)
  local sub = main .. "/sub"
  vim.fn.mkdir(sub, "p")
  local s = repo.open(sub)
  check("subdir resolves root", s and norm(s.root) == norm(main))
end

print("runners")
do
  local h = repo.open(main)
  local r = h:run({ "rev-parse", "--abbrev-ref", "HEAD" })
  check("sync run", r.code == 0 and vim.trim(r.stdout) == "main")
  check("lines", vim.deep_equal(h:lines({ "rev-parse", "--abbrev-ref", "HEAD" }), { "main" }))
  check("lines empty on failure", #h:lines({ "no-such-command" }) == 0)
  check("head", h:head() == "main")
  local got
  h:run_async({ "rev-parse", "--abbrev-ref", "HEAD" }, function(res) got = res end)
  vim.wait(5000, function() return got ~= nil end, 20)
  check("async run", got and got.code == 0 and vim.trim(got.stdout) == "main")
end

print("parse_status: renames and quoted paths")
do
  local e = repo.parse_status('?? new.txt\nR  old.txt -> renamed.txt\n M "sp ace.txt"\nR  "a b" -> "c d"\nA  sub/n.txt\n')
  check("5 entries", #e == 5, vim.inspect(e))
  check("untracked", e[1].status == "??" and e[1].path == "new.txt")
  check("rename keeps new path", e[2].status == "R" and e[2].path == "renamed.txt", vim.inspect(e[2]))
  check("quoted unquoted, status trimmed", e[3].status == "M" and e[3].path == "sp ace.txt", vim.inspect(e[3]))
  check("quoted rename", e[4].path == "c d", vim.inspect(e[4]))
  check("nested", e[5].path == "sub/n.txt")
  check("empty", #repo.parse_status("") == 0 and #repo.parse_status(nil) == 0)
end

print("status on real repo")
do
  local h = repo.open(main)
  check("clean", #h:status() == 0)
  sh(main, "mv", "a.txt", "b b.txt")
  vim.fn.writefile({ "x" }, main .. "/u.txt")
  local e = h:status()
  local by = {}
  for _, x in ipairs(e) do by[x.path] = x.status end
  check("rename", by["b b.txt"] == "R", vim.inspect(e))
  check("untracked", by["u.txt"] == "??", vim.inspect(e))
  local got
  h:status_async(function(x) got = x end)
  vim.wait(5000, function() return got ~= nil end, 20)
  check("status_async same", got and #got == #e)
  sh(main, "mv", "b b.txt", "a.txt")
  vim.fn.delete(main .. "/u.txt")
end

print("worktrees / branches / stashes")
do
  local h = repo.open(main)
  local wts = h:worktrees()
  check("two worktrees", #wts == 2, vim.inspect(wts))
  check("main first", wts[1].is_main and wts[1].branch == "main" and norm(wts[1].path) == norm(main), vim.inspect(wts[1]))
  check("linked", not wts[2].is_main and wts[2].branch == "feat/x" and norm(wts[2].path) == norm(wt_path), vim.inspect(wts[2]))

  sh(main, "branch", "other")
  local bare = tmp_root .. "/origin.git"
  sh(tmp_root, "init", "--bare", "-b", "main", "origin.git")
  sh(main, "remote", "add", "origin", bare)
  sh(main, "push", "origin", "main:main", "main:remoteonly")
  sh(main, "fetch", "origin")
  local bs = h:branches()
  local names = {}
  for _, b in ipairs(bs) do names[b.name] = b end
  check("locals", names.main and names.main.is_local and names.other and names["feat/x"])
  check("remote-only entry", names.remoteonly and not names.remoteonly.is_local and names.remoteonly.remote == "origin/remoteonly", vim.inspect(names.remoteonly))
  check("remote of local branch not duplicated", #vim.tbl_filter(function(b) return b.name == "main" end, bs) == 1)
  check("no HEAD pseudo-branch", names.HEAD == nil)

  check("no stashes", #h:stashes() == 0)
  vim.fn.writefile({ "changed" }, main .. "/a.txt")
  sh(main, "stash", "push", "-m", "first")
  vim.fn.writefile({ "changed2" }, main .. "/a.txt")
  sh(main, "stash", "push", "-m", "second")
  local st = h:stashes()
  check("two stashes newest first", #st == 2 and st[1].ref == "stash@{0}" and st[1].raw:find("second", 1, true) and st[2].ref == "stash@{1}", vim.inspect(st))
end

print("is_locked")
do
  local w = repo.open(wt_path)
  check("not locked", w:is_locked() == false)
  sh(main, "worktree", "lock", wt_path)
  check("locked", w:is_locked() == true)
  sh(main, "worktree", "unlock", wt_path)
end

print("branch lookup without git")
do
  check("main", repo.branch_for_dir(main) == "main")
  check("linked worktree", repo.branch_for_dir(wt_path) == "feat/x")
  check("non-repo nil", repo.branch_for_dir(tmp_root .. "/plain") == nil)
end

print("branch cache invalidated by repo runners")
do
  local h = repo.open(main)
  check("cached initial", repo.cached_branch(main) == "main")
  h:run({ "switch", "-c", "newb" })
  check("sync run invalidates", repo.cached_branch(main) == "newb", tostring(repo.cached_branch(main)))
  local done
  h:run_async({ "switch", "main" }, function() done = true end)
  vim.wait(5000, function() return done end, 20)
  check("async run invalidates", repo.cached_branch(main) == "main", tostring(repo.cached_branch(main)))
  check("non-repo cached nil", repo.cached_branch(tmp_root .. "/plain") == nil)
  sh(main, "switch", "-c", "outside")
  vim.api.nvim_exec_autocmds("FocusGained", {})
  check("FocusGained invalidates", repo.cached_branch(main) == "outside")
  sh(main, "switch", "main")
  vim.api.nvim_exec_autocmds("DirChanged", {})
  check("DirChanged invalidates", repo.cached_branch(main) == "main")
end

print("busy counter")
do
  local busy = repo.busy
  check("idle", busy.label() == nil)
  local a = busy.start("removing")
  local b = busy.start("removing")
  busy.stop(a)
  check("overlap keeps label", busy.label() == "removing")
  busy.stop(b)
  check("cleared after all finish", busy.label() == nil)
  local x = busy.start("one")
  local y = busy.start("two")
  check("latest label shown", busy.label() == "two")
  busy.stop(y)
  check("falls back to earlier", busy.label() == "one")
  busy.stop(x)
  busy.stop(x)
  check("double stop harmless", busy.label() == nil)
end

vim.fn.chdir(repo_root)
if #failures > 0 then
  print(#failures .. " failure(s)")
  tmp.exit(1)
end
print("all passed")
tmp.exit(0)
