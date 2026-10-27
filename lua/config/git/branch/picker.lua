-- <M-b> git branch/worktree menu: pick "Branch" or "Worktree", then fuzzy
-- search all local+remote branches. Selecting an existing branch/worktree
-- switches to it; typing a name that matches nothing creates it.
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local themes = require("telescope.themes")
local menu_stack = require("config.ui.menu")
local identity = require("config.git.worktree.identity")
local palette = require("config.ui.palette")
local repo = require("config.git.repo")
local git_base_sync = require("config.git.branch.base_sync")
local ops = require("config.git.branch.ops")
local batch_remove = require("config.git.worktree.remove")
local remove_adapter = require("config.git.worktree.remove_adapter.telescope")

local M = {}

local WORKTREE_ICON = palette.ICON
local WORKTREE_HL = "GitBranchWorktree"

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

-- Stable partition: branches with a worktree checked out first, preserving
-- list_branches()'s existing relative order within each group. Only matters
-- for the picker's initial, empty-prompt display — see worktree_priority_sorter
-- for how this priority is preserved once the user starts typing.
local function worktrees_first(entries, worktree_map)
  local with_wt, without_wt = {}, {}
  for _, entry in ipairs(entries) do
    if worktree_map[entry.name] then
      table.insert(with_wt, entry)
    else
      table.insert(without_wt, entry)
    end
  end
  vim.list_extend(with_wt, without_wt)
  return with_wt
end

-- Wraps the stock fuzzy sorter so entries with a worktree checked out always
-- outrank entries without one, at any fuzzy-match quality, as long as both
-- still match the query. Telescope's generic_sorter re-scores every entry
-- against the prompt from scratch, which otherwise discards worktrees_first's
-- ordering the moment there's a query.
local function worktree_priority_sorter(worktree_map)
  local inner = conf.generic_sorter({})
  -- inner may be a stateful sorter (e.g. telescope-fzf-native, which caches
  -- a per-prompt parsed pattern and a native "slab" on self.state), so its
  -- init/start/destroy lifecycle has to be forwarded, not just scoring_function.
  return require("telescope.sorters").new({
    discard = inner.discard,
    init = function()
      inner:_init()
    end,
    start = function(_, prompt)
      inner:_start(prompt)
    end,
    finish = function(_, prompt)
      inner:_finish(prompt)
    end,
    destroy = function()
      inner:_destroy()
    end,
    scoring_function = function(_, prompt, line, entry)
      local score = inner:scoring_function(prompt, line, entry)
      if score == -1 then
        return -1
      end
      if worktree_map[entry.value.name] then
        return score
      end
      -- Offset guarantees any non-worktree score sorts below (worse than)
      -- every worktree score, regardless of fuzzy quality on either side.
      return score + 1e6
    end,
  })
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

local function branch_entry_maker(entry)
  local display = entry.name
  if not entry.is_local then
    display = display .. "  [remote]"
  end
  return {
    value = entry,
    display = display,
    ordinal = entry.name,
  }
end

-- Generic menu-of-labeled-actions picker with Esc-to-back support via
-- menu_stack (see that module for how "back" is threaded through).
local function pick_from(title, items, actions_by_label)
  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = title,
        finder = finders.new_table({ results = items }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if selection then
              actions_by_label[selection[1]]()
            end
          end)
          menu_stack.attach_back(map, prompt_bufnr)
          return true
        end,
      })
      :find()
end

-- Yes/No confirm via vim.ui.select (telescope-ui-select-backed). Unlike
-- pick_from/pick_entry/etc. this does NOT push onto menu_stack: "No"/Esc
-- just dismisses the dialog rather than reopening the previous screen.
local function confirm_picker(prompt, on_yes)
  vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
    if choice == "Yes" then
      on_yes()
    end
  end)
end

-- Free-text entry as a Telescope picker (replaces vim.ui.input) for the same
-- reason: consistent look, and Esc-to-back for free.
local function prompt_text(title, default, callback)
  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = title,
        default_text = default or "",
        finder = finders.new_table({ results = {} }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            local input = vim.trim(action_state.get_current_line())
            actions.close(prompt_bufnr)
            if input ~= "" then
              callback(input)
            end
          end)
          menu_stack.attach_back(map, prompt_bufnr)
          return true
        end,
      })
      :find()
