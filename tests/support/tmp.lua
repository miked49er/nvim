-- Shared temp-dir helper for headless specs. Every dir made via dir() is
-- deleted on cleanup(), on os.exit() (wrapped once dir() is first used), and
-- on any other nvim exit (uncaught error) via a VimLeavePre autocmd.
--
-- Usage (spec preamble):
--   package.path = repo_root .. "/?.lua;" .. package.path
--   local tmp = require("tests.support.tmp")
--   local root = tmp.dir()          -- fresh empty dir
--   ... checks ...
--   tmp.exit(#failures > 0 and 1 or 0)
local M = {}

local dirs = {}
local hooked = false

local function leave_cwd(dir)
  -- Windows cannot delete the cwd; step out first.
  local cwd = vim.uv.cwd()
  if cwd and vim.fs.normalize(cwd):find(vim.fs.normalize(dir), 1, true) == 1 then
    vim.uv.chdir(vim.fn.fnamemodify(dir, ":h"))
  end
end

function M.cleanup()
  for i = #dirs, 1, -1 do
    pcall(leave_cwd, dirs[i])
    vim.fn.delete(dirs[i], "rf")
    dirs[i] = nil
  end
end

function M.dir(suffix)
  if not hooked then
    hooked = true
    vim.api.nvim_create_autocmd("VimLeavePre", { callback = M.cleanup })
    -- Plain os.exit() skips autocmds; clean up first.
    local real_exit = os.exit
    os.exit = function(...)
      M.cleanup()
      return real_exit(...)
    end
  end
  local path = vim.fn.tempname() .. (suffix and ("-" .. suffix) or "")
  vim.fn.mkdir(path, "p")
  dirs[#dirs + 1] = path
  return path
end

--- Delete all temp dirs, then exit with `code`.
function M.exit(code)
  M.cleanup()
  os.exit(code)
end

return M
