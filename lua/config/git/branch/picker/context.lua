-- Leaf helpers shared by the branch picker's actions and screens: repo
-- access, list queries and result reporting. Requires no other picker module.
local identity = require("config.git.worktree.identity")
local repo = require("config.git.repo")

local M = {}

M.NOT_A_REPO = { ok = false, err = "fatal: not a git repository" }

-- A repo handle is opened per call for the current directory; nil outside a
-- repository.
function M.open_repo()
  return repo.open(vim.fn.getcwd())
end

function M.notify_err(prefix, result)
  vim.notify(prefix .. ": " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
end

function M.current_head()
  local h = M.open_repo()
  return h and h:head() or "HEAD"
end

-- Shared across all worktrees of this repo, unlike the checkout root which
-- is whichever worktree you happen to be sitting in.
function M.repo_root()
  local h = M.open_repo()
  return h and h.main_root or nil
end

function M.list_branches()
  local h = M.open_repo()
  return h and h:branches() or {}
end

-- Ordered list of {path, branch, is_main}; the first entry is always the
-- main worktree.
function M.list_worktrees_ordered()
  local h = M.open_repo()
  return h and h:worktrees() or {}
end

function M.list_worktrees()
  local map = {}
  for _, wt in ipairs(M.list_worktrees_ordered()) do
    if wt.branch then
      map[wt.branch] = wt.path
    end
  end
  return map
end

function M.list_local_branches()
  return vim.tbl_filter(function(entry)
    return entry.is_local
  end, M.list_branches())
end

function M.list_stashes()
  local h = M.open_repo()
  return h and h:stashes() or {}
end

-- git status --porcelain, tracked + untracked; for renames, keeps the new
-- path since that's what a pathspec needs to match.
function M.list_changed_files()
  local h = M.open_repo()
  return h and h:status() or {}
end

function M.worktree_path_for(branch)
  local root = M.repo_root()
  if not root then
    return nil
  end
  return identity.path_for(root, branch)
end

-- Folders under .claude/worktrees/ that `git worktree list` no longer knows
-- about: left behind when Remove Worktree's `git worktree remove` deleted
-- the worktree's admin entry but couldn't clear the folder itself (typically
-- a Windows file lock). {path = ...}, matching the removal selection shape.
function M.list_orphan_worktree_folders()
  local root = M.repo_root()
  if not root then
    return {}
  end
  local base = identity.base_dir(root)
  if vim.fn.isdirectory(base) == 0 then
    return {}
  end
  local active = {}
  for _, wt in ipairs(M.list_worktrees_ordered()) do
    active[vim.fs.normalize(wt.path)] = true
  end
  local orphans = {}
  for name, kind in vim.fs.dir(base) do
    if kind == "directory" then
      local path = vim.fs.joinpath(base, name)
      if not active[vim.fs.normalize(path)] then
        table.insert(orphans, { path = path, orphan = true })
      end
    end
  end
  return orphans
end

function M.join(list, name_of)
  local out = {}
  for _, item in ipairs(list) do
    table.insert(out, name_of(item))
  end
  return table.concat(out, ", ")
end

function M.confirm(title, on_yes)
  return { kind = "confirm", title = title, on_yes = on_yes }
end

-- Reports an ops result: notifies the error on failure, otherwise the success
-- message (a string, or a function of the result value). Returns true on success.
function M.report(result, fail_prefix, ok_msg)
  if not result.ok then
    vim.notify(fail_prefix .. ": " .. result.err, vim.log.levels.ERROR)
    return false
  end
  if ok_msg then
    vim.notify(type(ok_msg) == "function" and ok_msg(result.value) or ok_msg)
  end
  return true
end

-- Merge-style failures that left unmerged files fall back to the diff tool.
function M.report_conflicts(result, label)
  if result.conflicts then
    vim.notify(label .. " conflicts in " .. #result.conflicts .. " file(s); opening changes panel", vim.log.levels.WARN)
    require("diffbandit").commit_panel()
    return true
  end
  return false
end

return M
