local shell = require("config.terminal.shell")

vim.api.nvim_create_autocmd("TermOpen", {
  group = vim.api.nvim_create_augroup("custom-term-open", { clear = true }),
  callback = function()
    vim.opt.number = false
    vim.opt.relativenumber = false
    vim.opt.bufhidden = "wipe"
  end,
})

local M = {}

local job_id = 0
function M.open_shell_split()
  vim.cmd.vnew()

  job_id = shell.open()
  if job_id <= 0 then
    vim.notify("Could not start terminal", vim.log.levels.ERROR)
    return
  end

  vim.cmd.wincmd("J")
  vim.api.nvim_win_set_height(0, 15)
end

--vim.keymap.set("n", "<leader>example", function()
-- make
-- go build, go test ./asdf
--vim.fn.chansend(job_id, { "echo 'Hello World'\r\n" })
--end)

return M
