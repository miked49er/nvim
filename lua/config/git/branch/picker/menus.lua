-- Menu declarations for the git menu tree. Pure data over screens and
-- actions; navigation is handled by config.ui.menu, never required here.
local c = require("config.git.branch.picker.context")
local actions = require("config.git.branch.picker.actions")
local branch = require("config.git.branch.picker.screens.branch")
local stash = require("config.git.branch.picker.screens.stash")
local switch_create = require("config.git.branch.picker.screens.switch_create")
local worktree = require("config.git.branch.picker.screens.worktree")

local M = {}

function M.branch()
  return {
    kind = "menu",
    title = "Branch",
    items = {
      { label = "Switch/Create", open = switch_create.screen("branch") },
      { label = "Delete", open = branch.delete },
      { label = "Rename", open = branch.rename },
      { label = "Merge", open = branch.merge },
    },
  }
end

function M.worktree()
  return {
    kind = "menu",
    title = "Worktree",
    items = {
      { label = "Switch/Create", open = switch_create.screen("worktree") },
      { label = "Remove", open = worktree.remove },
      {
        label = "Prune",
        run = function(ctx)
          if #c.list_orphan_worktree_folders() == 0 then
            vim.notify("No orphaned worktree folders")
            return
          end
          ctx.open(worktree.prune)
        end,
      },
    },
  }
end

function M.stash()
  return {
    kind = "menu",
    title = "Stash",
    items = {
      { label = "Push", open = stash.push_all },
      { label = "Push (Select Files)", open = stash.push_selected },
      { label = "Pop", run = actions.stash_pop },
      { label = "Apply", open = stash.apply },
      { label = "Drop", open = stash.drop },
    },
  }
end

function M.root()
  return {
    kind = "menu",
    title = "Git",
    items = {
      { label = "Branch", open = M.branch },
      { label = "Worktree", open = M.worktree },
      { label = "Stash", open = M.stash },
      { label = "Push", run = actions.push },
      { label = "Pull", run = actions.pull },
    },
  }
end

M.switch_create = switch_create.screen

return M
