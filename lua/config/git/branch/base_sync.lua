-- Brings a base branch up to date with its remote before a new branch is cut
-- from it. Fully async (vim.system callbacks) so the editor never freezes.
--
-- prepare(base, on_done): on_done(start_ref, warning) runs on the main loop.
--   1. fetch the base from its remote
--   2. fast-forward the local base (ff-only); on success start_ref = base
--   3. else (diverged / checked out in another worktree / no upstream)
--      start_ref = "<remote>/<base>"
--   4. else (e.g. offline) start_ref = base and warning is set
-- The remote is branch.<base>.remote when configured (intentional: a base
-- tracking e.g. "upstream" is synced from there), else "origin".
-- Remote-tracking bases ("origin/main") are fetched, then passed through.
-- Other bases (tags, HEAD) pass through untouched.
local branch_cache = require("config.git.branch.cache")

local M = {}

local function git(args, on_done)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true, cwd = vim.fn.getcwd() }, function(result)
    vim.schedule(function()
      branch_cache.invalidate()
      on_done(result)
    end)
  end)
end

function M.prepare(base, on_done)
  local function stale_warning(why)
    return "Branch may be behind the remote (" .. why .. "); created from local '" .. base .. "'"
  end

  git({ "rev-parse", "--verify", "--quiet", "refs/heads/" .. base }, function(is_local)
    if is_local.code ~= 0 then
      -- A remote-tracking ref (e.g. "origin/main") has no local branch to
      -- fast-forward, but is still fetched so the new branch starts at the
      -- remote's tip.
      local remote, branch = base:match("^([^/]+)/(.+)$")
      if not remote then
        return on_done(base, nil)
      end
      return git({ "rev-parse", "--verify", "--quiet", "refs/remotes/" .. base }, function(is_remote)
        if is_remote.code ~= 0 then
          return on_done(base, nil)
        end
        git({ "fetch", remote, branch }, function(fetched)
          if fetched.code ~= 0 then
            return on_done(base, "Branch may be behind the remote (fetch failed); created from '" .. base .. "'")
          end
          on_done(base, nil)
        end)
      end)
    end
    git({ "config", "--get", "branch." .. base .. ".remote" }, function(cfg)
      local remote = vim.trim(cfg.stdout or "")
      if cfg.code ~= 0 or remote == "" or remote == "." then
        remote = "origin"
      end
      local remote_ref = remote .. "/" .. base

      git({ "fetch", remote, base }, function(fetched)
        if fetched.code ~= 0 then
          return on_done(base, stale_warning("fetch failed"))
        end

        local function fall_back_to_remote_ref()
          git({ "rev-parse", "--verify", "--quiet", "refs/remotes/" .. remote_ref }, function(r)
            if r.code == 0 then
              on_done(remote_ref, nil)
            else
              on_done(base, stale_warning("could not update from " .. remote_ref))
            end
          end)
        end

        local function done_if_ok(r)
          if r.code == 0 then
            on_done(base, nil)
          else
            fall_back_to_remote_ref()
          end
        end

        git({ "rev-parse", "--abbrev-ref", "HEAD" }, function(head)
          if vim.trim(head.stdout or "") == base then
            git({ "merge", "--ff-only", "refs/remotes/" .. remote_ref }, done_if_ok)
          else
            -- Fetching into a local branch is ff-only and refuses a branch
            -- checked out in any worktree.
            git({ "fetch", ".", "refs/remotes/" .. remote_ref .. ":refs/heads/" .. base }, done_if_ok)
          end
        end)
      end)
    end)
  end)
end

return M
