-- Telescope adapter for config.ui.menu. Picker-internal keys are named actions
-- (back, toggle_select, confirm, cancel, skip) applied here; M.keys is the table of
-- their bindings, defined in the central keymap table (config.keymaps.tables, `picker`).
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local themes = require("telescope.themes")

local M = {}

-- name -> { modes, lhs }, defined in config.keymaps.tables.picker. `confirm` is
-- Telescope's select_default (<CR>); `cancel` is only used by dialogs that
-- distinguish cancel from back.
M.keys = require("config.keymaps.tables").picker

-- Binds the named action's key(s) on a picker's `map`. `confirm` is applied
-- by replacing Telescope's select_default instead (callers do that directly).
function M.bind(map, name, fn)
  local k = M.keys[name]
  for _, lhs in ipairs(type(k[2]) == "table" and k[2] or { k[2] }) do
    map(k[1], lhs, fn)
  end
end

local bind = M.bind

local function entry_maker(e)
  local display = e.display
  if e.icon then
    local text = e.icon .. " " .. e.display
    display = function()
      return text, { { { 0, #text }, e.hl } }
    end
  end
  return { value = e, display = display, ordinal = e.ordinal }
end

-- Wraps the stock fuzzy sorter so preferred entries always outrank the rest,
-- at any fuzzy-match quality, as long as both still match the query. The inner
-- sorter may be stateful (telescope-fzf-native), so its lifecycle is forwarded.
-- `rank(score, preferred)` comes from the menu declaration (the caller owns
-- the ranking policy); `inner` defaults to the configured generic sorter.
function M.priority_sorter(prefer, rank, inner)
  inner = inner or conf.generic_sorter({})
  return require("telescope.sorters").new({
    discard = inner.discard,
    init = function() inner:_init() end,
    start = function(_, prompt) inner:_start(prompt) end,
    finish = function(_, prompt) inner:_finish(prompt) end,
    destroy = function() inner:_destroy() end,
    scoring_function = function(_, prompt, line, entry)
      local score = inner:scoring_function(prompt, line, entry)
      return rank(score, prefer(entry.value.value))
    end,
  })
end

local function open(opts, results, attach)
  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = opts.title,
        default_text = opts.default_text,
        finder = finders.new_table({ results = results, entry_maker = entry_maker }),
        sorter = opts.sorter or conf.generic_sorter({}),
        on_complete = opts.on_complete,
        attach_mappings = function(bufnr, map)
          attach(bufnr, map)
          bind(map, "back", function()
            actions.close(bufnr)
            opts.done(nil)
          end)
          return true
        end,
      })
      :find()
end

function M.choose_one(req, done)
  open({
    title = req.title,
    default_text = req.default_text,
    sorter = req.prefer and M.priority_sorter(req.prefer, req.rank) or nil,
    done = done,
  }, req.entries, function(bufnr)
    actions.select_default:replace(function()
      local selection = action_state.get_selected_entry()
      local prompt = vim.trim(action_state.get_current_line())
      actions.close(bufnr)
      if selection then
        done({ value = selection.value.value })
      elseif req.accepts_input then
        done({ input = prompt })
      end
    end)
  end)
end

-- <Tab> toggles; <CR> returns the toggled entries, or the highlighted one when
-- nothing was toggled.
function M.choose_many(req, done)
  open({
    title = req.title .. req.hint,
    done = done,
    on_complete = req.preselect_all and { function(picker) actions.select_all(picker.prompt_bufnr) end } or nil,
  }, req.entries, function(bufnr, map)
    bind(map, "toggle_select", actions.toggle_selection + actions.move_selection_worse)
    actions.select_default:replace(function()
      local multi = action_state.get_current_picker(bufnr):get_multi_selection()
      local values = {}
      if #multi > 0 then
        for _, e in ipairs(multi) do
          table.insert(values, e.value.value)
        end
      else
        local selection = action_state.get_selected_entry()
        if selection then
          table.insert(values, selection.value.value)
        end
      end
      actions.close(bufnr)
      done({ values = values })
    end)
  end)
end

-- Free text as a picker with an empty list: same look, Esc goes back.
function M.text(req, done)
  open({ title = req.title, default_text = req.default_text, done = done }, {}, function(bufnr)
    actions.select_default:replace(function()
      local input = action_state.get_current_line()
      actions.close(bufnr)
      done({ text = input })
    end)
  end)
end

-- Yes/No via vim.ui.select (telescope-ui-select backed). Esc/No just dismisses.
function M.confirm(req, done)
  vim.ui.select({ "Yes", "No" }, { prompt = req.title }, function(choice)
    done(choice == "Yes")
  end)
end

return M
