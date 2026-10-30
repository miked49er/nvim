local identity = require("config.git.worktree.identity")
local palette = require("config.ui.palette")
local repo = require("config.git.repo")

local M = {}

local function get_empty_tab_name(cwd)
  local wt = identity.name_for_path(cwd)
  if wt then
    return wt
  else
    local branch = repo.cached_branch(cwd)
    return branch or "[No Name]"
  end
end

local function tab_label(tabnr, hl)
  local buflist = vim.fn.tabpagebuflist(tabnr)
  local bufnr = buflist[vim.fn.tabpagewinnr(tabnr)]

  local buftype = vim.fn.getbufvar(bufnr, "&buftype")
  local name

  if buftype ~= "" then
    local cwd = vim.fn.getcwd(-1, tabnr)
    name = get_empty_tab_name(cwd)
  else
    local bufname = vim.fn.bufname(bufnr)
    if bufname ~= "" then
      name = vim.fn.fnamemodify(bufname, ":t")
    else
      local cwd = vim.fn.getcwd(-1, tabnr)
      name = get_empty_tab_name(cwd)
    end
  end

  local modified = ""
  for _, buf in ipairs(buflist) do
    if vim.fn.getbufvar(buf, "&modified") == 1 then
      modified = " +"
      break
    end
  end

  -- Icon only, no name/box: a full "(worktree-name)" chunk pushed long names
  -- into the rest of the tabline, so only the glyph is colored (fg-only,
  -- same as palette.HL) and the buffer name stays in the tab's own hl.
  -- Colored by the worktree's assigned palette slot so different worktrees'
  -- tabs are visually distinguishable at a glance.
  local wt = identity.name_for_path(vim.fn.getcwd(-1, tabnr))
  local prefix = wt and ("%#" .. palette.group_name(hl, palette.slot_for(wt)) .. "#" .. palette.ICON .. " %#" .. hl .. "#") or ""

  return " " .. prefix .. name .. modified .. " "
end

function M.render()
  local open_worktrees = {}
  for tabnr = 1, vim.fn.tabpagenr("$") do
    local wt = identity.name_for_path(vim.fn.getcwd(-1, tabnr))
    if wt then
      open_worktrees[wt] = true
    end
  end
  palette.reconcile_open(open_worktrees)

  local current = vim.fn.tabpagenr()
  local parts = {}
  for tabnr = 1, vim.fn.tabpagenr("$") do
    local hl = tabnr == current and "TabLineSel" or "TabLine"
    table.insert(parts, "%#" .. hl .. "#%" .. tabnr .. "T" .. tab_label(tabnr, hl))
  end
  table.insert(parts, "%#TabLineFill#%T")
  return table.concat(parts)
end

-- Replace the active tab's solid accent-colored background with a same-bg,
-- bold, brighter-text look — no line/bar indicator, just weight and
-- contrast against the dimmer inactive tabs. A colored bg meant the active
-- tab could only ever contrast against one specific hue (blue, in
-- tokyonight) — worse, that hue was also the theme's accent color, so any
-- worktree icon sharing it would vanish. Flat backgrounds on both states let
-- every palette color, including the accent hue itself, stay visible in
-- both tab states.
local function restyle_active_tab()
  local inactive_bg = vim.api.nvim_get_hl(0, { name = "TabLine", link = false }).bg
  local normal_fg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg
  vim.api.nvim_set_hl(0, "TabLineSel", { bg = inactive_bg, fg = normal_fg, bold = true })
end

-- Per-slot groups inherit the base group's bg wholesale and override only
-- fg. palette.color_for_slot() is fg-only — nvim_set_hl with no bg falls
-- back to Normal's background rather than the base group's, which showed up
-- as a mismatched patch behind the icon. One group per (base, palette slot)
-- pair, created upfront regardless of whether a slot is in use yet — cheap
-- (12 groups).
local function define_tab_slot_groups(base)
  local base_hl = vim.api.nvim_get_hl(0, { name = base, link = false })
  palette.define_slot_groups(base, function(color)
    return vim.tbl_extend("force", base_hl, { fg = color, bold = true })
  end)
end

local function define_tabline_highlights()
  restyle_active_tab()
  define_tab_slot_groups("TabLine")
  define_tab_slot_groups("TabLineSel")
end

function M.setup()
  palette.define_now_and_on_colorscheme(
    "Re-derive tabline worktree highlights for the new colorscheme",
    define_tabline_highlights
  )

  vim.o.tabline = "%!v:lua.require('config.tabline').render()"
end

return M
