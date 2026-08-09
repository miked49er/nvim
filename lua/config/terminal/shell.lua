local M = {}

M.is_windows = vim.uv.os_uname().sysname == "Windows_NT"

--- Starts a terminal job for the current buffer using PowerShell on Windows,
--- falling back to the default shell everywhere else.
---@param opts? table extra options merged into the jobstart opts
---@return integer job_id
function M.open(opts)
  opts = vim.tbl_extend("force", { term = true }, opts or {})

  if M.is_windows then
    return vim.fn.jobstart({ "powershell.exe", "-NoLogo" }, opts)
  end

  return vim.fn.jobstart(vim.o.shell, opts)
end

return M
