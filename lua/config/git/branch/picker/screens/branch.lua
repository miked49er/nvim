-- Branch screens: delete, rename, merge.
local c = require("config.git.branch.picker.context")
local actions = require("config.git.branch.picker.actions")
local entries = require("config.git.branch.entries")
local repo = require("config.git.repo")

local M = {}

local branch_entry = entries.branch
local confirm = c.confirm

function M.delete()
  return {
    kind = "choose_many",
    title = "Delete Branch",
    items = c.list_local_branches(),
    entry = branch_entry,
    on_select = function(selected, ctx)
      -- Single selection keeps the interactive force-delete prompt. Batch
      -- delete skips per-item prompts and reports which ones need a manual
      -- force-delete, same as the worktree removal flow.
      if #selected == 1 then
        local entry = selected[1]
        return ctx.open(confirm("Delete branch " .. entry.name .. "?", function()
          local busy = repo.busy.start("deleting " .. entry.name)
          actions.delete_branch_async(entry, false, function(result)
            repo.busy.stop(busy)
            if result.ok then
              return
            end
            vim.notify("git branch -d failed: " .. result.err, vim.log.levels.ERROR)
            ctx.open(confirm(entry.name .. " is not fully merged. Force delete?", function()
              local force_busy = repo.busy.start("deleting " .. entry.name)
              actions.delete_branch_async(entry, true, function(force_result)
                repo.busy.stop(force_busy)
                if not force_result.ok then
                  vim.notify("git branch -D failed: " .. force_result.err, vim.log.levels.ERROR)
                end
              end)
            end))
          end)
        end))
      end

      local names = c.join(selected, function(e) return e.name end)
      ctx.open(confirm("Delete " .. #selected .. " branches: " .. names .. "?", function()
        local failed = {}
        local remaining = #selected
        local busy = repo.busy.start("deleting " .. #selected .. " branches")
        for _, entry in ipairs(selected) do
          actions.delete_branch_async(entry, false, function(result)
            if not result.ok then
              table.insert(failed, entry.name)
            end
            remaining = remaining - 1
            if remaining == 0 then
              repo.busy.stop(busy)
              if #failed > 0 then
                vim.notify(
                  "Not fully merged, delete individually to force: " .. table.concat(failed, ", "),
                  vim.log.levels.WARN
                )
              end
            end
          end)
        end
      end))
    end,
  }
end

function M.rename()
  return {
    kind = "choose_one",
    title = "Rename Branch",
    items = c.list_local_branches(),
    entry = branch_entry,
    on_select = function(entry, ctx)
      ctx.open({
        kind = "text",
        title = "New name for " .. entry.name,
        default = entry.name,
        on_submit = function(input)
          actions.rename_branch(entry.name, (input:gsub(" ", "-")))
        end,
      })
    end,
  }
end

function M.merge()
  return {
    kind = "choose_one",
    title = "Merge into " .. c.current_head(),
    items = c.list_branches(),
    entry = branch_entry,
    on_select = function(entry)
      actions.merge_branch(entry)
    end,
  }
end

return M
