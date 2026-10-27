-- The one place that runs git. A repo handle is opened per action for a
-- directory and resolves the checkout root and the main repo root once:
--
--   local h = repo.open(dir)            -- nil, err outside a repository
--   h.root, h.main_root, h.git_dir
--   h:run(args) / h:run_async(args, cb) -- {code, stdout, stderr}; cb on main loop
--   h:lines(args), h:head(), h:is_locked()
--   h:worktrees(), h:branches(), h:status(), h:status_async(cb), h:stashes()
--
-- Module level (no git spawned):
--   repo.branch_for_dir(dir)  file-read branch/short-SHA lookup, uncached
--   repo.cached_branch(dir)   same, cached; for tabline/statusline redraws
--   repo.BRANCH_ICON
--   repo.busy.start(text) -> token, repo.busy.stop(token), repo.busy.label()
--   repo.parse_status / parse_worktrees / parse_branches / parse_stashes
--
-- This module is the only invalidator of the branch cache (after every
-- command it runs, plus DirChanged/FocusGained) and the only owner of the
-- busy indicator. The busy indicator is a counter: overlapping operations
-- keep the label until all of them have finished.
local M = {}

-- nf-oct-git_branch (U+F418), distinct from the worktree glyph.
M.BRANCH_ICON = string.char(0xEF, 0x90, 0x98)

---------------------------------------------------------------------------
-- Branch cache + git-free branch lookup
---------------------------------------------------------------------------

local cache = {}

local function invalidate()
  cache = {}
end

-- HEAD file content -> branch name, or short SHA when detached.
local function branch_from_head_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*l")
  file:close()
  if not content then
    return nil
  end
  local branch = content:match("^ref: refs/heads/(.+)$")
  if branch then
    return branch
  end
  return content:sub(1, 7)
end

-- `.git` is either a repo's own directory (main worktree) or, for a linked
-- worktree, a file containing "gitdir: <path>/.git/worktrees/<name>"; the
-- HEAD file lives directly inside that gitdir.
function M.branch_for_dir(dir)
  local dot_git = vim.fs.joinpath(dir, ".git")
  local stat = vim.uv.fs_stat(dot_git)
  if not stat then
    return nil
  end

  local gitdir = dot_git
  if stat.type == "file" then
    local file = io.open(dot_git, "r")
    if not file then
      return nil
    end
    local content = file:read("*l")
    file:close()
    gitdir = content and content:match("^gitdir: (.+)$")
    if not gitdir then
      return nil
    end
  end

  return branch_from_head_file(vim.fs.joinpath(gitdir, "HEAD"))
end

function M.cached_branch(dir)
  local name = cache[dir]
  if name == nil then
    name = M.branch_for_dir(dir) or false
    cache[dir] = name
  end
  return name or nil
end

vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained" }, {
  desc = "Invalidate cached statusline branch name",
  callback = invalidate,
})

---------------------------------------------------------------------------
-- Busy counter
---------------------------------------------------------------------------

local active = {} -- ordered list of { text = ... } tokens

M.busy = {}

function M.busy.start(text)
  local token = { text = text }
  table.insert(active, token)
  vim.cmd("redrawstatus")
  return token
end

function M.busy.stop(token)
  for i, t in ipairs(active) do
    if t == token then
      table.remove(active, i)
      break
    end
  end
  vim.cmd("redrawstatus")
end

