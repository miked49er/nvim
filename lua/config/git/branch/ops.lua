-- Branch and stash operations. Every function takes a repo handle (see
-- config.git.repo) and returns a result; none notify or open UI:
--
--   { ok = true,  value = <op specific> }
--   { ok = false, err = "<stderr>", result = <raw git result>, conflicts = {files}? }
--
-- `conflicts` is set (non-empty) on merge/stash pop/apply when the failure left
-- unmerged files, so the caller can fall back to the diff tool.
local M = {}

local function ok(value)
  return { ok = true, value = value }
end

local function fail(result, err)
  return { ok = false, err = err or vim.trim(result and result.stderr or ""), result = result }
end

local function from(result, value)
  if result.code ~= 0 then
    return fail(result)
  end
  return ok(value)
end

local function with_conflicts(h, result)
  local r = fail(result)
  local unmerged = h:lines({ "diff", "--name-only", "--diff-filter=U" })
  if #unmerged > 0 then
    r.conflicts = unmerged
  end
  return r
end

---------------------------------------------------------------------------
-- Branches
---------------------------------------------------------------------------

function M.switch(h, name)
  return from(h:run({ "switch", name }), name)
end

function M.track_remote(h, name, remote)
  return from(h:run({ "switch", "-c", name, "--track", remote }), name)
end

function M.create(h, name, base)
  return from(h:run({ "switch", "-c", name, base }), name)
end

function M.rename(h, old, new)
  return from(h:run({ "branch", "-m", old, new }), new)
end

-- Both worktree adders return the new worktree path as the value.
function M.worktree_add_new(h, path, name, base)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  return from(h:run({ "worktree", "add", "-b", name, path, base }), path)
end

function M.worktree_add_existing(h, path, entry)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local args
  if entry.is_local then
    args = { "worktree", "add", path, entry.name }
  else
    args = { "worktree", "add", "-b", entry.name, path, entry.remote }
  end
  return from(h:run(args), path)
end

-- Local-only cleanup: never touches the remote. If the deleted branch left a
-- stale remote-tracking ref behind (origin/<name>), drop that too.
local function prune_stale_remote_ref(h, name)
  if h:run({ "rev-parse", "--verify", "--quiet", "refs/remotes/origin/" .. name }).code == 0 then
    h:run({ "branch", "-dr", "origin/" .. name })
  end
end

--- Async. opts.force uses -D. on_done(result) runs on the main loop; value is
--- the branch name.
function M.delete_async(h, name, opts, on_done)
  local flag = (opts and opts.force) and "-D" or "-d"
  h:run_async({ "branch", flag, name }, function(result)
    if result.code == 0 then
      prune_stale_remote_ref(h, name)
    end
    on_done(from(result, name))
  end)
end

function M.merge(h, entry)
  local source = entry.is_local and entry.name or entry.remote
  local result = h:run({ "merge", source })
  if result.code == 0 then
    return ok(source)
  end
  return with_conflicts(h, result)
end

-- A plain `git push` only works when the upstream's own branch name matches
-- the local one. A branch created from a remote base (e.g. `origin/main`)
-- tracks that ref under its original name, so pushing a same-named local
-- branch to it is rejected. Treat that mismatch the same as "no upstream".
-- Value is the pushed branch name.
function M.push(h)
  local branch = h:head()
  local upstream = h:lines({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" })[1]
  local upstream_branch = upstream and upstream:match("^[^/]+/(.+)$")
  local args = (upstream_branch == branch) and { "push" } or { "push", "-u", "origin", branch }
  return from(h:run(args), branch)
end

-- Value is the branch name pulled into.
function M.pull(h)
  local result = h:run({ "pull" })
  if result.code ~= 0 then
    return fail(result)
  end
  return ok(h:head())
end

---------------------------------------------------------------------------
-- Stashes
---------------------------------------------------------------------------

--- opts.message (optional), opts.files (optional list: stash only these,
--- including untracked). Value is { saved = bool }.
function M.stash_push(h, opts)
  opts = opts or {}
  local args = { "stash", "push" }
  if opts.files then
    table.insert(args, "-u")
  end
  if opts.message and opts.message ~= "" then
    vim.list_extend(args, { "-m", opts.message })
  end
  if opts.files then
    table.insert(args, "--")
    vim.list_extend(args, opts.files)
  end
  local result = h:run(args)
  if result.code ~= 0 then
    return fail(result)
  end
  local saved = not (result.stdout or ""):find("No local changes to save", 1, true)
  return ok({ saved = saved })
end

function M.stash_pop(h)
  local result = h:run({ "stash", "pop" })
  if result.code == 0 then
    return ok(true)
  end
  return with_conflicts(h, result)
end

function M.stash_apply(h, ref)
  local result = h:run({ "stash", "apply", ref })
  if result.code == 0 then
    return ok(ref)
  end
  return with_conflicts(h, result)
end

function M.stash_drop(h, ref)
  return from(h:run({ "stash", "drop", ref }), ref)
end

local function stash_index(ref)
  return tonumber(ref:match("{(%d+)}")) or 0
end

--- Drops highest index first: dropping an older stash never renumbers newer
--- ones, but dropping a newer one shifts every older index down. Always ok;
--- value is { dropped = {refs}, failed = {refs} } in drop order.
function M.stash_drop_many(h, refs)
  local ordered = vim.list_slice(refs)
  table.sort(ordered, function(a, b)
    return stash_index(a) > stash_index(b)
  end)
  local dropped, failed = {}, {}
  for _, ref in ipairs(ordered) do
    if h:run({ "stash", "drop", ref }).code == 0 then
      table.insert(dropped, ref)
    else
      table.insert(failed, ref)
    end
  end
  return ok({ dropped = dropped, failed = failed })
end

return M
