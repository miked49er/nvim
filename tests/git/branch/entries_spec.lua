-- Run with: nvim --headless -l tests/git/branch/entries_spec.lua
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local failures = {}
local function check(name, ok)
  print((ok and "  ok - " or "  FAIL - ") .. name)
  if not ok then table.insert(failures, name) end
end

local entries = require("config.git.branch.entries")
check("no telescope loaded", package.loaded["telescope"] == nil)

local list = {
  { name = "main", is_local = true },
  { name = "feat/x", is_local = true },
  { name = "origin/dev", is_local = false, remote = "origin" },
  { name = "dev", is_local = true },
}
local wts = { dev = "/r/.claude/worktrees/dev", ["feat/x"] = "/r/.claude/worktrees/foo" }

local names = vim.tbl_map(function(e) return e.name end, entries.order(list, wts))
check("worktree branches first, stable otherwise", vim.deep_equal(names, { "feat/x", "dev", "main", "origin/dev" }))
check("order keeps all when no worktrees", #entries.order(list, {}) == 4)

local plain = entries.describe(list[1], wts, "branch")
check("plain branch display", plain.display == "main" and plain.ordinal == "main" and not plain.worktree)

local remote = entries.describe(list[3], wts, "branch")
check("remote marker", remote.display == "origin/dev  [remote]" and remote.ordinal == "origin/dev")

local same = entries.describe(list[4], wts, "branch")
check("worktree with same name: not distinct", same.display == "dev" and same.ordinal == "dev" and same.worktree)

local diff = entries.describe(list[2], wts, "branch")
check("differing name shown as name:branch", diff.display == "foo:feat/x")
check("differing name searchable", diff.ordinal == "foo feat/x")

local wtmode = entries.describe(list[4], wts, "worktree")
check("worktree mode shows path", wtmode.display == "dev  (/r/.claude/worktrees/dev)")
check("worktree mode non-worktree has no path", entries.describe(list[1], wts, "worktree").display == "main")

check("preferred predicate", entries.prefers(wts)(list[2]) and not entries.prefers(wts)(list[1]))
check("rank boost for non-preferred", entries.rank(5, false) == 5 + 1e6)
check("rank keeps preferred", entries.rank(5, true) == 5)
check("rank keeps no-match", entries.rank(-1, false) == -1)

if #failures > 0 then
  print(#failures .. " failed")
  os.exit(1)
end
print("all passed")
