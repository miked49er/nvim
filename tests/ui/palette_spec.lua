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

if #failures > 0 then
  print(#failures .. " failure(s)")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
