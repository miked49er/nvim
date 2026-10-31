-- Run with: nvim --headless -l tests/git/worktree/identity_spec.lua
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local failures = {}
local function check(name, ok)
  print((ok and "  ok - " or "  FAIL - ") .. name)
  if not ok then table.insert(failures, name) end
end

local id = require("config.git.worktree.identity")

check("name -> path", id.path_for("/r/main", "feat/x") == "/r/main/.claude/worktrees/feat+x")
check("plain name -> path", id.path_for("/r/main", "dev") == "/r/main/.claude/worktrees/dev")
check("path -> name", id.name_for_path("/r/main/.claude/worktrees/feat+x") == "feat+x")
check("path -> name windows", id.name_for_path((("C:/r/.claude/worktrees/dev/sub"):gsub("/", string.char(92)))) == "dev")
check("path -> name nil outside layout", id.name_for_path("/r/main/src") == nil)
check("nested layout path -> outermost worktree", id.name_for_path("/a/.claude/worktrees/foo/.claude/worktrees/bar") == "foo")
check("layout segment inside a name is not matched", id.name_for_path("/a/x.claude/worktrees/foo") == nil)
check("roundtrip", id.name_for_path(id.path_for("/r", "a/b")) == id.sanitize("a/b"))
check("base dir", id.base_dir("/r/main") == "/r/main/.claude/worktrees")

check("differs: sanitized name vs branch", id.name_differs("/r/.claude/worktrees/feat+x", "feat/x") == "feat+x")
check("differs: arbitrary name", id.name_differs("/r/.claude/worktrees/foo", "bar") == "foo")
check("same name: nil", id.name_differs("/r/.claude/worktrees/dev", "dev") == nil)

check("label for layout dir", id.label_for_dir("/nonexistent/.claude/worktrees/foo") == "foo")
check("label falls back to dir", id.label_for_dir("/nonexistent/zzz") == "/nonexistent/zzz")
check("key is normalized, no trailing slash", id.key_for_dir("/nonexistent/zzz/") == "/nonexistent/zzz")
check("branch_for_dir exists", type(id.branch_for_dir) == "function")

if #failures > 0 then
  print(#failures .. " failure(s)")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
