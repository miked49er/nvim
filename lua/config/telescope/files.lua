-- File-finder pickers bound by config.keymaps.telescope.
local M = {}

local function builtin()
  return require("telescope.builtin")
end

function M.help_tags()
  builtin().help_tags()
end

function M.find_in_cwd()
  builtin().find_files({ cwd = vim.fn.getcwd() })
end

function M.find_in_config()
  builtin().find_files(require("telescope.themes").get_dropdown({
    cwd = vim.fn.stdpath("config"),
  }))
end

function M.find_in_plugins()
  builtin().find_files({
    cwd = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy"),
  })
end

function M.find_in_chosen_dir()
  local dir = vim.fn.input("Search in dir: ", vim.fn.getcwd() .. "/", "dir")
  if dir == "" then
    return
  end
  builtin().find_files({
    cwd = dir,
    hidden = true,
    no_ignore = true,
    file_ignore_patterns = {},
  })
end

return M
