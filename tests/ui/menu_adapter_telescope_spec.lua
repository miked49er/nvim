-- Run with: nvim --headless -l tests/ui/menu_adapter_telescope_spec.lua
-- The Telescope adapter ranks with the function the menu declaration injects,
-- and the ui area does not require anything from the git area.
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path
local lazy = vim.fn.stdpath("data") .. "/lazy/"
vim.opt.rtp:append(lazy .. "telescope.nvim")
vim.opt.rtp:append(lazy .. "plenary.nvim")

local failures = {}
local function check(name, ok)
  print((ok and "  ok - " or "  FAIL - ") .. name)
  if not ok then table.insert(failures, name) end
end

local adapter = require("config.ui.menu_adapter.telescope")
local inner = { scoring_function = function(_, _, _, _) return 5 end }
local calls = {}
local function rank(score, preferred)
  calls[#calls + 1] = { score, preferred }
  return preferred and 111 or 222
end
local sorter = adapter.priority_sorter(function(v) return v == "wt" end, rank, inner)
local score = function(v) return sorter:scoring_function("q", "line", { value = { value = v } }) end
check("preferred value ranked via injected fn", score("wt") == 111)
check("other value ranked via injected fn", score("other") == 222)
check("rank received inner score", calls[1][1] == 5 and calls[1][2] == true and calls[2][2] == false)

local menu = require("config.ui.menu")
local scripted = require("config.ui.menu_adapter.scripted")
local ad = scripted.new({ "a" })
local r = function() end
menu.open({ kind = "choose_one", title = "T", items = { "a" }, prefer = function() return true end,
  rank = r, on_select = function() end }, { adapter = ad })
check("menu passes rank to adapter request", ad.prompts[1].rank == r)

local leaked = false
for _, f in ipairs(vim.fn.globpath(repo_root .. "/lua/config/ui", "**/*.lua", false, true)) do
  for line in io.lines(f) do
    if line:match("require") and line:match("config%.git") then leaked = true end
  end
end
check("ui area requires nothing from git area", not leaked)

if #failures > 0 then
  print(#failures .. " failure(s)")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
