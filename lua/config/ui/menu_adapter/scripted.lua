-- Scripted menu adapter for headless specs. Answers are consumed in order, one
-- per prompt, and every prompt is recorded in adapter.prompts.
--   scripted.new({ answer, ... })
-- Answers by prompt kind:
--   choose_one:  "label" (matches an entry's display/ordinal) | {pick=label|fn(entry)}
--                | {input="typed text"}
--   choose_many: {pick={label|fn, ...}}
--   text:        "text" | {text="..."}
--   confirm:     true | false
--   any:         scripted.BACK (Esc); a missing answer also means back/no.
local M = {}

M.BACK = setmetatable({}, { __tostring = function() return "BACK" end })

local function find(entries, want)
  for _, e in ipairs(entries) do
    local hit
    if type(want) == "function" then
      hit = want(e)
    else
      hit = e.display == want or e.ordinal == want
    end
    if hit then
      return e
    end
  end
  local names = {}
  for _, e in ipairs(entries) do
    names[#names + 1] = tostring(e.display)
  end
  error("scripted menu: no entry " .. tostring(want) .. " in [" .. table.concat(names, ", ") .. "]", 0)
end

function M.new(script)
  local adapter = { prompts = {} }
  local i = 0

  local function next_answer(kind, req)
    i = i + 1
    table.insert(adapter.prompts, vim.tbl_extend("force", { kind = kind }, req))
    local a = script[i]
    if a == M.BACK then
      return nil
    end
    return a
  end

  function adapter.choose_one(req, done)
    local a = next_answer("choose_one", req)
    if a == nil then
      return done(nil)
    end
    if type(a) == "table" and a.input ~= nil then
      return done({ input = a.input })
    end
    local want = type(a) == "table" and a.pick or a
    done({ value = find(req.entries, want).value })
  end

  function adapter.choose_many(req, done)
    local a = next_answer("choose_many", req)
    if a == nil then
      return done(nil)
    end
    local values = {}
    local wants = type(a.pick) == "table" and a.pick or { a.pick }
    for _, want in ipairs(wants) do
      table.insert(values, find(req.entries, want).value)
    end
    done({ values = values })
  end

  function adapter.text(req, done)
    local a = next_answer("text", req)
    if a == nil then
      return done(nil)
    end
    done({ text = type(a) == "table" and a.text or a })
  end

  function adapter.confirm(req, done)
    done(next_answer("confirm", req) == true)
  end

  return adapter
end

return M
