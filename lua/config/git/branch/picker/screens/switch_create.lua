-- Switch/Create screen (branch and worktree modes) and its base-ref prompt.
-- Fuzzy search over all local+remote branches, worktree branches first;
-- typing a name that matches nothing creates it.
local ctx_mod = require("config.git.branch.picker.context")
local actions = require("config.git.branch.picker.actions")
local entries = require("config.git.branch.entries")
local palette = require("config.ui.palette")

local M = {}

local WORKTREE_ICON = palette.ICON

local branch_entry = entries.branch

-- Resolves to a ref string: selecting an entry uses its name, typing text uses
-- that text verbatim, and accepting empty input falls back to HEAD. It never
-- creates a branch.
local function base_ref_prompt(callback)
  return function()
    local head = ctx_mod.current_head()
    return {
      kind = "choose_one",
      title = "Base ref (empty = " .. head .. ")",
      default_text = head,
      items = ctx_mod.list_branches(),
      entry = branch_entry,
      on_select = function(entry)
        callback(entry.name)
      end,
      on_input = function(text)
        callback(text ~= "" and text or head)
      end,
    }
  end
end

local function handle_existing(mode, entry)
  if mode == "branch" then
    if entry.is_local then
      actions.switch_branch(entry.name)
    else
      actions.checkout_remote_tracking(entry.name, entry.remote)
    end
    return
  end

  local worktree_path = ctx_mod.list_worktrees()[entry.name]
  if worktree_path then
    actions.open_worktree_tab(worktree_path)
  else
    actions.create_worktree_for_branch(entry)
  end
end

local function handle_new(mode, name, ctx)
  name = name:gsub(" ", "-")
  ctx.open(base_ref_prompt(function(base)
    actions.create_from_fresh_base(base, function(start)
      if mode == "branch" then
        actions.create_and_switch_branch(name, start)
      else
        actions.create_worktree_new_branch(name, start)
      end
    end)
  end))
end

-- mode is "branch" or "worktree".
function M.screen(mode)
  return function()
    local worktree_map = ctx_mod.list_worktrees()
    return {
      kind = "choose_one",
      title = mode == "branch" and "Switch/Create Branch" or "Switch/Create Worktree",
      items = entries.order(ctx_mod.list_branches(), worktree_map),
      prefer = entries.prefers(worktree_map),
      rank = entries.rank,
      entry = function(entry)
        local made = entries.describe(entry, worktree_map, mode)
        if made.worktree then
          made.icon = WORKTREE_ICON
          made.hl = ctx_mod.WORKTREE_HL
        end
        return made
      end,
      on_select = function(entry)
        handle_existing(mode, entry)
      end,
      on_input = function(text, ctx)
        if text ~= "" then
          handle_new(mode, text, ctx)
        end
      end,
    }
  end
end

return M
