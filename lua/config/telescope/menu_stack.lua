-- Back-navigation for nested Telescope pickers/prompts (see
-- lua/config/telescope/git_branch.lua). Before opening a child screen, the
-- caller pushes a thunk that reopens the screen it's leaving; popping
-- replays that thunk to go back one level. An empty stack means "root
-- screen" — back() then just closes without reopening anything.
local M = {}

local stack = {}

function M.reset()
  stack = {}
end

function M.push(reopen)
  table.insert(stack, reopen)
end

function M.pop_and_open()
  local parent = table.remove(stack)
  if parent then
    parent()
  end
end

-- Wires <Esc> (normal + insert) on a picker to go back one level.
function M.attach_back(map, prompt_bufnr)
  local actions = require("telescope.actions")
  local function back()
    actions.close(prompt_bufnr)
    M.pop_and_open()
  end
  map("n", "<Esc>", back)
  map("i", "<Esc>", back)
end

return M
