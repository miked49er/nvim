-- Run with: nvim --headless -l tests/keymaps/loader_spec.lua
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local failures = {}
local function check(name, ok)
  print((ok and "  ok - " or "  FAIL - ") .. name)
  if not ok then table.insert(failures, name) end
end

local keymaps = require("config.keymaps")

local function find(mode, lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhs == lhs then return m end
  end
end

-- Registers string rhs, function rhs and multi-mode entries with their desc.
local called = 0
local warnings = keymaps.register({
  { "n", "<F13>", "<cmd>echo 1<CR>", "String rhs" },
  { { "n", "t" }, "<F14>", function() called = called + 1 end, "Function rhs" },
})
check("no warnings for clean table", #warnings == 0)
local m = find("n", "<F13>")
check("string rhs registered with desc", m and m.desc == "String rhs" and m.rhs == "<Cmd>echo 1<CR>")
check("multi-mode registered in n", find("n", "<F14>") ~= nil)
check("multi-mode registered in t", find("t", "<F14>") ~= nil)
find("n", "<F14>").callback()
check("function rhs callable", called == 1)

-- {module, fn, args...} is a lazy require: nothing loaded until the key fires.
package.preload["spec.fake_owner"] = function()
  _G.fake_owner_loaded = true
  return { go = function(...) _G.fake_owner_args = { ... } end }
end
keymaps.register({ { "n", "<F15>", { "spec.fake_owner", "go", "left" }, "Lazy owner call" } })
check("owner not required at registration", _G.fake_owner_loaded == nil)
find("n", "<F15>").callback()
check("owner required on first use", _G.fake_owner_loaded == true)
check("fixed args passed, keymap args not", #_G.fake_owner_args == 1 and _G.fake_owner_args[1] == "left")

-- Extra opts are forwarded.
keymaps.register({ { "t", "<F16>", "<C-n>", "With opts", { silent = true } } })
check("opts forwarded", find("t", "<F16>").silent == 1)

-- Missing description is rejected, nothing registered.
local ok = pcall(keymaps.register, { { "n", "<F17>", "<cmd>echo 2<CR>" } })
check("missing desc rejected", not ok)
check("rejected entry not registered", find("n", "<F17>") == nil)
ok = pcall(keymaps.register, { { "n", "<F17>", "<cmd>echo 2<CR>", "" } })
check("empty desc rejected", not ok)

-- Duplicate lhs (same mode) warns; different modes do not.
local notified = {}
local real_notify = vim.notify
vim.notify = function(msg, level) table.insert(notified, { msg, level }) end
warnings = keymaps.register({
  { "n", "<F18>", "<cmd>echo 3<CR>", "First" },
  { "n", "<F18>", "<cmd>echo 4<CR>", "Second" },
  { "t", "<F18>", "<cmd>echo 5<CR>", "Other mode" },
  { { "n", "t" }, "<F19>", "<cmd>echo 6<CR>", "Multi" },
  { "t", "<F19>", "<cmd>echo 7<CR>", "Clashes in t" },
})
vim.notify = real_notify
check("two duplicate warnings", #warnings == 2)
check("warning names lhs", warnings[1]:find("<F18>", 1, true) ~= nil)
check("warning names mode", warnings[2]:find("t", 1, true) ~= nil and warnings[2]:find("<F19>", 1, true) ~= nil)
check("warnings also notified at WARN", #notified == 2 and notified[1][2] == vim.log.levels.WARN)

-- The real tables are clean: every entry described, no duplicate lhs.
local tables = require("config.keymaps.tables")
local real = tables.keymaps
local seen, dup, nodesc = {}, 0, 0
for _, e in ipairs(real) do
  if type(e[4]) ~= "string" or e[4] == "" then nodesc = nodesc + 1 end
  for _, mode in ipairs(type(e[1]) == "table" and e[1] or { e[1] }) do
    local k = mode .. " " .. e[2]
    if seen[k] then dup = dup + 1 end
    seen[k] = true
  end
end
check("real table: every entry has a description", nodesc == 0)
check("real table: no duplicate lhs", dup == 0)

-- Plugin-internal exported data keeps its shape.
local completion = tables.completion
check("completion preset kept", completion.preset == "default")
check("completion <Tab> chain", vim.deep_equal(completion["<Tab>"], { "select_and_accept", "snippet_forward", "fallback" }))
check("completion <S-Tab> chain", vim.deep_equal(completion["<S-Tab>"], { "snippet_backward", "fallback" }))
local picker = tables.picker
check("picker actions exported", picker.back and picker.toggle_select and picker.confirm and picker.cancel and picker.skip)

if #failures > 0 then
  print(#failures .. " failure(s)")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
