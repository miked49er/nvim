-- Run with: nvim --headless -l tests/ui/palette_spec.lua
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local failures = {}
local function check(name, ok)
  print((ok and "  ok - " or "  FAIL - ") .. name)
  if not ok then table.insert(failures, name) end
end

local p = require("config.ui.palette")
check("icon is glyph", p.ICON == string.char(0xEF, 0x90, 0x82))
check("lowest slot first", p.slot_for("a") == 1 and p.slot_for("b") == 2 and p.slot_for("a") == 1)
p.reconcile_open({ b = true })
check("freed slot reused", p.slot_for("c") == 1)
check("fg legible", p.fg_for_bg("#ffff00") == "black" and p.fg_for_bg("#000080") == "white")
check("color fallback", p.color_for_slot(1) == "#ffffff")

-- Shared highlight helpers
check("group_name", p.group_name("TabLine", 3) == "TabLineWorktree3")
p.define_slot_groups("SpecBase", function(color, slot) return { fg = color, bold = slot == 2 } end)
local g1 = vim.api.nvim_get_hl(0, { name = "SpecBaseWorktree1", link = false })
local g6 = vim.api.nvim_get_hl(0, { name = "SpecBaseWorktree" .. p.PALETTE_SIZE, link = false })
check("slot groups defined for every slot", g1.fg == 0xffffff and g6.fg == 0xffffff)
check("style fn receives slot", vim.api.nvim_get_hl(0, { name = "SpecBaseWorktree2", link = false }).bold == true and not g1.bold)
local runs = 0
p.define_now_and_on_colorscheme("spec", function() runs = runs + 1 end)
check("runs immediately", runs == 1)
vim.api.nvim_exec_autocmds("ColorScheme", {})
check("reruns on colorscheme", runs == 2)

-- Tabline re-reads its base highlight on every run
vim.o.termguicolors = true
local tabline = require("config.tabline")
tabline.setup()
vim.api.nvim_set_hl(0, "TabLine", { bg = 0x123456 })
vim.api.nvim_exec_autocmds("ColorScheme", {})
check("tabline slot inherits base bg", vim.api.nvim_get_hl(0, { name = "TabLineWorktree1", link = false }).bg == 0x123456)
check("tabline slot fg/bold", vim.api.nvim_get_hl(0, { name = "TabLineWorktree1", link = false }).bold == true)

if #failures > 0 then
  print(#failures .. " failure(s)")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
