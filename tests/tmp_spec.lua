-- Run with: nvim --headless -l tests/tmp_spec.lua
-- The shared temp helper must delete its dirs on success and on failure.
-- Each scenario runs in a child nvim so we see what is left after it exits.
local repo_root = vim.fn.getcwd()
package.path = repo_root .. "/?.lua;" .. package.path
local tmp = require("tests.support.tmp")

local failures = {}
local function check(name, ok, detail)
  print((ok and "  ok - " or "  FAIL - ") .. name .. ((not ok and detail) and (": " .. detail) or ""))
  if not ok then table.insert(failures, name) end
end

-- Runs `body` in a child nvim that has the helper loaded; returns exit code and
-- the temp path the child created (printed on a line starting "PATH=").
local function child(body)
  local script = vim.fn.tempname() .. ".lua"
  local f = assert(io.open(script, "w"))
  f:write(('package.path = %q .. "/?.lua;" .. package.path\n'):format(repo_root))
  f:write('local tmp = require("tests.support.tmp")\n')
  f:write(body)
  f:close()
  local r = vim.system({ "nvim", "--headless", "-l", script }, { text = true, cwd = repo_root }):wait()
  os.remove(script)
  local out = (r.stdout or "") .. (r.stderr or "")
  return r.code, out:match("PATH=(%S+)"), out
end

local function exists(p) return p ~= nil and vim.uv.fs_stat(p) ~= nil end

-- Direct API
local d = tmp.dir()
vim.fn.mkdir(d .. "/nested", "p")
check("dir() creates a directory", exists(d))
tmp.cleanup()
check("cleanup() removes created dirs", not exists(d))

-- Success path: explicit exit
local code, p = child([[
local d = tmp.dir()
vim.fn.writefile({ "x" }, d .. "/f")
print("PATH=" .. d)
tmp.exit(0)
]])
check("success: exit code propagated", code == 0, tostring(code))
check("success: dir deleted", p ~= nil and not exists(p), tostring(p))

-- Failure via exit code
code, p = child([[
local d = tmp.dir()
print("PATH=" .. d)
tmp.exit(1)
]])
check("failure exit: code propagated", code == 1, tostring(code))
check("failure exit: dir deleted", p ~= nil and not exists(p), tostring(p))

-- Failure via uncaught error (no explicit cleanup)
local out
code, p, out = child([[
local d = tmp.dir()
print("PATH=" .. d)
error("boom")
]])
check("uncaught error: non-zero exit", code ~= 0, tostring(code))
check("uncaught error: dir deleted", p ~= nil and not exists(p), tostring(p) .. " " .. out)

-- Failure via plain os.exit(1)
code, p = child([[
local d = tmp.dir()
print("PATH=" .. d)
os.exit(1)
]])
check("os.exit(1): dir deleted", p ~= nil and not exists(p), tostring(p))

-- cwd inside the temp dir (Windows cannot delete the cwd)
code, p = child([[
local d = tmp.dir()
vim.fn.chdir(d)
print("PATH=" .. d)
tmp.exit(0)
]])
check("cwd inside temp dir: dir deleted", p ~= nil and not exists(p), tostring(p))

if #failures > 0 then
  print(#failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
