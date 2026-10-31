-- Telescope/vim.ui adapter for config.git.worktree.remove: the policy choice
-- is a vim.ui.select; the per-worktree confirm is a scrollable list of the
-- worktree's changes with a diff/file previewer.
local remove = require("config.git.worktree.remove")
local repo = require("config.git.repo")

local M = {}

local FORCE_ALL = "Force remove all"
local ONE_BY_ONE = "Review one by one"
local SKIP = "Skip"
local FORCE_ONE = "Force remove"

function M.choose_policy(dirty, cb)
  local labels = {}
  for _, info in ipairs(dirty) do
    local summary = remove.summarize_entries(info.entries)
    table.insert(labels, vim.fs.basename(info.wt.path) .. (summary ~= "" and (" (" .. summary .. ")") or ""))
  end
  vim.ui.select({ FORCE_ALL, ONE_BY_ONE, SKIP }, {
    prompt = #dirty .. " worktrees have changes: " .. table.concat(labels, "; "),
  }, function(choice)
    cb(({
      [FORCE_ALL] = remove.POLICY.FORCE_ALL,
      [ONE_BY_ONE] = remove.POLICY.REVIEW,
      [SKIP] = remove.POLICY.SKIP,
    })[choice])
  end)
end

-- <CR> confirms the force removal; <C-s> skips (only when opts.allow_skip);
-- <Esc>/<C-c> cancels. cb(RESULT.FORCE | RESULT.SKIP | nil) runs once.
function M.confirm(wt, entries, opts, cb)
  opts = opts or {}
  if #entries == 0 then
    local items = opts.allow_skip and { FORCE_ONE, SKIP } or { FORCE_ONE }
    return vim.ui.select(items, {
      prompt = wt.path .. " has no listed changes. Force remove?",
    }, function(pick)
      cb(pick == FORCE_ONE and remove.RESULT.FORCE or (pick and remove.RESULT.SKIP) or nil)
    end)
  end
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local previewers = require("telescope.previewers")
  local finished = false
  local function resolve(result)
    if finished then
      return
    end
    finished = true
    cb(result)
  end
  local hint = opts.allow_skip and "<CR> force remove, <C-s> skip, <Esc> cancel" or "<CR> force remove, <Esc> cancel"
  pickers
      .new({ layout_strategy = "horizontal", layout_config = { width = 0.9, height = 0.8 } }, {
        prompt_title = "Force remove " .. vim.fs.basename(wt.path) .. "? " .. hint,
        finder = finders.new_table({
          results = entries,
          entry_maker = function(e)
            return {
              value = e,
              display = string.format("%-2s %s", e.status, e.path),
              ordinal = e.status .. " " .. e.path,
              path = vim.fs.joinpath(wt.path, e.path),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = previewers.new_buffer_previewer({
          title = "Change",
          define_preview = function(self, entry)
            local e = entry.value
            if e.status == remove.UNTRACKED then
              local ok, content = pcall(vim.fn.readfile, entry.path)
              vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false,
                ok and content or { "(unreadable or directory)" })
              vim.bo[self.state.bufnr].filetype = ""
              return
            end
            -- Async so scrolling the list never blocks on git.
            local bufnr = self.state.bufnr
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "(loading diff...)" })
            repo.open_async(wt.path, function(h)
              if not h then
                return
              end
              h:run_async({ "diff", "HEAD", "--", e.path }, function(r)
                if not vim.api.nvim_buf_is_valid(bufnr) then
                  return
                end
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(r.stdout or "", "\n"))
                vim.bo[bufnr].filetype = "diff"
              end)
            end)
          end,
        }),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            resolve(remove.RESULT.FORCE)
          end)
          if opts.allow_skip then
            map({ "i", "n" }, "<C-s>", function()
              actions.close(prompt_bufnr)
              resolve(remove.RESULT.SKIP)
            end)
          end
          for _, key in ipairs({ "<Esc>", "<C-c>" }) do
            map({ "i", "n" }, key, function()
              actions.close(prompt_bufnr)
              resolve(nil)
            end)
          end
          return true
        end,
      })
      :find()
end

return M