end

-- Like prompt_text, but always calls back (with "" on empty input) instead
-- of treating empty as cancel — for prompts where "nothing typed" is itself
-- a valid choice (e.g. an optional stash message).
local function prompt_text_optional(title, default, callback)
  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = title,
        default_text = default or "",
        finder = finders.new_table({ results = {} }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            local input = vim.trim(action_state.get_current_line())
            actions.close(prompt_bufnr)
            callback(input)
          end)
          menu_stack.attach_back(map, prompt_bufnr)
          return true
        end,
      })
      :find()
end

-- Reuses the same branch listing as the switch/create picker, but only ever
-- resolves to a ref string: selecting an entry uses its name, typing text
-- uses that text verbatim, and accepting empty input falls back to HEAD.
-- It never creates a branch.
local function prompt_base_ref(callback)
  local head = current_head()
  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = "Base ref (empty = " .. head .. ")",
        default_text = head,
        finder = finders.new_table({
          results = list_branches(),
          entry_maker = branch_entry_maker,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            local prompt = vim.trim(action_state.get_current_line())
            actions.close(prompt_bufnr)

            if selection then
              callback(selection.value.name)
            elseif prompt ~= "" then
              callback(prompt)
            else
              callback(head)
            end
          end)
          menu_stack.attach_back(map, prompt_bufnr)
          return true
        end,
      })
      :find()
end

-- Select-only picker (no create-on-type) over an arbitrary entry list.
local function pick_entry(title, entries, entry_maker, callback)
  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = title,
        finder = finders.new_table({ results = entries, entry_maker = entry_maker }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if selection then
              callback(selection.value)
            end
          end)
          menu_stack.attach_back(map, prompt_bufnr)
          return true
        end,
      })
      :find()
end

-- Like pick_entry, but <Tab> toggles multi-selection (bufferline/Telescope's
-- usual convention). Enter calls back with the multi-selected values, or
-- falls back to the single highlighted entry when nothing was tab-toggled.
local function pick_entries_multi(title, entries, entry_maker, callback)
  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = title .. " (<Tab> to select multiple)",
        finder = finders.new_table({ results = entries, entry_maker = entry_maker }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          map({ "i", "n" }, "<Tab>", actions.toggle_selection + actions.move_selection_worse)
          actions.select_default:replace(function()
            local picker = action_state.get_current_picker(prompt_bufnr)
            local multi = picker:get_multi_selection()
            actions.close(prompt_bufnr)
            if #multi > 0 then
              local values = {}
              for _, entry in ipairs(multi) do
                table.insert(values, entry.value)
              end
              callback(values)
            else
              local selection = action_state.get_selected_entry()
              if selection then
                callback({ selection.value })
              end
            end
          end)
          menu_stack.attach_back(map, prompt_bufnr)
          return true
        end,
      })
      :find()
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

local function remove_worktree_action()
  local worktrees = vim.tbl_filter(function(wt)
    return not wt.is_main
  end, list_worktrees_ordered())

  pick_entries_multi("Remove Worktree", worktrees, function(wt)
    local name = vim.fs.basename(wt.path)
    return { value = wt, display = name, ordinal = name }
  end, function(selected)
    if #selected == 1 then
      return confirm_picker("Remove worktree at " .. selected[1].path .. "?", function()
        run_removal(selected)
      end)
    end
    local names = {}
    for _, wt in ipairs(selected) do
      table.insert(names, vim.fs.basename(wt.path))
    end
    confirm_picker("Remove " .. #selected .. " worktrees: " .. table.concat(names, ", ") .. "?", function()
      run_removal(selected)
    end)
  end)
end

-- Folders under .claude/worktrees/ that `git worktree list` no longer knows
-- about: left behind when Remove Worktree's `git worktree remove` deleted
-- the worktree's admin entry but couldn't clear the folder itself (typically
-- a Windows file lock). {path = ...}, matching the shape pick_entries_multi's
-- entry_maker expects.
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

