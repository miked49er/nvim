-- Persistent, worktree-keyed terminal. Unlike <leader>st (always a fresh,
-- disposable split) this keeps one shell job alive per worktree (keyed by
-- worktree root, not branch) for the life of the session: hiding it via
-- toggle leaves the job running, manually closing the window ends it, and
-- closing the last tab of the worktree kills the job and its process tree. See docs/specs/0001-persistent-worktree-terminal.md.
local shell = require("config.terminal.shell")
local worktree = require("config.git.worktree.identity")
local worktree_tabs = require("config.git.worktree.tabs")

local M = {}

local DEFAULT_SIDE = "right"
local DEFAULT_FRAC = 0.3

-- worktree path -> { buf, win, job, side, frac, toggling }
local state = {}

local function normalize(path)
  return (vim.fs.normalize(path):gsub("/+$", ""))
end

-- The key identifies the worktree itself: its normalized root directory
-- (nearest ancestor holding `.git`, a dir for the main checkout or a file
-- for a linked worktree). It is independent of the checked-out branch, so
-- switching branches reuses the terminal and two worktrees on the same
-- branch (or detached HEAD) stay separate. Outside a git repo the cwd
-- itself is the key.
local function worktree_key(cwd)
  return normalize(vim.fs.root(cwd, ".git") or cwd)
end

-- Human-readable name for a key (winbar text and colour slot). branch_for_cwd
-- works for any git dir; label_for_cwd only recognizes this config's own
-- worktree layout; the key itself is the last resort.
local function display_name(key)
  return worktree.branch_for_cwd(key) or worktree.label_for_cwd(key) or key
end

local function current_key()
  return worktree_key(vim.fn.getcwd(-1, 0))
end

-- Overridable in tests.
local hooks = {}

-- Ends the job's whole process tree, so children (e.g. `sleep 1000`) do not
-- outlive the shell.
function hooks.kill_tree(job)
  local ok, pid = pcall(vim.fn.jobpid, job)
  if not ok or not pid or pid <= 0 then
    return
  end
  if vim.uv.os_uname().sysname == "Windows_NT" then
    vim.fn.system({ "taskkill", "/PID", tostring(pid), "/T", "/F" })
    return
  end
  local function descendants(parent, acc)
    local out = vim.fn.systemlist({ "pgrep", "-P", tostring(parent) })
    for _, child in ipairs(out) do
      local c = tonumber(child)
      if c then
        descendants(c, acc)
        table.insert(acc, c)
      end
    end
    return acc
  end
  for _, c in ipairs(descendants(pid, {})) do
    pcall(vim.uv.kill, c, "sigkill")
  end
end

local function teardown(key)
  local entry = state[key]
  if not entry then
    return
  end
  state[key] = nil
  pcall(hooks.kill_tree, entry.job)
  pcall(vim.fn.jobstop, entry.job)
  -- Deferred: nvim_buf_delete on a buffer that just lost its last window
  -- (still mid-close) aborts with E855.
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(entry.buf) then
      pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
    end
  end)
end

-- Tears down every terminal whose worktree no longer backs any tab.
local function reconcile_tabs()
  local open = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local cwd = worktree_tabs.tab_cwd(tab)
    if cwd then
      open[worktree_key(cwd)] = true
    end
  end
  for key in pairs(state) do
    if not open[key] then
      teardown(key)
    end
  end
end

local MOVE_CMD = { left = "H", right = "L", top = "K", bottom = "J" }

local function is_vertical(side)
  return side == "left" or side == "right"
end

local function size_window(win, side, frac)
  if is_vertical(side) then
    vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * frac))
  else
    vim.api.nvim_win_set_height(win, math.floor(vim.o.lines * frac))
  end
end

-- `fresh`: use vnew/new (a brand-new empty buffer) for spawning a
-- worktree's first terminal. Otherwise vsplit/split (shows whatever buffer
-- was current) is used for reopening, since the caller immediately
-- overwrites it via nvim_win_set_buf — cheaper than a throwaway buffer.
local function place_split(side, fresh)
  local vertical_cmd = fresh and "vnew" or "vsplit"
  local horizontal_cmd = fresh and "new" or "split"
  vim.cmd(is_vertical(side) and vertical_cmd or horizontal_cmd)
  local win = vim.api.nvim_get_current_win()
  vim.cmd.wincmd(MOVE_CMD[side])
  return win
end

-- Nerd Font terminal glyph (nf-fa-terminal, U+F120), colored to match this
-- worktree's tabline icon so the two stay visually linked.
local ICON = string.char(0xEF, 0x84, 0xA0)

