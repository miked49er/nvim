-- Declarative menus. A screen is declared as data; opening a child screen
-- through ctx.open() records where "back" goes, so no action can forget
-- Esc-to-back. Rendering is delegated to an adapter (menu_adapter/telescope,
-- menu_adapter/scripted).
--
-- A declaration is a table (or a function returning one, re-evaluated on every
-- show so lists are fresh when you come back):
--   { kind = "menu", title, items = { {label, run = fn(ctx) | open = decl}, ... } }
--   { kind = "choose_one",  title, items, entry = fn(v) -> {display, ordinal, icon?, hl?},
--     default_text?, prefer = fn(v) -> bool (ranks matches first),
--     rank = fn(score, preferred) -> score (required with prefer; supplied by the caller),
--     on_select = fn(v, ctx), on_input = fn(text, ctx) (typed text matching nothing) }
--   { kind = "choose_many", title, items, entry?, hint?, preselect_all?,
--     on_select = fn(values, ctx) }                 -- empty selection is ignored
--   { kind = "text", title, default?, allow_empty?, on_submit = fn(text, ctx) }
--   { kind = "confirm", title, on_yes = fn(ctx) }   -- dead end: no back target
-- Items without `entry` use themselves (or item.label) as the display text.
--
-- Adapter: adapter.choose_one(req, done), .choose_many, .text, .confirm.
-- done(nil) means "back"; otherwise choose_one gets {value=} or {input=},
-- choose_many {values=}, text {text=}, confirm a boolean.
local M = {}

local MANY_HINT = " (<Tab> to select multiple)"

local function resolve(decl)
  if type(decl) == "function" then
    return decl()
  end
  return decl
end

local function entries_for(spec)
  local out = {}
  for _, item in ipairs(spec.items or {}) do
    local e
    if spec.entry then
      e = spec.entry(item)
    else
      local label = type(item) == "table" and item.label or item
      e = { display = label, ordinal = label }
    end
    e.value = item
    out[#out + 1] = e
  end
  return out
end

local function default_adapter()
  return require("config.ui.menu_adapter.telescope")
end

function M.open(decl, opts)
  local adapter = (opts and opts.adapter) or default_adapter()
  local stack = {}
  local show

  local function back()
    local parent = table.remove(stack)
    if parent then
      show(parent)
    end
  end

  -- `thunk` is the declaration as written (re-resolved if we come back to it).
  local function render(thunk, spec)
    local ctx = {
      open = function(child)
        local child_spec = resolve(child)
        if child_spec.kind ~= "confirm" then
          table.insert(stack, thunk)
        end
        render(child, child_spec)
      end,
    }
    local kind = spec.kind
    assert(not spec.prefer or spec.rank, "menu: `prefer` requires `rank` (title: " .. tostring(spec.title) .. ")")

    if kind == "menu" or kind == "choose_one" then
      adapter.choose_one({
        title = spec.title,
        entries = entries_for(spec),
        default_text = spec.default_text,
        prefer = spec.prefer,
        rank = spec.rank,
        accepts_input = spec.on_input ~= nil,
      }, function(out)
        if out == nil then
          return back()
        end
        if out.input ~= nil then
          return spec.on_input(out.input, ctx)
        end
        local v = out.value
        if kind == "menu" then
          if v.open then
            return ctx.open(v.open)
          end
          return v.run(ctx)
        end
        spec.on_select(v, ctx)
      end)
    elseif kind == "choose_many" then
      adapter.choose_many({
        title = spec.title,
        hint = spec.hint or MANY_HINT,
        entries = entries_for(spec),
        preselect_all = spec.preselect_all,
      }, function(out)
        if out == nil then
          return back()
        end
        if out.values and #out.values > 0 then
          spec.on_select(out.values, ctx)
        end
      end)
    elseif kind == "text" then
      adapter.text({ title = spec.title, default_text = spec.default or "" }, function(out)
        if out == nil then
          return back()
        end
        local text = vim.trim(out.text or "")
        if text ~= "" or spec.allow_empty then
          spec.on_submit(text, ctx)
        end
      end)
    elseif kind == "confirm" then
      adapter.confirm({ title = spec.title }, function(yes)
        if yes then
          spec.on_yes(ctx)
        end
      end)
    else
      error("unknown menu kind: " .. tostring(kind))
    end
  end

  show = function(thunk)
    render(thunk, resolve(thunk))
  end

  show(decl)
end

return M
