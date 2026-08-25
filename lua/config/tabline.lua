local worktree = require("config.worktree")

local M = {}

local function tab_label(tabnr, hl, worktree_hl)
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

  local wt = worktree.label_for_cwd(vim.fn.getcwd(-1, tabnr))
  local prefix = wt and ("%#" .. worktree_hl .. "#(" .. wt .. ")%#" .. hl .. "# ") or ""

  return " " .. prefix .. name .. modified .. " "
end

function M.render()
  local current = vim.fn.tabpagenr()
  local parts = {}
  for tabnr = 1, vim.fn.tabpagenr("$") do
    local hl = tabnr == current and "TabLineSel" or "TabLine"
    local worktree_hl = hl .. "Worktree"
    table.insert(parts, "%#" .. hl .. "#%" .. tabnr .. "T" .. tab_label(tabnr, hl, worktree_hl))
  end
  table.insert(parts, "%#TabLineFill#%T")
  return table.concat(parts)
end

-- Solid electric-blue background so the worktree segment stands out instead
-- of blending into the tab's own background (e.g. in tokyonight).
local function link_worktree_hl(base)
  vim.api.nvim_set_hl(0, base .. "Worktree", { fg = "black", bg = "DeepSkyBlue", bold = true })
end

function M.setup()
  link_worktree_hl("TabLine")
  link_worktree_hl("TabLineSel")

  vim.api.nvim_create_autocmd("ColorScheme", {
    desc = "Re-derive tabline worktree highlights for the new colorscheme",
    callback = function()
      link_worktree_hl("TabLine")
      link_worktree_hl("TabLineSel")
    end,
  })

  vim.o.tabline = "%!v:lua.require('config.tabline').render()"
end

return M