local function set_winbar(win, key)
  local name = display_name(key)
  local slot = worktree.slot_for(worktree.label_for_cwd(key) or name)
  local hl = "PersistentTerminalWorktree" .. slot
  vim.api.nvim_set_hl(0, hl, { fg = worktree.color_for_slot(slot), bold = true })
  vim.api.nvim_set_option_value("winbar", "%#" .. hl .. "#" .. ICON .. " " .. name:gsub("%%", "%%%%") .. "%*", { win = win })
end

local function show(key, side)
  local entry = state[key]
  local frac = (entry and entry.frac) or DEFAULT_FRAC

  if not entry then
    local win = place_split(side, true)
    size_window(win, side, frac)

    local buf = vim.api.nvim_get_current_buf()
    local job = shell.open()
    if job <= 0 then
      vim.notify("Could not start terminal", vim.log.levels.ERROR)
      vim.api.nvim_win_close(win, true)
      return
    end

    -- Overrides the wipe set by config.terminal.term's global TermOpen
    -- autocmd (fired by shell.open()'s jobstart above): this terminal must
    -- survive a hidden window, only a manual close should end it.
    vim.bo[buf].bufhidden = ""

    entry = { buf = buf, win = win, job = job, side = side, frac = frac }
    state[key] = entry
  else
    local win = place_split(side, false)
    size_window(win, side, frac)
    vim.api.nvim_win_set_buf(win, entry.buf)
    entry.win = win
    entry.side = side
  end

  set_winbar(entry.win, key)
  vim.cmd.startinsert()
end

local function hide(entry)
  entry.toggling = true
  vim.api.nvim_win_hide(entry.win)
end

--- Toggles the current worktree's terminal. With no direction, shows/hides
--- at its last-used side/size (or the default). With a direction, moves
--- (and shows) the terminal on that side, remembering it for next time.
---@param direction? "left"|"right"|"top"|"bottom"
function M.toggle(direction)
  local key = current_key()
  local entry = state[key]
  local visible = entry and entry.win and vim.api.nvim_win_is_valid(entry.win)

  if not direction then
    if visible then
      hide(entry)
    else
      show(key, (entry and entry.side) or DEFAULT_SIDE)
    end
    return
  end

  if visible then
    hide(entry)
  end
  show(key, direction)
end

vim.api.nvim_create_autocmd("WinClosed", {
  group = vim.api.nvim_create_augroup("persistent-terminal-close", { clear = true }),
  callback = function(args)
    local closed_win = tonumber(args.match)
    for key, entry in pairs(state) do
      if entry.win == closed_win then
        if entry.toggling then
          entry.toggling = nil
          entry.win = nil
        else
          -- A window also closes when its whole tab does. That is not a
          -- manual close: leave the terminal alone and let the TabClosed
          -- check decide whether the worktree still has a tab.
          local tab = vim.api.nvim_win_get_tabpage(closed_win)
          entry.win = nil
          vim.schedule(function()
            if vim.api.nvim_tabpage_is_valid(tab) then
              teardown(key)
            else
              reconcile_tabs()
            end
          end)
        end
        return
      end
    end
  end,
})

-- Last tab of a worktree closed -> end its terminal and every process in it.
vim.api.nvim_create_autocmd("TabClosed", {
  group = vim.api.nvim_create_augroup("persistent-terminal-tabclosed", { clear = true }),
  callback = reconcile_tabs,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("persistent-terminal-quit", { clear = true }),
  callback = function()
    for _, entry in pairs(state) do
      pcall(hooks.kill_tree, entry.job)
      pcall(vim.fn.jobstop, entry.job)
    end
  end,
})

vim.keymap.set({ "n", "t" }, "<M-\\>", function()
  M.toggle()
end, { desc = "Toggle persistent worktree terminal" })

vim.keymap.set({ "n", "t" }, "<leader>\\h", function()
  M.toggle("left")
end, { desc = "Mount persistent worktree terminal left" })

vim.keymap.set({ "n", "t" }, "<leader>\\j", function()
  M.toggle("bottom")
end, { desc = "Mount persistent worktree terminal bottom" })

vim.keymap.set({ "n", "t" }, "<leader>\\k", function()
  M.toggle("top")
end, { desc = "Mount persistent worktree terminal top" })

vim.keymap.set({ "n", "t" }, "<leader>\\l", function()
  M.toggle("right")
end, { desc = "Mount persistent worktree terminal right" })

-- Test-only introspection; not part of the public API.
M._test = {
  state = state,
  worktree_key = worktree_key,
  display_name = display_name,
  hooks = hooks,
  real_kill_tree = hooks.kill_tree,
}

return M
