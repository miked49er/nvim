-- Run with: nvim --headless -l tests/ui/menu_spec.lua
-- Declarative menu engine driven by the scripted adapter (no Telescope).
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local menu = require("config.ui.menu")
local scripted = require("config.ui.menu_adapter.scripted")
local BACK = scripted.BACK

local failures = {}
local function check(name, ok, detail)
  print((ok and "  ok - " or "  FAIL - ") .. name .. ((not ok and detail) and (": " .. detail) or ""))
  if not ok then table.insert(failures, name) end
end

local function titles(ad)
  local t = {}
  for _, p in ipairs(ad.prompts) do t[#t + 1] = p.title end
  return table.concat(t, ">")
end

print("menu: select runs a plain callback")
do
  local ran = 0
  local ad = scripted.new({ "Go" })
  menu.open({ kind = "menu", title = "Root", items = {
    { label = "Go", run = function() ran = ran + 1 end },
    { label = "Other", run = function() ran = ran + 10 end },
  } }, { adapter = ad })
  check("ran once", ran == 1)
  check("one prompt", #ad.prompts == 1 and ad.prompts[1].kind == "choose_one")
end

print("menu: nested menus, back goes up exactly one level")
do
  local leaf = 0
  local sub = { kind = "menu", title = "Sub", items = { { label = "Leaf", run = function() leaf = leaf + 1 end } } }
  local root = { kind = "menu", title = "Root", items = { { label = "Sub", open = sub } } }
  local ad = scripted.new({ "Sub", BACK, "Sub", "Leaf" })
  menu.open(root, { adapter = ad })
  check("path", titles(ad) == "Root>Sub>Root>Sub", titles(ad))
  check("leaf ran", leaf == 1)
end

print("menu: back at the root closes without reopening")
do
  local ad = scripted.new({ BACK })
  menu.open({ kind = "menu", title = "Root", items = { { label = "x", run = function() end } } }, { adapter = ad })
  check("only root shown", #ad.prompts == 1)
end

print("menu: decl functions are re-evaluated on every show")
do
  local calls = 0
  local fresh = function()
    calls = calls + 1
    return { kind = "choose_one", title = "List", items = { "a", "b" }, on_select = function() end }
  end
  local root = { kind = "menu", title = "Root", items = { { label = "List", open = fresh } } }
  menu.open(root, { adapter = scripted.new({ "List", BACK, "List", "a" }) })
  check("evaluated per show", calls == 2, tostring(calls))
end

print("choose_one: selection and typed input")
do
  local picked, typed
  local decl = {
    kind = "choose_one", title = "Pick", items = { { name = "x" }, { name = "y" } },
    entry = function(v) return { display = v.name, ordinal = v.name } end,
    on_select = function(v) picked = v.name end,
    on_input = function(text) typed = text end,
  }
  menu.open(decl, { adapter = scripted.new({ "y" }) })
  check("selected value", picked == "y")
  menu.open(decl, { adapter = scripted.new({ { input = "zzz" } }) })
  check("typed input", typed == "zzz")
  local ad = scripted.new({ "y" })
  menu.open(decl, { adapter = ad })
  check("entries exposed to script", #ad.prompts[1].entries == 2 and ad.prompts[1].entries[1].display == "x")
end

print("choose_many: returns values; empty selection does nothing")
do
  local got
  local decl = { kind = "choose_many", title = "Many", items = { "a", "b", "c" }, on_select = function(vs) got = vs end }
  menu.open(decl, { adapter = scripted.new({ { pick = { "a", "c" } } }) })
  check("values", got and #got == 2 and got[1] == "a" and got[2] == "c")
  got = nil
  menu.open(decl, { adapter = scripted.new({ { pick = {} } }) })
  check("empty ignored", got == nil)
  local ad = scripted.new({ BACK })
  menu.open(decl, { adapter = ad })
  check("hint defaults", ad.prompts[1].hint == " (<Tab> to select multiple)")
end

print("text: trims, empty cancels unless allow_empty, back")
do
  local got
  local decl = { kind = "text", title = "T", default = "d", on_submit = function(t) got = t end }
  menu.open(decl, { adapter = scripted.new({ { text = "  hi  " } }) })
  check("trimmed", got == "hi")
  got = nil
  menu.open(decl, { adapter = scripted.new({ { text = "" } }) })
  check("empty cancels", got == nil)
  decl.allow_empty = true
  menu.open(decl, { adapter = scripted.new({ { text = "" } }) })
  check("allow_empty submits", got == "")
  local ad = scripted.new({ BACK })
  menu.open(decl, { adapter = ad })
  check("default exposed", ad.prompts[1].default_text == "d")
end

print("confirm: yes runs, no dismisses; never pushes back-target")
do
  local yes = 0
  local confirm = { kind = "confirm", title = "Sure?", on_yes = function() yes = yes + 1 end }
  menu.open(confirm, { adapter = scripted.new({ true }) })
  check("yes", yes == 1)
  menu.open(confirm, { adapter = scripted.new({ false }) })
  check("no", yes == 1)

  local list = { kind = "choose_one", title = "L", items = { "a" },
    on_select = function(_, ctx) ctx.open(confirm) end }
  local ad = scripted.new({ "a", false })
  menu.open(list, { adapter = ad })
  check("declined confirm does not reopen parent", titles(ad) == "L>Sure?", titles(ad))
end

print("ctx.open from a prompt: back returns to that prompt")
do
  local list = { kind = "choose_one", title = "L", items = { "a" },
    on_select = function(_, ctx)
      ctx.open({ kind = "text", title = "T", on_submit = function() end })
    end }
  local ad = scripted.new({ "a", BACK, "a", { text = "ok" } })
  menu.open(list, { adapter = ad })
  check("path", titles(ad) == "L>T>L>T", titles(ad))
end

print("menu: prefer without rank fails clearly")
do
  local ok, err = pcall(menu.open, { kind = "choose_one", title = "P", items = { "a" },
    prefer = function() return true end, on_select = function() end }, { adapter = scripted.new({ "a" }) })
  check("errors", not ok)
  check("message names prefer/rank", tostring(err):find("prefer", 1, true) and tostring(err):find("rank", 1, true))
end

if #failures > 0 then
  print(#failures .. " FAILED")
  os.exit(1)
end
print("all ok")
