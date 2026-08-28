-- Worktrees always live at <repo_root>/.claude/worktrees/<name> (see
-- lua/config/telescope/git_branch.lua), so a cheap path match avoids
-- spawning git on every statusline/tabline redraw.
local M = {}

function M.label_for_cwd(cwd)
  return cwd:match('%.claude[\\/]worktrees[\\/]([^\\/]+)')
end

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
local next_slot = 1

-- Order-of-opening assignment: the first worktree name seen (by tabline or
-- statusline, whichever renders first) claims slot 1, the next claims slot
-- 2, etc., for the life of the session. Wraps past PALETTE_SIZE — two
-- worktrees could then share a color, but more than 6 concurrent worktree
-- tabs isn't a realistic session, so that collision is left unhandled.
function M.slot_for(name)
  if not assigned[name] then
    assigned[name] = next_slot
    next_slot = (next_slot % M.PALETTE_SIZE) + 1
  end
  return assigned[name]
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

return M
