-- Run with: nvim --headless -l tests/git/worktree/remove_spec.lua
-- Real git repo + worktrees; prompts are answered by the scripted adapter.
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local tmp = require("tests.support.tmp")
local remove = require("config.git.worktree.remove")
local scripted = require("config.git.worktree.remove_adapter.scripted")
local repo = require("config.git.repo")
local P, R = remove.POLICY, remove.RESULT

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

local tmp_root = tmp.dir()
local n = 0

-- Fresh repo with worktrees: specs are {name, dirty?}. Returns main dir, wts.
local function scenario(specs)
  n = n + 1
  local main = tmp_root .. "/r" .. n
  vim.fn.mkdir(main, "p")
  sh(main, "init", "-b", "main")
  sh(main, "config", "user.email", "t@t")
  sh(main, "config", "user.name", "t")
  sh(main, "commit", "--allow-empty", "-m", "c1")
  local wts = {}
  for _, s in ipairs(specs) do
    local path = tmp_root .. "/w" .. n .. s[1]
    sh(main, "worktree", "add", "-b", s[1] .. n, path)
    if s[2] then vim.fn.writefile({ "x" }, path .. "/dirty.txt") end
    wts[#wts + 1] = { path = path }
  end
  vim.fn.chdir(main)
  return main, wts
end

local function exists(w) return vim.uv.fs_stat(w.path) ~= nil end

local function count_alive(wts)
  local alive = 0
  for _, w in ipairs(wts) do if exists(w) then alive = alive + 1 end end
  return alive
end

-- Runs remove.run with a scripted adapter. Returns result, adapter, and the
-- number of surviving selected items seen at each prompt.
local function run(sel, script)
  script = script or {}
  local alive = {}
  script.on_prompt = function() alive[#alive + 1] = count_alive(sel) end
  local adapter = scripted.new(script)
  local res
  remove.run(sel, adapter, function(r) res = r end)
  vim.wait(10000, function() return res ~= nil end, 20)
  return res, adapter, alive
end

local function has(list, w)
  for _, x in ipairs(list) do
    if (x.wt or x) == w then return true end
  end
  return false
end

print("clean only: no prompts, all removed")
do
  local _, wts = scenario({ { "a" }, { "b" } })
  local res, ad = run(wts)
  check("finished", res ~= nil)
  check("no prompts", #ad.policies == 0 and #ad.confirms == 0)
  check("all removed", not exists(wts[1]) and not exists(wts[2]))
  check("result lists both removed", #res.removed == 2 and #res.failed == 0 and #res.skipped == 0)
  local label = repo.busy.label()
  check("busy cleared", label == nil or label == "", tostring(label))
end

print("mixed + force all: nothing removed before prompt")
do
  local _, wts = scenario({ { "a" }, { "b", true }, { "c", true } })
  local res, ad, alive = run(wts, { policy = P.FORCE_ALL })
  check("one prompt", #ad.policies == 1)
  check("policy sees only dirty", #ad.policies[1] == 2)
  check("all 3 still present at prompt", alive[1] == 3, tostring(alive[1]))
  check("all removed after", count_alive(wts) == 0)
  check("3 removed", #res.removed == 3)
end

print("cancel at policy prompt removes nothing")
do
  local _, wts = scenario({ { "a" }, { "b", true } })
  local res = run(wts, {})
  check("cancelled", res.cancelled)
  check("nothing removed", exists(wts[1]) and exists(wts[2]))
  check("empty lists", #res.removed == 0 and #res.skipped == 0)
end

print("skip: clean removed, dirty intact and reported skipped")
do
  local _, wts = scenario({ { "a" }, { "b", true } })
  local res = run(wts, { policy = P.SKIP })
  check("clean removed", not exists(wts[1]))
  check("dirty kept", exists(wts[2]))
  check("reported", has(res.removed, wts[1]) and has(res.skipped, wts[2]))
end

print("review one by one: decisions all collected before any removal")
do
  local _, wts = scenario({ { "a" }, { "b", true }, { "c", true } })
  local res, ad, alive = run(wts, { policy = P.REVIEW, confirms = { R.FORCE, R.SKIP } })
  check("1 policy + 2 confirms", #ad.policies == 1 and #ad.confirms == 2)
  check("all present at every prompt", alive[1] == 3 and alive[2] == 3 and alive[3] == 3, vim.inspect(alive))
  check("confirm gets entries",
    ad.confirms[1].entries[1].status == "??" and ad.confirms[1].entries[1].path == "dirty.txt")
  check("skip allowed in batch", ad.confirms[1].opts.allow_skip == true)
  check("clean removed", not exists(wts[1]))
  check("forced removed", not exists(wts[2]))
  check("skipped kept", exists(wts[3]))
  check("result", #res.removed == 2 and #res.skipped == 1 and has(res.skipped, wts[3]))
end

print("cancel during review removes nothing")
do
  local _, wts = scenario({ { "a" }, { "b", true }, { "c", true } })
  local res = run(wts, { policy = P.REVIEW, confirms = { R.FORCE } })
  check("cancelled", res.cancelled)
  check("nothing removed", count_alive(wts) == 3)
end

print("single dirty worktree: straight to confirm, no skip option")
do
  local _, wts = scenario({ { "b", true } })
  local res, ad = run(wts, { confirms = { R.FORCE } })
  check("no policy prompt", #ad.policies == 0)
  check("one confirm without skip", #ad.confirms == 1 and ad.confirms[1].opts.allow_skip == false)
  check("removed", not exists(wts[1]) and #res.removed == 1)
  local _, w2 = scenario({ { "d", true } })
  local r2 = run(w2, {})
  check("cancel keeps it", r2.cancelled and exists(w2[1]))
end

print("locked dirty worktree is not offered force; failure is reported")
do
  local _, wts = scenario({ { "a" }, { "b", true } })
  sh(wts[2].path, "worktree", "lock", wts[2].path)
  local res, ad = run(wts, {})
  check("no prompt offered", #ad.policies == 0 and #ad.confirms == 0)
  check("clean removed", not exists(wts[1]))
  check("locked kept", exists(wts[2]))
  check("failure reported", #res.failed == 1 and res.failed[1].wt == wts[2]
    and res.failed[1].result.stderr:find("locked", 1, true) ~= nil, vim.inspect(res.failed))
end

print("single locked worktree gets the same handling")
do
  local _, wts = scenario({ { "b", true } })
  sh(wts[1].path, "worktree", "lock", wts[1].path)
  local res, ad = run(wts, {})
  check("no prompts", #ad.confirms == 0)
  check("failed, still present", #res.failed == 1 and exists(wts[1]))
end

print("orphan folders go through the same flow")
do
  local main, wts = scenario({ { "a" } })
  local dirty = { path = main .. "/orph_dirty", orphan = true }
  vim.fn.mkdir(dirty.path, "p")
  vim.fn.writefile({ "x" }, dirty.path .. "/keep.txt")
  -- Not its own checkout, so there is no git state saying it is safe: dirty.
  local res, ad = run({ wts[1], dirty }, { policy = P.SKIP })
  check("dirty orphan prompts via policy", #ad.policies == 1)
  check("dirty orphan lists its files",
    ad.policies[1][1].entries[1] and ad.policies[1][1].entries[1].path == "keep.txt", vim.inspect(ad.policies))
  check("dirty orphan kept on skip", exists(dirty) and has(res.skipped, dirty))
  check("worktree removed", not exists(wts[1]))
  local res2 = run({ dirty }, { confirms = { R.FORCE } })
  check("force removes orphan folder", not exists(dirty) and has(res2.removed, dirty))
end

print("changes_summary_async returns status + full relative path entries")
do
  local _, wts = scenario({ { "a" } })
  vim.fn.mkdir(wts[1].path .. "/sub", "p")
  vim.fn.writefile({ "x" }, wts[1].path .. "/sub/new.txt")
  vim.fn.writefile({ "x" }, wts[1].path .. "/top.txt")
  sh(wts[1].path, "add", "sub/new.txt")
  local got
  remove.changes_summary_async(wts[1], function(e) got = e end)
  vim.wait(5000, function() return got ~= nil end, 20)
  check("two entries", got and #got == 2, vim.inspect(got))
  check("added file with nested path", got and got[1].status == "A" and got[1].path == "sub/new.txt", vim.inspect(got))
  check("untracked top-level file", got and got[2].status == "??" and got[2].path == "top.txt", vim.inspect(got))
end

vim.fn.chdir(repo_root)
if #failures > 0 then
  print(#failures .. " failure(s)")
  tmp.exit(1)
end
print("all passed")
tmp.exit(0)
