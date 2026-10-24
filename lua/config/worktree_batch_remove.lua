-- Batch worktree removal that decides first, removes second: every selected
-- worktree is checked for changes, every dirty-worktree decision is collected
-- (force all / review one by one / skip), and only then does any removal run.
-- Dismissing any prompt removes nothing.
local M = {}

-- e.g. names {"Podfile.lock", "a.txt", "b.txt", "c.txt"} -> "Podfile.lock, a.txt, b.txt +1 more"
local function summarize_names(names)
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
  return summarize_names(names)
end

-- Parse `git status --porcelain` output into { {status = "??", path = "dir/a.txt"}, ... }.
function M.parse_porcelain(stdout)
  local entries = {}
  for _, line in ipairs(vim.split(stdout or "", "\n", { trimempty = true })) do
    local path = line:sub(4):gsub("^.* %-> ", ""):gsub('^"(.*)"$', "%1")
    table.insert(entries, { status = vim.trim(line:sub(1, 2)), path = path })
  end
  return entries
end

-- Async: on_done(entries) gets the full list of changes, each {status, path}
-- (untracked files included, since they block a plain remove too). An empty
-- list means the worktree is clean.
function M.changes_summary_async(wt, on_done)
  vim.system(
    { "git", "-C", wt.path, "status", "--porcelain", "--untracked-files=all" },
    { text = true },
    function(result)
      vim.schedule(function()
        on_done(M.parse_porcelain(result.stdout))
      end)
    end
  )
end

local FORCE_ALL = "Force remove all"
local ONE_BY_ONE = "Review one by one"
local SKIP = "Skip"
local FORCE_ONE = "Force remove"

-- selected: { {path = ...}, ... }
-- deps.remove(wt, force, on_done(result)): performs one removal (required).
-- deps.done(): called when finished or cancelled (optional).
-- deps.on_failure(wt, result): called per failed removal (optional).
-- deps.review(wt, entries, cb): per-worktree review view (optional; falls
-- back to vim.ui.select). cb("force" | "skip" | nil for cancel).
function M.run(selected, deps)
  local function finish()
    if deps.done then
      deps.done()
    end
  end

  local infos = {}
  local pending = #selected
  if pending == 0 then
    return finish()
  end

  local function execute(plan)
    if #plan == 0 then
      return finish()
    end
    local remaining = #plan
    for _, item in ipairs(plan) do
      deps.remove(item.wt, item.force, function(result)
        if result.code ~= 0 and deps.on_failure then
          deps.on_failure(item.wt, result)
        end
        remaining = remaining - 1
        if remaining == 0 then
          finish()
        end
      end)
    end
  end

  local function decide()
    local clean, dirty = {}, {}
    for _, info in ipairs(infos) do
      table.insert(#info.entries == 0 and clean or dirty, info)
    end

    local plan = {}
    for _, info in ipairs(clean) do
      table.insert(plan, { wt = info.wt, force = false })
    end
    if #dirty == 0 then
      return execute(plan)
    end

    local labels = {}
    for _, info in ipairs(dirty) do
      table.insert(labels, vim.fs.basename(info.wt.path) .. " (" .. M.summarize_entries(info.entries) .. ")")
    end
    vim.ui.select({ FORCE_ALL, ONE_BY_ONE, SKIP }, {
      prompt = #dirty .. " worktrees have changes: " .. table.concat(labels, "; "),
    }, function(choice)
      if choice == FORCE_ALL then
        for _, info in ipairs(dirty) do
          table.insert(plan, { wt = info.wt, force = true })
        end
        execute(plan)
      elseif choice == SKIP then
        execute(plan)
      elseif choice == ONE_BY_ONE then
        local idx = 0
        local function next_one()
          idx = idx + 1
          local info = dirty[idx]
          if not info then
            return execute(plan)
          end
          local function answered(pick, force_value)
            if pick == nil then
              return finish() -- cancelled: nothing removed
            end
            if pick == force_value then
              table.insert(plan, { wt = info.wt, force = true })
            end
            next_one()
          end
          if deps.review then
            -- Rich view: cb("force" | "skip" | nil)
            deps.review(info.wt, info.entries, function(pick)
              answered(pick, "force")
            end)
          else
            vim.ui.select({ FORCE_ONE, SKIP }, {
              prompt = info.wt.path .. " has changes (" .. M.summarize_entries(info.entries) .. ")",
            }, function(pick)
              answered(pick, FORCE_ONE)
            end)
          end
        end
        next_one()
      else
        finish() -- dismissed: nothing removed
      end
    end)
  end

  for i, wt in ipairs(selected) do
    M.changes_summary_async(wt, function(entries)
      infos[i] = { wt = wt, entries = entries }
      pending = pending - 1
      if pending == 0 then
        decide()
      end
    end)
  end
end

return M
