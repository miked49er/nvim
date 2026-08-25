return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config = function()
      require("telescope").setup({
        pickers = {
          find_files = {
            theme = "ivy",
            hidden = true,
            file_ignore_patterns = { "%.claude[\\/]worktrees[\\/]" },
          },
        },
        extensions = {
          fzf = {
            case_mode = "ignore_case",
          },
        },
      })

      require("telescope").load_extension("fzf")

      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>fh", builtin.help_tags)
      vim.keymap.set("n", "<leader>fd", function()
        builtin.find_files({ cwd = vim.fn.getcwd() })
      end)
      vim.keymap.set("n", "<leader>en", function()
        local opts = require("telescope.themes").get_dropdown({
          cwd = vim.fn.stdpath("config"),
        })
        builtin.find_files(opts)
      end)
      vim.keymap.set("n", "<leader>ep", function()
        builtin.find_files({
          cwd = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy"),
        })
      end)

      require("config.telescope.multigrep").setup()
      require("config.telescope.git_branch").setup()
    end,
  },
}
