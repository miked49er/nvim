local M = {}

-- Tabpage handles (nvim_list_tabpages) differ from tab numbers once any tab
-- has been closed; getcwd(-1, n) and :tabclose need numbers, so resolve them
-- per tab, tolerating tabs that vanish mid-iteration.
local function tab_cwd(tabpage)
  if not vim.api.nvim_tabpage_is_valid(tabpage) then
    return nil
  end
  local ok, cwd = pcall(function()
    return vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabpage))
  end)
  return ok and vim.fs.normalize(cwd) or nil
end

-- Closes every tab whose cwd is `path`, never the last remaining tab.
-- Never raises.
function M.close_for_cwd(path)
  local normalized = vim.fs.normalize(path)
  local matches = {}
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    if tab_cwd(tabpage) == normalized then
      table.insert(matches, tabpage)
    end
  end
  for _, tabpage in ipairs(matches) do
    if vim.api.nvim_tabpage_is_valid(tabpage) and #vim.api.nvim_list_tabpages() > 1 then
      pcall(function()
        vim.cmd(vim.api.nvim_tabpage_get_number(tabpage) .. "tabclose")
      end)
    end
  end
end

return M
