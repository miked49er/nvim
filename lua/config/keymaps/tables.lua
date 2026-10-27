-- The one central keymap table: concatenation of the area files below.
-- Plugin-internal keys are exported data in config.keymaps.completion and
-- config.keymaps.picker, consumed by their owners.
local areas = { "editor", "git", "telescope", "terminal", "lsp" }

local all = {}
for _, area in ipairs(areas) do
  vim.list_extend(all, require("config.keymaps." .. area))
end
return all