local function prune_worktree_folders_action()
  local orphans = list_orphan_worktree_folders()
  if #orphans == 0 then
    vim.notify("No orphaned worktree folders")
    return
  end

  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = "Prune Worktree Folders (<Tab> to toggle)",
        finder = finders.new_table({
          results = orphans,
          entry_maker = function(o)
            local name = vim.fs.basename(o.path)
            return { value = o, display = name, ordinal = name }
          end,
        }),
        sorter = conf.generic_sorter({}),
        on_complete = {
          function(picker)
            actions.select_all(picker.prompt_bufnr)
          end,
        },
        attach_mappings = function(prompt_bufnr, map)
          map({ "i", "n" }, "<Tab>", actions.toggle_selection + actions.move_selection_worse)
          actions.select_default:replace(function()
            local picker = action_state.get_current_picker(prompt_bufnr)
            local multi = picker:get_multi_selection()
            actions.close(prompt_bufnr)
            local selected = {}
            if #multi > 0 then
              for _, entry in ipairs(multi) do
                table.insert(selected, entry.value)
              end
            else
              local selection = action_state.get_selected_entry()
              if selection then
                table.insert(selected, selection.value)
              end
            end
            if #selected == 0 then
              return
            end

            local names = {}
            for _, o in ipairs(selected) do
              table.insert(names, vim.fs.basename(o.path))
            end
            confirm_picker("Prune " .. #selected .. " worktree folder(s): " .. table.concat(names, ", ") .. "?",
              function()
                run_removal(selected)
              end)
          end)
          menu_stack.attach_back(map, prompt_bufnr)
          return true
        end,
      })
      :find()
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

local function delete_branch_action()
  pick_entries_multi("Delete Branch", list_local_branches(), branch_entry_maker, function(selected)
    -- Single selection keeps the interactive force-delete prompt. Batch
    -- delete skips per-item prompts and reports which ones need a manual
    -- force-delete, same as the worktree removal flow.
    if #selected == 1 then
      local entry = selected[1]
      confirm_picker("Delete branch " .. entry.name .. "?", function()
        local busy = repo.busy.start("deleting " .. entry.name)
        delete_branch_async(entry, false, function(result)
          repo.busy.stop(busy)
          if result.ok then
            return
          end
          vim.notify("git branch -d failed: " .. result.err, vim.log.levels.ERROR)
          confirm_picker(entry.name .. " is not fully merged. Force delete?", function()
            local force_busy = repo.busy.start("deleting " .. entry.name)
            delete_branch_async(entry, true, function(force_result)
              repo.busy.stop(force_busy)
              if not force_result.ok then
                vim.notify("git branch -D failed: " .. force_result.err, vim.log.levels.ERROR)
              end
            end)
          end)
        end)
      end)
      return
    end

    local names = {}
    for _, entry in ipairs(selected) do
      table.insert(names, entry.name)
    end
    confirm_picker("Delete " .. #selected .. " branches: " .. table.concat(names, ", ") .. "?", function()
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
    end)
  end)
end

local function rename_branch_action()
  local open_list
  open_list = function()
    pick_entry("Rename Branch", list_local_branches(), branch_entry_maker, function(entry)
      menu_stack.push(open_list)
      prompt_text("New name for " .. entry.name, entry.name, function(input)
        local new_name = input:gsub(" ", "-")
        local h = open_repo()
        report(h and ops.rename(h, entry.name, new_name) or NOT_A_REPO, "git branch -m failed",
          "Renamed branch " .. entry.name .. " to " .. new_name)
      end)
    end)
  end
  open_list()
end

local function merge_branch_action()
  pick_entry("Merge into " .. current_head(), list_branches(), branch_entry_maker, function(entry)
    local h = open_repo()
    local result = h and ops.merge(h, entry) or NOT_A_REPO
    if result.ok then
      vim.notify("Merged " .. result.value .. " into " .. current_head())
    elseif not report_conflicts(result, "Merge") then
      report(result, "git merge failed")
    end
  end)
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

local function list_stashes()
  local h = open_repo()
  return h and h:stashes() or {}
end

local function stash_entry_maker(entry)
  return { value = entry, display = entry.raw, ordinal = entry.raw }
end

-- git status --porcelain, tracked + untracked; for renames, keeps the new
-- path since that's what a pathspec needs to match.
local function list_changed_files()
  local h = open_repo()
  return h and h:status() or {}
end

local function file_entry_maker(entry)
  local display = entry.status .. "  " .. entry.path
  return { value = entry, display = display, ordinal = entry.path }
