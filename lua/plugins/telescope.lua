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
      require("config.git.branch.picker").setup()
    end,
  },
}
