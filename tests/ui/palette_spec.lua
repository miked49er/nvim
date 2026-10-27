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

-- Definitions keep resolving to the pre-refactor attributes
vim.g.terminal_color_1 = "#ffff00"
vim.g.terminal_color_4 = "#000080"
p.define_slot_groups("MiniStatusline", function(color)
  return { fg = p.fg_for_bg(color), bg = color, bold = true }
end)
local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end
local s1, s2 = hl("MiniStatuslineWorktree1"), hl("MiniStatuslineWorktree" .. 2)
check("statusline slot 1 (light bg) black fg", s1.bg == 0xffff00 and s1.fg == 0x000000 and s1.bold == true)
local s4 = hl("MiniStatuslineWorktree4")
check("statusline slot 4 (dark bg) white fg", s4.bg == 0x000080 and s4.fg == 0xffffff and s4.bold == true)
require("config.git.branch.picker").setup()
local w = hl("GitBranchWorktree")
check("picker worktree hl is DeepSkyBlue bold, fg only", w.fg == 0x00bfff and w.bold == true and w.bg == nil)

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
