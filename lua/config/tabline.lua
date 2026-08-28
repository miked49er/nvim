local worktree = require("config.worktree")

local M = {}

local function tab_label(tabnr, hl)
  local buflist = vim.fn.tabpagebuflist(tabnr)
  local bufnr = buflist[vim.fn.tabpagewinnr(tabnr)]

  local bufname = vim.fn.bufname(bufnr)
  local name = bufname ~= "" and vim.fn.fnamemodify(bufname, ":t") or "[No Name]"

  local modified = ""
  for _, buf in ipairs(buflist) do
    if vim.fn.getbufvar(buf, "&modified") == 1 then
      modified = " +"
      break
    end
  end

  -- Icon only, no name/box: a full "(worktree-name)" chunk pushed long names
  -- into the rest of the tabline, so only the glyph is colored (fg-only,
  -- same as worktree.HL) and the buffer name stays in the tab's own hl.
  -- Colored by the worktree's assigned palette slot so different worktrees'
  -- tabs are visually distinguishable at a glance.
  local wt = worktree.label_for_cwd(vim.fn.getcwd(-1, tabnr))
  local prefix = wt and ("%#" .. hl .. "Worktree" .. worktree.slot_for(wt) .. "#" .. worktree.ICON .. " %#" .. hl .. "#") or ""

  return " " .. prefix .. name .. modified .. " "
end

function M.render()
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
-- fg. worktree.color_for_slot() is fg-only — nvim_set_hl with no bg falls
-- back to Normal's background rather than the base group's, which showed up
-- as a mismatched patch behind the icon. One group per (base, palette slot)
-- pair, created upfront regardless of whether a slot is in use yet — cheap
-- (12 groups).
local function link_worktree_hl(base)
  local base_hl = vim.api.nvim_get_hl(0, { name = base, link = false })
  for slot = 1, worktree.PALETTE_SIZE do
    vim.api.nvim_set_hl(0, base .. "Worktree" .. slot, vim.tbl_extend("force", base_hl, {
      fg = worktree.color_for_slot(slot),
      bold = true,
    }))
  end
end

local function link_all()
  restyle_active_tab()
  link_worktree_hl("TabLine")
  link_worktree_hl("TabLineSel")
end

function M.setup()
  link_all()

  vim.api.nvim_create_autocmd("ColorScheme", {
    desc = "Re-derive tabline worktree highlights for the new colorscheme",
    callback = link_all,
  })

  vim.o.tabline = "%!v:lua.require('config.tabline').render()"
end

return M
