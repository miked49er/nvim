-- <M-b> git branch/worktree menu, declared with config.ui.menu: navigation
-- (push and back) is handled by the menu module and rendering by its adapter.
-- Branch, stash and worktree actions below are plain callbacks. Selecting an
-- existing branch/worktree switches to it; typing a name that matches nothing
-- creates it.
local menu = require("config.ui.menu")
local identity = require("config.git.worktree.identity")
local entries = require("config.git.branch.entries")
local palette = require("config.ui.palette")
local repo = require("config.git.repo")
local git_base_sync = require("config.git.branch.base_sync")
local ops = require("config.git.branch.ops")
local batch_remove = require("config.git.worktree.remove")
local remove_adapter = require("config.git.worktree.remove_adapter.telescope")

local M = {}

local WORKTREE_ICON = palette.ICON
local WORKTREE_HL = "GitBranchWorktree"

-- Overridable for headless specs (see config.ui.menu_adapter.scripted).
local adapter = nil

function M.set_adapter(a)
  adapter = a
end

local function open_menu(decl)
  menu.open(decl, { adapter = adapter })
end

-- A repo handle is opened per call for the current directory; nil outside a
-- repository.
local function open_repo()
  return repo.open(vim.fn.getcwd())
end

local function notify_err(prefix, result)
  vim.notify(prefix .. ": " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
end

local function current_head()
  local h = open_repo()
  return h and h:head() or "HEAD"
end

-- Shared across all worktrees of this repo, unlike the checkout root which
-- is whichever worktree you happen to be sitting in.
local function repo_root()
  local h = open_repo()
  return h and h.main_root or nil
end

local function list_branches()
  local h = open_repo()
  return h and h:branches() or {}
end

-- Ordered list of {path, branch, is_main}; the first entry is always the
-- main worktree.
local function list_worktrees_ordered()
  local h = open_repo()
  return h and h:worktrees() or {}
end

local function list_worktrees()
  local map = {}
  for _, wt in ipairs(list_worktrees_ordered()) do
    if wt.branch then
      map[wt.branch] = wt.path
    end
  end
  return map
end

local function list_local_branches()
  return vim.tbl_filter(function(entry)
    return entry.is_local
  end, list_branches())
end

local function worktree_path_for(branch)
  local root = repo_root()
  if not root then
    return nil
  end
  return identity.path_for(root, branch)
end

local function open_worktree_tab(path)
  vim.cmd("tabnew")
  vim.cmd("tcd " .. vim.fn.fnameescape(path))
  vim.notify("Worktree: " .. path)
end

local branch_entry = entries.branch

local function dir_entry(item)
  local name = vim.fs.basename(item.path)
  return { display = name, ordinal = name }
end

local function stash_entry(entry)
  return { display = entry.raw, ordinal = entry.raw }
end

local function file_entry(entry)
  return { display = entry.status .. "  " .. entry.path, ordinal = entry.path }
end

local function join(list, name_of)
  local out = {}
  for _, item in ipairs(list) do
    table.insert(out, name_of(item))
  end
  return table.concat(out, ", ")
end

local function confirm(title, on_yes)
  return { kind = "confirm", title = title, on_yes = on_yes }
end

-- Reports an ops result: notifies the error on failure, otherwise the success
-- message (a string, or a function of the result value). Returns true on success.
local function report(result, fail_prefix, ok_msg)
  if not result.ok then
    vim.notify(fail_prefix .. ": " .. result.err, vim.log.levels.ERROR)
    return false
  end
  if ok_msg then
    vim.notify(type(ok_msg) == "function" and ok_msg(result.value) or ok_msg)
  end
  return true
end

-- Merge-style failures that left unmerged files fall back to the diff tool.
local function report_conflicts(result, label)
  if result.conflicts then
    vim.notify(label .. " conflicts in " .. #result.conflicts .. " file(s); opening changes panel", vim.log.levels.WARN)
    require("diffbandit").commit_panel()
    return true
  end
  return false
end

local NOT_A_REPO = { ok = false, err = "fatal: not a git repository" }

local function switch_branch(name)
  local h = open_repo()
  report(h and ops.switch(h, name) or NOT_A_REPO, "git switch failed", "Switched to branch " .. name)
end

local function checkout_remote_tracking(name, remote)
  local h = open_repo()
  report(h and ops.track_remote(h, name, remote) or NOT_A_REPO, "git switch failed", "Switched to branch " .. name)
end

local function create_and_switch_branch(name, base)
  local h = open_repo()
  report(h and ops.create(h, name, base) or NOT_A_REPO, "git switch -c failed",
    "Created and switched to branch " .. name)
end

local function create_worktree_new_branch(name, base)
  local h = open_repo()
  local path = worktree_path_for(name)
  if not (h and path) then
    vim.notify("Could not resolve repo root", vim.log.levels.ERROR)
    return
  end
  if report(ops.worktree_add_new(h, path, name, base), "git worktree add failed") then
    open_worktree_tab(path)
  end
end

local function create_worktree_for_branch(entry)
  local h = open_repo()
  local path = worktree_path_for(entry.name)
  if not (h and path) then
    vim.notify("Could not resolve repo root", vim.log.levels.ERROR)
    return
  end
  if report(ops.worktree_add_existing(h, path, entry), "git worktree add failed") then
    open_worktree_tab(path)
  end
end

-- Reports a removal result: notifications live here, removal itself lives in
-- config.git.worktree.remove.
local function report_removal(res)
  for _, wt in ipairs(res.removed) do
    vim.notify("Removed " .. (wt.orphan and "worktree folder " or "worktree ") .. wt.path)
  end
  for _, f in ipairs(res.failed) do
    notify_err(f.wt.orphan and "Folder removal failed" or "git worktree remove failed", f.result)
  end
end

local function run_removal(selection)
  batch_remove.run(selection, remove_adapter, report_removal)
end

-- Folders under .claude/worktrees/ that `git worktree list` no longer knows
-- about: left behind when Remove Worktree's `git worktree remove` deleted
-- the worktree's admin entry but couldn't clear the folder itself (typically
-- a Windows file lock). {path = ...}, matching the removal selection shape.
local function list_orphan_worktree_folders()
  local root = repo_root()
  if not root then
    return {}
  end
  local base = identity.base_dir(root)
  if vim.fn.isdirectory(base) == 0 then
    return {}
  end
  local active = {}
  for _, wt in ipairs(list_worktrees_ordered()) do
    active[vim.fs.normalize(wt.path)] = true
  end
  local orphans = {}
  for name, kind in vim.fs.dir(base) do
    if kind == "directory" then
      local path = vim.fs.joinpath(base, name)
      if not active[vim.fs.normalize(path)] then
        table.insert(orphans, { path = path, orphan = true })
      end
    end
  end
  return orphans
end

-- Async: on_done(result) runs whether or not the delete succeeded; success
-- notification fires here since every caller wants it.
local function delete_branch_async(entry, force, on_done)
  local h = open_repo()
  if not h then
    return vim.schedule(function()
      on_done(NOT_A_REPO)
    end)
  end
  ops.delete_async(h, entry.name, { force = force }, function(result)
    if result.ok then
      vim.notify("Deleted branch " .. entry.name)
    end
    on_done(result)
  end)
end

local function list_stashes()
  local h = open_repo()
  return h and h:stashes() or {}
end

-- git status --porcelain, tracked + untracked; for renames, keeps the new
-- path since that's what a pathspec needs to match.
local function list_changed_files()
  local h = open_repo()
  return h and h:status() or {}
end

-- Shared by Pop/Apply: both can fail with merge-style conflicts, handled the
-- same way as merge.
local function handle_stash_result(result, action_label, success_msg)
  if result.ok then
    vim.notify(success_msg)
  elseif not report_conflicts(result, action_label) then
    report(result, action_label .. " failed")
  end
end

local function push_current()
  local h = open_repo()
  report(h and ops.push(h) or NOT_A_REPO, "git push failed", function(branch)
    return "Pushed " .. branch
  end)
end

local function pull_current()
  local h = open_repo()
  report(h and ops.pull(h) or NOT_A_REPO, "git pull failed", function(branch)
    return "Pulled " .. branch
  end)
end

-- Async-updates the base from its remote (busy guard shown meanwhile), warns
-- if the branch may start behind the remote, then calls create(start_ref).
local function create_from_fresh_base(base, create)
  local busy = repo.busy.start("updating " .. base)
  git_base_sync.prepare(base, function(start, warning)
    repo.busy.stop(busy)
    if warning then
      vim.notify(warning, vim.log.levels.WARN)
    end
    create(start)
  end)
end

---------------------------------------------------------------------------
-- Screens (declarations; functions are re-evaluated on every show)
---------------------------------------------------------------------------

-- Resolves to a ref string: selecting an entry uses its name, typing text uses
-- that text verbatim, and accepting empty input falls back to HEAD. It never
-- creates a branch.
local function base_ref_prompt(callback)
  return function()
    local head = current_head()
    return {
      kind = "choose_one",
      title = "Base ref (empty = " .. head .. ")",
      default_text = head,
      items = list_branches(),
      entry = branch_entry,
      on_select = function(entry)
        callback(entry.name)
      end,
      on_input = function(text)
        callback(text ~= "" and text or head)
      end,
    }
  end
end

local function handle_existing(mode, entry)
  if mode == "branch" then
    if entry.is_local then
      switch_branch(entry.name)
    else
      checkout_remote_tracking(entry.name, entry.remote)
    end
    return
  end

  local worktree_path = list_worktrees()[entry.name]
  if worktree_path then
    open_worktree_tab(worktree_path)
  else
    create_worktree_for_branch(entry)
  end
end

local function handle_new(mode, name, ctx)
  name = name:gsub(" ", "-")
  ctx.open(base_ref_prompt(function(base)
    create_from_fresh_base(base, function(start)
      if mode == "branch" then
        create_and_switch_branch(name, start)
      else
        create_worktree_new_branch(name, start)
      end
    end)
  end))
end

-- Fuzzy search over all local+remote branches, worktree branches first.
local function switch_create(mode)
  return function()
    local worktree_map = list_worktrees()
    return {
      kind = "choose_one",
      title = mode == "branch" and "Switch/Create Branch" or "Switch/Create Worktree",
      items = entries.order(list_branches(), worktree_map),
      prefer = entries.prefers(worktree_map),
      entry = function(entry)
        local made = entries.describe(entry, worktree_map, mode)
        if made.worktree then
          made.icon = WORKTREE_ICON
          made.hl = WORKTREE_HL
        end
        return made
      end,
      on_select = function(entry)
        handle_existing(mode, entry)
      end,
      on_input = function(text, ctx)
        if text ~= "" then
          handle_new(mode, text, ctx)
        end
      end,
    }
  end
end

local function delete_branch_screen()
  return {
    kind = "choose_many",
    title = "Delete Branch",
    items = list_local_branches(),
    entry = branch_entry,
    on_select = function(selected, ctx)
      -- Single selection keeps the interactive force-delete prompt. Batch
      -- delete skips per-item prompts and reports which ones need a manual
      -- force-delete, same as the worktree removal flow.
      if #selected == 1 then
        local entry = selected[1]
        return ctx.open(confirm("Delete branch " .. entry.name .. "?", function()
          local busy = repo.busy.start("deleting " .. entry.name)
          delete_branch_async(entry, false, function(result)
            repo.busy.stop(busy)
            if result.ok then
              return
            end
            vim.notify("git branch -d failed: " .. result.err, vim.log.levels.ERROR)
            ctx.open(confirm(entry.name .. " is not fully merged. Force delete?", function()
              local force_busy = repo.busy.start("deleting " .. entry.name)
              delete_branch_async(entry, true, function(force_result)
                repo.busy.stop(force_busy)
                if not force_result.ok then
                  vim.notify("git branch -D failed: " .. force_result.err, vim.log.levels.ERROR)
                end
              end)
            end))
          end)
        end))
      end

      local names = join(selected, function(e) return e.name end)
      ctx.open(confirm("Delete " .. #selected .. " branches: " .. names .. "?", function()
        local failed = {}
        local remaining = #selected
        local busy = repo.busy.start("deleting " .. #selected .. " branches")
        for _, entry in ipairs(selected) do
          delete_branch_async(entry, false, function(result)
            if not result.ok then
              table.insert(failed, entry.name)
            end
            remaining = remaining - 1
            if remaining == 0 then
              repo.busy.stop(busy)
              if #failed > 0 then
                vim.notify(
                  "Not fully merged, delete individually to force: " .. table.concat(failed, ", "),
                  vim.log.levels.WARN
                )
              end
            end
          end)
        end
      end))
    end,
  }
end

local function rename_branch_screen()
  return {
    kind = "choose_one",
    title = "Rename Branch",
    items = list_local_branches(),
    entry = branch_entry,
    on_select = function(entry, ctx)
      ctx.open({
        kind = "text",
        title = "New name for " .. entry.name,
        default = entry.name,
        on_submit = function(input)
          local new_name = input:gsub(" ", "-")
          local h = open_repo()
          report(h and ops.rename(h, entry.name, new_name) or NOT_A_REPO, "git branch -m failed",
            "Renamed branch " .. entry.name .. " to " .. new_name)
        end,
      })
    end,
  }
end

local function merge_branch_screen()
  return {
    kind = "choose_one",
    title = "Merge into " .. current_head(),
    items = list_branches(),
    entry = branch_entry,
    on_select = function(entry)
      local h = open_repo()
      local result = h and ops.merge(h, entry) or NOT_A_REPO
      if result.ok then
        vim.notify("Merged " .. result.value .. " into " .. current_head())
      elseif not report_conflicts(result, "Merge") then
        report(result, "git merge failed")
      end
    end,
  }
end

local function remove_worktree_screen()
  return {
    kind = "choose_many",
    title = "Remove Worktree",
    items = vim.tbl_filter(function(wt)
      return not wt.is_main
    end, list_worktrees_ordered()),
    entry = dir_entry,
    on_select = function(selected, ctx)
      if #selected == 1 then
        return ctx.open(confirm("Remove worktree at " .. selected[1].path .. "?", function()
          run_removal(selected)
        end))
      end
      local names = join(selected, function(wt) return vim.fs.basename(wt.path) end)
      ctx.open(confirm("Remove " .. #selected .. " worktrees: " .. names .. "?", function()
        run_removal(selected)
      end))
    end,
  }
end

local function prune_worktree_folders_screen()
  return {
    kind = "choose_many",
    title = "Prune Worktree Folders",
    hint = " (<Tab> to toggle)",
    items = list_orphan_worktree_folders(),
    preselect_all = true,
    entry = dir_entry,
    on_select = function(selected, ctx)
      local names = join(selected, function(o) return vim.fs.basename(o.path) end)
      ctx.open(confirm("Prune " .. #selected .. " worktree folder(s): " .. names .. "?", function()
        run_removal(selected)
      end))
    end,
  }
end

local function stash_message_prompt(on_submit)
  return {
    kind = "text",
    title = "Stash message (optional)",
    default = "",
    allow_empty = true,
    on_submit = on_submit,
  }
end

local function stash_push_all_screen()
  return stash_message_prompt(function(message)
    local h = open_repo()
    local result = h and ops.stash_push(h, { message = message }) or NOT_A_REPO
    if report(result, "git stash push failed") then
      vim.notify(result.value.saved and "Stashed changes" or "No local changes to stash")
    end
  end)
end

local function stash_push_selected_screen()
  return {
    kind = "choose_many",
    title = "Stash Files",
    items = list_changed_files(),
    entry = file_entry,
    on_select = function(selected, ctx)
      ctx.open(stash_message_prompt(function(message)
        local files = {}
        for _, entry in ipairs(selected) do
          table.insert(files, entry.path)
        end
        local h = open_repo()
        report(h and ops.stash_push(h, { message = message, files = files }) or NOT_A_REPO,
          "git stash push failed", "Stashed " .. #selected .. " file(s)")
      end))
    end,
  }
end

local function stash_apply_screen()
  return {
    kind = "choose_one",
    title = "Apply Stash",
    items = list_stashes(),
    entry = stash_entry,
    on_select = function(entry)
      local h = open_repo()
      handle_stash_result(h and ops.stash_apply(h, entry.ref) or NOT_A_REPO, "git stash apply", "Applied " .. entry.ref)
    end,
  }
end

local function stash_drop_screen()
  return {
    kind = "choose_many",
    title = "Drop Stash",
    items = list_stashes(),
    entry = stash_entry,
    on_select = function(selected, ctx)
      if #selected == 1 then
        local entry = selected[1]
        return ctx.open(confirm("Drop " .. entry.raw .. "?", function()
          local h = open_repo()
          report(h and ops.stash_drop(h, entry.ref) or NOT_A_REPO, "git stash drop failed", "Dropped " .. entry.ref)
        end))
      end

      local refs = {}
      for _, entry in ipairs(selected) do
        table.insert(refs, entry.ref)
      end
      ctx.open(confirm("Drop " .. #selected .. " stashes: " .. table.concat(refs, ", ") .. "?", function()
        local h = open_repo()
        if not h then
          return report(NOT_A_REPO, "git stash drop failed")
        end
        local failed = ops.stash_drop_many(h, refs).value.failed
        if #failed > 0 then
          vim.notify("Failed to drop: " .. table.concat(failed, ", "), vim.log.levels.WARN)
        end
      end))
    end,
  }
end

local function branch_menu()
  return {
    kind = "menu",
    title = "Branch",
    items = {
      { label = "Switch/Create", open = switch_create("branch") },
      { label = "Delete", open = delete_branch_screen },
      { label = "Rename", open = rename_branch_screen },
      { label = "Merge", open = merge_branch_screen },
    },
  }
end

local function worktree_menu()
  return {
    kind = "menu",
    title = "Worktree",
    items = {
      { label = "Switch/Create", open = switch_create("worktree") },
      { label = "Remove", open = remove_worktree_screen },
      {
        label = "Prune",
        run = function(ctx)
          if #list_orphan_worktree_folders() == 0 then
            vim.notify("No orphaned worktree folders")
            return
          end
          ctx.open(prune_worktree_folders_screen)
        end,
      },
    },
  }
end

local function stash_menu()
  return {
    kind = "menu",
    title = "Stash",
    items = {
      { label = "Push", open = stash_push_all_screen },
      { label = "Push (Select Files)", open = stash_push_selected_screen },
      {
        label = "Pop",
        run = function()
          local h = open_repo()
          handle_stash_result(h and ops.stash_pop(h) or NOT_A_REPO, "git stash pop", "Popped stash")
        end,
      },
      { label = "Apply", open = stash_apply_screen },
      { label = "Drop", open = stash_drop_screen },
    },
  }
end

local function root_menu()
  return {
    kind = "menu",
    title = "Git",
    items = {
      { label = "Branch", open = branch_menu },
      { label = "Worktree", open = worktree_menu },
      { label = "Stash", open = stash_menu },
      { label = "Push", run = push_current },
      { label = "Pull", run = pull_current },
    },
  }
end

---------------------------------------------------------------------------
-- Public entry points (bound in config.keymaps)
---------------------------------------------------------------------------

function M.open_menu()
  open_menu(root_menu)
end

function M.switch_create_branch()
  open_menu(switch_create("branch"))
end

function M.switch_create_worktree()
  open_menu(switch_create("worktree"))
end

M.push = push_current
M.pull = pull_current

local function link_worktree_hl()
  vim.api.nvim_set_hl(0, WORKTREE_HL, palette.HL)
end

M.setup = function()
  link_worktree_hl()
  vim.api.nvim_create_autocmd("ColorScheme", {
    desc = "Re-derive git branch/worktree picker highlight for the new colorscheme",
    callback = link_worktree_hl,
  })
end

return M
