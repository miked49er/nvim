-- Scripted removal adapter for headless specs. Answers come from a script and
-- every prompt is recorded.
--   scripted.new({ policy = POLICY.*|nil, confirms = { RESULT.*|false, ... },
--                  on_prompt = function(kind) end })
-- A nil policy / missing confirm answers cancel. `on_prompt` (optional) runs
-- at each prompt, e.g. to observe disk state.
local M = {}

function M.new(script)
  script = script or {}
  local adapter = { policies = {}, confirms = {} }
  local ci = 0

  function adapter.choose_policy(dirty, cb)
    table.insert(adapter.policies, dirty)
    if script.on_prompt then
      script.on_prompt("policy")
    end
    cb(script.policy)
  end

  function adapter.confirm(wt, entries, opts, cb)
    ci = ci + 1
    table.insert(adapter.confirms, { wt = wt, entries = entries, opts = opts })
    if script.on_prompt then
      script.on_prompt("confirm")
    end
    cb((script.confirms and script.confirms[ci]) or nil)
  end

  return adapter
end

return M
