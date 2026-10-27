-- Branch, worktree, stash, push and pull handlers: each runs an operation
-- from config.git.branch.ops (or worktree removal) and reports the outcome.
local ctx = require("config.git.branch.picker.context")
local git_base_sync = require("config.git.branch.base_sync")
local ops = require("config.git.branch.ops")
local repo = require("config.git.repo")
local batch_remove = require("config.git.worktree.remove")
local remove_adapter = require("config.git.worktree.remove_adapter.telescope")

local M = {}

local open_repo, report, report_conflicts, NOT_A_REPO = ctx.open_repo, ctx.report, ctx.report_conflicts, ctx.NOT_A_REPO

function M.open_worktree_tab(path)
  vim.cmd("tabnew")
  vim.cmd("tcd " .. vim.fn.fnameescape(path))
  vim.notify("Worktree: " .. path)
end

function M.switch_branch(name)
  local h = open_repo()
  report(h and ops.switch(h, name) or NOT_A_REPO, "git switch failed", "Switched to branch " .. name)
end

function M.checkout_remote_tracking(name, remote)
  local h = open_repo()
  report(h and ops.track_remote(h, name, remote) or NOT_A_REPO, "git switch failed", "Switched to branch " .. name)
end

function M.create_and_switch_branch(name, base)
  local h = open_repo()
  report(h and ops.create(h, name, base) or NOT_A_REPO, "git switch -c failed",
    "Created and switched to branch " .. name)
end

function M.create_worktree_new_branch(name, base)
  local h = open_repo()
  local path = ctx.worktree_path_for(name)
  if not (h and path) then
    vim.notify("Could not resolve repo root", vim.log.levels.ERROR)
    return
  end
  if report(ops.worktree_add_new(h, path, name, base), "git worktree add failed") then
    M.open_worktree_tab(path)
  end
end

function M.create_worktree_for_branch(entry)
  local h = open_repo()
  local path = ctx.worktree_path_for(entry.name)
  if not (h and path) then
    vim.notify("Could not resolve repo root", vim.log.levels.ERROR)
    return
  end
  if report(ops.worktree_add_existing(h, path, entry), "git worktree add failed") then
    M.open_worktree_tab(path)
  end
end

-- Reports a removal result: notifications live here, removal itself lives in
-- config.git.worktree.remove.
local function report_removal(res)
  for _, wt in ipairs(res.removed) do
    vim.notify("Removed " .. (wt.orphan and "worktree folder " or "worktree ") .. wt.path)
  end
  for _, f in ipairs(res.failed) do
    ctx.notify_err(f.wt.orphan and "Folder removal failed" or "git worktree remove failed", f.result)
  end
end

function M.run_removal(selection)
  batch_remove.run(selection, remove_adapter, report_removal)
end

-- Async: on_done(result) runs whether or not the delete succeeded; success
-- notification fires here since every caller wants it.
function M.delete_branch_async(entry, force, on_done)
  local h = open_repo()
  if not h then
    return vim.schedule(function()
      on_done(NOT_A_REPO)
    end)
  end
  ops.delete_async(h, entry.name, { force = force }, function(result)
    if result.ok then
      vim.notify("Deleted branch " .. entry.name)
    end
    on_done(result)
  end)
end

function M.rename_branch(old, new_name)
  local h = open_repo()
  report(h and ops.rename(h, old, new_name) or NOT_A_REPO, "git branch -m failed",
    "Renamed branch " .. old .. " to " .. new_name)
end

function M.merge_branch(entry)
  local h = open_repo()
  local result = h and ops.merge(h, entry) or NOT_A_REPO
  if result.ok then
    vim.notify("Merged " .. result.value .. " into " .. ctx.current_head())
  elseif not report_conflicts(result, "Merge") then
    report(result, "git merge failed")
  end
end

-- Shared by Pop/Apply: both can fail with merge-style conflicts, handled the
-- same way as merge.
local function handle_stash_result(result, action_label, success_msg)
  if result.ok then
    vim.notify(success_msg)
  elseif not report_conflicts(result, action_label) then
    report(result, action_label .. " failed")
  end
end

function M.stash_push_all(message)
  local h = open_repo()
  local result = h and ops.stash_push(h, { message = message }) or NOT_A_REPO
  if report(result, "git stash push failed") then
    vim.notify(result.value.saved and "Stashed changes" or "No local changes to stash")
  end
end

function M.stash_push_files(message, files)
  local h = open_repo()
  report(h and ops.stash_push(h, { message = message, files = files }) or NOT_A_REPO,
    "git stash push failed", "Stashed " .. #files .. " file(s)")
end

function M.stash_pop()
  local h = open_repo()
  handle_stash_result(h and ops.stash_pop(h) or NOT_A_REPO, "git stash pop", "Popped stash")
end

function M.stash_apply(ref)
  local h = open_repo()
  handle_stash_result(h and ops.stash_apply(h, ref) or NOT_A_REPO, "git stash apply", "Applied " .. ref)
end

function M.stash_drop(ref)
  local h = open_repo()
  report(h and ops.stash_drop(h, ref) or NOT_A_REPO, "git stash drop failed", "Dropped " .. ref)
end

function M.stash_drop_many(refs)
  local h = open_repo()
  if not h then
    return report(NOT_A_REPO, "git stash drop failed")
  end
  local failed = ops.stash_drop_many(h, refs).value.failed
  if #failed > 0 then
    vim.notify("Failed to drop: " .. table.concat(failed, ", "), vim.log.levels.WARN)
  end
end

function M.push()
  local h = open_repo()
  report(h and ops.push(h) or NOT_A_REPO, "git push failed", function(branch)
    return "Pushed " .. branch
  end)
end

function M.pull()
  local h = open_repo()
  report(h and ops.pull(h) or NOT_A_REPO, "git pull failed", function(branch)
    return "Pulled " .. branch
  end)
end

-- Async-updates the base from its remote (busy guard shown meanwhile), warns
-- if the branch may start behind the remote, then calls create(start_ref).
function M.create_from_fresh_base(base, create)
  local busy = repo.busy.start("updating " .. base)
  git_base_sync.prepare(base, function(start, warning)
    repo.busy.stop(busy)
    if warning then
      vim.notify(warning, vim.log.levels.WARN)
    end
    create(start)
  end)
end

return M
