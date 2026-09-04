return {
  {
    'echasnovski/mini.nvim',
    enabled = true,
    config = function()
      local statusline = require 'mini.statusline'
      local worktree = require 'config.worktree'
      local git_busy = require 'config.git_busy'

      -- Solid-background look, one group per palette slot so the statusline
      -- indicator matches whatever color the tabline assigned that
      -- worktree. Doesn't collide with MiniStatuslineModeOther (used for
      -- Terminal mode, linked to IncSearch).
      local function worktree_hl_group(slot)
        return 'MiniStatuslineWorktree' .. slot
      end

      local function link_worktree_hl()
        for slot = 1, worktree.PALETTE_SIZE do
          local color = worktree.color_for_slot(slot)
          vim.api.nvim_set_hl(0, worktree_hl_group(slot), { fg = worktree.fg_for_bg(color), bg = color, bold = true })
        end
      end
      link_worktree_hl()
      vim.api.nvim_create_autocmd('ColorScheme', {
        desc = 'Re-derive statusline worktree highlights for the new colorscheme',
        callback = link_worktree_hl,
      })

      local function worktree_section()
        local name = worktree.label_for_cwd(vim.fn.getcwd(0))
        if not name then
          return '', 'MiniStatuslineDevinfo'
        end
        return worktree.ICON .. ' ' .. name, worktree_hl_group(worktree.slot_for(name))
      end

      -- Branch requires a file read (unlike the worktree label's plain
      -- string match), so it's cached per-cwd and only refreshed when the
      -- cwd changes or focus returns to nvim (catches branch switches made
      -- in another terminal without spawning git to poll for them).
      vim.api.nvim_set_hl(0, 'MiniStatuslineBranch', { fg = 'MediumSpringGreen', bold = true })
      local branch_cache = {}
      local function refresh_branch_cache()
        branch_cache = {}
      end
      vim.api.nvim_create_autocmd({ 'DirChanged', 'FocusGained' }, {
        desc = 'Invalidate cached statusline branch name',
        callback = refresh_branch_cache,
      })

      local function branch_section()
        local cwd = vim.fn.getcwd(0)
        local name = branch_cache[cwd]
        if name == nil then
          name = worktree.branch_for_cwd(cwd) or false
          branch_cache[cwd] = name
        end
        return name and (' ' .. name) or ''
      end

      -- Always relative to cwd (tab's repo/worktree root, via `tcd`) instead
      -- of mini.statusline's default of full path when window isn't truncated.
      local function filename_section()
        if vim.bo.buftype == 'terminal' then
          return '%t'
        end
        return '%f%m%r'
      end

      local function busy_section()
        local label = git_busy.label()
        return label and ('⏳ ' .. label) or ''
      end

      local function active_content()
        local mode, mode_hl = statusline.section_mode { trunc_width = 120 }
        local worktree, worktree_hl = worktree_section()
        local branch         = branch_section()
        local busy           = busy_section()
        local git           = statusline.section_git { trunc_width = 40 }
        local diff          = statusline.section_diff { trunc_width = 75 }
        local diagnostics   = statusline.section_diagnostics { trunc_width = 75 }
        local lsp           = statusline.section_lsp { trunc_width = 75 }
        local filename      = filename_section()
        local fileinfo      = statusline.section_fileinfo { trunc_width = 120 }
        local location      = statusline.section_location { trunc_width = 75 }
        local search        = statusline.section_searchcount { trunc_width = 75 }

        return statusline.combine_groups {
          { hl = mode_hl,                    strings = { mode } },
          { hl = worktree_hl,                 strings = { worktree } },
          { hl = 'MiniStatuslineBranch',       strings = { branch } },
          { hl = 'MiniStatuslineDevinfo',     strings = { busy } },
          { hl = 'MiniStatuslineDevinfo',     strings = { git, diff, diagnostics, lsp } },
          '%<',
          { hl = 'MiniStatuslineFilename',    strings = { filename } },
          '%=',
          { hl = 'MiniStatuslineFileinfo',    strings = { fileinfo } },
          { hl = mode_hl,                     strings = { search, location } },
        }
      end

      statusline.setup {
        use_icons = true,
        content = { active = active_content },
      }
    end
  },
}
