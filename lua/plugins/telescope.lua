return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
      "nvim-telescope/telescope-ui-select.nvim",
    },
    config = function()
      require("telescope").setup({
        pickers = {
          find_files = {
            theme = "ivy",
            hidden = true,
            file_ignore_patterns = {
              "%.claude[\\/]worktrees[\\/]",
              "%.git[\\/]",
              "node_modules[\\/]",
              "dist[\\/]",
              "build[\\/]",
              "target[\\/]",
            },
          },
        },
        extensions = {
          fzf = {
            case_mode = "ignore_case",
          },
          ["ui-select"] = {
            require("telescope.themes").get_cursor({}),
          },
        },
      })

      require("telescope").load_extension("fzf")
      require("telescope").load_extension("ui-select")

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
      vim.keymap.set("n", "<leader>fN", function()
        local dir = vim.fn.input("Search in dir: ", vim.fn.getcwd() .. "/", "dir")
        if dir == "" then
          return
        end
        builtin.find_files({
          cwd = dir,
          hidden = true,
          no_ignore = true,
          file_ignore_patterns = {},
        })
      end)

      require("config.telescope.multigrep").setup()
      require("config.telescope.git_branch").setup()
    end,
  },
}
