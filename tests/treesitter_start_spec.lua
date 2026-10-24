-- Run with: nvim --headless -l tests/treesitter_start_spec.lua
-- Seam: the FileType autocmd installed by config.treesitter.setup().
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local failures = {}
local function check(name, ok)
  print((ok and "  ok - " or "  FAIL - ") .. name)
  if not ok then table.insert(failures, name) end
end

-- 'lua' parser is bundled with Neovim; 'zsh_fake' has no parser installed.
require("config.treesitter").setup({ "lua", "zsh_fake" })

local function open(ft)
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = ft
  return buf
end

local buf = open("lua")
check("highlighter active for installed parser", vim.treesitter.highlighter.active[buf] ~= nil)
check("indentexpr set per buffer", vim.bo[buf].indentexpr:find("nvim%-treesitter") ~= nil)

check("missing parser raises no error", (pcall(open, "zsh_fake")))
check("unlisted filetype raises no error", (pcall(open, "text")))
check("jsonc maps to json parser", vim.treesitter.language.get_lang("jsonc") == "json")

if #failures > 0 then os.exit(1) end
