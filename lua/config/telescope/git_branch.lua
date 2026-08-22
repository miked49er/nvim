-- <M-b> git branch/worktree menu: pick "Branch" or "Worktree", then fuzzy
-- search all local+remote branches. Selecting an existing branch/worktree
-- switches to it; typing a name that matches nothing creates it.
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local themes = require("telescope.themes")

local M = {}

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

local function list_worktrees()
  local result = git({ "worktree", "list", "--porcelain" })
  local map = {}
  if result.code ~= 0 then
    return map
  end
  local path
  for _, line in ipairs(vim.split(result.stdout or "", "\n")) do
    local wt_path = line:match("^worktree (.+)$")
    local branch = line:match("^branch refs/heads/(.+)$")
    if wt_path then
      path = wt_path
    elseif branch and path then
      map[branch] = path
    elseif line == "" then
      path = nil
    end
  end
  return map
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
        attach_mappings = function(prompt_bufnr)
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

local function handle_new(mode, name)
  name = name:gsub(" ", "-")
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

local function open_picker(mode)
  local worktree_map = mode == "worktree" and list_worktrees() or nil
  local entries = list_branches()

  pickers
      .new({}, {
        prompt_title = mode == "branch" and "Switch/Create Branch" or "Switch/Create Worktree",
        finder = finders.new_table({
          results = entries,
          entry_maker = function(entry)
            local made = branch_entry_maker(entry)
            if worktree_map and worktree_map[entry.name] then
              made.display = made.display .. "  (" .. worktree_map[entry.name] .. ")"
            end
            return made
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
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
          return true
        end,
      })
      :find()
end

local function pick_mode(callback)
  pickers
      .new(themes.get_dropdown({}), {
        prompt_title = "Git",
        finder = finders.new_table({ results = { "Branch", "Worktree" } }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if selection then
              callback(selection[1])
            end
          end)
          return true
        end,
      })
      :find()
end

M.setup = function()
  vim.keymap.set("n", "<M-b>", function()
    pick_mode(function(choice)
      if choice == "Branch" then
        open_picker("branch")
      elseif choice == "Worktree" then
        open_picker("worktree")
      end
    end)
  end, { desc = "Git branch/worktree menu" })

  vim.keymap.set("n", "<M-b>b", function()
    open_picker("branch")
  end, { desc = "Switch/create git branch" })

  vim.keymap.set("n", "<M-b>w", function()
    open_picker("worktree")
  end, { desc = "Switch/create git worktree" })
end

return M
