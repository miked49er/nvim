-- The one removal path for single, batch and orphan-folder removal. It decides
-- first, removes second: every selected worktree is checked for changes and
-- locks, every dirty-worktree decision is collected through the adapter
-- (force all / review one by one / skip), and only then does any removal run.
-- Dismissing any prompt removes nothing.
--
-- Selection items: {path = ...} for a registered worktree, or
-- {path = ..., orphan = true} for a leftover folder git no longer knows.
-- Adapter (injected; see worktree/remove_adapter/{telescope,scripted}.lua):
--   adapter.choose_policy(dirty, cb)       dirty = {{wt, entries}, ...};
--                                          cb(M.POLICY.* | nil for cancel)
--   adapter.confirm(wt, entries, opts, cb) opts.allow_skip; cb(M.RESULT.* | nil)
-- Result: {removed = {wt}, skipped = {wt}, failed = {{wt, result}},
--          cancelled = bool}
local repo = require("config.git.repo")

local M = {}

-- Values handed back by adapter.confirm. nil = cancel.
M.RESULT = { FORCE = "force", SKIP = "skip" }
-- Values handed back by adapter.choose_policy. nil = cancel.
M.POLICY = { FORCE_ALL = "force_all", REVIEW = "review", SKIP = "skip" }
-- Porcelain status code for an untracked file.
M.UNTRACKED = "??"

-- e.g. names {"Podfile.lock", "a.txt", "b.txt", "c.txt"} -> "Podfile.lock, a.txt, b.txt +1 more"
function M.summarize_names(names)
  local max = 3
  local summary = table.concat(vim.list_slice(names, 1, max), ", ")
  if #names > max then
    summary = summary .. " +" .. (#names - max) .. " more"
  end
  return summary
end

-- Short one-line form of entries, for the group prompt.
function M.summarize_entries(entries)
  local names = {}
  for _, e in ipairs(entries) do
    table.insert(names, vim.fs.basename(e.path))
  end
  return M.summarize_names(names)
end

-- Async: on_done(entries) gets the full list of changes, each {status, path}
-- (untracked files included, since they block a plain remove too). An empty
-- list means the worktree is clean.
function M.changes_summary_async(wt, on_done)
  repo.open_async(wt.path, function(handle)
    if not handle then
      return on_done({})
    end
    handle:status_async(on_done)
  end)
end

-- Async: on_done(true) when the worktree is locked (`<git-dir>/locked`
-- exists). A locked worktree is usually locked on purpose, so removal never
-- offers to force it.
function M.is_locked_async(wt, on_done)
  repo.open_async(wt.path, function(handle)
    on_done(handle ~= nil and handle:is_locked())
  end)
end

local function norm(p)
  return vim.fs.normalize(p)
end

-- Orphan folders: git status when the folder is its own checkout; otherwise
-- (admin entry already gone, or git resolves to an enclosing repo) there is no
-- git state saying it is safe to drop, so it counts as dirty and lists its
-- top-level files instead.
local function orphan_info_async(wt, on_done)
  repo.open_async(wt.path, function(handle)
    if handle and norm(handle.root) == norm(wt.path) then
      return handle:status_async(function(entries)
        on_done({ wt = wt, entries = entries, dirty = #entries > 0 })
      end)
    end
    local entries = {}
    local ok, iter = pcall(vim.fs.dir, wt.path)
    if ok then
      for name, kind in iter do
        if kind ~= "directory" then
          table.insert(entries, { status = M.UNTRACKED, path = name })
        end
      end
    end
    on_done({ wt = wt, entries = entries, dirty = true })
  end)
end

local function classify_async(wt, on_done)
  if wt.orphan then
    return orphan_info_async(wt, on_done)
  end
  M.changes_summary_async(wt, function(entries)
    M.is_locked_async(wt, function(locked)
      on_done({ wt = wt, entries = entries, locked = locked, dirty = #entries > 0 and not locked })
    end)
  end)
end

local function remove_one_async(wt, force, on_done)
  if wt.orphan then
    local ok = vim.fn.delete(wt.path, "rf") == 0
    return on_done({ code = ok and 0 or 1, stdout = "", stderr = ok and "" or ("Failed to remove " .. wt.path) })
  end
  repo.open_async(vim.fn.getcwd(), function(handle)
    if not handle then
      return on_done({ code = 128, stdout = "", stderr = "fatal: not a git repository" })
    end
    local args = { "worktree", "remove" }
    if force then
      table.insert(args, "--force")
    end
    table.insert(args, wt.path)
    handle:run_async(args, function(result)
      if result.code == 0 then
        -- Tab cleanup must never abort the rest of the batch.
        pcall(require("config.git.worktree.tabs").close_for_cwd, wt.path)
      end
      on_done(result)
    end)
  end)
end

-- selection: list of items (see header). on_done(result) always runs once.
-- A lone dirty (unlocked) item skips the policy prompt and goes straight to
-- the per-worktree confirm, without a skip option. Locked worktrees are never
-- offered force: a plain removal is attempted and its failure reported.
function M.run(selection, adapter, on_done)
  local result = { removed = {}, skipped = {}, failed = {}, cancelled = false }
  local function finish()
    on_done(result)
  end
  local function cancel()
    result.cancelled = true
    result.removed, result.skipped, result.failed = {}, {}, {}
    finish()
  end

  if #selection == 0 then
    return finish()
  end

  local infos = {}
  local pending = #selection

  local function execute(plan)
    if #plan == 0 then
      return finish()
    end
    local busy = repo.busy.start(#plan == 1 and "removing worktree" or ("removing " .. #plan .. " worktrees"))
    -- Removals run concurrently; finish once every one has reported back.
    local remaining = #plan
    for _, item in ipairs(plan) do
      remove_one_async(item.wt, item.force, function(r)
        if r.code == 0 then
          table.insert(result.removed, item.wt)
        else
          table.insert(result.failed, { wt = item.wt, result = r })
        end
        remaining = remaining - 1
        if remaining == 0 then
          repo.busy.stop(busy)
          finish()
        end
      end)
    end
  end

  local function decide()
    local plan, dirty = {}, {}
    for _, info in ipairs(infos) do
      if info.dirty then
        table.insert(dirty, info)
      else
        table.insert(plan, { wt = info.wt, force = false })
      end
    end
    if #dirty == 0 then
      return execute(plan)
    end

    local function review_each()
      local idx = 0
      local function next_one()
        idx = idx + 1
        local info = dirty[idx]
        if not info then
          return execute(plan)
        end
        adapter.confirm(info.wt, info.entries, { allow_skip = #selection > 1 }, function(pick)
          if pick == nil then
            return cancel()
          end
          if pick == M.RESULT.FORCE then
            table.insert(plan, { wt = info.wt, force = true })
          else
            table.insert(result.skipped, info.wt)
          end
          next_one()
        end)
      end
      next_one()
    end

    if #selection == 1 then
      return review_each()
    end

    adapter.choose_policy(dirty, function(choice)
      if choice == M.POLICY.FORCE_ALL then
        for _, info in ipairs(dirty) do
          table.insert(plan, { wt = info.wt, force = true })
        end
        execute(plan)
      elseif choice == M.POLICY.SKIP then
        for _, info in ipairs(dirty) do
          table.insert(result.skipped, info.wt)
        end
        execute(plan)
      elseif choice == M.POLICY.REVIEW then
        review_each()
      else
        cancel()
      end
    end)
  end

  for i, wt in ipairs(selection) do
    classify_async(wt, function(info)
      infos[i] = info
      pending = pending - 1
      if pending == 0 then
        decide()
      end
    end)
  end
end

return M
