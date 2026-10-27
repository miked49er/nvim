-- <M-b> git branch/worktree menu entry point (bound in config.keymaps). Holds
-- the menu adapter; menus, screens and actions live under picker/ and depend
-- downward only. Navigation (push and back) is handled by config.ui.menu.
local menu = require("config.ui.menu")
local menus = require("config.git.branch.picker.menus")
local actions = require("config.git.branch.picker.actions")
local ctx_mod = require("config.git.branch.picker.context")
local palette = require("config.ui.palette")

local M = {}

-- Overridable for headless specs (see config.ui.menu_adapter.scripted).
local adapter = nil

function M.set_adapter(a)
  adapter = a
end

local function open_menu(decl)
  menu.open(decl, { adapter = adapter })
end

function M.open_menu()
  open_menu(menus.root)
end

function M.switch_create_branch()
  open_menu(menus.switch_create("branch"))
end

function M.switch_create_worktree()
  open_menu(menus.switch_create("worktree"))
end

M.push = actions.push
M.pull = actions.pull

local function define_picker_worktree_highlight()
  vim.api.nvim_set_hl(0, ctx_mod.WORKTREE_HL, palette.HL)
end

M.setup = function()
  palette.define_now_and_on_colorscheme(
    "Re-derive git branch/worktree picker highlight for the new colorscheme",
    define_picker_worktree_highlight
  )
end

return M
