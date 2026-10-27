-- Stash screens: push (all / selected files), apply, drop.
local c = require("config.git.branch.picker.context")
local actions = require("config.git.branch.picker.actions")

local M = {}

local function stash_entry(entry)
  return { display = entry.raw, ordinal = entry.raw }
end

local function file_entry(entry)
  return { display = entry.status .. "  " .. entry.path, ordinal = entry.path }
end

local function stash_message_prompt(on_submit)
  return {
    kind = "text",
    title = "Stash message (optional)",
    default = "",
    allow_empty = true,
    on_submit = on_submit,
  }
end

function M.push_all()
  return stash_message_prompt(function(message)
    actions.stash_push_all(message)
  end)
end

function M.push_selected()
  return {
    kind = "choose_many",
    title = "Stash Files",
    items = c.list_changed_files(),
    entry = file_entry,
    on_select = function(selected, ctx)
      ctx.open(stash_message_prompt(function(message)
        local files = {}
        for _, entry in ipairs(selected) do
          table.insert(files, entry.path)
        end
        actions.stash_push_files(message, files)
      end))
    end,
  }
end

function M.apply()
  return {
    kind = "choose_one",
    title = "Apply Stash",
    items = c.list_stashes(),
    entry = stash_entry,
    on_select = function(entry)
      actions.stash_apply(entry.ref)
    end,
  }
end

function M.drop()
  return {
    kind = "choose_many",
    title = "Drop Stash",
    items = c.list_stashes(),
    entry = stash_entry,
    on_select = function(selected, ctx)
      if #selected == 1 then
        local entry = selected[1]
        return ctx.open(c.confirm("Drop " .. entry.raw .. "?", function()
          actions.stash_drop(entry.ref)
        end))
      end

      local refs = {}
      for _, entry in ipairs(selected) do
        table.insert(refs, entry.ref)
      end
      ctx.open(c.confirm("Drop " .. #selected .. " stashes: " .. table.concat(refs, ", ") .. "?", function()
        actions.stash_drop_many(refs)
      end))
    end,
  }
end

return M