function M.busy.label()
  local last = active[#active]
  return last and last.text or nil
end

---------------------------------------------------------------------------
-- Porcelain parsers (plain data)
---------------------------------------------------------------------------

local function split_lines(stdout)
  return vim.split(stdout or "", "\n", { trimempty = true })
end

-- `git status --porcelain` -> { {status = "??", path = "dir/a.txt"}, ... }.
-- Status is trimmed; renames keep the new path; quoted paths are unquoted.
function M.parse_status(stdout)
  local entries = {}
  for _, line in ipairs(split_lines(stdout)) do
    local path = line:sub(4):gsub("^.* %-> ", ""):gsub('^"(.*)"$', "%1")
    table.insert(entries, { status = vim.trim(line:sub(1, 2)), path = path })
  end
  return entries
end

-- `git worktree list --porcelain` -> ordered { {path, branch?, is_main}, ... };
-- the first block is always the main worktree.
function M.parse_worktrees(stdout)
  local list = {}
  local current
  for _, line in ipairs(vim.split(stdout or "", "\n")) do
    local wt_path = line:match("^worktree (.+)$")
    local branch = line:match("^branch refs/heads/(.+)$")
    if wt_path then
      current = { path = wt_path, is_main = #list == 0 }
      table.insert(list, current)
    elseif branch and current then
      current.branch = branch
    elseif line == "" then
      current = nil
    end
  end
  return list
end

-- Local branch names and remote refs (`origin/x`) -> entries. A remote branch
-- with a local namesake is dropped; remote HEAD pointers are skipped.
function M.parse_branches(local_names, remote_refs)
  local entries, locals_set = {}, {}
  for _, name in ipairs(local_names) do
    locals_set[name] = true
    table.insert(entries, { name = name, is_local = true })
  end
  for _, remote in ipairs(remote_refs) do
    if not remote:match("/HEAD$") then
      local short = remote:gsub("^[^/]+/", "")
      if not locals_set[short] then
        table.insert(entries, { name = short, is_local = false, remote = remote })
      end
    end
  end
  return entries
end

-- `git stash list` -> { {ref = "stash@{0}", raw = "<full line>"}, ... }
function M.parse_stashes(stdout)
  local entries = {}
  for _, line in ipairs(split_lines(stdout)) do
    local ref = line:match("^(stash@{%d+})")
    if ref then
      table.insert(entries, { ref = ref, raw = line })
    end
  end
  return entries
end

---------------------------------------------------------------------------
-- Handle
---------------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

local NOT_A_REPO = "not a git repository"

local RESOLVE = {
  "git", "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir", "--absolute-git-dir",
}

local function make_handle(dir, result)
  if result.code ~= 0 then
    return nil, NOT_A_REPO
  end
  local lines = split_lines(result.stdout)
  if #lines < 3 then
    return nil, NOT_A_REPO
  end
  -- The common git dir is shared by every worktree, unlike --show-toplevel
  -- which is whichever worktree's own root you are sitting in.
  return setmetatable({
    dir = dir,
    root = lines[1],
    main_root = vim.fs.dirname(lines[2]),
    git_dir = lines[3],
  }, Handle)
end

--- Sync. Returns a handle, or nil + reason when `dir` is not in a repository.
function M.open(dir)
  dir = dir or vim.fn.getcwd()
  if vim.fn.isdirectory(dir) == 0 then
    return nil, NOT_A_REPO
  end
  return make_handle(dir, vim.system(RESOLVE, { text = true, cwd = dir }):wait())
end

--- Async: on_done(handle|nil, err) runs on the main loop.
function M.open_async(dir, on_done)
  dir = dir or vim.fn.getcwd()
  if vim.fn.isdirectory(dir) == 0 then
    return vim.schedule(function()
      on_done(nil, NOT_A_REPO)
    end)
  end
  vim.system(RESOLVE, { text = true, cwd = dir }, function(result)
    vim.schedule(function()
      on_done(make_handle(dir, result))
    end)
  end)
end

local function cmd_of(args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  return cmd
end

-- Any command might have moved HEAD (switch/checkout/rename/...), so the
-- branch cache is invalidated unconditionally rather than per call site.
function Handle:run(args)
  local result = vim.system(cmd_of(args), { text = true, cwd = self.dir }):wait()
  invalidate()
  return result
end

-- on_done runs on the main loop (vim.system's own callback fires off-loop
-- and is not safe for notify/buffer/window calls).
function Handle:run_async(args, on_done)
  vim.system(cmd_of(args), { text = true, cwd = self.dir }, function(result)
    vim.schedule(function()
      invalidate()
      on_done(result)
    end)
  end)
end

function Handle:lines(args)
  local result = self:run(args)
  if result.code ~= 0 then
    return {}
  end
  return split_lines(result.stdout)
end

function Handle:head()
  return self:lines({ "rev-parse", "--abbrev-ref", "HEAD" })[1] or "HEAD"
end

--- A locked worktree has `<git-dir>/locked`.
function Handle:is_locked()
  return vim.uv.fs_stat(self.git_dir .. "/locked") ~= nil
end

function Handle:worktrees()
  local result = self:run({ "worktree", "list", "--porcelain" })
  if result.code ~= 0 then
    return {}
  end
  return M.parse_worktrees(result.stdout)
end

function Handle:branches()
  return M.parse_branches(
    self:lines({ "branch", "--format=%(refname:short)" }),
    self:lines({ "branch", "-r", "--format=%(refname:short)" })
  )
end

local STATUS_ARGS = { "status", "--porcelain", "--untracked-files=all" }

function Handle:status()
  local result = self:run(STATUS_ARGS)
  if result.code ~= 0 then
    return {}
  end
  return M.parse_status(result.stdout)
end

function Handle:status_async(on_done)
  self:run_async(STATUS_ARGS, function(result)
    on_done(result.code == 0 and M.parse_status(result.stdout) or {})
  end)
end

function Handle:stashes()
  local result = self:run({ "stash", "list" })
  if result.code ~= 0 then
    return {}
  end
  return M.parse_stashes(result.stdout)
end

return M
