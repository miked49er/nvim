-- Run with: nvim --clean --headless -l tests/persistent_terminal_spec.lua
-- Exercises the real persistent-terminal module against a real (headless)
-- Neovim instance, stubbing only the job-spawning boundary
-- (config.terminal.shell) and vim.fn.jobstop, per
-- docs/specs/0001-persistent-worktree-terminal.md's testing decisions.

local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local tmp = require("tests.support.tmp")

local failures = {}
local function check(name, ok, detail)
  if ok then
    print("  ok - " .. name)
  else
    print("  FAIL - " .. name .. (detail and (": " .. detail) or ""))
    table.insert(failures, name)
  end
end

-- Stub the job-spawning boundary: never spawn a real shell.
local next_job = 1
local open_calls = 0
package.loaded["config.terminal.shell"] = {
  open = function()
    open_calls = open_calls + 1
    next_job = next_job + 1
    return next_job
  end,
}

-- Spy on vim.fn.jobstop instead of stubbing config.terminal.shell for it,
-- since the module calls vim.fn.jobstop directly (matches term.lua's own
-- convention of talking to jobstart/jobstop, not a wrapped stop function).
local jobstop_calls = {}
local real_jobstop = vim.fn.jobstop
vim.fn.jobstop = function(id)
  table.insert(jobstop_calls, id)
  return 1
end

local persistent = require("config.terminal.persistent")
local test = persistent._test

-- Isolate from this session's actual git branch: point the module at a
-- fabricated, non-git cwd so worktree_key falls back to cwd itself.
local fake_cwd = tmp.dir()
vim.cmd("tcd " .. vim.fn.fnameescape(fake_cwd))

local key = test.worktree_key(vim.fn.getcwd(-1, 0))
check("worktree_key falls back to cwd outside a git repo", key == vim.fs.normalize(fake_cwd), key)

-- 1. First toggle: no entry yet -> creates a split, spawns (stubbed) job.
persistent.toggle()
local entry = test.state[key]
check("first toggle creates a state entry", entry ~= nil)
check("first toggle opens exactly one job", open_calls == 1, tostring(open_calls))
check("first toggle's window is valid and visible", entry and vim.api.nvim_win_is_valid(entry.win))
check("first toggle defaults to the right side", entry and entry.side == "right", entry and entry.side)

local expected_width = math.floor(vim.o.columns * 0.3)
check(
  "default split width is ~30% of columns",
  entry and vim.api.nvim_win_get_width(entry.win) == expected_width,
  entry and tostring(vim.api.nvim_win_get_width(entry.win))
)

local first_buf = entry.buf
check("bufhidden is not wipe (survives hide)", vim.bo[first_buf].bufhidden ~= "wipe", vim.bo[first_buf].bufhidden)

