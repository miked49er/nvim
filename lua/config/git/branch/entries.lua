-- Branch/worktree entry list as plain data (no Telescope). Ordering, display
-- text, ordinals and worktree annotation for the switch/create pickers.
-- `worktree_map` is branch name -> worktree path. Glyph/colors are
-- presentation and stay with the picker.
local identity = require("config.git.worktree.identity")

local M = {}

--- Branches with a worktree first; otherwise keeps the input order.
function M.order(branches, worktree_map)
  local with_wt, without_wt = {}, {}
  for _, b in ipairs(branches) do
    table.insert(worktree_map[b.name] and with_wt or without_wt, b)
  end
  vim.list_extend(with_wt, without_wt)
  return with_wt
end

--- Plain display for a branch with no worktree annotation.
function M.branch(b)
  local display = b.name
  if not b.is_local then
    display = display .. "  [remote]"
  end
  return { display = display, ordinal = b.name }
end

--- Display for a branch in the switch/create list. `mode` is "branch" or
--- "worktree". When the worktree name differs from the branch it is shown as
--- "<worktree>:<branch>" and is searchable (glossary: worktree vs branch name).
function M.describe(b, worktree_map, mode)
  local made = M.branch(b)
  local path = worktree_map[b.name]
  if path then
    made.worktree = true
    made.worktree_path = path
    local wt_name = identity.name_differs(path, b.name)
    if wt_name then
      made.display = wt_name .. ":" .. made.display
      made.ordinal = wt_name .. " " .. made.ordinal
    end
    if mode == "worktree" then
      made.display = made.display .. "  (" .. path .. ")"
    end
  end
  return made
end

--- Predicate for branches that outrank the rest while typing.
function M.prefers(worktree_map)
  return function(b)
    return worktree_map[b.name] ~= nil
  end
end

--- Final sort score: non-preferred matches are pushed behind preferred ones;
--- -1 (no match) is preserved.
function M.rank(score, preferred)
  if score == -1 or preferred then
    return score
  end
  return score + 1e6
end

return M
