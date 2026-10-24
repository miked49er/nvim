-- Run with: nvim --headless -l tests/worktree_batch_remove_spec.lua
-- Real git repo + worktrees; only the prompt (vim.ui.select) is scripted.
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local batch = require("config.worktree_batch_remove")

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

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local n = 0

-- Fresh repo with worktrees: specs are {name, dirty?}. Returns main dir, wts.
local function scenario(specs)
  n = n + 1
  local main = tmp .. "/r" .. n
  vim.fn.mkdir(main, "p")
  sh(main, "init", "-b", "main")
  sh(main, "config", "user.email", "t@t")
  sh(main, "config", "user.name", "t")
  sh(main, "commit", "--allow-empty", "-m", "c1")
  local wts = {}
  for _, s in ipairs(specs) do
    local path = tmp .. "/w" .. n .. s[1]
    sh(main, "worktree", "add", "-b", s[1] .. n, path)
    if s[2] then vim.fn.writefile({ "x" }, path .. "/dirty.txt") end
    wts[#wts + 1] = { path = path }
  end
  vim.fn.chdir(main)
  return main, wts
end

-- script: successive vim.ui.select answers ("<cancel>" = dismiss). Records, at
-- each prompt, how many worktrees still exist.
local function run(wts, script)
  local prompts, existing_at_prompt, finished = {}, {}, false
  local i = 0
  local orig = vim.ui.select
  vim.ui.select = function(items, opts, cb)
    i = i + 1
    prompts[#prompts + 1] = { items = items, prompt = opts.prompt }
    local alive = 0
    for _, w in ipairs(wts) do
      if vim.uv.fs_stat(w.path) then alive = alive + 1 end
    end
    existing_at_prompt[#existing_at_prompt + 1] = alive
    local ans = script[i]
    if ans == "<cancel>" or ans == nil then return cb(nil, nil) end
    for idx, it in ipairs(items) do
      if it == ans then return cb(it, idx) end
    end
    error("no such choice: " .. tostring(ans))
  end
  batch.run(wts, {
    remove = function(wt, force, on_done)
      local args = { "git", "worktree", "remove" }
      if force then table.insert(args, "--force") end
      table.insert(args, wt.path)
      vim.system(args, { text = true }, function(r) vim.schedule(function() on_done(r) end) end)
    end,
    done = function() finished = true end,
  })
  vim.wait(10000, function() return finished end, 20)
  vim.ui.select = orig
  return prompts, existing_at_prompt, finished
end

local function exists(w) return vim.uv.fs_stat(w.path) ~= nil end

print("clean only: no prompts, all removed")
do
  local _, wts = scenario({ { "a" }, { "b" } })
  local prompts, _, fin = run(wts, {})
  check("finished", fin)
  check("no prompts", #prompts == 0)
  check("all removed", not exists(wts[1]) and not exists(wts[2]))
end

print("mixed + force all: nothing removed before prompt")
do
  local _, wts = scenario({ { "a" }, { "b", true }, { "c", true } })
  local prompts, alive = run(wts, { "Force remove all" })
  check("one prompt", #prompts == 1)
  check("all 3 still present at prompt", alive[1] == 3, tostring(alive[1]))
  check("all removed after", not exists(wts[1]) and not exists(wts[2]) and not exists(wts[3]))
end

print("cancel at first prompt removes nothing")
do
  local _, wts = scenario({ { "a" }, { "b", true } })
  local _, _, fin = run(wts, { "<cancel>" })
  check("finished", fin)
  check("nothing removed", exists(wts[1]) and exists(wts[2]))
end

print("skip: clean removed, dirty intact")
do
  local _, wts = scenario({ { "a" }, { "b", true } })
  run(wts, { "Skip" })
  check("clean removed", not exists(wts[1]))
  check("dirty kept", exists(wts[2]))
end

print("review one by one: decisions all collected before any removal")
do
  local _, wts = scenario({ { "a" }, { "b", true }, { "c", true } })
  local prompts, alive = run(wts, { "Review one by one", "Force remove", "Skip" })
  check("3 prompts", #prompts == 3, tostring(#prompts))
  check("all present at every prompt", alive[1] == 3 and alive[2] == 3 and alive[3] == 3, vim.inspect(alive))
  check("clean removed", not exists(wts[1]))
  check("forced removed", not exists(wts[2]))
  check("skipped kept", exists(wts[3]))
end

print("cancel during review removes nothing")
do
  local _, wts = scenario({ { "a" }, { "b", true }, { "c", true } })
  run(wts, { "Review one by one", "Force remove", "<cancel>" })
  check("nothing removed", exists(wts[1]) and exists(wts[2]) and exists(wts[3]))
end

print("changes_summary_async returns status + full relative path entries")
do
  local _, wts = scenario({ { "a" } })
  vim.fn.mkdir(wts[1].path .. "/sub", "p")
  vim.fn.writefile({ "x" }, wts[1].path .. "/sub/new.txt")
  vim.fn.writefile({ "x" }, wts[1].path .. "/top.txt")
  sh(wts[1].path, "add", "sub/new.txt")
  local got
  batch.changes_summary_async(wts[1], function(e) got = e end)
  vim.wait(5000, function() return got ~= nil end, 20)
  check("two entries", got and #got == 2, vim.inspect(got))
  check("added file with nested path",
    got and got[1].status == "A" and got[1].path == "sub/new.txt", vim.inspect(got))
  check("untracked top-level file", got and got[2].status == "??" and got[2].path == "top.txt", vim.inspect(got))
  local _, cw = scenario({ { "c2" } })
  local c
  batch.changes_summary_async(cw[1], function(e) c = e end)
  vim.wait(5000, function() return c ~= nil end, 20)
  check("clean is empty list", c and #c == 0, vim.inspect(c))
end

print("review one by one uses deps.review with entries instead of vim.ui.select")
do
  local _, wts = scenario({ { "b", true }, { "c", true } })
  local seen, finished = {}, false
  local answers = { "force", "skip" }
  local orig = vim.ui.select
  local selects = 0
  vim.ui.select = function(items, opts, cb)
    selects = selects + 1
    if selects == 1 then return cb("Review one by one", 2) end
    error("unexpected select")
  end
  batch.run(wts, {
    remove = function(wt, force, on_done)
      local args = { "git", "worktree", "remove" }
      if force then table.insert(args, "--force") end
      table.insert(args, wt.path)
      vim.system(args, { text = true }, function(r) vim.schedule(function() on_done(r) end) end)
    end,
    review = function(wt, entries, cb)
      seen[#seen + 1] = { wt = wt, entries = entries }
      cb(answers[#seen])
    end,
    done = function() finished = true end,
  })
  vim.wait(10000, function() return finished end, 20)
  vim.ui.select = orig
  check("finished", finished)
  check("review called per dirty worktree", #seen == 2)
  check("entries passed", seen[1] and seen[1].entries[1].status == "??" and seen[1].entries[1].path == "dirty.txt",
    vim.inspect(seen[1]))
  check("forced removed", not exists(wts[1]))
  check("skipped kept", exists(wts[2]))
end

print("locked dirty worktree is not offered force removal; failure is reported")
do
  local _, wts = scenario({ { "a" }, { "b", true } })
  sh(wts[2].path, "worktree", "lock", wts[2].path)
  local prompts, _, fin = run(wts, {})
  check("finished", fin)
  check("no prompt offered", #prompts == 0, vim.inspect(prompts))
  check("clean removed", not exists(wts[1]))
  check("locked kept", exists(wts[2]))
end

print("locked worktree failure is passed to on_failure")
do
  local _, wts = scenario({ { "b", true } })
  sh(wts[1].path, "worktree", "lock", wts[1].path)
  local fails, finished = {}, false
  batch.run(wts, {
    remove = function(wt, force, on_done)
      local args = { "git", "worktree", "remove" }
      if force then table.insert(args, "--force") end
      table.insert(args, wt.path)
      vim.system(args, { text = true }, function(r) vim.schedule(function() on_done(r) end) end)
    end,
    on_failure = function(_, r) fails[#fails + 1] = r.stderr end,
    done = function() finished = true end,
  })
  vim.wait(10000, function() return finished end, 20)
  check("one failure reported", #fails == 1 and fails[1]:find("locked", 1, true) ~= nil, vim.inspect(fails))
  check("still present", exists(wts[1]))
end

vim.fn.chdir(repo_root)
if #failures > 0 then
  print(#failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
os.exit(0)
