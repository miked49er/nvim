-- Keymap loader. Entries are { mode, lhs, rhs, desc, opts? } where
--   mode : string | string[]
--   rhs  : string | function | { "module", "function", ...fixed args }
--          The table form is a lazy require: the owning module is only loaded
--          when the key is pressed, and the function is called with the fixed
--          args only (never the keymap's own arguments).
--   desc : required, non-empty
-- The entries live in config.keymaps.tables (`keymaps`, grouped by comment headers).
local M = {}

local function modes_of(entry)
  return type(entry[1]) == "table" and entry[1] or { entry[1] }
end

local function resolve(rhs)
  if type(rhs) ~= "table" then
    return rhs
  end
  local module, fn = rhs[1], rhs[2]
  local args = { unpack(rhs, 3) }
  return function()
    return require(module)[fn](unpack(args))
  end
end

--- Registers entries as global keymaps. Errors (registering nothing) if any
--- entry lacks a description. Returns the list of duplicate-lhs warnings,
--- which are also reported through vim.notify at WARN level.
---@param entries table[]
---@return string[] warnings
function M.register(entries)
  for i, e in ipairs(entries) do
    if type(e[4]) ~= "string" or e[4] == "" then
      error(string.format("keymap entry #%d (%s) has no description", i, tostring(e[2])), 2)
    end
  end

  local warnings, seen = {}, {}
  for _, e in ipairs(entries) do
    for _, mode in ipairs(modes_of(e)) do
      local key = mode .. "\0" .. e[2]
      if seen[key] then
        table.insert(warnings, string.format("duplicate keymap: mode '%s' lhs %s ('%s' overrides '%s')", mode, e[2], e[4], seen[key]))
      end
      seen[key] = e[4]
    end
    local opts = vim.tbl_extend("force", e[5] or {}, { desc = e[4] })
    vim.keymap.set(e[1], e[2], resolve(e[3]), opts)
  end

  for _, w in ipairs(warnings) do
    vim.notify(w, vim.log.levels.WARN)
  end
  return warnings
end

--- Registers every central table.
function M.setup()
  return M.register(require("config.keymaps.tables").keymaps)
end

return M