-- 2. Second toggle (no direction): hides, keeps job alive, buffer intact.
persistent.toggle()
entry = test.state[key]
check("toggle-hide keeps the state entry", entry ~= nil)
check("toggle-hide clears the window handle", entry and entry.win == nil)
check("toggle-hide does not stop the job", #jobstop_calls == 0, tostring(#jobstop_calls))
check("toggle-hide keeps the buffer loaded", vim.api.nvim_buf_is_valid(first_buf))

-- 3. Third toggle: reopens the SAME buffer/job, does not spawn a new one.
persistent.toggle()
entry = test.state[key]
check("reopen reuses the original buffer", entry and entry.buf == first_buf)
check("reopen does not spawn a second job", open_calls == 1, tostring(open_calls))
check("reopen makes the window visible again", entry and vim.api.nvim_win_is_valid(entry.win))

-- 4. Directional toggle: moves to bottom, remembers the new side.
persistent.toggle("bottom")
entry = test.state[key]
check("directional toggle updates the remembered side", entry and entry.side == "bottom", entry and entry.side)
local expected_height = math.floor(vim.o.lines * 0.3)
check(
  "bottom mount sizes by ~30% of lines",
  entry and vim.api.nvim_win_get_height(entry.win) == expected_height,
  entry and tostring(vim.api.nvim_win_get_height(entry.win))
)

-- Reopening with no direction after moving should now default to "bottom".
persistent.toggle() -- hide
persistent.toggle() -- reopen, no explicit direction
entry = test.state[key]
check("plain toggle remembers last-used side across a hide/show cycle", entry and entry.side == "bottom")

-- 5. Manual close: closing the window directly (not via toggle) kills the
-- job and wipes the buffer/state entry.
vim.api.nvim_win_close(entry.win, true)
vim.wait(100, function()
  return not vim.api.nvim_buf_is_valid(first_buf)
end)
check("manual close stops the job", #jobstop_calls == 1, tostring(#jobstop_calls))
check("manual close removes the state entry", test.state[key] == nil)
check("manual close wipes the buffer", not vim.api.nvim_buf_is_valid(first_buf))

-- 6. A fresh open after a manual close spawns a brand new job/buffer.
persistent.toggle()
entry = test.state[key]
check("post-kill toggle spawns a fresh job", open_calls == 2, tostring(open_calls))
check("post-kill toggle gets a fresh buffer", entry and entry.buf ~= first_buf)

-- 7. VimLeavePre force-stops any still-live job (e.g. Alpha's plain :qa
-- must never hit E947 "job still running").
vim.api.nvim_exec_autocmds("VimLeavePre", {})
check("VimLeavePre force-stops the remaining live job", #jobstop_calls == 2, tostring(#jobstop_calls))

-- 8. Worktree-keyed identity (issue #5): the key is the worktree root, not
-- the branch, so branch switches reuse the terminal and same-branch
-- worktrees stay separate.
local function write_head(root, head)
  local f = assert(io.open(root .. "/.git/HEAD", "w"))
  f:write(head .. "\n")
  f:close()
end
local function make_worktree(name, head)
  local root = tmp.dir(name)
  vim.fn.mkdir(root .. "/.git", "p")
  write_head(root, head)
  return root
end

local wt_a = make_worktree("a", "ref: refs/heads/main")
local wt_b = make_worktree("b", "ref: refs/heads/main")
local key_a1 = test.worktree_key(wt_a)
check("same branch, different worktrees get different keys", key_a1 ~= test.worktree_key(wt_b))
write_head(wt_a, "ref: refs/heads/feature")
check("switching branches keeps the same key", test.worktree_key(wt_a) == key_a1)
write_head(wt_a, "0123456789abcdef0123456789abcdef01234567")
check("detached HEAD keeps the same key", test.worktree_key(wt_a) == key_a1)
vim.fn.mkdir(wt_a .. "/sub/dir", "p")
check("a subdirectory resolves to its worktree root key", test.worktree_key(wt_a .. "/sub/dir") == key_a1)
check("display name is the branch/SHA, not the key", test.display_name(key_a1) == "0123456", test.display_name(key_a1))

-- 9. Teardown on last-tab close.
local function new_tab_in(root)
  vim.cmd("tabnew")
  vim.cmd("tcd " .. vim.fn.fnameescape(root))
  return vim.api.nvim_get_current_tabpage()
end

jobstop_calls = {}
local killed = {}
test.hooks.kill_tree = function(job)
  table.insert(killed, job)
end

local tab1 = new_tab_in(wt_b)
local key_b = test.worktree_key(wt_b)
persistent.toggle()
local b_buf, b_job = test.state[key_b].buf, test.state[key_b].job
local tab2 = new_tab_in(wt_b)

vim.api.nvim_set_current_tabpage(tab2)
vim.cmd("tabclose")
vim.wait(100, function() return false end)
check("closing a tab while another for the worktree remains keeps the terminal", test.state[key_b] ~= nil and vim.api.nvim_buf_is_valid(b_buf))
check("...and does not kill any process", #killed == 0 and #jobstop_calls == 0)

vim.api.nvim_set_current_tabpage(tab1)
vim.cmd("tabclose")
vim.wait(200, function() return test.state[key_b] == nil end)
check("closing the last tab of a worktree removes its state", test.state[key_b] == nil)
check("...kills the process tree of its job", killed[1] == b_job, tostring(killed[1]))
check("...stops its job", jobstop_calls[1] == b_job, tostring(jobstop_calls[1]))
vim.wait(200, function() return not vim.api.nvim_buf_is_valid(b_buf) end)
check("...and wipes its buffer", not vim.api.nvim_buf_is_valid(b_buf))

-- Terminal visible in a tab that closes while a sibling tab remains: it is
-- hidden, not killed.
local tab3 = new_tab_in(wt_b)
persistent.toggle()
local e3buf = test.state[key_b].buf
local tab4 = new_tab_in(wt_b)
killed, jobstop_calls = {}, {}
vim.api.nvim_set_current_tabpage(tab3)
vim.cmd("tabclose")
vim.wait(100, function() return false end)
check("closing a tab showing the terminal while a sibling remains keeps it alive", test.state[key_b] ~= nil and vim.api.nvim_buf_is_valid(e3buf) and #killed == 0)
vim.api.nvim_set_current_tabpage(tab4)
vim.cmd("tabclose")
vim.wait(200, function() return test.state[key_b] == nil end)
check("...then closing the final tab tears it down", test.state[key_b] == nil and #killed == 1)

-- 10. Real process tree: the default kill_tree ends a long-running child.
local is_windows = vim.uv.os_uname().sysname == "Windows_NT"
local real_hooks_kill = test.real_kill_tree
local cmd = is_windows and { "cmd", "/c", "ping -n 1000 127.0.0.1 >nul" } or { "sh", "-c", "sleep 1000; true" }
vim.fn.jobstop = real_jobstop
local job = vim.fn.jobstart(cmd)
local pid = vim.fn.jobpid(job)
vim.wait(500, function() return false end)
real_hooks_kill(job)
vim.wait(1000, function() return vim.uv.kill(pid, 0) ~= 0 end)
check("real process tree is gone after kill_tree", vim.uv.kill(pid, 0) ~= 0)
pcall(vim.fn.jobstop, job)

print("")
if #failures > 0 then
  print(#failures .. " failure(s): " .. table.concat(failures, ", "))
  tmp.exit(1)
else
  print("all checks passed")
  tmp.exit(0)
end
