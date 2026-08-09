local is_windows = vim.uv.os_uname().sysname == "Windows_NT"

vim.api.nvim_create_autocmd("TermOpen", {
  group = vim.api.nvim_create_augroup("custom-term-open", { clear = true }),
  callback = function()
    vim.opt.number = false
    vim.opt.relativenumber = false
    vim.opt.bufhidden = "wipe"
  end,
})

local job_id = 0
vim.keymap.set("n", "<leader>st", function()
  vim.cmd.vnew()

  if is_windows then
    job_id = vim.fn.jobstart({
      "powershell.exe",
      "-NoLogo",
    }, { term = true })

    if job_id <= 0 then
      vim.notify("Could not start PowerShell terminal", vim.log.levels.ERROR)
      return
    end
  else
    vim.cmd.term()
  end
  vim.cmd.wincmd("J")
  vim.api.nvim_win_set_height(0, 15)

  --job_id = vim.bo.channel
end)

vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], {
  noremap = true,
  silent = true,
  desc = "Exit terminal mode",
})

--vim.keymap.set("n", "<leader>example", function()
-- make
-- go build, go test ./asdf
--vim.fn.chansend(job_id, { "echo 'Hello World'\r\n" })
--end)
