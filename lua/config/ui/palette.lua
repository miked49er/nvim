-- Presentation for worktrees (glyph, colors, per-worktree palette slots).
-- Identity (names, paths, keys) lives in config.git.worktree.identity.
local M = {}

-- Shared "this is a worktree" glyph for the git menu picker, tabline, and
-- statusline: nf-oct-repo_forked (U+F402) — a repo branched into a separate
-- working copy reads closer to "worktree" than a generic branch/tree glyph.
-- No trailing space baked in: callers join it against their own text so
-- spacing doesn't double up when a highlight-group switch sits in between.
M.ICON = string.char(0xEF, 0x90, 0x82)

-- Named color (not a hex pulled from one colorscheme) so it stays electric
-- blue across theme changes. Foreground-only so it layers over a picker's
-- selection-row background instead of fighting it for the same pixels.
-- Used only by the git branch/worktree picker, which lists worktrees that
-- may not have an open tab (and therefore no assigned palette slot yet).
M.HL = { fg = 'DeepSkyBlue', bold = true }

-- Per-worktree tab/statusline coloring: ANSI red, green, yellow, blue,
-- magenta, cyan, skipping 0/7 (black/gray) and the bright 8-15 variants.
-- Blue and cyan are safe to include because the active tab no longer fills
-- its background with the theme's accent color (see tabline.lua's
-- restyle_active_tab) — that fill was blue in tokyonight and made a blue or
-- cyan icon unreadable against it. Read from vim.g.terminal_color_N so the
-- palette follows whatever colorscheme is active (tested against
-- tokyonight) instead of being hardcoded to one theme's hex values.
local ANSI_SLOTS = { 1, 2, 3, 4, 5, 6 }
M.PALETTE_SIZE = #ANSI_SLOTS

function M.color_for_slot(slot)
  return vim.g['terminal_color_' .. ANSI_SLOTS[slot]] or '#ffffff'
end

local assigned = {}

-- Lowest-unused-slot assignment: a worktree claims the smallest palette slot
-- no other currently-tracked worktree holds, and keeps it until reconciled
-- away (see M.reconcile_open). Unlike a monotonic counter, this lets slots
-- freed by closed worktrees be reused instead of cycling forever toward a
-- collision — two worktrees only ever share a color if more than
-- PALETTE_SIZE are tracked at once, which reconcile_open prevents as long as
-- tabline.render() calls it with the actual open set.
function M.slot_for(name)
  if assigned[name] then
    return assigned[name]
  end

  local used = {}
  for _, slot in pairs(assigned) do
    used[slot] = true
  end

  local slot = 1
  while used[slot] and slot < M.PALETTE_SIZE do
    slot = slot + 1
  end

  assigned[name] = slot
  return slot
end

-- Drops tracked worktrees that are no longer open, freeing their slot for
-- reuse. `open_names` is a set (name -> true) of worktree names currently
-- backing a tab. Called from tabline.render(), which already enumerates
-- every open tab, so this stays in sync without a dedicated close event.
function M.reconcile_open(open_names)
  for name in pairs(assigned) do
    if not open_names[name] then
      assigned[name] = nil
    end
  end
end

-- Relative luminance of a "#rrggbb" hex color, used to pick legible
-- black/white statusline text against whichever palette color a worktree
-- was assigned (some ANSI slots, e.g. yellow, are too light for white text).
local function luminance(hex)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255
end

function M.fg_for_bg(hex)
  return luminance(hex) > 0.6 and 'black' or 'white'
end

-- Highlight group name for a base prefix and palette slot, e.g.
-- ("TabLine", 3) -> "TabLineWorktree3".
function M.group_name(base, slot)
  return base .. 'Worktree' .. slot
end

-- Defines one group per palette slot under `base`. `style(color, slot)`
-- returns the nvim_set_hl attributes for that slot's color.
function M.define_slot_groups(base, style)
  for slot = 1, M.PALETTE_SIZE do
    vim.api.nvim_set_hl(0, M.group_name(base, slot), style(M.color_for_slot(slot), slot))
  end
end

-- Runs `define` now and again on every ColorScheme change.
function M.define_now_and_on_colorscheme(desc, define)
  define()
  vim.api.nvim_create_autocmd('ColorScheme', { desc = desc, callback = define })
end

return M
