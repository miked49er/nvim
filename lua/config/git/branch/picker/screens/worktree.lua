-- Worktree screens: remove and prune orphan folders.
local c = require("config.git.branch.picker.context")
local actions = require("config.git.branch.picker.actions")

local M = {}

local confirm = c.confirm

local function dir_entry(item)
  local name = vim.fs.basename(item.path)
  return { display = name, ordinal = name }
end

function M.remove()
  return {
    kind = "choose_many",
    title = "Remove Worktree",
    items = vim.tbl_filter(function(wt)
      return not wt.is_main
    end, c.list_worktrees_ordered()),
    entry = dir_entry,
    on_select = function(selected, ctx)
      if #selected == 1 then
        return ctx.open(confirm("Remove worktree at " .. selected[1].path .. "?", function()
          actions.run_removal(selected)
        end))
      end
      local names = c.join(selected, function(wt) return vim.fs.basename(wt.path) end)
      ctx.open(confirm("Remove " .. #selected .. " worktrees: " .. names .. "?", function()
        actions.run_removal(selected)
      end))
    end,
  }
end

function M.prune()
  return {
    kind = "choose_many",
    title = "Prune Worktree Folders",
    hint = " (<Tab> to toggle)",
    items = c.list_orphan_worktree_folders(),
    preselect_all = true,
    entry = dir_entry,
    on_select = function(selected, ctx)
      local names = c.join(selected, function(o) return vim.fs.basename(o.path) end)
      ctx.open(confirm("Prune " .. #selected .. " worktree folder(s): " .. names .. "?", function()
        actions.run_removal(selected)
      end))
    end,
  }
end

return M
