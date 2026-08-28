-- <M-b> git branch/worktree menu: pick "Branch" or "Worktree", then fuzzy
-- search all local+remote branches. Selecting an existing branch/worktree
-- switches to it; typing a name that matches nothing creates it.
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local themes = require("telescope.themes")
local menu_stack = require("config.telescope.menu_stack")
local worktree = require("config.worktree")

local M = {}

local WORKTREE_ICON = worktree.ICON
local WORKTREE_HL = "GitBranchWorktree"

local function git(args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { text = true, cwd = vim.fn.getcwd() }):wait()
end

local function git_lines(args)
  local result = git(args)
  if result.code ~= 0 then
    return {}
  end
  return vim.split(result.stdout or "", "\n", { trimempty = true })
end

local function notify_err(prefix, result)
  vim.notify(prefix .. ": " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
end

local function current_head()
  return git_lines({ "rev-parse", "--abbrev-ref", "HEAD" })[1] or "HEAD"
end

-- Shared across all worktrees of this repo, unlike --show-toplevel which
-- returns whichever worktree's own root you happen to be sitting in.
local function repo_root()
  local common_dir = git_lines({ "rev-parse", "--path-format=absolute", "--git-common-dir" })[1]
  if not common_dir then
    return nil
  end
  return vim.fs.dirname(common_dir)
end

local function list_branches()
  local locals = git_lines({ "branch", "--format=%(refname:short)" })
  local locals_set = {}
  local entries = {}
  for _, name in ipairs(locals) do
    locals_set[name] = true
    table.insert(entries, { name = name, is_local = true })
  end

  local remotes = git_lines({ "branch", "-r", "--format=%(refname:short)" })
  for _, remote in ipairs(remotes) do
    if not remote:match("/HEAD$") then
      local short = remote:gsub("^[^/]+/", "")
      if not locals_set[short] then
        table.insert(entries, { name = short, is_local = false, remote = remote })
      end
    end
  end
  return entries
end

-- Ordered list of {path, branch, is_main}; the first block from
-- `git worktree list --porcelain` is always the main worktree.
local function list_worktrees_ordered()
  local result = git({ "worktree", "list", "--porcelain" })
  local list = {}
  if result.code ~= 0 then
    return list
  end
  local current
  for _, line in ipairs(vim.split(result.stdout or "", "\n")) do
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
-- list_branches()'s existing relative order within each group.
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

local function sanitize_worktree_name(branch)
  return (branch:gsub("/", "+"))
end

local function worktree_path_for(branch)
  local root = repo_root()
  if not root then
    return nil
  end
  return vim.fs.joinpath(root, ".claude", "worktrees", sanitize_worktree_name(branch))
end

local function open_worktree_tab(path)
  vim.cmd("tabnew")
  vim.cmd("tcd " .. vim.fn.fnameescape(path))
  vim.cmd("Alpha")
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

-- Yes/No confirm as a Telescope picker (replaces vim.ui.select) so it slots
-- into the same back-stack as everything else. "No" behaves like Esc.
local function confirm_picker(prompt, on_yes)
  pick_from(prompt, { "Yes", "No" }, {
    Yes = on_yes,
    No = menu_stack.pop_and_open,
  })
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

local function switch_branch(name)
  local result = git({ "switch", name })
  if result.code ~= 0 then
    notify_err("git switch failed", result)
    return
  end
  vim.notify("Switched to branch " .. name)
end

local function checkout_remote_tracking(name, remote)
  local result = git({ "switch", "-c", name, "--track", remote })
  if result.code ~= 0 then
    notify_err("git switch failed", result)
    return
  end
  vim.notify("Switched to branch " .. name)
end

local function create_and_switch_branch(name, base)
  local result = git({ "switch", "-c", name, base })
  if result.code ~= 0 then
    notify_err("git switch -c failed", result)
    return
  end
  vim.notify("Created and switched to branch " .. name)
end

local function ensure_worktrees_dir()
  local root = repo_root()
  if root then
    vim.fn.mkdir(vim.fs.joinpath(root, ".claude", "worktrees"), "p")
  end
end

local function create_worktree_new_branch(name, base)
  local path = worktree_path_for(name)
  if not path then
    vim.notify("Could not resolve repo root", vim.log.levels.ERROR)
    return
  end
  ensure_worktrees_dir()
  local result = git({ "worktree", "add", "-b", name, path, base })
  if result.code ~= 0 then
    notify_err("git worktree add failed", result)
    return
  end
  open_worktree_tab(path)
end

local function create_worktree_for_branch(entry)
  local path = worktree_path_for(entry.name)
  if not path then
    vim.notify("Could not resolve repo root", vim.log.levels.ERROR)
    return
  end
  ensure_worktrees_dir()
  local args
  if entry.is_local then
    args = { "worktree", "add", path, entry.name }
  else
    args = { "worktree", "add", "-b", entry.name, path, entry.remote }
  end
  local result = git(args)
  if result.code ~= 0 then
    notify_err("git worktree add failed", result)
    return
  end
  open_worktree_tab(path)
end

local function tabnr_for_cwd(path)
  local normalized = vim.fs.normalize(path)
  for _, tabnr in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.fs.normalize(vim.fn.getcwd(-1, tabnr)) == normalized then
      return tabnr
    end
  end
  return nil
end

local function delete_branch(entry)
  local result = git({ "branch", "-d", entry.name })
  if result.code == 0 then
    vim.notify("Deleted branch " .. entry.name)
    return true
  end
  return false
end

local function delete_branch_action()
  local open_list
  open_list = function()
    pick_entries_multi("Delete Branch", list_local_branches(), branch_entry_maker, function(selected)
      menu_stack.push(open_list)

      -- Single selection keeps the interactive force-delete prompt. Batch
      -- delete skips per-item prompts and reports which ones need a manual
      -- force-delete, same as the worktree removal flow.
      if #selected == 1 then
        local entry = selected[1]
        confirm_picker("Delete branch " .. entry.name .. "?", function()
          if delete_branch(entry) then
            return
          end
          menu_stack.push(open_list)
          confirm_picker(entry.name .. " is not fully merged. Force delete?", function()
            local force_result = git({ "branch", "-D", entry.name })
            if force_result.code ~= 0 then
              notify_err("git branch -D failed", force_result)
              return
            end
            vim.notify("Deleted branch " .. entry.name)
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
        for _, entry in ipairs(selected) do
          if not delete_branch(entry) then
            table.insert(failed, entry.name)
          end
        end
        if #failed > 0 then
          vim.notify(
            "Not fully merged, delete individually to force: " .. table.concat(failed, ", "),
            vim.log.levels.WARN
          )
        end
      end)
    end)
  end
  open_list()
end

local function remove_worktree(wt)
  local function finish()
    vim.notify("Removed worktree " .. wt.path)
    local tabnr = tabnr_for_cwd(wt.path)
    if tabnr and #vim.api.nvim_list_tabpages() > 1 then
      vim.cmd(tabnr .. "tabclose")
    end
  end
  local result = git({ "worktree", "remove", wt.path })
  if result.code == 0 then
    finish()
    return true
  end
  return false
end

local function remove_worktree_action()
  local open_list
  open_list = function()
    local worktrees = vim.tbl_filter(function(wt)
      return not wt.is_main
    end, list_worktrees_ordered())

    pick_entries_multi("Remove Worktree", worktrees, function(wt)
      local name = vim.fs.basename(wt.path)
      return { value = wt, display = name, ordinal = name }
    end, function(selected)
      menu_stack.push(open_list)

      -- Single selection keeps the interactive force-remove prompt. Batch
      -- removal skips per-item prompts (stacking a confirm per failure would
      -- be a mess) and just reports which ones need a manual force-remove.
      if #selected == 1 then
        local wt = selected[1]
        confirm_picker("Remove worktree at " .. wt.path .. "?", function()
          if remove_worktree(wt) then
            return
          end
          menu_stack.push(open_list)
          confirm_picker(wt.path .. " has changes. Force remove?", function()
            local force_result = git({ "worktree", "remove", "--force", wt.path })
            if force_result.code ~= 0 then
              notify_err("git worktree remove failed", force_result)
              return
            end
            vim.notify("Removed worktree " .. wt.path)
            local tabnr = tabnr_for_cwd(wt.path)
            if tabnr and #vim.api.nvim_list_tabpages() > 1 then
              vim.cmd(tabnr .. "tabclose")
            end
          end)
        end)
        return
      end

      local names = {}
      for _, wt in ipairs(selected) do
        table.insert(names, vim.fs.basename(wt.path))
      end
      confirm_picker("Remove " .. #selected .. " worktrees: " .. table.concat(names, ", ") .. "?", function()
        local failed = {}
        for _, wt in ipairs(selected) do
          if not remove_worktree(wt) then
            table.insert(failed, vim.fs.basename(wt.path))
          end
        end
        if #failed > 0 then
          vim.notify(
            "Has changes, remove individually to force: " .. table.concat(failed, ", "),
            vim.log.levels.WARN
          )
        end
      end)
    end)
  end
  open_list()
end

local function rename_branch_action()
  local open_list
  open_list = function()
    pick_entry("Rename Branch", list_local_branches(), branch_entry_maker, function(entry)
      menu_stack.push(open_list)
      prompt_text("New name for " .. entry.name, entry.name, function(input)
        local new_name = input:gsub(" ", "-")
        local result = git({ "branch", "-m", entry.name, new_name })
        if result.code ~= 0 then
          notify_err("git branch -m failed", result)
          return
        end
        vim.notify("Renamed branch " .. entry.name .. " to " .. new_name)
      end)
    end)
  end
  open_list()
end

local function merge_branch_action()
  pick_entry("Merge into " .. current_head(), list_branches(), branch_entry_maker, function(entry)
    local source = entry.is_local and entry.name or entry.remote
    local result = git({ "merge", source })
    if result.code == 0 then
      vim.notify("Merged " .. source .. " into " .. current_head())
      return
    end
    local unmerged = git_lines({ "diff", "--name-only", "--diff-filter=U" })
    if #unmerged > 0 then
      vim.notify("Merge conflicts in " .. #unmerged .. " file(s); opening changes panel", vim.log.levels.WARN)
      require("diffbandit").commit_panel()
      return
    end
    notify_err("git merge failed", result)
  end)
end

local function push_current()
  local branch = current_head()
  local has_upstream = git({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" }).code == 0
  local args = has_upstream and { "push" } or { "push", "-u", "origin", branch }
  local result = git(args)
  if result.code ~= 0 then
    notify_err("git push failed", result)
    return
  end
  vim.notify("Pushed " .. branch)
end

local function pull_current()
  local result = git({ "pull" })
  if result.code ~= 0 then
    notify_err("git pull failed", result)
    return
  end
  vim.notify("Pulled " .. current_head())
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
        sorter = conf.generic_sorter({}),
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

handle_new = function(mode, name)
  name = name:gsub(" ", "-")
  local function reopen()
    open_picker(mode)
  end
  menu_stack.push(reopen)
  if mode == "branch" then
    prompt_base_ref(function(base)
      create_and_switch_branch(name, base)
    end)
  else
    prompt_base_ref(function(base)
      create_worktree_new_branch(name, base)
    end)
  end
end

local function link_worktree_hl()
  vim.api.nvim_set_hl(0, WORKTREE_HL, worktree.HL)
end

local open_branch_submenu, open_worktree_submenu, pick_mode

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

local worktree_submenu_order = { "Switch/Create", "Remove" }
local worktree_submenu_actions = {
  ["Switch/Create"] = function()
    menu_stack.push(open_worktree_submenu)
    open_picker("worktree")
  end,
  ["Remove"] = function()
    menu_stack.push(open_worktree_submenu)
    remove_worktree_action()
  end,
}

open_worktree_submenu = function()
  pick_from("Worktree", worktree_submenu_order, worktree_submenu_actions)
end

local mode_order = { "Branch", "Worktree", "Push", "Pull" }
local mode_actions = {
  ["Branch"] = function()
    menu_stack.push(pick_mode)
    open_branch_submenu()
  end,
  ["Worktree"] = function()
    menu_stack.push(pick_mode)
    open_worktree_submenu()
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

  vim.keymap.set("n", "<M-b>b", function()
    menu_stack.reset()
    open_picker("branch")
  end, { desc = "Switch/create git branch" })

  vim.keymap.set("n", "<M-b>w", function()
    menu_stack.reset()
    open_picker("worktree")
  end, { desc = "Switch/create git worktree" })

  vim.keymap.set("n", "<M-b>p", pull_current, { desc = "Git pull" })
  vim.keymap.set("n", "<M-b>P", push_current, { desc = "Git push" })
end

return M
