-- Worktree identity: the single owner of the layout convention. Worktrees
-- live at <main_repo_root>/.claude/worktrees/<sanitized branch name>.
-- Also answers key / label / branch for a working directory, so tabs,
-- terminals, tabline and the picker agree. Presentation (glyph, colors)
-- lives in config.ui.palette. Path matching is cheap and spawns no git, so
-- it is safe on every statusline/tabline redraw.
local M = {}

local BS = string.char(92)
local SEP = "[" .. BS .. "/]"
local SEGMENTS = { ".claude", "worktrees" }

function M.sanitize(branch)
  return (branch:gsub("/", "+"))
end

function M.base_dir(main_root)
  return vim.fs.joinpath(main_root, unpack(SEGMENTS))
end

--- Name -> path: where a worktree for `branch` lives.
function M.path_for(main_root, branch)
  return vim.fs.joinpath(M.base_dir(main_root), M.sanitize(branch))
end

--- Path -> name: the worktree folder name for any path inside the layout,
--- or nil when the path is outside it.
function M.name_for_path(path)
  return path:match("%.claude" .. SEP .. "worktrees" .. SEP .. "([^" .. BS .. "/]+)")
end

--- The folder name when it differs from the checked-out branch (else nil).
--- The picker shows it as a "name:" prefix.
function M.name_differs(path, branch)
  local name = vim.fs.basename(path)
  if name ~= branch then
    return name
  end
  return nil
end

--- Normalized root of the checkout containing `dir` (the dir itself outside a repo).
function M.key_for_dir(dir)
  local root = vim.fs.root(dir, ".git") or dir
  return (vim.fs.normalize(root):gsub("/+$", ""))
end

function M.branch_for_dir(dir)
  return require("config.git.repo").branch_for_dir(dir)
end

--- Human-readable name: branch, else layout folder name, else the dir.
function M.label_for_dir(dir)
  return M.branch_for_dir(dir) or M.name_for_path(dir) or dir
end

return M