end

-- Shared by Pop/Apply: both can fail with merge-style conflicts, handled the
-- same way as merge_branch_action.
local function handle_stash_result(result, action_label, success_msg)
  if result.ok then
    vim.notify(success_msg)
  elseif not report_conflicts(result, action_label) then
    report(result, action_label .. " failed")
  end
end

local function stash_push_all()
  prompt_text_optional("Stash message (optional)", "", function(message)
    local h = open_repo()
    local result = h and ops.stash_push(h, { message = message }) or NOT_A_REPO
    if report(result, "git stash push failed") then
      vim.notify(result.value.saved and "Stashed changes" or "No local changes to stash")
    end
  end)
end

local function stash_push_selected()
  local open_files
  open_files = function()
    pick_entries_multi("Stash Files", list_changed_files(), file_entry_maker, function(selected)
      menu_stack.push(open_files)
      prompt_text_optional("Stash message (optional)", "", function(message)
        local files = {}
        for _, entry in ipairs(selected) do
          table.insert(files, entry.path)
        end
        local h = open_repo()
        report(h and ops.stash_push(h, { message = message, files = files }) or NOT_A_REPO,
          "git stash push failed", "Stashed " .. #selected .. " file(s)")
      end)
    end)
  end
  open_files()
end

local function stash_pop_action()
  local h = open_repo()
  handle_stash_result(h and ops.stash_pop(h) or NOT_A_REPO, "git stash pop", "Popped stash")
end

local function stash_apply_action()
  pick_entry("Apply Stash", list_stashes(), stash_entry_maker, function(entry)
    local h = open_repo()
    handle_stash_result(h and ops.stash_apply(h, entry.ref) or NOT_A_REPO, "git stash apply", "Applied " .. entry.ref)
  end)
end

local function stash_drop_action()
  pick_entries_multi("Drop Stash", list_stashes(), stash_entry_maker, function(selected)
    if #selected == 1 then
      local entry = selected[1]
      confirm_picker("Drop " .. entry.raw .. "?", function()
        local h = open_repo()
        report(h and ops.stash_drop(h, entry.ref) or NOT_A_REPO, "git stash drop failed", "Dropped " .. entry.ref)
      end)
      return
    end

    local refs = {}
    for _, entry in ipairs(selected) do
      table.insert(refs, entry.ref)
    end
    confirm_picker("Drop " .. #selected .. " stashes: " .. table.concat(refs, ", ") .. "?", function()
      local h = open_repo()
      if not h then
        return report(NOT_A_REPO, "git stash drop failed")
      end
      local failed = ops.stash_drop_many(h, refs).value.failed
      if #failed > 0 then
        vim.notify("Failed to drop: " .. table.concat(failed, ", "), vim.log.levels.WARN)
      end
    end)
  end)
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

local handle_new

local function open_picker(mode)
  local worktree_map = list_worktrees()
  local entries = worktrees_first(list_branches(), worktree_map)

  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = mode == "branch" and "Switch/Create Branch" or "Switch/Create Worktree",
        finder = finders.new_table({
          results = entries,
          entry_maker = function(entry)
            local made = branch_entry_maker(entry)
            local wt_path = worktree_map[entry.name]
            if wt_path then
              local wt_name = identity.name_differs(wt_path, entry.name)
              if wt_name then
                made.display = wt_name .. ":" .. made.display
                made.ordinal = wt_name .. " " .. made.ordinal
              end
            end
            if mode == "worktree" and wt_path then
              made.display = made.display .. "  (" .. wt_path .. ")"
            end
            if wt_path then
              local text = WORKTREE_ICON .. " " .. made.display
              made.display = function()
                return text, { { { 0, #text }, WORKTREE_HL } }
              end
            end
            return made
          end,
        }),
        sorter = worktree_priority_sorter(worktree_map),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            local prompt = vim.trim(action_state.get_current_line())
            actions.close(prompt_bufnr)

            if selection then
              handle_existing(mode, selection.value)
            elseif prompt ~= "" then
              handle_new(mode, prompt)
            end
          end)
          menu_stack.attach_back(map, prompt_bufnr)
          return true
        end,
      })
      :find()
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

handle_new = function(mode, name)
  name = name:gsub(" ", "-")
  local function reopen()
    open_picker(mode)
  end
  menu_stack.push(reopen)
  if mode == "branch" then
    prompt_base_ref(function(base)
      create_from_fresh_base(base, function(start)
        create_and_switch_branch(name, start)
      end)
    end)
  else
    prompt_base_ref(function(base)
      create_from_fresh_base(base, function(start)
        create_worktree_new_branch(name, start)
      end)
    end)
  end
end

local function link_worktree_hl()
  vim.api.nvim_set_hl(0, WORKTREE_HL, palette.HL)
end

local open_branch_submenu, open_worktree_submenu, open_stash_submenu, pick_mode

local branch_submenu_order = { "Switch/Create", "Delete", "Rename", "Merge" }
local branch_submenu_actions = {
  ["Switch/Create"] = function()
    menu_stack.push(open_branch_submenu)
    open_picker("branch")
  end,
  ["Delete"] = function()
    menu_stack.push(open_branch_submenu)
    delete_branch_action()
  end,
  ["Rename"] = function()
    menu_stack.push(open_branch_submenu)
    rename_branch_action()
  end,
  ["Merge"] = function()
    menu_stack.push(open_branch_submenu)
    merge_branch_action()
  end,
}

open_branch_submenu = function()
  pick_from("Branch", branch_submenu_order, branch_submenu_actions)
end

local worktree_submenu_order = { "Switch/Create", "Remove", "Prune" }
local worktree_submenu_actions = {
  ["Switch/Create"] = function()
    menu_stack.push(open_worktree_submenu)
    open_picker("worktree")
  end,
  ["Remove"] = function()
    menu_stack.push(open_worktree_submenu)
    remove_worktree_action()
  end,
  ["Prune"] = function()
    menu_stack.push(open_worktree_submenu)
    prune_worktree_folders_action()
  end,
}

open_worktree_submenu = function()
  pick_from("Worktree", worktree_submenu_order, worktree_submenu_actions)
end

local stash_submenu_order = { "Push", "Push (Select Files)", "Pop", "Apply", "Drop" }
local stash_submenu_actions = {
  ["Push"] = function()
    menu_stack.push(open_stash_submenu)
    stash_push_all()
  end,
  ["Push (Select Files)"] = function()
    menu_stack.push(open_stash_submenu)
    stash_push_selected()
  end,
  ["Pop"] = function()
    menu_stack.push(open_stash_submenu)
    stash_pop_action()
  end,
  ["Apply"] = function()
    menu_stack.push(open_stash_submenu)
    stash_apply_action()
  end,
  ["Drop"] = function()
    menu_stack.push(open_stash_submenu)
    stash_drop_action()
  end,
}

open_stash_submenu = function()
  pick_from("Stash", stash_submenu_order, stash_submenu_actions)
end

local mode_order = { "Branch", "Worktree", "Stash", "Push", "Pull" }
local mode_actions = {
  ["Branch"] = function()
    menu_stack.push(pick_mode)
    open_branch_submenu()
  end,
  ["Worktree"] = function()
    menu_stack.push(pick_mode)
    open_worktree_submenu()
  end,
  ["Stash"] = function()
    menu_stack.push(pick_mode)
    open_stash_submenu()
  end,
  ["Push"] = push_current,
  ["Pull"] = pull_current,
}

pick_mode = function()
  menu_stack.reset()
  pick_from("Git", mode_order, mode_actions)
end

M.setup = function()
  link_worktree_hl()
  vim.api.nvim_create_autocmd("ColorScheme", {
    desc = "Re-derive git branch/worktree picker highlight for the new colorscheme",
    callback = link_worktree_hl,
  })

  vim.keymap.set("n", "<M-b>", pick_mode, { desc = "Git branch/worktree menu" })

  vim.keymap.set("n", "<leader>bb", function()
    menu_stack.reset()
    open_picker("branch")
  end, { desc = "Switch/create git branch" })

  vim.keymap.set("n", "<leader>bw", function()
    menu_stack.reset()
    open_picker("worktree")
  end, { desc = "Switch/create git worktree" })

  vim.keymap.set("n", "<leader>bp", pull_current, { desc = "Git pull" })
  vim.keymap.set("n", "<leader>bP", push_current, { desc = "Git push" })
end

return M
