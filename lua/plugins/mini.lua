return {
  {
    'echasnovski/mini.nvim',
    enabled = true,
    config = function()
      local statusline = require 'mini.statusline'
      local worktree = require 'config.worktree'

      -- Named color (not a hex pulled from one colorscheme) so it stays
      -- electric blue across theme changes, matching the tabline's worktree
      -- highlight, and doesn't collide with MiniStatuslineModeOther (used
      -- for Terminal mode, linked to IncSearch).
      vim.api.nvim_set_hl(0, 'MiniStatuslineWorktree', { fg = 'black', bg = 'DeepSkyBlue', bold = true })

      local function worktree_section()
        local name = worktree.label_for_cwd(vim.fn.getcwd(0))
        return name and ('' .. name .. '') or ''
      end

      -- Always relative to cwd (tab's repo/worktree root, via `tcd`) instead
      -- of mini.statusline's default of full path when window isn't truncated.
      local function filename_section()
        if vim.bo.buftype == 'terminal' then
          return '%t'
        end
        return '%f%m%r'
      end

      local function active_content()
        local mode, mode_hl = statusline.section_mode { trunc_width = 120 }
        local worktree      = worktree_section()
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
          { hl = 'MiniStatuslineWorktree',    strings = { worktree } },
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
