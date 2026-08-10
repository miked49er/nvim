-- Neovim core also registers a MenuPopup autocmd (augroup "nvim.popupmenu")
-- that toggles its own PopUp.* items (e.g. "Go to definition"). Since we
-- wipe the whole PopUp menu below, that autocmd errors trying to enable
-- items that no longer exist unless we remove it first.
pcall(vim.api.nvim_del_augroup_by_name, "nvim.popupmenu")

vim.cmd([[
  aunmenu   PopUp
  anoremenu PopUp.Inspect     <cmd>Inspect<CR>
  amenu     PopUp.-1-         <NOP>
  anoremenu PopUp.Definition  <cmd>lua vim.lsp.buf.definition()<CR>
  anoremenu PopUp.References  <cmd>Telescope lsp_references<CR>
  anoremenu PopUp.Back        <C-t>
  amenu     PopUp.-1-         <NOP>
  amenu     PopUp.URL         gx
]])

local group = vim.api.nvim_create_augroup("nvim_popupmenu", { clear = true })
vim.api.nvim_create_autocmd("MenuPopup", {
  pattern = "*",
  group = group,
  desc = "Custom PopUp Setup",
  callback = function()
    vim.cmd([[
      amenu disable PopUp.Definition
      amenu disable PopUp.References
      amenu disable PopUp.URL
    ]])
    if vim.lsp.get_clients({ bufnr = 0 })[1] then
      vim.cmd([[
        amenu enable PopUp.Definition
        amenu enable PopUp.References
      ]])
    end

    local urls = require("vim.ui")._get_urls()
    if vim.startswith(urls[1], "http") then
      vim.cmd([[amenu enable PopUp.URL]])
    end
  end,
})

return {}
